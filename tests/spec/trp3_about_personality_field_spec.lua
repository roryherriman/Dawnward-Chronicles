-- L1 (v0.10.1): the player's own personality description (a profile field)
-- is the About page's Personality section, and in Total RP 3's template 3
-- it is the personality part (PS) alone. Nothing is generated from the axes.
local Loader = require("support.loader")

return function(t, expect)
	t:describe("About page: the personality description field", function()
		t:it("is a profile field, published as its own section and as T3's personality part", function()
			local ns = Loader.WithTRP3()
			local char = ns.Schema.NewCharacter(1)
			ns.Publication.Adopt(char, 1)
			assert(ns.Character.SetField(char, "personality", "Quiet, stubborn, kind to strangers.", 2))
			ns.Personality.Set(char, "courage", 18, 3)
			local public = ns.Projection.GetPublic(char)
			local doc = ns.TRP3AboutDoc.Build(public)
			local ids = {}
			for _, s in ipairs(doc) do
				local parts = {}
				for _, ch in ipairs(s.chapters or {}) do parts[#parts + 1] = ch.body or "" end
				ids[s.id] = table.concat(parts, "\n")
			end
			expect.truthy(ids.personality and ids.personality:find("Quiet, stubborn", 1, true), "its own section")
			local t3 = ns.TRP3AboutDoc.Render(doc, 3)
			expect.truthy(t3.PS:find("Quiet, stubborn", 1, true), "T3 personality part")
			expect.falsy(t3.PH:find("Quiet", 1, true), "never in the physical description")
			-- Without the field, nothing is generated from the axes.
			char.fields.personality = nil
			local none = ns.TRP3AboutDoc.Render(ns.TRP3AboutDoc.Build(ns.Projection.GetPublic(char)), 3)
			expect.equal(none.PS, "")
		end)
	end)
end
