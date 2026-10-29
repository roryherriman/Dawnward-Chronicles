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

local function typeInto(box, text)
	box:SetText(text)
	box:GetScript("OnTextChanged")(box, true)
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
			expect.equal(section.newButton:GetText(), "+ New entry")
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
			typeInto(section.search, "goldshire")
			expect.equal(section.visibleCount, 1)
			expect.equal(section.rows[1].entry.kind, "event", "matched by its place")
			typeInto(section.search, "RIVER")
			expect.equal(section.visibleCount, 1)
			expect.equal(section.rows[1].entry.kind, "note")
			typeInto(section.search, "dragons")
			expect.equal(section.visibleCount, 0)
			expect.truthy(section.empty:IsShown())
			expect.equal(section.empty:GetText(), ns.JournalView.NO_MATCH_TEXT)
			typeInto(section.search, "")
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

		t:it("reuses card frames across refreshes and pages", function()
			local mock, _, ns, section = start()
			for i = 1, 15 do mock.Slash("journal add Entry " .. i) end
			ns.MainWindow.Refresh()
			local first = section.rows[1]
			expect.equal(#section.rows, 10)
			expect.truthy(section.older:IsShown(), "the pager appears when there is more than one page")
			click(section.older)
			ns.MainWindow.Refresh()
			expect.equal(#section.rows, 10)
			expect.equal(section.rows[1], first)
			expect.equal(section.visibleCount, 5)
			expect.falsy(section.rows[6]:IsShown())
		end)

		t:it("hides the pager when everything fits on one page", function()
			local mock, _, ns, section = start()
			mock.Slash("journal add Only one")
			ns.MainWindow.Refresh()
			expect.falsy(section.older:IsShown())
			expect.falsy(section.newer:IsShown())
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
			-- Toolbar: New entry, then search, then the filter at the right edge.
			local searchRight = section.newButton:GetWidth() + 10 + section.search:GetWidth()
			local seg = section.filters.buttons
			local segWidth = #seg * seg[1]:GetWidth() + (#seg - 1) * 2
			local segLeft = W + lastPoint(seg[1])[4] - seg[1]:GetWidth()
			expect.truthy(searchRight + 10 <= segLeft, "search and filter apart")
			expect.truthy(segLeft + segWidth <= W, "filter inside the content area")
			-- Right column: both panels stacked inside the content height.
			local goalsTop = -lastPoint(section.goals)[5]
			local placesTop = -lastPoint(section.places)[5]
			expect.truthy(goalsTop + section.goals:GetHeight() <= placesTop, "goals above places")
			expect.truthy(placesTop + section.places:GetHeight() <= H, "places inside the content area")
			expect.equal(lastPoint(section.goals)[4], W - 270, "right column 270 wide at the right edge")
			expect.equal(section.goals.shown, 3)
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
