-- Journal section (v0.7 dashboard, docs/design/mockups/journal-dashboard.png).
--
--   subline      real counts: entries, defining moments, when the last was written
--   toolbar      New entry, a search box (title, text and place) and a filter:
--                All / Defining (important) / Story (story entries) / Events
--                (automatic entries)
--   callout      "A moment awaits": the first Story Director reaction still
--                pending, with Answer (opens it in the Story section) and Later
--                (the same postpone as the reaction card). Hidden when none.
--   cards        entries newest first, ten per page: date block, title, meta
--                line, text, status chips, visibility and the entry's actions,
--                all inside the card
--   right column Active goals (milestones and verified progress) and Recent
--                places (from the places log, with Homeland / Meaningful chips)
--
-- Cards, goal rows and place rows are created once and reused, so the number of
-- frames stays small however large the journal grows. Every write goes
-- through Core/Actions.lua.
local _, ns = ...
local Widgets, MainWindow, Actions, Journal = ns.Widgets, ns.MainWindow, ns.Actions, ns.Journal

local JournalView = {}
ns.JournalView = JournalView

JournalView.PAGE_SIZE = 10
JournalView.EMPTY_TEXT = "Your journal is empty.\n\nWrite your first entry with New entry, or keep adventuring: "
	.. "level-ups are recorded here automatically."
JournalView.NO_MATCH_TEXT = "No entries match.\n\nTry other words, or choose All to see every entry."
JournalView.GOALS_EMPTY = "No active goals yet. Add one in Chronicle > Goals: its milestones and verified "
	.. "progress show here."
JournalView.PLACES_EMPTY = "No places recorded yet. Places are logged as you travel; mark the ones that "
	.. "matter in Chronicle > Places."
JournalView.FILTERS = {
	{ id = "all", label = "All" },
	{ id = "defining", label = "Defining" },
	{ id = "story", label = "Story" },
	{ id = "events", label = "Events" },
}
JournalView.MAX_GOALS = 3
JournalView.MAX_PLACES = 4

local SEP = " · "

-- Layout (UI units, measured from the content area's top-left corner).
local CONTENT_W = MainWindow.ContentWidth()
local CONTENT_H = MainWindow.ContentHeight()
local SIDE_W = 270          -- right column
local COL_GAP = 16
local LIST_W = CONTENT_W - SIDE_W - COL_GAP
local SCROLLBAR = 22        -- the scroll bar sits inside the list column
local SUBLINE_TOP = 0
local TOOLBAR_TOP = 24
local TOOLBAR_H = 28
local CALLOUT_TOP = 64
local BLOCK_GAP = 12
local PAGER_H = 30
local PAD = 14              -- inside a card
local DATE_W = 56
local TEXT_X = PAD + DATE_W + 6
local CHIP_GAP = 6
local MAX_CHIPS = 3
local SEGMENT_W = 264

--- Full meta text for an entry (date, level, place, origin, flags). Kept for
-- the card's date tooltip and for callers outside the window.
function JournalView.MetaText(entry, formatDate)
	local parts = { formatDate(entry.createdAt) }
	local event = entry.event
	if entry.kind == "event" and event then
		if event.level then
			parts[#parts + 1] = "Level " .. event.level
		end
		if event.zone then
			parts[#parts + 1] = event.subzone and (event.zone .. " (" .. event.subzone .. ")") or event.zone
		end
		parts[#parts + 1] = event.source == "SIMULATION" and "simulated" or "recorded automatically"
	elseif entry.kind == "story" then
		parts[#parts + 1] = entry.status == "approved" and "story" or "draft - approve to keep"
		if entry.updatedAt then
			parts[#parts + 1] = "edited"
		end
	elseif entry.updatedAt then
		parts[#parts + 1] = "edited"
	end
	if entry.important then
		parts[#parts + 1] = "defining moment"
	end
	return table.concat(parts, "  -  ")
end

-- The recorded event a story entry was written from, if it is still kept.
local function storyRecord(char, entry)
	local key = entry.kind == "story" and entry.story and entry.story.eventKey
	return key and char and ns.GameEvents.Find(char, key) or nil
end

--- Where an entry happened, from recorded data only ("Goldshire, Elwynn
-- Forest"), or nil. Notes carry no place: none is ever guessed.
function JournalView.Location(char, entry)
	local event = entry.kind == "event" and entry.event
	if event and event.zone then
		return event.subzone and (event.subzone .. ", " .. event.zone) or event.zone
	end
	local record = storyRecord(char, entry)
	return record and record.zone or nil
end

--- The card's meta line: place, level and where the words came from. Pure.
function JournalView.CardMeta(char, entry)
	local parts = {}
	if entry.kind == "event" then
		local event = entry.event or {}
		local place = JournalView.Location(char, entry)
		if place then parts[#parts + 1] = place end
		if event.level then parts[#parts + 1] = "Level " .. event.level end
		parts[#parts + 1] = event.source == "SIMULATION" and "simulated" or "recorded automatically"
	elseif entry.kind == "story" then
		parts[#parts + 1] = "Story development"
		local place = JournalView.Location(char, entry)
		if place then parts[#parts + 1] = "from your answer in " .. place end
		if entry.updatedAt then parts[#parts + 1] = "edited" end
	else
		parts[#parts + 1] = "Your words"
		if entry.updatedAt then parts[#parts + 1] = "edited" end
	end
	return table.concat(parts, SEP)
end

--- Status chips for an entry, from its real flags: { { text, tone } }. Pure.
function JournalView.Chips(entry)
	local chips = {}
	if entry.important then
		chips[#chips + 1] = { text = "Defining", tone = "accent" }
	end
	if Journal.NeedsApproval(entry) then
		chips[#chips + 1] = { text = "Waiting for your approval", tone = "accent" }
	elseif entry.kind == "story" then
		chips[#chips + 1] = { text = "Story", tone = "muted" }
	elseif entry.kind == "event" then
		local simulated = entry.event and entry.event.source == "SIMULATION"
		chips[#chips + 1] = { text = simulated and "Simulated event" or "Recorded event", tone = "muted" }
	end
	return chips
end

--- The card's title: the entry's own, or for an automatic entry its recorded
-- text (which then is not repeated as the body). Returns title, body.
function JournalView.TitleAndBody(entry)
	if entry.title then
		return entry.title, entry.text
	end
	if entry.kind == "event" and entry.text then
		return (entry.text:gsub("%.$", "")), nil
	end
	return nil, entry.text
end

--- Entries for a filter id and search text, newest first. Search covers the
-- title, the text and the recorded place, ignoring case. Pure.
function JournalView.Filter(char, filterId, query)
	local needle = query and query ~= "" and query:lower() or nil
	local out = {}
	for _, e in ipairs(Journal.NewestFirst(char)) do
		local ok = filterId == "defining" and e.important == true
			or filterId == "story" and e.kind == "story"
			or filterId == "events" and e.kind == "event"
			or (filterId == nil or filterId == "all")
		if ok and needle then
			local hay = ((e.title or "") .. "\n" .. (e.text or "") .. "\n" .. (JournalView.Location(char, e) or ""))
			ok = hay:lower():find(needle, 1, true) ~= nil
		end
		if ok then
			out[#out + 1] = e
		end
	end
	return out
end

local function dayKey(t)
	return date("%Y%m%d", t)
end

--- "today", "yesterday", "3 days ago" or a date, for a timestamp. Pure.
function JournalView.When(t, now)
	if type(t) ~= "number" or t <= 0 then
		return "on an unknown date"
	end
	now = now or t
	if dayKey(t) == dayKey(now) then return "today" end
	if dayKey(t) == dayKey(now - 86400) then return "yesterday" end
	local days = math.floor((now - t) / 86400)
	if days >= 2 and days < 7 then return days .. " days ago" end
	return date("%d %b %Y", t)
end

--- The header subline: "12 entries · 2 defining moments · last entry today". Pure.
function JournalView.Subline(char, now)
	local list = char and char.journal or {}
	if #list == 0 then
		return "No entries yet"
	end
	local defining = 0
	for _, e in ipairs(list) do
		if e.important then defining = defining + 1 end
	end
	return string.format("%d %s%s%d defining %s%slast entry %s", #list, #list == 1 and "entry" or "entries", SEP,
		defining, defining == 1 and "moment" or "moments", SEP, JournalView.When(list[#list].createdAt, now))
end

--- Reactions still waiting for an answer (postponed ones live in the Story
-- section only), in the Story Director's order.
function JournalView.PendingReactions(char, now)
	local out = {}
	if not char then return out end
	for _, r in ipairs(ns.Reactions.List(char, now)) do
		if r.status == "pending" then out[#out + 1] = r end
	end
	return out
end

--- A goal's progress for the right column: fraction (0..1) and caption, from
-- the verified objective when there is one, otherwise from milestones. Pure.
function JournalView.GoalProgress(char, goal)
	local p = ns.Goals.Progress(char, goal)
	local parts, fraction = {}, 0
	local o = p.objective
	if o and o.kind == "level" then
		if o.current then
			parts[#parts + 1] = string.format("Level %d of %d%sverified", o.current, o.target, SEP)
			fraction = o.current / o.target
		else
			parts[#parts + 1] = string.format("Level %d goal%snot verified yet", o.target, SEP)
		end
	elseif o and o.kind == "reputation" then
		local S = ns.GameEvents.STANDINGS
		if o.current then
			parts[#parts + 1] = string.format("%s of %s with %s%sobserved", S[o.current], S[o.target], o.factionName,
				SEP)
			fraction = o.current / o.target
		else
			parts[#parts + 1] = string.format("%s with %s%snot observed yet", S[o.target], o.factionName, SEP)
		end
	end
	if p.milestonesTotal > 0 then
		parts[#parts + 1] = string.format("%d of %d milestones", p.milestonesDone, p.milestonesTotal)
		if not o then fraction = p.milestonesDone / p.milestonesTotal end
	end
	if #parts == 0 then
		parts[1] = "No milestones yet"
	end
	return math.max(0, math.min(1, fraction)), table.concat(parts, SEP)
end

--- A place's detail line: "Elwynn Forest · settlement · 3 visits". Pure.
function JournalView.PlaceDetail(entry)
	local parts = {}
	if entry.subzone then parts[#parts + 1] = entry.zone end
	if entry.kind then parts[#parts + 1] = ns.Places.KIND_LABELS[entry.kind] or entry.kind end
	parts[#parts + 1] = string.format("%d %s", entry.visits or 1, entry.visits == 1 and "visit" or "visits")
	return table.concat(parts, SEP)
end

--- Page maths: returns clamped page and page count for n entries.
function JournalView.ClampPage(page, n)
	local pages = math.max(1, math.ceil(n / JournalView.PAGE_SIZE))
	if page < 1 then
		page = 1
	elseif page > pages then
		page = pages
	end
	return page, pages
end

-- Lays chips out from a right edge leftwards; returns the width they take.
local function placeChips(chips, specs, anchor, x, y)
	local width = 0
	for i = 1, #chips do
		local chip, spec = chips[i], specs[i]
		if spec then
			chip:SetChip(spec.text, spec.tone)
			chip:ClearAllPoints()
			chip:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -(x + width), y)
			chip:Show()
			width = width + chip:GetWidth() + CHIP_GAP
		else
			chip:Hide()
		end
	end
	return width
end

local function textHeight(fs, minimum)
	local h = fs.GetStringHeight and fs:GetStringHeight() or 0
	return math.max(minimum or 0, type(h) == "number" and h or 0)
end

local function openChronicle(tab)
	local chronicle = ns.ChronicleView and ns.ChronicleView.section
	if chronicle then
		if chronicle.SelectTab then
			chronicle:SelectTab(tab)
		else
			chronicle.tab, chronicle.page = tab, 1
		end
	end
	MainWindow.Select("chronicle")
end

--- The right column ---------------------------------------------------------------

local SIDE_INNER = SIDE_W - 2 * Widgets.PANEL_PAD
local PANEL_TOP = Widgets.PANEL_PAD + 22  -- the panel's title takes this much

local function buildSide(section, f)
	-- Active goals.
	local goals = Widgets.Panel(f, "Active goals")
	goals:SetWidth(SIDE_W)
	goals.all = Widgets.Button(goals, "All", 40, 18, "ghost")
	goals.all:SetPoint("TOPRIGHT", -8, -10)
	goals.all:SetScript("OnClick", function() openChronicle("goals") end)
	Widgets.Tooltip(goals.all, "All goals", "Open Chronicle > Goals to see, add and edit every goal.")
	goals.empty = Widgets.Label(goals.inner, "GameFontHighlightSmall", true, "muted")
	goals.empty:SetPoint("TOPLEFT", 0, 0)
	goals.empty:SetWidth(SIDE_INNER)
	goals.empty:SetText(JournalView.GOALS_EMPTY)
	goals.rows = {}
	for i = 1, JournalView.MAX_GOALS do
		local row = CreateFrame("Frame", nil, goals.inner)
		row:SetWidth(SIDE_INNER)
		row.title = Widgets.Label(row, "GameFontHighlight", true, "body")
		row.title:SetPoint("TOPLEFT", 0, 0)
		row.title:SetWidth(SIDE_INNER)
		row.bar = Widgets.ProgressBar(row, SIDE_INNER, 4)
		row.caption = Widgets.Label(row, "GameFontHighlightSmall", true, "muted")
		row.caption:SetWidth(SIDE_INNER)
		goals.rows[i] = row
	end
	section.goals = goals

	-- Recent places.
	local places = Widgets.Panel(f, "Recent places")
	places:SetWidth(SIDE_W)
	places.empty = Widgets.Label(places.inner, "GameFontHighlightSmall", true, "muted")
	places.empty:SetPoint("TOPLEFT", 0, 0)
	places.empty:SetWidth(SIDE_INNER)
	places.empty:SetText(JournalView.PLACES_EMPTY)
	places.rows = {}
	for i = 1, JournalView.MAX_PLACES do
		local row = CreateFrame("Frame", nil, places.inner)
		row:SetWidth(SIDE_INNER)
		row.divider = Widgets.Divider(row)
		row.divider:SetPoint("TOPLEFT", 0, 0)
		row.divider:SetPoint("TOPRIGHT", 0, 0)
		row.name = Widgets.Label(row, "GameFontHighlight", false, "body")
		row.name:SetWidth(SIDE_INNER)
		row.chips = { Widgets.Chip(row, "Homeland"), Widgets.Chip(row, "Meaningful") }
		row.detail = Widgets.Label(row, "GameFontHighlightSmall", true, "muted")
		row.detail:SetWidth(SIDE_INNER)
		places.rows[i] = row
	end
	section.places = places
end

local function renderGoals(goals, char)
	local list = char and ns.Goals.Active(char) or {}
	goals.empty:SetShown(#list == 0)
	local y = 0
	for i, row in ipairs(goals.rows) do
		local goal = list[i]
		row:SetShown(goal ~= nil)
		if goal then
			row.goalId = goal.id
			row.title:SetText(goal.title)
			local fraction, caption = JournalView.GoalProgress(char, goal)
			local th = textHeight(row.title, 16)
			row.bar:ClearAllPoints()
			row.bar:SetPoint("TOPLEFT", 0, -(th + 6))
			row.bar:SetValue(fraction)
			row.caption:ClearAllPoints()
			row.caption:SetPoint("TOPLEFT", 0, -(th + 16))
			row.caption:SetText(caption)
			local h = th + 16 + textHeight(row.caption, 14)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 0, -y)
			row:SetHeight(h)
			y = y + h + 12
		end
	end
	if #list == 0 then
		y = textHeight(goals.empty, 28) + 12
	end
	goals.shown = math.min(#list, #goals.rows)
	return PANEL_TOP + y - 12 + Widgets.PANEL_PAD
end

local function renderPlaces(places, char, available)
	local list = char and ns.Places.List(char) or {}
	places.empty:SetShown(#list == 0)
	local y, shown = 0, 0
	for i, row in ipairs(places.rows) do
		local entry = list[i]
		local fits = false
		if entry then
			local specs = {}
			if ns.Places.IsHomeland(char, entry) then specs[#specs + 1] = { text = "Homeland" } end
			if entry.meaningful then specs[#specs + 1] = { text = "Meaningful" } end
			local top = i > 1 and 9 or 0
			row.divider:SetShown(i > 1)
			row.name:ClearAllPoints()
			row.name:SetPoint("TOPLEFT", 0, -top)
			row.name:SetText(entry.subzone or entry.zone)
			local h = top + 18
			for c, chip in ipairs(row.chips) do
				local spec = specs[c]
				chip:SetShown(spec ~= nil)
				if spec then
					chip:SetChip(spec.text, "accent")
					chip:ClearAllPoints()
					if c == 1 then
						chip:SetPoint("TOPLEFT", 0, -h - 2)
					else
						chip:SetPoint("LEFT", row.chips[c - 1], "RIGHT", CHIP_GAP, 0)
					end
				end
			end
			if #specs > 0 then h = h + Widgets.CHIP_HEIGHT + 6 end
			row.detail:ClearAllPoints()
			row.detail:SetPoint("TOPLEFT", 0, -h)
			row.detail:SetText(JournalView.PlaceDetail(entry))
			h = h + textHeight(row.detail, 14)
			fits = y + h <= available
			if fits then
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", 0, -y)
				row:SetHeight(h)
				y = y + h
				shown = shown + 1
			end
		end
		row:SetShown(fits)
		if not fits then
			for j = i + 1, #places.rows do places.rows[j]:Hide() end
			break
		end
	end
	places.shown = shown
end

--- The section ----------------------------------------------------------------------

local function create(parent)
	local section = { frame = CreateFrame("Frame", nil, parent), rows = {}, page = 1, filter = "all", query = "" }
	local f = section.frame

	-- Subline and toolbar.
	section.subline = Widgets.Label(f, "GameFontHighlight", false, "muted")
	section.subline:SetPoint("TOPLEFT", 0, -SUBLINE_TOP)
	section.subline:SetWidth(CONTENT_W)

	section.toolbar = CreateFrame("Frame", nil, f)
	section.toolbar:SetPoint("TOPLEFT", 0, -TOOLBAR_TOP)
	section.toolbar:SetSize(CONTENT_W, TOOLBAR_H)

	section.search = Widgets.SearchBox(section.toolbar, 230, "Search the journal", function(text)
		if text ~= section.query then
			section.query = text
			section.page = 1
			MainWindow.Refresh()
		end
	end)
	section.search:SetHeight(TOOLBAR_H - 2)
	Widgets.Tooltip(section.search, "Search the journal", "Finds entries by title, text or recorded place.")

	section.filters = Widgets.Segmented(section.toolbar, JournalView.FILTERS, SEGMENT_W, 24, function(id)
		section.filter, section.page = id, 1
		section.scroll:SetVerticalScroll(0)
		MainWindow.Refresh()
	end)
	-- Right-aligned: the first button's right edge sits (n - 1) buttons in.
	section.filters.buttons[1]:SetPoint("TOPRIGHT", section.toolbar, "TOPRIGHT",
		-((#JournalView.FILTERS - 1) * math.floor(SEGMENT_W / #JournalView.FILTERS)), -2)
	section.filters:Select("all")

	-- "A moment awaits".
	local callout = Widgets.Callout(f, "A moment awaits")
	callout:SetPoint("TOPLEFT", 0, -CALLOUT_TOP)
	callout:SetWidth(CONTENT_W)
	callout.icon = callout:CreateTexture(nil, "ARTWORK")
	callout.icon:SetSize(36, 36)
	callout.icon:SetPoint("TOPLEFT", 16, -14)
	callout.icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
	callout.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	callout.title:ClearAllPoints()
	callout.title:SetPoint("TOPLEFT", 66, -12)
	callout.later = Widgets.Button(callout, "Later", 80, 26, "ghost")
	callout.later:SetPoint("TOPRIGHT", -16, -18)
	Widgets.Tooltip(callout.later, "Later", "Keep it in the Story section for later. You will not be reminded again.")
	callout.answer = Widgets.Button(callout, "Answer", 90, 26, "primary")
	callout.answer:SetPoint("RIGHT", callout.later, "LEFT", -8, 0)
	callout.question = Widgets.Label(callout, "GameFontHighlight", true, "body")
	callout.question:SetPoint("TOPLEFT", 66, -30)
	callout.question:SetWidth(CONTENT_W - 66 - 220)
	callout.answer:SetScript("OnClick", function()
		local id = callout.reactionId
		if ns.StoryView and ns.StoryView.section then
			ns.StoryView.section:Focus(id)
		end
		MainWindow.Select("story")
	end)
	callout.later:SetScript("OnClick", function()
		local _, message = Actions.PostponeReaction(ns.ctx, callout.reactionId)
		MainWindow.SetStatus(message)
		MainWindow.Refresh()
	end)
	callout:Hide()
	section.callout = callout

	-- The list column.
	local scroll = CreateFrame("ScrollFrame", Widgets.NextName("JournalScroll"), f, "UIPanelScrollFrameTemplate")
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(100, 100)
	scroll:SetScrollChild(child)
	section.scroll, section.child = scroll, child

	section.older = Widgets.Button(f, "Older >", 76, 22, "ghost")
	section.older:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", LIST_W, 0)
	section.pageLabel = Widgets.Label(f, "GameFontHighlightSmall", false, "muted")
	section.pageLabel:SetJustifyH("CENTER")
	section.pageLabel:SetWidth(90)
	section.pageLabel:SetPoint("RIGHT", section.older, "LEFT", -4, 0)
	section.newer = Widgets.Button(f, "< Newer", 76, 22, "ghost")
	section.newer:SetPoint("RIGHT", section.pageLabel, "LEFT", -4, 0)
	section.newer:SetScript("OnClick", function()
		section.page = section.page - 1
		section.scroll:SetVerticalScroll(0)
		MainWindow.Refresh()
	end)
	section.older:SetScript("OnClick", function()
		section.page = section.page + 1
		section.scroll:SetVerticalScroll(0)
		MainWindow.Refresh()
	end)

	section.empty = Widgets.Label(f, "GameFontHighlight", true, "muted")
	section.empty:SetJustifyH("CENTER")
	section.empty:SetWidth(LIST_W - 60)
	section.empty:SetText(JournalView.EMPTY_TEXT)

	buildSide(section, f)

	local function getRow(index)
		local row = section.rows[index]
		if row then
			return row
		end
		row = Widgets.Card(child)
		row.date = Widgets.DateBlock(row)
		row.date:SetPoint("TOPLEFT", PAD - 4, -PAD)
		if row.date.EnableMouse then row.date:EnableMouse(true) end
		Widgets.Tooltip(row.date, "Written")
		row.title = Widgets.Label(row, "GameFontHighlightLarge", true, "body")
		row.meta = Widgets.Label(row, "GameFontHighlightSmall", true, "muted")
		row.body = Widgets.Label(row, "GameFontHighlight", true, "body")
		row.chips = {}
		for i = 1, MAX_CHIPS do
			row.chips[i] = Widgets.Chip(row, "")
			row.chips[i]:Hide()
		end
		row.vis = Widgets.VisibilityButton(row, function(level)
			local _, message = Actions.SetEntryVisibility(ns.ctx, row.entryId, level)
			MainWindow.SetStatus(message)
			MainWindow.Refresh()
		end)
		if section.decorateRow then
			section.decorateRow(row)
		end
		section.rows[index] = row
		return row
	end

	-- Lays out one card for entry at vertical offset y; returns its height plus the gap.
	local function layoutRow(row, entry, y, width, char)
		row.entryId = entry.id
		row.entry = entry
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
		row:SetWidth(width)
		row.date:SetDate(entry.createdAt)
		row.date.tooltipText = JournalView.MetaText(entry, Widgets.FormatDate)

		local textWidth = width - TEXT_X - PAD
		local chipsWidth = placeChips(row.chips, JournalView.Chips(entry), row, PAD, -PAD)
		local headWidth = textWidth - chipsWidth
		local title, body = JournalView.TitleAndBody(entry)
		if body and entry.kind == "story" and char then
			-- Story drafts show their development's current status (display only).
			body = ns.Narrative.DisplayText(char, entry)
		end

		local cursor = PAD
		if title then
			row.title:Show()
			row.title:SetWidth(headWidth)
			row.title:SetText(title)
			row.title:ClearAllPoints()
			row.title:SetPoint("TOPLEFT", TEXT_X, -cursor)
			cursor = cursor + math.max(textHeight(row.title, 18), chipsWidth > 0 and Widgets.CHIP_HEIGHT or 0) + 4
		else
			row.title:Hide()
		end
		row.meta:SetWidth(title and textWidth or headWidth)
		row.meta:SetText(JournalView.CardMeta(char, entry))
		row.meta:ClearAllPoints()
		row.meta:SetPoint("TOPLEFT", TEXT_X, -cursor)
		cursor = cursor + math.max(textHeight(row.meta, 14), (not title and chipsWidth > 0) and Widgets.CHIP_HEIGHT or 0)
		if body then
			row.body:Show()
			row.body:SetWidth(textWidth)
			row.body:SetText(body)
			row.body:ClearAllPoints()
			row.body:SetPoint("TOPLEFT", TEXT_X, -(cursor + 8))
			cursor = cursor + 8 + textHeight(row.body, 14)
		else
			row.body:Hide()
		end

		-- Visibility on the left, the entry's actions on the right: inside the card.
		cursor = cursor + 10
		row.vis:ClearAllPoints()
		row.vis:SetPoint("TOPLEFT", TEXT_X, -cursor)
		row.vis:SetLevel(entry.visibility)
		if section.updateRowActions then
			section.updateRowActions(row, entry, cursor)
		end
		local height = math.max(cursor + 20 + PAD, PAD + 46 + PAD)
		row:SetHeight(height)
		row:Show()
		return height + Widgets.ENTRY.gap + 4
	end

	function section:ApplyTheme(theme)
		self.theme = theme
	end

	-- The callout for the first pending reaction; returns its height (0 when hidden).
	function section:RenderCallout(char, now)
		local pending = JournalView.PendingReactions(char, now)
		local presentation
		for _, r in ipairs(pending) do
			presentation = ns.Reactions.Present(char, r)
			if presentation then break end
		end
		self.callout:SetShown(presentation ~= nil)
		if not presentation then
			self.callout.reactionId = nil
			return 0
		end
		local index = 1
		for i, r in ipairs(pending) do
			if r == presentation.reaction then index = i end
		end
		self.callout.reactionId = presentation.reaction.id
		self.callout:SetTitle(string.format("A moment awaits%s%d of %d", SEP, index, #pending))
		self.callout.question:SetText(presentation.question or "")
		local height = math.max(64, 30 + textHeight(self.callout.question, 18) + 14)
		self.callout:SetHeight(height)
		return height
	end

	function section:RenderList(view)
		local char = view.char
		local now = view.ctx and view.ctx.now and view.ctx.now() or nil
		self.subline:SetText(JournalView.Subline(char, now))
		self.filters:Select(self.filter)

		local calloutHeight = self:RenderCallout(char, now)
		local top = CALLOUT_TOP + (calloutHeight > 0 and (calloutHeight + BLOCK_GAP) or 0)

		local total = char and #char.journal or 0
		local entries = char and JournalView.Filter(char, self.filter, self.query) or {}
		local pages
		self.page, pages = JournalView.ClampPage(self.page, #entries)
		self.pageLabel:SetText(string.format("Page %d of %d", self.page, pages))
		self.newer:SetEnabled(self.page > 1)
		self.older:SetEnabled(self.page < pages)
		local paged = pages > 1
		self.newer:SetShown(paged)
		self.older:SetShown(paged)
		self.pageLabel:SetShown(paged)

		self.scroll:ClearAllPoints()
		self.scroll:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, -top)
		self.scroll:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMLEFT", LIST_W - SCROLLBAR, paged and PAGER_H or 0)
		self.scroll:Show()

		self.empty:SetShown(#entries == 0)
		self.empty:SetText(total == 0 and JournalView.EMPTY_TEXT or JournalView.NO_MATCH_TEXT)
		self.empty:ClearAllPoints()
		self.empty:SetPoint("TOP", self.frame, "TOPLEFT", LIST_W / 2, -(top + 60))

		local width = LIST_W - SCROLLBAR
		self.child:SetWidth(width)
		local first = (self.page - 1) * JournalView.PAGE_SIZE + 1
		local y, shown = 0, 0
		for i = first, math.min(#entries, first + JournalView.PAGE_SIZE - 1) do
			shown = shown + 1
			y = y + layoutRow(getRow(shown), entries[i], y, width, char)
		end
		for i = shown + 1, #self.rows do
			self.rows[i]:Hide()
		end
		self.child:SetHeight(math.max(y, 1))
		self.visibleCount = shown

		-- Right column.
		local sideX = LIST_W + COL_GAP
		local goals, places = self.goals, self.places
		local goalsHeight = renderGoals(goals, char)
		goals:ClearAllPoints()
		goals:SetPoint("TOPLEFT", self.frame, "TOPLEFT", sideX, -top)
		goals:SetHeight(goalsHeight)
		goals:Show()
		local placesTop = top + goalsHeight + BLOCK_GAP
		local placesHeight = CONTENT_H - placesTop
		places:ClearAllPoints()
		places:SetPoint("TOPLEFT", self.frame, "TOPLEFT", sideX, -placesTop)
		places:SetHeight(placesHeight)
		renderPlaces(places, char, placesHeight - PANEL_TOP - Widgets.PANEL_PAD)
		places:SetShown(placesHeight >= PANEL_TOP + Widgets.PANEL_PAD + 30)
	end

	function section:Refresh(view)
		self.theme = view.theme
		if self.editor:IsShown() then
			self:ThemeEditor(view.theme)
			return
		end
		self:RenderList(view)
	end

	section.getRow = getRow
	JournalView.AttachEditing(section)
	JournalView.section = section
	return section
end

--- Editing ---------------------------------------------------------------------

local INSET = 8
local EDIT_BUTTON_WIDTH = 50
local DELETE_BUTTON_WIDTH = 58
local APPROVE_BUTTON_WIDTH = 64
local MARK_BUTTON_WIDTH = 64

local function preview(text)
	text = text or ""
	if #text > 120 then
		return text:sub(1, 120) .. "..."
	end
	return text
end

--- Adds the New entry button, row Edit/Delete/Approve/Defining buttons and the entry editor.
function JournalView.AttachEditing(section)
	local f = section.frame

	section.newButton = Widgets.Button(section.toolbar, "+ New entry", 112, TOOLBAR_H, "primary")
	section.newButton:SetPoint("LEFT", 0, 0)
	section.newButton:SetScript("OnClick", function() section:OpenEditor(nil) end)
	section.search:SetPoint("LEFT", section.newButton, "RIGHT", 10, 0)

	function section.decorateRow(row)
		row.delete = Widgets.Button(row, "Delete", DELETE_BUTTON_WIDTH, 20, "danger")
		row.delete:SetScript("OnClick", function() section:ConfirmDelete(row.entry) end)
		row.edit = Widgets.Button(row, "Edit", EDIT_BUTTON_WIDTH, 20)
		row.edit:SetScript("OnClick", function() section:OpenEditor(row.entry) end)
		-- Story drafts are Dawnward's words until the player approves them.
		row.approve = Widgets.Button(row, "Approve", APPROVE_BUTTON_WIDTH, 20, "primary")
		row.approve:SetScript("OnClick", function()
			local _, message = Actions.ApproveEntry(ns.ctx, row.entryId)
			MainWindow.SetStatus(message)
			MainWindow.Refresh()
		end)
		Widgets.Tooltip(row.approve, "Approve draft",
			"Accept this draft as part of your character's story. It stays private until you change its visibility.")
		-- Any entry can be marked as a defining moment.
		row.mark = Widgets.Button(row, "Defining", MARK_BUTTON_WIDTH, 20, "ghost")
		row.mark:SetScript("OnClick", function()
			local _, message = Actions.SetEntryImportant(ns.ctx, row.entryId, not (row.entry and row.entry.important))
			MainWindow.SetStatus(message)
			MainWindow.Refresh()
		end)
		Widgets.Tooltip(row.mark, "Defining moment",
			"Mark or unmark this entry as an important memory. Approved, public defining moments can appear in "
				.. "Total RP 3 if you turned biography sync on.")
		row.actions = { row.delete, row.edit, row.approve, row.mark } -- right to left
	end

	-- Only entries the player wrote (or story entries) can be edited or deleted.
	-- The shown actions line up from the card's right edge, at offset y.
	function section.updateRowActions(row, entry, y)
		local written = entry.kind == "note" or entry.kind == "story"
		row.edit:SetShown(written)
		row.delete:SetShown(written)
		row.approve:SetShown(Journal.NeedsApproval(entry))
		row.mark:SetSelected(entry.important)
		local x = PAD
		for _, button in ipairs(row.actions) do
			if button:IsShown() then
				button:ClearAllPoints()
				button:SetPoint("TOPRIGHT", row, "TOPRIGHT", -x, -(y or 0))
				x = x + button:GetWidth() + 6
			end
		end
	end

	-- Editor panel (replaces the dashboard while open).
	local editor = CreateFrame("Frame", nil, f)
	editor:SetAllPoints(f)
	editor:Hide()
	section.editor = editor

	editor.heading = Widgets.Label(editor, "GameFontNormalLarge", false, "title")
	editor.heading:SetPoint("TOPLEFT", INSET, -10)

	editor.titleLabel = Widgets.Label(editor, "GameFontHighlightSmall", false, "muted")
	editor.titleLabel:SetPoint("TOPLEFT", INSET, -40)
	editor.titleLabel:SetText("Title (optional)")
	editor.title = Widgets.EditLine(editor, 101)
	editor.title:SetPoint("TOPLEFT", INSET + 6, -56)
	editor.title:SetPoint("TOPRIGHT", -INSET, -56)

	editor.textLabel = Widgets.Label(editor, "GameFontHighlightSmall", false, "muted")
	editor.textLabel:SetPoint("TOPLEFT", INSET, -100) -- below the title's error line
	editor.textLabel:SetText("Entry")
	editor.area = Widgets.TextArea(editor, 2001, MainWindow.ContentWidth() - 2 * INSET)
	editor.area.frame:SetPoint("TOPLEFT", INSET, -116)
	editor.area.frame:SetPoint("BOTTOMRIGHT", -INSET, 62) -- room for an error line above the buttons
	Widgets.FieldError(editor.title, 560)
	Widgets.FieldError(editor.area.edit, 560)
	-- Keyboard: Tab moves between title and text, Enter on the title moves
	-- to the text (which keeps Enter for new lines), Escape cancels.
	editor.chain = Widgets.FocusChain({
		onEscape = function(dirty) editor.chain.ConfirmDiscard(dirty, function() section:CloseEditor() end) end,
	})

	editor.vis = Widgets.VisibilityButton(editor, function(level, button) button:SetLevel(level) end)
	editor.vis:SetPoint("BOTTOMLEFT", INSET, 12)
	editor.cancel = Widgets.Button(editor, "Cancel", 90, 22)
	editor.cancel:SetPoint("BOTTOMRIGHT", -INSET, 12)
	editor.save = Widgets.Button(editor, "Save", 90, 22, "primary")
	editor.save:SetPoint("RIGHT", editor.cancel, "LEFT", -6, 0)

	-- The dashboard's parts, hidden while the editor is open. Showing them
	-- again is RenderList's job (the callout, pager and empty state depend on data).
	local dashboard = { section.subline, section.toolbar, section.callout, section.scroll, section.newer,
		section.older, section.pageLabel, section.empty, section.goals, section.places }
	local function listParts(shown)
		if shown then
			section.subline:Show()
			section.toolbar:Show()
			return
		end
		for _, part in ipairs(dashboard) do
			part:Hide()
		end
	end

	-- The editor's controls paint themselves (UI/Style.lua).
	function section.ThemeEditor() end

	--- entry nil = new entry.
	function section:OpenEditor(entry)
		editor.entryId = entry and entry.id or nil
		editor.heading:SetText(entry and "Edit entry" or "New entry")
		editor.title:SetText(entry and entry.title or "")
		editor.area.edit:SetText(entry and entry.text or "")
		editor.vis:SetLevel(entry and entry.visibility or "private")
		section.search:ClearFocus()
		listParts(false)
		editor:Show()
		if self.theme then
			self:ThemeEditor(self.theme)
		end
		Widgets.SetFieldError(editor.title, nil)
		Widgets.SetFieldError(editor.area.edit, nil)
		editor.chain.SetFields({ editor.title, editor.area.edit })
		editor.chain.FocusFirst()
		MainWindow.SetStatus(entry and "Editing your entry." or "Write in your character's voice, or your own.")
	end

	function section.CloseEditor()
		editor:Hide()
		editor.title:ClearFocus()
		editor.area.edit:ClearFocus()
		listParts(true)
		MainWindow.Refresh()
	end

	function section:SaveEditor()
		local title = editor.title:GetText()
		local text = editor.area.edit:GetText()
		local ok, message
		if editor.entryId then
			ok, message = Actions.UpdateNote(ns.ctx, editor.entryId, title, text, editor.vis.level)
		else
			ok, message = Actions.AddNote(ns.ctx, title, text, editor.vis.level)
			if ok then
				self.page = 1
			end
		end
		if ok then
			self:CloseEditor()
			MainWindow.SetStatus(message)
		else
			-- Journal refusals concern the entry text: shown beneath it, typed text kept.
			Widgets.SetFieldError(editor.area.edit, message)
			editor.area.edit:SetFocus()
		end
	end

	function section.ConfirmDelete(_, entry)
		if not entry or (entry.kind ~= "note" and entry.kind ~= "story") then
			return
		end
		local id = entry.id
		Widgets.Confirm("Delete this journal entry?\n\n\"" .. preview(entry.title or entry.text) .. "\"\n\n"
			.. "This cannot be undone (a backup export keeps a copy).", "Delete", function()
			local _, message = Actions.RemoveNote(ns.ctx, id)
			MainWindow.SetStatus(message)
			MainWindow.Refresh()
		end)
	end

	editor.save:SetScript("OnClick", function() section:SaveEditor() end)
	editor.cancel:SetScript("OnClick", function() section:CloseEditor() end)
end

MainWindow.RegisterSection({ id = "journal", label = "Journal", order = 1, icon = "Interface\\Icons\\INV_Misc_Book_09",
	create = create })
