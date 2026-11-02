-- L2: editing profile fields from the Character section.
local Boot = require("support.boot")

local CHAR = "Testchar-TestRealm"

local function click(button)
	button:GetScript("OnClick")(button)
end

local function openCharacter(opts)
	local mock, env, ns = Boot.Start(opts)
	mock.Slash("")
	ns.MainWindow.Select("character")
	return mock, env, ns, ns.CharacterView.section
end

local function rowFor(section, key)
	for i, spec in ipairs(section.specs) do
		if spec.kind == "field" and spec.field.key == key then
			return section.rows[i]
		end
	end
end

return function(t, expect)
	t:describe("character editing (L2)", function()
		t:it("edits a short field on one line and saves it (the stored default visibility is untouched)", function()
			local _, env, _, section = openCharacter()
			click(rowFor(section, "name").edit)
			expect.truthy(section.editor:IsShown())
			expect.truthy(section.editor.line:IsShown())
			expect.falsy(section.editor.area.frame:IsShown())
			section.editor.line:SetText("Aelin Brightwater")
			click(section.editor.save)
			expect.falsy(section.editor:IsShown())
			expect.deepEqual(env.DawnwardChroniclesDB.characters[CHAR].fields.name,
				{ value = "Aelin Brightwater", visibility = "private" })
		end)

		t:it("edits a long field in a text area", function()
			local _, env, _, section = openCharacter()
			click(rowFor(section, "summary").edit)
			expect.truthy(section.editor.area.frame:IsShown())
			expect.falsy(section.editor.line:IsShown())
			section.editor.area.edit:SetText("Raised by the sea.\nNever forgot it.")
			click(section.editor.save)
			expect.equal(env.DawnwardChroniclesDB.characters[CHAR].fields.summary.value,
				"Raised by the sea.\nNever forgot it.")
		end)

		t:it("reuses validation: empty text is refused and the editor stays open", function()
			local _, env, ns, section = openCharacter()
			click(rowFor(section, "title").edit)
			section.editor.line:SetText("   ")
			click(section.editor.save)
			expect.truthy(section.editor:IsShown())
			local line = section.editor.line
			expect.truthy(line.invalid, "the field is marked")
			expect.truthy(line.errorLabel:GetText():find("! Value is empty.", 1, true), line.errorLabel:GetText())
			expect.truthy(line:HasFocus(), "focus stays on the field")
			expect.equal(line:GetText(), "   ", "what was typed is kept")
			expect.falsy(ns.MainWindow.GetFrame().status:GetText():find("Not changed"), "not at the bottom")
			expect.equal(env.DawnwardChroniclesDB.characters[CHAR], nil, "no empty character created")
		end)

		t:it("offers Add on an empty field and Edit on a set one, and nothing to classify", function()
			local mock, _, _, section = openCharacter()
			expect.equal(rowFor(section, "name").edit:GetText(), "Add")
			mock.Slash("set name Aelin")
			local row = rowFor(section, "name")
			expect.equal(row.edit:GetText(), "Edit")
			expect.equal(row.vis, nil, "no visibility chip")
		end)

		t:it("clears a field only after confirmation", function()
			local mock, env, _, section = openCharacter()
			mock.Slash("set title Knight")
			click(rowFor(section, "title").edit)
			expect.truthy(section.editor.clear:IsShown())
			click(section.editor.clear)
			expect.equal(env.DawnwardChroniclesDB.characters[CHAR].fields.title.value, "Knight")
			mock.AcceptPopup()
			expect.equal(env.DawnwardChroniclesDB.characters[CHAR].fields.title, nil)
			expect.falsy(section.editor:IsShown())
		end)

		t:it("does not offer Clear for an empty field", function()
			local _, _, _, section = openCharacter()
			click(rowFor(section, "faith").edit)
			expect.falsy(section.editor.clear:IsShown())
		end)

		t:it("refuses edits on read-only data", function()
			local saved = { schemaVersion = 99, characters = {} }
			local _, env, _, section = openCharacter({ savedVariables = { DawnwardChroniclesDB = saved } })
			click(rowFor(section, "name").edit)
			section.editor.line:SetText("X")
			click(section.editor.save)
			expect.truthy(section.editor.line.errorLabel:GetText():find("read%-only"))
			expect.deepEqual(env.DawnwardChroniclesDB, { schemaVersion = 99, characters = {} })
		end)

		t:it("adds, edits and removes family and history from forms (#17)", function()
			local mock, env, ns, section = openCharacter()
			local function specRow(kind, list)
				for i, spec in ipairs(section.specs) do
					if spec.kind == kind and spec.list == list then return section.rows[i] end
				end
			end
			local function fill(values)
				for _, row in ipairs(section.form.rows) do
					local v = row.field and values[row.field.key]
					if v ~= nil then
						if row.field.kind == "area" then row.area.edit:SetText(v)
						elseif row.field.kind == "cycle" then row.value = v
						else row.line:SetText(v) end
					end
				end
				click(section.form.save)
			end
			click(specRow("add", "family").edit)
			fill({ relation = "sister", name = "Mira", status = "missing" })
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			expect.equal(char.family[1].name, "Mira")
			expect.equal(char.family[1].status, "missing")
			expect.equal(char.family[1].visibility, "private")
			click(specRow("item", "family").edit)
			fill({ notes = "Last seen in Westfall" })
			expect.equal(char.family[1].notes, "Last seen in Westfall")
			expect.equal(char.family[1].name, "Mira", "other fields kept")
			click(specRow("item", "family").edit)
			fill({ relation = "", name = "", notes = "" })
			expect.truthy(section.form:IsOpen(), "an edit cannot empty the entry")
			click(section.form.cancel)
			expect.equal(specRow("item", "family").vis, nil, "no visibility chip")

			-- Long notes written from chat survive an edit of another field.
			local long = string.rep("n", 1500)
			char.family[1].notes = long
			click(specRow("item", "family").edit)
			for _, row in ipairs(section.form.rows) do
				if row.field and row.field.key == "notes" then
					expect.equal(row.area.edit.__maxBytes, 2001)
				end
			end
			fill({ status = "deceased" })
			expect.equal(char.family[1].notes, long)

			click(specRow("add", "history").edit)
			fill({ when = "As a child", text = "Learned to ride" })
			expect.equal(char.history[1].text, "Learned to ride")
			click(specRow("item", "history").edit)
			click(section.form.delete)
			expect.equal(#char.history, 1, "nothing removed before confirming")
			mock.AcceptPopup()
			expect.equal(#char.history, 0)
			expect.falsy(ns.CharacterView.section.form:IsOpen())
		end)
	end)
end
