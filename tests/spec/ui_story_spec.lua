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

		t:it("lays the moment card out without overlaps for any amount of content", function()
			local _, _, ns = start()
			local SV, L, Style = ns.StoryView, ns.StoryView.LAYOUT, ns.Style
			local function check(m)
				local l = SV.MomentLayout(m)
				local label = string.format("q%d why%d rows%d", m.questionLines, #m.whyRows, #m.rows)
				expect.truthy(l.fits, "fits: " .. label)
				local y = 0
				local function after(top, height, what)
					expect.truthy(top >= y, what .. " starts below the previous block (" .. label .. ")")
					y = top + height
				end
				if m.chips then after(l.chipsTop, L.chipH, "chips") end
				after(l.questionTop, l.questionH, "question")
				if #m.whyRows > 0 then after(l.whyTop, l.whyH, "why") end
				for i, row in ipairs(l.rows) do
					after(row.top, row.height, "row " .. i)
					expect.truthy(row.height >= L.option.min, "an answer card is at least 52 high")
				end
				after(l.customLabelTop, L.customLabelH, "own-words label")
				after(l.customTop, l.customH, "own-words field")
				expect.truthy(l.customH >= Style.CONTROL.input, "the field is at least an input high")
				after(l.buttonsTop, L.buttonH, "buttons")
				expect.truthy(y <= L.contentH - 16, "the action row stays inside the card: " .. label)
				return l
			end
			-- The mockup's moment: comfortable spacing and a 64 px field.
			local mock = check({ chips = true, questionLines = 2, whyRows = { { lines = 1 }, { lines = 1 } },
				rows = { 2, 2, 2 } })
			expect.equal(mock.density, "comfortable")
			expect.equal(mock.customH, 64)
			expect.equal(mock.optionLines, 3, "answers are never cut in an ordinary moment")
			-- Every combination up to the most a moment can hold.
			for q = 1, 4 do
				for nWhy = 0, 3 do
					for whyLines = 1, 3 do
						for nRows = 1, 4 do
							for rowLines = 1, 3 do
								local why, rows = {}, {}
								for i = 1, nWhy do why[i] = { lines = whyLines, stacked = i == 2 } end
								for i = 1, nRows do rows[i] = rowLines end
								check({ chips = true, questionLines = q, whyRows = why, rows = rows })
							end
						end
					end
				end
			end
			for name, size in pairs({ question = L.question.size, why = L.why.size, answer = L.option.size,
				hint = L.option.hint, row = L.rowText.size, meta = L.rowMeta, reason = L.reason.size,
				note = L.note.size }) do
				expect.truthy(size >= Style.MIN_TEXT, name .. " text is at least 13")
			end
		end)

		t:it("draws numbered choice cards with round discs, hints that fit and a gold hover", function()
			local mock, _, ns, section = start()
			turnIn(mock, 50, "Cards")
			ns.MainWindow.Refresh()
			local L = ns.StoryView.LAYOUT
			local theme = ns.Style.Current()
			for _, b in ipairs(section.optionButtons) do
				if b:IsShown() then
					expect.truthy(b.key.ring and b.key.fill, "the number sits in a disc")
					expect.equal(b.key.ring:GetWidth(), L.option.key)
					expect.truthy(ns.Style.TextWidth(b.hint:GetText(), "small") <= L.optionTextW,
						"hint fits on its line: " .. b.hint:GetText())
					expect.truthy(b.tooltipText:find(b:GetText(), 1, true), "the whole answer is in the tooltip")
				end
			end
			local a = section.optionButtons[1]
			local before = a.bg.__color
			a:GetScript("OnEnter")(a)
			expect.equal(a.edges.top.__color[1], theme.accent[1], "hovered: gold edge")
			expect.equal(a.key.fill.__color[1], theme.accent[1], "hovered: gold disc")
			a:GetScript("OnLeave")(a)
			expect.deepEqual(a.bg.__color, before, "leaving restores the card")
			-- Two columns 8 apart, the cards' text column right of the disc.
			local b = section.optionButtons[2]
			local ax = offset(a, section.frame)
			local bx = offset(b, section.frame)
			expect.equal(bx - ax, L.colW + L.optionGap)
		end)

		t:it("keeps the action row on one line at the card's foot, Dismiss on the right", function()
			local mock, _, ns, section = start()
			turnIn(mock, 51, "Buttons")
			ns.MainWindow.Refresh()
			local L = ns.StoryView.LAYOUT
			local row = { section.save, section.later, section.notNow, section.dismiss }
			local _, y0 = offset(section.save, section.frame)
			local right = 0
			for i, b in ipairs(row) do
				expect.equal(b:GetHeight(), ns.Style.CONTROL.standard)
				expect.truthy(ns.Widgets.LabelFits(b:GetText(), b:GetWidth(), b:GetHeight(), b.variant), b:GetText())
				local x, y = offset(b, section.frame)
				expect.equal(y, y0, "one row")
				expect.truthy(x >= right, "no overlap")
				right = x + b:GetWidth() + (i < 3 and L.buttonGap or 0)
			end
			local dx = offset(section.dismiss, section.frame)
			expect.equal(dx + section.dismiss:GetWidth(), L.pad + L.inner, "Dismiss ends at the card's inner edge")
			local _, fy = offset(section.customArea.frame, section.frame)
			expect.truthy(-fy + section.customArea.frame:GetHeight() < -y0, "the field ends above the buttons")
			expect.equal(section.save.variant, "primary")
			expect.equal(section.later.variant, "ghost")
			expect.equal(section.notNow.variant, "ghost")
			expect.equal(section.dismiss.variant, "danger")
		end)

		t:it("shows the player's own earlier answer on its own Last time line", function()
			local _, env, ns, section = start()
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			local first = ns.Reactions.Consider(char, assert(ns.GameEvents.Record(char, "death",
				{ at = 100, zone = "Duskwood", level = 25 }, 100)), 100, 100)
			assert(ns.Decisions.Decide(char, first.id, { optionId = "careful" }, 101))
			local later = 100 + 4 * 86400
			assert(ns.Reactions.Consider(char, assert(ns.GameEvents.Record(char, "death",
				{ at = later, zone = "Duskwood", level = 25 }, later)), later, later))
			ns.MainWindow.Refresh()
			local labels = {}
			for _, row in ipairs(section.whyRows) do
				if row.shown then labels[#labels + 1] = row.label:GetText() end
			end
			expect.equal(labels[1], "Why now:")
			expect.equal(labels[#labels], "Last time:")
			-- The text runs on after its label (no-break spaces hold the label's room).
			local echo = section.whyRows[#labels].plain
			expect.truthy(section.whyRows[#labels].text:GetText():find(echo, 1, true))
			expect.equal(echo, "Morrow came back more careful.")
			expect.falsy(section.whyRows[1].text:GetText():find("Last time", 1, true), "not repeated in Why now")
			expect.truthy(section.context:GetText():find("Last time: Morrow came back more careful.", 1, true))
			-- The well holds every row inside its own height.
			local layout = section.layout
			local last = layout.whyRows[#labels]
			expect.truthy(last.top + ns.StoryView.TextHeight(last.lines, 14, 4) <= layout.whyH)
		end)

		t:it("keeps both side panels inside the content area with many moments and changes", function()
			local mock, env, ns, section = start()
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			mock.Slash("story set frequency frequent")
			local zones = { "Duskwood", "Westfall", "Redridge Mountains", "Darkshire", "Loch Modan", "Wetlands",
				"Ashenvale" }
			for i, zone in ipairs(zones) do
				mock.zone = zone
				char.story.pacing.playByCategory = {}
				turnIn(mock, 60 + i, "Many " .. i)
			end
			ns.MainWindow.Refresh()
			-- Two answers approved (reversible), two waiting for approval.
			for _ = 1, 2 do
				click(section.optionButtons[1])
				click(section.changeRows[1].approve)
			end
			click(section.optionButtons[2])
			section.index = 1
			ns.MainWindow.Refresh()
			click(section.optionButtons[3])
			ns.MainWindow.Refresh()
			local contentHeight = ns.MainWindow.ContentHeight()
			local _, wy = offset(section.waitingPanel, section.frame)
			local _, gy = offset(section.growthPanel, section.frame)
			expect.truthy(-gy >= -wy + section.waitingPanel:GetHeight(), "growth starts below Also waiting")
			expect.truthy(-gy + section.growthPanel:GetHeight() <= contentHeight,
				"bottom at " .. (-gy + section.growthPanel:GetHeight()))
			local rows = { section.growthNote }
			for _, r in ipairs(section.changeRows) do rows[#rows + 1] = r end
			for _, r in ipairs(section.appliedRows) do rows[#rows + 1] = r end
			local y = 0
			for _, r in ipairs(rows) do
				if r:IsShown() and r ~= section.growthNote then
					local _, ry = offset(r, section.growthPanel)
					expect.truthy(-ry >= y, "rows do not overlap")
					y = -ry + r:GetHeight()
				end
			end
			-- Approvals keep priority; a waiting moment that has no room is
			-- still counted and reachable with < >.
			expect.truthy(section.changeRows[2]:IsShown())
			expect.truthy(section.appliedRows[2]:IsShown())
			expect.truthy(section.waitingRows[1]:IsShown())
			expect.truthy(section.waitingNote:GetText():find("more: use < > above", 1, true),
				section.waitingNote:GetText())
		end)

		t:it("runs each Why now line on after its bold label, as one paragraph", function()
			local _, _, ns = start()
			local SV = ns.StoryView
			local room = ns.Style.TextWidth("Why now:", "label") + SV.LAYOUT.why.labelGap
			local prefix, indent = SV.InlineIndent(room, SV.LAYOUT.whyInner)
			expect.truthy(prefix, "the bundled font is in use")
			local space = ns.Style.TextWidth(" ", "meta")
			expect.truthy(math.abs(indent - room) <= space, "the text starts within one space of the label's end")
			expect.truthy(prefix:sub(-1) == " ", "a normal space after the no-break run, where a line may break")
			expect.falsy(prefix:sub(1, -2):find(" ", 1, true), "no breaking space inside the run")
			expect.falsy(SV.InlineIndent(SV.LAYOUT.whyInner * 0.8, SV.LAYOUT.whyInner), "a very long label stacks")
			-- The estimate counts the label's room on the first line only.
			local text = string.rep("word ", 30)
			expect.truthy(SV.WrapLines(text, "meta", 14, 300, 120) >= SV.WrapLines(text, "meta", 14, 300))
			expect.equal(SV.WrapLines("Supercalifragilistic", "meta", 14, 160, 150), 2,
				"a first word that does not fit after the label starts the next line")
		end)

		t:it("lays the Why now rows out from their measured lines, inside the well", function()
			local mock, env, ns, section = start()
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			ns.Memories.Add(char, { title = "The night the lanterns went out", zone = "Elwynn Forest",
				importance = 2 }, "player", 1)
			turnIn(mock, 31, "Why Quest")
			ns.MainWindow.Refresh()
			local layout = section.layout
			local shown = 0
			for i, row in ipairs(section.whyRows) do
				if row.shown then
					shown = shown + 1
					expect.falsy(row.stacked, "inline with the bundled font")
					local spec = layout.whyRows[i]
					-- Label and text start on the same line; the text holds the label's room.
					expect.equal(row.label.__points[1][5], row.text.__points[1][5])
					expect.truthy(row.text:GetText():find(row.plain, 1, true))
					expect.truthy(spec.top + ns.StoryView.TextHeight(spec.lines, 14, 4) <= layout.whyH)
				end
			end
			expect.equal(shown, 2, "Why now and remembers")
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

		t:it("grows with its question, keeps the meta line clear of Close and uses compact buttons", function()
			local mock, _, ns = Boot.Start()
			mock.Slash("set name Card")
			turnIn(mock, 23, "Card Layout Quest")
			mock.RunTimers()
			local card = ns.ReactionCard.Frame()
			local L = ns.ReactionCard.LAYOUT
			local lines = math.min(3, ns.StoryView.WrapLines(card.question:GetText(), "reading", L.question.size,
				L.questionW * 0.96))
			expect.truthy(card.why:IsShown(), "the Director's reason, as in the Story section")
			expect.equal(card.whyLabel:GetText(), "Why now:")
			local h = card:GetHeight()
			expect.truthy(h == ns.ReactionCard.Height(lines, 1) or h == ns.ReactionCard.Height(lines, 2), "height " .. h)
			expect.truthy(ns.ReactionCard.Height(3) > ns.ReactionCard.Height(1))
			expect.truthy(ns.ReactionCard.Height(1, 2) > ns.ReactionCard.Height(1, 0), "the reason adds its lines")
			expect.equal(ns.ReactionCard.Height(9, 9), ns.ReactionCard.Height(3, 2), "at most three and two lines")
			for _, b in ipairs({ card.answer, card.later, card.dismiss }) do
				expect.equal(b:GetHeight(), ns.Style.CONTROL.compact)
				expect.truthy(ns.Widgets.LabelFits(b:GetText(), b:GetWidth(), b:GetHeight(), b.variant), b:GetText())
			end
			-- The chips: the gold place, then the event; they end left of the close button.
			expect.equal(card.chips[1].label:GetText(), "Goldshire, Elwynn Forest")
			expect.equal(card.chips[2].label:GetText(), "Quest completed")
			local x = L.pad
			for _, chip in ipairs(card.chips) do
				if chip:IsShown() then x = x + chip:GetWidth() + 8 end
			end
			expect.truthy(x - 8 <= ns.ReactionCard.WIDTH - 10 - L.close, "chips end at " .. x)
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
		t:it("drafts can be approved and marked as defining moments, which makes them part of the profile",
			function()
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
			expect.equal(row.vis, nil, "no visibility chip")
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			local journal = char.journal
			local entry = journal[#journal]
			click(row.approve)
			expect.equal(entry.status, "approved")
			click(section.rows[1].mark)
			expect.equal(entry.important, true)
			expect.falsy(ns.Widgets.dialog and ns.Widgets.dialog:IsShown(), "nothing to confirm")
			ns.Publication.Adopt(char, 1)
			local moments = ns.Projection.GetPublic(char).journal
			expect.equal(moments[1] and moments[1].id, entry.id, "a defining moment is part of the profile")
			expect.truthy(ns.JournalView.MetaText(entry, function() return "d" end):find("defining moment", 1, true))
		end)
	end)

	t:describe("story settings (L2)", function()
		t:it("segmented controls show every option and change preferences through the same actions", function()
			local mock, env, ns = Boot.Start()
			mock.Slash("set name A")
			mock.Slash("")
			ns.MainWindow.ToggleSettings()
			local panel = ns.SettingsPanel.panel
			local moments = panel.storyRows[1]
			local function option(row, value)
				for _, b in ipairs(row.control.buttons) do
					if b.segmentId == value then return b end
				end
			end
			local labels = {}
			for i, b in ipairs(moments.control.buttons) do labels[i] = b:GetText() end
			expect.deepEqual(labels, { "Rare", "Normal", "Frequent", "Off" }, "every option is visible")
			expect.equal(moments.control.selected, "normal", "the value in use is selected")
			expect.truthy(option(moments, "normal").selected)
			expect.truthy(moments.hover.tooltipText:find("[Normal]", 1, true), "every option, the current one marked")
			click(option(moments, "frequent"))
			local prefs = env.DawnwardChroniclesDB.characters[CHAR].story.prefs
			expect.equal(prefs.frequency, "frequent")
			expect.truthy(option(moments, "frequent").selected)
			expect.falsy(option(moments, "normal").selected)
			expect.truthy(moments.hover.tooltipText:find("[Frequent]", 1, true))
			local quests
			for _, row in ipairs(panel.storyRows) do
				if row.setting.tracking == "quest" then quests = row end
			end
			click(option(quests, false))
			expect.equal(prefs.tracking.quest, false)
			expect.truthy(option(quests, false).selected)
		end)
	end)
end
