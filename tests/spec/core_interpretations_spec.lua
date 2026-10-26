-- L1: proposals (interpretations), keys and promotion.
local Loader = require("support.loader")

return function(t, expect)
	local ns = Loader.CoreUpTo("Interpretations")
	local Schema, Interpretations, Sources, Util = ns.Schema, ns.Interpretations, ns.Sources, ns.Util

	local function proposal(statement, extra)
		local values = { kind = "candidate", category = "fear", statement = statement, origin = "paste" }
		for k, v in pairs(extra or {}) do values[k] = v end
		return values
	end

	t:describe("Interpretations.Key", function()
		t:it("normalises case, spaces and punctuation", function()
			local a = Interpretations.Key("paste", "fear", "Fears the  SEA!")
			expect.equal(a, "paste:fear:fears the sea")
			expect.equal(Interpretations.Key("paste", "fear", " fears, the sea. "), a)
			expect.truthy(Interpretations.Key("trp3-biography", "fear", "Fears the sea") ~= a, "origin is part of the key")
			expect.truthy(Interpretations.Key("paste", "trait", "Fears the sea") ~= a, "category is part of the key")
		end)

		t:it("stays bounded and distinct for long statements", function()
			local base = string.rep("word ", 70)
			local a = Interpretations.Key("paste", "event", base .. "alpha")
			local b = Interpretations.Key("paste", "event", base .. "beta")
			expect.truthy(a ~= b)
			expect.truthy(Schema.IsInterpretationKey(a))
			expect.truthy(#a <= Schema.FOUNDATION.keyBytes)
		end)
	end)

	t:describe("Interpretations", function()
		t:it("proposes private suggestions and refuses known keys", function()
			local c = Schema.NewCharacter(1)
			local item = assert(Interpretations.Propose(c, proposal("Fears the sea."), 5))
			expect.equal(item.visibility, "private")
			expect.equal(item.status, "open")
			expect.equal(Interpretations.Status(c, item.key), "open")
			local again, err = Interpretations.Propose(c, proposal("fears the SEA"))
			expect.falsy(again)
			expect.equal(err, "known")
			expect.equal(#Interpretations.Open(c), 1)
		end)

		t:it("refuses invalid input with no side effects", function()
			local c = Schema.NewCharacter(1)
			local before = Util.DeepCopy(c)
			expect.falsy(Interpretations.Propose(c, proposal("x", { kind = "guess" })))
			expect.falsy(Interpretations.Propose(c, proposal("x", { category = "hobby" })))
			expect.falsy(Interpretations.Propose(c, proposal("x", { origin = "rumour" })))
			expect.falsy(Interpretations.Propose(c, proposal("x", { visibility = "loud" })))
			expect.falsy(Interpretations.Propose(c, proposal("   ")))
			expect.deepEqual(c, before)
		end)

		t:it("rejecting remembers the key so it is never suggested again", function()
			local c = Schema.NewCharacter(1)
			local item = assert(Interpretations.Propose(c, proposal("Fears the sea.")))
			assert(Interpretations.Reject(c, item.key, 9))
			expect.equal(#Interpretations.Open(c), 0)
			expect.deepEqual(c.interpretationKeys[item.key], { status = "rejected", at = 9 })
			expect.equal(select(2, Interpretations.Propose(c, proposal("Fears the sea."))), "known")
			expect.falsy(Interpretations.Reject(c, item.key))
		end)

		t:it("an unchanged re-import creates no duplicates", function()
			local c = Schema.NewCharacter(1)
			local statements = { "Fears the sea.", "Distrusts nobles.", "Lost a brother." }
			for _, s in ipairs(statements) do assert(Interpretations.Propose(c, proposal(s))) end
			Interpretations.Reject(c, Interpretations.Open(c)[1].key)
			Interpretations.Promote(c, Interpretations.Open(c)[1].key)
			local added = 0
			for _, s in ipairs(statements) do
				if Interpretations.Propose(c, proposal(s)) then added = added + 1 end
			end
			expect.equal(added, 0)
			expect.equal(#Interpretations.Open(c), 1)
			expect.equal(#c.facts, 1)
		end)

		t:it("promotes with the player's edits and full provenance", function()
			local c = Schema.NewCharacter(1)
			local source = Sources.Capture(c, "trp3", "She fears the sea. She grew up inland.", { profile = "A" }, 2)
			local item = assert(Interpretations.Propose(c, proposal("Fears the sea.", {
				origin = "trp3-biography", sourceId = source.id, sourceVersion = source.hash, ref = "p1.s1",
				excerpt = "She fears the sea.",
			})))
			local fact = assert(Interpretations.Promote(c, item.key,
				{ statement = "Fears deep water since childhood.", visibility = "public" }, 20))
			expect.equal(fact.statement, "Fears deep water since childhood.")
			expect.equal(fact.category, "fear")
			expect.equal(fact.visibility, "public")
			expect.deepEqual(fact.provenance, {
				origin = "trp3-biography", sourceId = source.id, sourceVersion = source.hash, ref = "p1.s1",
				excerpt = "She fears the sea.", interpreted = true, interpretationKey = item.key,
			})
			expect.equal(Interpretations.Status(c, item.key), "promoted")
			expect.equal(#Interpretations.Open(c), 0)
		end)

		t:it("a failed promotion changes nothing", function()
			local c = Schema.NewCharacter(1)
			local item = assert(Interpretations.Propose(c, proposal("Fears the sea.")))
			local before = Util.DeepCopy(c)
			expect.falsy(Interpretations.Promote(c, item.key, { category = "hobby" }))
			expect.falsy(Interpretations.Promote(c, item.key, { visibility = "loud" }))
			for i = 1, Schema.FOUNDATION.facts do
				c.facts[i] = { id = 100 + i }
			end
			expect.falsy(Interpretations.Promote(c, item.key))
			c.facts = {}
			expect.deepEqual(c, before)
		end)

		t:it("stops proposing at 300 open suggestions", function()
			local c = Schema.NewCharacter(1)
			for i = 1, Schema.FOUNDATION.pending do
				assert(Interpretations.Propose(c, proposal("statement " .. i)))
			end
			local item, err = Interpretations.Propose(c, proposal("one more"))
			expect.falsy(item)
			expect.equal(err, "full")
			expect.equal(#Interpretations.Open(c), Schema.FOUNDATION.pending)
		end)

		t:it("key memory keeps 1,000 keys, dropping the oldest first", function()
			local c = Schema.NewCharacter(1)
			for i = 1, Schema.FOUNDATION.keyMemory + 2 do
				local item = assert(Interpretations.Propose(c, proposal("statement " .. i)))
				Interpretations.Reject(c, item.key, i)
			end
			expect.equal(Util.CountKeys(c.interpretationKeys), Schema.FOUNDATION.keyMemory)
			expect.equal(Interpretations.Status(c, Interpretations.Key("paste", "fear", "statement 1")), nil)
			expect.equal(Interpretations.Status(c, Interpretations.Key("paste", "fear", "statement 3")), "rejected")
		end)
	end)
end
