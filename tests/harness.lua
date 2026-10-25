-- Minimal, dependency-free test harness for Lua 5.1.
--
-- We deliberately avoid busted here: its C dependencies need a compiler on
-- Windows, and the whole suite must run on the same Lua version as the WoW
-- client. Kept small enough to audit at a glance.

local Harness = {}
Harness.__index = Harness

function Harness.new(reporter)
	return setmetatable({
		passed = 0,
		failed = 0,
		failures = {},
		stack = {},
		reporter = reporter or print,
	}, Harness)
end

local function fullName(self, name)
	local parts = {}
	for i = 1, #self.stack do
		parts[#parts + 1] = self.stack[i]
	end
	parts[#parts + 1] = name
	return table.concat(parts, " > ")
end

function Harness:describe(name, fn)
	self.stack[#self.stack + 1] = name
	fn()
	self.stack[#self.stack] = nil
end

function Harness:it(name, fn)
	local label = fullName(self, name)
	-- xpcall + traceback so a failing assertion points at the test line.
	local ok, err = xpcall(fn, function(e)
		return debug.traceback(tostring(e), 2)
	end)
	if ok then
		self.passed = self.passed + 1
		self.reporter("  ok   " .. label)
	else
		self.failed = self.failed + 1
		self.failures[#self.failures + 1] = { name = label, err = err }
		self.reporter("  FAIL " .. label)
	end
end

-- Assertions -----------------------------------------------------------------

local Expect = {}
Harness.expect = Expect

local function fail(msg, level)
	error(msg, (level or 1) + 2)
end

local function describeValue(v)
	if type(v) == "string" then
		return string.format("%q", v)
	end
	return tostring(v)
end

function Expect.equal(actual, expected, msg)
	if actual ~= expected then
		fail((msg and (msg .. ": ") or "") .. "expected " .. describeValue(expected)
			.. ", got " .. describeValue(actual))
	end
end

function Expect.truthy(value, msg)
	if not value then
		fail(msg or ("expected a truthy value, got " .. describeValue(value)))
	end
end

function Expect.falsy(value, msg)
	if value then
		fail(msg or ("expected a falsy value, got " .. describeValue(value)))
	end
end

local function deepEqual(a, b, seen)
	if a == b then return true end
	if type(a) ~= "table" or type(b) ~= "table" then return false end
	seen = seen or {}
	if seen[a] == b then return true end
	seen[a] = b
	for k, v in pairs(a) do
		if not deepEqual(v, b[k], seen) then return false end
	end
	for k in pairs(b) do
		if a[k] == nil then return false end
	end
	return true
end
Harness.deepEqual = deepEqual

function Expect.deepEqual(actual, expected, msg)
	if not deepEqual(actual, expected) then
		fail(msg or "tables are not deeply equal")
	end
end

--- Asserts that fn raises an error; optionally that the message matches a Lua pattern.
function Expect.errors(fn, pattern, msg)
	local ok, err = pcall(fn)
	if ok then
		fail(msg or "expected an error, but none was raised")
	end
	if pattern and not string.find(tostring(err), pattern) then
		fail(msg or ("error " .. describeValue(tostring(err)) .. " does not match " .. describeValue(pattern)))
	end
end

function Harness:summary()
	for _, f in ipairs(self.failures) do
		self.reporter("\nFAIL " .. f.name .. "\n" .. f.err)
	end
	self.reporter(string.format("\n%d passed, %d failed", self.passed, self.failed))
	return self.failed
end

return Harness
