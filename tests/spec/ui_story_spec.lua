-- L2: the Story section, reaction card, journal approvals and story
-- settings through the window (mocked client; not in-game evidence).
local Boot = require("support.boot")

local CHAR = "Testchar-TestRealm"

local function click(button)
	button:GetScript("OnClick")(button)
end

local function turnIn(mock, id, title)
	mock.quest = { id = id, title = title, level = 20 }
	mock.Fire("QUEST_COMPLETE")
	mock.Fire("QUEST_TURNED_IN", id, 100, 10)
end

-- x, y of a widget's TOPLEFT relative to the section frame, following
-- TOPLEFT anchors up through its parents (each anchored TOPLEFT to TOPLEFT).
local function offset(widget, root)
	local x, y = 0, 0
	local w = widget
	while w and w ~= root do
		local found
		for _, p in ipairs(w.__points or {}) do
			if p[1] == "TOPLEFT" then found = p end
		end
		if not found then return nil end
		x, y = x + found[#found - 1], y + found[#found]
		w = w.__parent
	end
	return x, y
end

return function(t, expect)
	local function start()
		local mock, env, ns = Boot.Start()
		mock.Slash("set name Morrow")
		mock.Slash("")
		ns.MainWindow.Select("story")
		return mock, env, ns, ns.StoryView.section
	end

	t:describe("Story section (L2)", function()
		t:it("shows an empty state with a summary until something happens", function()
			local _, _, _, section = start()
			expect.truthy(section.heading:IsShown())
			expect.falsy(section.question:IsShown())
			expect.truthy(section.summary:GetText():find("0 waiting moments", 1, true))
		end)

		t:it("answers a moment with a button, then approves the change", function()
			local mock, env, ns, section = start()
			turnIn(mock, 10, "The Defias Brotherhood")
			ns.MainWindow.Refresh()
			expect.truthy(section.question:IsShown())
			expect.truthy(section.question:GetText():find("Morrow", 1, true))
			expect.truthy(section.optionButtons[1]:IsShown())
			local last
			for _, b in ipairs(section.optionButtons) do
				if b:IsShown() then last = b end
			end
			expect.equal(last:GetText(), "Nothing worth remembering.")
			click(section.optionButtons[1])
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			expect.equal(#char.story.reactions, 0)
			expect.equal(#char.story.decisions, 1)
			expect.truthy(section.changeRows[1]:IsShown())
			local before = char.personality.compassion
			click(section.changeRows[1].approve)
			expect.truthy(char.personality.compassion ~= before)
			expect.falsy(section.changeRows[1]:IsShown())
			expect.truthy(section.heading:IsShown(), "back to the empty state")
		end)

		t:it("saves an answer in the player's own words, and supports later and dismiss", function()
			local mock, env, ns, section = start()
			turnIn(mock, 11, "One")
			mock.zone = "Duskwood"
			mock.Slash("story set frequency frequent")
			env.DawnwardChroniclesDB.characters[CHAR].story.pacing.playByCategory = {}
			turnIn(mock, 12, "Two")
			ns.MainWindow.Refresh()
			expect.truthy(section.position:GetText():find("of 2", 1, true))
			click(section.later)
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			expect.equal(char.story.reactions[1].status, "postponed")
			ns.MainWindow.Refresh()
			section.custom:SetText("He kept the money and said nothing.")
			click(section.save)
			expect.equal(char.story.decisions[1].custom, "He kept the money and said nothing.")
			ns.MainWindow.Refresh()
			click(section.dismiss)
			expect.equal(#char.story.reactions, 0)
		end)

		t:it("fits every control inside the content area", function()
			local mock, _, ns, section = start()
			turnIn(mock, 13, "Fit")
			ns.MainWindow.Refresh()
			local contentHeight = ns.MainWindow.ContentHeight()
			local contentWidth = ns.MainWindow.ContentWidth()
			local widgets = { section.later, section.dismiss, section.customArea.frame, section.question,
				section.changeRows[1], section.waitingPanel, section.growthPanel, section.card }
			for _, b in ipairs(section.optionButtons) do widgets[#widgets + 1] = b end
			for _, w in ipairs(widgets) do
				local x, y = offset(w, section.frame)
				if not w:IsShown() then x, y = 0, 0 end
				expect.truthy(y, "anchored by TOPLEFT")
				expect.truthy(-y + w:GetHeight() <= contentHeight, "bottom at " .. (-y + w:GetHeight()))
				expect.truthy(x + w:GetWidth() <= contentWidth, "right at " .. (x + w:GetWidth()))
			end
		end)

		t:it("lays the answers out as a two-column grid of numbered choice cards with hints", function()
			local mock, _, ns, section = start()
			turnIn(mock, 14, "Grid")
			ns.MainWindow.Refresh()
			local a, b, c = section.optionButtons[1], section.optionButtons[2], section.optionButtons[3]
			local ax, ay = offset(a, section.frame)
			local bx, by = offset(b, section.frame)
			local cx, cy = offset(c, section.frame)
			expect.equal(ay, by, "1 and 2 share a row")
			expect.truthy(bx > ax, "2 is right of 1")
			expect.equal(cx, ax, "3 starts the next row")
			expect.truthy(cy < ay)
			expect.equal(a.key.label:GetText(), "1")
			-- The first quest answer proposes Compassion +1: the hint says so, from the library.
			expect.truthy(a.hint:GetText():find("More Compassionate", 1, true), a.hint:GetText())
			local last
			for _, btn in ipairs(section.optionButtons) do
				if btn:IsShown() then last = btn end
			end
			expect.equal(last.hint:GetText(), "No personality change")
		end)

		t:it("shows where, what and when from the record, and why now from the Director", function()
			local mock, env, ns, section = start()
			turnIn(mock, 15, "Context Quest")
			ns.MainWindow.Refresh()
			local chips = {}
			for _, chip in ipairs(section.chips) do
				if chip:IsShown() then chips[#chips + 1] = chip.label:GetText() end
			end
			expect.equal(chips[1], "Goldshire, Elwynn Forest")
			expect.equal(chips[2], "Quest completed")
			expect.truthy(chips[3]:find("Level 20", 1, true), chips[3])
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			local reaction = char.story.reactions[1]
			local view = ns.Reactions.Present(char, reaction)
			local why = section.context:GetText()
			expect.truthy(why:find("Why now:", 1, true))
			expect.truthy(why:find(view.why[1], 1, true), "the Director's own reason")
			expect.falsy(why:find("remembers", 1, true), "no memories, no memory line")
			expect.truthy(ns.MainWindow.GetFrame().eyebrow:GetText():find("MOMENT 1 OF 1", 1, true))
		end)

		t:it("names relevant established memories, and only those", function()
			local mock, env, ns, section = start()
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			ns.Memories.Add(char, { title = "The night the lanterns went out", zone = "Elwynn Forest",
				importance = 2 }, "player", 1)
			ns.Memories.Add(char, { title = "A proposed one", zone = "Elwynn Forest" }, "suggested", 1)
			turnIn(mock, 16, "Memory Quest")
			ns.MainWindow.Refresh()
			local text = section.context:GetText()
			expect.truthy(text:find("Morrow remembers:", 1, true), text)
			expect.truthy(text:find("The night the lanterns went out", 1, true))
			expect.falsy(text:find("A proposed one", 1, true), "proposed memories have no influence")
		end)

		t:it("lists other waiting moments and selects one", function()
			local mock, env, ns, section = start()
			turnIn(mock, 17, "First")
			mock.zone = "Duskwood"
			mock.Slash("story set frequency frequent")
			env.DawnwardChroniclesDB.characters[CHAR].story.pacing.playByCategory = {}
			turnIn(mock, 18, "Second")
			ns.MainWindow.Refresh()
			local row = section.waitingRows[1]
			expect.truthy(row:IsShown())
			expect.falsy(section.waitingRows[2]:IsShown())
			local other = row.text:GetText()
			expect.truthy(other ~= section.question:GetText())
			click(row)
			expect.equal(section.question:GetText(), other)
			expect.equal(section.index, 2)
			expect.truthy(section.position:GetText():find("2 of 2", 1, true))
		end)

		t:it("refuses an empty answer inline and keeps the moment", function()
			local mock, env, ns, section = start()
			turnIn(mock, 19, "Empty")
			ns.MainWindow.Refresh()
			section.custom:SetText("   ")
			click(section.save)
			expect.truthy(section.custom.invalid)
			expect.truthy(section.customError:IsShown())
			expect.equal(#env.DawnwardChroniclesDB.characters[CHAR].story.reactions, 1)
		end)

		t:it("explains a waiting change, rejects it, and reverses an applied one", function()
			local mock, env, ns, section = start()
			turnIn(mock, 40, "Growth")
			ns.MainWindow.Refresh()
			click(section.optionButtons[1])
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			local row = section.changeRows[1]
			expect.equal(row.label:GetText(), "More Compassionate")
			expect.truthy(row.reason:GetText():find("From your answer: Morrow", 1, true), row.reason:GetText())
			click(row.reject)
			expect.equal(char.story.changes[1].status, "rejected")
			expect.falsy(section.appliedRows[1]:IsShown())
			-- A second moment, approved, can be reversed after a confirmation.
			mock.Slash("story set frequency frequent")
			char.story.pacing.playByCategory = {}
			turnIn(mock, 41, "Growth Again")
			ns.MainWindow.Refresh()
			click(section.optionButtons[1])
			local change = ns.Evolution.Pending(char)[1]
			local axis = change.axis
			click(section.changeRows[1].approve)
			local applied = section.appliedRows[1]
			expect.truthy(applied:IsShown())
			local after = char.personality[axis].value
			click(applied.reverse)
			expect.equal(char.personality[axis].value, after, "nothing until confirmed")
			click(ns.Widgets.dialog.accept)
			expect.equal(char.personality[axis].value, after - change.delta)
			expect.falsy(section.appliedRows[1]:IsShown())
		end)

		t:it("with automatic approval, changes apply at once and stay reversible", function()
			local mock, env, ns, section = start()
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			char.story.prefs.approval = "auto"
			turnIn(mock, 42, "Auto")
			ns.MainWindow.Refresh()
			click(section.optionButtons[1])
			expect.falsy(section.changeRows[1]:IsShown())
			expect.truthy(section.appliedRows[1]:IsShown())
			expect.truthy(section.growthNote:GetText():find("Automatic approval is on", 1, true))
		end)

		t:it("explains an empty Story section", function()
			local _, _, ns, section = start()
			expect.truthy(section.body:IsShown())
			expect.falsy(section.optionButtons[1]:IsShown())
			expect.truthy(section.waitingNote:GetText():find("Nothing is waiting", 1, true))
			expect.truthy(section.growthNote:GetText():find("No personality changes are waiting", 1, true))
			expect.equal(ns.MainWindow.GetFrame().eyebrow:GetText(), "STORY")
		end)
	end)

	t:describe("reaction card (L2)", function()
		t:it("appears at a safe moment and opens the Story section on that moment", function()
			local mock, _, ns = Boot.Start()
			mock.Slash("set name Card")
			turnIn(mock, 20, "Card Quest")
			mock.RunTimers()
			local card = ns.ReactionCard.Frame()
			expect.truthy(card and card:IsShown())
			expect.truthy(card.question:GetText():find("Card Quest", 1, true))
			expect.equal(card.meta:GetText(), "Quest completed · Elwynn Forest")
			expect.equal(card.dismiss.variant, "danger")
			click(card.answer)
			expect.falsy(card:IsShown())
			expect.truthy(ns.MainWindow.IsShown())
			expect.equal(ns.MainWindow.CurrentSection(), "story")
		end)

		t:it("is never shown in combat and hides when combat starts", function()
			local mock, _, ns = Boot.Start()
			mock.Slash("set name Card")
			mock.inCombat = true
			turnIn(mock, 21, "Combat Quest")
			mock.RunTimers()
			expect.falsy(ns.ReactionCard.Frame() and ns.ReactionCard.Frame():IsShown())
			mock.inCombat = false
			mock.Fire("PLAYER_REGEN_ENABLED")
			mock.RunTimers()
			local card = ns.ReactionCard.Frame()
			expect.truthy(card:IsShown())
			mock.Fire("PLAYER_REGEN_DISABLED")
			expect.falsy(card:IsShown())
		end)

		t:it("can be switched off; the chat notice remains", function()
			local mock, _, ns = Boot.Start()
			mock.Slash("story set card off")
			turnIn(mock, 22, "Quiet Quest")
			mock.chat = {}
			mock.RunTimers()
			expect.falsy(ns.ReactionCard.Frame() and ns.ReactionCard.Frame():IsShown())
			expect.truthy(table.concat(mock.chat, "\n"):find("A moment for your story", 1, true))
		end)
	end)

	t:describe("journal story entries (L2)", function()
		t:it("drafts can be approved, marked as defining moments, edited and then made public", function()
			local mock, env, ns = Boot.Start()
			mock.Slash("set name Drafter")
			turnIn(mock, 30, "Draft Quest")
			mock.Slash("story 1 1")
			mock.Slash("")
			ns.MainWindow.Select("journal")
			local section = ns.JournalView.section
			local row = section.rows[1]
			expect.equal(row.entry.kind, "story")
			expect.truthy(row.approve:IsShown())
			expect.truthy(row.edit:IsShown())
			click(row.vis) -- private -> public: refused for a draft
			local journal = env.DawnwardChroniclesDB.characters[CHAR].journal
			local entry = journal[#journal]
			expect.equal(entry.visibility, "private")
			click(row.approve)
			expect.equal(entry.status, "approved")
			click(section.rows[1].mark)
			expect.equal(entry.important, true)
			click(section.rows[1].vis)
			-- Publishing asks first and names where a defining moment can appear (#13).
			local asked = mock.AcceptPopup()
			expect.truthy(asked.text:find("Total RP 3 biography block", 1, true))
			expect.equal(entry.visibility, "public")
			expect.truthy(ns.JournalView.MetaText(entry, function() return "d" end):find("defining moment", 1, true))
		end)
	end)

	t:describe("story settings (L2)", function()
		t:it("cycle buttons change preferences through the same actions", function()
			local mock, env, ns = Boot.Start()
			mock.Slash("set name A")
			mock.Slash("")
			ns.MainWindow.ToggleSettings()
			local panel = ns.SettingsPanel.panel
			local moments = panel.storyButtons[1]
			expect.equal(moments:GetText(), "Moments: Normal  ›", "the current value, and that a click moves on")
			expect.truthy(moments.tooltipText:find("[Normal]", 1, true), "every option, the current one marked")
			expect.truthy(moments.tooltipText:find("Click to switch", 1, true))
			click(moments)
			local prefs = env.DawnwardChroniclesDB.characters[CHAR].story.prefs
			expect.equal(prefs.frequency, "frequent")
			expect.equal(moments:GetText(), "Moments: Frequent  ›")
			expect.truthy(moments.tooltipText:find("[Frequent]", 1, true))
			local quests = panel.storyButtons[#panel.storyButtons]
			click(quests)
			expect.equal(prefs.tracking.quest, false)
		end)
	end)
end
