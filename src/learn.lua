-- learn: record the remotes the game actually uses
--
-- This is the module that closes the guess gap. Instead of hoping a remote is
-- named "Reel", the hub watches `__namecall` while you perform one action by
-- hand and records exactly which RemoteEvent fired, with what arguments and at
-- what rate. Press "Tag: reel" before reeling once, and the recorded remote is
-- the real one, by construction.
--
-- Hooking __namecall is deliberately isolated here: one connection, fully
-- pcall-guarded, removable, and inert until recording is switched on.
local env = __require("env")
local util = __require("util")
local config = __require("config")

local M = {
	recording = false,
	hooked = false,
	entries = {},
	counts = {},
	byTag = {},
	tag = nil,
	tagUntil = 0,
	good = false,
	MAX_ENTRIES = 400,
}

local originalNamecall = nil
local metatable = nil

--------------------------------------------------------------------------------
-- hook plumbing
--------------------------------------------------------------------------------

local function canHook()
	return typeof(getrawmetatable) == "function"
		and typeof(setreadonly) == "function"
		and typeof(getnamecallmethod) == "function"
end

local function describe(value)
	local kind = typeof(value)
	if kind == "Instance" then
		return string.format("%s(%s)", value.Name, value.ClassName)
	elseif kind == "string" then
		return string.format("%q", value:sub(1, 40))
	elseif kind == "number" or kind == "boolean" or kind == "nil" then
		return tostring(value)
	elseif kind == "Vector3" then
		return string.format("V3(%d,%d,%d)", value.X, value.Y, value.Z)
	elseif kind == "table" then
		return "table"
	end
	return kind
end

local function record(remote, method, args)
	if not M.recording then return end
	local name = remote:GetFullName()
	local now = util.now()

	local signatureParts = {}
	for index = 1, math.min(#args, 6) do
		signatureParts[#signatureParts + 1] = describe(args[index])
	end
	local signature = table.concat(signatureParts, ",")

	local entry = {
		name = name,
		remote = remote,
		method = method,
		time = now,
		argc = #args,
		signature = signature,
		tag = (M.tag and now <= M.tagUntil) and M.tag or nil,
	}

	M.entries[#M.entries + 1] = entry
	if #M.entries > M.MAX_ENTRIES then table.remove(M.entries, 1) end

	local stat = M.counts[name]
	if not stat then
		stat = { name = name, remote = remote, count = 0, first = now, last = now, tags = {}, signatures = {} }
		M.counts[name] = stat
	end
	stat.count = stat.count + 1
	stat.last = now
	stat.remote = remote
	if entry.tag then
		stat.tags[entry.tag] = (stat.tags[entry.tag] or 0) + 1
		M.byTag[entry.tag] = M.byTag[entry.tag] or {}
		M.byTag[entry.tag][name] = (M.byTag[entry.tag][name] or 0) + 1
	end
	if signature ~= "" then
		stat.signatures[signature] = (stat.signatures[signature] or 0) + 1
	end
	return entry
end

function M.hook()
	if M.hooked then return true end
	if not canHook() then
		env.log("executor cannot hook __namecall - learning disabled")
		return false
	end

	local ok, err = pcall(function()
		metatable = getrawmetatable(game)
		originalNamecall = metatable.__namecall
		setreadonly(metatable, false)

		metatable.__namecall = function(self, ...)
			local method = getnamecallmethod()
			if M.recording and (method == "FireServer" or method == "InvokeServer") then
				pcall(record, self, method, { ... })
			end
			return originalNamecall(self, ...)
		end

		setreadonly(metatable, true)
	end)

	if not ok then
		env.log("hook failed: %s", tostring(err))
		pcall(function() if metatable then setreadonly(metatable, true) end end)
		return false
	end

	M.hooked = true
	return true
end

function M.unhook()
	if not M.hooked or not metatable then return end
	pcall(function()
		setreadonly(metatable, false)
		metatable.__namecall = originalNamecall
		setreadonly(metatable, true)
	end)
	M.hooked = false
	M.recording = false
end

--------------------------------------------------------------------------------
-- session control
--------------------------------------------------------------------------------

function M.start()
	M.entries = {}
	M.counts = {}
	M.byTag = {}
	M.tag = nil
	M.recording = true
	return M.hook()
end

function M.stop()
	M.recording = false
	return #M.entries
end

function M.tagNext(label, seconds)
	M.tag = label
	M.tagUntil = util.now() + (seconds or 8)
	return true
end

--------------------------------------------------------------------------------
-- analysis
--------------------------------------------------------------------------------

function M.bestForTag(label)
	local bucket = M.byTag[label]
	if not bucket then return nil, 0 end

	local bestName, bestCount = nil, 0
	for name, count in pairs(bucket) do
		if count > bestCount then bestName, bestCount = name, count end
	end
	if not bestName then return nil, 0 end

	local stat = M.counts[bestName]
	return stat and stat.remote or nil, bestCount
end

-- A reel remote is fired many times per second; a cast or sell remote fires
-- once per action. Rate separates them without any naming convention.
function M.classify()
	local ranked = {}
	for _, stat in pairs(M.counts) do
		local span = math.max(stat.last - stat.first, 0.001)
		stat.rate = stat.count / span
		ranked[#ranked + 1] = stat
	end
	table.sort(ranked, function(a, b) return a.rate > b.rate end)

	local reel, cast
	for _, stat in ipairs(ranked) do
		if stat.count >= 4 and stat.rate >= 2 and not reel then
			reel = stat
		elseif stat.count >= 1 and stat.rate < 2 and not cast then
			cast = stat
		end
	end
	return ranked, reel, cast
end

function M.report()
	local ranked = M.classify()
	local lines = { string.format("%d remotes recorded", #ranked) }
	for index, stat in ipairs(ranked) do
		if index > 8 then break end
		lines[#lines + 1] = string.format("  %.2f/s  x%-4d %s", stat.rate, stat.count, stat.name)
	end
	return table.concat(lines, "\n")
end

function M.apply()
	local scanner = __require("scanner")
	local ranked, reel, cast = M.classify()
	local applied = {}

	local reelTag = M.bestForTag("reel")
	if reelTag then scanner.remotes.reel = reelTag; applied.reel = reelTag.Name end
	local castTag = M.bestForTag("cast")
	if castTag then scanner.remotes.cast = castTag; applied.cast = castTag.Name end
	local sellTag = M.bestForTag("sell")
	if sellTag then scanner.remotes.sell = sellTag; applied.sell = sellTag.Name end

	if not applied.reel and reel then
		scanner.remotes.reel = reel.remote
		applied.reel = reel.name
	end
	if not applied.cast and cast then
		scanner.remotes.cast = cast.remote
		applied.cast = cast.name
	end

	M.good = applied.reel ~= nil
	config.save()
	return applied
end

return M
