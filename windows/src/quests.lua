-- quests: turn-in and reward prompts
local env = __require("env")
local util = __require("util")
local config = __require("config")
local scanner = __require("scanner")
local motion = __require("motion")

local M = { claims = 0, lastClaim = 0 }

-- Quest NPCs are interacted with through ProximityPrompt, which is the one
-- interface every quest system in this genre exposes. Firing it repeatedly
-- covers the common pattern of talk -> accept -> hand in -> claim, since each
-- step is a fresh prompt on the same object.
function M.claim()
	local record = scanner.nearestPrompt("quest")
	if not record then return false end

	local origin = env.Root() and env.Root().Position
	if record.position and origin and (record.position - origin).Magnitude > 12 then
		motion.tweenTo(record.position + Vector3.new(0, 3, 0))
		task.wait(0.4)
	end

	for _ = 1, 6 do
		if env.has.proximity then
			pcall(fireproximityprompt, record.prompt)
		else
			pcall(function()
				record.prompt:InputHoldBegin()
				task.wait(math.max(record.prompt.HoldDuration, 0.1))
				record.prompt:InputHoldEnd()
			end)
		end
		task.wait(0.45)
	end

	if record.position and origin and (record.position - origin).Magnitude > 12 then
		motion.tweenTo(origin)
	end

	M.claims = M.claims + 1
	M.lastClaim = util.now()
	return true
end

local nextClaim = 0

util.task("quests", 4, function()
	if not config.get("autoQuest") then
		nextClaim = 0
		return
	end
	local now = util.now()
	if nextClaim == 0 then nextClaim = now + 20 end
	if now >= nextClaim then
		if M.claim() then
			nextClaim = now + config.get("questInterval")
		else
			nextClaim = now + 60
		end
	end
end)

return M
