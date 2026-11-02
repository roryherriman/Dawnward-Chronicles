local Loader = require("support.loader")

return function(t, expect)
	local ns = Loader.CoreUpTo("Transfer")
	local Schema, Character, Serializer, Transfer = ns.Schema, ns.Character, ns.Serializer, ns.Transfer

	t:describe("Serializer", function()
		t:it("round-trips nested plain data", function()
			local data = {
				s = 'quote " backslash \\ newline \n tab \t nul \0 bell \7 utf8 \195\169',
				n = -12.5, i = 42, big = 2 ^ 40, yes = true, no = false,
				list = { 1, "two", { three = 3 } },
				[7] = "numeric key",
			}
			local text = assert(Serializer.Encode(data))
			expect.deepEqual(assert(Serializer.Decode(text)), data)
		end)

		t:it("is deterministic", function()
			expect.equal(Serializer.Encode({ b = 1, a = 2, [2] = 3, [1] = 4 }),
				Serializer.Encode({ [1] = 4, a = 2, [2] = 3, b = 1 }))
		end)

		t:it("refuses functions, cycles and deep nesting", function()
			expect.falsy(Serializer.Encode({ f = print }))
			local cyc = {}
			cyc.me = cyc
			expect.falsy(Serializer.Encode(cyc))
			local deep = {}
			local cur = deep
			for _ = 1, Serializer.MAX_DEPTH + 2 do
				cur.x = {}
				cur = cur.x
			end
			expect.falsy(Serializer.Encode(deep))
		end)

		t:it("never executes input and rejects anything outside the format", function()
			local executed = false
			_G.__dawnwardPwned = function() executed = true end
			for _, bad in ipairs({
				"__dawnwardPwned()", '{"a"=__dawnwardPwned()}', "{a=1}", '{"a"=1', '{"a"=1}junk',
				'{"a"=1,"a"=2}', '"unterminated', '"bad\\q"', "nil", "",
			}) do
				local value = Serializer.Decode(bad)
				expect.equal(value, nil, "should reject: " .. bad)
			end
			_G.__dawnwardPwned = nil
			expect.falsy(executed)
		end)

		t:it("rejects oversized and over-nested input", function()
			expect.falsy(Serializer.Decode(string.rep(" ", Serializer.MAX_INPUT + 1)))
			local nested = string.rep('{"x"=', Serializer.MAX_DEPTH + 2) .. "1" .. string.rep("}", Serializer.MAX_DEPTH + 2)
			local value, err = Serializer.Decode(nested)
			expect.falsy(value)
			expect.truthy(err:find("nested too deeply"))
		end)
	end)

	local function sample()
		local c = Schema.NewCharacter(100)
		Character.SetField(c, "name", "Aelin")
		Character.SetFieldVisibility(c, "name", "public")
		Character.SetField(c, "summary", "Grew up by the sea.")
		Character.SetField(c, "motivation", "A hidden vow")
		Character.SetFieldVisibility(c, "motivation", "secret")
		local f = Character.AddItem(c, "family", { relation = "father", name = "Corwin", status = "deceased" })
		Character.SetItemVisibility(c, "family", f.id, "secret")
		Character.AddItem(c, "history", { when = "Year 3", text = "Joined the guard" })
		return c
	end

	t:describe("Transfer", function()
		t:it("a backup (v0.10) always includes everything, whatever an item's old visibility", function()
			local text = assert(Transfer.Export(sample(), "backup", { addonVersion = "0.1.0" }))
			expect.equal(text:sub(1, 8), "!DWC1!B!")
			local plan = assert(Transfer.Decode(text))
			expect.equal(plan.kind, "backup")
			expect.truthy(plan.includesSecrets)
			expect.equal(plan.addonVersion, "0.1.0")
			expect.equal(plan.character.fields.summary.value, "Grew up by the sea.")
			expect.equal(plan.character.fields.motivation.value, "A hidden vow")
			expect.equal(plan.character.family[1].name, "Corwin")
			expect.equal(#plan.character.history, 1)
		end)

		t:it("an older backup that left secrets out still imports (the smaller shape older versions wrote)",
			function()
			local text = assert(Transfer.Export(sample(), "backup", { includeSecrets = false }))
			local plan = assert(Transfer.Decode(text))
			expect.falsy(plan.includesSecrets)
			expect.equal(plan.character.fields.motivation, nil)
			expect.equal(#plan.character.family, 0)
			expect.falsy(text:find("hidden vow", 1, true))
		end)

		t:it("share exports of a character waiting for the one-time confirmation hold what was marked Public",
			function()
			local text = assert(Transfer.Export(sample(), "share"))
			expect.equal(text:sub(1, 8), "!DWC1!S!")
			expect.falsy(text:find("Grew up", 1, true))
			expect.falsy(text:find("Corwin", 1, true))
			expect.truthy(text:find("Aelin", 1, true))
		end)

		t:it("share exports (v0.10) hold the whole published profile and never journal notes or the story",
			function()
			local c = sample()
			ns.Publication.Adopt(c, 1)
			ns.Journal.AddNote(c, { text = "NOTE-MARKER" }, 2)
			local text = assert(Transfer.Export(c, "share"))
			for _, marker in ipairs({ "Aelin", "Grew up", "hidden vow", "Corwin", "Joined the guard" }) do
				expect.truthy(text:find(marker, 1, true), "profile part missing: " .. marker)
			end
			expect.falsy(text:find("NOTE-MARKER", 1, true))
			local plan = assert(Transfer.Decode(text))
			expect.equal(plan.kind, "share")
			expect.equal(#plan.character.journal, 0)
		end)

		t:it("tolerates surrounding whitespace but detects tampering and truncation", function()
			local text = assert(Transfer.Export(sample(), "backup"))
			expect.truthy(Transfer.Decode("  \n" .. text .. "\n "))
			local tampered = text:gsub("Aelin", "Aelim")
			local plan, err = Transfer.Decode(tampered)
			expect.falsy(plan)
			expect.truthy(err:find("checksum"))
			expect.falsy(Transfer.Decode(text:sub(1, #text - 5)))
			expect.falsy(Transfer.Decode("hello"))
			expect.falsy(Transfer.Decode(nil))
		end)

		t:it("rejects exports from a newer schema", function()
			local payload = Serializer.Encode({
				format = 1, kind = "backup", schemaVersion = Schema.VERSION + 1, character = {},
			})
			local text = "!DWC1!B!" .. Transfer.Checksum(payload) .. "!" .. payload
			local plan, err = Transfer.Decode(text)
			expect.falsy(plan)
			expect.truthy(err:find("newer version"))
		end)

		t:it("normalises imported data through the schema", function()
			local payload = Serializer.Encode({ format = 1, kind = "backup", schemaVersion = 1,
				character = { fields = { name = { value = "|cffff0000Red|r", visibility = "public" }, evil = { value = "x" } } } })
			local plan = assert(Transfer.Decode("!DWC1!B!" .. Transfer.Checksum(payload) .. "!" .. payload))
			expect.equal(plan.character.fields.name.value, "Red")
			expect.equal(plan.character.fields.evil, nil)
		end)

		t:it("carries current secrets over when an older backup has none", function()
			local current = sample()
			local plan = assert(Transfer.Decode(assert(Transfer.Export(current, "backup", { includeSecrets = false }))))
			local merged, carried = Transfer.MergeForImport(current, plan.character, plan.includesSecrets, 500)
			expect.equal(carried, 2)
			expect.equal(merged.fields.motivation.value, "A hidden vow")
			expect.equal(merged.family[1].name, "Corwin")
			expect.equal(merged.createdAt, 100)
			local seen = {}
			for _, list in ipairs({ merged.family, merged.history }) do
				for _, item in ipairs(list) do
					expect.falsy(seen[item.id], "IDs stay unique after merging")
					seen[item.id] = true
				end
			end
		end)

		t:it("checksum matches the Adler-32 reference value", function()
			-- Adler-32("Wikipedia") = 0x11E60398
			expect.equal(Transfer.Checksum("Wikipedia"), "11e60398")
		end)
	end)

	t:describe("Transfer and character foundations (v0.3)", function()
		local Facts, Sources, Interpretations = ns.Facts, ns.Sources, ns.Interpretations

		local function planted()
			local c = sample()
			Facts.Add(c, { category = "belief", statement = "PUBLIC-FACT", visibility = "public" })
			Facts.Add(c, { category = "fear", statement = "PRIVATE-FACT" })
			Facts.Add(c, { category = "origin", statement = "SECRET-FACT", visibility = "secret" })
			Sources.Capture(c, "paste", "SOURCE-MARKER biography", { note = "META-MARKER" }, 1)
			Interpretations.Propose(c, { kind = "candidate", category = "trait", statement = "OPEN-MARKER",
				origin = "paste", excerpt = "EXCERPT-MARKER" }, 2)
			local rejected = Interpretations.Propose(c, { kind = "insight", category = "trait",
				statement = "REJECTED-MARKER", origin = "paste" }, 3)
			Interpretations.Reject(c, rejected.key, 4)
			return c
		end

		t:it("share exports contain public facts only and never sources, suggestions or keys", function()
			local text = assert(Transfer.Export(planted(), "share", { includeBiography = true, includeSecrets = true }))
			expect.truthy(text:find("PUBLIC-FACT", 1, true))
			for _, marker in ipairs({ "PRIVATE-FACT", "SECRET-FACT", "SOURCE-MARKER", "META-MARKER", "OPEN-MARKER",
				"EXCERPT-MARKER", "REJECTED-MARKER", "rejected-marker", "interpretation", "sources" }) do
				expect.falsy(text:find(marker, 1, true), "share export leaked " .. marker)
			end
		end)

		t:it("backups carry facts, suggestions, key memory and the biography sources (v0.10: always)", function()
			local c = planted()
			local plan = assert(Transfer.Decode(assert(Transfer.Export(c, "backup"))))
			expect.truthy(plan.includesBiography)
			expect.truthy(plan.includesSecrets)
			expect.equal(#plan.character.facts, 3)
			expect.equal(#plan.character.interpretations, 1)
			expect.equal(ns.Util.CountKeys(plan.character.interpretationKeys), 1)
			expect.equal(Sources.Current(plan.character).text, "SOURCE-MARKER biography")
			expect.truthy(Transfer.Describe(plan):find("includes the stored biography"))

			-- The shape older versions wrote by default: no sources, no secrets.
			local old = assert(Transfer.Export(c, "backup", { includeBiography = false, includeSecrets = false }))
			expect.falsy(old:find("SOURCE-MARKER", 1, true))
			expect.falsy(old:find("SECRET-FACT", 1, true))
			local oldPlan = assert(Transfer.Decode(old))
			expect.falsy(oldPlan.includesBiography)
			expect.equal(#oldPlan.character.facts, 2)
			expect.equal(oldPlan.character.sources.current, nil)
		end)

		t:it("restoring an older backup without sources keeps the current sources; with sources replaces them",
			function()
			local c = planted()
			local plan = assert(Transfer.Decode(assert(Transfer.Export(c, "backup", { includeBiography = false }))))
			Sources.Capture(c, "paste", "NEWER biography", nil, 9)
			local merged = Transfer.MergeForImport(c, plan.character, plan.includesSecrets, 10, plan.includesBiography)
			expect.equal(Sources.Current(merged).text, "NEWER biography")
			expect.equal(#Sources.Versions(merged), 2)

			local bioPlan = assert(Transfer.Decode(assert(Transfer.Export(planted(), "backup"))))
			local replaced = Transfer.MergeForImport(c, bioPlan.character, false, 11, true)
			expect.equal(Sources.Current(replaced).text, "SOURCE-MARKER biography")
		end)

		t:it("secret facts carry over from an older backup with unique IDs, and key memory is merged", function()
			local c = planted()
			local plan = assert(Transfer.Decode(assert(Transfer.Export(c, "backup", { includeSecrets = false,
				includeBiography = false }))))
			local later = Interpretations.Propose(c, { kind = "candidate", category = "fear", statement = "LATER",
				origin = "paste" }, 20)
			Interpretations.Reject(c, later.key, 21)
			local merged, carried = Transfer.MergeForImport(c, plan.character, false, 30, false)
			expect.equal(carried, 3, "secret field, secret family member and secret fact")
			local statements, seen = {}, {}
			for _, f in ipairs(merged.facts) do
				statements[#statements + 1] = f.statement
				expect.falsy(seen[f.id])
				seen[f.id] = true
			end
			expect.truthy(table.concat(statements, " "):find("SECRET-FACT", 1, true))
			for _, list in ipairs({ merged.family, merged.history, merged.journal }) do
				for _, item in ipairs(list) do
					expect.falsy(seen[item.id], "IDs unique across all lists")
					seen[item.id] = true
				end
			end
			expect.equal(merged.interpretationKeys[later.key].status, "rejected")
		end)

		t:it("a suggestion resolved after the backup stays resolved on restore", function()
			local c = planted()
			local plan = assert(Transfer.Decode(assert(Transfer.Export(c, "backup"))))
			local open = Interpretations.Open(c)[1]
			Interpretations.Promote(c, open.key, nil, 40)
			local merged = Transfer.MergeForImport(c, plan.character, false, 50, false)
			expect.equal(#merged.interpretations, 0)
		end)

		t:it("v0.2 exports import with empty foundations", function()
			local payload = Serializer.Encode({ format = 1, kind = "backup", schemaVersion = 2, includesSecrets = false,
				character = { fields = { name = { value = "Old", visibility = "public" } }, family = {}, history = {},
					journal = {}, journalKeys = {}, theme = "arcane" } })
			local plan = assert(Transfer.Decode("!DWC1!B!" .. Transfer.Checksum(payload) .. "!" .. payload))
			expect.equal(plan.character.theme, "arcane")
			expect.deepEqual(plan.character.facts, {})
			expect.deepEqual(plan.character.interpretations, {})
			expect.deepEqual(plan.character.sources, { nextId = 1, versions = {} })
		end)

		t:it("sources smuggled into a backup without the biography flag are ignored", function()
			local payload = Serializer.Encode({ format = 1, kind = "backup", schemaVersion = 3,
				character = { sources = { current = 1, nextId = 2, versions = { { id = 1, kind = "paste", text = "X" } } } } })
			local plan = assert(Transfer.Decode("!DWC1!B!" .. Transfer.Checksum(payload) .. "!" .. payload))
			expect.equal(plan.character.sources.current, nil)
		end)

		t:it("Util.Checksum and the Transfer alias agree", function()
			expect.equal(Transfer.Checksum, ns.Util.Checksum)
		end)
	end)
end
