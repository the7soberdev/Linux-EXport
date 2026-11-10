-- anti: anti-afk, staff detection, auto rejoin, performance cleanup
local env = __require("env")
local util = __require("util")
local config = __require("config")

local M = {
	staff = {},
	staffPresent = false,
	paused = false,
	kicks = 0,
	rejoins = 0,
	lastRejoin = 0,
}

-- Names and group ids checked for staff. Add to this from the console with
-- getgenv().FischHub.anti.watch("name", "groupid")
M.watchList = {}
M.watchGroups = {}

function M.watch(name, groupId)
	M.watchList[name:lower()] = true
	if groupId then M.watchGroups[tostring(groupId)] = true end
end

local function looksLikeStaff(player)
	local name = player.Name:lower()
	local display = (player.DisplayName or ""):lower()

	if M.watchList[name] or M.watchList[display] then return true end
	for marker in pairs({ mod = true, admin = true, staff = true, dev = true }) do
		if name:find(marker, 1, true) or display:find(marker, 1, true) then return true end
	end

	for groupId in pairs(M.watchGroups) do
		local ok, rank = pcall(function() return player:GetRankInGroup(tonumber(groupId) or 0) end)
		if ok and rank and rank >= 250 then return true end
	end
	return false
end

function M.scanStaff()
	local found = {}
	for _, player in ipairs(env.Players:GetPlayers()) do
		if player ~= env.LocalPlayer and looksLikeStaff(player) then
			found[player.Name] = true
		end
	end
	local changed = false
	for name in pairs(found) do
		if not M.staff[name] then changed = true end
	end
	for name in pairs(M.staff) do
		if not found[name] then changed = true end
	end
	M.staff = found
	M.staffPresent = next(found) ~= nil
	if changed and config.get("notify") then
		local names = {}
		for name in pairs(found) do names[#names + 1] = name end
		table.sort(names)
		if M.staffPresent then
			env.log("staff detected: %s", table.concat(names, ", "))
		end
	end
	return M.staffPresent
end

local function antiAfk()
	local humanoid = env.Humanoid()
	if not humanoid then return end
	pcall(function()
		env.VirtualUser:CaptureController()
		env.VirtualUser:ClickButton2(Vector2.new())
	end)
	if humanoid.MoveDirection.Magnitude < 0.01 then
		humanoid.Jump = true
	end
end

function M.shouldPause()
	return config.get("antiMod") and M.staffPresent
end

function M.rejoin()
	if not env.has.queue then return false end
	if util.now() - M.lastRejoin < 30 then return false end
	M.lastRejoin = util.now()
	M.rejoins = M.rejoins + 1
	local placeId = game.PlaceId
	local jobId = game.JobId
	-- No queue_on_teleport here on purpose: the hub is reloaded by the executor
	-- autoexec stub on the next injection, so queueing a duplicate would run it
	-- twice. install.sh keeps that stub in every detected executor folder.
	if jobId and jobId ~= "" then
		pcall(function()
			game:GetService("TeleportService"):TeleportToPlaceInstance(placeId, jobId, env.LocalPlayer)
		end)
	else
		pcall(function()
			game:GetService("TeleportService"):Teleport(placeId, env.LocalPlayer)
		end)
	end
	return true
end

local function hookDisconnect()
	local service = game:GetService("TeleportService")
	service.TeleportInitFailed:Connect(function()
		M.kicks = M.kicks + 1
		if config.get("autoRejoin") then
			task.delay(3, function() pcall(M.rejoin) end)
		end
	end)
end

function M.cleanupVisuals()
	local removed = 0
	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("ParticleEmitter") or obj:IsA("Smoke") or obj:IsA("Fire") or obj:IsA("Sparkles") then
			pcall(function() obj.Enabled = false end)
			removed = removed + 1
		end
	end
	env.Lighting.GlobalShadows = false
	return removed
end

hookDisconnect()

util.task("anti", 2, function()
	if config.get("antiMod") then M.scanStaff() end
end)

util.task("antiafk", 60, function()
	if config.get("antiAfk") then pcall(antiAfk) end
end)

return M
