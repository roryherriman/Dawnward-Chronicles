-- L1: personality axes (data model only).
local Loader = require("support.loader")

return function(t, expect)
	local ns = Loader.Core()
	local Schema, Personality, Projection, Util = ns.Schema, ns.Personality, ns.Projection, ns.Util

	t:describe("Personality", function()
		t:it("sets private values within 0-20 and refuses anything else without side effects", function()
			local c = Schema.NewCharacter(1)
			local entry = assert(Personality.Set(c, "courage", 14, 5))
			expect.equal(entry.visibility, "private")
			expect.equal(entry.value, 14)
			local before = Util.DeepCopy(c)
			expect.falsy(Personality.Set(c, "courage", 21))
			expect.falsy(Personality.Set(c, "courage", -1))
			expect.falsy(Personality.Set(c, "courage", 3.5))
			expect.falsy(Personality.Set(c, "luck", 3))
			expect.falsy(Personality.SetVisibility(c, "courage", "loud"))
			expect.falsy(Personality.SetVisibility(c, "faith", "public"))
			expect.deepEqual(c, before)
		end)

		t:it("lists in axis order and only public values reach the public projection", function()
			local c = Schema.NewCharacter(1)
			Personality.Set(c, "sociability", 3)
			Personality.Set(c, "courage", 18)
			Personality.SetVisibility(c, "courage", "public")
			local list = Personality.List(c)
			expect.equal(list[1].axis.id, "courage")
			expect.equal(list[2].axis.id, "sociability")
			local public = Projection.GetPublic(c)
			expect.equal(public.personality.courage.value, 18)
			expect.equal(public.personality.sociability, nil)
			assert(Personality.Clear(c, "courage"))
			expect.equal(c.personality.courage, nil)
		end)

		t:it("normalises stored values, dropping unknown axes and bad values", function()
			local c = Schema.NormalizeCharacter({ personality = {
				courage = { value = 12, visibility = "public" }, luck = { value = 3 },
				faith = { value = 30 }, honour = { value = 2, visibility = "everyone" },
			} })
			expect.deepEqual(c.personality, {
				courage = { value = 12, visibility = "public", updatedAt = 0 },
				honour = { value = 2, visibility = "private", updatedAt = 0 },
			})
		end)

		t:it("is driven by /dawnward personality", function()
			local store = ns.Store.new(Schema.NewDatabase(), Schema.NewDatabase())
			local lines = {}
			local ctx = { store = store, characterKey = "A-R", now = function() return 1 end,
				print = function(l) lines[#lines + 1] = l end }
			ns.Commands.Execute(ctx, "personality set courage 15")
			ns.Commands.Execute(ctx, "personality vis courage public")
			ns.Commands.Execute(ctx, "personality set luck 3")
			ns.Commands.Execute(ctx, "personality clear courage")
			local text = table.concat(lines, "\n")
			expect.truthy(text:find("courage: 15/20"), text)
			expect.truthy(text:find("unknown axis"))
			expect.truthy(text:find("confirm"))
			expect.equal(store.real.characters["A-R"].personality.courage.visibility, "public")
			lines = {}
			ns.Commands.Execute(ctx, "personality list")
			expect.truthy(table.concat(lines, "\n"):find("courage: Cautious 15/20 Bold %[public%]"))
		end)
	end)
end
