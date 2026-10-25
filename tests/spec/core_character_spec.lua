local Loader = require("support.loader")

return function(t, expect)
	local ns = Loader.CoreUpTo("Projection")
	local Schema, Character, Projection = ns.Schema, ns.Character, ns.Projection

	local function newChar()
		return Schema.NewCharacter(100)
	end

	t:describe("Character fields", function()
		t:it("sets a field as private by default and keeps visibility on update", function()
			local c = newChar()
			expect.truthy(Character.SetField(c, "name", "Aelin", 200))
			expect.equal(c.fields.name.visibility, "private")
			expect.equal(c.updatedAt, 200)
			Character.SetFieldVisibility(c, "name", "public")
			Character.SetField(c, "name", "Aelin Brightwater")
			expect.deepEqual(c.fields.name, { value = "Aelin Brightwater", visibility = "public" })
		end)

		t:it("rejects unknown fields, empty values and bad visibility", function()
			local c = newChar()
			expect.falsy(Character.SetField(c, "favouriteColour", "blue"))
			expect.falsy(Character.SetField(c, "name", "   "))
			Character.SetField(c, "name", "A")
			local ok, err = Character.SetFieldVisibility(c, "name", "everyone")
			expect.falsy(ok)
			expect.truthy(err:find("public, private or secret"))
		end)

		t:it("clears a field", function()
			local c = newChar()
			Character.SetField(c, "title", "Knight")
			expect.truthy(Character.ClearField(c, "title"))
			expect.equal(c.fields.title, nil)
			expect.falsy(Character.ClearField(c, "title"))
		end)
	end)

	t:describe("Character lists", function()
		t:it("adds family members with sequential IDs and default status", function()
			local c = newChar()
			local a = Character.AddItem(c, "family", { relation = "mother", name = "Ilsa" })
			local b = Character.AddItem(c, "history", { text = "Left home at sixteen" })
			expect.equal(a.id, 1)
			expect.equal(b.id, 2)
			expect.equal(a.status, "unknown")
			expect.equal(a.visibility, "private")
		end)

		t:it("rejects an invalid status instead of silently changing it", function()
			local c = newChar()
			local item, err = Character.AddItem(c, "family", { name = "X", status = "undead" })
			expect.falsy(item)
			expect.truthy(err:find("invalid status"))
		end)

		t:it("updates, hides and removes items by ID", function()
			local c = newChar()
			local item = Character.AddItem(c, "family", { relation = "brother", name = "Tam" })
			expect.truthy(Character.UpdateItem(c, "family", item.id, "status", "deceased"))
			expect.truthy(Character.SetItemVisibility(c, "family", item.id, "secret"))
			expect.equal(item.status, "deceased")
			expect.equal(item.visibility, "secret")
			expect.truthy(Character.RemoveItem(c, "family", item.id))
			expect.equal(#c.family, 0)
			expect.falsy(Character.RemoveItem(c, "family", item.id))
		end)

		t:it("does not find a history ID in the family list", function()
			local c = newChar()
			local h = Character.AddItem(c, "history", { text = "x" })
			expect.falsy(Character.UpdateItem(c, "family", h.id, "name", "y"))
		end)

		t:it("enforces the list limit", function()
			local c = newChar()
			for i = 1, Schema.LISTS.family.limit do
				expect.truthy(Character.AddItem(c, "family", { name = "n" .. i }))
			end
			local item, err = Character.AddItem(c, "family", { name = "one too many" })
			expect.falsy(item)
			expect.truthy(err:find("full"))
		end)
	end)

	t:describe("Projection", function()
		local function sample()
			local c = newChar()
			Character.SetField(c, "name", "Aelin")
			Character.SetFieldVisibility(c, "name", "public")
			Character.SetField(c, "summary", "PRIVATE-SUMMARY")
			Character.SetField(c, "motivation", "SECRET-MOTIVE")
			Character.SetFieldVisibility(c, "motivation", "secret")
			local f = Character.AddItem(c, "family", { name = "SECRET-SIBLING" })
			Character.SetItemVisibility(c, "family", f.id, "secret")
			local h = Character.AddItem(c, "history", { text = "Public deed" })
			Character.SetItemVisibility(c, "history", h.id, "public")
			return c
		end

		t:it("GetPublic contains public facts only", function()
			local p = Projection.GetPublic(sample())
			expect.equal(p.fields.name.value, "Aelin")
			expect.equal(p.fields.summary, nil)
			expect.equal(p.fields.motivation, nil)
			expect.equal(#p.family, 0)
			expect.equal(#p.history, 1)
		end)

		t:it("never leaks private or secret text anywhere in the projection", function()
			local p = Projection.GetPublic(sample())
			local function scan(v)
				if type(v) == "table" then
					for k, x in pairs(v) do
						scan(k)
						scan(x)
					end
				elseif type(v) == "string" then
					expect.falsy(v:find("PRIVATE") or v:find("SECRET"), "leaked: " .. v)
				end
			end
			scan(p)
		end)

		t:it("returns copies that cannot change the character", function()
			local c = sample()
			local p = Projection.GetPublic(c)
			p.fields.name.value = "Changed"
			p.history[1].text = "Changed"
			expect.equal(c.fields.name.value, "Aelin")
			expect.equal(c.history[1].text, "Public deed")
		end)
	end)
end
