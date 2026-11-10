-- economy: sell, appraise, restock
--
-- Three interaction mechanisms are attempted in order, because the vendor
-- interface is the least stable part of a fishing game across updates:
--   1. ProximityPrompt  (hold / fire)
--   2. ClickDetector    (fireclickdetector)
--   3. RemoteEvent      (FireServer, discovered or learned)
local env = __require("env")
local util = __require("util")
local config = __require("config")
local scanner = __require("scanner")
local motion = __require("motion")

local M = { sells = 0, appraisals = 0, mechanism = "-" }

local function travel(position)
	local root = env.Root()
	if not (position and root) then return false end
	if (position - root.Position).Magnitude > 12 then
		return motion.tweenTo(position + Vector3.new(0, 3, 0))
	end
	return false
end

local function returnTo(origin)
	if origin then
		task.wait(0.2)
		pcall(motion.tweenTo, origin)
	end
end

local function firePrompt(prompt, times)
	if not prompt then return false end
	for _ = 1, times or 3 do
		if env.has.proximity then
			pcall(fireproximityprompt, prompt)
		else
			pcall(function()
				prompt:InputHoldBegin()
				task.wait(math.max(prompt.HoldDuration, 0.1))
				prompt:InputHoldEnd()
			end)
		end
		task.wait(0.22)
	end
	return true
end

local function fireDetector(detector)
	if typeof(fireclickdetector) ~= "function" then return false end
	local ok = pcall(fireclickdetector, detector)
	if ok then
		task.wait(0.25)
		pcall(fireclickdetector, detector)
	end
	return ok
end

local function fireRemote(remote)
	if not remote then return false end
	local ok = pcall(function() remote:FireServer() end)
	if not ok then
		ok = pcall(function() remote:InvokeServer() end)
	end
	return ok
end

function M.interact(kind, times)
	local origin = env.Root() and env.Root().Position

	-- 1. proximity prompt
	local record = scanner.nearestPrompt(kind)
	if record then
		travel(record.position)
		firePrompt(record.prompt, times)
		returnTo(origin)
		M.mechanism = "prompt"
		return true
	end

	-- 2. click detector
	local detectors = scanner.clickDetectors[kind]
	if detectors and #detectors > 0 then
		local best = detectors[1]
		travel(best.position)
		if fireDetector(best.detector) then
			returnTo(origin)
			M.mechanism = "clickdetector"
			return true
		end
	end

	-- 3. remote
	local remote = scanner.remotes[kind]
	if remote and fireRemote(remote) then
		M.mechanism = "remote"
		return true
	end

	M.mechanism = "none"
	return false
end

function M.sell()
	if not M.interact("sell", 4) then return false end
	M.sells = M.sells + 1
	return true
end

function M.appraise()
	if not M.interact("appraise", 2) then return false end
	M.appraisals = M.appraisals + 1
	return true
end

function M.buyBait()
	return M.interact("bait", 2)
end

local nextSell, nextAppraise = 0, 0

util.task("economy", 2, function()
	local now = util.now()

	if config.get("autoSell") then
		if nextSell == 0 then nextSell = now + 15 end
		if now >= nextSell then
			nextSell = M.sell() and (now + config.get("sellInterval")) or (now + 30)
		end
	else
		nextSell = 0
	end

	if config.get("autoAppraise") then
		if nextAppraise == 0 then nextAppraise = now + 30 end
		if now >= nextAppraise then
			M.appraise()
			nextAppraise = now + config.get("appraiseInterval")
		end
	else
		nextAppraise = 0
	end
end)

return M
