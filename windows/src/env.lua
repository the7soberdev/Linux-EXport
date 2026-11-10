-- env: services, executor capability detection, logging
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Lighting = game:GetService("Lighting")
local CoreGui = game:GetService("CoreGui")

local M = {
	Players = Players,
	ReplicatedStorage = ReplicatedStorage,
	RunService = RunService,
	TweenService = TweenService,
	UserInputService = UserInputService,
	VirtualUser = VirtualUser,
	VirtualInputManager = VirtualInputManager,
	Lighting = Lighting,
	CoreGui = CoreGui,
}

M.has = {
	drawing    = typeof(Drawing) == "table" and Drawing.new ~= nil,
	writefile  = typeof(writefile) == "function",
	readfile   = typeof(readfile) == "function",
	isfile     = typeof(isfile) == "function",
	isfolder   = typeof(isfolder) == "function",
	makefolder = typeof(makefolder) == "function",
	loadstring = typeof(loadstring) == "function",
	hook       = typeof(hookfunction) == "function",
	getgenv    = typeof(getgenv) == "function",
	proximity  = typeof(fireproximityprompt) == "function",
	mouse1     = typeof(mouse1press) == "function",
	httppost   = typeof(request) == "function" or typeof(http_request) == "function",
	queue      = typeof(queue_on_teleport) == "function" or typeof(TeleportToPlaceInstance) == "function",
}

repeat task.wait() until Players.LocalPlayer
M.LocalPlayer = Players.LocalPlayer
M.Character = function()
	return M.LocalPlayer.Character or M.LocalPlayer.CharacterAdded:Wait()
end
M.Humanoid = function()
	local character = M.LocalPlayer.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end
M.Root = function()
	local character = M.LocalPlayer.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local startedAt = os.clock()
M.executor = "unknown"
if typeof(identifyexecutor) == "function" then
	local ok, name = pcall(identifyexecutor)
	if ok and type(name) == "string" then M.executor = name end
end

function M.log(fmt, ...)
	local text
	if select("#", ...) > 0 then
		local ok, formatted = pcall(string.format, fmt, ...)
		text = ok and formatted or tostring(fmt)
	else
		text = tostring(fmt)
	end
	print(string.format("[FischHub] %s", text))
end

function M.uptime()
	return os.clock() - startedAt
end

return M
