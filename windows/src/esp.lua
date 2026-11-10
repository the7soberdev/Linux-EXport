-- esp: drawing-based overlay for players, fish, npcs, chests
local env = __require("env")
local util = __require("util")
local config = __require("config")

local M = {
	entries = {},
	candidates = {},
	refreshAt = 0,
	enabledColors = {
		player = Color3.fromRGB(88, 166, 255),
		fish = Color3.fromRGB(88, 214, 141),
		npc = Color3.fromRGB(240, 190, 90),
		chest = Color3.fromRGB(230, 120, 230),
	},
}

local function remove(entry)
	if entry.box then pcall(function() entry.box:Remove() end) end
	if entry.label then pcall(function() entry.label:Remove() end) end
end

function M.clear()
	for _, entry in pairs(M.entries) do remove(entry) end
	M.entries = {}
	M.candidates = {}
end

local function worldToScreen(position)
	local camera = workspace.CurrentCamera
	if not camera then return nil, 0 end
	local screen, onScreen = camera:WorldToViewportPoint(position)
	if not onScreen or screen.Z <= 0 then return nil, screen.Z end
	return Vector2.new(screen.X, screen.Y), screen.Z
end

local function classify(name)
	local patterns = config.patterns
	if util.matches(name, patterns.espFish) then return "fish" end
	if util.matches(name, patterns.espNpc) then return "npc" end
	return "fish"
end

local function rebuildCandidates()
	local camera = workspace.CurrentCamera
	if not camera then return end
	local origin = camera.CFrame.Position
	local range = config.get("espRange")
	local list = {}

	if config.get("espPlayers") then
		for _, player in ipairs(env.Players:GetPlayers()) do
			if player ~= env.LocalPlayer and player.Character then
				local head = player.Character:FindFirstChild("Head")
				local root = player.Character:FindFirstChild("HumanoidRootPart")
				if root then
					list[#list + 1] = { kind = "player", position = root.Position, name = player.Name, object = player.Character }
				elseif head then
					list[#list + 1] = { kind = "player", position = head.Position, name = player.Name, object = player.Character }
				end
			end
		end
	end

	local wantFish = config.get("espFish")
	local wantNpc = config.get("espNpcs")
	local wantChest = config.get("espChests")

	if wantFish or wantNpc or wantChest then
		for _, part in ipairs(workspace:GetDescendants()) do
			if part:IsA("BasePart") and part.Parent then
				local kind
				local name = part.Name
				if wantNpc and util.matches(name, config.patterns.espNpc) then
					kind = "npc"
				elseif wantChest and (util.matches(name, { "chest", "crate", "loot" })) then
					kind = "chest"
				elseif wantFish and util.matches(name, config.patterns.espFish) then
					kind = "fish"
				end
				if kind then
					local distance = (part.Position - origin).Magnitude
					if distance <= range then
						list[#list + 1] = { kind = kind, position = part.Position, name = name, object = part, distance = distance }
					end
				end
			end
		end
	end

	M.candidates = list
end

local function ensure(entry)
	if entry.box or entry.label then return end
	if config.get("espBoxes") then
		local box = Drawing.new("Square")
		box.Thickness = 1
		box.Filled = false
		box.Transparency = 0.85
		box.Color = M.enabledColors[entry.kind] or Color3.new(1, 1, 1)
		entry.box = box
	end
	if config.get("espLabels") then
		local label = Drawing.new("Text")
		label.Size = 13
		label.Center = true
		label.Outline = true
		label.Color = M.enabledColors[entry.kind] or Color3.new(1, 1, 1)
		entry.label = label
	end
end

function M.step()
	if not env.has.drawing then return end
	if not config.get("esp") then
		if next(M.entries) then M.clear() end
		return
	end

	local now = util.now()
	if now >= M.refreshAt then
		M.refreshAt = now + 1
		rebuildCandidates()
	end

	local seen = {}
	for index, candidate in ipairs(M.candidates) do
		local key = candidate.object or index
		seen[key] = true
		local screen, depth = worldToScreen(candidate.position)

		if screen then
			local entry = M.entries[key]
			if not entry then
				entry = { kind = candidate.kind, name = candidate.name }
				M.entries[key] = entry
			end
			ensure(entry)

			local scale = util.clamp(1600 / math.max(depth, 1), 10, 180)
			if entry.box then
				entry.box.Size = Vector2.new(scale, scale)
				entry.box.Position = screen - Vector2.new(scale / 2, scale / 2)
				entry.box.Visible = true
			end
			if entry.label then
				local text = candidate.kind == "player" and candidate.name
					or string.format("%s [%dm]", candidate.name, math.floor(depth))
				entry.label.Text = text
				entry.label.Position = screen - Vector2.new(0, scale / 2 + 16)
				entry.label.Visible = true
			end
		else
			local entry = M.entries[key]
			if entry then
				if entry.box then entry.box.Visible = false end
				if entry.label then entry.label.Visible = false end
			end
		end
	end

	for key, entry in pairs(M.entries) do
		if not seen[key] then
			remove(entry)
			M.entries[key] = nil
		end
	end
end

util.task("esp", 0.1, function() pcall(M.step) end)

return M
