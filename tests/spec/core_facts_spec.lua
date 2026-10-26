-- L1: canon facts.
local Loader = require("support.loader")

return function(t, expect)
	local ns = Loader.CoreUpTo("Interpretations")
	local Schema, Facts = ns.Schema, ns.Facts

	local function newChar()
		return Schema.NewCharacter(1)
	end

	t:describe("Facts", function()
		t:it("adds private player facts with provenance and a shared ID", function()
			local c = newChar()
			c.nextId = 5
			local fact = assert(Facts.Add(c, { category = "belief", statement = "  Protect the weak.  " }, nil, 10))
			expect.equal(fact.id, 5)
			expect.equal(c.nextId, 6)
			expect.equal(fact.statement, "Protect the weak.")
			expect.equal(fact.visibility, "private")
			expect.deepEqual(fact.provenance, { origin = "player", interpreted = false })
			expect.equal(fact.createdAt, 10)
			expect.equal(c.updatedAt, 10)
			expect.equal(Facts.Count(c), 1)
		end)

		t:it("never marks a player fact as interpreted", function()
			local c = newChar()
			local fact = assert(Facts.Add(c, { category = "trait", statement = "Brave" },
				{ origin = "written", interpreted = true, interpretationKey = "x" }))
			expect.equal(fact.provenance.origin, "written")
			expect.falsy(fact.provenance.interpreted)
			expect.equal(fact.provenance.interpretationKey, nil)
		end)

		t:it("refuses invalid categories, visibility, statements and provenance with no side effects", function()
			local c = newChar()
			local before = ns.Util.DeepCopy(c)
			expect.falsy(Facts.Add(c, { category = "hobby", statement = "x" }))
			expect.falsy(Facts.Add(c, { category = "future_kind", statement = "x" }), "new facts need a registered category")
			expect.falsy(Facts.Add(c, { category = "fear", statement = "x", visibility = "everyone" }))
			expect.falsy(Facts.Add(c, { category = "fear", statement = " |r " }))
			expect.falsy(Facts.Add(c, { category = "fear", statement = "x" }, { origin = "aliens" }))
			expect.deepEqual(c, before)
		end)

		t:it("cleans and caps statements", function()
			local c = newChar()
			local fact = assert(Facts.Add(c, { category = "event", statement = "|cffff0000Red|r " .. string.rep("x", 400) }))
			expect.equal(fact.statement:sub(1, 4), "Red ")
			expect.equal(#fact.statement, Schema.FOUNDATION.statement)
		end)

		t:it("refuses beyond the limit and never removes canon to make room", function()
			local c = newChar()
			for i = 1, Schema.FOUNDATION.facts do
				assert(Facts.Add(c, { category = "event", statement = "fact " .. i }))
			end
			local fact, err = Facts.Add(c, { category = "event", statement = "one more" })
			expect.falsy(fact)
			expect.truthy(err:find("limit"))
			expect.equal(Facts.Count(c), Schema.FOUNDATION.facts)
			expect.equal(c.facts[1].statement, "fact 1")
		end)

		t:it("updates, changes visibility and removes", function()
			local c = newChar()
			local fact = assert(Facts.Add(c, { category = "fear", statement = "Deep water" }))
			assert(Facts.Update(c, fact.id, { statement = "Deep, dark water", subject = "the sea" }, 20))
			expect.equal(fact.statement, "Deep, dark water")
			expect.equal(fact.subject, "the sea")
			expect.equal(fact.updatedAt, 20)
			expect.falsy(Facts.Update(c, fact.id, { statement = "" }))
			expect.falsy(Facts.Update(c, fact.id, { category = "nope" }))
			expect.equal(fact.statement, "Deep, dark water")
			assert(Facts.SetVisibility(c, fact.id, "public"))
			expect.equal(fact.visibility, "public")
			expect.falsy(Facts.SetVisibility(c, fact.id, "loud"))
			expect.falsy(Facts.SetVisibility(c, 99, "public"))
			assert(Facts.Remove(c, fact.id))
			expect.equal(Facts.Count(c), 0)
			expect.falsy(Facts.Remove(c, fact.id))
		end)

		t:it("groups by category in registry order, showing unknown categories as Other", function()
			local c = Schema.NormalizeCharacter({ facts = {
				{ id = 1, category = "place", statement = "Goldshire" },
				{ id = 2, category = "future_kind", statement = "From a newer build" },
				{ id = 3, category = "origin", statement = "Born in Stormwind" },
				{ id = 4, category = "place", statement = "Lakeshire" },
				{ id = 5, category = "other", statement = "Likes tea" },
			} })
			local groups = Facts.ByCategory(c)
			local labels = {}
			for _, g in ipairs(groups) do labels[#labels + 1] = g.category.id .. "=" .. #g.facts end
			expect.deepEqual(labels, { "origin=1", "place=2", "other=2" })
			expect.equal(groups[2].facts[1].statement, "Goldshire")
			expect.equal(groups[3].facts[1].category, "future_kind", "the stored category is kept")
			expect.equal(Facts.DisplayCategory("future_kind").label, "Other")
		end)

		t:it("only accepts interpreted facts with an interpretation key", function()
			local c = newChar()
			expect.falsy(Facts.AddFromInterpretation(c, { category = "fear", statement = "x" }, { origin = "paste" }))
			local fact = assert(Facts.AddFromInterpretation(c, { category = "fear", statement = "x" },
				{ origin = "paste", interpretationKey = "paste:fear:x" }))
			expect.truthy(fact.provenance.interpreted)
		end)
	end)
end
