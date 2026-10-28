-- L2: keyboard navigation and inline validation in every form (v0.6).
-- Mocked client: the mock models focus, Tab/Enter/Escape scripts and
-- visibility like the client; real key handling needs TESTING.md part O.
local Boot = require("support.boot")
local Loader = require("support.loader")

local CHAR = "Testchar-TestRealm"

local function click(button)
	button:GetScript("OnClick")(button)
end

local function press(box, script)
	box:GetScript(script)(box)
end

-- What a player typing does: new text, then OnTextChanged(userInput = true).
local function type(box, text)
	box:SetText(text)
	local onChanged = box:GetScript("OnTextChanged")
	if onChanged then onChanged(box, true) end
end

return function(t, expect)
	local function chronicle(tabId)
		local mock, env, ns = Boot.Start()
		mock.Slash("set name Lirael")
		mock.Slash("")
		ns.MainWindow.Select("chronicle")
		local section = ns.ChronicleView.section
		for _, b in ipairs(section.tabButtons) do
			if b.tabId == tabId then click(b) end
		end
		return mock, env, ns, section, section.form
	end

	local function focused(mock)
		return mock.focus
	end

	-- The form row whose field has this key.
	local function row(form, key)
		for _, r in ipairs(form.rows) do
			if r.field and r.field.key == key then return r end
		end
	end

	local function input(form, key)
		return form.InputOf(row(form, key))
	end

	t:describe("keyboard navigation in forms", function()
		t:it("opening a form focuses its first editable field; Tab and Shift+Tab move between fields", function()
			local mock, _, _, section, form = chronicle("identity")
			click(section.new)
			local subject, persona, conviction = input(form, "subject"), input(form, "persona"),
				input(form, "conviction")
			expect.equal(focused(mock), subject, "first field focused")
			press(subject, "OnTabPressed")
			expect.equal(focused(mock), persona)
			press(persona, "OnTabPressed")
			expect.equal(focused(mock), conviction)
			press(conviction, "OnTabPressed")
			expect.equal(focused(mock), subject, "the cycle button is skipped and Tab wraps")
			mock.shift = true
			press(subject, "OnTabPressed")
			expect.equal(focused(mock), conviction, "Shift+Tab goes back")
		end)

		t:it("skips hidden and disabled fields", function()
			local mock, _, _, section, form = chronicle("identity")
			click(section.new)
			local subject = input(form, "subject")
			input(form, "persona"):Hide()
			press(subject, "OnTabPressed")
			expect.equal(focused(mock), input(form, "conviction"), "hidden field skipped")
			input(form, "persona"):Show()
			input(form, "persona"):Disable()
			subject:SetFocus()
			press(subject, "OnTabPressed")
			expect.equal(focused(mock), input(form, "conviction"), "disabled field skipped")
		end)

		t:it("focuses the first editable field even when a choice comes first", function()
			local mock, _, ns, section, form = chronicle("goals")
			local env = ns.ctx
			ns.Goals.Add(ns.Actions.Character(env), { title = "A goal" }, 1)
			ns.MainWindow.Refresh()
			click(section.new)
			expect.equal(focused(mock), input(form, "title"))
		end)

		t:it("Enter moves to the next field and saves only from the last one; multi-line keeps Enter", function()
			local mock, env, _, section, form = chronicle("identity")
			click(section.new)
			local subject = input(form, "subject")
			type(subject, "Stormwind")
			press(subject, "OnEnterPressed")
			expect.truthy(form:IsOpen(), "Enter on a first field never submits")
			expect.equal(focused(mock), input(form, "persona"))
			type(input(form, "persona"), "Loyal")
			press(input(form, "persona"), "OnEnterPressed")
			press(input(form, "conviction"), "OnEnterPressed")
			expect.falsy(form:IsOpen(), "Enter on the last field saves")
			expect.equal(env.DawnwardChroniclesDB.characters[CHAR].story.identity[1].persona, "Loyal")

			click(section.new) -- a memory form: its text area keeps Enter for new lines
			local _, _, _, section2, form2 = chronicle("memories")
			click(section2.new)
			local area = input(form2, "text")
			expect.truthy(area.multiline)
			expect.falsy(area:GetScript("OnEnterPressed"), "no Enter handler: the client inserts a new line")
			expect.truthy(area:GetScript("OnTabPressed"), "Tab still moves on")
		end)

		t:it("Escape closes an unchanged form, and asks before discarding typed changes", function()
			local mock, env, ns, section, form = chronicle("people")
			click(section.new)
			press(input(form, "name"), "OnEscapePressed")
			expect.falsy(form:IsOpen(), "nothing typed: closes at once")
			click(section.new)
			type(input(form, "name"), "Brom")
			press(input(form, "name"), "OnEscapePressed")
			expect.truthy(form:IsOpen(), "asks first")
			local dialog = ns.Widgets.dialog
			expect.truthy(dialog:IsShown())
			click(dialog.cancel)
			expect.truthy(form:IsOpen())
			expect.equal(input(form, "name"):GetText(), "Brom", "typed text kept")
			press(input(form, "name"), "OnEscapePressed")
			mock.AcceptPopup()
			expect.falsy(form:IsOpen())
			expect.equal(#env.DawnwardChroniclesDB.characters[CHAR].story.people, 0, "nothing saved")
		end)

		t:it("shows keyboard focus clearly, and errors differently from focus", function()
			local _, _, ns, section, form = chronicle("arcs")
			click(section.new)
			local title = input(form, "title")
			local theme = ns.Style.Current()
			expect.truthy(title.focusBar:IsShown(), "a focus bar")
			expect.equal(title.focusBar.__color[1], theme.accent[1])
			expect.equal(title.edges.top.__color[1], theme.accent[1])
			click(form.save)
			expect.truthy(title.invalid)
			expect.equal(title.focusBar.__color[1], theme.danger[1], "an invalid field uses the danger colour")
			expect.truthy(title.errorLabel:GetText():find("^! "), "not colour alone: the message starts with !")
		end)
	end)

	t:describe("inline validation in forms", function()
		t:it("Stances: the empty field is marked, focused and explained; what was typed is kept", function()
			local mock, env, _, section, form = chronicle("identity")
			click(section.new)
			type(input(form, "conviction"), "Doubts its leaders")
			click(form.save)
			local subject = input(form, "subject")
			expect.truthy(form:IsOpen())
			expect.truthy(subject.invalid)
			expect.equal(focused(mock), subject, "focus moves to the invalid field")
			expect.truthy(subject.errorLabel:IsShown())
			expect.equal(input(form, "conviction"):GetText(), "Doubts its leaders", "typed data preserved")
			expect.equal(#env.DawnwardChroniclesDB.characters[CHAR].story.identity, 0)
			-- Correcting the field clears its error.
			type(subject, "Darnassus")
			expect.falsy(subject.invalid)
			expect.falsy(subject.errorLabel:IsShown())
			-- Neither side: the public stance is pointed at.
			type(input(form, "conviction"), "")
			click(form.save)
			expect.truthy(input(form, "persona").invalid)
			expect.falsy(subject.invalid)
		end)

		t:it("People: a player's character without a realm marks the realm field", function()
			local mock, env, _, section, form = chronicle("people")
			click(section.new)
			type(input(form, "name"), "Aria")
			row(form, "kind").value = "player"
			click(form.save)
			local realm = input(form, "realm")
			expect.truthy(realm.invalid)
			expect.truthy(realm.errorLabel:GetText():find("needs a realm", 1, true))
			expect.equal(focused(mock), realm)
			expect.equal(input(form, "name"):GetText(), "Aria")
			type(realm, "Silverhand")
			expect.falsy(realm.invalid)
			click(form.save)
			expect.falsy(form:IsOpen())
			expect.equal(env.DawnwardChroniclesDB.characters[CHAR].story.people[1].realm, "Silverhand")
		end)

		t:it("People: a duplicate is explained beside the name", function()
			local mock, _, _, section, form = chronicle("people")
			mock.Slash("person add npc Brom; Innkeeper")
			click(section.new)
			type(input(form, "name"), "brom")
			click(form.save)
			expect.truthy(input(form, "name").errorLabel:GetText():find("is already", 1, true))
		end)

		t:it("Goals: a non-number target and an unseen faction are marked on their own fields", function()
			local _, _, _, section, form = chronicle("goals")
			click(section.new)
			type(input(form, "title"), "Earn trust")
			type(input(form, "target"), "twenty")
			click(form.save)
			expect.truthy(input(form, "target").invalid)
			expect.truthy(input(form, "target").errorLabel:GetText():find("whole number", 1, true))
			expect.equal(input(form, "title"):GetText(), "Earn trust")
			type(input(form, "target"), "")
			type(input(form, "faction"), "Darnassus")
			click(form.save)
			expect.truthy(input(form, "faction").invalid)
			expect.truthy(input(form, "faction").errorLabel:GetText():find("has not seen", 1, true))
			type(input(form, "target"), "20")
			click(form.save)
			expect.truthy(input(form, "faction").errorLabel:GetText():find("not both", 1, true))
		end)

		t:it("Memories, Arcs, Family and History mark their first field", function()
			local _, _, _, section, form = chronicle("memories")
			click(section.new)
			click(form.save)
			expect.truthy(input(form, "title").errorLabel:GetText():find("needs a title or some text", 1, true))
			local _, _, _, s2, f2 = chronicle("arcs")
			click(s2.new)
			click(f2.save)
			expect.truthy(input(f2, "title").errorLabel:GetText():find("needs a title", 1, true))

			local mock, _, ns = Boot.Start()
			mock.Slash("set name Lirael")
			mock.Slash("")
			ns.MainWindow.Select("character")
			local cv = ns.CharacterView.section
			cv:OpenItemForm("family", nil)
			click(cv.form.save)
			local relation = cv.form.InputOf(cv.form.rows[1])
			expect.truthy(relation.invalid)
			expect.truthy(relation.errorLabel:GetText():find("Nothing to add", 1, true))
			expect.equal(mock.focus, relation)
		end)

		t:it("error lines push later fields down and stay inside the form", function()
			local _, _, ns, section, form = chronicle("people")
			click(section.new)
			local before = form.contentBottom
			ns.Widgets.SetFieldError(input(form, "name"), "a long explanation that wraps onto more than one line "
				.. "because it is very long indeed")
			expect.truthy(form.contentBottom > before, "room is made for the message")
			expect.truthy(form.contentBottom <= 412 - 50, "above the buttons, inside the window")
			ns.Widgets.SetFieldError(input(form, "name"), nil)
			expect.equal(form.contentBottom, before, "and given back when it clears")
		end)

		t:it("reopening a form starts without old errors", function()
			local _, _, _, section, form = chronicle("arcs")
			click(section.new)
			click(form.save)
			expect.truthy(input(form, "title").invalid)
			click(form.cancel)
			click(section.new)
			expect.falsy(input(form, "title").invalid)
		end)

		t:it("the danger colour stays readable on every theme", function()
			local ns = Loader.CoreUpTo("Themes")
			for _, theme in ipairs(ns.Themes.LIST) do
				for _, surface in ipairs({ "panel", "background", "surface" }) do
					expect.truthy(ns.Themes.Contrast(theme.danger, theme[surface]) >= 4.5, theme.id .. " danger on " .. surface)
				end
			end
		end)
	end)

	t:describe("keyboard in the editors and the setup wizard", function()
		t:it("Journal editor: title first, Tab and Enter to the text, Escape asks about typed text", function()
			local mock, env, ns = Boot.Start()
			mock.Slash("")
			local section = ns.JournalView.section
			click(section.newButton)
			local editor = section.editor
			expect.equal(mock.focus, editor.title, "first editable field")
			type(editor.title, "A title")
			press(editor.title, "OnEnterPressed")
			expect.equal(mock.focus, editor.area.edit, "Enter on the title moves to the text")
			press(editor.area.edit, "OnEscapePressed")
			expect.truthy(ns.Widgets.dialog:IsShown(), "asks before discarding")
			mock.AcceptPopup()
			expect.falsy(editor:IsShown())
			expect.falsy(env.DawnwardChroniclesDB.characters[CHAR])
		end)

		t:it("Character editor: Enter saves a one-line field, Escape cancels", function()
			local mock, env, ns = Boot.Start()
			mock.Slash("")
			ns.MainWindow.Select("character")
			local section = ns.CharacterView.section
			section:OpenEditor(ns.Schema.FIELD_BY_KEY.title)
			expect.equal(mock.focus, section.editor.line)
			type(section.editor.line, "Wanderer")
			press(section.editor.line, "OnEnterPressed")
			expect.falsy(section.editor:IsShown())
			expect.equal(env.DawnwardChroniclesDB.characters[CHAR].fields.title.value, "Wanderer")
			section:OpenEditor(ns.Schema.FIELD_BY_KEY.title)
			press(section.editor.line, "OnEscapePressed")
			expect.falsy(section.editor:IsShown(), "unchanged: closes at once")
		end)

		t:it("setup wizard: Character page focuses Name; Tab, Enter and Escape behave; the draft is kept", function()
			local mock, env, ns = Boot.Start({ wizard = true })
			mock.Slash("")
			ns.SetupWizard.Go(2)
			local w = ns.SetupWizard.Frame()
			local function field(key)
				for _, i in ipairs(w.inputs) do if i.fieldKey == key then return i end end
			end
			expect.equal(mock.focus, field("name"))
			press(field("name"), "OnTabPressed")
			expect.equal(mock.focus, field("title"))
			type(field("homeland"), "Goldshire")
			press(field("homeland"), "OnEnterPressed")
			expect.equal(mock.focus, field("summary"), "Enter moves on to the summary")
			expect.truthy(field("summary").multiline)
			press(field("summary"), "OnEscapePressed")
			expect.falsy(ns.SetupWizard.IsShown(), "Escape closes setup")
			expect.equal(env.DawnwardChroniclesDB.ui.wizardDrafts[CHAR].values.homeland, "Goldshire",
				"what was typed is kept in the draft")
		end)

		t:it("setup wizard: Enter on the last one-line field goes to the next page when Summary is hidden", function()
			local mock, _, ns = Boot.Start({ wizard = true })
			mock.Slash("")
			ns.SetupWizard.Go(2)
			local w = ns.SetupWizard.Frame()
			local summary
			for _, i in ipairs(w.inputs) do if i.fieldKey == "summary" then summary = i end end
			summary.anchorRegion:Hide()
			local homeland
			for _, i in ipairs(w.inputs) do if i.fieldKey == "homeland" then homeland = i end end
			press(homeland, "OnEnterPressed")
			expect.equal(w.page, 3)
		end)
	end)
end
