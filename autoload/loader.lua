-- Fisch Hub autoload stub (Windows + Linux)
--
-- Put this in an executor's autoexec directory. It runs on every injection and
-- pulls the hub from the newest source it can reach:
--
--   1. getgenv().FischHubPath, if you set it
--   2. a copy next to the executor's workspace (both platforms)
--   3. an absolute install path (Linux config dir, Windows LOCALAPPDATA)
--   4. the remote URL below, when you host the bundle yourself
--
-- The installers write the bundle to the relative paths first, so they normally
-- hit without any configuration.

local REMOTE = "" -- e.g. "https://raw.githubusercontent.com/you/fisch-hub/main/dist/FischHub.lua"

local function getenv(name)
	if type(os) ~= "table" or type(os.getenv) ~= "function" then return nil end
	local ok, value = pcall(os.getenv, name)
	if ok and type(value) == "string" and #value > 0 then return value end
	return nil
end

local SOURCES = {}

local genv
if type(getgenv) == "function" then
	local ok, env = pcall(getgenv)
	if ok and type(env) == "table" then genv = env end
end
if genv and type(genv.FischHubPath) == "string" and #genv.FischHubPath > 0 then
	table.insert(SOURCES, genv.FischHubPath)
end

-- relative to the executor workspace; installed by fisch-hub.sh and fisch-hub.ps1
table.insert(SOURCES, "fischhub/hub.lua")
table.insert(SOURCES, "FischHub.lua")
table.insert(SOURCES, "H FischHub.lua")

local home = getenv("HOME")
if home then
	table.insert(SOURCES, home .. "/.config/fisch-hub/FischHub.lua")
end

local localAppData = getenv("LOCALAPPDATA")
if localAppData then
	local win = localAppData:gsub("\\", "/")
	table.insert(SOURCES, win .. "/FischHub/FischHub.lua")
	table.insert(SOURCES, win .. "/FischHub/fischhub/hub.lua")
end

local function canRead()
	return type(isfile) == "function" and type(readfile) == "function"
end

local function readLocal()
	if not canRead() then return nil end
	for _, path in ipairs(SOURCES) do
		local ok, exists = pcall(isfile, path)
		if ok and exists then
			local readOk, source = pcall(readfile, path)
			if readOk and type(source) == "string" and #source > 1000 then
				return source, path
			end
		end
	end
	return nil
end

local function fetchRemote()
	if REMOTE == "" then return nil end
	local ok, source = pcall(function() return game:HttpGet(REMOTE) end)
	if ok and type(source) == "string" and #source > 1000 then
		if type(writefile) == "function" then
			pcall(function()
				if type(isfolder) == "function" and not isfolder("fischhub") then
					if type(makefolder) == "function" then makefolder("fischhub") end
				end
				writefile("fischhub/hub.lua", source)
			end)
		end
		return source
	end
	return nil
end

local source, origin = readLocal()
if not source then
	source = fetchRemote()
	origin = REMOTE ~= "" and REMOTE or nil
end

if not source then
	warn("[FischHub] loader found no hub source - run the installer for your platform")
	return
end

local chunk, compileError = loadstring(source, "=FischHub")
if not chunk then
	warn("[FischHub] bundle failed to compile: " .. tostring(compileError))
	return
end

local ok, err = pcall(chunk)
if not ok then
	warn("[FischHub] runtime error: " .. tostring(err))
	return
end

print(string.format("[FischHub] autoloaded from %s", tostring(origin)))
