-- Guards against silently running the suite on the wrong Lua dialect.
-- WoW runs a modified PUC Lua 5.1; Lua 5.2+ features must not slip into tests.

return function(t, expect)
	t:describe("test runtime", function()
		t:it("is Lua 5.1", function()
			expect.equal(_VERSION, "Lua 5.1")
		end)

		t:it("has 5.1 globals and lacks 5.2+ ones", function()
			expect.truthy(unpack, "unpack should be global in 5.1")
			expect.truthy(loadstring, "loadstring should exist in 5.1")
			expect.falsy(rawget(table, "unpack"), "table.unpack is 5.2+")
			expect.falsy(rawget(_G, "utf8"), "utf8 library is 5.3+")
		end)

		t:it("rejects 5.3 integer division syntax", function()
			expect.falsy(loadstring("return 7 // 2"))
		end)

		t:it("rejects goto on PUC Lua 5.1 (LuaJIT accepts it, WoW does not)", function()
			if jit then
				return -- LuaJIT extension; PUC 5.1 is the reference runtime
			end
			expect.falsy(loadstring("goto done ::done::"))
		end)
	end)
end
