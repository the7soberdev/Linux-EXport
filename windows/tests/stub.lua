-- Minimal Roblox surface, enough to load the bundle outside the engine.
-- Locals, not _G: the bundle is concatenated after this file into one chunk,
-- and the luau CLI ships a readonly _G.

local function Event()
	local listeners = {}
	return {
		Connect = function(_, fn)
			listeners[#listeners + 1] = fn
			return { Disconnect = function() end }
		end,
		Fire = function(...)
			for _, fn in ipairs(listeners) do fn(...) end
		end,
		listeners = listeners,
	}
end

local Vector3 = function(x, y, z)
	x, y, z = x or 0, y or 0, z or 0
	return {
		__vector3 = true,
		X = x, Y = y, Z = z,
		Magnitude = math.sqrt(x * x + y * y + z * z),
		Unit = { X = x, Y = y, Z = z },
	}
end

local Vector2 = function(x, y) return { X = x or 0, Y = y or 0 } end
local Color3 = setmetatable({
	fromRGB = function(r, g, b) return { R = r or 0, G = g or 0, B = b or 0 } end,
	new = function(r, g, b) return { R = r or 0, G = g or 0, B = b or 0 } end,
}, {
	__call = function(_, r, g, b) return { R = r or 0, G = g or 0, B = b or 0 } end,
})
local CFrame = { new = function() return { Position = Vector3(0, 0, 0), LookVector = Vector3(0, 0, -1) } end }
local UDim = { new = function(scale, offset) return { Scale = scale or 0, Offset = offset or 0 } end }
local function newUDim2(sx, ox, sy, oy)
	return { X = { Scale = sx or 0, Offset = ox or 0 }, Y = { Scale = sy or 0, Offset = oy or 0 } }
end
local UDim2 = {
	new = newUDim2,
	fromOffset = function(x, y) return newUDim2(0, x, 0, y) end,
	fromScale = function(x, y) return newUDim2(x, 0, y, 0) end,
}
local TweenInfo = { new = function() return {} end }

local Enum = setmetatable({}, {
	__index = function(_, name)
		return setmetatable({}, {
			__index = function(_, key) return { Name = key, Value = key } end,
		})
	end,
})

local baseTypeof = typeof
local function typeOf(value)
	local t = baseTypeof(value)
	if t == "table" then
		if value.__instance then return "Instance" end
		if value.__vector3 then return "Vector3" end
	end
	return t
end

local function newInstance(class)
	local object = {
		__instance = true,
		ClassName = class,
		Name = class,
		Parent = nil,
		Children = {},
		Attributes = {},
		AbsolutePosition = Vector2(0, 0),
		AbsoluteSize = Vector2(100, 100),
		Position = UDim2.new(),
		Size = UDim2.new(),
		Visible = true,
		Enabled = true,
	}
	object.MouseButton1Click = Event()
	object.InputBegan = Event()
	object.InputEnded = Event()
	object.FocusLost = Event()
	object.ChildAdded = Event()
	object.CharacterAdded = Event()
	object.Idled = Event()
	object.TeleportInitFailed = Event()
	object.Heartbeat = Event()
	object.InputChanged = Event()

	function object:IsA(name)
		if self.ClassName == name then return true end
		if name == "BasePart" then return self.ClassName:find("Part") ~= nil end
		if name == "GuiObject" then
			return self.ClassName:find("Frame") ~= nil
				or self.ClassName:find("Label") ~= nil
				or self.ClassName:find("Button") ~= nil
				or self.ClassName:find("TextBox") ~= nil
		end
		return false
	end
	function object:GetChildren() return self.Children end
	function object:GetDescendants() return self.Children end
	function object:FindFirstChild() return nil end
	function object:FindFirstChildOfClass() return nil end
	function object:FindFirstChildWhichIsA() return nil end
	function object:GetAttributes() return self.Attributes end
	function object:SetAttribute(key, value) self.Attributes[key] = value end
	function object:Destroy() self.Parent = nil end
	function object:GetFullName() return self.Name end
	function object:Activate() end
	function object:FireServer() end
	function object:InputHoldBegin() end
	function object:InputHoldEnd() end

	return setmetatable(object, {
		__newindex = function(t, key, value)
			if key == "Parent" and value ~= nil and type(value) == "table" and value.Children then
				table.insert(value.Children, t)
			end
			rawset(t, key, value)
		end,
	})
end

local Instance = { new = newInstance }

local task = {
	wait = function() return 0 end,
	spawn = function() end,
	delay = function() end,
}

local function service(name) return newInstance(name .. "Service") end

local players = service("Players")
local character = newInstance("Model")
character.Name = "Character"
local root = newInstance("Part")
root.Name = "HumanoidRootPart"

local localPlayer = newInstance("Player")
localPlayer.Name = "TestPlayer"
localPlayer.Character = character
localPlayer.Idled = Event()
localPlayer.CharacterAdded = Event()
localPlayer.FindFirstChildOfClass = function(_, class)
	if class == "PlayerGui" then return newInstance("PlayerGui") end
	if class == "Backpack" then return newInstance("Backpack") end
	return nil
end
localPlayer.FindFirstChild = function() return nil end
localPlayer.GetRankInGroup = function() return 0 end

players.LocalPlayer = localPlayer
players.GetPlayers = function() return { localPlayer } end
players.PlayerAdded = Event()

local workspace = newInstance("Workspace")
workspace.Raycast = function() return nil end
local RaycastParams = { new = function() return { FilterDescendantsInstances = {}, FilterType = nil } end }
workspace.CurrentCamera = newInstance("Camera")
workspace.CurrentCamera.CFrame = CFrame.new()

local game = {
	PlaceId = 123456,
	JobId = "job-test",
	GetService = function(_, name)
		if name == "Players" then return players end
		local svc = service(name)
		if name == "UserInputService" then
			svc.IsKeyDown = function() return false end
			svc.GetMouseLocation = function() return Vector2(0, 0) end
		end
		if name == "TweenService" then
			svc.Create = function()
				return { Play = function() end, Completed = { Wait = function() end } }
			end
		end
		if name == "TeleportService" then
			svc.Teleport = function() end
			svc.TeleportToPlaceInstance = function() end
			svc.TeleportInitFailed = Event()
		end
		return svc
	end,
}

local GENV = {}
local getgenv = function() return GENV end
local identifyexecutor = function() return "stub" end
local fireproximityprompt = function() return true end
local function mouse1press() end
local function mouse1release() end
local Drawing = {
	new = function(kind)
		return { Remove = function() end, kind = kind }
	end,
}

print("[stub] environment ready")
