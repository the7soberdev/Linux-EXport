-- stealth: make automated behaviour statistically boring
--
-- Detection is mostly statistics and reports, not injection. This module
-- attacks both:
--
--   variance     every interval drawn from a distribution, never a constant
--   presence     stops while a player can actually see you, resumes when clear
--   pacing       rolling rate cap, work/break cycles, daily session shape
--   imperfection deliberate missed catches so the success rate is not 100%
--   teleport     refuses to blink inside someone's line of sight
--   fingerprint  per-session constants drawn at boot, so two sessions differ
--   panic        one key wipes the surface: features off, UI hidden, ESP gone
local env = __require("env")
local util = __require("util")
local config = __require("config")

local M = {
	active = true,
	breaks = 0,
	lastCatch = 0,
	catches = {},
	sessionStart = util.now(),
	breakUntil = 0,
	blockedReason = nil,
	blockedBy = nil,
	panic = false,
	visibleToPlayer = false,
	proximity = {},
}

-- Per-session fingerprint. Drawn once at load, so no two runs of the hub look
-- identical in timing even with the same settings.
M.fingerprint = {
	castScale = 0.85 + math.random() * 0.4,
	reelLeadScale = 0.8 + math.random() * 0.5,
	slipBias = 0.7 + math.random() * 0.6,
	paceScale = 0.9 + math.random() * 0.25,
}

--------------------------------------------------------------------------------
-- distributions
--------------------------------------------------------------------------------

-- Jittered value with a soft lower bound. The sum of two uniforms is a cheap
-- triangular distribution: most draws land near the middle, few at the edges.
function M.jitter(base, spread)
	spread = spread or 0.25
	if not config.get("humanize") then return base end
	local wobble = (math.random() + math.random() - 1) * spread
	return math.max(base * (1 + wobble), 0.02)
end

function M.pause()
	local base = config.get("humanize") and math.random(120, 900) / 1000 or 0
	if base > 0 then task.wait(base) end
	return base
end

--------------------------------------------------------------------------------
-- presence
--------------------------------------------------------------------------------

local function rootOf(player)
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function lineOfSight(fromPart, toPart)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {
		env.LocalPlayer.Character,
		toPart.Parent,
	}
	local result = workspace:Raycast(fromPart.Position, toPart.Position - fromPart.Position, params)
	return result == nil
end

function M.scanPresence()
	local myRoot = rootOf(env.LocalPlayer)
	if not myRoot then return false, nil end

	local radius = config.get("proximityRadius")
	local nearestPlayer, nearestDistance = nil, math.huge
	local visible = false

	for _, player in ipairs(env.Players:GetPlayers()) do
		if player ~= env.LocalPlayer then
			local other = rootOf(player)
			if other then
				local distance = (other.Position - myRoot.Position).Magnitude
				if distance <= radius then
					M.proximity[player] = distance
					if distance < nearestDistance then
						nearestPlayer, nearestDistance = player, distance
					end
					if not visible and distance < radius * 0.8 then
						local ok, line = pcall(lineOfSight, myRoot, other)
						if ok and line then visible = true end
					end
				else
					M.proximity[player] = nil
				end
			end
		end
	end

	M.visibleToPlayer = visible
	M.nearest = nearestPlayer
	M.nearestDistance = nearestDistance < math.huge and nearestDistance or nil
	return visible, nearestPlayer
end

--------------------------------------------------------------------------------
-- rate limiting
--------------------------------------------------------------------------------

local function pruneCatches(now)
	while #M.catches > 0 and now - M.catches[1] > 60 do
		table.remove(M.catches, 1)
	end
end

function M.rateLimited()
	local now = util.now()
	pruneCatches(now)
	local cap = math.floor(config.get("rateCap") * M.fingerprint.paceScale)
	return #M.catches >= cap, #M.catches, cap
end

function M.noteCatch()
	local now = util.now()
	M.catches[#M.catches + 1] = now
	M.lastCatch = now
	pruneCatches(now)
end

-- Deliberate slip. A bot that lands every single catch at the same interval is
-- a beacon; a 5-10% failure rate is what a person actually looks like.
function M.shouldSlip()
	local chance = config.get("imperfection") * M.fingerprint.slipBias
	if chance <= 0 then return false end
	return math.random() < chance
end

--------------------------------------------------------------------------------
-- session shape
--------------------------------------------------------------------------------

local function sessionElapsedMinutes()
	return (util.now() - M.sessionStart) / 60
end

function M.updateSession(now)
	if M.breakUntil > 0 and now >= M.breakUntil then
		M.breakUntil = 0
		M.sessionStart = now
	end

	if M.breakUntil == 0 then
		local length = config.get("sessionMinutes")
		if length > 0 and sessionElapsedMinutes() >= length * (0.9 + math.random() * 0.25) then
			local breakLength = config.get("breakMinutes")
			M.breakUntil = now + breakLength * 60 * (0.7 + math.random() * 0.8)
			M.breaks = M.breaks + 1
			env.log("stealth: taking a %d minute break", breakLength)
		end
	end
end

--------------------------------------------------------------------------------
-- gate
--------------------------------------------------------------------------------

function M.blocked()
	M.blockedReason = nil
	M.blockedBy = nil

	if M.panic then
		M.blockedReason = "panic"
		return true
	end
	if not config.get("stealth") then return false end

	local now = util.now()
	M.updateSession(now)

	if M.breakUntil > 0 then
		M.blockedReason = "break"
		return true
	end

	local limited = M.rateLimited()
	if limited then
		M.blockedReason = "rate"
		return true
	end

	if config.get("pauseOnPlayers") then
		local visible, player = M.scanPresence()
		if visible and player then
			M.blockedReason = "seen"
			M.blockedBy = player.Name
			return true
		end
	end

	return false
end

function M.teleportAllowed(target)
	if not config.get("stealth") or not config.get("teleportGuard") then return true end
	local myRoot = rootOf(env.LocalPlayer)
	if not myRoot then return true end
	if not target then return true end

	local range = config.get("proximityRadius")
	for _, player in ipairs(env.Players:GetPlayers()) do
		if player ~= env.LocalPlayer then
			local other = rootOf(player)
			if other then
				local destination = Vector3.new(target.X, target.Y, target.Z)
				if (other.Position - destination).Magnitude < range then
					return false, player.Name
				end
			end
		end
	end
	return true
end

--------------------------------------------------------------------------------
-- panic
--------------------------------------------------------------------------------

function M.engagePanic()
	M.panic = true
	config.set("autoCast", false)
	config.set("autoReel", false)
	config.set("autoSell", false)
	config.set("autoAppraise", false)
	config.set("autoQuest", false)
	config.set("esp", false)
	config.set("fly", false)
	config.set("noclip", false)
	pcall(function() __require("motion").stopFly() end)
	pcall(function() __require("esp").clear() end)
	pcall(function() __require("ui").hide() end)
	pcall(function() __require("ui").notify("panic - everything off", "bad") end)
end

function M.releasePanic()
	M.panic = false
end

function M.status()
	if M.panic then return "PANIC" end
	if not config.get("stealth") then return "off" end
	if M.breakUntil > 0 then
		return string.format("break %ds", math.max(0, math.floor(M.breakUntil - util.now())))
	end
	local _, count, cap = M.rateLimited()
	if M.blockedReason == "seen" then return "hidden:" .. (M.blockedBy or "?") end
	return string.format("%d/%d per min", count, cap)
end

util.task("stealth", 1, function()
	if config.get("stealth") then
		pcall(M.scanPresence)
	else
		M.visibleToPlayer = false
	end
end)

return M
