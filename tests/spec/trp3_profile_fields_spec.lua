-- L2 (v0.9): the extended Total RP 3 profile: names, title prefix,
-- appearance details, residence, relationship status, the game's own
-- defaults, the one-time takeover, and Dawnward-owned additional
-- information entries (pronouns, faith, occupation, allegiance), against
-- the TRP3 3.4.1 fake (mocked; not in-game evidence).
local Loader = require("support.loader")
local Fake = require("fakes.trp3_341")

return function(t, expect)
	local KEY = "Testchar-TestRealm"

	local function world(fakeOpts)
		local ns = Loader.WithTRP3()
		local fake = Fake.new(fakeOpts or {})
		fake.env.UnitName = function() return "Testchar" end
		fake.env.UnitRace = function() return "Human" end
		fake.env.UnitClass = function() return "Paladin" end
		local store = ns.Store.new(ns.Schema.NewDatabase(), ns.Schema.NewDatabase())
		local clock = 1000
		local deps = {
			env = fake.env, ledger = ns.TRP3Ledger.New(), store = store, characterKey = KEY,
			now = function() clock = clock + 1; return clock end,
			inCombat = function() return false end,
		}
		local w = { ns = ns, fake = fake, deps = deps, Sync = ns.TRP3Sync }
		function w.char()
			return assert(store:EnsureCharacter(KEY, 1))
		end
		function w.field(key, value, level)
			assert(ns.Character.SetField(w.char(), key, value, 1))
			assert(ns.Character.SetFieldVisibility(w.char(), key, level or "public", 1))
		end
		function w.manage(...)
			for _, id in ipairs({ ... }) do
				assert(w.Sync.SetPolicy(deps, id, "dawnward"))
			end
		end
		function w.ch() return fake.profile.player.characteristics end
		function w.run(feature)
			return w.Sync.RunFeature(deps, feature)
		end
		return w
	end

	t:describe("TRP3 profile fields v0.9", function()
		t:it("writes every new characteristics field from Public details, as TRP3's editor stores them", function()
			local w = world({ characteristics = { v = 3, PS = {} } })
			w.field("firstName", "Kyssarra")
			w.field("lastName", "Dawnward")
			w.field("honorific", "Lady")
			w.field("eyes", "Pale gold")
			w.field("height", "Tall")
			w.field("weight", "Lean")
			w.field("residence", "Stormwind")
			w.field("relationship", "Widowed")
			w.manage("firstName", "lastName", "honorific", "eyes", "height", "weight", "residence", "relationship")
			local r = w.run("fields")
			expect.equal(r.state, "written", r.message)
			local ch = w.ch()
			expect.equal(ch.FN, "Kyssarra")
			expect.equal(ch.LN, "Dawnward")
			expect.equal(ch.TI, "Lady")
			expect.equal(ch.EC, "Pale gold")
			expect.equal(ch.HE, "Tall")
			expect.equal(ch.WE, "Lean")
			expect.equal(ch.RE, "Stormwind")
			expect.equal(ch.RS, 5, "TRP3 stores the relationship status as its enum number")
			expect.equal(w.run("fields").state, "noop", "no churn on the next run")
		end)

		t:it("refuses a relationship status TRP3 has no value for, without writing anything", function()
			local w = world({ characteristics = { v = 3, PS = {} } })
			w.field("relationship", "It's complicated")
			w.manage("relationship")
			local check = w.Sync.Check(w.deps, "fields")
			expect.equal(check.state, "noop")
			expect.truthy(check.notes[1]:find("single, taken, married, divorced or widowed", 1, true))
			expect.equal(w.ch().RS, nil)
		end)

		t:it("replaces the game's own name, race and class, but never the player's own text", function()
			local w = world({ characteristics = { v = 3, FN = "Testchar", RA = "Human", CL = "Paladin", AG = "Old",
				PS = {} } })
			w.field("firstName", "Kyssarra")
			w.field("race", "Quel'dorei")
			w.field("class", "Sunwalker")
			w.field("age", "34")
			w.manage("firstName", "race", "class", "age")
			local r = w.run("fields")
			expect.equal(r.state, "written", r.message)
			expect.equal(w.ch().FN, "Kyssarra", "the game's default name is replaced")
			expect.equal(w.ch().RA, "Quel'dorei")
			expect.equal(w.ch().CL, "Sunwalker")
			expect.equal(w.ch().AG, "Old", "the player's own age is never overwritten")
			local record = w.deps.ledger.profiles[w.fake.profileId]
			expect.truthy(record.fieldConflicts.age, "paused until the player chooses")
		end)

		t:it("takes over the player's own text once when they chose Replace, after a backup", function()
			local w = world({ characteristics = { v = 3, AG = "Old", PS = {} } })
			w.field("age", "34")
			assert(w.Sync.Authorize(w.deps, { age = "dawnward" }, { adopt = true }))
			local r = w.run("fields")
			expect.equal(r.state, "written", r.message)
			expect.equal(w.ch().AG, "34")
			local backup = w.deps.ledger.backups[#w.deps.ledger.backups]
			expect.equal(w.ns.TRP3Ledger.BackupData(backup).AG, "Old", "the player's value is in the backup")
			expect.falsy(w.deps.ledger.optIn[KEY].adopt and w.deps.ledger.optIn[KEY].adopt.fields,
				"used once, then forgotten")
			-- Later edits in TRP3 are conflicts again, never overwritten.
			w.ch().AG = "Ancient"
			w.field("age", "35")
			expect.equal(w.run("fields").state, "conflict")
			expect.equal(w.ch().AG, "Ancient")
		end)
	end)

	t:describe("TRP3 additional information v0.9", function()
		t:it("adds pronouns as TRP3's preset and the others as named custom entries", function()
			local w = world({ characteristics = { v = 3, PS = {}, MI = { { ID = 3, NA = "Nickname", VA = "Kys" } } } })
			w.field("pronouns", "she/her")
			w.field("faith", "The Holy Light")
			w.field("occupation", "Paladin of the Silver Hand")
			w.field("allegiance", "The Alliance")
			w.manage("pronouns", "faith", "occupation", "allegiance")
			local r = w.run("misc")
			expect.equal(r.state, "written", r.message)
			local mi = w.ch().MI
			expect.equal(#mi, 5)
			expect.deepEqual(mi[1], { ID = 3, NA = "Nickname", VA = "Kys" }, "the player's own entry is untouched")
			-- As TRP3's editor adds them (miscAdd with GetMiscTypeInfo's name and icon).
			expect.deepEqual(mi[2], { ID = 7, NA = "Pronouns", VA = "she/her", IC = "vas_namechange" })
			expect.deepEqual(mi[3], { ID = 1, NA = "Faith", VA = "The Holy Light", IC = "inv_misc_questionmark" })
			expect.equal(mi[4].VA, "Paladin of the Silver Hand")
			expect.equal(w.run("misc").state, "noop")
		end)

		t:it("updates and removes only its own entries, keeping a restyled icon", function()
			local w = world({ characteristics = { v = 3, PS = {} } })
			w.field("faith", "The Holy Light")
			w.manage("faith")
			w.run("misc")
			w.ch().MI[1].IC = "Spell_Holy_HolyBolt" -- the player picks an icon in TRP3
			w.field("faith", "The Light and the Naaru")
			expect.equal(w.run("misc").state, "written")
			expect.equal(w.ch().MI[1].VA, "The Light and the Naaru")
			expect.equal(w.ch().MI[1].IC, "Spell_Holy_HolyBolt", "styling is the player's")
			w.ns.Character.SetFieldVisibility(w.char(), "faith", "private", 2)
			expect.equal(w.run("misc").state, "written")
			expect.equal(#w.ch().MI, 0, "no longer Public: taken back out")
		end)

		t:it("pauses on the player's own entry or an edited one, and resolves either way", function()
			local w = world({ characteristics = { v = 3, PS = {}, MI = { { ID = 7, NA = "Pronouns", VA = "they/them" } } } })
			w.field("pronouns", "she/her")
			w.manage("pronouns")
			local r = w.run("misc")
			expect.equal(r.state, "conflict", r.message)
			expect.equal(w.ch().MI[1].VA, "they/them")
			local ok = w.Sync.Resolve(w.deps, "pronouns", "reclaim")
			expect.truthy(ok)
			expect.equal(w.run("misc").state, "written")
			expect.equal(w.ch().MI[1].VA, "she/her")
			-- Edited in TRP3 afterwards: a conflict again.
			w.ch().MI[1].VA = "she/they"
			w.field("pronouns", "she/her ")
			expect.equal(w.run("misc").state, "conflict")
			assert(w.Sync.Resolve(w.deps, "pronouns", "keep"))
			expect.equal(w.ns.TRP3Ledger.Policy(w.deps.ledger.optIn[KEY], "pronouns"), "trp3")
		end)

		t:it("rolls back to the player's own entries only", function()
			local w = world({ characteristics = { v = 3, PS = {}, MI = { { ID = 3, NA = "Nickname", VA = "Kys" } } } })
			w.field("faith", "The Holy Light")
			w.manage("faith")
			w.run("misc")
			w.ns.Character.SetFieldVisibility(w.char(), "faith", "secret", 2)
			local preview = w.Sync.RollbackPreview(w.deps)
			expect.truthy(preview.ownPossible)
			local ok, msg = w.Sync.Rollback(w.deps, nil, "own")
			expect.truthy(ok, msg)
			expect.equal(#w.ch().MI, 1, "the Secret faith does not come back")
			expect.equal(w.ch().MI[1].VA, "Kys")
		end)

		t:it("keeps the ledger across a reload, and an older ledger version still loads", function()
			local w = world({ characteristics = { v = 3, PS = {} } })
			w.field("pronouns", "she/her")
			w.manage("pronouns")
			w.run("misc")
			local clean = w.ns.TRP3Ledger.Normalize(w.ns.Util.DeepCopy(w.deps.ledger))
			expect.deepEqual(clean.profiles[w.fake.profileId].misc, { pronouns = { value = "she/her" } })
			expect.equal(clean.schemaVersion, 2)
			expect.truthy(w.ns.TRP3Ledger.Normalize({ schemaVersion = 1, optIn = {} }), "v1 ledgers load")
			expect.falsy(w.ns.TRP3Ledger.Normalize({ schemaVersion = 3 }), "a newer ledger is left alone")
		end)
	end)
end
