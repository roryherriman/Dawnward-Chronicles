local Loader = require("support.loader")

return function(t, expect)
	local ns = Loader.CoreUpTo("Migrations")
	local Schema, Migrations = ns.Schema, ns.Migrations

	t:describe("Schema.NormalizeCharacter", function()
		t:it("keeps known fields, cleans text and drops unknown keys", function()
			local char = Schema.NormalizeCharacter({
				fields = {
					name = { value = "  |cffffffffAelin|r ", visibility = "public" },
					class = { value = "", visibility = "public" },
					bogus = { value = "x" },
				},
				extra = "dropped",
			})
			expect.deepEqual(char.fields, { name = { value = "Aelin", visibility = "public" } })
			expect.equal(char.extra, nil)
		end)

		t:it("defaults bad visibility to private", function()
			local char = Schema.NormalizeCharacter({ fields = { name = { value = "A", visibility = "everyone" } } })
			expect.equal(char.fields.name.visibility, "private")
		end)

		t:it("caps long text", function()
			local char = Schema.NormalizeCharacter({ fields = { summary = { value = string.rep("x", 5000) } } })
			expect.equal(#char.fields.summary.value, Schema.LIMITS.long)
		end)

		t:it("caps list sizes", function()
			local history = {}
			for i = 1, Schema.LISTS.history.limit + 25 do
				history[i] = { id = i, text = "event " .. i }
			end
			local report = {}
			local char = Schema.NormalizeCharacter({ history = history }, report)
			expect.equal(#char.history, Schema.LISTS.history.limit)
			expect.truthy(#report > 0, "the cap should be reported")
		end)

		t:it("drops empty items and repairs duplicate or invalid IDs", function()
			local char = Schema.NormalizeCharacter({
				family = {
					{ id = 3, relation = "mother", name = "Ilsa" },
					{ id = 3, relation = "father" },
					{ id = -1, name = "Cousin" },
					{ status = "living" }, -- no content
				},
				history = { { id = 3, text = "clash" } },
			})
			expect.equal(#char.family, 3)
			expect.equal(#char.history, 1)
			local seen = {}
			for _, list in ipairs({ char.family, char.history }) do
				for _, item in ipairs(list) do
					expect.falsy(seen[item.id], "IDs must be unique across lists")
					seen[item.id] = true
				end
			end
			expect.truthy(char.nextId > 3)
		end)

		t:it("rejects unknown family status", function()
			local char = Schema.NormalizeCharacter({ family = { { name = "A", status = "undead" } } })
			expect.equal(char.family[1].status, "unknown")
		end)

		t:it("never modifies its input", function()
			local raw = { fields = { name = { value = " A " } }, family = { { id = 1, name = "B" } } }
			Schema.NormalizeCharacter(raw)
			expect.equal(raw.fields.name.value, " A ")
		end)
	end)

	t:describe("Migrations.Load", function()
		t:it("creates a new database when nothing is saved", function()
			local db, info = Migrations.Load(nil)
			expect.equal(info.status, "new")
			expect.equal(db.schemaVersion, Schema.VERSION)
			local _, info2 = Migrations.Load({})
			expect.equal(info2.status, "new")
		end)

		t:it("loads and normalises current data", function()
			local raw = { schemaVersion = 1, characters = { ["A-Realm"] = { fields = { name = { value = "A" } } } } }
			local db, info = Migrations.Load(raw)
			expect.equal(info.status, "ok")
			expect.equal(db.characters["A-Realm"].fields.name.value, "A")
			expect.truthy(db ~= raw, "a new table is returned")
		end)

		t:it("is read-only for data from a newer version and leaves it untouched", function()
			local raw = { schemaVersion = 99, characters = { x = 1 } }
			local _, info = Migrations.Load(raw)
			expect.equal(info.status, "readOnly")
			expect.deepEqual(raw, { schemaVersion = 99, characters = { x = 1 } })
		end)

		t:it("is read-only for unversioned or malformed data", function()
			expect.equal(select(2, Migrations.Load({ characters = {} })).status, "readOnly")
			expect.equal(select(2, Migrations.Load({ schemaVersion = "1" })).status, "readOnly")
			expect.equal(select(2, Migrations.Load("garbage")).status, "readOnly")
		end)

		t:it("runs migration steps in order on a copy", function()
			local calls = {}
			local steps = {
				[1] = function(db) calls[#calls + 1] = 1; db.characters.moved = db.old; db.old = nil; return db end,
				[2] = function(db) calls[#calls + 1] = 2; return db end,
			}
			local raw = { schemaVersion = 1, old = { fields = { name = { value = "Kept" } } }, characters = {} }
			local db, info = Migrations.Load(raw, steps, 3)
			expect.equal(info.status, "migrated")
			expect.deepEqual(calls, { 1, 2 })
			expect.equal(db.schemaVersion, 3)
			expect.equal(db.characters.moved.fields.name.value, "Kept")
			expect.truthy(raw.old ~= nil, "raw data must not be modified")
		end)

		t:it("is read-only when a step fails or is missing", function()
			local failing = { [1] = function() error("boom") end }
			local _, info = Migrations.Load({ schemaVersion = 1 }, failing, 2)
			expect.equal(info.status, "readOnly")
			expect.truthy(info.reason:find("boom"))
			local _, info2 = Migrations.Load({ schemaVersion = 1 }, {}, 2)
			expect.equal(info2.status, "readOnly")
		end)
	end)
end
