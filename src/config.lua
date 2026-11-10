-- config: defaults, persistence, profiles
local env = __require("env")
local util = __require("util")

local M = {}

local DEFAULTS = {
	-- fishing
	autoCast = true,
	autoReel = true,
	instantReel = true,
	autoRod = true,
	castDelay = 0.9,
	reelMode = "Auto",        -- Auto | Tool | Remote | Input
	keepDistance = 0,         -- 0 = off, otherwise hold this range from others

	-- economy
	autoSell = true,
	sellInterval = 120,
	autoAppraise = false,
	appraiseInterval = 300,
	autoBuyBait = false,
	autoQuest = false,
	questInterval = 120,

	-- movement
	walkSpeed = 16,
	jumpPower = 50,
	fly = false,
	noclip = false,
	infOxygen = false,
	tpSpeed = 200,

	-- esp
	esp = false,
	espPlayers = true,
	espFish = true,
	espNpcs = false,
	espChests = true,
	espRange = 600,
	espBoxes = true,
	espLabels = true,

	-- stealth
	stealth = true,
	humanize = true,
	pauseOnPlayers = true,
	proximityRadius = 140,
	teleportGuard = true,
	rateCap = 14,          -- catches per minute ceiling
	imperfection = 0.07,   -- chance of a deliberate slip per catch
	sessionMinutes = 55,
	breakMinutes = 7,
	panicKey = "Delete",

	-- misc
	antiAfk = true,
	antiMod = true,
	autoRejoin = false,
	notify = true,
	debug = false,

	-- ui
	keybind = "RightControl",
}

local PATTERNS = {
	rod       = { "rod", "fishing rod" },
	reel      = { "reel", "catch", "fish", "hook" },
	cast      = { "cast", "throw", "fish" },
	sell      = { "sell", "shop", "vendor", "merchant", "trader" },
	appraise  = { "appraise", "appraiser", "appraisal", "evaluate" },
	quest     = { "quest", "mission", "claim", "reward" },
	bait      = { "bait", "buy", "purchase" },
	minigame  = { "fish", "reel", "catch", "mini", "bobber", "bite", "hook" },
	marker    = { "marker", "indicator", "pointer", "needle", "zone", "target", "perfect", "cursor" },
	track     = { "bar", "track", "zone", "area", "gauge", "meter" },
	espFish   = { "fish", "bobber", "crate", "chest", "loot", "item" },
	espNpc    = { "npc", "villager", "merchant", "angler", "keeper" },
	oxygen    = { "oxygen", "air", "breath" },
}

M.patterns = PATTERNS

local Config = {}
for key, value in pairs(DEFAULTS) do Config[key] = value end
M.data = Config

local FILE = "fischhub/config.lua"

function M.get(key)
	return Config[key]
end

function M.set(key, value)
	Config[key] = value
	M.save()
end

function M.save()
	if not (env.has.writefile and env.has.isfolder and env.has.makefolder) then
		if not env.has.writefile then return false end
	end
	local ok, err = pcall(function()
		local folder = "fischhub"
		if env.has.isfolder and not isfolder(folder) then
			makefolder(folder)
		end
		if env.has.makefolder and not env.has.isfolder then
			makefolder(folder)
		end
		writefile(FILE, "return " .. util.serialize(Config) .. "\n")
	end)
	if not ok then env.log("config save failed: %s", tostring(err)) end
	return ok
end

function M.load()
	if not (env.has.readfile and env.has.isfile) then return false end
	local ok, data = pcall(function()
		if not isfile(FILE) then return nil end
		if env.has.loadstring then
			return loadstring(readfile(FILE))()
		end
		return nil
	end)
	if ok and type(data) == "table" then
		for key, value in pairs(data) do
			if DEFAULTS[key] ~= nil and typeof(DEFAULTS[key]) == typeof(value) then
				Config[key] = value
			end
		end
		return true
	end
	return false
end

function M.reset()
	for key, value in pairs(DEFAULTS) do Config[key] = value end
	return M.save()
end

function M.defaults()
	return DEFAULTS
end

function M.profilePath(name)
	local safe = (tostring(name):gsub("[^%w_-]", "_"))
	return string.format("fischhub/profile-%s.lua", safe)
end

function M.saveProfile(name)
	if not env.has.writefile then return false end
	return pcall(writefile, M.profilePath(name), "return " .. util.serialize(Config) .. "\n")
end

function M.loadProfile(name)
	if not (env.has.readfile and env.has.isfile) then return false end
	local path = M.profilePath(name)
	if not isfile(path) then return false end
	local ok, data = pcall(function() return loadstring(readfile(path))() end)
	if not (ok and type(data) == "table") then return false end
	for key, value in pairs(data) do
		if DEFAULTS[key] ~= nil and typeof(DEFAULTS[key]) == typeof(value) then
			Config[key] = value
		end
	end
	return true
end

return M
