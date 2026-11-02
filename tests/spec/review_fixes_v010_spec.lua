-- L1/L2 (v0.10): fixes from the independent review of the v0.10 milestone.
local Loader = require("support.loader")
local Boot = require("support.boot")

return function(t, expect)
	t:describe("v0.10 review fixes", function()
		t:it("a backup restore never takes a character back to an earlier publication model", function()
			local ns = Loader.Core()
			local T = ns.Transfer
			local char = ns.Schema.NewCharacter(1)
			ns.Sources.Capture(char, "paste", "My whole story.", nil, 2) -- stored Private (the 0.9 order)
			char.publication = { mode = "profile" }
			expect.equal(ns.Publication.Status(char), "pending")
			assert(ns.Publication.Transition(char, nil, 3))
			-- A backup taken after the confirmation restores it as it was.
			local text = assert(T.Export(char, T.KIND_BACKUP))
			local decoded = assert(T.Decode(text))
			local merged = T.MergeForImport(char, decoded.character, decoded.includesSecrets, 4,
				decoded.includesBiography, decoded.includesStory)
			expect.truthy(ns.Publication.IsComplete(merged))
			expect.equal(ns.Projection.GetPublic(merged).biography.text, "My whole story.")
			expect.truthy(ns.Publication.Revert(merged, 5), "undo still works after a restore")
			-- An older backup (no model) restored over a confirmed character keeps the confirmation.
			local older = ns.Util.DeepCopy(decoded.character)
			older.publication = {}
			local kept = T.MergeForImport(char, older, true, 6, true, true)
			expect.truthy(ns.Publication.IsComplete(kept), "the model never goes backwards")
			-- A confirmed backup restored over a character still waiting brings the confirmation back.
			local waiting = ns.Util.DeepCopy(char)
			waiting.publication = { mode = "profile" }
			local back = T.MergeForImport(waiting, decoded.character, true, 7, true, true)
			expect.truthy(ns.Publication.IsComplete(back))
		end)

		t:it("a trait rename never makes two identical traits (the player's own, or two axes)", function()
			local ns = Loader.WithTRP3()
			local TraitPlan = ns.TRP3TraitPlan
			local list = { { LT = "Cautious", RT = "Bold", V2 = 5 }, { LT = "Brave", RT = "Timid", V2 = 10 } }
			local record = { owned = { courage = { LT = "Cautious", RT = "Bold", V2 = 5 } } }
			local plan = TraitPlan.Plan({ PS = ns.Util.DeepCopy(list) }, record,
				{ courage = { LT = "Brave", RT = "Timid", V2 = 5 } })
			expect.equal(plan.action, "conflict", "the player's own Brave/Timid trait is never duplicated")
			plan = TraitPlan.Plan({ PS = ns.Util.DeepCopy(list) }, record,
				{ courage = { LT = "Valiant", RT = "Wary", V2 = 5 }, honour = { LT = "Valiant", RT = "Wary", V2 = 9 } })
			expect.equal(plan.action, "conflict", "two axes with the same words")
			plan = TraitPlan.Plan({ PS = ns.Util.DeepCopy(list) }, record,
				{ courage = { LT = "Valiant", RT = "Wary", V2 = 5 } })
			expect.equal(plan.action, "write", "a free name renames in place")
			local valiant = 0
			for _, trait in ipairs(plan.characteristics.PS) do
				if trait.LT == "Valiant" then valiant = valiant + 1 end
			end
			expect.equal(valiant, 1)
			expect.equal(#plan.characteristics.PS, 2)
		end)

		t:it("an automatic upgrade never starts publishing the player's own axis words", function()
			local ns = Loader.Core()
			local char = ns.Schema.NormalizeCharacter({ publication = { mode = "profile", since = 3 },
				fields = { name = { value = "Lirael", visibility = "public" } },
				axisMeanings = { faith = { left = "Trusts no god" } } })
			expect.falsy(ns.Publication.IsComplete(char))
			expect.equal(ns.Publication.Status(char), "pending")
			expect.truthy(table.concat(ns.Publication.PreviewLines(char), "\n"):find("Your own words", 1, true))
			expect.falsy(ns.Projection.GetPublic(char).axisWords, "not published before the confirmation")
		end)

		t:it("the one-time confirmation and its undo refuse to act in simulation mode", function()
			local mock, env, ns = Boot.Start()
			mock.Slash("set name Lirael")
			local char = env.DawnwardChroniclesDB.characters["Testchar-TestRealm"]
			char.publication = {}
			char.fields.name.visibility = "private"
			ns.ctx.store:SetSimulation(true)
			local ok, message = ns.Actions.TransitionPublication(ns.ctx)
			expect.falsy(ok)
			expect.truthy(message:find("simulation", 1, true))
			expect.falsy(ns.Publication.IsComplete(char))
			expect.falsy(ns.Actions.RevertPublication(ns.ctx))
		end)

		t:it("an empty field's tile takes the mouse (a Frame's click needs EnableMouse in the client)", function()
			local mock, _, ns = Boot.Start()
			mock.Slash("set name Aelin")
			ns.MainWindow.Show(true)
			ns.MainWindow.Select("character")
			local section = ns.CharacterView.section
			local empty, set
			for _, row in ipairs(section.rows) do
				if row:IsShown() and row.spec and row.spec.kind == "field" then
					if row.emptyField and not empty then empty = row end
					if row.spec.field.key == "name" then set = row end
				end
			end
			expect.truthy(empty and empty:IsMouseEnabled(), "an empty tile is clickable")
			expect.truthy(set and not set.emptyField)
		end)
	end)
end
