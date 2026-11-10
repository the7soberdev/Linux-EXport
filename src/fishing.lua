-- fishing: cast / wait / reel state machine
local env = __require("env")
local util = __require("util")
local config = __require("config")
local scanner = __require("scanner")
local minigame = __require("minigame")
local stealth = __require("stealth")

local M = {
	state = "idle",
	rod = nil,
	casts = 0,
	catches = 0,
	sessionStart = util.now(),
	lastCast = 0,
	waitStart = 0,
	waits = {},
	enabled = true,
}

local MAX_REEL_SECONDS = 25

local function equip(rod)
	local character = env.LocalPlayer.Character
	if not character then return false end
	if rod.Parent == character then return true end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return false end
	local ok = pcall(function() humanoid:EquipTool(rod) end)
	task.wait(0.12)
	return ok and rod.Parent == character
end

function M.currentRod()
	if not config.get("autoRod") then
		local character = env.LocalPlayer.Character
		if character then
			for _, item in ipairs(character:GetChildren()) do
				if item:IsA("Tool") and util.matches(item.Name, config.patterns.rod) then
					return item
				end
			end
		end
		return nil
	end
	return scanner.bestRod()
end

local function cast()
	local rod = M.rod
	if not rod then
		M.state = "no-rod"
		return false
	end
	if not equip(rod) then
		M.state = "equip-failed"
		return false
	end

	if config.get("reelMode") == "Remote" then
		local remote = scanner.remotes.cast
		if remote then
			pcall(function() remote:FireServer() end)
			M.casts = M.casts + 1
			M.lastCast = util.now()
			M.state = "wait"
			M.waitStart = util.now()
			return true
		end
	end

	pcall(function() rod:Activate() end)
	M.casts = M.casts + 1
	M.lastCast = util.now()
	M.state = "wait"
	M.waitStart = util.now()
	return true
end

function M.step()
	if not M.enabled then
		M.state = "disabled"
		return
	end

	local wantCast = config.get("autoCast")
	local wantReel = config.get("autoReel")
	if not (wantCast or wantReel) then
		M.state = "off"
		return
	end

	-- A reel already in progress is always finished: abandoning mid-catch is
	-- exactly the kind of half-action that looks wrong. Everything else waits.
	if M.state ~= "reel" and stealth.blocked() then
		M.state = "hold:" .. (stealth.blockedReason or "?")
		return
	end

	local rod = M.currentRod()
	if not rod then
		M.state = "no-rod"
		return
	end
	M.rod = rod

	local active = minigame.tick(wantReel) == true

	if active then
		if wantReel then
			if M.state ~= "reel" then
				M.state = "reel"
				M.reelStart = util.now()
				M.wasReeling = true
				M.slip = stealth.shouldSlip()

				-- close out the wait sample so patience adapts to this rod
				if M.waitStart and M.waitStart > 0 then
					M.waits[#M.waits + 1] = util.now() - M.waitStart
					if #M.waits > 12 then table.remove(M.waits, 1) end
				end
			end

			if util.now() - (M.reelStart or 0) > MAX_REEL_SECONDS then
				M.state = "reel-timeout"
				M.reelStart = util.now()
			end

			-- Deliberate slip: hold off long enough that this catch escapes.
			-- A sub-perfect success rate is part of the profile, not a bug.
			if M.slip then
				if util.now() - M.reelStart < 0.65 then
					return
				end
				M.slip = false
			end
			return
		end
		M.state = "reel-skip"
		return
	end

	if M.wasReeling then
		M.wasReeling = false
		M.catches = M.catches + 1
		stealth.noteCatch()
		M.state = "loot"
		return
	end

	if not wantCast then
		M.state = "idle"
		return
	end

	local waited = util.now() - M.waitStart
	local average = 4
	if #M.waits > 0 then
		local total = 0
		for _, value in ipairs(M.waits) do total += value end
		average = total / #M.waits
	end
	local patience = util.clamp(math.max(average * 2.2, config.get("castDelay") + 1), 3, 20)
	patience = stealth.jitter(patience, 0.3)

	if M.state == "wait" and waited < patience then
		return
	end

	cast()
end

function M.stats()
	local elapsed = math.max(util.now() - M.sessionStart, 1)
	return {
		state = M.state,
		casts = M.casts,
		catches = M.catches,
		perMinute = M.catches / (elapsed / 60),
		rod = M.rod and M.rod.Name or nil,
	}
end

util.task("fishing", 0.05, function() pcall(M.step) end)

return M
