-- L2: writing, editing and deleting journal entries through the window.
local Boot = require("support.boot")

local CHAR = "Testchar-TestRealm"

local function click(button)
	button:GetScript("OnClick")(button)
end

local function openJournal()
	local mock, env, ns = Boot.Start()
	mock.Slash("")
	return mock, env, ns, ns.JournalView.section
end

return function(t, expect)
	t:describe("journal editing (L2)", function()
		t:it("writes a new entry with title, text and visibility", function()
			local _, env, _, section = openJournal()
			click(section.newButton)
			expect.truthy(section.editor:IsShown())
			expect.falsy(section.scroll:IsShown(), "the list is replaced by the editor")
			section.editor.title:SetText("Arrival")
			section.editor.area.edit:SetText("The road to Goldshire was quiet.")
			click(section.editor.vis) -- private -> public
			click(section.editor.save)
			expect.falsy(section.editor:IsShown())
			local entry = env.DawnwardChroniclesDB.characters[CHAR].journal[1]
			expect.equal(entry.title, "Arrival")
			expect.equal(entry.text, "The road to Goldshire was quiet.")
			expect.equal(entry.visibility, "public")
			expect.equal(section.rows[1].entry.id, entry.id, "shown at the top of the list")
		end)

		t:it("keeps the editor open and explains why when the entry is empty", function()
			local _, env, ns, section = openJournal()
			click(section.newButton)
			section.editor.area.edit:SetText("   ")
			click(section.editor.save)
			expect.truthy(section.editor:IsShown())
			expect.truthy(ns.MainWindow.GetFrame().status:GetText():find("empty"))
			expect.equal(env.DawnwardChroniclesDB.characters[CHAR], nil)
		end)

		t:it("cancel discards the draft", function()
			local _, env, _, section = openJournal()
			click(section.newButton)
			section.editor.area.edit:SetText("Never mind")
			click(section.editor.cancel)
			expect.falsy(section.editor:IsShown())
			expect.equal(env.DawnwardChroniclesDB.characters[CHAR], nil)
		end)

		t:it("edits an existing entry in place", function()
			local mock, env, _, section = openJournal()
			mock.Slash("journal add First draft")
			click(section.rows[1].edit)
			expect.equal(section.editor.area.edit:GetText(), "First draft")
			section.editor.area.edit:SetText("Second draft")
			click(section.editor.save)
			local entry = env.DawnwardChroniclesDB.characters[CHAR].journal[1]
			expect.equal(entry.text, "Second draft")
			expect.truthy(entry.updatedAt)
			expect.equal(#env.DawnwardChroniclesDB.characters[CHAR].journal, 1)
		end)

		t:it("deletes only after confirmation", function()
			local mock, env, ns, section = openJournal()
			mock.Slash("journal add Delete me")
			click(section.rows[1].delete)
			local dialog = ns.Widgets.dialog
			expect.truthy(dialog and dialog:IsShown(), "asks first")
			expect.equal(dialog:GetFrameStrata(), "DIALOG")
			expect.equal(#env.DawnwardChroniclesDB.characters[CHAR].journal, 1)
			expect.truthy(dialog.text:GetText():find("Delete me", 1, true))
			-- Cancel does nothing.
			click(dialog.cancel)
			expect.equal(#env.DawnwardChroniclesDB.characters[CHAR].journal, 1)
			click(section.rows[1].delete)
			mock.AcceptPopup()
			expect.equal(#env.DawnwardChroniclesDB.characters[CHAR].journal, 0)
			expect.equal(section.visibleCount, 0)
		end)

		t:it("offers no edit or delete for automatic entries", function()
			local mock, _, _, section = openJournal()
			mock.Fire("PLAYER_LEVEL_UP", 7)
			mock.Slash("journal add A note")
			local byKind = {}
			for i = 1, section.visibleCount do
				byKind[section.rows[i].entry.kind] = section.rows[i]
			end
			expect.falsy(byKind.event.edit:IsShown())
			expect.falsy(byKind.event.delete:IsShown())
			expect.truthy(byKind.note.edit:IsShown())
			expect.truthy(byKind.event.vis:IsShown(), "visibility can still change")
		end)

		t:it("a milestone arriving while editing does not discard the draft", function()
			local mock, env, _, section = openJournal()
			click(section.newButton)
			section.editor.area.edit:SetText("Half-written thought")
			mock.Fire("PLAYER_LEVEL_UP", 8)
			expect.truthy(section.editor:IsShown())
			expect.equal(section.editor.area.edit:GetText(), "Half-written thought")
			click(section.editor.save)
			expect.equal(#env.DawnwardChroniclesDB.characters[CHAR].journal, 2)
		end)

		t:it("writes into simulation data while simulation mode is on", function()
			local mock, env, _, section = openJournal()
			mock.Slash("sim on")
			click(section.newButton)
			section.editor.area.edit:SetText("Test entry")
			click(section.editor.save)
			expect.equal(env.DawnwardChroniclesDB.characters[CHAR], nil)
			expect.equal(#env.DawnwardChroniclesSimDB.characters[CHAR].journal, 1)
		end)
	end)
end
