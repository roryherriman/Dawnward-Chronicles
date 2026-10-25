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
		t:it("round-trips a backup without secrets by default", function()
			local text = assert(Transfer.Export(sample(), "backup", { addonVersion = "0.1.0" }))
			expect.equal(text:sub(1, 8), "!DWC1!B!")
			local plan = assert(Transfer.Decode(text))
			expect.equal(plan.kind, "backup")
			expect.falsy(plan.includesSecrets)
			expect.equal(plan.addonVersion, "0.1.0")
			expect.equal(plan.character.fields.summary.value, "Grew up by the sea.")
			expect.equal(plan.character.fields.motivation, nil)
			expect.equal(#plan.character.family, 0)
			expect.falsy(text:find("hidden vow", 1, true))
		end)

		t:it("includes secrets only when asked", function()
			local text = assert(Transfer.Export(sample(), "backup", { includeSecrets = true }))
			local plan = assert(Transfer.Decode(text))
			expect.truthy(plan.includesSecrets)
			expect.equal(plan.character.fields.motivation.value, "A hidden vow")
			expect.equal(plan.character.family[1].name, "Corwin")
		end)

		t:it("share exports contain public facts only", function()
			local text = assert(Transfer.Export(sample(), "share"))
			expect.equal(text:sub(1, 8), "!DWC1!S!")
			expect.falsy(text:find("Grew up", 1, true))
			expect.falsy(text:find("Corwin", 1, true))
			expect.truthy(text:find("Aelin", 1, true))
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

		t:it("carries current secrets over when the backup has none", function()
			local current = sample()
			local plan = assert(Transfer.Decode(assert(Transfer.Export(current, "backup"))))
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
end
