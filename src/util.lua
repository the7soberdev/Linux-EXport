-- util: string matching, timers, a heartbeat scheduler, small math helpers
local env = __require("env")

local M = {}

function M.matches(name, patterns)
	if type(name) ~= "string" then return false end
	local lower = name:lower()
	for _, pattern in ipairs(patterns) do
		if lower:find(pattern, 1, true) then return true end
	end
	return false
end

function M.any(...)
	for _, value in ipairs({ ... }) do
		if value then return value end
	end
	return nil
end

function M.clamp(value, low, high)
	if value < low then return low end
	if value > high then return high end
	return value
end

function M.round(value, places)
	local factor = 10 ^ (places or 0)
	return math.floor(value * factor + 0.5) / factor
end

function M.distance(a, b)
	return (a - b).Magnitude
end

function M.now()
	return os.clock()
end

--------------------------------------------------------------------------------
-- scheduler
--
-- One heartbeat connection drives every periodic task. Each task declares an
-- interval and gets an accumulator, so a slow task cannot starve a fast one and
-- nothing spins in its own `while true do task.wait()` competing for frames.
--------------------------------------------------------------------------------

local Scheduler = { tasks = {}, index = {}, connection = nil }

function Scheduler.add(spec)
	assert(type(spec.run) == "function", "task needs a run function")
	spec.interval = spec.interval or 0.1
	spec.accumulator = spec.interval
	spec.runs = 0
	spec.errors = 0
	Scheduler.tasks[#Scheduler.tasks + 1] = spec
	if spec.name then Scheduler.index[spec.name] = spec end
	return spec
end

function Scheduler.remove(name)
	local spec = Scheduler.index[name]
	if not spec then return false end
	for i, entry in ipairs(Scheduler.tasks) do
		if entry == spec then
			table.remove(Scheduler.tasks, i)
			break
		end
	end
	Scheduler.index[name] = nil
	return true
end

function Scheduler.start()
	if Scheduler.connection then return end
	Scheduler.connection = env.RunService.Heartbeat:Connect(function(delta)
		for _, spec in ipairs(Scheduler.tasks) do
			if not spec.paused then
				spec.accumulator = spec.accumulator + delta
				if spec.accumulator >= spec.interval then
					spec.accumulator = 0
					spec.runs = spec.runs + 1
					local ok, err = pcall(spec.run)
					if not ok then
						spec.errors = spec.errors + 1
						if spec.errors <= 3 then
							env.log("task %s error: %s", spec.name or "?", tostring(err))
						end
					end
				end
			end
		end
	end)
end

function Scheduler.pause(name, paused)
	local spec = Scheduler.index[name]
	if spec then spec.paused = paused end
end

function Scheduler.stats()
	local rows = {}
	for _, spec in ipairs(Scheduler.tasks) do
		rows[#rows + 1] = string.format("%s %dms", spec.name or "?", math.floor(spec.interval * 1000))
	end
	return table.concat(rows, ", ")
end

M.scheduler = Scheduler

function M.task(name, interval, run)
	return Scheduler.add({ name = name, interval = interval, run = run })
end

function M.spawn(fn)
	local ok, err = pcall(fn)
	if not ok then env.log("spawn error: %s", tostring(err)) end
end

function M.retry(fn, attempts, delay)
	attempts = attempts or 3
	for attempt = 1, attempts do
		local ok, result = pcall(fn)
		if ok then return result end
		if attempt < attempts then task.wait(delay or 0.25) end
	end
	return nil
end

--------------------------------------------------------------------------------
-- serialization for the config file
--------------------------------------------------------------------------------

function M.serialize(value, indent)
	indent = indent or ""
	local kind = typeof(value)
	if kind == "table" then
		local parts = {}
		local keys = {}
		for key in pairs(value) do keys[#keys + 1] = key end
		table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
		for _, key in ipairs(keys) do
			local keyText = (type(key) == "string" and key:match("^[%a_][%w_]*$")) and key or ("[" .. M.serialize(key) .. "]")
			parts[#parts + 1] = indent .. "  " .. keyText .. " = " .. M.serialize(value[key], indent .. "  ")
		end
		return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
	elseif kind == "string" then
		return string.format("%q", value)
	elseif kind == "Vector3" then
		return string.format("Vector3.new(%.3f, %.3f, %.3f)", value.X, value.Y, value.Z)
	elseif kind == "boolean" or kind == "number" then
		return tostring(value)
	end
	return "nil"
end

return M
