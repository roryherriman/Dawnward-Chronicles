-- L1: schema v3 (character foundations): migration from v2 and normalisation.
local Loader = require("support.loader")

-- A realistic v0.2 (schema 2) saved table, with every kind of v2 data.
local function v2Database()
	return {
		schemaVersion = 2,
		characters = {
			["Aelin-Realm"] = {
				createdAt = 100, updatedAt = 900, nextId = 9, theme = "silverhand",
				fields = {
					name = { value = "Aelin", visibility = "public" },
					summary = { value = "Grew up by the sea.\nLeft at sixteen.", visibility = "private" },
					motivation = { value = "A hidden vow", visibility = "secret" },
				},
				family = { { id = 1, relation = "mother", name = "Ilsa", status = "living", visibility = "private" } },
				history = { { id = 3, when = "Year 3", text = "Joined the guard", visibility = "public" } },
				journal = {
					{ id = 4, kind = "note", title = "Arrival", text = "Reached Goldshire.", visibility = "private",
						createdAt = 300 },
					{ id = 5, kind = "event", text = "Reached level 5.", visibility = "private", createdAt = 400,
						event = { type = "levelup", key = "levelup:5", level = 5, zone = "Elwynn Forest" } },
					{ id = 8, kind = "note", text = "Edited", visibility = "secret", createdAt = 500, updatedAt = 600 },
				},
				journalKeys = { ["levelup:5"] = 400 },
			},
		},
		importBackups = {
			["Aelin-Realm"] = { createdAt = 50, updatedAt = 60, nextId = 2, theme = "neutral",
				fields = { name = { value = "Old Aelin", visibility = "private" } },
				family = {}, history = {}, journal = {}, journalKeys = {} },
		},
		ui = { position = { left = 12, top = 640 } },
	}
end

return function(t, expect)
	local ns = Loader.CoreUpTo("Migrations")
	local Schema, Migrations, Util = ns.Schema, ns.Migrations, ns.Util

	local V2_PARTS = { "createdAt", "updatedAt", "nextId", "theme", "fields", "family", "history", "journal",
		"journalKeys" }

	t:describe("migration v2 -> v3", function()
		t:it("preserves every v2 value exactly", function()
			local raw = v2Database()
			local before = Util.DeepCopy(raw)
			local db, info = Migrations.Load(raw)
			expect.equal(info.status, "migrated")
			expect.equal(info.from, 2)
			expect.equal(db.schemaVersion, ns.Schema.VERSION, "v2 data migrates through v3 to the current schema")
			expect.deepEqual(raw, before, "the saved v2 table is never modified")
			for _, mapName in ipairs({ "characters", "importBackups" }) do
				local char, old = db[mapName]["Aelin-Realm"], before[mapName]["Aelin-Realm"]
				for _, part in ipairs(V2_PARTS) do
					expect.deepEqual(char[part], old[part], mapName .. "." .. part .. " must be unchanged")
				end
			end
			expect.deepEqual(db.ui, before.ui)
			expect.equal(#info.notes, 0, "a clean v2 database needs no repairs")
		end)

		t:it("adds empty foundations to characters and import backups", function()
			local db = Migrations.Load(v2Database())
			for _, char in ipairs({ db.characters["Aelin-Realm"], db.importBackups["Aelin-Realm"] }) do
				expect.deepEqual(char.sources, { nextId = 1, versions = {} })
				expect.deepEqual(char.interpretations, {})
				expect.deepEqual(char.interpretationKeys, {})
				expect.deepEqual(char.facts, {})
				expect.deepEqual(char.wizard, {})
			end
		end)

		t:it("the step itself only adds containers", function()
			local raw = v2Database()
			local out = Migrations.steps[2](Util.DeepCopy(raw))
			local char = out.characters["Aelin-Realm"]
			for _, part in ipairs(V2_PARTS) do
				expect.deepEqual(char[part], raw.characters["Aelin-Realm"][part])
			end
			expect.deepEqual(char.facts, {})
		end)

		t:it("migrates v1 data through v2 to v3", function()
			local db, info = Migrations.Load({ schemaVersion = 1,
				characters = { A = { nextId = 2, fields = { name = { value = "A", visibility = "public" } },
					family = { { id = 1, name = "B" } }, history = {} } } })
			expect.equal(info.status, "migrated")
			expect.equal(db.characters.A.fields.name.value, "A")
			expect.deepEqual(db.characters.A.facts, {})
			expect.deepEqual(db.characters.A.journal, {})
		end)

		t:it("is idempotent: loading v3 data again changes nothing", function()
			local once = Migrations.Load(v2Database())
			local char = once.characters["Aelin-Realm"]
			char.facts[1] = { id = 9, category = "belief", statement = "Protect the weak.", visibility = "public",
				provenance = { origin = "player", interpreted = false }, createdAt = 1000 }
			char.nextId = 10
			local newBio = "New bio\n\n|cffff0000red|r"
			char.sources = { current = 2, nextId = 3, versions = {
				{ id = 1, kind = "paste", text = "Old {h1}bio{/h1}", hash = Schema.SourceHash("Old {h1}bio{/h1}"),
					meta = {}, capturedAt = 10 },
				{ id = 2, kind = "trp3", text = newBio, hash = Schema.SourceHash(newBio),
					meta = { profile = "Aelin" }, capturedAt = 20 },
			} }
			char.interpretations[1] = { key = "paste:fear:the sea", kind = "candidate", category = "fear",
				statement = "The sea.", origin = "paste", visibility = "private", status = "open", createdAt = 30 }
			char.interpretationKeys["paste:trait:brave"] = { status = "rejected", at = 31 }
			local twice, info = Migrations.Load(Util.DeepCopy(once))
			expect.equal(info.status, "ok")
			expect.deepEqual(twice, once)
			expect.equal(#info.notes, 0)
		end)

		t:it("v3 data opened by a v2-only build is newer and left untouched", function()
			local raw = Util.DeepCopy(Migrations.Load(v2Database()))
			local before = Util.DeepCopy(raw)
			local _, info = Migrations.Load(raw, Migrations.steps, 2)
			expect.equal(info.status, "readOnly")
			expect.truthy(info.reason:find("newer"))
			expect.deepEqual(raw, before)
		end)
	end)

	t:describe("foundation normalisation", function()
		t:it("drops unknown keys in foundation records", function()
			local char = Schema.NormalizeCharacter({
				facts = { { id = 1, category = "belief", statement = "x", visibility = "public", bogus = 1,
					provenance = { origin = "player", interpreted = false, extra = "y" } } },
				wizard = { step = 3 },
				stray = true,
			})
			expect.equal(char.facts[1].bogus, nil)
			expect.equal(char.facts[1].provenance.extra, nil)
			expect.deepEqual(char.wizard, {})
			expect.equal(char.stray, nil)
		end)

		t:it("repairs or drops malformed facts with a report", function()
			local report = {}
			local char = Schema.NormalizeCharacter({ facts = {
				{ id = 1, category = "Not Valid!", statement = "Kept under other" },
				{ id = 2, category = "belief", statement = "   " },
				{ id = 3, category = "belief", statement = "No provenance", provenance = { origin = "aliens" } },
				"garbage",
				{ id = 4, category = "future_kind", statement = "Unknown but well-formed", visibility = "everyone" },
			} }, report)
			expect.equal(#char.facts, 3)
			expect.equal(char.facts[1].category, "other")
			expect.equal(char.facts[2].provenance.origin, "player")
			expect.equal(char.facts[3].category, "future_kind", "well-formed unknown categories are kept")
			expect.equal(char.facts[3].visibility, "private")
			expect.truthy(#report >= 3)
		end)

		t:it("cleans and caps statements and excerpts", function()
			local long = string.rep("\195\169", 200) -- 400 bytes of two-byte characters
			local char = Schema.NormalizeCharacter({ facts = { { id = 1, category = "trait",
				statement = "|cffff0000Brave|r " .. long,
				provenance = { origin = "paste", interpreted = true, excerpt = long, interpretationKey = "k" } } } })
			local fact = char.facts[1]
			expect.truthy(#fact.statement <= Schema.FOUNDATION.statement)
			expect.equal(fact.statement:sub(1, 6), "Brave ")
			expect.truthy(#fact.provenance.excerpt <= Schema.FOUNDATION.excerpt)
			expect.equal(#fact.provenance.excerpt % 2, 0, "cut at a UTF-8 boundary")
		end)

		t:it("keeps IDs unique across family, history, journal and facts", function()
			local char = Schema.NormalizeCharacter({
				nextId = 2,
				family = { { id = 1, name = "A" } },
				history = { { id = 2, text = "B" } },
				journal = { { id = 2, kind = "note", text = "C", createdAt = 1 } },
				facts = { { id = 1, category = "belief", statement = "D" }, { id = 7, category = "fear", statement = "E" } },
			})
			local seen = {}
			for _, list in ipairs({ char.family, char.history, char.journal, char.facts }) do
				for _, item in ipairs(list) do
					expect.falsy(seen[item.id], "duplicate ID " .. tostring(item.id))
					seen[item.id] = true
				end
			end
			expect.equal(char.facts[2].id, 7)
			expect.truthy(char.nextId > 8)
		end)

		t:it("caps facts and open interpretations, and drops resolved or duplicate suggestions", function()
			local facts, items = {}, {}
			for i = 1, Schema.FOUNDATION.facts + 5 do
				facts[i] = { id = i, category = "event", statement = "fact " .. i }
			end
			for i = 1, Schema.FOUNDATION.pending + 5 do
				items[i] = { key = "paste:event:" .. i, kind = "candidate", category = "event", origin = "paste",
					statement = "s" .. i }
			end
			items[#items + 1] = { key = "paste:event:1", kind = "candidate", category = "event", origin = "paste",
				statement = "duplicate" }
			table.insert(items, 1, { key = "paste:event:gone", kind = "insight", category = "event", origin = "paste",
				statement = "already rejected" })
			local report = {}
			local char = Schema.NormalizeCharacter({ facts = facts, interpretations = items,
				interpretationKeys = { ["paste:event:gone"] = { status = "rejected", at = 1 } } }, report)
			expect.equal(#char.facts, Schema.FOUNDATION.facts)
			expect.equal(#char.interpretations, Schema.FOUNDATION.pending)
			expect.equal(char.interpretations[1].key, "paste:event:1")
			expect.truthy(#report >= 2)
		end)

		t:it("caps key memory, dropping the oldest", function()
			local keys = {}
			for i = 1, Schema.FOUNDATION.keyMemory + 3 do
				keys["k" .. i] = { status = i % 2 == 0 and "rejected" or "promoted", at = i }
			end
			keys.bad = { status = "maybe", at = 1 }
			local char = Schema.NormalizeCharacter({ interpretationKeys = keys })
			expect.equal(Util.CountKeys(char.interpretationKeys), Schema.FOUNDATION.keyMemory)
			expect.equal(char.interpretationKeys.k1, nil)
			expect.equal(char.interpretationKeys.k3, nil)
			expect.truthy(char.interpretationKeys.k4)
			expect.equal(char.interpretationKeys.bad, nil)
		end)

		t:it("keeps source text byte for byte and recomputes hashes", function()
			local text = "{h1}Title{/h1}\r\n|cffaabbccColour|r \0 caf\195\169\n\n  trailing  "
			local char = Schema.NormalizeCharacter({ sources = { current = 5, nextId = 6, versions = {
				{ id = 5, kind = "trp3", text = text, hash = "forged", meta = { profile = "P", secret = "x" } },
			} } })
			local v = char.sources.versions[1]
			expect.equal(v.text, text)
			expect.equal(v.hash, Schema.SourceHash(text))
			expect.deepEqual(v.meta, { profile = "P" })
			expect.equal(char.sources.current, 5)
			expect.equal(char.sources.nextId, 6)
		end)

		t:it("drops oversized sources rather than truncating, and repairs the current pointer", function()
			local report = {}
			local char = Schema.NormalizeCharacter({ sources = { current = 2, versions = {
				{ id = 1, kind = "paste", text = "small" },
				{ id = 2, kind = "paste", text = string.rep("x", Schema.FOUNDATION.bioBytes + 1) },
				{ id = 3, kind = "unknown", text = "bad kind" },
			} } }, report)
			expect.equal(#char.sources.versions, 1)
			expect.equal(char.sources.versions[1].text, "small")
			expect.equal(char.sources.current, 1)
			expect.truthy(#report >= 2)
		end)

		t:it("keeps at most three versions and never drops the current one", function()
			local versions = {}
			for i = 1, 5 do
				versions[i] = { id = i, kind = "paste", text = "v" .. i }
			end
			local char = Schema.NormalizeCharacter({ sources = { current = 1, nextId = 6, versions = versions } })
			local ids = {}
			for _, v in ipairs(char.sources.versions) do ids[#ids + 1] = v.id end
			expect.deepEqual(ids, { 1, 4, 5 })
			expect.equal(char.sources.current, 1)
		end)
	end)
end
