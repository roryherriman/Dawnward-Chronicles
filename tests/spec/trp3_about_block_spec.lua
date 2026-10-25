-- L1: Dawnward-owned About content (pure planning; no TRP3 involved).
local Loader = require("support.loader")

return function(t, expect)
	local ns = Loader.WithTRP3()
	local AboutBlock, Util, Facts, Schema, Projection = ns.TRP3AboutBlock, ns.Util, ns.Facts, ns.Schema, ns.Projection

	local function about(te, extra)
		local a = { v = 7, TE = te, BK = 3, MU = "music",
			T1 = { TX = "{h1}My story{/h1}\nPlayer prose." },
			T2 = { { TX = "Frame one", IC = "Ability_X", BK = 2 } },
			T3 = { PH = { TX = "Tall" }, PS = { TX = "Kind" }, HI = { TX = "Born somewhere.", IC = "I", BK = 1 } } }
		for k, v in pairs(extra or {}) do a[k] = v end
		return a
	end

	t:describe("AboutBlock.Compose", function()
		t:it("uses public facts only, in category order, and escapes braces", function()
			local c = Schema.NewCharacter(1)
			Facts.Add(c, { category = "belief", statement = "Protect the {weak}", visibility = "public" })
			Facts.Add(c, { category = "origin", statement = "Born in Stormwind", visibility = "public" })
			Facts.Add(c, { category = "fear", statement = "PRIVATE fear" })
			Facts.Add(c, { category = "fear", statement = "SECRET fear", visibility = "secret" })
			local block = AboutBlock.Compose(Projection.GetPublic(c))
			expect.equal(block, "{h3}Chronicle{/h3}\nOrigin: Born in Stormwind\nBelief: Protect the (weak)")
			expect.equal(AboutBlock.Compose(Projection.GetPublic(Schema.NewCharacter(1))), "")
		end)

		t:it("never exceeds the size cap and says how much was left out", function()
			local facts = {}
			for i = 1, 200 do
				facts[i] = { category = "event", statement = string.rep("x", 290) .. i, visibility = "public" }
			end
			local block = AboutBlock.Compose({ facts = facts })
			expect.truthy(#block <= AboutBlock.MAX_BYTES)
			expect.truthy(block:find("more in the character's chronicle"))
		end)
	end)

	t:describe("AboutBlock.Plan", function()
		for _, te in ipairs({ 1, 3 }) do
			local field = te == 1 and function(a) return a.T1.TX end or function(a) return a.T3.HI.TX end
			t:it("template " .. te .. ": inserts, replaces, no-ops and removes only the owned block", function()
				local original = about(te)
				local before = field(original)
				local plan = AboutBlock.Plan(Util.DeepCopy(original), nil, "BLOCK one")
				expect.equal(plan.action, "insert")
				expect.equal(field(plan.about), before .. "\n\nBLOCK one")
				expect.deepEqual(plan.record, { block = "\n\nBLOCK one", template = te })
				-- Everything else is untouched.
				local rest = Util.DeepCopy(plan.about)
				if te == 1 then rest.T1.TX = before else rest.T3.HI.TX = before end
				expect.deepEqual(rest, original)

				local same = AboutBlock.Plan(Util.DeepCopy(plan.about), plan.record, "BLOCK one")
				expect.equal(same.action, "noop")

				local changed = AboutBlock.Plan(Util.DeepCopy(plan.about), plan.record, "BLOCK two")
				expect.equal(changed.action, "replace")
				expect.equal(field(changed.about), before .. "\n\nBLOCK two")

				local removed = AboutBlock.Plan(Util.DeepCopy(changed.about), changed.record, "")
				expect.equal(removed.action, "remove")
				expect.equal(field(removed.about), before, "the player's text is restored byte for byte")
				expect.equal(removed.record, nil)
			end)
		end

		t:it("template 1: inserts without a separator into empty text", function()
			local plan = AboutBlock.Plan({ v = 1, TE = 1 }, nil, "BLOCK")
			expect.equal(plan.about.T1.TX, "BLOCK")
			expect.equal(plan.record.block, "BLOCK")
			local again = AboutBlock.Plan(Util.DeepCopy(plan.about), plan.record, "NEW")
			expect.equal(again.about.T1.TX, "NEW")
		end)

		t:it("player text after the block is preserved on replace", function()
			local a = about(1)
			local plan = AboutBlock.Plan(a, nil, "BLOCK")
			plan.about.T1.TX = plan.about.T1.TX .. "\nAdded later by the player."
			local changed = AboutBlock.Plan(Util.DeepCopy(plan.about), plan.record, "BLOCK v2")
			expect.equal(changed.action, "replace")
			expect.truthy(changed.about.T1.TX:find("BLOCK v2\nAdded later by the player.", 1, true))
		end)

		t:it("an edited, removed or duplicated block is a conflict and nothing is planned", function()
			local plan = AboutBlock.Plan(about(1), nil, "BLOCK")
			local edited = Util.DeepCopy(plan.about)
			edited.T1.TX = edited.T1.TX:gsub("BLOCK", "BLOCK (tweaked)")
			local r = AboutBlock.Plan(edited, plan.record, "NEW")
			expect.equal(r.action, "conflict")
			expect.truthy(r.reason:find("edited or removed"))
			expect.equal(r.about, nil)

			local twice = Util.DeepCopy(plan.about)
			twice.T1.TX = twice.T1.TX .. "\n" .. twice.T1.TX
			expect.equal(AboutBlock.Plan(twice, plan.record, "NEW").action, "conflict")
		end)

		t:it("a changed template is a conflict", function()
			local plan = AboutBlock.Plan(about(1), nil, "BLOCK")
			local switched = Util.DeepCopy(plan.about)
			switched.TE = 2
			local r = AboutBlock.Plan(switched, plan.record, "NEW")
			expect.equal(r.action, "conflict")
			expect.truthy(r.reason:find("template"))
		end)

		t:it("template 2: owns one whole frame", function()
			local original = about(2)
			local plan = AboutBlock.Plan(Util.DeepCopy(original), nil, "BLOCK")
			expect.equal(plan.action, "insert")
			expect.equal(#plan.about.T2, 2)
			expect.deepEqual(plan.about.T2[1], original.T2[1])
			expect.equal(plan.about.T2[2].TX, "BLOCK")
			local changed = AboutBlock.Plan(Util.DeepCopy(plan.about), plan.record, "NEW")
			expect.equal(changed.action, "replace")
			expect.equal(changed.about.T2[2].TX, "NEW")
			expect.equal(changed.about.T2[2].IC, AboutBlock.FRAME_ICON, "frame layout is kept")
			expect.equal(AboutBlock.Plan(Util.DeepCopy(changed.about), changed.record, "NEW").action, "noop")
			local removed = AboutBlock.Plan(Util.DeepCopy(changed.about), changed.record, "")
			expect.deepEqual(removed.about, original)
			local gone = Util.DeepCopy(changed.about)
			gone.T2[2].TX = "player rewrote it"
			expect.equal(AboutBlock.Plan(gone, changed.record, "X").action, "conflict")
		end)

		t:it("nothing to write and nothing owned is a no-op; unknown templates are unsupported", function()
			expect.equal(AboutBlock.Plan(about(1), nil, "").action, "noop")
			expect.equal(AboutBlock.Plan(about(9), nil, "X").action, "unsupported")
			expect.equal(AboutBlock.Plan(about(1), nil, string.rep("x", AboutBlock.MAX_BYTES + 1)).action, "unsupported")
		end)
	end)
end
