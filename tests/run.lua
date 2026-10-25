-- Test entry point. Usage (from the repository root):
--   lua5.1 tests/run.lua tests/spec/a_spec.lua tests/spec/b_spec.lua ...
-- tools/check.py discovers spec files and passes them in, because plain Lua
-- has no portable directory listing.
--
-- Each spec file returns function(t, expect), where t is the harness.

package.path = "./?.lua;./tests/?.lua;" .. package.path

local Harness = require("harness")
local t = Harness.new()

local runtime = _VERSION .. (jit and (" / " .. jit.version) or "")
print("Runtime: " .. runtime)

if _VERSION ~= "Lua 5.1" then
	print("Refusing to run: tests must run on Lua 5.1 (the WoW client language), got " .. _VERSION)
	os.exit(2)
end

local files = {}
for i = 1, select("#", ...) do
	files[#files + 1] = select(i, ...)
end
if #files == 0 and type(arg) == "table" then
	for i = 1, #arg do
		files[#files + 1] = arg[i]
	end
end
if #files == 0 then
	print("No spec files given.")
	os.exit(2)
end

for _, path in ipairs(files) do
	print("\n" .. path)
	local chunk, loadErr = loadfile(path)
	if not chunk then
		t.failed = t.failed + 1
		t.failures[#t.failures + 1] = { name = path, err = loadErr }
		print("  FAIL (could not load)")
	else
		local ok, spec = pcall(chunk)
		if not ok or type(spec) ~= "function" then
			t.failed = t.failed + 1
			t.failures[#t.failures + 1] = { name = path, err = ok and "spec must return a function" or spec }
			print("  FAIL (bad spec file)")
		else
			spec(t, Harness.expect)
		end
	end
end

local failed = t:summary()
os.exit(failed == 0 and 0 or 1)
