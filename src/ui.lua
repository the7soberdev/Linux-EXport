-- ui: tabbed panel
local env = __require("env")
local util = __require("util")
local config = __require("config")

local M = { root = nil, tabs = {}, pages = {}, current = nil, notifications = nil }

local Palette = {
	bg      = Color3.fromRGB(14, 15, 18),
	panel   = Color3.fromRGB(22, 23, 28),
	row     = Color3.fromRGB(32, 34, 41),
	rowOn   = Color3.fromRGB(30, 46, 38),
	accent  = Color3.fromRGB(90, 200, 160),
	good    = Color3.fromRGB(90, 220, 140),
	warn    = Color3.fromRGB(240, 170, 80),
	bad     = Color3.fromRGB(240, 110, 110),
	text    = Color3.fromRGB(232, 234, 240),
	dim     = Color3.fromRGB(138, 142, 155),
	border  = Color3.fromRGB(48, 50, 60),
}

local function inst(class, props, parent)
	local object = Instance.new(class)
	for key, value in pairs(props) do object[key] = value end
	if parent then object.Parent = parent end
	return object
end

local function round(parent, radius)
	inst("UICorner", { CornerRadius = UDim.new(0, radius or 6) }, parent)
end

local function pad(parent, amount)
	inst("UIPadding", {
		PaddingLeft = UDim.new(0, amount),
		PaddingRight = UDim.new(0, amount),
		PaddingTop = UDim.new(0, amount),
		PaddingBottom = UDim.new(0, amount),
	}, parent)
end

--------------------------------------------------------------------------------
-- notifications
--------------------------------------------------------------------------------

function M.notify(text, tone)
	if not M.notifications then return end
	local color = tone == "good" and Palette.good or tone == "bad" and Palette.bad or Palette.accent

	local frame = inst("Frame", {
		Size = UDim2.fromOffset(260, 32),
		BackgroundColor3 = Palette.panel,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
	}, M.notifications)
	round(frame, 6)
	inst("UIStroke", { Color = color, Thickness = 1, Transparency = 0.45 }, frame)

	local label = inst("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = Palette.text,
		TextSize = 13,
		Font = Enum.Font.GothamMedium,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, frame)
	inst("UIPadding", { PaddingLeft = UDim.new(0, 10) }, label)

	if config.get("notify") then
		task.delay(4.5, function()
			pcall(function()
				env.TweenService:Create(frame, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
				task.wait(0.35)
				frame:Destroy()
			end)
		end)
	end
end

--------------------------------------------------------------------------------
-- row builders
--------------------------------------------------------------------------------

local function rowShell(parent, height)
	local row = inst("Frame", {
		Size = UDim2.new(1, -10, 0, height or 30),
		BackgroundColor3 = Palette.row,
		BorderSizePixel = 0,
	}, parent)
	round(row, 5)
	return row
end

local function toggleRow(parent, labelText, key, onChange)
	local row = rowShell(parent, 30)
	local dot = inst("Frame", {
		Size = UDim2.fromOffset(10, 10),
		Position = UDim2.new(1, -20, 0.5, -5),
		BackgroundColor3 = config.get(key) and Palette.good or Palette.dim,
		BorderSizePixel = 0,
	}, row)
	round(dot, 5)

	inst("TextLabel", {
		Size = UDim2.new(1, -44, 1, 0),
		Position = UDim2.fromOffset(10, 0),
		BackgroundTransparency = 1,
		Text = labelText,
		TextColor3 = Palette.text,
		TextSize = 13,
		Font = Enum.Font.GothamMedium,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, row)

	local hit = inst("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "" }, row)

	local function flip()
		config.set(key, not config.get(key))
		dot.BackgroundColor3 = config.get(key) and Palette.good or Palette.dim
		row.BackgroundColor3 = config.get(key) and Palette.rowOn or Palette.row
		if onChange then onChange(config.get(key)) end
	end

	hit.MouseButton1Click:Connect(flip)
	return row, flip
end

local function sliderRow(parent, labelText, key, low, high, onChange)
	local row = inst("Frame", {
		Size = UDim2.new(1, -10, 0, 44),
		BackgroundColor3 = Palette.row,
		BorderSizePixel = 0,
	}, parent)
	round(row, 5)

	local text = inst("TextLabel", {
		Size = UDim2.new(1, -20, 0, 18),
		Position = UDim2.fromOffset(10, 4),
		BackgroundTransparency = 1,
		Text = string.format("%s  %s", labelText, tostring(config.get(key))),
		TextColor3 = Palette.text,
		TextSize = 12,
		Font = Enum.Font.GothamMedium,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, row)

	local track = inst("Frame", {
		Size = UDim2.new(1, -20, 0, 4),
		Position = UDim2.fromOffset(10, 30),
		BackgroundColor3 = Palette.border,
		BorderSizePixel = 0,
	}, row)
	round(track, 2)

	local fill = inst("Frame", {
		Size = UDim2.fromScale((config.get(key) - low) / (high - low), 1),
		BackgroundColor3 = Palette.accent,
		BorderSizePixel = 0,
	}, track)

	local hit = inst("TextButton", { Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 20), BackgroundTransparency = 1, Text = "" }, row)

	local function apply(absoluteX)
		local left = track.AbsolutePosition.X
		local width = track.AbsoluteSize.X
		local ratio = util.clamp((absoluteX - left) / math.max(width, 1), 0, 1)
		local value = low + (high - low) * ratio
		value = math.floor(value * 10 + 0.5) / 10
		fill.Size = UDim2.fromScale(ratio, 1)
		text.Text = string.format("%s  %s", labelText, tostring(value))
		config.set(key, value)
		if onChange then onChange(value) end
	end

	hit.MouseButton1Click:Connect(function() apply(env.UserInputService:GetMouseLocation().X) end)
	return row
end

local function buttonRow(parent, labelText, callback, height)
	local button = inst("TextButton", {
		Size = UDim2.new(1, -10, 0, height or 28),
		BackgroundColor3 = Palette.row,
		BorderSizePixel = 0,
		Text = labelText,
		TextColor3 = Palette.text,
		TextSize = 13,
		Font = Enum.Font.GothamMedium,
		AutoButtonColor = true,
	}, parent)
	round(button, 5)
	button.MouseButton1Click:Connect(function()
		local ok, err = pcall(callback)
		if not ok then M.notify(tostring(err), "bad") end
	end)
	return button
end

local function inputRow(parent, placeholder, callback)
	local box = inst("TextBox", {
		Size = UDim2.new(1, -10, 0, 28),
		BackgroundColor3 = Palette.row,
		BorderSizePixel = 0,
		Text = "",
		PlaceholderText = placeholder,
		PlaceholderColor3 = Palette.dim,
		TextColor3 = Palette.text,
		TextSize = 12,
		Font = Enum.Font.Gotham,
		ClearTextOnFocus = false,
	}, parent)
	round(box, 5)
	inst("UIPadding", { PaddingLeft = UDim.new(0, 10) }, box)
	box.FocusLost:Connect(function(enterPressed)
		if enterPressed and box.Text ~= "" then callback(box.Text) end
	end)
	return box
end

local function header(parent, text)
	return inst("TextLabel", {
		Size = UDim2.new(1, -10, 0, 18),
		BackgroundTransparency = 1,
		Text = text:upper(),
		TextColor3 = Palette.dim,
		TextSize = 10,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, parent)
end

--------------------------------------------------------------------------------
-- page construction
--------------------------------------------------------------------------------

local function newPage()
	local scroll = inst("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 2,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Visible = false,
	}, M.content)
	inst("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
	pad(scroll, 10)
	return scroll
end

local function buildFishingPage()
	local page = newPage()
	header(page, "autofish")
	toggleRow(page, "Auto Cast", "autoCast")
	toggleRow(page, "Auto Reel", "autoReel")
	toggleRow(page, "Instant Reel", "instantReel")
	toggleRow(page, "Auto Rod (best in bag)", "autoRod")
	header(page, "timing")
	sliderRow(page, "Cast delay", "castDelay", 0.2, 3)
	buttonRow(page, "Reset session counters", function()
		local fishing = __require("fishing")
		fishing.casts, fishing.catches = 0, 0
		fishing.sessionStart = util.now()
		M.notify("counters reset", "good")
	end)
	return page
end

local function buildEconomyPage()
	local page = newPage()
	header(page, "automation")
	toggleRow(page, "Auto Sell", "autoSell")
	toggleRow(page, "Auto Appraise", "autoAppraise")
	toggleRow(page, "Auto Quest", "autoQuest")
	header(page, "intervals")
	sliderRow(page, "Sell every (s)", "sellInterval", 30, 600)
	sliderRow(page, "Appraise every (s)", "appraiseInterval", 60, 900)
	header(page, "manual")
	buttonRow(page, "Sell now", function()
		local ok = __require("economy").sell()
		M.notify(ok and "sell pass done" or "no vendor in range", ok and "good" or "bad")
	end)
	buttonRow(page, "Appraise now", function()
		local ok = __require("economy").appraise()
		M.notify(ok and "appraisal done" or "no appraiser in range", ok and "good" or "bad")
	end)
	return page
end

local function buildMovePage()
	local page = newPage()
	local motion = __require("motion")
	header(page, "movement")
	sliderRow(page, "Walk speed", "walkSpeed", 16, 200, function(value) motion.setSpeed(value) end)
	sliderRow(page, "Jump power", "jumpPower", 50, 300, function(value) motion.setJump(value) end)
	toggleRow(page, "Fly", "fly", function(value)
		if value then
			motion.startFly(80)
		else
			motion.stopFly()
		end
	end)
	toggleRow(page, "Noclip", "noclip", function(value) motion.setNoclip(value) end)
	toggleRow(page, "Infinite oxygen", "infOxygen")
	header(page, "teleport")
	inputRow(page, "landmark name, press enter", function(text)
		local scanner = __require("scanner")
		scanner.refresh(true)
		local target = scanner.landmark(text)
		if target then
			motion.tweenTo(target + Vector3.new(0, 5, 0))
			M.notify("tp -> " .. text, "good")
		else
			M.notify("no landmark: " .. text, "bad")
		end
	end)
	buttonRow(page, "Save waypoint", function()
		local scanner = __require("scanner")
		local root = env.Root()
		if root then
			scanner.landmarks["wp-" .. os.time()] = root.Position
			M.notify("waypoint saved", "good")
		end
	end)
	return page
end

local function buildEspPage()
	local page = newPage()
	header(page, "targets")
	toggleRow(page, "ESP master", "esp")
	toggleRow(page, "Players", "espPlayers")
	toggleRow(page, "Fish / items", "espFish")
	toggleRow(page, "NPCs", "espNpcs")
	toggleRow(page, "Chests", "espChests")
	header(page, "render")
	toggleRow(page, "Boxes", "espBoxes")
	toggleRow(page, "Labels", "espLabels")
	sliderRow(page, "Range (studs)", "espRange", 100, 2000)
	return page
end

local function buildStealthPage()
	local page = newPage()
	local stealth = __require("stealth")

	header(page, "profile")
	toggleRow(page, "Stealth master", "stealth")
	toggleRow(page, "Timing humanization", "humanize")
	header(page, "presence")
	toggleRow(page, "Hide when players can see you", "pauseOnPlayers")
	sliderRow(page, "Proximity radius (studs)", "proximityRadius", 40, 400)
	toggleRow(page, "Teleport guard", "teleportGuard")
	header(page, "pacing")
	sliderRow(page, "Catch cap (per minute)", "rateCap", 4, 30)
	sliderRow(page, "Imperfection", "imperfection", 0, 0.3)
	sliderRow(page, "Session length (min)", "sessionMinutes", 15, 180)
	sliderRow(page, "Break length (min)", "breakMinutes", 1, 30)
	header(page, "presets")
	buttonRow(page, "Apply paranoid preset", function()
		config.set("humanize", true)
		config.set("pauseOnPlayers", true)
		config.set("proximityRadius", 250)
		config.set("teleportGuard", true)
		config.set("rateCap", 9)
		config.set("imperfection", 0.12)
		config.set("sessionMinutes", 40)
		config.set("breakMinutes", 11)
		M.notify("paranoid preset applied", "good")
	end)
	buttonRow(page, "Apply normal preset", function()
		config.set("proximityRadius", 140)
		config.set("rateCap", 14)
		config.set("imperfection", 0.07)
		config.set("sessionMinutes", 55)
		config.set("breakMinutes", 7)
		M.notify("normal preset applied", "good")
	end)
	header(page, "emergency")
	buttonRow(page, "PANIC - disable everything now", function()
		stealth.engagePanic()
	end)
	buttonRow(page, "Release panic", function()
		stealth.releasePanic()
		M.notify("panic released - features stay off until re-enabled", "good")
	end)
	return page
end

local function buildMiscPage()
	local page = newPage()
	header(page, "safety")
	toggleRow(page, "Anti-AFK", "antiAfk")
	toggleRow(page, "Pause on staff", "antiMod")
	toggleRow(page, "Auto rejoin", "autoRejoin")
	buttonRow(page, "Add staff name (console)", function()
		M.notify("use getgenv().FischHub.anti.watch(name)", "good")
	end)
	header(page, "performance")
	buttonRow(page, "Strip particles", function()
		local removed = __require("anti").cleanupVisuals()
		M.notify(string.format("%d effects disabled", removed), "good")
	end)
	header(page, "diagnostics")
	buttonRow(page, "Probe remotes + prompts", function()
		local scanner = __require("scanner")
		scanner.refresh(true)
		env.log(scanner.summary())
		for _, remote in ipairs(scanner.remotes.all) do
			env.log("  remote %s", remote:GetFullName())
		end
		for kind, records in pairs(scanner.prompts) do
			for _, record in ipairs(records) do
				env.log("  prompt[%s] %s", kind, record.prompt:GetFullName())
			end
		end
		M.notify("probe written to console", "good")
	end)
	return page
end

local function buildLearnPage()
	local page = newPage()
	local learn = __require("learn")

	header(page, "remote capture")
	buttonRow(page, "Start capture", function()
		if learn.start() then
			M.notify("capturing - do one action by hand", "good")
		else
			M.notify("executor cannot hook namecall", "bad")
		end
	end)
	buttonRow(page, "Tag next as CAST", function()
		learn.tagNext("cast")
		M.notify("next remote tagged cast", "good")
	end)
	buttonRow(page, "Tag next as REEL", function()
		learn.tagNext("reel", 15)
		M.notify("next remotes tagged reel", "good")
	end)
	buttonRow(page, "Tag next as SELL", function()
		learn.tagNext("sell")
		M.notify("next remote tagged sell", "good")
	end)
	buttonRow(page, "Stop and apply", function()
		local count = learn.stop()
		local applied = learn.apply()
		local parts = {}
		for kind, name in pairs(applied) do parts[#parts + 1] = kind .. "=" .. name end
		M.notify(string.format("%d calls, %s", count, #parts > 0 and table.concat(parts, " ") or "nothing matched"),
			#parts > 0 and "good" or "bad")
	end)
	header(page, "results")
	buttonRow(page, "Dump capture to console", function()
		env.log(learn.report())
		M.notify("written to console", "good")
	end)
	buttonRow(page, "Unhook", function()
		learn.unhook()
		M.notify("unhooked", "good")
	end)
	return page
end

--------------------------------------------------------------------------------
-- shell
--------------------------------------------------------------------------------

local function tabButton(parent, text, index)
	local button = inst("TextButton", {
		Size = UDim2.fromOffset(84, 26),
		Position = UDim2.fromOffset(index * 88, 0),
		BackgroundColor3 = Palette.row,
		BorderSizePixel = 0,
		Text = text,
		TextColor3 = Palette.dim,
		TextSize = 11,
		Font = Enum.Font.GothamBold,
		LayoutOrder = index,
	}, parent)
	round(button, 4)
	return button
end

function M.select(name)
	for key, page in pairs(M.pages) do page.Visible = (key == name) end
	for key, button in pairs(M.tabs) do
		button.TextColor3 = (key == name) and Palette.accent or Palette.dim
		button.BackgroundColor3 = (key == name) and Palette.panel or Palette.row
	end
	M.current = name
end

function M.build()
	local gui = inst("ScreenGui", {
		Name = "FischHub",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 60,
	}, env.CoreGui)

	M.notifications = inst("Frame", {
		Size = UDim2.fromOffset(260, 220),
		Position = UDim2.new(1, -280, 0, 60),
		BackgroundTransparency = 1,
	}, gui)
	inst("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, M.notifications)

	local root = inst("Frame", {
		Size = UDim2.fromOffset(420, 430),
		Position = UDim2.new(0, 20, 0.5, -215),
		BackgroundColor3 = Palette.bg,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, gui)
	M.root = root
	round(root, 8)
	inst("UIStroke", { Color = Palette.border, Thickness = 1 }, root)

	local bar = inst("Frame", {
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundColor3 = Palette.panel,
		BorderSizePixel = 0,
	}, root)

	inst("TextLabel", {
		Size = UDim2.new(1, -90, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		BackgroundTransparency = 1,
		Text = "FISCH HUB",
		TextColor3 = Palette.text,
		TextSize = 12,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, bar)

	local close = inst("TextButton", {
		Size = UDim2.fromOffset(28, 32),
		Position = UDim2.new(1, -28, 0, 0),
		BackgroundTransparency = 1,
		Text = "x",
		TextColor3 = Palette.dim,
		TextSize = 14,
		Font = Enum.Font.GothamBold,
	}, bar)
	close.MouseButton1Click:Connect(function() root.Visible = false end)

	local tabBar = inst("Frame", {
		Size = UDim2.new(1, -20, 0, 26),
		Position = UDim2.fromOffset(10, 40),
		BackgroundTransparency = 1,
	}, root)

	local content = inst("Frame", {
		Size = UDim2.new(1, -20, 1, -120),
		Position = UDim2.fromOffset(10, 72),
		BackgroundTransparency = 1,
	}, root)
	M.content = content

	-- drag
	local dragging, dragStart, startPos = false, nil, nil
	bar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging, dragStart, startPos = true, input.Position, root.Position
		end
	end)
	env.UserInputService.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = input.Position - dragStart
			root.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end)
	env.UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
	end)

	local footer = inst("Frame", {
		Size = UDim2.new(1, -20, 0, 34),
		Position = UDim2.new(0, 10, 1, -44),
		BackgroundColor3 = Palette.panel,
		BorderSizePixel = 0,
	}, root)
	round(footer, 5)

	M.status = inst("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "booting",
		TextColor3 = Palette.dim,
		TextSize = 11,
		Font = Enum.Font.Code,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, footer)
	inst("UIPadding", { PaddingLeft = UDim.new(0, 10) }, M.status)

	local pages = {
		{ name = "FISH", build = buildFishingPage },
		{ name = "ECONOMY", build = buildEconomyPage },
		{ name = "MOVE", build = buildMovePage },
		{ name = "ESP", build = buildEspPage },
		{ name = "STEALTH", build = buildStealthPage },
		{ name = "LEARN", build = buildLearnPage },
		{ name = "MISC", build = buildMiscPage },
	}

	for index, spec in ipairs(pages) do
		local button = tabButton(tabBar, spec.name, index - 1)
		local page = spec.build()
		M.tabs[spec.name] = button
		M.pages[spec.name] = page
		button.MouseButton1Click:Connect(function() M.select(spec.name) end)
	end

	M.select("FISH")
	return gui
end

function M.toggle()
	if not M.root then return end
	M.root.Visible = not M.root.Visible
end

function M.hide()
	if M.root then M.root.Visible = false end
	if M.notifications then M.notifications.Visible = false end
end

function M.show()
	if M.root then M.root.Visible = true end
	if M.notifications then M.notifications.Visible = true end
end

function M.setStatus(text, tone)
	if not M.status then return end
	M.status.Text = text
	M.status.TextColor3 = (tone == "good" and Palette.good) or (tone == "bad" and Palette.bad) or Palette.dim
end

return M
