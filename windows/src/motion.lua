-- motion: walk speed, jump, fly, noclip, oxygen, tween teleports
local env = __require("env")
local util = __require("util")
local config = __require("config")

local M = { flyBody = nil, flying = false, noclipOn = false }

local original = { speed = nil, jump = nil }

function M.root()
	return env.Root()
end

--------------------------------------------------------------------------------
-- speed / jump
--------------------------------------------------------------------------------

function M.setSpeed(value)
	local humanoid = env.Humanoid()
	if not humanoid then return false end
	original.speed = original.speed or humanoid.WalkSpeed
	humanoid.WalkSpeed = value
	return true
end

function M.setJump(value)
	local humanoid = env.Humanoid()
	if not humanoid then return false end
	original.jump = original.jump or humanoid.JumpPower
	humanoid.UseJumpPower = true
	humanoid.JumpPower = value
	return true
end

function M.resetPhysics()
	local humanoid = env.Humanoid()
	if not humanoid then return end
	humanoid.WalkSpeed = original.speed or 16
	humanoid.JumpPower = original.jump or 50
	humanoid.UseJumpPower = true
end

--------------------------------------------------------------------------------
-- teleport
--------------------------------------------------------------------------------

function M.tweenTo(position, speed)
	local root = env.Root()
	if not root then return false end

	local stealth = __require("stealth")
	local allowed, witness = stealth.teleportAllowed(position)
	if not allowed then
		env.log("teleport held: %s is within range of the destination", tostring(witness))
		return false
	end

	speed = speed or config.get("tpSpeed")
	local distance = (root.Position - position).Magnitude
	local duration = util.clamp(distance / math.max(speed, 1), 0.08, 3)
	local tween = env.TweenService:Create(root, TweenInfo.new(duration, Enum.EasingStyle.Linear), { CFrame = CFrame.new(position) })
	tween:Play()

	if config.get("noclip") then
		pcall(function() root.CanCollide = false end)
	end
	tween.Completed:Wait()
	return true
end

function M.blink(position)
	local root = env.Root()
	if not root then return false end
	root.CFrame = CFrame.new(position)
	return true
end

--------------------------------------------------------------------------------
-- fly
--------------------------------------------------------------------------------

function M.stopFly()
	M.flying = false
	if M.flyBody then
		pcall(function() M.flyBody:Destroy() end)
		M.flyBody = nil
	end
	local root = env.Root()
	if root then
		for _, child in ipairs(root:GetChildren()) do
			if child:IsA("BodyVelocity") and child.Name == "FischHubFly" then child:Destroy() end
		end
	end
end

function M.startFly(speed)
	local root = env.Root()
	if not root then return false end
	M.stopFly()

	local body = Instance.new("BodyVelocity")
	body.Name = "FischHubFly"
	body.Velocity = Vector3.zero
	body.MaxForce = Vector3.new(1e6, 1e6, 1e6)
	body.P = 1250
	body.Parent = root
	M.flyBody = body
	M.flying = true
	M.flySpeed = speed or 80

	local humanoid = env.Humanoid()
	if humanoid then humanoid.PlatformStand = true end
	return true
end

local function flyStep()
	if not M.flying or not M.flyBody then return end
	local root = env.Root()
	local camera = workspace.CurrentCamera
	if not root or not camera then return end

	local move = Vector3.zero
	if env.UserInputService:IsKeyDown(Enum.KeyCode.W) then move += camera.CFrame.LookVector end
	if env.UserInputService:IsKeyDown(Enum.KeyCode.S) then move -= camera.CFrame.LookVector end
	if env.UserInputService:IsKeyDown(Enum.KeyCode.D) then move += camera.CFrame.RightVector end
	if env.UserInputService:IsKeyDown(Enum.KeyCode.A) then move -= camera.CFrame.RightVector end
	if env.UserInputService:IsKeyDown(Enum.KeyCode.Space) then move += Vector3.new(0, 1, 0) end
	if env.UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then move -= Vector3.new(0, 1, 0) end

	if move.Magnitude > 0 then
		M.flyBody.Velocity = move.Unit * M.flySpeed
	else
		M.flyBody.Velocity = Vector3.zero
	end
end

--------------------------------------------------------------------------------
-- noclip
--------------------------------------------------------------------------------

local function noclipStep()
	if not config.get("noclip") then return end
	local character = env.LocalPlayer.Character
	if not character then return end
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") and part.CanCollide then
			part.CanCollide = false
		end
	end
end

function M.setNoclip(enabled)
	config.set("noclip", enabled)
	if not enabled then
		local character = env.LocalPlayer.Character
		if character then
			for _, part in ipairs(character:GetDescendants()) do
				if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
					part.CanCollide = true
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- oxygen
--
-- Fisch tracks air while submerged. The value lives either as a leaderstats
-- entry, a player attribute, or a field inside the character's humanoid
-- attributes depending on the version. All three are written every tick; a
-- write that lands on the wrong one is harmless.
--------------------------------------------------------------------------------

local function oxygenStep()
	if not config.get("infOxygen") then return end
	local player = env.LocalPlayer

	for _, container in ipairs({ player, player:FindFirstChild("leaderstats"), env.LocalPlayer.Character }) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("IntValue") or child:IsA("NumberValue") then
					if util.matches(child.Name, config.patterns.oxygen) then
						child.Value = 100
					end
				end
			end
		end
	end

	for name in pairs(player:GetAttributes()) do
		if util.matches(name, config.patterns.oxygen) then
			pcall(function() player:SetAttribute(name, 100) end)
		end
	end
end

--------------------------------------------------------------------------------
-- tick
--------------------------------------------------------------------------------

util.task("motion", 0.1, function()
	pcall(flyStep)
	pcall(noclipStep)
	pcall(oxygenStep)
end)

return M
