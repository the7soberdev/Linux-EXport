-- minigame: geometry classifier + predictive reel solver
--
-- Four reel shapes cover essentially every fishing game:
--   linear   - static zone, marker slides along the track
--   reverse  - static marker, zone slides along the track
--   fill     - a bar grows toward a marked target
--   radial   - marker orbits a centre point
-- plus `spam`, the fallback when the UI cannot be classified.
--
-- Every frame the marker's velocity is estimated from the last two samples and
-- the press is aimed at where it *will* be after the input latency, not where
-- it is now. That single change is what separates a solver from a spammer.
local env = __require("env")
local util = __require("util")
local config = __require("config")

local M = {
	active = false,
	gui = nil,
	track = nil,
	marker = nil,
	zone = nil,
	geometry = "none",
	lastPositions = setmetatable({}, { __mode = "k" }),
	velocity = Vector2(0, 0),
	lastSample = 0,
	samples = 0,
	hits = 0,
	misses = 0,
	lead = 0.08,
	tolerance = 0.12,
}

local function visible(obj)
	return obj
		and obj:IsA("GuiObject")
		and obj.Visible
		and obj.AbsoluteSize.X > 1
		and obj.AbsoluteSize.Y > 1
end

local function area(obj)
	return obj.AbsoluteSize.X * obj.AbsoluteSize.Y
end

local function centre(obj)
	return obj.AbsolutePosition + obj.AbsoluteSize / 2
end

local function horizontal(track)
	return track.AbsoluteSize.X >= track.AbsoluteSize.Y
end

--------------------------------------------------------------------------------
-- detection
--------------------------------------------------------------------------------

function M.findGui()
	local playerGui = env.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return nil end

	local best, bestArea = nil, 0
	for _, gui in ipairs(playerGui:GetChildren()) do
		if gui:IsA("ScreenGui") and gui.Enabled and util.matches(gui.Name, config.patterns.minigame) then
			for _, child in ipairs(gui:GetDescendants()) do
				if visible(child) and area(child) > 4000 then
					if area(child) > bestArea then
						best, bestArea = gui, area(child)
					end
					break
				end
			end
		end
	end
	return best
end

local function pickTrack(gui)
	local track, trackArea = nil, 0
	for _, child in ipairs(gui:GetDescendants()) do
		if visible(child) and area(child) > trackArea then
			track, trackArea = child, area(child)
		end
	end
	if track and trackArea >= 4000 then return track end
	return nil
end

--------------------------------------------------------------------------------
-- classification
--------------------------------------------------------------------------------

local function classify(track, mover, still)
	if not mover then return "unknown" end

	local trackCentre = centre(track)
	local moverCentre = centre(mover)
	local offset = moverCentre - trackCentre
	local radius = offset.Magnitude
	local axis = horizontal(track) and "x" or "y"

	-- Orbiting marker: constant distance from the track centre while the angle
	-- keeps changing.
	local previousAngle = M.lastAngle
	local angle = math.atan2(offset.Y, offset.X)
	M.lastAngle = angle
	if previousAngle and radius > 10 then
		local delta = math.abs(angle - previousAngle)
		if delta > 1e-3 and delta < 1 then
			local previousRadius = M.lastRadius or radius
			if math.abs(radius - previousRadius) < radius * 0.25 then
				M.lastRadius = radius
				return "radial"
			end
		end
	end
	M.lastRadius = radius

	if not still then return "unknown" end

	-- Fill bar: the mover is a child whose Size changes while its Position is
	-- pinned to one edge of the track.
	local sizeChange = M.lastSize and (mover.AbsoluteSize - M.lastSize).Magnitude or 0
	M.lastSize = mover.AbsoluteSize
	if sizeChange > 0.5 then return "fill" end

	local stillCentre = centre(still)
	if still == mover then return "unknown" end

	-- Which one actually travels along the long axis?
	local function travel(obj)
		local previous = M.lastPositions[obj]
		if not previous then return 0 end
		local current = obj.AbsolutePosition
		local delta = current - previous
		return math.abs(axis == "x" and delta.X or delta.Y)
	end

	local moverTravel = travel(mover)
	local stillTravel = travel(still)

	if stillTravel > moverTravel * 1.5 then
		M.swap = true
		return "reverse"
	end

	if moverTravel > 0.05 then
		M.swap = false
		return "linear"
	end

	return "unknown"
end

function M.analyze(gui)
	local track = pickTrack(gui)
	if not track then
		M.geometry = "none"
		return false
	end
	M.track = track

	local movers, stills = {}, {}

	for _, child in ipairs(track:GetDescendants()) do
		if visible(child) and child ~= track then
			local previous = M.lastPositions[child]
			local current = child.AbsolutePosition
			if previous then
				local delta = (current - previous).Magnitude
				if delta > 0.4 then
					movers[#movers + 1] = { object = child, delta = delta }
				elseif area(child) < area(track) * 0.9 then
					stills[#stills + 1] = { object = child, area = area(child) }
				end
			end
			M.lastPositions[child] = current
		end
	end

	table.sort(movers, function(a, b) return a.delta > b.delta end)
	table.sort(stills, function(a, b) return a.area > b.area end)

	local mover = movers[1] and movers[1].object
	local still = stills[1] and stills[1].object

	if mover then
		local previous = M.lastPosition or centre(mover)
		local now = centre(mover)
		local deltaTime = math.max(util.now() - (M.lastSample or util.now()), 0.001)
		local instant = (now - previous) / deltaTime
		M.velocity = M.velocity * 0.6 + instant * 0.4
		M.lastPosition = now
		M.lastSample = util.now()
	end

	M.marker = mover
	M.zone = still

	if mover then
		M.geometry = classify(track, mover, still)
	else
		M.geometry = "unknown"
	end

	M.samples = M.samples + 1
	return M.geometry ~= "none"
end

--------------------------------------------------------------------------------
-- press helpers
--------------------------------------------------------------------------------

local function pressDown()
	if env.has.mouse1 then
		pcall(mouse1press)
	else
		pcall(function() env.VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0) end)
	end
end

local function pressUp()
	if env.has.mouse1 then
		pcall(mouse1release)
	else
		pcall(function() env.VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0) end)
	end
end

local function hold(duration)
	pressDown()
	task.wait(duration)
	pressUp()
end

--------------------------------------------------------------------------------
-- solving
--------------------------------------------------------------------------------

local function fraction(position, track, alongX)
	if alongX then
		return (position.X - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1)
	end
	return (position.Y - track.AbsolutePosition.Y) / math.max(track.AbsoluteSize.Y, 1)
end

local function solveLinear()
	local track, marker, zone = M.track, M.marker, M.zone
	if not (track and marker and zone) then return false end

	local alongX = horizontal(track)
	local predicted = centre(marker) + M.velocity * M.lead

	local low, high
	if M.swap then
		local zoneCentre = centre(zone)
		local half = (alongX and marker.AbsoluteSize.X or marker.AbsoluteSize.Y) / 2
		local value = alongX and zoneCentre.X or zoneCentre.Y
		low, high = value - half, value + half
	else
		local zoneStart = alongX and zone.AbsolutePosition.X or zone.AbsolutePosition.Y
		local zoneSize = alongX and zone.AbsoluteSize.X or zone.AbsoluteSize.Y
		low, high = zoneStart, zoneStart + zoneSize
	end

	local point = alongX and predicted.X or predicted.Y
	return point >= low and point <= high
end

local function solveFill()
	local marker = M.marker
	local track = M.track
	if not (marker and track) then return false end
	local ratio = marker.AbsoluteSize.Magnitude / math.max(track.AbsoluteSize.Magnitude, 1)
	return ratio >= 0.45 and ratio <= 0.95
end

local function solveRadial()
	local track, marker, zone = M.track, M.marker, M.zone
	if not (track and marker) then return false end

	local trackCentre = centre(track)
	local offset = centre(marker) - trackCentre
	local angle = math.atan2(offset.Y, offset.X)

	local target = M.lastTargetAngle
	if zone then
		local zoneOffset = centre(zone) - trackCentre
		target = math.atan2(zoneOffset.Y, zoneOffset.X)
		M.lastTargetAngle = target
	end
	if not target then return false end

	local delta = math.abs(((angle - target + math.pi) % (2 * math.pi)) - math.pi)
	return delta < M.tolerance * math.pi
end

function M.inWindow()
	local geometry = M.geometry
	if geometry == "linear" or geometry == "reverse" then
		return solveLinear()
	elseif geometry == "fill" then
		return solveFill()
	elseif geometry == "radial" then
		return solveRadial()
	end
	return false
end

--------------------------------------------------------------------------------
-- tick
--------------------------------------------------------------------------------

function M.tick(solve)
	local gui = M.findGui()
	if not gui then
		M.active = false
		M.gui = nil
		M.track, M.marker, M.zone = nil, nil, nil
		M.geometry = "none"
		M.samples = 0
		M.velocity = Vector2(0, 0)
		M.lastPosition = nil
		return false
	end

	if gui ~= M.gui then
		M.gui = gui
		M.samples = 0
		M.lastPositions = setmetatable({}, { __mode = "k" })
		M.lastPosition, M.lastSample = nil, nil
		M.velocity = Vector2(0, 0)
		M.analyze(gui)
	end

	M.active = true
	if solve == false then return true end

	if M.samples < 45 then
		M.analyze(gui)
	end

	local mode = config.get("reelMode")
	if mode == "Remote" then
		local remote = __require("scanner").remotes.reel
		if remote then
			pcall(function() remote:FireServer() end)
			M.hits = M.hits + 1
			return true
		end
	end

	if config.get("instantReel") == false then
		hold(0.05)
		task.wait(0.02)
		M.hits = M.hits + 1
		return true
	end

	if M.geometry == "none" or M.geometry == "unknown" then
		hold(0.05)
		task.wait(0.02)
		M.hits = M.hits + 1
		return true
	end

	-- Input frequency is itself a fingerprint. A real player does not press on
	-- every single frame; a short, random dead beat removes that regularity.
	if math.random() < 0.06 then
		task.wait(0.012 + math.random() * 0.03)
		return true
	end

	if M.inWindow() then
		hold(0.05 + math.random() * 0.025)
		M.hits = M.hits + 1
	else
		hold(0.012 + math.random() * 0.01)
	end
	return true
end

function M.status()
	return string.format("%s %s m%d z%d", M.geometry, M.active and "on" or "off",
		M.marker and 1 or 0, M.zone and 1 or 0)
end

function M.confidence()
	local known = { linear = 0.9, reverse = 0.9, fill = 0.8, radial = 0.7, unknown = 0.35, none = 0.1 }
	return known[M.geometry] or 0.35
end

return M
