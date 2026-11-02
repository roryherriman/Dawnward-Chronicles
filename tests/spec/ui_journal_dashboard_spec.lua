-- L2: the v0.7 Journal dashboard (docs/design/mockups/journal-dashboard.png):
-- subline counts, toolbar search and filter, the "A moment awaits" callout,
-- entry cards and the right column, all from the character's real data.
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

-- Types text and lets the search's short pause run out (mock = the client).
local function typeInto(box, text, mock)
	box:SetText(text)
	box:GetScript("OnTextChanged")(box, true)
	if mock then mock.RunTimers() end
end

local function start()
	local mock, env, ns = Boot.Start()
	mock.Slash("set name Morrow")
	mock.Slash("")
	return mock, env, ns, ns.JournalView.section
end

local function char(env)
	return env.DawnwardChroniclesDB.characters[CHAR]
end

-- The last point set on a region, as { point, relativeTo, relativePoint, x, y }.
local function lastPoint(region)
	local points = region.__points or {}
	return points[#points]
end

local function shownEntries(section)
	local out = {}
	for i = 1, section.visibleCount do out[i] = section.rows[i].entry end
	return out
end

return function(t, expect)
	t:describe("journal dashboard: header and toolbar (L2)", function()
		t:it("counts entries and defining moments from the real journal", function()
			local mock, env, ns, section = start()
			expect.equal(section.subline:GetText(), "No entries yet")
			mock.Slash("journal add One")
			mock.Slash("journal add Two")
			ns.Actions.SetEntryImportant(ns.ctx, char(env).journal[1].id, true)
			ns.MainWindow.Refresh()
			expect.equal(section.subline:GetText(), "2 entries · 1 defining moment · last entry today")
		end)

		t:it("says when the last entry was written", function()
			local JV = select(3, Boot.Start()).JournalView
			local now = 1700000000
			expect.equal(JV.When(now - 60, now), "today")
			expect.equal(JV.When(now - 86400, now), "yesterday")
			expect.equal(JV.When(now - 3 * 86400, now), "3 days ago")
			expect.truthy(JV.When(now - 30 * 86400, now):find("2023", 1, true))
		end)

		t:it("New entry opens the existing editor, and the dashboard comes back after", function()
			local _, _, _, section = start()
			expect.equal(section.newButton:GetText(), "New entry")
			expect.equal(section.newButton.icon.name, "plus", "the design's + is a line icon")
			click(section.newButton)
			expect.truthy(section.editor:IsShown())
			for _, part in ipairs({ section.subline, section.toolbar, section.scroll, section.goals, section.places }) do
				expect.falsy(part:IsShown(), "dashboard hidden while writing")
			end
			click(section.editor.cancel)
			for _, part in ipairs({ section.subline, section.toolbar, section.scroll, section.goals, section.places }) do
				expect.truthy(part:IsShown(), "dashboard back")
			end
		end)

		t:it("filters by All, Defining, Story and Events, mapped to the entries' real kinds and flags", function()
			local mock, env, ns, section = start()
			mock.Fire("PLAYER_LEVEL_UP", 7)
			turnIn(mock, 30, "Draft Quest")
			mock.Slash("story 1 1")
			mock.Slash("journal add My own words")
			local note = char(env).journal[#char(env).journal]
			ns.Actions.SetEntryImportant(ns.ctx, note.id, true)
			ns.MainWindow.Refresh()
			expect.equal(section.visibleCount, 3)
			local labels = {}
			for i, b in ipairs(section.filters.buttons) do labels[i] = b:GetText() end
			expect.deepEqual(labels, { "All", "Defining", "Story", "Events" })

			click(section.filters.buttons[2])
			expect.deepEqual(shownEntries(section), { note })
			expect.truthy(section.filters.buttons[2].selected)
			click(section.filters.buttons[3])
			expect.equal(section.visibleCount, 1)
			expect.equal(section.rows[1].entry.kind, "story")
			click(section.filters.buttons[4])
			expect.equal(section.visibleCount, 1)
			expect.equal(section.rows[1].entry.kind, "event")
			click(section.filters.buttons[1])
			expect.equal(section.visibleCount, 3)
		end)

		t:it("searches title, text and recorded place, and explains an empty result", function()
			local mock, _, ns, section = start()
			mock.Fire("PLAYER_LEVEL_UP", 7) -- recorded in Goldshire, Elwynn Forest
			mock.Slash("journal add A quiet evening by the river")
			ns.MainWindow.Refresh()
			typeInto(section.search, "gold")
			expect.equal(section.visibleCount, 2, "nothing refreshes while the player is still typing")
			typeInto(section.search, "goldshire", mock)
			expect.equal(section.visibleCount, 1)
			expect.equal(section.rows[1].entry.kind, "event", "matched by its place")
			typeInto(section.search, "RIVER", mock)
			expect.equal(section.visibleCount, 1)
			expect.equal(section.rows[1].entry.kind, "note")
			typeInto(section.search, "dragons", mock)
			expect.equal(section.visibleCount, 0)
			expect.truthy(section.empty:IsShown())
			expect.equal(section.empty:GetText(), ns.JournalView.NO_MATCH_TEXT)
			typeInto(section.search, "", mock)
			expect.equal(section.visibleCount, 2)
		end)
	end)

	t:describe("journal dashboard: entry cards (L2)", function()
		t:it("shows date, title, meta, text, chips and the entry's own actions inside its card", function()
			local mock, env, ns, section = start()
			mock.Fire("PLAYER_LEVEL_UP", 7)
			turnIn(mock, 30, "Draft Quest")
			mock.Slash("story 1 1")
			mock.Slash("journal add Night watch; The lanterns went out.")
			click(section.newButton)
			section.editor.title:SetText("The night the lanterns went out")
			section.editor.area.edit:SetText("I walked the road with a candle.")
			click(section.editor.save)
			local byKind = {}
			for i = 1, section.visibleCount do byKind[section.rows[i].entry.kind] = section.rows[i] end
			local note = section.rows[1]
			expect.equal(note.title:GetText(), "The night the lanterns went out")
			expect.equal(note.meta:GetText(), "Your words")
			expect.equal(note.body:GetText(), "I walked the road with a candle.")
			expect.truthy(note.date.day:GetText():match("^%d+$"))
			expect.truthy(note.date.month:GetText():match("^%u%u%u$"))
			expect.falsy(note.chips[1]:IsShown(), "a plain note has no status chip")

			local event = byKind.event
			expect.equal(event.title:GetText(), "Reached level 7 in Elwynn Forest")
			expect.equal(event.meta:GetText(), "Goldshire, Elwynn Forest · Level 7 · recorded automatically")
			expect.falsy(event.body:IsShown(), "the recorded text is the title, not repeated")
			expect.equal(event.chips[1].label:GetText(), "Recorded event")
			expect.falsy(event.edit:IsShown())

			local story = byKind.story
			expect.equal(story.chips[1].label:GetText(), "Waiting for your approval")
			expect.truthy(story.meta:GetText():find("^Story development"))
			expect.truthy(story.approve:IsShown())
			click(story.mark)
			local storyRow
			for i = 1, section.visibleCount do
				if section.rows[i].entry.kind == "story" then storyRow = section.rows[i] end
			end
			expect.equal(storyRow.chips[1].label:GetText(), "Defining")
			expect.equal(storyRow.chips[2].label:GetText(), "Waiting for your approval")
			click(storyRow.approve)
			expect.equal(char(env).journal[2].status, "approved")
			expect.falsy(storyRow.approve:IsShown())

			-- Every action and the visibility control sit inside the card.
			for i = 1, section.visibleCount do
				local row = section.rows[i]
				for _, b in ipairs({ row.vis, row.edit, row.delete, row.approve, row.mark }) do
					expect.equal(b:GetParent(), row)
				end
				for _, b in ipairs({ row.vis, row.edit, row.delete, row.approve, row.mark }) do
					if b:IsShown() then
						local p = lastPoint(b)
						expect.truthy(type(p[2]) ~= "table" or p[2] == row, "anchored to its own card")
						expect.truthy(-p[#p] + b:GetHeight() <= row:GetHeight(), "above the card's bottom")
					end
				end
				expect.truthy(row:GetWidth() <= ns.MainWindow.ContentWidth() - 270, "cards leave room for the right column")
			end
			expect.truthy(ns.JournalView.MetaText(char(env).journal[1], ns.Widgets.FormatDate):find("Level 7", 1, true))
		end)

		t:it("scrolls one long list from a small pool of reused cards", function()
			local mock, _, ns, section = start()
			for i = 1, 60 do mock.Slash("journal add Entry " .. i) end
			ns.MainWindow.Refresh()
			local L = ns.JournalView.LAYOUT
			expect.equal(section.matchCount, 60, "every entry is in the one list")
			expect.equal(section.rows[1].entry.text, "Entry 60", "newest first")
			expect.truthy(section.maxOffset > 0, "the list scrolls")
			-- Only the cards in view exist: a card is at least 46 + padding high.
			local most = math.ceil(section.viewH / (46 + 2 * L.padY + L.cardGap)) + 1
			expect.truthy(#section.rows <= most, "pool bounded by the visible area, not the journal")
			local pool = {}
			for _, row in ipairs(section.rows) do pool[row] = true end
			-- Scroll through the whole list, a card at a time.
			local step = 40
			local offset = 0
			while offset < section.maxOffset do
				offset = offset + step
				section:ScrollTo(offset)
			end
			expect.equal(section.offset, section.maxOffset)
			expect.equal(section.rows[section.visibleCount].entry.text, "Entry 1", "the oldest at the end")
			section:ScrollTo(0)
			ns.MainWindow.Refresh()
			expect.equal(section.rows[1].entry.text, "Entry 60")
			local created = 0
			for _, row in ipairs(section.rows) do
				if not pool[row] then created = created + 1 end
			end
			expect.truthy(#section.rows <= most + 1, "scrolling reuses the pool")
			expect.truthy(created <= 1, "at most one card added while scrolling")
			-- Shown cards are stacked in list order, a card gap apart, never overlapping.
			for i = 2, section.visibleCount do
				local above, row = section.rows[i - 1], section.rows[i]
				local aboveTop, rowTop = -lastPoint(above)[5], -lastPoint(row)[5]
				expect.equal(rowTop, aboveTop + above:GetHeight() + L.cardGap)
			end
		end)

		t:it("keeps the scroll position on refresh; a filter, a search or a new entry go back to the top", function()
			local mock, _, ns, section = start()
			for i = 1, 30 do mock.Slash("journal add Entry " .. i) end
			ns.MainWindow.Refresh()
			section:ScrollTo(300)
			mock.Fire("PLAYER_LEVEL_UP", 9)
			expect.equal(section.offset, 300, "a milestone arriving does not move the list")
			click(section.filters.buttons[1])
			expect.equal(section.offset, 0)
			section:ScrollTo(300)
			typeInto(section.search, "Entry", mock)
			expect.equal(section.offset, 0)
			typeInto(section.search, "", mock)
			section:ScrollTo(300)
			expect.equal(section.offset, 300)
			click(section.newButton)
			section.editor.area.edit:SetText("Fresh")
			click(section.editor.save)
			expect.equal(section.offset, 0)
			expect.equal(section.rows[1].entry.text, "Fresh")
		end)

		t:it("a short journal has no scroll range and no pager", function()
			local mock, _, ns, section = start()
			mock.Slash("journal add Only one")
			ns.MainWindow.Refresh()
			expect.equal(section.maxOffset, 0)
			expect.equal(section.older, nil)
			expect.equal(section.newer, nil)
			expect.equal(section.visibleCount, 1)
		end)

		t:it("measures an entry once: a refresh with the same content measures nothing new", function()
			local mock, _, ns, section = start()
			for i = 1, 12 do mock.Slash("journal add Entry " .. i) end
			ns.MainWindow.Refresh()
			local measured = section.heightCount
			ns.MainWindow.Refresh()
			ns.MainWindow.Refresh()
			expect.equal(section.heightCount, measured)
			mock.Slash("journal add One more")
			expect.equal(section.heightCount, measured + 1)
		end)

		t:it("defining moments are featured cards with a gold day; drafts wait in amber", function()
			local mock, env, ns, section = start()
			turnIn(mock, 30, "Draft Quest")
			mock.Slash("story 1 1")
			mock.Slash("journal add Plain")
			mock.Slash("journal add Defining")
			local list = char(env).journal
			ns.Actions.SetEntryImportant(ns.ctx, list[#list].id, true)
			ns.MainWindow.Refresh()
			local byText = {}
			for i = 1, section.visibleCount do
				local row = section.rows[i]
				byText[row.entry.kind == "story" and "story" or row.entry.text] = row
			end
			expect.truthy(byText.Defining.featured)
			expect.equal(byText.Defining.date.day.textRole, "accentBright")
			expect.falsy(byText.Plain.featured)
			expect.equal(byText.Plain.date.day.textRole, "ghostText")
			expect.equal(byText.story.chips[1].tone, "waiting")
			expect.equal(byText.Defining.chips[1].tone, "accent")
		end)
	end)

	t:describe("journal dashboard: a moment awaits (L2)", function()
		t:it("is hidden while nothing is waiting", function()
			local _, _, _, section = start()
			expect.falsy(section.callout:IsShown())
		end)

		t:it("shows the real pending question; Answer opens it in the Story section", function()
			local mock, env, ns, section = start()
			turnIn(mock, 10, "The Defias Brotherhood")
			ns.MainWindow.Select("journal")
			local callout = section.callout
			expect.truthy(callout:IsShown())
			local reaction = char(env).story.reactions[1]
			local presentation = ns.Reactions.Present(char(env), reaction)
			expect.equal(callout.question:GetText(), presentation.question)
			expect.equal(callout.title:GetText(), "A MOMENT AWAITS · 1 OF 1")
			click(callout.answer)
			expect.equal(ns.MainWindow.CurrentSection(), "story")
			expect.equal(ns.StoryView.section.reactionId, reaction.id)
		end)

		t:it("Later keeps the moment in the Story section and the callout moves on", function()
			local mock, env, ns, section = start()
			turnIn(mock, 11, "One")
			mock.zone = "Duskwood"
			mock.Slash("story set frequency frequent")
			char(env).story.pacing.playByCategory = {}
			turnIn(mock, 12, "Two")
			ns.MainWindow.Refresh()
			expect.truthy(section.callout.title:GetText():find("1 OF 2", 1, true))
			local first = section.callout.reactionId
			click(section.callout.later)
			expect.equal(ns.Reactions.Find(char(env), first).status, "postponed")
			expect.truthy(section.callout:IsShown())
			expect.truthy(section.callout.title:GetText():find("1 OF 1", 1, true))
			click(section.callout.later)
			expect.falsy(section.callout:IsShown(), "postponed moments wait in the Story section only")
			expect.equal(#char(env).story.reactions, 2, "nothing was answered or dismissed")
		end)
	end)

	t:describe("journal dashboard: layout (L2)", function()
		t:it("keeps the toolbar apart and the right column inside the content area, callout included", function()
			local mock, _, ns, section = start()
			turnIn(mock, 10, "The Defias Brotherhood")
			mock.Fire("PLAYER_LEVEL_UP", 24)
			for i = 1, 3 do
				local id = mock.Slash("goal add A long goal title that wraps onto a second line " .. i):match("#(%d+)")
				mock.Slash("goal level " .. id .. " 30")
			end
			ns.MainWindow.Refresh()
			expect.truthy(section.callout:IsShown())
			local W, H = ns.MainWindow.ContentWidth(), ns.MainWindow.ContentHeight()
			local L = ns.JournalView.LAYOUT
			-- Toolbar: New entry, then search, then the filter's track at the right edge.
			local searchRight = section.newButton:GetWidth() + L.toolGap + section.search:GetWidth()
			local seg = section.filters.buttons
			local segWidth = (#seg - 1) * L.segmentGap
			for i, b in ipairs(seg) do
				segWidth = segWidth + b:GetWidth()
				expect.equal(b:GetWidth(), L.segmentWidths[i], "each item sized to its word")
				if i > 1 then expect.equal(lastPoint(b)[4], L.segmentGap) end
			end
			expect.equal(segWidth, L.segmentsW)
			expect.truthy(seg[1]:GetWidth() < seg[2]:GetWidth(), "All is narrower than Defining, as in the design")
			local trackLeft = W - section.filterTrack:GetWidth()
			expect.equal(lastPoint(section.filterTrack)[1], "TOPRIGHT")
			expect.truthy(searchRight + 10 <= trackLeft, "search and filter apart")
			expect.truthy(L.trackPad + segWidth + L.trackPad <= section.filterTrack:GetWidth(), "items inside the track")
			-- Right column: both panels stacked inside the content height.
			local goalsTop = -lastPoint(section.goals)[5]
			local placesTop = -lastPoint(section.places)[5]
			expect.truthy(goalsTop + section.goals:GetHeight() <= placesTop, "goals above places")
			expect.truthy(placesTop + section.places:GetHeight() <= H, "places inside the content area")
			expect.equal(lastPoint(section.goals)[4], W - 250, "right column 250 wide at the right edge")
			expect.equal(section.goals.shown, 3)
		end)
	end)

	t:describe("journal dashboard: design sizes (L2, Main.dc.html)", function()
		t:it("splits the content area like the design: list, gutter with the scroll bar, gap, right column", function()
			local _, _, ns = start()
			local L = ns.JournalView.LAYOUT
			local W = ns.MainWindow.ContentWidth()
			expect.equal(L.listW + L.colGap + L.sideW, W)
			expect.equal(L.cardW + L.gutter, L.listW)
			expect.equal(L.sideW, 250)
			expect.equal(L.textX, 86, "18 padding, 52 date, 16 gap")
			expect.truthy(L.scrollBarW <= L.gutter, "the scroll bar sits in the gutter, beside the cards")
		end)

		t:it("puts the subline under the window title and above the toolbar, without overlapping either", function()
			local _, _, ns, section = start()
			local L, W = ns.JournalView.LAYOUT, ns.MainWindow.LAYOUT
			local titleBottom = W.headerTop + W.eyebrowHeight + W.titleGap + W.titleHeight -- from the window top
			local sublineTop = W.contentTop + L.sublineTop
			expect.truthy(sublineTop >= titleBottom, "below the title box")
			expect.truthy(sublineTop - titleBottom <= 4, "close under the title, as in the design")
			expect.truthy(L.sublineTop + L.sublineH <= L.toolbarTop, "above the toolbar")
			expect.equal(lastPoint(section.subline)[3], -L.sublineTop)
			expect.equal(section.subline:GetText(), "No entries yet")
		end)

		t:it("uses the design system's control heights in the toolbar, callout and cards", function()
			local mock, _, ns, section = start()
			local C = ns.Style.CONTROL
			turnIn(mock, 10, "The Defias Brotherhood")
			mock.Slash("journal add Words")
			ns.MainWindow.Refresh()
			expect.equal(section.newButton:GetHeight(), C.standard)
			expect.equal(section.search:GetHeight(), C.input)
			for _, b in ipairs(section.filters.buttons) do
				expect.equal(b:GetHeight(), C.compact)
				expect.truthy(ns.Widgets.LabelFits(b:GetText(), b:GetWidth(), b:GetHeight(), "segment"), b:GetText())
			end
			expect.equal(section.filterTrack:GetHeight(), C.compact + 2 * ns.JournalView.LAYOUT.trackPad)
			expect.equal(section.callout.answer:GetHeight(), C.standard)
			expect.equal(section.callout.later:GetHeight(), C.standard)
			expect.truthy(ns.Widgets.LabelFits("New entry", section.newButton:GetWidth(), C.standard, "primary", true))
			local row = section.rows[1]
			for _, b in ipairs({ row.edit, row.delete, row.approve, row.mark }) do
				expect.equal(b:GetHeight(), C.compact)
				expect.truthy(ns.Widgets.LabelFits(b:GetText(), b:GetWidth(), b:GetHeight(), nil, b.icon ~= nil),
					b:GetText() .. " fits with its icon")
				expect.truthy(b.icon ~= nil, "every footer action has the design's line icon")
			end
			expect.equal(row.mark:GetWidth(), C.compact, "Defining is a square star toggle")
			expect.equal(row.vis, nil, "no visibility chip in the footer")
		end)

		t:it("sets story text in the reading style, meta in the meta style and titles in Cinzel", function()
			local mock, _, ns, section = start()
			mock.Slash("journal add Words")
			ns.MainWindow.Refresh()
			local row = section.rows[1]
			local S = ns.Style
			expect.equal(row.body.__template, S.FontFor("reading"))
			expect.equal(row.meta.__template, S.FontFor("meta"))
			expect.equal(row.title.__template, S.FontFor("GameFontNormalLarge"))
			expect.equal(section.callout.question.__template, S.FontFor("reading"))
			expect.equal(row.body.textRole, "reading")
			expect.equal(row.title.textRole, "heading", "title white")
		end)

		t:it("keeps a draft's footer to its actions, every action inside the card's text column", function()
			local mock, _, ns, section = start()
			turnIn(mock, 30, "Draft Quest")
			mock.Slash("story 1 1")
			ns.MainWindow.Refresh()
			local L = ns.JournalView.LAYOUT
			local row
			for i = 1, section.visibleCount do
				if section.rows[i].entry.kind == "story" then row = section.rows[i] end
			end
			expect.truthy(row.approve:IsShown() and row.edit:IsShown() and row.delete:IsShown() and row.mark:IsShown())
			-- Actions laid from the right edge, all inside the text column.
			local width = 0
			for _, b in ipairs(row.actions) do
				if b:IsShown() then width = width + b:GetWidth() + L.actionGap end
			end
			local actionsLeft = L.cardW - L.padX - (width - L.actionGap)
			expect.truthy(actionsLeft >= L.textX, "inside the text column")
			expect.equal(row.vis, nil, "no visibility chip")
			-- Title and chips share the first line without overlapping.
			local chipsWidth = 0
			for _, chip in ipairs(row.chips) do
				if chip:IsShown() then chipsWidth = chipsWidth + chip:GetWidth() + L.chipGap end
			end
			expect.truthy(row.meta:GetWidth() + chipsWidth <= L.textW or row.title:IsShown(), "meta beside chips")
			if row.title:IsShown() then
				expect.truthy(row.title:GetWidth() + chipsWidth <= L.textW, "title beside chips")
			end
			for _, chip in ipairs(row.chips) do
				expect.truthy(chip:GetWidth() <= L.chipMaxW, "long chips are capped (full text on hover)")
			end
		end)

		t:it("lays the callout out like the design: disc, eyebrow and question, buttons at the right", function()
			local mock, _, ns, section = start()
			turnIn(mock, 10, "The Defias Brotherhood")
			ns.MainWindow.Refresh()
			local L = ns.JournalView.LAYOUT
			local c = section.callout
			expect.truthy(c:IsShown())
			expect.truthy(c:GetHeight() >= L.calloutMinH)
			expect.equal(lastPoint(c.question)[2], L.questionX)
			local buttons = L.answerW + 8 + L.laterW + L.calloutPadX
			expect.truthy(L.questionX + c.question:GetWidth() + L.discGap + buttons <= ns.MainWindow.ContentWidth(),
				"question never runs under Answer and Later")
			expect.equal(lastPoint(c.later)[1], "RIGHT")
			expect.truthy(c.discEdge and c.disc and c.icon, "icon disc with the sparkle")
			expect.equal(c.icon.name, "sparkle")
			-- The list starts below the callout with the design's gap.
			expect.equal(section.listTop, L.calloutTop + c:GetHeight() + L.blockGap)
		end)

		t:it("shows an empty list as a card explaining what to do", function()
			local _, _, ns, section = start()
			expect.truthy(section.emptyCard:IsShown())
			expect.equal(section.empty:GetText(), ns.JournalView.EMPTY_TEXT)
			expect.equal(section.empty:GetParent(), section.emptyCard)
			expect.truthy(section.emptyCard:GetHeight() >= 24 + 60 + 24)
		end)

		t:it("finds the cards in view with pure list maths", function()
			local JV = select(3, Boot.Start()).JournalView
			local items = { { height = 100 }, { height = 50 }, { height = 200 }, { height = 80 } }
			expect.equal(JV.Stack(items, 12), 100 + 50 + 200 + 80 + 3 * 12)
			expect.equal(items[3].top, 174)
			local a, b = JV.Window(items, 0, 120)
			expect.equal(a, 1); expect.equal(b, 2)
			a, b = JV.Window(items, 165, 30)
			expect.equal(a, 3); expect.equal(b, 3)
			a, b = JV.Window(items, 380, 500)
			expect.equal(a, 4); expect.equal(b, 4)
			expect.equal(JV.Window({}, 0, 100), nil)
			expect.equal(JV.ClampOffset(900, 466, 300), 166)
			expect.equal(JV.ClampOffset(-5, 466, 300), 0)
			expect.equal(JV.ClampOffset(50, 100, 300), 0)
		end)
	end)

	t:describe("journal dashboard: right column (L2)", function()
		t:it("explains empty goals and places", function()
			local _, _, ns, section = start()
			expect.truthy(section.goals.empty:IsShown())
			expect.equal(section.goals.empty:GetText(), ns.JournalView.GOALS_EMPTY)
			expect.truthy(section.places.empty:IsShown())
			expect.equal(section.places.empty:GetText(), ns.JournalView.PLACES_EMPTY)
			expect.equal(section.goals.shown, 0)
		end)

		t:it("shows active goals with milestone and verified progress; All opens Chronicle > Goals", function()
			local mock, _, ns, section = start()
			mock.Fire("PLAYER_LEVEL_UP", 24)
			local id = mock.Slash("goal add Earn the Light's trust"):match("#(%d+)")
			mock.Slash("goal level " .. id .. " 30")
			local id2 = mock.Slash("goal add Find the missing courier"):match("#(%d+)")
			mock.Slash("goal milestone " .. id2 .. " Ask in the inn")
			mock.Slash("goal milestone " .. id2 .. " Search the road")
			mock.Slash("goal done " .. id2 .. " 1")
			ns.MainWindow.Refresh()
			local goals = section.goals
			expect.falsy(goals.empty:IsShown())
			expect.equal(goals.shown, 2)
			expect.equal(goals.rows[1].title:GetText(), "Earn the Light's trust")
			expect.equal(goals.rows[1].caption:GetText(), "Level 24 of 30 · verified")
			expect.equal(goals.rows[1].bar.value, 0.8)
			expect.equal(goals.rows[2].caption:GetText(), "1 of 2 milestones")
			expect.equal(goals.rows[2].bar.value, 0.5)
			click(goals.all)
			expect.equal(ns.MainWindow.CurrentSection(), "chronicle")
			expect.equal(ns.ChronicleView.section.tab, "goals")
		end)

		t:it("lists recent places from the places log with Homeland and Meaningful chips", function()
			local mock, env, ns, section = start()
			mock.zone, mock.subzone = "Duskwood", "Darkshire"
			mock.Fire("ZONE_CHANGED_NEW_AREA")
			local c = char(env)
			local P = ns.Places
			local goldshire = P.CleanEntry({ zone = "Elwynn Forest", subzone = "Goldshire", first = 1, last = 2,
				visits = 9, kind = "town" })
			c.story.places[P.Key("Elwynn Forest", "Goldshire")] = goldshire
			P.SetHomeland(c, goldshire, 3)
			ns.MainWindow.Refresh()
			local places = section.places
			expect.falsy(places.empty:IsShown())
			local byName = {}
			for i = 1, places.shown do byName[places.rows[i].name:GetText()] = places.rows[i] end
			local home = byName.Goldshire
			expect.truthy(home, "the homeland is listed")
			expect.equal(home.chips[1].label:GetText(), "Homeland")
			expect.equal(home.chips[2].label:GetText(), "Meaningful")
			expect.equal(home.detail:GetText(), "Elwynn Forest · settlement · 9 visits")
			local dark = byName.Darkshire
			expect.truthy(dark, "a place logged by travelling")
			expect.falsy(dark.chips[1]:IsShown())
			expect.truthy(dark.detail:GetText():find("^Duskwood"))
			expect.equal(places.rows[places.shown].name:GetText(), "Goldshire", "most recent first")
		end)
	end)
end
