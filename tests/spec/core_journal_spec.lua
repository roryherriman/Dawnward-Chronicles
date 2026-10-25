-- L1: schema v2 migration, journal engine, milestones, retention, actions.
local Loader = require("support.loader")

-- A realistic v0.1 (schema 1) saved table.
local function v1Database()
	return {
		schemaVersion = 1,
		characters = {
			["Aelin-Realm"] = {
				createdAt = 100, updatedAt = 200, nextId = 4,
				fields = {
					name = { value = "Aelin", visibility = "public" },
					motivation = { value = "A hidden vow", visibility = "secret" },
				},
				family = { { id = 1, relation = "mother", name = "Ilsa", status = "living", visibility = "private" } },
				history = { { id = 3, when = "Year 3", text = "Joined the guard", visibility = "public" } },
			},
		},
		importBackups = {
			["Aelin-Realm"] = { createdAt = 50, fields = { name = { value = "Old Aelin", visibility = "private" } },
				family = {}, history = {}, nextId = 1 },
		},
	}
end

return function(t, expect)
	local ns = Loader.Core()
	local Schema, Migrations, Journal, Milestones, Transfer, Util =
		ns.Schema, ns.Migrations, ns.Journal, ns.Milestones, ns.Transfer, ns.Util

	local function newChar()
		return Schema.NewCharacter(1000)
	end

	t:describe("migration v1 -> v2", function()
		t:it("preserves every v1 profile, family, history, privacy and backup", function()
			local raw = v1Database()
			local before = Util.DeepCopy(raw)
			local db, info = Migrations.Load(raw)
			expect.equal(info.status, "migrated")
			expect.equal(info.from, 1)
			expect.equal(db.schemaVersion, 2)
			expect.deepEqual(raw, before, "the saved v1 table is never modified")

			local char = db.characters["Aelin-Realm"]
			local old = before.characters["Aelin-Realm"]
			expect.deepEqual(char.fields, old.fields)
			expect.deepEqual(char.family, old.family)
			expect.deepEqual(char.history, old.history)
			expect.equal(char.createdAt, 100)
			expect.equal(char.updatedAt, 200)
			expect.equal(char.nextId, 4)
			expect.equal(db.importBackups["Aelin-Realm"].fields.name.value, "Old Aelin")
		end)

		t:it("adds an empty journal, keys and the neutral theme", function()
			local db = Migrations.Load(v1Database())
			local char = db.characters["Aelin-Realm"]
			expect.deepEqual(char.journal, {})
			expect.deepEqual(char.journalKeys, {})
			expect.equal(char.theme, "neutral")
			expect.deepEqual(db.ui, {})
		end)

		t:it("is idempotent: loading migrated data again changes nothing", function()
			local once = Migrations.Load(v1Database())
			local char = once.characters["Aelin-Realm"]
			Journal.AddNote(char, { text = "A note" }, 300)
			Milestones.Record(char, "levelup", { level = 5, zone = "Elwynn Forest" }, 301)
			char.theme = "arcane"
			once.ui.position = { left = 10, top = 600 }
			local twice, info = Migrations.Load(Util.DeepCopy(once))
			expect.equal(info.status, "ok")
			expect.deepEqual(twice, once)
			local thrice = Migrations.Load(Util.DeepCopy(twice))
			expect.deepEqual(thrice, twice)
		end)

		t:it("treats schema 3 data as newer and leaves it alone", function()
			local raw = { schemaVersion = 3, characters = {} }
			local _, info = Migrations.Load(raw)
			expect.equal(info.status, "readOnly")
		end)

		t:it("rejects invalid themes and window positions when loading", function()
			local db = Migrations.Load({ schemaVersion = 2,
				characters = { A = { theme = "rainbow" } }, ui = { position = { left = "x", top = 1 } } })
			expect.equal(db.characters.A.theme, "neutral")
			expect.equal(db.ui.position, nil)
		end)
	end)

	t:describe("journal notes", function()
		t:it("adds private notes by default, newest first", function()
			local c = newChar()
			local a = Journal.AddNote(c, { title = "Arrival", text = "Reached Goldshire." }, 10)
			local b = Journal.AddNote(c, { text = "Met a stranger." }, 20)
			expect.equal(a.visibility, "private")
			expect.equal(a.kind, "note")
			local list = Journal.NewestFirst(c)
			expect.equal(list[1].id, b.id)
			expect.equal(list[2].id, a.id)
		end)

		t:it("rejects empty notes and bad visibility", function()
			local c = newChar()
			expect.falsy(Journal.AddNote(c, { title = "  ", text = "" }))
			expect.falsy(Journal.AddNote(c, { text = "x", visibility = "everyone" }))
			expect.equal(#c.journal, 0)
		end)

		t:it("edits a note, keeps unchanged parts and records the edit time", function()
			local c = newChar()
			local e = Journal.AddNote(c, { title = "T", text = "Old" }, 10)
			expect.truthy(Journal.UpdateNote(c, e.id, { text = "New" }, 30))
			expect.equal(e.title, "T")
			expect.equal(e.text, "New")
			expect.equal(e.updatedAt, 30)
			expect.truthy(Journal.UpdateNote(c, e.id, { title = "" }, 31))
			expect.equal(e.title, nil, "an empty title clears it")
			expect.falsy(Journal.UpdateNote(c, e.id, { text = "" }), "cannot make an entry empty")
		end)

		t:it("deletes notes but never automatic entries", function()
			local c = newChar()
			local n = Journal.AddNote(c, { text = "note" }, 10)
			local ev = Milestones.Record(c, "levelup", { level = 2 }, 11)
			expect.truthy(Journal.RemoveNote(c, n.id))
			local ok, err = Journal.RemoveNote(c, ev.id)
			expect.falsy(ok)
			expect.truthy(err:find("cannot be deleted"))
			expect.falsy(Journal.UpdateNote(c, ev.id, { text = "fabricated" }))
			expect.equal(ev.text, "Reached level 2.")
		end)

		t:it("lets automatic entries change visibility", function()
			local c = newChar()
			local ev = Milestones.Record(c, "levelup", { level = 2 }, 11)
			expect.truthy(Journal.SetVisibility(c, ev.id, "public"))
			expect.equal(ev.visibility, "public")
		end)
	end)

	t:describe("level-up milestones", function()
		t:it("records level, zone, time and source", function()
			local c = newChar()
			local e = Milestones.Record(c, "levelup", { level = 12, zone = "Westfall", subzone = "Moonbrook" }, 777)
			expect.equal(e.kind, "event")
			expect.equal(e.text, "Reached level 12 in Westfall.")
			expect.deepEqual(e.event, { type = "levelup", key = "levelup:12", source = "PLAYER_LEVEL_UP",
				level = 12, zone = "Westfall", subzone = "Moonbrook" })
			expect.equal(e.createdAt, 777)
			expect.equal(e.visibility, "private")
		end)

		t:it("prevents duplicates, even after the entry was pruned", function()
			local c = newChar()
			expect.truthy(Milestones.Record(c, "levelup", { level = 12 }, 1))
			local again, reason = Milestones.Record(c, "levelup", { level = 12 }, 2)
			expect.falsy(again)
			expect.equal(reason, "duplicate")
			table.remove(c.journal, 1) -- as if retention removed it
			expect.equal(select(2, Milestones.Record(c, "levelup", { level = 12 }, 3)), "duplicate")
			expect.equal(#c.journal, 0)
		end)

		t:it("rejects invalid levels and unknown milestone types", function()
			local c = newChar()
			expect.falsy(Milestones.Record(c, "levelup", { level = 1 }))
			expect.falsy(Milestones.Record(c, "levelup", { level = 2.5 }))
			expect.falsy(Milestones.Record(c, "levelup", {}))
			expect.falsy(Milestones.Record(c, "dragonslain", { level = 5 }))
			expect.equal(#c.journal, 0)
		end)

		t:it("allows new milestone types without changing the journal", function()
			Milestones.Register("testdiscovery", {
				build = function(d) return { type = "testdiscovery", key = "discovery:" .. d.name, text = "Found " .. d.name } end,
			})
			local c = newChar()
			local e = Milestones.Record(c, "testdiscovery", { name = "a hidden glade" }, 5)
			expect.equal(e.text, "Found a hidden glade")
			expect.equal(select(2, Milestones.Record(c, "testdiscovery", { name = "a hidden glade" }, 6)), "duplicate")
			Milestones.TYPES.testdiscovery = nil
		end)
	end)

	t:describe("journal retention", function()
		local LIMIT = Schema.JOURNAL.limit

		t:it("removes the oldest automatic entry when full, never a written one", function()
			local c = newChar()
			Journal.AddNote(c, { text = "first written entry" }, 1)
			for level = 2, LIMIT do
				Milestones.Record(c, "levelup", { level = level }, level)
			end
			-- 1 note + 499 events = 500: full. MAX_LEVEL caps levels at 100, so pad with notes.
			while #c.journal < LIMIT do
				Journal.AddNote(c, { text = "filler" }, 5000)
			end
			expect.equal(#c.journal, LIMIT)
			local entry, pruned = Journal.AddNote(c, { text = "one more" }, 6000)
			expect.truthy(entry)
			expect.equal(pruned, 1)
			expect.equal(#c.journal, LIMIT)
			expect.equal(c.journal[1].text, "first written entry", "written entry kept")
		end)

		t:it("refuses new entries when every entry was written by the player", function()
			local c = newChar()
			for i = 1, LIMIT do
				Journal.AddNote(c, { text = "note " .. i }, i)
			end
			local entry, err = Journal.AddNote(c, { text = "overflow" }, LIMIT + 1)
			expect.falsy(entry)
			expect.truthy(err:find("full"))
			local ev, reason = Milestones.Record(c, "levelup", { level = 10 }, LIMIT + 2)
			expect.falsy(ev)
			expect.truthy(reason:find("full"))
			expect.equal(c.journalKeys["levelup:10"], nil, "an unrecorded milestone is not marked as seen")
			expect.equal(c.journal[1].text, "note 1")
		end)

		t:it("caps oversized saved journals on load, preferring written entries", function()
			local journal = {}
			for i = 1, LIMIT + 50 do
				journal[i] = { id = i, kind = (i % 2 == 0) and "event" or "note", createdAt = i, text = "e" .. i,
					event = { type = "levelup", key = "k" .. i } }
			end
			local report = {}
			local char = Schema.NormalizeCharacter({ journal = journal }, report)
			expect.equal(#char.journal, LIMIT)
			local notes = 0
			for _, e in ipairs(char.journal) do
				if e.kind == "note" then notes = notes + 1 end
			end
			expect.equal(notes, (LIMIT + 50) / 2, "every written entry survives")
			expect.truthy(#report > 0)
		end)

		t:it("caps milestone keys, dropping the oldest", function()
			local keys = {}
			for i = 1, Schema.JOURNAL.keyLimit + 5 do
				keys["k" .. i] = i
			end
			expect.equal(Schema.CapJournalKeys(keys), 5)
			expect.equal(keys.k1, nil)
			expect.equal(keys["k" .. (Schema.JOURNAL.keyLimit + 5)], Schema.JOURNAL.keyLimit + 5)
		end)

		t:it("keeps IDs unique across lists after load-time pruning", function()
			local journal = {}
			for i = 1, LIMIT + 5 do
				journal[i] = { id = 100 + i, kind = "event", createdAt = i, text = "e",
					event = { type = "levelup", key = "k" .. i } }
			end
			local char = Schema.NormalizeCharacter({
				family = { { id = 1, name = "A" } }, history = { { id = 2, text = "B" } }, journal = journal })
			local seen = {}
			for _, list in ipairs({ char.family, char.history, char.journal }) do
				for _, item in ipairs(list) do
					expect.falsy(seen[item.id], "duplicate id " .. item.id)
					seen[item.id] = true
				end
			end
		end)
	end)

	t:describe("journal privacy and transfer", function()
		local function sample()
			local c = newChar()
			local pub = Journal.AddNote(c, { text = "PUBLIC-NOTE" }, 1)
			Journal.SetVisibility(c, pub.id, "public")
			Journal.AddNote(c, { text = "PRIVATE-NOTE" }, 2)
			local sec = Journal.AddNote(c, { text = "SECRET-NOTE" }, 3)
			Journal.SetVisibility(c, sec.id, "secret")
			Milestones.Record(c, "levelup", { level = 7 }, 4)
			c.theme = "silverhand"
			return c
		end

		t:it("share exports contain public journal entries only, and no milestone keys", function()
			local text = assert(Transfer.Export(sample(), "share"))
			expect.truthy(text:find("PUBLIC-NOTE", 1, true))
			expect.falsy(text:find("PRIVATE-NOTE", 1, true))
			expect.falsy(text:find("SECRET-NOTE", 1, true))
			expect.falsy(text:find("levelup:7", 1, true))
		end)

		t:it("backups round-trip the journal, keys and theme; secrets carry over", function()
			local current = sample()
			local plan = assert(Transfer.Decode(assert(Transfer.Export(current, "backup"))))
			expect.equal(plan.character.theme, "silverhand")
			expect.truthy(plan.character.journalKeys["levelup:7"])
			expect.equal(#plan.character.journal, 3, "public, private and the milestone")
			local merged = Transfer.MergeForImport(current, plan.character, plan.includesSecrets, 50)
			local texts = {}
			for _, e in ipairs(merged.journal) do texts[#texts + 1] = e.text end
			expect.equal(#merged.journal, 4)
			expect.truthy(table.concat(texts, "|"):find("SECRET-NOTE", 1, true), "secret entry carried over")
			expect.equal(select(2, Milestones.Record(merged, "levelup", { level = 7 }, 60)), "duplicate")
		end)

		t:it("imports v0.1 (schema 1) exports with an empty journal", function()
			local payload = ns.Serializer.Encode({ format = 1, kind = "backup", schemaVersion = 1,
				character = { fields = { name = { value = "Old", visibility = "public" } }, family = {}, history = {} } })
			local plan = assert(Transfer.Decode("!DWC1!B!" .. Transfer.Checksum(payload) .. "!" .. payload))
			expect.equal(plan.character.fields.name.value, "Old")
			expect.deepEqual(plan.character.journal, {})
			expect.equal(plan.character.theme, "neutral")
		end)
	end)

	t:describe("actions", function()
		local function ctxFor(storeOpts)
			local store = ns.Store.new(Schema.NewDatabase(), Schema.NewDatabase(), storeOpts)
			local clock = 0
			return {
				store = store, characterKey = "Aelin-Realm",
				now = function() clock = clock + 1; return clock end,
			}
		end

		t:it("persists theme per character without touching character data", function()
			local ctx = ctxFor()
			ns.Actions.SetField(ctx, "name", "Aelin")
			local before = Util.DeepCopy(ns.Actions.Character(ctx).fields)
			expect.truthy(ns.Actions.SetTheme(ctx, "arcane"))
			expect.equal(ns.Actions.Character(ctx).theme, "arcane")
			expect.deepEqual(ns.Actions.Character(ctx).fields, before)
			expect.falsy(ns.Actions.SetTheme(ctx, "class-paladin"))
			ctx.characterKey = "Other-Realm"
			expect.equal(ns.Actions.ThemeOf(ns.Actions.Character(ctx)).id, "neutral", "new characters start neutral")
		end)

		t:it("records real milestones in real data even during simulation", function()
			local ctx = ctxFor()
			ctx.store:SetSimulation(true)
			expect.truthy(ns.Actions.RecordRealMilestone(ctx, "levelup", { level = 9 }))
			expect.equal(#ctx.store.real.characters["Aelin-Realm"].journal, 1)
			expect.equal(ctx.store.sim.characters["Aelin-Realm"], nil)
		end)

		t:it("records simulated milestones only in simulation data", function()
			local ctx = ctxFor()
			expect.falsy(ns.Actions.RecordSimulatedMilestone(ctx, "levelup", { level = 9 }), "needs simulation mode")
			ctx.store:SetSimulation(true)
			local entry = ns.Actions.RecordSimulatedMilestone(ctx, "levelup", { level = 9 })
			expect.equal(entry.event.source, "SIMULATION")
			expect.equal(ctx.store.real.characters["Aelin-Realm"], nil)
			local again, message = ns.Actions.RecordSimulatedMilestone(ctx, "levelup", { level = 9 })
			expect.falsy(again)
			expect.truthy(message:find("duplicate"))
		end)

		t:it("refuses every write on read-only data", function()
			local ctx = ctxFor({ realReadOnly = "newer data" })
			for _, call in ipairs({
				function() return ns.Actions.AddNote(ctx, nil, "x") end,
				function() return ns.Actions.SetField(ctx, "name", "x") end,
				function() return ns.Actions.SetTheme(ctx, "arcane") end,
				function() return ns.Actions.RecordRealMilestone(ctx, "levelup", { level = 3 }) end,
			}) do
				local ok, message = call()
				expect.falsy(ok)
				expect.truthy(tostring(message):find("read%-only"), tostring(message))
			end
			expect.equal(next(ctx.store.real.characters), nil)
		end)
	end)
end
