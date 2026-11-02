-- Journal section (v0.8 dashboard, docs/design/mockups/journal-dashboard.png
-- and its source Main.dc.html; audit: docs/design/audit/journal.md).
--
--   subline      real counts: entries, defining moments, when the last was
--                written; directly under the window's title, as in the design
--   toolbar      New entry, a search box (title, text and place) and a filter:
--                All / Defining (important) / Story (story entries) / Events
--                (automatic entries), on a padded, edged track
--   callout      "A moment awaits": the first Story Director reaction still
--                pending, with Answer (opens it in the Story section) and Later
--                (the same postpone as the reaction card). Hidden when none.
--   cards        entries newest first in one scrolling list: date block,
--                title with its status chips, meta line, the story text and a
--                footer with the entry's actions, all inside the card. Defining moments use the design's featured
--                card (lighter fill, stronger edge, gold day).
--   right column Active goals (milestones and verified progress) and Recent
--                places (from the places log, with Homeland / Meaningful chips)
--
-- The list is virtual: every matching entry gets a measured height (cached
-- by its content), but only the cards that intersect the visible part of the
-- scroll frame exist, drawn from a small pool. Scrolling lays out only the
-- cards that come into view, so the number of frames stays small however
-- large the journal grows. Every write goes through Core/Actions.lua.
local _, ns = ...
local Widgets, MainWindow, Actions, Journal, Style = ns.Widgets, ns.MainWindow, ns.Actions, ns.Journal, ns.Style

local JournalView = {}
ns.JournalView = JournalView

JournalView.EMPTY_TEXT = "Your journal is empty.\n\nWrite your first entry with New entry, or keep adventuring: "
	.. "level-ups are recorded here automatically."
JournalView.NO_MATCH_TEXT = "No entries match.\n\nTry other words, or choose All to see every entry."
JournalView.SEARCH_DELAY = 0.15
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
local CONTROL = Style.CONTROL

-- Layout in UI units, from the content area's top-left corner. The values
-- are Main.dc.html's; exposed for the layout tests.
local L = {
	contentW = MainWindow.ContentWidth(),   -- 772
	contentH = MainWindow.ContentHeight(),  -- 588
	sideW = 250,            -- right column (aside 250)
	colGap = 20,            -- list to right column
	gutter = 14,            -- the list column's right padding; the scroll bar sits in it
	scrollBarW = 6,
	-- The subline sits right under the window's title (the title box ends 80
	-- below the window top, the content area starts at 96): 16 above.
	sublineTop = -16,
	sublineH = 18,
	toolbarTop = 18,
	toolbarH = 38,          -- the filter track: 30 high items, 3 padding and a 1 px edge
	newW = Widgets.ButtonWidth("New entry", CONTROL.standard, true), -- "+" icon, 16 padding
	searchW = 230,
	toolGap = 10,
	segmentGap = Widgets.SEGMENT.gap,
	trackPad = Widgets.SEGMENT.pad + 1, -- 3 padding + the 1 px edge
	calloutTop = 72,
	blockGap = 16,          -- toolbar, callout and list (the main column's gap)
	calloutPadX = 18,
	calloutPadY = 14,
	disc = 44,
	discGap = 16,
	eyebrowH = 16,
	calloutMinH = 76,
	answerW = 92,
	laterW = 76,
	cardGap = 12,           -- between cards
	padX = 18,              -- inside a card
	padY = 14,
	padYFeatured = 16,
	dateW = 52,
	dateGap = 16,
	lineGap = 6,            -- title, meta and text (gap 6)
	footerGap = 10,         -- text to the footer (gap 6 + margin 4)
	footerH = CONTROL.compact,
	chipGap = 8,
	maxChips = 3,
	chipMaxW = 200,
	actionGap = 8,
	titleLine = 22,         -- Cinzel 18
	metaLine = 17,          -- 14
	readingLine = 20,       -- 16 + 4 spacing
	panelGap = 12,          -- between the right column's panels
	sidePad = 16,           -- the right column's panels: padding 14 / 16
	panelFirst = 6,         -- eyebrow to the first row
	goalGap = 12,
	goalInner = 6,
	placeGap = 10,
	thumbMin = 30,
}
L.listW = L.contentW - L.sideW - L.colGap        -- 502
L.cardW = L.listW - L.gutter                      -- 488
L.textX = L.padX + L.dateW + L.dateGap            -- 86
L.textW = L.cardW - L.textX - L.padX              -- 384
-- Filter items sized to their words (the design's .btn.sm: 12 px padding).
L.segmentWidths = Widgets.SegmentWidths(JournalView.FILTERS, CONTROL.compact, true)
L.segmentsW = (#JournalView.FILTERS - 1) * L.segmentGap
for _, w in ipairs(L.segmentWidths) do L.segmentsW = L.segmentsW + w end
L.trackW = L.segmentsW + 2 * L.trackPad
L.questionX = L.calloutPadX + L.disc + L.discGap  -- 78
L.questionW = L.contentW - L.questionX - L.discGap - L.answerW - 8 - L.laterW - L.calloutPadX
L.sideInner = L.sideW - 2 * L.sidePad
L.panelTop = Widgets.PANEL_PAD + 22               -- a panel's eyebrow takes this much
JournalView.LAYOUT = L

-- Footer actions: the design's small buttons (bold 14 on 30, a 14 px line
-- icon, 12 px padding; tested to fit their labels). Defining is a star
-- toggle as wide as it is high; without line regions it keeps its word.
JournalView.ACTION_WIDTHS = {
	Delete = Widgets.ButtonWidth("Delete", CONTROL.compact, true),
	Edit = Widgets.ButtonWidth("Edit", CONTROL.compact, true),
	Approve = Widgets.ButtonWidth("Approve", CONTROL.compact, true),
	Defining = CONTROL.compact,
	DefiningText = 80,
}
JournalView.ACTION_ICONS = { Delete = "delete", Edit = "edit", Approve = "check", Defining = "star" }

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
-- Tones follow the design: gold for a defining moment, amber for what
-- waits on the player, neutral tags for the rest.
function JournalView.Chips(entry)
	local chips = {}
	if entry.important then
		chips[#chips + 1] = { text = "Defining", tone = "accent" }
	end
	if Journal.NeedsApproval(entry) then
		chips[#chips + 1] = { text = "Waiting for your approval", tone = "waiting" }
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

--- Virtual list maths ----------------------------------------------------------

--- Tops of items { height } stacked with gap; returns the total height. Pure.
function JournalView.Stack(items, gap)
	local y = 0
	for i, item in ipairs(items) do
		item.top = y
		y = y + item.height + (i < #items and gap or 0)
	end
	return y
end

--- The first and last index of items (with top and height) that intersect
-- [offset, offset + viewH]; nil when none. Binary search. Pure.
function JournalView.Window(items, offset, viewH)
	local n = #items
	if n == 0 then return nil end
	local lo, hi = 1, n
	while lo < hi do -- first item whose bottom is below offset
		local mid = math.floor((lo + hi) / 2)
		if items[mid].top + items[mid].height <= offset then lo = mid + 1 else hi = mid end
	end
	local first = lo
	if items[first].top + items[first].height <= offset then return nil end
	local last = first
	while last < n and items[last + 1].top < offset + viewH do
		last = last + 1
	end
	return first, last
end

--- The scroll range: 0 .. max(0, total - viewH), offset clamped into it. Pure.
function JournalView.ClampOffset(offset, total, viewH)
	local max = math.max(0, total - viewH)
	return math.max(0, math.min(max, offset or 0)), max
end

--- Helpers -------------------------------------------------------------------------

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

-- A text link (the design's "All" in Active goals): accent text, brighter
-- on hover, no box. Built on a Button so it keeps clicks and tooltips.
local function textLink(parent, text, width, height)
	local b = Widgets.Button(parent, text, width, height, "ghost")
	b.label:SetJustifyH("RIGHT")
	-- The design's link is regular 14 (a, font-size 14), not a bold button label.
	local meta = Style.UsesBundledFont("meta") and Style.fontObjects[Style.FontFor("meta")]
	if meta then b.label:SetFontObject(meta) end
	b.underline = Style.Solid(b, "ARTWORK")
	b.underline:SetHeight(1)
	b.underline:SetPoint("BOTTOMRIGHT", b.label, "BOTTOMRIGHT", 0, -1)
	b.underline:SetWidth(math.ceil(Style.TextWidth(text, meta and "meta" or "buttonSmall")))
	Style.Register(b, function(link, theme)
		local tones = Style.Tones(theme)
		local color = link.hover and tones.accentBright or theme.accent
		Style.Color(link.bg, theme.surface, 0)
		link.edges:Paint(theme.edge, 0)
		Style.TextColor(link.label, color)
		Style.Color(link.underline, color, 0.8)
	end)
	return b
end

--- The right column ---------------------------------------------------------------

local function buildSide(section, f)
	local inner = L.sideInner
	-- Active goals.
	local goals = Widgets.Panel(f, "Active goals", { padX = L.sidePad })
	goals:SetWidth(L.sideW)
	goals.all = textLink(goals, "All", 36, 20)
	goals.all:SetPoint("TOPRIGHT", -(L.sidePad - Widgets.BUTTON.inset), -Widgets.PANEL_PAD + 1)
	goals.all:SetScript("OnClick", function() openChronicle("goals") end)
	Widgets.Tooltip(goals.all, "All goals", "Open Chronicle > Goals to see, add and edit every goal.")
	goals.empty = Widgets.Label(goals.inner, "GameFontHighlightSmall", true, "muted")
	goals.empty:SetPoint("TOPLEFT", 0, -L.panelFirst)
	goals.empty:SetWidth(inner)
	goals.empty:SetText(JournalView.GOALS_EMPTY)
	goals.rows = {}
	for i = 1, JournalView.MAX_GOALS do
		local row = CreateFrame("Frame", nil, goals.inner)
		row:SetWidth(inner)
		row.title = Widgets.Label(row, "GameFontHighlight", true, "body")
		row.title:SetPoint("TOPLEFT", 0, 0)
		row.title:SetWidth(inner)
		row.bar = Widgets.ProgressBar(row, inner, CONTROL.progress)
		row.caption = Widgets.Label(row, "GameFontHighlightSmall", true, "muted")
		row.caption:SetWidth(inner)
		goals.rows[i] = row
	end
	section.goals = goals

	-- Recent places.
	local places = Widgets.Panel(f, "Recent places", { padX = L.sidePad })
	places:SetWidth(L.sideW)
	places.empty = Widgets.Label(places.inner, "GameFontHighlightSmall", true, "muted")
	places.empty:SetPoint("TOPLEFT", 0, -L.panelFirst)
	places.empty:SetWidth(inner)
	places.empty:SetText(JournalView.PLACES_EMPTY)
	places.rows = {}
	for i = 1, JournalView.MAX_PLACES do
		local row = CreateFrame("Frame", nil, places.inner)
		row:SetWidth(inner)
		row.divider = Widgets.Divider(row)
		row.divider:SetPoint("TOPLEFT", 0, 0)
		row.divider:SetPoint("TOPRIGHT", 0, 0)
		row.name = Widgets.Label(row, "GameFontHighlight", false, "body")
		row.name:SetWidth(inner)
		row.chips = { Widgets.Chip(row, "Homeland", "accent", CONTROL.chipSmall),
			Widgets.Chip(row, "Meaningful", "accent", CONTROL.chipSmall) }
		row.detail = Widgets.Label(row, "GameFontHighlightSmall", true, "muted")
		row.detail:SetWidth(inner)
		places.rows[i] = row
	end
	section.places = places
end

-- Lays the goal rows out; returns the panel's height.
local function renderGoals(goals, char)
	local list = char and ns.Goals.Active(char) or {}
	goals.empty:SetShown(#list == 0)
	local y = L.panelFirst
	for i, row in ipairs(goals.rows) do
		local goal = list[i]
		row:SetShown(goal ~= nil)
		if goal then
			row.goalId = goal.id
			row.title:SetText(goal.title)
			local fraction, caption = JournalView.GoalProgress(char, goal)
			local th = textHeight(row.title, 18)
			row.bar:ClearAllPoints()
			row.bar:SetPoint("TOPLEFT", 0, -(th + L.goalInner))
			row.bar:SetValue(fraction)
			local captionTop = th + L.goalInner + CONTROL.progress + L.goalInner
			row.caption:ClearAllPoints()
			row.caption:SetPoint("TOPLEFT", 0, -captionTop)
			row.caption:SetText(caption)
			local h = captionTop + textHeight(row.caption, 16)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 0, -y)
			row:SetHeight(h)
			y = y + h + L.goalGap
		end
	end
	if #list == 0 then
		y = y + textHeight(goals.empty, 32) + L.goalGap
	end
	goals.shown = math.min(#list, #goals.rows)
	return L.panelTop + y - L.goalGap + Widgets.PANEL_PAD
end

-- Lays out as many place rows as fit in available; returns the height used.
local function renderPlaces(places, char, available)
	local list = char and ns.Places.List(char) or {}
	places.empty:SetShown(#list == 0)
	local y, shown = L.panelFirst, 0
	for i, row in ipairs(places.rows) do
		local entry = list[i]
		local fits = false
		if entry then
			local specs = {}
			if ns.Places.IsHomeland(char, entry) then specs[#specs + 1] = { text = "Homeland" } end
			if entry.meaningful then specs[#specs + 1] = { text = "Meaningful" } end
			local top = i > 1 and L.placeGap + 1 + L.placeGap or 0
			row.divider:ClearAllPoints()
			row.divider:SetPoint("TOPLEFT", 0, -L.placeGap)
			row.divider:SetPoint("TOPRIGHT", 0, -L.placeGap)
			row.divider:SetShown(i > 1)
			row.name:ClearAllPoints()
			row.name:SetPoint("TOPLEFT", 0, -top)
			row.name:SetText(entry.subzone or entry.zone)
			local h = top + 18 + 2
			for c, chip in ipairs(row.chips) do
				local spec = specs[c]
				chip:SetShown(spec ~= nil)
				if spec then
					chip:SetChip(spec.text, "accent")
					chip:ClearAllPoints()
					if c == 1 then
						chip:SetPoint("TOPLEFT", 0, -h)
					else
						chip:SetPoint("LEFT", row.chips[c - 1], "RIGHT", 6, 0)
					end
				end
			end
			if #specs > 0 then h = h + CONTROL.chipSmall + 4 end
			row.detail:ClearAllPoints()
			row.detail:SetPoint("TOPLEFT", 0, -h)
			local detail = JournalView.PlaceDetail(entry)
			row.detail:SetText(detail)
			h = h + textHeight(row.detail, 16)
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
	if #list == 0 then
		y = y + textHeight(places.empty, 32)
	end
	places.shown = shown
	return y
end

--- Cards -----------------------------------------------------------------------------

-- One card's content signature: everything its height depends on.
local function signature(title, meta, body, chips)
	local parts = { title or "", meta, body or "" }
	for _, chip in ipairs(chips) do parts[#parts + 1] = chip.text end
	return table.concat(parts, "\1")
end

--- The section ----------------------------------------------------------------------

local function create(parent)
	local section = { frame = CreateFrame("Frame", nil, parent), rows = {}, filter = "all", query = "", offset = 0,
		items = {}, heights = {}, heightCount = 0, gen = 0, visibleCount = 0, matchCount = 0 }
	local f = section.frame

	-- Subline, right under the window's title.
	section.subline = Widgets.Label(f, "GameFontHighlight", false, "muted")
	section.subline:SetPoint("TOPLEFT", 0, -L.sublineTop)
	section.subline:SetWidth(L.contentW - 60)

	-- Toolbar: New entry (added with the editing parts), search, filter.
	section.toolbar = CreateFrame("Frame", nil, f)
	section.toolbar:SetPoint("TOPLEFT", 0, -L.toolbarTop)
	section.toolbar:SetSize(L.contentW, L.toolbarH)

	-- Typing refreshes once it pauses (JournalView.SEARCH_DELAY), not per key.
	section.search = Widgets.SearchBox(section.toolbar, L.searchW, "Search the journal", function(text)
		if text == section.query then return end
		section.query = text
		section.offset = 0
		section.searchToken = (section.searchToken or 0) + 1
		local token = section.searchToken
		local function refresh()
			if token == section.searchToken then MainWindow.Refresh() end
		end
		if C_Timer and C_Timer.After and JournalView.SEARCH_DELAY > 0 then
			C_Timer.After(JournalView.SEARCH_DELAY, refresh)
		else
			refresh()
		end
	end, CONTROL.input)
	Widgets.Tooltip(section.search, "Search the journal", "Finds entries by title, text or recorded place.")

	-- The filter: the shared segmented control on its framed track (panel
	-- fill, 1 px edge, 3 px padding), each item sized to its word.
	section.filters = Widgets.Segmented(section.toolbar, JournalView.FILTERS, L.segmentsW, CONTROL.compact,
		function(id)
			section.filter, section.offset = id, 0
			MainWindow.Refresh()
		end, { fit = true, framed = true })
	section.filterTrack = section.filters.frame
	section.filterTrack:SetPoint("TOPRIGHT", section.toolbar, "TOPRIGHT", 0, 0)
	section.filters:Select("all")

	-- "A moment awaits".
	local callout = Widgets.Callout(f, "A moment awaits", { padX = L.calloutPadX })
	callout:SetPoint("TOPLEFT", 0, -L.calloutTop)
	callout:SetWidth(L.contentW)
	-- The icon disc: a gold-edged dark disc with the design's sparkle (a line
	-- icon, 22 px; a gold jewel where the client has no line regions).
	callout.discEdge = Style.Disc(callout, "ARTWORK", 1, L.disc)
	callout.discEdge:SetPoint("LEFT", L.calloutPadX, 0)
	callout.disc = Style.Disc(callout, "ARTWORK", 2, L.disc - 2)
	callout.disc:SetPoint("CENTER", callout.discEdge, "CENTER", 0, 0)
	callout.icon = Style.LineIcon(callout, "sparkle", 22, nil, "OVERLAY")
	if callout.icon then
		callout.icon:SetPoint("CENTER", callout.discEdge, "CENTER", 0, 0)
		Style.Register(callout.icon, function(t, theme) t:SetColor(Style.Tones(theme).accentBright) end)
	else
		callout.jewel = Style.Solid(callout, "OVERLAY")
		callout.jewel:SetSize(12, 12)
		callout.jewel:SetPoint("CENTER", callout.discEdge, "CENTER", 0, 0)
		if callout.jewel.SetRotation then callout.jewel:SetRotation(math.pi / 4) end
		Style.Register(callout.jewel, function(t, theme) Style.Color(t, Style.Tones(theme).accentBright) end)
	end
	Style.Register(callout.discEdge, function(t, theme) Style.Color(t, theme.border) end)
	Style.Register(callout.disc, function(t, theme)
		Style.Color(t, Style.Mix(Style.Tones(theme).calloutFill, theme.accent, 0.1))
	end)
	callout.title:ClearAllPoints()
	callout.title:SetPoint("TOPLEFT", L.questionX, -L.calloutPadY)
	callout.title:SetWidth(L.questionW)
	callout.later = Widgets.Button(callout, "Later", L.laterW, CONTROL.standard, "ghost")
	callout.later:SetPoint("RIGHT", -L.calloutPadX, 0)
	Widgets.Tooltip(callout.later, "Later", "Keep it in the Story section for later. You will not be reminded again.")
	callout.answer = Widgets.Button(callout, "Answer", L.answerW, CONTROL.standard, "primary")
	callout.answer:SetPoint("RIGHT", callout.later, "LEFT", -8, 0)
	callout.question = Widgets.Label(callout, "reading", true, "title")
	callout.question:SetPoint("TOPLEFT", L.questionX, -(L.calloutPadY + L.eyebrowH + 2))
	callout.question:SetWidth(L.questionW)
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

	-- The list column: a scroll frame whose child holds the pooled cards at
	-- their place in the whole list.
	local scroll = CreateFrame("ScrollFrame", Widgets.NextName("JournalScroll"), f, "UIPanelScrollFrameTemplate")
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(L.cardW, 1)
	scroll:SetScrollChild(child)
	section.scroll, section.child = scroll, child

	-- The design's slim scroll bar: a 6 px track in the list's gutter and a
	-- proportional thumb; the template's arrow buttons are not shown (the
	-- mouse wheel and dragging the thumb scroll).
	local bar = scroll.ScrollBar -- parentKey in the 1.15.9 template
	if type(bar) ~= "table" then bar = nil end
	if bar and bar.ClearAllPoints then
		bar:ClearAllPoints()
		bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", L.gutter - L.scrollBarW, 0)
		bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", L.gutter - L.scrollBarW, 0)
		bar:SetWidth(L.scrollBarW)
		for _, key in ipairs({ "ScrollUpButton", "ScrollDownButton" }) do
			local arrow = type(bar[key]) == "table" and bar[key] or nil
			if arrow then
				arrow:SetAlpha(0)
				if arrow.EnableMouse then arrow:EnableMouse(false) end
				arrow:SetSize(1, 1)
			end
		end
		bar.track = Style.Solid(bar, "BACKGROUND")
		bar.track:SetAllPoints(bar)
		local thumb = type(bar.ThumbTexture) == "table" and bar.ThumbTexture or nil
		bar.thumb = thumb
		if thumb then
			thumb:SetTexture(nil)
			thumb:SetTexCoord(0, 1, 0, 1)
			thumb:SetSize(L.scrollBarW, 90)
		end
		Style.Register(bar, function(b, theme)
			local tones = Style.Tones(theme)
			Style.Color(b.track, Style.Mix(theme.background, theme.panel, 0.6))
			if b.thumb then Style.Color(b.thumb, tones.edgeStrong) end
		end)
		section.scrollBar = bar
	end

	-- Empty states: a card at the top of the list with the explanation.
	section.emptyCard = Widgets.Card(f)
	section.emptyCard:SetWidth(L.cardW)
	section.empty = Widgets.Label(section.emptyCard, "reading", true, "muted")
	section.empty:SetJustifyH("CENTER")
	section.empty:SetPoint("TOP", 0, -24)
	section.empty:SetWidth(L.cardW - 2 * 40)
	section.empty:SetText(JournalView.EMPTY_TEXT)
	section.emptyCard:Hide()

	buildSide(section, f)

	local function buildCard(parentFrame)
		local row = Widgets.Card(parentFrame)
		row:SetWidth(L.cardW)
		row.date = Widgets.DateBlock(row)
		row.date:SetWidth(L.dateW)
		if row.date.EnableMouse then row.date:EnableMouse(true) end
		Widgets.Tooltip(row.date, "Written")
		row.title = Widgets.Label(row, "GameFontNormalLarge", true, "title")
		row.meta = Widgets.Label(row, "meta", true, "muted")
		row.body = Widgets.Label(row, "reading", true, "reading")
		row.chips = {}
		for i = 1, L.maxChips do
			row.chips[i] = Widgets.Chip(row, "", "accent")
			row.chips[i]:SetMaxWidth(L.chipMaxW)
			row.chips[i]:Hide()
		end
		return row
	end

	local function getRow(index)
		local row = section.rows[index]
		if row then
			return row
		end
		row = buildCard(child)
		if section.decorateRow then
			section.decorateRow(row)
		end
		section.rows[index] = row
		return row
	end

	-- What a card shows for entry: title, body, meta and chips.
	local function cardContent(entry, char)
		local title, body = JournalView.TitleAndBody(entry)
		if body and entry.kind == "story" and char then
			-- Story drafts show their development's current status (display only).
			body = ns.Narrative.DisplayText(char, entry)
		end
		return title, body, JournalView.CardMeta(char, entry), JournalView.Chips(entry)
	end

	-- Lays out one card for item at its place in the list; returns its height.
	-- measuring: lay out the hidden measuring card only (no actions, no show).
	local function layoutRow(row, item, measuring)
		local entry = item.entry
		local featured = entry.important and true or false
		local padY = featured and L.padYFeatured or L.padY
		row.entryId = entry.id
		row.entry = entry
		if row.featured ~= featured then
			row:SetFeatured(featured)
			Widgets.SetTextRole(row.date.day, featured and "accentBright" or "ghostText")
		end
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(item.top or 0))
		row.date:ClearAllPoints()
		row.date:SetPoint("TOPLEFT", L.padX, -(padY + 2))
		row.date:SetDate(entry.createdAt)
		row.date.tooltipText = JournalView.MetaText(entry, Widgets.FormatDate)

		local title, body, meta, chips = item.title, item.body, item.meta, item.chips
		-- Chips from the right edge leftwards, centred on the first line.
		local chipsWidth = 0
		for i, chip in ipairs(row.chips) do
			local spec = chips[i]
			if spec then
				chip:SetChip(spec.text, spec.tone)
				chip:ClearAllPoints()
				chip:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(L.padX + chipsWidth),
					-(padY + math.floor((L.titleLine - CONTROL.chip) / 2)))
				chip:Show()
				chipsWidth = chipsWidth + chip:GetWidth() + L.chipGap
			else
				chip:Hide()
			end
		end
		local headWidth = L.textW - chipsWidth

		local cursor = padY
		if title then
			row.title:Show()
			row.title:SetWidth(headWidth)
			row.title:SetText(title)
			row.title:ClearAllPoints()
			row.title:SetPoint("TOPLEFT", L.textX, -cursor)
			cursor = cursor + math.max(textHeight(row.title, L.titleLine), chipsWidth > 0 and CONTROL.chip or 0)
				+ L.lineGap
		else
			row.title:Hide()
		end
		row.meta:SetWidth(title and L.textW or headWidth)
		row.meta:SetText(meta)
		row.meta:ClearAllPoints()
		row.meta:SetPoint("TOPLEFT", L.textX, -cursor)
		cursor = cursor + math.max(textHeight(row.meta, L.metaLine), (not title and chipsWidth > 0) and CONTROL.chip or 0)
		if body then
			row.body:Show()
			row.body:SetWidth(L.textW)
			row.body:SetText(body)
			row.body:ClearAllPoints()
			row.body:SetPoint("TOPLEFT", L.textX, -(cursor + L.lineGap))
			cursor = cursor + L.lineGap + textHeight(row.body, L.readingLine)
		else
			row.body:Hide()
		end

		-- Footer: the entry's actions, from the right.
		cursor = cursor + L.footerGap
		if not measuring and section.updateRowActions then
			section.updateRowActions(row, entry, cursor)
		end
		local height = math.max(cursor + L.footerH + padY, padY + 46 + padY)
		row:SetHeight(height)
		if not measuring then row:Show() end
		return height
	end
	section.layoutRow = layoutRow

	-- The hidden card used to measure entries that have no cached height.
	local measureCard
	local function measure(item)
		if not measureCard then
			measureCard = buildCard(child)
			measureCard:Hide()
		end
		return layoutRow(measureCard, item, true)
	end

	function section:ApplyTheme(theme)
		self.theme = theme
		-- Font metrics can differ per theme only through fonts; a cheap reset.
		self.heights, self.heightCount = {}, 0
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
		local height = math.max(L.calloutMinH,
			L.calloutPadY + L.eyebrowH + 2 + textHeight(self.callout.question, L.readingLine) + L.calloutPadY)
		self.callout:SetHeight(height)
		return height
	end

	-- Shows the cards that intersect the visible part of the list. Cards that
	-- already show the right entry (same render generation) stay as they are.
	function section:RenderWindow(offset)
		local items = self.items
		local max
		offset, max = JournalView.ClampOffset(offset, self.totalHeight or 0, self.viewH or 0)
		self.offset, self.maxOffset = offset, max
		local first, last = JournalView.Window(items, offset, self.viewH or 0)
		local keep, free = {}, {}
		for _, row in ipairs(self.rows) do
			local i = row.itemIndex
			if row:IsShown() and row.gen == self.gen and first and i and i >= first and i <= last
				and items[i] and items[i].entry == row.entry then
				keep[i] = row
			else
				free[#free + 1] = row
			end
		end
		local ordered, mismatch = {}, false
		if first then
			for i = first, last do
				local row = keep[i]
				if not row then
					row = table.remove(free, 1) or getRow(#self.rows + 1)
					local h = layoutRow(row, items[i])
					if h ~= items[i].height then
						-- The measured height was off (fonts were not ready): correct it.
						items[i].height = h
						self.heights[items[i].sig] = h
						mismatch = true
					end
					row.itemIndex, row.gen = i, self.gen
				end
				ordered[#ordered + 1] = row
			end
		end
		for _, row in ipairs(free) do
			row:Hide()
			row.itemIndex = nil
			ordered[#ordered + 1] = row
		end
		self.rows = ordered
		self.firstIndex = first
		self.visibleCount = first and (last - first + 1) or 0
		if mismatch and not self.correcting then
			-- Restack and lay out again; newly visible cards may correct
			-- their heights too, so repeat a few times at most.
			self.correcting = true
			for _ = 1, 3 do
				if not self:Restack() then break end
			end
			self.correcting = nil
		end
		return mismatch
	end

	-- Recomputes tops and the list's height after a height correction;
	-- returns whether another correction was needed.
	function section:Restack()
		self.totalHeight = JournalView.Stack(self.items, L.cardGap)
		self.child:SetHeight(math.max(self.totalHeight, 1))
		self.gen = self.gen + 1
		self:UpdateThumb()
		return self:RenderWindow(self.offset)
	end

	-- A proportional thumb for the slim scroll bar.
	function section:UpdateThumb()
		local sb = self.scrollBar
		if not (sb and sb.thumb) then return end
		local total, viewH = self.totalHeight or 0, self.viewH or 0
		local h = total > viewH and math.max(L.thumbMin, math.floor(viewH * viewH / total)) or viewH
		sb.thumb:SetSize(L.scrollBarW, math.max(1, h))
		sb:SetShown(total > viewH)
	end

	--- Scrolls the list to offset (clamped) and shows the cards there.
	function section:ScrollTo(offset)
		offset = JournalView.ClampOffset(offset, self.totalHeight or 0, self.viewH or 0)
		self.scroll:SetVerticalScroll(offset)
		self:RenderWindow(offset)
	end

	-- The template moves the list (mouse wheel, thumb): show what comes into view.
	scroll:HookScript("OnVerticalScroll", function(_, offset)
		if offset ~= section.offset then section:RenderWindow(offset) end
	end)

	function section:RenderList(view)
		local char = view.char
		self.char = char
		local now = view.ctx and view.ctx.now and view.ctx.now() or nil
		self.subline:SetText(JournalView.Subline(char, now))
		self.filters:Select(self.filter)

		local calloutHeight = self:RenderCallout(char, now)
		local top = L.calloutTop + (calloutHeight > 0 and (calloutHeight + L.blockGap) or 0)
		self.listTop = top
		self.viewH = L.contentH - top

		local total = char and #char.journal or 0
		local entries = char and JournalView.Filter(char, self.filter, self.query) or {}
		self.matchCount = #entries

		-- Every matching entry: its content and height (measured once per content).
		if self.heightCount > 4 * #entries + 200 then
			self.heights, self.heightCount = {}, 0
		end
		local items = {}
		for i, entry in ipairs(entries) do
			local title, body, meta, chips = cardContent(entry, char)
			local item = { entry = entry, title = title, body = body, meta = meta, chips = chips }
			item.sig = signature(title, meta, body, chips) .. (entry.important and "\2" or "")
			local h = self.heights[item.sig]
			if not h then
				h = measure(item)
				self.heights[item.sig] = h
				self.heightCount = self.heightCount + 1
			end
			item.height = h
			items[i] = item
		end
		self.items = items
		self.totalHeight = JournalView.Stack(items, L.cardGap)
		self.gen = self.gen + 1

		self.scroll:ClearAllPoints()
		self.scroll:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, -top)
		self.scroll:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMLEFT", L.cardW, 0)
		self.scroll:Show()
		self.child:SetWidth(L.cardW)
		self.child:SetHeight(math.max(self.totalHeight, 1))
		self:UpdateThumb()

		self.emptyCard:SetShown(#entries == 0)
		self.empty:SetShown(#entries == 0)
		self.empty:SetText(total == 0 and JournalView.EMPTY_TEXT or JournalView.NO_MATCH_TEXT)
		self.emptyCard:ClearAllPoints()
		self.emptyCard:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, -top)
		self.emptyCard:SetHeight(24 + textHeight(self.empty, 60) + 24)

		local offset = JournalView.ClampOffset(self.offset, self.totalHeight, self.viewH)
		self.scroll:SetVerticalScroll(offset)
		self:RenderWindow(offset)

		-- Right column.
		local sideX = L.listW + L.colGap
		local goals, places = self.goals, self.places
		local goalsHeight = renderGoals(goals, char)
		goals:ClearAllPoints()
		goals:SetPoint("TOPLEFT", self.frame, "TOPLEFT", sideX, -top)
		goals:SetHeight(goalsHeight)
		goals:Show()
		local placesTop = top + goalsHeight + L.panelGap
		local available = L.contentH - placesTop
		places:ClearAllPoints()
		places:SetPoint("TOPLEFT", self.frame, "TOPLEFT", sideX, -placesTop)
		local used = renderPlaces(places, char, available - L.panelTop - Widgets.PANEL_PAD)
		places:SetHeight(math.min(available, L.panelTop + used + Widgets.PANEL_PAD))
		places:SetShown(available >= L.panelTop + Widgets.PANEL_PAD + 30)
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
	local W = JournalView.ACTION_WIDTHS

	section.newButton = Widgets.Button(section.toolbar, "New entry", L.newW, CONTROL.standard, "primary")
	-- The design's "+" icon; a "+" in the label where lines are unavailable.
	if not section.newButton:SetIcon("plus") then section.newButton:SetText("+ New entry") end
	section.newButton:SetPoint("LEFT", 0, 0)
	section.newButton:SetScript("OnClick", function() section:OpenEditor(nil) end)
	section.search:SetPoint("LEFT", section.newButton, "RIGHT", L.toolGap, 0)

	local I = JournalView.ACTION_ICONS
	function section.decorateRow(row)
		row.delete = Widgets.Button(row, "Delete", W.Delete, CONTROL.compact, "danger")
		row.delete:SetIcon(I.Delete)
		row.delete:SetScript("OnClick", function() section:ConfirmDelete(row.entry) end)
		row.edit = Widgets.Button(row, "Edit", W.Edit, CONTROL.compact)
		row.edit:SetIcon(I.Edit)
		row.edit:SetScript("OnClick", function() section:OpenEditor(row.entry) end)
		-- Story drafts are Dawnward's words until the player approves them.
		row.approve = Widgets.Button(row, "Approve", W.Approve, CONTROL.compact, "primary")
		row.approve:SetIcon(I.Approve)
		row.approve:SetScript("OnClick", function()
			local _, message = Actions.ApproveEntry(ns.ctx, row.entryId)
			MainWindow.SetStatus(message)
			MainWindow.Refresh()
		end)
		Widgets.Tooltip(row.approve, "Approve draft",
			"Accept this draft as part of your character's story. Mark it Defining to make it part of your profile.")
		-- Any entry can be marked as a defining moment: a star toggle (gold
		-- while the entry is defining); the word where lines are unavailable.
		row.mark = Widgets.Button(row, "", W.Defining, CONTROL.compact, "ghost")
		if not row.mark:SetIcon(I.Defining) then
			row.mark:SetText("Defining")
			row.mark:SetWidth(W.DefiningText)
		end
		row.mark:SetScript("OnClick", function()
			local _, message = Actions.SetEntryImportant(ns.ctx, row.entryId, not (row.entry and row.entry.important))
			MainWindow.SetStatus(message)
			MainWindow.Refresh()
		end)
		Widgets.Tooltip(row.mark, "Defining moment",
			"Mark or unmark this entry as an important memory. Approved defining moments are part of your profile "
				.. "and appear in Total RP 3 once it is connected.")
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
		if row.mark.icon then
			row.mark.iconRole = entry.important and "accentBright" or nil
			Style.Repaint(row.mark)
		end
		local x = L.padX
		for _, button in ipairs(row.actions) do
			if button:IsShown() then
				button:ClearAllPoints()
				button:SetPoint("TOPRIGHT", row, "TOPRIGHT", -x, -(y or 0))
				x = x + button:GetWidth() + L.actionGap
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

	editor.cancel = Widgets.Button(editor, "Cancel", 90, 22)
	editor.cancel:SetPoint("BOTTOMRIGHT", -INSET, 12)
	editor.save = Widgets.Button(editor, "Save", 90, 22, "primary")
	editor.save:SetPoint("RIGHT", editor.cancel, "LEFT", -6, 0)

	-- The dashboard's parts, hidden while the editor is open. Showing them
	-- again is RenderList's job (the callout and empty state depend on data).
	local dashboard = { section.subline, section.toolbar, section.callout, section.scroll, section.emptyCard,
		section.goals, section.places }
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
			ok, message = Actions.UpdateNote(ns.ctx, editor.entryId, title, text)
		else
			ok, message = Actions.AddNote(ns.ctx, title, text)
			if ok then
				self.offset = 0 -- the new entry is at the top
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

MainWindow.RegisterSection({ id = "journal", label = "Journal", heading = "The road so far", order = 1,
	icon = "Interface\\Icons\\INV_Misc_Book_09",
	create = create })
