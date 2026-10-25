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
		t:it("edits a short field on one line and saves it as private", function()
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
			expect.truthy(ns.MainWindow.GetFrame().status:GetText():find("Not changed"))
			expect.equal(env.DawnwardChroniclesDB.characters[CHAR], nil, "no empty character created")
		end)

		t:it("shows visibility only for set fields and cycles it", function()
			local mock, env, _, section = openCharacter()
			expect.falsy(rowFor(section, "name").vis:IsShown())
			mock.Slash("set name Aelin")
			local row = rowFor(section, "name")
			expect.truthy(row.vis:IsShown())
			click(row.vis)
			expect.equal(env.DawnwardChroniclesDB.characters[CHAR].fields.name.visibility, "public")
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
			local _, env, ns, section = openCharacter({ savedVariables = { DawnwardChroniclesDB = saved } })
			click(rowFor(section, "name").edit)
			section.editor.line:SetText("X")
			click(section.editor.save)
			expect.truthy(ns.MainWindow.GetFrame().status:GetText():find("read%-only"))
			expect.deepEqual(env.DawnwardChroniclesDB, { schemaVersion = 99, characters = {} })
		end)
	end)
end
