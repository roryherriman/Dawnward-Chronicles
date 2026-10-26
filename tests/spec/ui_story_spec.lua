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

-- y offset of a widget's TOPLEFT point relative to its parent (negative down).
local function top(widget)
	for _, p in ipairs(widget.__points or {}) do
		if p[1] == "TOPLEFT" then
			return p[#p]
		end
	end
	return nil
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
			env.DawnwardChroniclesDB.characters[CHAR].story.pacing.lastByCategory = {}
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
			local contentHeight = ns.MainWindow.LAYOUT.height - ns.MainWindow.LAYOUT.contentTop
				- ns.MainWindow.LAYOUT.contentBottom
			local widgets = { section.later, section.custom, section.changeRows[#section.changeRows] }
			for _, b in ipairs(section.optionButtons) do widgets[#widgets + 1] = b end
			for _, w in ipairs(widgets) do
				local y = top(w)
				expect.truthy(y, "anchored by TOPLEFT")
				expect.truthy(-y + w:GetHeight() <= contentHeight, "bottom at " .. (-y + w:GetHeight()))
			end
		end)
	end)

	t:describe("reaction card (L2)", function()
		t:it("appears at a safe moment and opens the Story section on that moment", function()
			local mock, _, ns = Boot.Start()
			turnIn(mock, 20, "Card Quest")
			mock.RunTimers()
			local card = ns.ReactionCard.Frame()
			expect.truthy(card and card:IsShown())
			expect.truthy(card.question:GetText():find("Card Quest", 1, true))
			click(card.answer)
			expect.falsy(card:IsShown())
			expect.truthy(ns.MainWindow.IsShown())
			expect.equal(ns.MainWindow.CurrentSection(), "story")
		end)

		t:it("is never shown in combat and hides when combat starts", function()
			local mock, _, ns = Boot.Start()
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
			expect.equal(moments:GetText(), "Moments: normal")
			click(moments)
			local prefs = env.DawnwardChroniclesDB.characters[CHAR].story.prefs
			expect.equal(prefs.frequency, "frequent")
			expect.equal(moments:GetText(), "Moments: frequent")
			local quests = panel.storyButtons[#panel.storyButtons]
			click(quests)
			expect.equal(prefs.tracking.quest, false)
		end)
	end)
end
