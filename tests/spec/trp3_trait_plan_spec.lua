-- L1: Dawnward-owned personality traits (pure planning; no TRP3 involved).
local Loader = require("support.loader")

return function(t, expect)
	local ns = Loader.WithTRP3()
	local TraitPlan, Util, Schema, Personality, Projection =
		ns.TRP3TraitPlan, ns.Util, ns.Schema, ns.Personality, ns.Projection

	local function characteristics()
		return { v = 4, FN = "Aelin", TI = "Knight", RA = "Human", CL = "Paladin", IC = "icon",
			PS = {
				{ ID = 1, V2 = 15 },                                         -- a preset trait
				{ LT = "Gloomy", RT = "Cheerful", V2 = 5, LI = "a", RI = "b" }, -- the player's own
			} }
	end

	local function desiredFrom(values)
		local c = Schema.NewCharacter(1)
		for axis, v in pairs(values) do
			Personality.Set(c, axis, v)
			Personality.SetVisibility(c, axis, "public")
		end
		return TraitPlan.Desired(Projection.GetPublic(c))
	end

	t:describe("TraitPlan", function()
		t:it("maps public axes only", function()
			local c = Schema.NewCharacter(1)
			Personality.Set(c, "courage", 18)
			Personality.SetVisibility(c, "courage", "public")
			Personality.Set(c, "faith", 3)
			local desired = TraitPlan.Desired(Projection.GetPublic(c))
			expect.deepEqual(desired, { courage = { LT = "Cautious", RT = "Bold", V2 = TraitPlan.ToTRP3(18) } })
		end)

		t:it("adds owned traits after existing ones and leaves everything else untouched", function()
			local original = characteristics()
			local plan = TraitPlan.Plan(Util.DeepCopy(original), nil, desiredFrom({ courage = 18, honour = 4 }))
			expect.equal(plan.action, "write")
			expect.equal(#plan.characteristics.PS, 4)
			expect.deepEqual(plan.characteristics.PS[1], original.PS[1])
			expect.deepEqual(plan.characteristics.PS[2], original.PS[2])
			expect.equal(plan.characteristics.PS[3].LT, "Cautious")
			expect.equal(plan.characteristics.PS[4].LT, "Pragmatic")
			expect.equal(plan.characteristics.FN, "Aelin")
			expect.equal(plan.characteristics.v, 4, "the planner never bumps versions itself")
			expect.deepEqual(plan.changes, { "added courage", "added honour" })
			expect.deepEqual(TraitPlan.WithoutOwned(plan.characteristics, plan.record), original)
		end)

		t:it("is a no-op when nothing changed, and updates only changed values", function()
			local first = TraitPlan.Plan(characteristics(), nil, desiredFrom({ courage = 18, honour = 4 }))
			local same = TraitPlan.Plan(Util.DeepCopy(first.characteristics), first.record,
				desiredFrom({ courage = 18, honour = 4 }))
			expect.equal(same.action, "noop")
			local changed = TraitPlan.Plan(Util.DeepCopy(first.characteristics), first.record,
				desiredFrom({ courage = 10, honour = 4 }))
			expect.equal(changed.action, "write")
			expect.deepEqual(changed.changes, { "updated courage" })
			expect.equal(changed.characteristics.PS[3].V2, TraitPlan.ToTRP3(10))
			expect.equal(changed.record.owned.courage.V2, TraitPlan.ToTRP3(10))
		end)

		t:it("removes an owned trait when its axis is no longer public, keeping positions of others", function()
			local first = TraitPlan.Plan(characteristics(), nil, desiredFrom({ courage = 18, honour = 4 }))
			local plan = TraitPlan.Plan(Util.DeepCopy(first.characteristics), first.record, desiredFrom({ honour = 4 }))
			expect.deepEqual(plan.changes, { "removed courage" })
			expect.equal(#plan.characteristics.PS, 3)
			expect.equal(plan.characteristics.PS[3].LT, "Pragmatic")
			local none = TraitPlan.Plan(Util.DeepCopy(plan.characteristics), plan.record, {})
			expect.deepEqual(none.characteristics, characteristics())
			expect.equal(none.record, nil)
		end)

		t:it("an owned trait edited, deleted or duplicated in TRP3 is a conflict", function()
			local first = TraitPlan.Plan(characteristics(), nil, desiredFrom({ courage = 18 }))
			local edited = Util.DeepCopy(first.characteristics)
			edited.PS[3].V2 = 9
			local r = TraitPlan.Plan(edited, first.record, desiredFrom({ courage = 12 }))
			expect.equal(r.action, "conflict")
			expect.truthy(r.reason:find("changed"))
			local deleted = Util.DeepCopy(first.characteristics)
			table.remove(deleted.PS, 3)
			expect.truthy(TraitPlan.Plan(deleted, first.record, {}).reason:find("removed"))
			local dup = Util.DeepCopy(first.characteristics)
			dup.PS[4] = Util.DeepCopy(dup.PS[3])
			expect.truthy(TraitPlan.Plan(dup, first.record, {}).reason:find("more than once"))
		end)

		t:it("never claims a trait the player created with the same labels", function()
			local c = characteristics()
			c.PS[3] = { LT = "Cautious", RT = "Bold", V2 = 3 }
			local r = TraitPlan.Plan(c, nil, desiredFrom({ courage = 18 }))
			expect.equal(r.action, "conflict")
			expect.truthy(r.reason:find("already exists"))
		end)

		t:it("respects the TRP3 trait limit", function()
			local r = TraitPlan.Plan(characteristics(), nil, desiredFrom({ courage = 18 }), 2)
			expect.equal(r.action, "conflict")
			expect.truthy(r.reason:find("at most 2"))
		end)
	end)
end
