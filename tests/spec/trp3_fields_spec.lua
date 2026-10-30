-- L2: automatic sync of profile fields, ownership policies, differences and
-- import, visibility-aware rollback, against the TRP3 3.4.1 fake (mocked;
-- not in-game evidence).
local Loader = require("support.loader")
local Fake = require("fakes.trp3_341")

return function(t, expect)
	local KEY = "Testchar-TestRealm"

	local function world(fakeOpts)
		local ns = Loader.WithTRP3()
		local fake = Fake.new(fakeOpts or {})
		local store = ns.Store.new(ns.Schema.NewDatabase(), ns.Schema.NewDatabase())
		local clock = 1000
		local combat = false
		local deps = {
			env = fake.env, ledger = ns.TRP3Ledger.New(), store = store, characterKey = KEY,
			now = function() clock = clock + 1; return clock end,
			inCombat = function() return combat end,
		}
		local w = { ns = ns, fake = fake, deps = deps, store = store, Sync = ns.TRP3Sync }
		function w.char()
			return assert(store:EnsureCharacter(KEY, 1))
		end
		function w.field(key, value, level)
			assert(ns.Character.SetField(w.char(), key, value, 1))
			assert(ns.Character.SetFieldVisibility(w.char(), key, level or "public", 1))
		end
		function w.publicFact(category, statement)
			return ns.Facts.Add(w.char(), { category = category, statement = statement, visibility = "public" })
		end
		function w.manage(...)
			for _, id in ipairs({ ... }) do
				assert(w.Sync.SetPolicy(deps, id, "dawnward"))
			end
		end
		function w.ch() return fake.profile.player.characteristics end
		function w.setCombat(v) combat = v end
		function w.ctx()
			return { store = store, characterKey = KEY, now = deps.now, trp3Deps = function() return deps end,
				print = function() end }
		end
		return w
	end

	t:describe("TRP3 field plan (pure)", function()
		t:it("cleans values so TRP3's sanitiser leaves them unchanged", function()
			local FieldPlan = Loader.WithTRP3().TRP3FieldPlan
			expect.equal(FieldPlan.Clean("  Half-elf  "), "Half-elf")
			expect.equal(FieldPlan.Clean("|cffff0000Red|r  title"), "cffff0000Redr title")
			expect.equal(FieldPlan.Clean("two\nlines"), "two lines")
			expect.equal(FieldPlan.Clean("   "), nil)
			expect.equal(FieldPlan.Clean(string.rep("x", 101)), nil, "never shortened")
			for _, v in ipairs({ "Sir", "Knight of the Silver Hand", "Elf" }) do
				expect.equal(FieldPlan.Clean(FieldPlan.Clean(v)), FieldPlan.Clean(v), "idempotent")
			end
		end)

		t:it("plans only Dawnward-managed fields and never claims matching text", function()
			local FieldPlan = Loader.WithTRP3().TRP3FieldPlan
			local ch = { v = 1, RA = "Elf", AG = "30" }
			local plan = FieldPlan.Plan(ch, nil, { race = "Elf", age = "31", class = "Paladin" },
				{ race = "dawnward", age = "dawnward", class = "trp3" }, {})
			local states = {}
			for _, row in ipairs(plan.rows) do states[row.id] = row.state end
			expect.deepEqual(states, { race = "matches", age = "conflict" })
			expect.equal(plan.action, "noop")
			expect.equal(ch.CL, nil, "a trp3 field is never written")
			expect.equal(plan.record, nil, "matching text is not ownership")
			expect.truthy(plan.conflicts.age:find("already has your own value", 1, true))
		end)
	end)

	t:describe("TRP3 sync: profile fields (L2)", function()
		t:it("writes nothing for any field until the player authorises it (default: managed by TRP3)", function()
			local w = world()
			w.field("race", "Elf")
			w.field("age", "31")
			local before = w.fake.snapshot()
			expect.equal(w.ns.TRP3Ledger.Policy(nil, "race"), "trp3")
			expect.deepEqual(w.Sync.Run(w.deps), {})
			expect.equal(w.Sync.Check(w.deps, "fields").state, "off")
			-- An explicit "off" or "trp3" writes nothing either.
			assert(w.Sync.SetPolicy(w.deps, "race", "off"))
			assert(w.Sync.SetPolicy(w.deps, "age", "trp3"))
			expect.deepEqual(w.Sync.Run(w.deps), {})
			expect.deepEqual(w.fake.snapshot(), before)
			expect.equal(#w.fake.events, 0)
			expect.equal(#w.fake.setterCalls, 0)
		end)

		t:it("writes an authorised Public field to its TRP3 key, backs up, bumps, notifies and reads back", function()
			local w = world()
			w.field("race", "Elf")
			w.field("homeland", "Goldshire")
			w.field("class", "Paladin") -- not authorised: stays TRP3's
			w.manage("race", "homeland")
			local r = w.Sync.Run(w.deps)
			expect.equal(#r, 1)
			expect.equal(r[1].state, "written", r[1].message)
			expect.equal(w.ch().RA, "Elf")
			expect.equal(w.ch().BP, "Goldshire")
			expect.equal(w.ch().CL, nil)
			expect.equal(w.ch().FN, "Aelin", "other characteristics untouched")
			expect.equal(w.ch().v, 5, "bumped two steps from 3")
			local e = w.fake.events[#w.fake.events]
			expect.deepEqual(e.args, { KEY, w.fake.profileId, "characteristics" })
			expect.equal(#w.deps.ledger.backups, 1)
			expect.equal(w.deps.ledger.backups[1].ownerFeature, "fields")
			expect.deepEqual(w.deps.ledger.profiles[w.fake.profileId].fields,
				{ race = { value = "Elf" }, homeland = { value = "Goldshire" } })
			expect.equal(#w.fake.setterCalls, 0)
		end)

		t:it("a no-op writes nothing: no backup, no version bump, no event", function()
			local w = world()
			w.field("age", "31")
			w.manage("age")
			w.Sync.Run(w.deps)
			local v, events, backups = w.ch().v, #w.fake.events, #w.deps.ledger.backups
			expect.equal(w.Sync.Run(w.deps)[1].state, "noop")
			expect.equal(w.ch().v, v)
			expect.equal(#w.fake.events, events)
			expect.equal(#w.deps.ledger.backups, backups)
		end)

		t:it("follows Dawnward's changes, and takes its value back out when it stops being Public", function()
			local w = world()
			w.field("title", "Squire")
			w.manage("title")
			w.Sync.Run(w.deps)
			w.field("title", "Knight of the Silver Hand")
			expect.equal(w.Sync.Run(w.deps)[1].state, "written")
			expect.equal(w.ch().FT, "Knight of the Silver Hand")
			w.ns.Character.SetFieldVisibility(w.char(), "title", "private", 2)
			expect.equal(w.Sync.Run(w.deps)[1].state, "written")
			expect.equal(w.ch().FT, nil, "a now-private value is not left in TRP3")
			expect.equal(w.deps.ledger.profiles[w.fake.profileId].fields, nil)
		end)

		t:it("never overwrites a value the player wrote in TRP3, and pauses only that field", function()
			local w = world({ characteristics = { v = 3, FN = "Aelin", RA = "Half-elf (mine)", PS = {} } })
			w.field("race", "Elf")
			w.field("age", "31")
			w.manage("race", "age")
			local r = w.Sync.Run(w.deps)[1]
			expect.equal(r.state, "written", "age still updates")
			expect.truthy(r.message:find("Paused", 1, true))
			expect.equal(w.ch().RA, "Half-elf (mine)")
			expect.equal(w.ch().AG, "31")
			-- The player edits Dawnward's age in TRP3: paused, never overwritten.
			w.ch().AG = "40 (edited)"
			w.field("age", "32")
			local again = w.Sync.Run(w.deps)[1]
			expect.equal(again.state, "conflict")
			expect.equal(w.ch().AG, "40 (edited)")
			expect.equal(w.ch().RA, "Half-elf (mine)")
			local record = w.deps.ledger.profiles[w.fake.profileId]
			expect.truthy(record.fieldConflicts.age:find("changed in Total RP 3", 1, true))
			-- It stays paused even if the player's value happens to match later.
			w.ch().AG = "32"
			expect.equal(w.Sync.Check(w.deps, "fields").state, "conflict")
		end)

		t:it("resolve keep hands the field to TRP3; reclaim lets Dawnward write it after a backup", function()
			local w = world({ characteristics = { v = 3, FN = "Aelin", RA = "Half-elf", AG = "40", PS = {} } })
			w.field("race", "Elf")
			w.field("age", "31")
			w.manage("race", "age")
			w.Sync.Run(w.deps)
			expect.falsy(w.Sync.Resolve(w.deps, "class", "keep"))
			assert(w.Sync.Resolve(w.deps, "race", "keep"))
			expect.equal(w.ns.TRP3Ledger.Policy(w.deps.ledger.optIn[KEY], "race"), "trp3")
			assert(w.Sync.Resolve(w.deps, "age", "reclaim"))
			local backups = #w.deps.ledger.backups
			expect.equal(w.Sync.Run(w.deps)[1].state, "written")
			expect.equal(w.ch().AG, "31")
			expect.equal(w.ch().RA, "Half-elf", "kept")
			expect.equal(#w.deps.ledger.backups, backups + 1)
			expect.equal(w.ns.TRP3Ledger.BackupData(w.deps.ledger.backups[#w.deps.ledger.backups]).AG, "40",
				"the player's value is in the backup")
		end)

		t:it("keeps every guard: editor draft and combat defer, default profile and unknown versions refuse", function()
			local w = world()
			w.field("age", "31")
			w.manage("age")
			w.fake.openEditor("characteristics")
			expect.equal(w.Sync.Run(w.deps)[1].state, "deferred")
			w.fake.cancelEditor("characteristics")
			w.setCombat(true)
			expect.equal(w.Sync.Run(w.deps)[1].state, "deferred")
			w.setCombat(false)
			w.store:SetSimulation(true)
			expect.equal(w.Sync.Run(w.deps)[1].state, "blocked")
			w.store:SetSimulation(false)
			expect.equal(w.ch().AG, nil)
			for _, opts in ipairs({ { isDefault = true }, { version = "3.5.3" }, { noEditorFrames = true } }) do
				local o = world(opts)
				expect.falsy(o.Sync.SetPolicy(o.deps, "age", "dawnward"), "refused for " .. next(opts))
				expect.falsy(o.Sync.Authorize(o.deps, { age = "dawnward" }))
			end
		end)

		t:it("authorise is all-or-nothing and one character per profile manages each field", function()
			local w = world({ characters = { [KEY] = { profileID = "1700000000ABCDE" },
				["Alt-TestRealm"] = { profileID = "1700000000ABCDE" } } })
			local ok, message = w.Sync.Authorize(w.deps, { race = "dawnward", about = "dawnward", class = "off" })
			expect.truthy(ok, message)
			expect.truthy(message:find("Race", 1, true))
			local entry = w.deps.ledger.optIn[KEY]
			expect.equal(entry.about, true, "the boolean mirrors the policy")
			expect.equal(w.ns.TRP3Ledger.Policy(entry, "class"), "off")
			expect.truthy(select(2, w.Sync.SetPolicy(w.deps, "age", "dawnward")):find("shared with 1", 1, true))
			w.deps.characterKey = "Alt-TestRealm"
			local refused, why = w.Sync.Authorize(w.deps, { traits = "dawnward", race = "dawnward" })
			expect.falsy(refused)
			expect.truthy(why:find("already synced by " .. KEY, 1, true))
			expect.equal(w.deps.ledger.optIn["Alt-TestRealm"], nil, "nothing saved after a refusal")
		end)

		t:it("restores the backup and hands fields back to TRP3 if they do not read back", function()
			local w = world()
			w.field("age", "31")
			w.manage("age")
			w.fake.env.TRP3_Addon.TriggerEvent = function(_, _, _, _, section)
				if section == "characteristics" and w.ch().AG == "31" then w.ch().AG = "mangled" end
			end
			local r = w.Sync.Run(w.deps)[1]
			expect.equal(r.state, "failed")
			expect.equal(w.ch().AG, nil)
			expect.equal(w.ns.TRP3Ledger.Policy(w.deps.ledger.optIn[KEY], "age"), "trp3")
		end)

		t:it("release removes only Dawnward's values and hands the fields to TRP3", function()
			local w = world({ characteristics = { v = 3, FN = "Aelin", RA = "Half-elf", PS = {} } })
			w.field("age", "31")
			w.field("homeland", "Goldshire")
			w.manage("age", "homeland")
			w.Sync.Run(w.deps)
			assert(w.Sync.Release(w.deps, "fields"))
			expect.equal(w.ch().AG, nil)
			expect.equal(w.ch().BP, nil)
			expect.equal(w.ch().RA, "Half-elf")
			expect.equal(w.char().fields.age.value, "31", "Dawnward data is untouched")
		end)

		t:it("traits and fields share the section without disturbing each other", function()
			local w = world()
			w.ns.Personality.Set(w.char(), "courage", 15)
			w.ns.Personality.SetVisibility(w.char(), "courage", "public")
			w.field("age", "31")
			w.manage("traits", "age")
			local results = w.Sync.Run(w.deps)
			expect.equal(results[1].state, "written")
			expect.equal(results[2].state, "written")
			expect.equal(#w.ch().PS, 1)
			expect.equal(w.ch().AG, "31")
			for _, r in ipairs(w.Sync.Run(w.deps)) do expect.equal(r.state, "noop") end
		end)
	end)

	t:describe("TRP3 differences and import (L2)", function()
		t:it("shows TRP3 against Dawnward's Public value only, and never imports by itself", function()
			local w = world({ characteristics = { v = 3, FN = "Aelin", RA = "Half-elf", AG = "40", BP = "Lakeshire",
				PS = {} } })
			w.field("race", "Elf")
			w.field("age", "SECRET-AGE", "secret")
			assert(w.Sync.SetPolicy(w.deps, "homeland", "off"))
			local view = w.Sync.Differences(w.deps)
			local rows = {}
			for _, row in ipairs(view.rows) do rows[row.id] = row end
			expect.equal(rows.homeland, nil, "an 'off' mapping is not compared")
			expect.equal(rows.race.trp3, "Half-elf")
			expect.equal(rows.race.dawnward, "Elf")
			expect.truthy(rows.race.differ)
			expect.equal(rows.age.dawnward, nil, "a Secret value is never shown")
			expect.truthy(rows.age.hidden)
			expect.truthy(rows.age.importable)
			-- Runs never import: Dawnward's data is unchanged after sync runs.
			w.Sync.Run(w.deps)
			expect.equal(w.char().fields.race.value, "Elf")
		end)

		t:it("imports one field explicitly through the Actions path, as Private by default", function()
			local w = world({ characteristics = { v = 3, FN = "Aelin", CL = "Lightbringer", PS = {} } })
			local ctx = w.ctx()
			local requests = 0
			ctx.trp3RequestSync = function() requests = requests + 1 end
			local before = w.fake.snapshot()
			local ok, message = w.ns.TRP3Commands.Import(ctx, "class")
			expect.truthy(ok, message)
			expect.deepEqual(w.char().fields.class, { value = "Lightbringer", visibility = "private" })
			expect.equal(requests, 1, "the normal write path asks sync to catch up")
			expect.deepEqual(w.fake.snapshot(), before, "nothing written to TRP3")
			assert(w.ns.TRP3Commands.Import(ctx, "class", "public"))
			expect.equal(w.char().fields.class.visibility, "public")
			expect.falsy(w.ns.TRP3Commands.Import(ctx, "age"), "TRP3 has no age")
			expect.falsy(w.ns.TRP3Commands.Import(ctx, "class", "everyone"))
			w.store.realReadOnly = "test"
			expect.falsy(w.ns.TRP3Commands.Import(ctx, "class"))
		end)
	end)

	t:describe("TRP3 ledger: policies and migration (L1)", function()
		t:it("migrates v0.7 opt-ins to 'dawnward' with no behaviour change", function()
			local ns = Loader.WithTRP3()
			local Ledger = ns.TRP3Ledger
			local raw = { schemaVersion = 1, optIn = {
				[KEY] = { about = true, traits = false, profileId = "1700000000ABCDE", at = 5 } } }
			local l = assert(Ledger.Normalize(raw))
			local entry = l.optIn[KEY]
			expect.equal(Ledger.Policy(entry, "about"), "dawnward")
			expect.equal(Ledger.Policy(entry, "traits"), "off")
			expect.equal(Ledger.Policy(entry, "race"), "trp3")
			expect.falsy(Ledger.AnyFieldManaged(entry))
			expect.deepEqual(assert(Ledger.Normalize(ns.Util.DeepCopy(l))), l, "stable on the next load")
		end)

		t:it("cleans corrupted policies, field records and conflicts instead of failing", function()
			local ns = Loader.WithTRP3()
			local Ledger = ns.TRP3Ledger
			local raw = {
				optIn = {
					[KEY] = { about = "yes", traits = true, profileId = "1700000000ABCDE",
						policy = { race = "dawnward", age = "always", title = 5, traits = "off", bogus = "dawnward" } },
					["Bad-Realm"] = { policy = { race = "dawnward" } }, -- no profile: dropped
				},
				profiles = { ["1700000000ABCDE"] = {
					fields = { race = { value = "Elf" }, age = { value = "|cff00ff00x" }, nope = { value = "x" },
						class = "Paladin" },
					fieldConflicts = { race = 42, age = "edited", zzz = "x" },
				} },
				backups = { { id = 1, profileId = "1700000000ABCDE", section = "characteristics",
					data = ns.Serializer.Encode({ v = 1 }), owners = { fields = { race = { value = "Elf" } },
						traits = "junk" } } },
			}
			local l = assert(Ledger.Normalize(raw))
			local entry = l.optIn[KEY]
			expect.equal(l.optIn["Bad-Realm"], nil)
			expect.equal(Ledger.Policy(entry, "race"), "dawnward")
			expect.equal(Ledger.Policy(entry, "age"), "trp3", "an unknown policy falls back to the default")
			expect.equal(Ledger.Policy(entry, "title"), "trp3")
			expect.equal(Ledger.Policy(entry, "traits"), "off", "the stored policy wins over the boolean")
			expect.equal(entry.traits, false)
			expect.equal(entry.policy.bogus, nil)
			local p = l.profiles["1700000000ABCDE"]
			expect.deepEqual(p.fields, { race = { value = "Elf" } })
			expect.deepEqual(p.fieldConflicts, { age = "edited" })
			expect.deepEqual(l.backups[1].owners, { fields = { race = { value = "Elf" } } })
		end)
	end)

	t:describe("TRP3 rollback: visibility-aware (L2)", function()
		local function setup()
			local w = world()
			w.publicFact("origin", "Born in Stormwind")
			local secretFact = w.publicFact("belief", "Loves the Duke")
			assert(w.Sync.SetPolicy(w.deps, "about", "dawnward"))
			w.Sync.Run(w.deps)                       -- backup #1: before insert
			w.publicFact("event", "Saved a village")
			w.Sync.Run(w.deps)                       -- backup #2: holds both lines
			w.ns.Facts.SetVisibility(w.char(), secretFact.id, "secret", 2)
			w.Sync.Run(w.deps)                       -- backup #3; TRP3 no longer shows it
			return w
		end

		t:it("previews what an exact restore would make visible again", function()
			local w = setup()
			expect.falsy(w.fake.profile.player.about.T1.TX:find("Duke", 1, true))
			local preview = assert(w.Sync.RollbackPreview(w.deps, 3))
			expect.equal(#preview.items, 1)
			expect.truthy(preview.items[1]:find("Loves the Duke", 1, true))
			expect.truthy(preview.ownPossible)
			expect.equal(#assert(w.Sync.RollbackPreview(w.deps, 1)).items, 0, "nothing Dawnward-owned in #1")
			local lines = w.ns.TRP3Commands.RollbackRiskLines(preview)
			expect.truthy(lines[1]:find("1 item", 1, true))
		end)

		t:it("the safe restore brings back only the player's text and rebuilds Dawnward's part", function()
			local w = setup()
			w.fake.profile.player.about.T1.TX = "Player rewrote everything"
			local ok, message = w.Sync.Rollback(w.deps, 3, "own")
			expect.truthy(ok, message)
			local text = w.fake.profile.player.about.T1.TX
			expect.truthy(text:find("^Private about text"), text)
			expect.falsy(text:find("Duke", 1, true), "nothing no longer Public reappears")
			expect.truthy(text:find("Saved a village", 1, true), "Dawnward's part rebuilt from Public data")
			expect.equal(w.Sync.Run(w.deps)[1].state, "noop", "ownership matches what was written")
		end)

		t:it("the exact restore is explicit and brings everything back, then stops managing", function()
			local w = setup()
			assert(w.Sync.Rollback(w.deps, 3, "exact"))
			expect.truthy(w.fake.profile.player.about.T1.TX:find("Duke", 1, true))
			expect.equal(w.Sync.Check(w.deps, "about").state, "off")
		end)

		t:it("a field rollback names the old value and the safe mode does not restore it", function()
			local w = world()
			w.field("age", "SECRET 31")
			w.manage("age")
			w.Sync.Run(w.deps)             -- #1 before add
			w.field("age", "32")
			w.Sync.Run(w.deps)             -- #2 holds "SECRET 31"
			w.ns.Character.SetFieldVisibility(w.char(), "age", "secret", 2)
			w.Sync.Run(w.deps)             -- #3 holds "32"; TRP3 now empty
			local preview = assert(w.Sync.RollbackPreview(w.deps, 2))
			expect.truthy(preview.items[1]:find("Age: SECRET 31", 1, true))
			assert(w.Sync.Rollback(w.deps, 2, "own"))
			expect.equal(w.ch().AG, nil, "a Secret value is never restored by the safe mode")
		end)

		t:it("refuses the safe mode when Dawnward's part cannot be separated", function()
			local w = setup()
			local b = w.deps.ledger.backups[3]
			b.owners.about.block = "\n\nnot in the backup"
			local preview = w.Sync.RollbackPreview(w.deps, 3)
			expect.falsy(preview.ownPossible)
			local before = w.fake.snapshot()
			expect.falsy(w.Sync.Rollback(w.deps, 3, "own"))
			expect.deepEqual(w.fake.snapshot(), before)
		end)
	end)
end
