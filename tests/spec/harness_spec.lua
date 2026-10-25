-- Self-test: a harness that cannot report failure is worse than none.

local Harness = require("harness")

local function silentHarness()
	return Harness.new(function() end)
end

return function(t, expect)
	t:describe("harness", function()
		t:it("counts passing and failing tests", function()
			local h = silentHarness()
			h:it("passes", function() end)
			h:it("fails", function() error("boom") end)
			expect.equal(h.passed, 1)
			expect.equal(h.failed, 1)
			expect.truthy(h.failures[1].err:find("boom"))
		end)

		t:it("prefixes nested describe names", function()
			local h = silentHarness()
			h:describe("outer", function()
				h:describe("inner", function()
					h:it("case", function() error("x") end)
				end)
			end)
			expect.equal(h.failures[1].name, "outer > inner > case")
		end)

		t:it("equal reports both values on mismatch", function()
			local ok, err = pcall(expect.equal, 1, 2)
			expect.falsy(ok)
			expect.truthy(tostring(err):find("expected 2, got 1"))
		end)

		t:it("deepEqual compares nested tables both ways", function()
			expect.truthy(Harness.deepEqual({ a = { 1, 2 } }, { a = { 1, 2 } }))
			expect.falsy(Harness.deepEqual({ a = 1 }, { a = 1, b = 2 }))
			expect.falsy(Harness.deepEqual({ a = 1, b = 2 }, { a = 1 }))
		end)

		t:it("errors() matches the message pattern", function()
			expect.errors(function() error("bad input") end, "bad input")
			local ok = pcall(expect.errors, function() end)
			expect.falsy(ok, "errors() must fail when nothing is raised")
		end)
	end)
end
