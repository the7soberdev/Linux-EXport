-- main: boot, keybinds, status, public API
local env = __require("env")
local util = __require("util")
local config = __require("config")
local scanner = __require("scanner")
local motion = __require("motion")
local minigame = __require("minigame")
local fishing = __require("fishing")
local economy = __require("economy")
local quests = __require("quests")
local esp = __require("esp")
local anti = __require("anti")
local stealth = __require("stealth")
local learn = __require("learn")
local ui = __require("ui")

local M = { version = "2.1.0" }

config.load()
scanner.refresh(true)
ui.build()

util.scheduler.start()

--------------------------------------------------------------------------------
-- keybind
--------------------------------------------------------------------------------

local function bindToggle()
	local keyName = config.get("keybind")
	local ok, key = pcall(function() return Enum.KeyCode[keyName] end)
	if not ok or not key then key = Enum.KeyCode.RightControl end

	local panicName = config.get("panicKey")
	local panicOk, panicKey = pcall(function() return Enum.KeyCode[panicName] end)
	if not panicOk or not panicKey then panicKey = Enum.KeyCode.Delete end

	env.UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == key then
			ui.toggle()
		elseif input.KeyCode == panicKey then
			-- One key, nothing to confirm, no menu to navigate.
			stealth.engagePanic()
		end
	end)
end

bindToggle()

--------------------------------------------------------------------------------
-- character lifecycle
--------------------------------------------------------------------------------

local function applyPhysics()
	local speed = config.get("walkSpeed")
	local jump = config.get("jumpPower")
	if speed and speed ~= 16 then motion.setSpeed(speed) end
	if jump and jump ~= 50 then motion.setJump(jump) end
	if config.get("noclip") then motion.setNoclip(true) end
	if config.get("fly") then motion.startFly(80) end
end

env.LocalPlayer.CharacterAdded:Connect(function()
	task.wait(0.6)
	pcall(applyPhysics)
	if config.get("autoRod") then pcall(function() fishing.rod = scanner.bestRod() end) end
end)

if env.LocalPlayer.Character then
	task.wait(0.4)
	pcall(applyPhysics)
end

--------------------------------------------------------------------------------
-- pause gate: staff detection stops the fisher without destroying state
--------------------------------------------------------------------------------

util.task("gate", 1, function()
	local paused = anti.shouldPause()
	fishing.enabled = not paused
	if paused ~= anti.paused then
		anti.paused = paused
		if paused then
			ui.notify("staff in server - paused", "bad")
		else
			ui.notify("resumed", "good")
		end
	end
end)

--------------------------------------------------------------------------------
-- status
--------------------------------------------------------------------------------

util.task("status", 0.5, function()
	local stats = fishing.stats()
	local text = string.format(
		"%s | rod:%s | casts:%d | catches:%d | %.1f/min",
		stats.state,
		stats.rod or "-",
		stats.casts,
		stats.catches,
		stats.perMinute
	)
	if anti.staffPresent then
		text = text .. " | STAFF"
	end
	text = text .. " | " .. stealth.status()
	ui.setStatus(text, anti.staffPresent and "bad" or (stats.state == "reel" and "good" or nil))
end)

--------------------------------------------------------------------------------
-- public API
--------------------------------------------------------------------------------

local API = {
	version = M.version,
	config = config,
	scanner = scanner,
	motion = motion,
	minigame = minigame,
	fishing = fishing,
	economy = economy,
	quests = quests,
	esp = esp,
	anti = anti,
	stealth = stealth,
	learn = learn,
	ui = ui,

	toggle = function() ui.toggle() end,
	notify = ui.notify,
	save = function() return config.save() end,
	reload = function()
		if env.has.loadstring and env.has.readfile then
			return true
		end
		return false
	end,
	probe = function()
		scanner.refresh(true)
		env.log(scanner.summary())
		env.log("scheduler: %s", util.scheduler.stats())
		for _, remote in ipairs(scanner.remotes.all) do
			env.log("  remote %s", remote:GetFullName())
		end
		for kind, records in pairs(scanner.prompts) do
			for _, record in ipairs(records) do
				env.log("  prompt[%s] %s", kind, record.prompt:GetFullName())
			end
		end
	end,
}

if env.has.getgenv then
	getgenv().FischHub = API
end

env.log("v%s loaded in %s", M.version, env.executor)
ui.notify("Fisch Hub v" .. M.version, "good")

return API
