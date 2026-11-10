-- scanner: instance discovery, cached and diffed
local env = __require("env")
local util = __require("util")
local config = __require("config")

local P = config.patterns

local M = {
	remotes = { all = {}, cast = nil, reel = nil, sell = nil, appraise = nil },
	overrides = { cast = nil, reel = nil, sell = nil, appraise = nil },
	clickDetectors = {},
	prompts = { sell = {}, appraise = {}, quest = {}, bait = {} },
	landmarks = {},
	mapName = "",
	lastScan = 0,
	generation = 0,
}

-- Rod preference order. Higher index wins. Edit freely: the hub equips the
-- best rod in the backpack by this list, and falls through to the first rod it
-- finds when nothing matches. Ordered oldest to newest progression.
local ROD_ORDER = {
	"old rod", "flimsy rod", "training rod", "fast rod", "carbon rod",
	"lucky rod", "steady rod", "plastic rod", "river rod", "arctic rod",
	"stone rod", "fossil rod", "solar rod", "magma rod", "depth rod",
	"warrior rod", "mythic rod", "leviathan", "rod of the sea",
	"rod of the depths", "heaven's rod", "challenger's rod",
}

function M.rodRank(name)
	local lower = name:lower()
	for index, entry in ipairs(ROD_ORDER) do
		if lower:find(entry, 1, true) then return index end
	end
	return 0
end

function M.bestRod()
	local candidates = {}
	local function collect(container)
		if not container then return end
		for _, item in ipairs(container:GetChildren()) do
			if item:IsA("Tool") and util.matches(item.Name, P.rod) then
				candidates[#candidates + 1] = item
			end
		end
	end
	collect(env.LocalPlayer.Character)
	collect(env.LocalPlayer:FindFirstChildOfClass("Backpack"))

	if #candidates == 0 then return nil end
	table.sort(candidates, function(a, b)
		local rankA, rankB = M.rodRank(a.Name), M.rodRank(b.Name)
		if rankA ~= rankB then return rankA > rankB end
		return a.Name < b.Name
	end)
	return candidates[1]
end

local function scanRemotes()
	local all = {}
	local found = { cast = nil, reel = nil, sell = nil, appraise = nil }
	for _, obj in ipairs(env.ReplicatedStorage:GetDescendants()) do
		if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") or obj:IsA("UnreliableRemoteEvent") then
			all[#all + 1] = obj
			if not found.cast and util.matches(obj.Name, P.cast) then found.cast = obj end
			if not found.reel and util.matches(obj.Name, P.reel) then found.reel = obj end
			if not found.sell and util.matches(obj.Name, P.sell) then found.sell = obj end
			if not found.appraise and util.matches(obj.Name, P.appraise) then found.appraise = obj end
		end
	end
	-- Learned assignments win over name-pattern guesses and survive rescans.
	for kind, override in pairs(M.overrides) do
		if override then found[kind] = override end
	end

	M.remotes = { all = all, cast = found.cast, reel = found.reel, sell = found.sell, appraise = found.appraise }
end

function M.setRemote(kind, remote)
	M.overrides[kind] = remote
	if M.remotes[kind] ~= nil or true then
		M.remotes[kind] = remote
	end
end

local function anchorPart(prompt)
	local anchor = prompt.Parent
	local depth = 0
	while anchor and depth < 4 do
		if anchor:IsA("BasePart") then return anchor.Position end
		if anchor:IsA("Model") then
			local primary = anchor.PrimaryPart or anchor:FindFirstChildWhichIsA("BasePart", true)
			if primary then return primary.Position end
		end
		anchor = anchor.Parent
		depth = depth + 1
	end
	return nil
end

local function scanPrompts()
	local buckets = { sell = {}, appraise = {}, quest = {}, bait = {} }
	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("ProximityPrompt") then
			local ownerName = obj.Parent and obj.Parent.Name or ""
			local position = anchorPart(obj)
			local record = { prompt = obj, position = position, label = obj.ObjectText ~= "" and obj.ObjectText or obj.ActionText }
			if util.matches(obj.Name, P.sell) or util.matches(ownerName, P.sell) then
				table.insert(buckets.sell, record)
			end
			if util.matches(obj.Name, P.appraise) or util.matches(ownerName, P.appraise) then
				table.insert(buckets.appraise, record)
			end
			if util.matches(obj.Name, P.quest) or util.matches(ownerName, P.quest) then
				table.insert(buckets.quest, record)
			end
			if util.matches(obj.Name, P.bait) or util.matches(ownerName, P.bait) then
				table.insert(buckets.bait, record)
			end
		end
	end
	M.prompts = buckets
end

local function scanClickDetectors()
	local buckets = { sell = {}, appraise = {}, quest = {}, bait = {} }
	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("ClickDetector") then
			local owner = obj.Parent
			local ownerName = owner and owner.Name or ""
			local position
			if owner then
				if owner:IsA("BasePart") then
					position = owner.Position
				else
					local part = owner:FindFirstChildWhichIsA("BasePart", true)
					position = part and part.Position
				end
			end
			local record = { detector = obj, position = position, label = ownerName }
			if util.matches(obj.Name, P.sell) or util.matches(ownerName, P.sell) then
				table.insert(buckets.sell, record)
			end
			if util.matches(obj.Name, P.appraise) or util.matches(ownerName, P.appraise) then
				table.insert(buckets.appraise, record)
			end
			if util.matches(obj.Name, P.quest) or util.matches(ownerName, P.quest) then
				table.insert(buckets.quest, record)
			end
			if util.matches(obj.Name, P.bait) or util.matches(ownerName, P.bait) then
				table.insert(buckets.bait, record)
			end
		end
	end
	M.clickDetectors = buckets
end

local function scanLandmarks()
	local map = {}
	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("BasePart") and #obj.Name > 2 then
			local key = obj.Name:lower()
			if not map[key] then map[key] = obj.Position end
		elseif obj:IsA("Model") and #obj.Name > 2 then
			local key = obj.Name:lower()
			if not map[key] then
				local primary = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true)
				if primary then map[key] = primary.Position end
			end
		end
	end
	M.landmarks = map
end

local function nearest(records)
	local origin = env.Root() and env.Root().Position
	if not origin then return records[1] end
	local best, bestDistance = nil, math.huge
	for _, record in ipairs(records) do
		if record.position then
			local distance = (record.position - origin).Magnitude
			if distance < bestDistance then
				best, bestDistance = record, distance
			end
		end
	end
	return best or records[1]
end

function M.nearestPrompt(kind)
	local records = M.prompts[kind]
	if not records or #records == 0 then return nil end
	return nearest(records)
end

function M.landmark(needle)
	if not needle or needle == "" then return nil end
	local key = needle:lower()
	if M.landmarks[key] then return M.landmarks[key] end
	for name, position in pairs(M.landmarks) do
		if name:find(key, 1, true) then return position end
	end
	return nil
end

function M.refresh(force)
	local now = util.now()
	if not force and now - M.lastScan < 3 then return end
	M.lastScan = now
	M.generation = M.generation + 1

	pcall(scanRemotes)
	pcall(scanPrompts)
	pcall(scanClickDetectors)
	pcall(scanLandmarks)

	local placeId = game.PlaceId
	M.mapName = tostring(placeId)
	if game:GetService("MarketplaceService") then
		local ok, info = pcall(function() return game:GetService("MarketplaceService"):GetProductInfo(placeId) end)
		if ok and info and info.Name then M.mapName = info.Name end
	end
end

function M.summary()
	return string.format(
		"remotes:%d reel:%s cast:%s sell:%s prompts:sell%d app%d",
		#M.remotes.all,
		M.remotes.reel and M.remotes.reel.Name or "-",
		M.remotes.cast and M.remotes.cast.Name or "-",
		M.remotes.sell and M.remotes.sell.Name or "-",
		#M.prompts.sell,
		#M.prompts.appraise
	)
end

util.task("scanner", 3, function() M.refresh() end)

return M
