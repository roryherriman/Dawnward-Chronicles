-- Chronicle section: the character's narrative records in the window
-- (v0.8, docs/design/mockups/chronicle-memories.png and chronicle-places.png;
-- audit in docs/design/audit/chronicle.md).
--
--   Memories, Arcs, Goals, Stances, People   records as cards in two
--       columns, each card as tall as its content: a status chip and the
--       date on top, the title, a meta line, the text, chips (where it came
--       from, canon status, visibility; the visibility chip is a button that
--       cycles it), a goal's progress from its real milestones or verified
--       objective, and the record's actions in a row at the bottom (Remove on
--       the right). A card that cannot show everything offers Read, the full
--       view of the record with the same actions. New and Edit open a form,
--       so nothing here needs a slash command. A search box filters the
--       current tab.
--   Places                                   list and detail
--       (UI/ChroniclePlaces.lua): mark a place as meaningful, link it as the
--       homeland, or write a memory there
--   Review                                   continuity findings as cards,
--       answered as growth / unreliable / secret / correction / ignore.
--       Examine (top right of a finding) shows the records behind it side
--       by side, with their dates, origin, canon status and visibility;
--       Edit opens a record's own form (Dawnward never corrects it for you);
--       Explain keeps the player's note with an answer. "Answered" lists
--       the answers given, each with Undo answer.
--
-- Every button calls the same core functions as the chat commands, through
-- Actions.WithCharacter (read-only data refused). Cards come from a fixed
-- pool and long lists are paged by what fits, so a refresh creates no frames.
local _, ns = ...
local Widgets, MainWindow, Actions, Forms, Style = ns.Widgets, ns.MainWindow, ns.Actions, ns.Forms, ns.Style

local ChronicleView = {}
ns.ChronicleView = ChronicleView

ChronicleView.TABS = {
	{ id = "memories", label = "Memories", module = "Memories", new = "New memory", noun = { "memory", "memories" },
		search = "Search memories", width = 112 },
	{ id = "arcs", label = "Arcs", module = "Arcs", new = "New arc", noun = { "arc", "arcs" },
		search = "Search arcs", width = 74 },
	{ id = "goals", label = "Goals", module = "Goals", new = "New goal", noun = { "goal", "goals" },
		search = "Search goals", width = 78 },
	{ id = "identity", label = "Stances", module = "Identity", new = "New stance", noun = { "stance", "stances" },
		search = "Search stances", width = 92 },
	{ id = "people", label = "People", module = "People", new = "New person", noun = { "person", "people" },
		search = "Search people", width = 86 },
	{ id = "places", label = "Places", width = 86 },
	{ id = "review", label = "Review", noun = { "finding", "findings" }, search = "Search findings", width = 86 },
}
ChronicleView.REVIEW_CHOICES = { "growth", "unreliable", "secret", "correction", "ignore" }
-- How each answer reads on its button, and what it means (tooltip).
ChronicleView.REVIEW_LABELS = { growth = "Growth", unreliable = "Unreliable", secret = "Secret",
	correction = "Correct it", ignore = "Ignore" }
ChronicleView.REVIEW_HELP = {
	growth = "Your character changed: both records stay true for their time.",
	unreliable = "Your character believes something that is not so.",
	secret = "Deliberate: it stays, and its private side stays hidden.",
	correction = "A mistake you will fix yourself. Nothing is changed for you.",
	ignore = "Not a problem. The finding is set aside.",
	explained = "Your own explanation, kept with the answer.",
}
-- Answers as they read on an answered card (and in the Explain form).
ChronicleView.ANSWER_LABELS = { growth = "Growth", unreliable = "Unreliable", secret = "Secret",
	correction = "Correction", ignore = "Ignored", explained = "Explained" }
ChronicleView.EXAMINE_HELP = "See the records behind this finding side by side, with their dates and where they came "
	.. "from, and edit either one yourself."
ChronicleView.UNDO_HELP = "Takes this answer back. The finding returns if the records still disagree, and anything "
	.. "the answer changed is put back, except that nothing becomes Public again: a hidden side that was Public "
	.. "comes back as Private."

-- Layout in section units (the content area is 772 x 588, the mockup's main
-- column; ChronicleMemories.dc.html). Tabs on top (a 34 px segmented row on
-- a 3 px padded track), a toolbar (New, search, count, pager) below them,
-- then the cards in two columns.
--
-- Cards are sized to their content (v0.8): a short memory is a short card,
-- a long one grows up to maxTextLines of text and offers Read, which shows
-- the whole record. Each card goes to the shorter column, so no card waits
-- for a taller neighbour, and a page holds as many cards as fit (at most
-- `pool`, the frames that exist). All sizes are computed by pure functions
-- (CardLayout, Paginate) from the bundled fonts' real advance widths, so a
-- refresh creates no frames and tests can check nothing overlaps.
ChronicleView.LAYOUT = {
	inset = 0, width = 772, height = 588,
	tabHeight = 40, tabGap = 4, tabPad = 3, tabTextPad = 12,
	toolbarTop = 54, toolbarHeight = 36, searchWidth = 240, newWidth = 148,
	gridTop = 102, cols = 2, colGap = 12, rowGap = 12, pool = 8,
	cardWidth = 380, cardPad = 16, padY = 14, gap = 8, dateWidth = 96,
	chipRow = 24, chipGap = 6, chips = 4,
	titleHeight = 22, metaLine = 18, maxMetaLines = 2, textLine = 20, maxTextLines = 6, progressHeight = 6,
	dividerGap = 10, buttons = 6, buttonHeight = 30, buttonGap = 6, buttonPad = 12, buttonPadTight = 8,
	minButton = 44,
	-- The full view of one record (Read).
	detailPad = 20, detailTitleLines = 3, detailTitleLine = 24, detailMetaLines = 3,
}
ChronicleView.LAYOUT.gridHeight = ChronicleView.LAYOUT.height - ChronicleView.LAYOUT.gridTop
ChronicleView.ROWS = ChronicleView.LAYOUT.pool

-- The Examine button at a finding card's top right (where a record's date
-- sits): a compact button, the top row grows to its height.
ChronicleView.EXAMINE_RECT = { w = 80, h = 30 }

-- Estimates err on the side of one line more than the client draws (kerning
-- and rounding): the estimated width of a line is this share of the real one.
ChronicleView.WRAP_SAFETY = 0.96

local wrapCache, wrapCount = {}, 0

--- Lines text takes when wrapped to width in a Dawnward font style
-- ("reading", "meta", "title", ...), from the bundled fonts' advance
-- widths; 0 for no text. Explicit line breaks count. Pure (cached).
function ChronicleView.WrapLines(text, width, style)
	if type(text) ~= "string" or not text:find("%S") then return 0 end
	local key = style .. "\1" .. width .. "\1" .. text
	local cached = wrapCache[key]
	if cached then return cached end
	local limit = width * ChronicleView.WRAP_SAFETY
	local space = Style.TextWidth(" ", style)
	local lines = 0
	for para in (text .. "\n"):gmatch("(.-)\n") do
		local n, x = 1, 0
		for word in para:gmatch("%S+") do
			local w = Style.TextWidth(word, style)
			local need = x > 0 and (x + space + w) or w
			if need <= limit then
				x = need
			else
				if x > 0 then n = n + 1 end
				while w > limit do
					n = n + 1
					w = w - limit
				end
				x = w
			end
		end
		lines = lines + n
	end
	if wrapCount > 2000 then wrapCache, wrapCount = {}, 0 end
	wrapCache[key], wrapCount = lines, wrapCount + 1
	return lines
end

--- Width of a card button labelled label, with pad on each side. Pure.
function ChronicleView.ButtonWidth(label, pad, L)
	L = L or ChronicleView.LAYOUT
	return math.max(L.minButton, math.ceil(ns.Style.TextWidth(label, "buttonSmall")) + 2 * (pad or L.buttonPad))
end

--- Places a card's buttons in width: left = { { id, label } } from the left,
-- right = { id, label } or nil alone at the right edge (Remove). One row
-- when it fits (with the usual padding, else a tighter one); otherwise the
-- buttons wrap to more rows. Returns { items = { { x, y, w, id, label } },
-- rows, height }, positions relative to the buttons' top-left. Pure.
function ChronicleView.ButtonRows(left, right, width, L)
	L = L or ChronicleView.LAYOUT
	local all = {}
	for _, e in ipairs(left or {}) do all[#all + 1] = e end
	if right then all[#all + 1] = right end
	if #all == 0 then return { items = {}, rows = 0, height = 0 } end
	local function widths(pad)
		local out, total = {}, 0
		for i, e in ipairs(all) do
			out[i] = ChronicleView.ButtonWidth(e[2], pad, L)
			total = total + out[i]
		end
		return out, total + L.buttonGap * (#all - 1)
	end
	local items = {}
	for _, pad in ipairs({ L.buttonPad, L.buttonPadTight }) do
		local w, total = widths(pad)
		if total <= width then
			local x = 0
			for i, e in ipairs(all) do
				local bx = (right and i == #all) and (width - w[i]) or x
				items[i] = { x = bx, y = 0, w = w[i], id = e[1], label = e[2] }
				x = x + w[i] + L.buttonGap
			end
			return { items = items, rows = 1, height = L.buttonHeight }
		end
	end
	-- Wrap: left to right, a new row when the next one would not fit.
	local w = widths(L.buttonPad)
	local x, row = 0, 0
	for i, e in ipairs(all) do
		local bw = math.min(w[i], width)
		if x > 0 and x + bw > width then
			row, x = row + 1, 0
		end
		local bx = x
		if right and i == #all then bx = math.max(x, width - bw) end
		items[i] = { x = bx, y = row * (L.buttonHeight + L.buttonGap), w = bw, id = e[1], label = e[2] }
		x = bx + bw + L.buttonGap
	end
	return { items = items, rows = row + 1, height = (row + 1) * L.buttonHeight + row * L.buttonGap }
end

--- Width of a chip showing text (a little over the estimate, so the
-- client's own width always fits in it). Pure.
function ChronicleView.ChipWidth(text)
	return math.ceil(ns.Style.TextWidth(text, "small") * 1.04) + 2 * ns.Widgets.CHIP_PAD + 2
end

--- Width of the visibility chip (a button) for a level. Pure.
function ChronicleView.VisibilityWidth(level)
	local label = ns.Themes.VISIBILITY_LABELS[level] or level or "Private"
	return math.ceil(ns.Style.TextWidth(label, "buttonSmall")) + 26
end

--- Places chips ({ { text, tone } }) and then the visibility chip (vis, a
-- level, or nil) in rows of width. Returns { items = { { x, y, w } }, vis =
-- { x, y, w } or nil, rows, height }. Pure.
function ChronicleView.ChipRows(chips, vis, width, L)
	L = L or ChronicleView.LAYOUT
	local out = { items = {} }
	local x, row = 0, 0
	local function put(w)
		w = math.min(w, width)
		if x > 0 and x + w > width then row, x = row + 1, 0 end
		local at = { x = x, y = row * (L.chipRow + L.chipGap), w = w }
		x = x + w + L.chipGap
		return at
	end
	for i, c in ipairs(chips or {}) do
		if i > L.chips then break end
		out.items[i] = put(ChronicleView.ChipWidth(c[1]))
	end
	if vis then out.vis = put(ChronicleView.VisibilityWidth(vis)) end
	local any = #out.items > 0 or out.vis ~= nil
	out.rows = any and row + 1 or 0
	out.height = any and (out.rows * L.chipRow + row * L.chipGap) or 0
	return out
end

--- Rectangles of one card's parts, relative to its top-left corner (y grows
-- downwards), and its height. content is CardContent's result, plus
-- content.vis (the record's visibility, for its chip) and content.examine
-- (a finding: the Examine button in the top row). actions(read) returns the
-- card's buttons (left, right; see ChronicleView.Actions); read is true when
-- the card cannot show everything. Pure.
function ChronicleView.CardLayout(content, actions, L)
	L = L or ChronicleView.LAYOUT
	content = content or {}
	local pad, inner = L.cardPad, L.cardWidth - 2 * L.cardPad
	local r = { width = L.cardWidth }
	local y = L.padY
	local er = ChronicleView.EXAMINE_RECT
	local top = content.examine and er.h or L.chipRow
	local reserve = content.examine and (er.w + 8) or (L.dateWidth + 8)
	r.chip = { x = pad, y = y + (top - L.chipRow) / 2, w = inner - reserve, h = L.chipRow }
	if content.examine then
		r.examine = { x = pad + inner - er.w, y = y, w = er.w, h = er.h }
	else
		r.date = { x = pad + inner - L.dateWidth, y = y + (top - 16) / 2, w = L.dateWidth, h = 16 }
	end
	y = y + top + L.gap
	local cut = false
	if content.title then
		r.title = { x = pad, y = y, w = inner, h = L.titleHeight }
		cut = ns.Style.TextWidth(content.title, "title") > inner * ChronicleView.WRAP_SAFETY
		y = y + L.titleHeight + L.gap
	end
	if content.meta then
		local total = math.max(1, ChronicleView.WrapLines(content.meta, inner, "meta"))
		local lines = math.min(total, L.maxMetaLines)
		cut = cut or total > lines
		r.meta = { x = pad, y = y, w = inner, h = lines * L.metaLine, lines = lines }
		y = y + r.meta.h + L.gap
	end
	local total = ChronicleView.WrapLines(content.text, inner, "reading")
	if total > 0 then
		local lines = math.min(total, L.maxTextLines)
		cut = cut or total > lines
		r.text = { x = pad, y = y, w = inner, h = lines * L.textLine, lines = lines, total = total }
		y = y + r.text.h + L.gap
	end
	if content.progress then
		r.progress = { x = pad, y = y, w = inner, h = L.progressHeight }
		y = y + L.progressHeight + L.gap
	end
	local chips = ChronicleView.ChipRows(content.chips, content.vis, inner, L)
	if chips.rows > 0 then
		r.chips = { x = pad, y = y, w = inner, h = chips.height, items = chips.items, vis = chips.vis }
		y = y + chips.height + L.gap
	end
	r.truncated = cut
	local left, right
	if actions then left, right = actions(cut) end
	local buttons = ChronicleView.ButtonRows(left, right, inner, L)
	if buttons.rows > 0 then
		r.divider = { x = pad, y = y, w = inner, h = 1 }
		y = y + 1 + L.dividerGap
		r.buttons = { x = pad, y = y, w = inner, h = buttons.height, items = buttons.items, rows = buttons.rows }
		y = y + buttons.height + L.padY
	else
		y = y - L.gap + L.padY
	end
	r.height = math.min(y, L.gridHeight)
	return r
end

--- Splits cards of the given heights into pages: each card goes to the
-- shorter column of the page (the left one on a tie), and a page ends when
-- the next card no longer fits under it, or when `pool` cards are on it.
-- Every page holds at least one card. Returns pages = { { { index, x, y, h,
-- col } } } (positions in the grid, from its top-left), at least one
-- (empty) page. Pure.
function ChronicleView.Paginate(heights, L)
	L = L or ChronicleView.LAYOUT
	local pages, i, n = {}, 1, #heights
	repeat
		local page, colY = {}, {}
		for c = 1, L.cols do colY[c] = 0 end
		while i <= n and #page < L.pool do
			local col = 1
			for c = 2, L.cols do
				if colY[c] < colY[col] then col = c end
			end
			local h = math.min(heights[i], L.gridHeight)
			if #page > 0 and colY[col] + h > L.gridHeight then break end
			page[#page + 1] = { index = i, col = col, x = L.inset + (col - 1) * (L.cardWidth + L.colGap),
				y = colY[col], h = h }
			colY[col] = colY[col] + h + L.rowGap
			i = i + 1
		end
		pages[#pages + 1] = page
	until i > n
	return pages
end

--- The clamped page number for a list of pages. Pure.
function ChronicleView.Pages(pages, page)
	local count = math.max(1, #pages)
	return count, math.min(math.max(page or 1, 1), count)
end

--- A tab's width for its label and count (the count may be nil). Pure.
function ChronicleView.TabWidth(spec, count, L)
	L = L or ChronicleView.LAYOUT
	local text = spec.label .. ((count and count > 0) and ("  " .. count) or "")
	return math.max(spec.width, math.ceil(ns.Style.TextWidth(text, "button")) + 2 * L.tabTextPad)
end

local IMPORTANCE_CHIPS = { { "Ordinary", "muted" }, { "Notable", "muted" }, { "Defining", "accent" } }
local PROVENANCE = { player = "Your words", observed = "From an event", suggested = "Suggested by Dawnward" }
local STATUS = { established = "Established", proposed = "Suggested", disputed = "Disputed",
	superseded = "Superseded" }
local STATE = { active = "Active", paused = "Paused", concluded = "Concluded", abandoned = "Abandoned",
	achieved = "Achieved", unresolved = "Unresolved" }
local ARC_KIND = { growth = "Growth", goal = "Goal", conflict = "Conflict", conviction = "Conviction",
	relationship = "Relationship", other = "Other" }
local PERSON = { npc = "Someone in the world", player = "Player character", family = "Family", other = "Other" }
local FINDING = { persona = "Stance", personality = "Personality", disputed = "Disputed record", goal = "Goal",
	duplicate = "Possible duplicate", privacy = "Privacy", publicfact = "Public stance and fact", date = "Dates",
	replaced = "Replaced record" }
local SIDE_STATUS = { established = "Established", proposed = "Suggested", disputed = "Disputed",
	superseded = "Superseded", observed = "Observed", verified = "Verified", partial = "Partial" }

--- Short date for a card: "Today", "28 Oct", or with the year when it is
-- not this year; nil when unknown. Pure.
function ChronicleView.ShortDate(timestamp, now)
	return ns.ChroniclePlaces.ShortDate(timestamp, now)
end

--- What a card shows for a record (or a Review finding). Pure.
-- Returns { chip = { text, tone } or nil, date, title, meta, text,
-- chips = { { text, tone } }, progress = 0..1 or nil, highlight }.
function ChronicleView.CardContent(listId, r, char, now)
	local c = { chips = {} }
	if listId == "review" then
		return ChronicleView.ReviewContent(r, now)
	end
	c.date = ChronicleView.ShortDate(r.at, now)
	if r.status == "proposed" then
		c.chip, c.highlight = { "Suggested · needs your call", "waiting" }, "waiting"
	elseif r.status == "disputed" then
		c.chip, c.highlight = { "Disputed · needs your call", "danger" }, "danger"
	elseif r.status == "superseded" then
		c.chip = { "Superseded", "muted" }
	end
	local function add(text, tone) c.chips[#c.chips + 1] = { text, tone or "muted" } end
	if listId == "memories" then
		c.chip = c.chip or IMPORTANCE_CHIPS[r.importance or 1] or IMPORTANCE_CHIPS[1]
		c.title, c.text = r.title, r.text
		if r.zone then add(r.zone) end
	elseif listId == "arcs" then
		c.chip = c.chip or { STATE[r.state] or r.state, r.state == "active" and "accent" or "muted" }
		c.title, c.text = r.title, r.summary
		local n = #(r.turningPoints or {})
		c.meta = string.format("%s arc · %s", ARC_KIND[r.kind] or r.kind,
			n == 0 and "no turning points yet" or string.format("%d turning point%s", n, n == 1 and "" or "s"))
		local last = r.turningPoints and r.turningPoints[n]
		if not c.text and last then c.text = "Last turning point: " .. last.note end
	elseif listId == "goals" then
		c.chip = c.chip or { STATE[r.state] or r.state,
			(r.state == "active" or r.state == "achieved") and "accent" or "muted" }
		c.title, c.text = r.title, r.text
		local p = ns.Goals.Progress(char, r)
		local parts = {}
		local objective = ns.Goals.ObjectiveText(p)
		if objective then parts[#parts + 1] = objective .. (p.objective.met and " (reached)" or "") end
		parts[#parts + 1] = p.milestonesTotal == 0 and "no milestones yet"
			or string.format("%d/%d milestones", p.milestonesDone, p.milestonesTotal)
		c.meta = table.concat(parts, " · ")
		-- Progress only from what is real: ticked milestones, else the verified objective.
		local o = p.objective
		if p.milestonesTotal > 0 then
			c.progress = p.milestonesDone / p.milestonesTotal
		elseif o and o.current and o.target and o.target > 0 then
			c.progress = o.met and 1 or o.current / o.target
		end
	elseif listId == "identity" then
		if r.deliberate then
			c.chip = c.chip or { "Deliberate contradiction", "accent" }
		elseif ns.Identity.Contradicts(r) then
			c.chip = c.chip or { "Public and private differ", "muted" }
		end
		c.title = r.subject
		c.text = string.format("In public: %s\nPrivately (%s): %s", r.persona or "-",
			ns.Themes.VISIBILITY_LABELS[r.convictionVisibility] or r.convictionVisibility, r.conviction or "-")
	elseif listId == "people" then
		c.chip = c.chip or { PERSON[r.kind] or r.kind, r.kind == "family" and "accent" or "muted" }
		c.title = r.name .. (r.realm and ("-" .. r.realm) or "")
		c.text = r.relation
		if not r.relation then c.meta = "No relation noted yet" end
	end
	if r.status ~= "proposed" and r.status ~= "disputed" then
		add(PROVENANCE[r.provenance] or r.provenance)
		if r.status == "established" then add(STATUS.established) end
	end
	return c
end

--- What a Review card shows. item is a finding (the list, or the finding
-- being examined: reviewKind "finding"), one side of an examined finding
-- (reviewKind "side", from Continuity.Examine), the Explain card
-- (reviewKind "explain") or an answered finding (reviewKind "answered").
-- Pure.
function ChronicleView.ReviewContent(item, now)
	local c = { chips = {} }
	local kind = item.reviewKind
	if kind == "side" then
		local side = item.side
		c.chip = { (item.letter and (item.letter .. " · ") or "") .. side.label, "accent" }
		c.date = ChronicleView.ShortDate(side.at, now)
		c.title = side.title or (side.missing and "No longer exists") or nil
		c.text = side.text or (side.missing and "This record no longer exists." or "")
		local meta = {}
		for _, v in ipairs({ side.provenance or false, SIDE_STATUS[side.status] or side.status or false }) do
			if v then meta[#meta + 1] = v end
		end
		if side.updatedAt and side.updatedAt > 0 and side.updatedAt ~= side.at then
			meta[#meta + 1] = "edited " .. (ChronicleView.ShortDate(side.updatedAt, now) or "")
		end
		if side.where then meta[#meta + 1] = "edit it in " .. side.where end
		c.meta = #meta > 0 and table.concat(meta, " · ") or nil
		if side.visibility then
			c.chips[#c.chips + 1] = { ns.Themes.VISIBILITY_LABELS[side.visibility] or side.visibility,
				side.visibility == "secret" and "secret" or "muted" }
		end
		return c
	elseif kind == "explain" then
		c.chip = { "Explain", "accent" }
		c.text = "Write why this is fine, in your own words, and choose what it is. Your note is kept with the "
			.. "answer; nothing in your story is changed."
		c.meta = "Your explanation"
		return c
	elseif kind == "answered" then
		local review = item.review
		c.chip = { ChronicleView.ANSWER_LABELS[review.choice] or review.choice, "muted" }
		c.date = ChronicleView.ShortDate(review.at, now)
		c.text = review.message or "A finding answered before Dawnward kept its wording."
		c.meta = review.note and ("Your note: " .. review.note) or "No note"
		return c
	end
	c.chip = { FINDING[item.kind] or "Continuity", item.kind == "privacy" and "secret" or "accent" }
	c.text = item.message
	c.meta = kind == "finding" and "Examined: the records are shown side by side above."
		or "What is it? Choose how your story reads it; canon is not changed."
	return c
end

--- The Review tab's items for a mode: "open" (findings), "examine" (the
-- sides of one finding, the finding, and the Explain card) or "answered".
-- Returns items, or nil when an examined finding is no longer open. Pure.
-- findings: the open findings when the caller has them (one run of the
-- rules per refresh); otherwise they are computed here.
function ChronicleView.ReviewItems(char, mode, key, findings)
	if mode == "answered" then
		local items = {}
		for _, a in ipairs(ns.Continuity.Answered(char)) do
			items[#items + 1] = { reviewKind = "answered", review = a.review, key = a.review.key }
		end
		return items
	elseif mode == "examine" then
		local open
		for _, f in ipairs(findings or ns.Continuity.Findings(char)) do
			if f.key == key then open = f end
		end
		local view = open and ns.Continuity.Examine(char, key, open)
		if not view then return nil end
		local items = {}
		for i = 1, 2 do
			local side = view.sides[i]
			items[#items + 1] = side and { reviewKind = "side", side = side, letter = i == 1 and "A" or "B", key = key }
				or { reviewKind = "side", side = { label = "Nothing else", text = "This finding is about one record." },
					key = key, empty = true }
		end
		local finding = {}
		for k, v in pairs(open) do finding[k] = v end
		finding.reviewKind = "finding"
		items[#items + 1] = finding
		items[#items + 1] = { reviewKind = "explain", key = key, finding = open }
		return items
	end
	return findings or ns.Continuity.Findings(char)
end

--- Whether a record (or finding) matches a search, ignoring case. Private
-- feelings are not searched (they are not shown on the card). Pure.
function ChronicleView.Matches(listId, r, query)
	if not query or query == "" then return true end
	local fields
	if listId == "memories" then fields = { r.title, r.text, r.zone }
	elseif listId == "arcs" then fields = { r.title, r.summary }
	elseif listId == "goals" then fields = { r.title, r.text }
	elseif listId == "identity" then fields = { r.subject, r.persona, r.conviction }
	elseif listId == "people" then fields = { r.name, r.realm, r.relation }
	elseif listId == "review" then
		fields = { r.message, r.review and r.review.message, r.review and r.review.note, r.side and r.side.title,
			r.side and r.side.text }
	else fields = {} end
	local needle = query:lower()
	for _, v in pairs(fields) do
		if type(v) == "string" and v:lower():find(needle, 1, true) then return true end
	end
	return false
end

ChronicleView.EMPTY = {
	memories = { "No memories yet", "Write one with New memory. Dawnward also suggests memories from the moments "
		.. "you answer in Story; a suggestion waits here until you accept, edit or remove it." },
	arcs = { "No arcs yet", "An arc is a thread of your character's story: a conflict, a conviction, a "
		.. "relationship. Start one with New arc; you decide when it turns, pauses or ends." },
	goals = { "No goals yet", "Add what your character wants with New goal. A target level, or a standing with a "
		.. "faction Dawnward has seen, shows verified progress; only you decide when it is achieved." },
	identity = { "No stances yet", "A stance records how your character presents themselves about something, "
		.. "and what they privately believe. The private side stays private unless you change it." },
	people = { "No people yet", "Add someone your character knows with New person. Only you write this; nothing "
		.. "is read from other players' profiles." },
	review = { "Nothing to review", "Nothing to review: your story is consistent as far as Dawnward can tell. "
		.. "Contradictions, duplicates and privacy risks appear here for you to answer." },
	answered = { "No answers yet", "Findings you answer are listed here, with your notes. Any answer can be "
		.. "taken back with Undo answer." },
}

local CYCLE = { private = "public", public = "secret", secret = "private" }

local VISIBILITY = { { "private", "Private" }, { "public", "Public" }, { "secret", "Secret" } }
local ARC_KINDS = { { "growth", "Growth" }, { "goal", "Goal" }, { "conflict", "Conflict" },
	{ "conviction", "Conviction" }, { "relationship", "Relationship" }, { "other", "Other" } }
local ARC_STATES = { { "active", "Active" }, { "paused", "Paused" }, { "concluded", "Concluded" },
	{ "abandoned", "Abandoned" } }
local GOAL_STATES = { { "active", "Active" }, { "paused", "Paused" }, { "achieved", "Achieved" },
	{ "unresolved", "Unresolved" }, { "abandoned", "Abandoned" } }
local PERSON_KINDS = { { "npc", "Someone in the world (NPC)" }, { "player", "Another player's character" },
	{ "family", "Family" }, { "other", "Other" } }
local IMPORTANCE = { { 1, "Ordinary" }, { 2, "Notable" }, { 3, "Defining" } }
local YES_NO = { { false, "No" }, { true, "Yes, on purpose" } }

-- Form specs for creating and editing each kind of record. save(char, values,
-- now) returns the record or nil plus a reason.
local FORMS = {}

FORMS.memories = function(r)
	return {
		title = r and "Edit memory" or "New memory",
		hint = "A memory in your own words. Editing a suggested memory makes it yours.",
		fields = {
			{ key = "title", label = "Title", kind = "line", errors = { "memory needs" } },
			{ key = "text", label = "What happened", kind = "area" },
			{ key = "importance", label = "Importance", kind = "cycle", values = IMPORTANCE },
			not r and { key = "visibility", label = "Visibility", kind = "cycle", values = VISIBILITY } or nil,
			not r and { key = "zone", label = "Where", kind = "line" } or nil,
		},
		values = r and { title = r.title, text = r.text, importance = r.importance } or {},
		save = function(char, v, now)
			if r then
				local m, err = ns.Memories.Edit(char, r.id, v, now)
				if m then m.importance = v.importance end
				return m, err
			end
			return ns.Memories.Add(char, v, "player", now)
		end,
	}
end

FORMS.arcs = function(r)
	return {
		title = r and "Edit arc" or "New arc",
		hint = "A thread of your character's story. You decide when it turns, pauses or ends.",
		fields = {
			{ key = "title", label = "Title", kind = "line", errors = { "needs a title" } },
			{ key = "summary", label = "Summary", kind = "area" },
			{ key = "kind", label = "Kind", kind = "cycle", values = ARC_KINDS },
			r and { key = "state", label = "State", kind = "cycle", values = ARC_STATES }
				or { key = "visibility", label = "Visibility", kind = "cycle", values = VISIBILITY },
		},
		values = r and { title = r.title, summary = r.summary, kind = r.kind, state = r.state } or {},
		save = function(char, v, now)
			if not r then return ns.Arcs.Add(char, v, "player", now) end
			local a, err = ns.Arcs.Edit(char, r.id, v, now)
			if not a then return nil, err end
			return ns.Arcs.SetState(char, r.id, v.state, now)
		end,
	}
end

-- Standings a reputation objective can target (Friendly and above are the
-- usual aims, but any standing is allowed).
local STANDINGS = { { 5, "Friendly" }, { 6, "Honored" }, { 7, "Revered" }, { 8, "Exalted" }, { 4, "Neutral" },
	{ 3, "Unfriendly" }, { 2, "Hostile" }, { 1, "Hated" } }

FORMS.goals = function(r)
	local o = r and r.objective
	local function blank(s) return not s or not s:match("%S") end
	-- One verified objective at most: a level, or a standing with a faction.
	local function objective(char, id, v, now)
		if not blank(v.faction) then
			if v.target then return nil, "choose a target level or a faction, not both" end
			return ns.Goals.SetReputationObjective(char, id, v.faction, v.standing, now)
		end
		return ns.Goals.Edit(char, id, { target = v.target or false }, now)
	end
	return {
		title = r and "Edit goal" or "New goal",
		hint = "What your character wants. A target level, or a standing with a faction Dawnward has seen, is "
			.. "shown as verified progress; only you decide when the goal is achieved.",
		fields = {
			{ key = "title", label = "Goal", kind = "line", errors = { "needs a title" } },
			{ key = "text", label = "Why it matters", kind = "area" },
			{ key = "target", label = "Target level", kind = "number", errors = { "whole number from 2" } },
			{ key = "faction", label = "Or a faction", kind = "line",
				errors = { "not both", "has not seen", "name a faction", "the standing must" } },
			{ key = "standing", label = "Standing", kind = "cycle", values = STANDINGS },
			r and { key = "state", label = "State", kind = "cycle", values = GOAL_STATES }
				or { key = "visibility", label = "Visibility", kind = "cycle", values = VISIBILITY },
		},
		values = r and { title = r.title, text = r.text, state = r.state,
			target = o and o.kind == "level" and o.target or nil,
			faction = o and o.kind == "reputation" and o.factionName or nil,
			standing = o and o.kind == "reputation" and o.target or nil } or {},
		save = function(char, v, now)
			if not r then
				local g, err = ns.Goals.Add(char, { title = v.title, text = v.text, visibility = v.visibility }, now)
				if not g then return nil, err end
				local ok, why = objective(char, g.id, v, now)
				if not ok then
					ns.Goals.Remove(char, g.id)
					return nil, why
				end
				return g
			end
			-- Checked first, so a refused save changes nothing.
			if blank(v.title) then return nil, "a goal needs a title" end
			local g, err = objective(char, r.id, v, now)
			if not g then return nil, err end
			ns.Goals.Edit(char, r.id, { title = v.title, text = v.text }, now)
			return ns.Goals.SetState(char, r.id, v.state, now)
		end,
	}
end

FORMS.identity = function(r)
	return {
		title = r and "Edit stance" or "New stance",
		hint = "How your character presents themselves about something, and what they privately believe. "
			.. "The private side stays private unless you change it.",
		fields = {
			{ key = "subject", label = "About", kind = "line", errors = { "needs a subject" } },
			{ key = "persona", label = "In public", kind = "line", errors = { "public stance or a private conviction" } },
			{ key = "conviction", label = "Privately", kind = "line" },
			{ key = "deliberate", label = "Contradiction", kind = "cycle", values = YES_NO },
		},
		-- Adding with neither side gives one message for two causes: point at the empty one.
		locate = function(v)
			if not (v.subject or ""):match("%S") then return "subject" end
			return "persona"
		end,
		values = r and { subject = r.subject, persona = r.persona, conviction = r.conviction,
			deliberate = r.deliberate == true } or { deliberate = false },
		save = function(char, v, now)
			if r then return ns.Identity.Edit(char, r.id, v, now) end
			v.deliberate = v.deliberate or nil
			return ns.Identity.Add(char, v, now)
		end,
	}
end

FORMS.people = function(r)
	return {
		title = r and "Edit person" or "New person",
		hint = "Someone your character knows. Only you write this; nothing is read from other players' profiles.",
		fields = {
			{ key = "name", label = "Name", kind = "line", errors = { "needs a name", "is already" } },
			{ key = "kind", label = "Who", kind = "cycle", values = PERSON_KINDS },
			{ key = "realm", label = "Realm (players)", kind = "line", errors = { "needs a realm" } },
			{ key = "relation", label = "Relation", kind = "line" },
			{ key = "feelings", label = "Private feelings", kind = "area" },
		},
		values = r and { name = r.name, kind = r.kind, realm = r.realm, relation = r.relation,
			feelings = r.feelings } or { kind = "npc" },
		save = function(char, v, now)
			if r then return ns.People.Edit(char, r.id, v, now) end
			return ns.People.Add(char, v, now)
		end,
	}
end

-- Milestones of a goal: the most recent ones can be ticked, and one added.
local MILESTONE_ROWS = Forms.MAX_FIELDS - 1

local function milestoneForm(goal)
	local fields, values, first = {}, {}, math.max(1, #goal.milestones - MILESTONE_ROWS + 1)
	for i = first, #goal.milestones do
		local m = goal.milestones[i]
		fields[#fields + 1] = { key = i, label = "Step " .. i, kind = "cycle",
			values = { { false, "Not yet: " .. m.text }, { true, "Done: " .. m.text } } }
		values[i] = m.done == true
	end
	fields[#fields + 1] = { key = "new", label = "New step", kind = "line", errors = { "milestone" } }
	return {
		title = "Milestones: " .. goal.title,
		hint = "Tick the steps your character has taken. Dawnward never ticks them for you.",
		fields = fields, values = values,
		save = function(char, v, now)
			for i = first, #goal.milestones do
				if (goal.milestones[i].done == true) ~= v[i] then
					ns.Goals.SetMilestone(char, goal.id, i, v[i], now)
				end
			end
			if v.new and v.new:match("%S") then
				return ns.Goals.AddMilestone(char, goal.id, v.new, now)
			end
			return goal
		end,
	}
end

local function turningPointForm(arc)
	return {
		title = "Turning point: " .. arc.title,
		hint = "A moment that changed the course of this arc.",
		fields = { { key = "note", label = "What changed", kind = "area", errors = { "turning point" } } },
		values = {},
		save = function(char, v, now) return ns.Arcs.AddTurningPoint(char, arc.id, v.note, nil, now) end,
	}
end

-- The Explain form: the player's note, kept with the answer they choose.
local EXPLAIN_ANSWERS = { { "explained", "Explained: keep my note" }, { "growth", "Growth" },
	{ "unreliable", "Unreliable" }, { "secret", "Secret" }, { "correction", "Correction" }, { "ignore", "Ignore" } }

function ChronicleView.ExplainForm(finding)
	return {
		title = "Explain this finding",
		hint = finding.message,
		fields = {
			{ key = "note", label = "Your note", kind = "area", max = 300, errors = { "explanation" } },
			{ key = "choice", label = "It is", kind = "cycle", values = EXPLAIN_ANSWERS },
		},
		values = { choice = "explained" },
		save = function(char, v, now)
			local note = v.note and v.note:match("%S") and v.note or nil
			return ns.Continuity.Review(char, finding.key, v.choice, note, now)
		end,
	}
end

ChronicleView.FORMS = FORMS
ChronicleView.CYCLE = CYCLE
ChronicleView.MilestoneForm = milestoneForm
ChronicleView.TurningPointForm = turningPointForm

local SECTION_DEF -- the registered section, whose heading follows the tab

local function place(region, rect, dx, dy)
	region:ClearAllPoints()
	region:SetPoint("TOPLEFT", rect.x + (dx or 0), -(rect.y + (dy or 0)))
	region:SetWidth(rect.w)
	if rect.h then region:SetHeight(rect.h) end
end

local function tabSpec(id)
	for _, tab in ipairs(ChronicleView.TABS) do
		if tab.id == id then return tab end
	end
end

-- Button labels of the record actions; every other label is an answer.
ChronicleView.ACTION_LABELS = { accept = "Accept", edit = "Edit", dispute = "Dispute", turn = "Turn",
	steps = "Steps", read = "Read", remove = "Remove", explain = "Explain...", undo = "Undo answer" }
-- Remove is destructive, Accept the one primary action, Edit and the
-- answers the usual ones (filled, with an edge); the rest are quiet.
ChronicleView.ACTION_VARIANTS = { accept = "primary", edit = "default", remove = "danger", explain = "default",
	undo = "default", growth = "default", unreliable = "default", secret = "default", correction = "default",
	ignore = "default" }
ChronicleView.CUT_HELP = "The game shortened this text to fit. Click to read the whole record."
ChronicleView.READ_HELP = "Shows the whole record: its full title, meta line and text, with its actions."

--- The buttons of a card (or of the full view): left = { { id, label } },
-- right = { id, label } or nil (Remove, at the right edge). opts.read adds
-- Read (the card cannot show everything). Pure.
function ChronicleView.Actions(tabId, item, opts)
	opts = opts or {}
	local A = ChronicleView.ACTION_LABELS
	local left = {}
	local function add(id, label) left[#left + 1] = { id, label or A[id] } end
	if tabId == "review" then
		local kind = item.reviewKind
		if kind == "side" then
			local side = item.side
			if side.editable and not side.missing and ChronicleView.FORMS[side.list] then
				add("edit")
				if side.list == "goals" then add("steps") end
			end
		elseif kind == "explain" then
			add("explain")
		elseif kind == "answered" then
			add("undo")
		else
			for _, choice in ipairs(ChronicleView.REVIEW_CHOICES) do add(choice, ChronicleView.REVIEW_LABELS[choice]) end
		end
		if opts.read then add("read") end
		return left
	end
	local m = ns[tabSpec(tabId).module] or {}
	if (item.status == "proposed" or item.status == "disputed") and m.Accept then add("accept") end
	add("edit")
	if item.status == "established" and m.Dispute then add("dispute") end
	if tabId == "arcs" then add("turn")
	elseif tabId == "goals" then add("steps")
	elseif tabId == "identity" then
		add("inner", "Inner: " .. (ns.Themes.VISIBILITY_LABELS[item.convictionVisibility] or item.convictionVisibility))
	end
	if opts.read then add("read") end
	local right = (item.provenance == "player" or item.status == "proposed") and { "remove", A.remove } or nil
	return left, right
end

--- True when the client cut a card's text or meta line although its layout
-- estimated they fit (no Read button). Guarded: IsTruncated may be missing.
function ChronicleView.ClientCut(row, layout)
	if layout.truncated then return false end
	for _, key in ipairs({ "text", "meta" }) do
		local fs = row[key]
		if layout[key] and fs and fs.IsTruncated and fs:IsTruncated() then return true end
	end
	return false
end

--- What a card shows for an item and where: content (CardContent plus vis
-- and examine) and layout (CardLayout). Pure.
function ChronicleView.ItemLayout(tabId, item, char, now, L)
	local content = ChronicleView.CardContent(tabId, item, char, now)
	if tabId ~= "review" then content.vis = item.visibility or "private" end
	content.examine = tabId == "review" and item.reviewKind == nil or nil
	local layout = ChronicleView.CardLayout(content, function(read)
		return ChronicleView.Actions(tabId, item, { read = read })
	end, L)
	return content, layout
end

-- The identity of an item across refreshes (records by id, Review items by
-- their finding and part).
local function itemKey(item)
	if item.id then return "id:" .. tostring(item.id) end
	return tostring(item.reviewKind or "finding") .. ":" .. tostring(item.key) .. ":" .. tostring(item.letter or "")
end
ChronicleView.ItemKey = itemKey

-- "rrggbb" of a colour, for inline colour codes.
local function hex(color)
	return string.format("%02x%02x%02x", math.floor(color[1] * 255 + 0.5), math.floor(color[2] * 255 + 0.5),
		math.floor(color[3] * 255 + 0.5))
end

--- A tab's label: its name, then its count in a quieter colour (the
-- "needs you" amber on Review, as the mockup's count badge). Pure.
function ChronicleView.TabLabel(spec, count, selected, theme)
	if not count or count == 0 then return spec.label end
	local tones = ns.Style.Tones(theme)
	local color = spec.id == "review" and ns.Themes.STATUS_COLORS.waiting
		or (selected and tones.label or ns.Style.Mix(theme.muted, theme.edge, 0.2))
	return string.format("%s  |cff%s%d|r", spec.label, hex(color), count)
end

-- Card painting (Widgets.Card, plus the design's "needs your call" card:
-- an amber edge on a warm fill for a suggestion, a red edge for a dispute).
-- Kept here until Widgets.Card takes a tone (see docs/design/audit/chronicle.md).
local function paintCard(c, theme)
	local tones = Style.Tones(theme)
	local fill = c.hover and tones.cardHover or theme.surface
	local edge = c.hover and tones.selectedEdge or theme.edge
	if c.highlight == "waiting" then
		fill = tones.calloutFill
		edge = Style.Mix(theme.surface, ns.Themes.STATUS_COLORS.waiting, c.hover and 0.6 or 0.36)
	elseif c.highlight == "danger" then
		edge = c.hover and theme.danger or tones.dangerEdge
	end
	Style.Color(c.bg, fill)
	c.edges:Paint(edge, 1)
	c.bar:Hide()
end

local function create(parent)
	local L = ChronicleView.LAYOUT
	local section = { frame = CreateFrame("Frame", nil, parent), tab = "memories", page = 1, rows = {},
		tabButtons = {}, query = "", reviewMode = "open" }
	local f = section.frame
	section.form = Forms.Create(f, L.width + 2 * L.inset)

	local function run(fn)
		return Actions.WithCharacter(ns.ctx, function(char)
			local r, err = fn(char, ns.ctx.now())
			if not r then return Actions.Fail(err) end
			return r, "Saved."
		end)
	end

	local function act(fn)
		local _, message = run(fn)
		MainWindow.SetStatus(message)
		MainWindow.Refresh()
	end

	--- Opens a form from a spec with a save(char, values, now).
	function section:OpenForm(spec)
		spec.onSave = function(values) return run(function(char, now) return spec.save(char, values, now) end) end
		self.form:Open(spec)
	end

	-- Secondary navigation: a segmented control on a panel track, each tab
	-- sized to its label and count.
	local tabItems = {}
	for i, tab in ipairs(ChronicleView.TABS) do tabItems[i] = { id = tab.id, label = tab.label } end
	section.tabBar = CreateFrame("Frame", nil, f)
	section.tabBar.bg = Style.Solid(section.tabBar, "BACKGROUND", -2)
	section.tabBar.bg:SetAllPoints(section.tabBar)
	section.tabBar.edges = Style.Edge(section.tabBar, "BORDER")
	Style.Register(section.tabBar, function(bar, theme)
		Style.Color(bar.bg, theme.panel)
		bar.edges:Paint(theme.edge, 1)
	end)
	section.tabs = Widgets.Segmented(f, tabItems, L.width, L.tabHeight - 2 * L.tabPad, function(id)
		if id ~= section.tab then
			section.tab, section.page, section.query = id, 1, ""
			section.reviewMode, section.examineKey = "open", nil
			section.search:SetText("")
			section.search:ClearFocus()
		end
		section.detailKey = nil
		section.form:Close()
		-- Before the refresh, which draws the heading first.
		if SECTION_DEF then SECTION_DEF.heading = tabSpec(id).label end
		MainWindow.Refresh()
	end)
	for i, b in ipairs(section.tabs.buttons) do
		b.tabId = ChronicleView.TABS[i].id
		section.tabButtons[i] = b
	end
	section.tabBar:SetPoint("TOPLEFT", L.inset, 0)

	--- Sizes each tab to its label and lines them up on the track.
	function section:LayoutTabs(counts)
		local x = L.tabPad
		for i, b in ipairs(self.tabButtons) do
			local spec = ChronicleView.TABS[i]
			b:SetWidth(ChronicleView.TabWidth(spec, counts and counts[i]))
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", L.inset + x, -L.tabPad)
			x = x + b:GetWidth() + L.tabGap
		end
		self.tabBar:SetSize(x - L.tabGap + L.tabPad, L.tabHeight)
	end
	section:LayoutTabs()

	-- Toolbar: New, search, count and pager (the pager only with more than one page).
	local barY = -L.toolbarTop
	section.new = Widgets.Button(f, "New", L.newWidth, L.toolbarHeight, "primary")
	section.new:SetPoint("TOPLEFT", L.inset, barY)
	section.new:SetScript("OnClick", function()
		if section.tab == "review" then
			-- Review: the toolbar button switches between the findings and the answers.
			section.reviewMode = section.reviewMode == "open" and "answered" or "open"
			section.examineKey, section.page = nil, 1
			MainWindow.Refresh()
			return
		end
		section:OpenForm(ChronicleView.FORMS[section.tab]())
	end)
	section.search = Widgets.SearchBox(f, L.searchWidth, "Search", function(text)
		if text ~= section.query then
			section.query, section.page = text, 1
			MainWindow.Refresh()
		end
	end, Style.CONTROL.input)
	section.search:SetHeight(L.toolbarHeight)
	local pagerY = barY - (L.toolbarHeight - Style.CONTROL.compact) / 2
	section.next = Widgets.Button(f, ">", Style.CONTROL.compact, Style.CONTROL.compact, "ghost")
	section.next:SetPoint("TOPRIGHT", -L.inset, pagerY)
	section.next:SetScript("OnClick", function() section.page = section.page + 1; MainWindow.Refresh() end)
	Widgets.Tooltip(section.next, "Next page")
	section.pageLabel = Widgets.Label(f, "meta", false, "muted")
	section.pageLabel:SetJustifyH("CENTER")
	section.pageLabel:SetWidth(84)
	section.pageLabel:SetPoint("RIGHT", section.next, "LEFT", -4, 0)
	section.prev = Widgets.Button(f, "<", Style.CONTROL.compact, Style.CONTROL.compact, "ghost")
	section.prev:SetPoint("RIGHT", section.pageLabel, "LEFT", -4, 0)
	section.prev:SetScript("OnClick", function() section.page = section.page - 1; MainWindow.Refresh() end)
	Widgets.Tooltip(section.prev, "Previous page")
	section.count = Widgets.Label(f, "meta", false, "muted")
	section.count:SetJustifyH("RIGHT")
	section.count:SetWidth(220)
	section.toolbar = { section.new, section.search, section.prev, section.pageLabel, section.next, section.count }
	section.pager = { section.prev, section.pageLabel, section.next }

	-- Empty state: what the tab holds and how to fill it.
	section.emptyPanel = Widgets.Panel(f, "Nothing here yet")
	section.emptyPanel:SetPoint("TOPLEFT", L.inset, -L.gridTop)
	section.emptyPanel:SetSize(L.width, 110)
	section.empty = Widgets.Label(section.emptyPanel.inner, "reading", true, "reading")
	section.empty:SetPoint("TOPLEFT", 0, 0)
	section.empty:SetWidth(L.width - 2 * Widgets.PANEL_PAD)

	-- The parts every record view has (a card, and the full view): status
	-- chip, date, title, meta, text, progress, chips, visibility, divider,
	-- Examine and the action buttons. width: the text width.
	local function addParts(row, width)
		row.chip = Widgets.Chip(row, "", "muted")
		row.date = Widgets.Label(row, "GameFontHighlightSmall", false, "muted")
		row.date:SetJustifyH("RIGHT")
		row.meta = Widgets.Label(row, "meta", true, "muted")
		row.progress = Widgets.ProgressBar(row, width, Style.CONTROL.progress)
		row.chips = {}
		for c = 1, L.chips do row.chips[c] = Widgets.Chip(row, "", "muted") end
		row.vis = Widgets.VisibilityButton(row, function(level)
			if row.onVisibility then row.onVisibility(level) end
		end)
		row.vis:SetHeight(L.chipRow)
		row.divider = Widgets.Divider(row)
		-- Review findings only: Examine, where a record card shows its date.
		local er = ChronicleView.EXAMINE_RECT
		row.examine = Widgets.Button(row, "Examine", er.w, er.h, "default")
		Widgets.Tooltip(row.examine, "Examine", ChronicleView.EXAMINE_HELP)
		row.examine:Hide()
		row.actions, row.buttons = {}, {}
		for b = 1, L.buttons do
			local button = Widgets.Button(row, "", 64, L.buttonHeight, "ghost")
			button:Hide()
			row.actions[b] = button
			row.buttons[b] = button
		end
		-- The visibility chip is one of the record's buttons too.
		row.buttons[#row.buttons + 1] = row.vis
	end

	-- The card pool.
	for i = 1, L.pool do
		local row = Widgets.Card(f)
		Style.Register(row, paintCard)
		row:SetSize(L.cardWidth, 200)
		row.title = Widgets.Label(row, nil, false, "title")
		-- One line, so a long title is cut with "..."; hovering shows it whole.
		row.titleHover = CreateFrame("Frame", nil, row)
		Widgets.Tooltip(row.titleHover, "", nil)
		-- Hovering the title still highlights its card.
		row.titleHover:HookScript("OnEnter", function() row:SetRowHover(true) end)
		row.titleHover:HookScript("OnLeave", function() row:SetRowHover(false) end)
		row.text = Widgets.Label(row, "reading", true, "reading")
		-- Over the text, shown only when the client shortened it although the
		-- estimate said it fits (so the card has no Read button): hovering
		-- says so, clicking opens the full view.
		row.textHover = CreateFrame("Button", nil, row)
		row.textHover:HookScript("OnEnter", function() row:SetRowHover(true) end)
		row.textHover:HookScript("OnLeave", function() row:SetRowHover(false) end)
		row.textHover:SetScript("OnClick", function()
			if row.readKey then section.detailKey = row.readKey; MainWindow.Refresh() end
		end)
		row.textHover:Hide()
		addParts(row, L.cardWidth - 2 * L.cardPad)
		row:Hide()
		section.rows[i] = row
	end

	-- The full view of one record (Read): over the toolbar and the cards,
	-- under the forms. Title and meta wrap; the text scrolls.
	local DW, DH, DP = L.width, L.height - L.toolbarTop, L.detailPad
	local dInner = DW - 2 * DP
	local detail = Widgets.Panel(f)
	detail:SetPoint("TOPLEFT", L.inset, -L.toolbarTop)
	detail:SetSize(DW, DH)
	if detail.SetFrameLevel and f.GetFrameLevel then detail:SetFrameLevel((f:GetFrameLevel() or 1) + 10) end
	if detail.EnableMouse then detail:EnableMouse(true) end
	detail.back = Widgets.Button(detail, "<  Back", 120, Style.CONTROL.compact, "ghost")
	detail.back:SetPoint("TOPLEFT", DP, -DP)
	detail.back:SetScript("OnClick", function()
		section.detailKey = nil
		MainWindow.Refresh()
	end)
	detail.title = Widgets.Label(detail, nil, true, "title")
	detail.scroll = CreateFrame("ScrollFrame", Widgets.NextName("ChronicleRead"), detail, "UIPanelScrollFrameTemplate")
	detail.body = CreateFrame("Frame", nil, detail.scroll)
	detail.body:SetSize(dInner - 26, 100)
	detail.scroll:SetScrollChild(detail.body)
	detail.scrollBar = Widgets.SlimScrollBar(detail.scroll, 14)
	detail.text = Widgets.Label(detail.body, "reading", true, "reading")
	detail.text:SetPoint("TOPLEFT", 0, 0)
	detail.text:SetWidth(dInner - 26)
	addParts(detail, dInner)
	detail:Hide()
	section.detail = detail

	local function setTooltip(button, id, item)
		if ChronicleView.REVIEW_HELP[id] then
			Widgets.Tooltip(button, ChronicleView.REVIEW_LABELS[id], ChronicleView.REVIEW_HELP[id])
		elseif id == "explain" then
			Widgets.Tooltip(button, "Explain", ChronicleView.REVIEW_HELP.explained)
		elseif id == "undo" then
			Widgets.Tooltip(button, "Undo answer", ChronicleView.UNDO_HELP)
		elseif id == "read" then
			Widgets.Tooltip(button, "Read", ChronicleView.READ_HELP)
		elseif id == "edit" and item.reviewKind == "side" then
			Widgets.Tooltip(button, "Edit", "Correct this record yourself, in its own form.")
		elseif id == "inner" then
			Widgets.Tooltip(button, "Private side", string.format("Who may see what your character privately "
				.. "believes: now %s. Click to change it to %s.",
				ns.Themes.VISIBILITY_LABELS[item.convictionVisibility] or item.convictionVisibility,
				ns.Themes.VISIBILITY_LABELS[ChronicleView.CYCLE[item.convictionVisibility]] or "Private"))
		else
			Widgets.Tooltip(button, nil)
		end
	end

	-- What a button does, by its action id.
	local function handler(id, tabId, item)
		if tabId == "review" then
			if id == "edit" then
				return function() section:OpenForm(ChronicleView.FORMS[item.side.list](item.side.record)) end
			elseif id == "steps" then
				return function() section:OpenForm(ChronicleView.MilestoneForm(item.side.record)) end
			elseif id == "explain" then
				return function() section:OpenForm(ChronicleView.ExplainForm(item.finding)) end
			elseif id == "undo" then
				return function() act(function(c) return ns.Continuity.Undo(c, item.key) end) end
			elseif id == "read" then
				return function() section.detailKey = itemKey(item); MainWindow.Refresh() end
			end
			return function()
				act(function(c, now2) return ns.Continuity.Review(c, item.key, id, nil, now2) end)
			end
		end
		local m = ns[tabSpec(tabId).module]
		local r = item
		if id == "accept" then
			return function() act(function(char, now) return m.Accept(char, r.id, now) end) end
		elseif id == "edit" then
			return function() section:OpenForm(ChronicleView.FORMS[tabId](r)) end
		elseif id == "dispute" then
			return function() act(function(char, now) return m.Dispute(char, r.id, now) end) end
		elseif id == "turn" then
			return function() section:OpenForm(ChronicleView.TurningPointForm(r)) end
		elseif id == "steps" then
			return function() section:OpenForm(ChronicleView.MilestoneForm(r)) end
		elseif id == "inner" then
			return function()
				act(function(char, now) return ns.Identity.SetConvictionVisibility(char, r.id,
					ChronicleView.CYCLE[r.convictionVisibility], now) end)
			end
		elseif id == "read" then
			return function() section.detailKey = itemKey(r); MainWindow.Refresh() end
		elseif id == "remove" then
			return function()
				Widgets.Confirm("Remove this record?", "Remove", function()
					act(function(char) return m.Remove(char, r.id) end)
				end)
			end
		end
	end

	-- Places the buttons of a laid-out view (rect = layout.buttons) and wires them.
	local function fillButtons(row, rect, tabId, item)
		local items = rect and rect.items or {}
		for b, button in ipairs(row.actions) do
			local spec = items[b]
			button:SetShown(spec ~= nil)
			if spec then
				button:SetText(spec.label)
				button:SetVariant(ChronicleView.ACTION_VARIANTS[spec.id] or "ghost")
				button:SetWidth(spec.w)
				button:ClearAllPoints()
				button:SetPoint("TOPLEFT", rect.x + spec.x, -(rect.y + spec.y))
				button:SetScript("OnClick", handler(spec.id, tabId, item))
				button.actionId = spec.id
				setTooltip(button, spec.id, item)
			end
		end
		row.examine:SetShown(tabId == "review" and item.reviewKind == nil)
		if tabId == "review" then
			row.examine:SetScript("OnClick", function()
				section.reviewMode, section.examineKey, section.page, section.detailKey = "examine", item.key, 1, nil
				MainWindow.Refresh()
			end)
			row.onVisibility = nil
		else
			local m = ns[tabSpec(tabId).module]
			row.onVisibility = function(level)
				act(function(char, now) return m.SetVisibility(char, item.id, level, now) end)
			end
		end
	end

	-- Chips and the visibility chip at the positions of rect (= layout.chips).
	local function fillChips(row, rect, content)
		for c, chip in ipairs(row.chips) do
			local spec, at = content.chips[c], rect and rect.items[c]
			chip:SetShown(spec ~= nil and at ~= nil)
			if spec and at then
				chip:SetMaxWidth(at.w)
				chip:SetChip(spec[1], spec[2])
				chip:ClearAllPoints()
				chip:SetPoint("TOPLEFT", rect.x + at.x, -(rect.y + at.y))
			end
		end
		local vis = rect and rect.vis
		row.vis:SetShown(vis ~= nil)
		if vis then
			row.vis:SetLevel(content.vis)
			row.vis:SetWidth(vis.w)
			row.vis:ClearAllPoints()
			row.vis:SetPoint("TOPLEFT", rect.x + vis.x, -(rect.y + vis.y))
		end
	end

	local function fillTop(row, layout, content)
		row.chip:SetShown(content.chip ~= nil)
		if content.chip then
			row.chip:SetMaxWidth(layout.chip.w)
			row.chip:SetChip(content.chip[1], content.chip[2])
			row.chip:ClearAllPoints()
			row.chip:SetPoint("TOPLEFT", layout.chip.x, -layout.chip.y)
		end
		row.date:SetShown(layout.date ~= nil)
		if layout.date then place(row.date, layout.date) end
		row.date:SetText(content.date or "")
		if layout.examine then
			row.examine:ClearAllPoints()
			row.examine:SetPoint("TOPLEFT", layout.examine.x, -layout.examine.y)
		end
	end

	local function fillCard(row, content, layout, tabId, item)
		row.layout, row.content = layout, content
		row:SetHeight(layout.height)
		fillTop(row, layout, content)
		row.title:SetShown(layout.title ~= nil)
		row.titleHover:SetShown(layout.title ~= nil)
		if layout.title then
			place(row.title, layout.title)
			row.title:SetText(content.title)
			place(row.titleHover, layout.title)
			Widgets.Tooltip(row.titleHover, content.title, content.meta)
		end
		row.meta:SetShown(layout.meta ~= nil)
		if layout.meta then
			place(row.meta, layout.meta)
			if row.meta.SetMaxLines then row.meta:SetMaxLines(layout.meta.lines) end
			row.meta:SetText(content.meta)
		end
		row.text:SetShown(layout.text ~= nil)
		if layout.text then
			place(row.text, layout.text)
			-- The estimate allows for the client's own wrapping; if it still
			-- needs more lines, the client ends the last one with "..." and
			-- Read shows the rest.
			if row.text.SetMaxLines then row.text:SetMaxLines(layout.text.lines) end
		end
		row.text:SetText(content.text or "")
		row.readKey = nil
		if ChronicleView.ClientCut(row, layout) then
			row.readKey = itemKey(item)
			place(row.textHover, layout.text or layout.title)
			Widgets.Tooltip(row.textHover, "Shortened", ChronicleView.CUT_HELP)
		end
		row.textHover:SetShown(row.readKey ~= nil)
		row.progress:SetShown(layout.progress ~= nil)
		if layout.progress then
			place(row.progress, layout.progress)
			row.progress:SetValue(content.progress)
		end
		row.divider:SetShown(layout.divider ~= nil)
		if layout.divider then place(row.divider, layout.divider) end
		fillChips(row, layout.chips, content)
		fillButtons(row, layout.buttons, tabId, item)
		row.highlight = content.highlight or nil
		Style.Repaint(row)
	end

	--- The full view of item: everything a card shows, nothing cut.
	function section:ShowDetail(tabId, item, char, now)
		local content = ChronicleView.CardContent(tabId, item, char, now)
		if tabId ~= "review" then content.vis = item.visibility or "private" end
		local d = self.detail
		d.item, d.content = item, content
		local spec = tabSpec(tabId)
		local backTo = tabId == "review" and "findings" or (spec.noun and spec.noun[2]) or "the list"
		d.back:SetText("<  Back to " .. backTo)
		d.back:SetWidth(ChronicleView.ButtonWidth(d.back:GetText(), L.buttonPad))
		local y = DP
		-- The top row: Back, then the date at the right.
		place(d.date, { x = DP + dInner - L.dateWidth, y = y + 7, w = L.dateWidth, h = 16 })
		d.date:SetText(content.date or "")
		y = y + Style.CONTROL.compact + 12
		local examine = tabId == "review" and item.reviewKind == nil
		local er = ChronicleView.EXAMINE_RECT
		local top = examine and er.h or L.chipRow
		d.chip:SetShown(content.chip ~= nil)
		if content.chip then
			d.chip:SetMaxWidth(dInner - (examine and (er.w + 8) or 0))
			d.chip:SetChip(content.chip[1], content.chip[2])
			d.chip:ClearAllPoints()
			d.chip:SetPoint("TOPLEFT", DP, -(y + (top - L.chipRow) / 2))
		end
		if examine then
			d.examine:ClearAllPoints()
			d.examine:SetPoint("TOPLEFT", DP + dInner - er.w, -y)
		end
		y = y + top + L.gap
		d.title:SetShown(content.title ~= nil)
		if content.title then
			local lines = math.max(1, math.min(L.detailTitleLines, ChronicleView.WrapLines(content.title, dInner, "title")))
			place(d.title, { x = DP, y = y, w = dInner, h = lines * L.detailTitleLine })
			if d.title.SetMaxLines then d.title:SetMaxLines(lines) end
			d.title:SetText(content.title)
			y = y + lines * L.detailTitleLine + L.gap
		end
		d.meta:SetShown(content.meta ~= nil)
		if content.meta then
			local lines = math.max(1, math.min(L.detailMetaLines, ChronicleView.WrapLines(content.meta, dInner, "meta")))
			place(d.meta, { x = DP, y = y, w = dInner, h = lines * L.metaLine })
			d.meta:SetText(content.meta)
			y = y + lines * L.metaLine + L.gap
		end
		-- From the bottom: the buttons, the divider, the chips.
		local left, right = ChronicleView.Actions(tabId, item, {})
		local rows = ChronicleView.ButtonRows(left, right, dInner, L)
		local bottom = DH - DP
		local buttons
		if rows.rows > 0 then
			buttons = { x = DP, y = bottom - rows.height, w = dInner, h = rows.height, items = rows.items }
			bottom = buttons.y - L.dividerGap - 1
			place(d.divider, { x = DP, y = bottom, w = dInner, h = 1 })
			bottom = bottom - L.gap
		end
		d.divider:SetShown(buttons ~= nil)
		local chipRows = ChronicleView.ChipRows(content.chips, content.vis, dInner, L)
		local chips
		if chipRows.rows > 0 then
			chips = { x = DP, y = bottom - chipRows.height, w = dInner, h = chipRows.height, items = chipRows.items,
				vis = chipRows.vis }
			bottom = chips.y - L.gap
		end
		d.progress:SetShown(content.progress ~= nil)
		if content.progress then
			bottom = bottom - L.progressHeight
			place(d.progress, { x = DP, y = bottom, w = dInner, h = L.progressHeight })
			d.progress:SetValue(content.progress)
			bottom = bottom - L.gap
		end
		-- The text, whole, scrolling when it is longer than the room left.
		-- The scroll bar (UIPanelScrollFrameTemplate) sits just right of the
		-- frame, so the frame leaves it room inside the panel.
		place(d.scroll, { x = DP, y = y, w = dInner - 26, h = math.max(L.textLine, bottom - y) })
		local text = content.text or ""
		d.text:SetText(text)
		local lines = ChronicleView.WrapLines(text, dInner - 26, "reading")
		local measured = d.text.GetStringHeight and d.text:GetStringHeight() or 0
		d.body:SetHeight(math.max(L.textLine, lines * L.textLine, type(measured) == "number" and measured or 0))
		-- A new record starts at its top (through the bar, so its thumb does
		-- not keep the last record's place).
		Widgets.ScrollTo(d.scroll, 0)
		fillChips(d, chips, content)
		fillButtons(d, buttons, tabId, item)
		d:Show()
	end

	function section:ApplyTheme(theme)
		self.theme = theme
		self.form:ApplyTheme(theme)
	end

	--- Every item of a tab, newest first. Without tabId: the current tab as
	-- shown (on Review, the current mode: findings, one examined, or answers);
	-- with one: its records (on Review, the open findings, as the tab counts them).
	function section:Items(char, tabId)
		local shown = tabId == nil
		tabId = tabId or self.tab
		local items = {}
		if not char then return items end
		if tabId == "review" then
			-- The rules run once per refresh (Refresh sets reviewFindings);
			-- tab counts, the list, an examined finding and search reuse them.
			local findings = self.reviewFindings or ns.Continuity.Findings(char)
			if shown then
				local reviewItems = ChronicleView.ReviewItems(char, self.reviewMode, self.examineKey, findings)
				if reviewItems then return reviewItems end
				-- The examined finding was answered or resolved: back to the list.
				self.reviewMode, self.examineKey = "open", nil
			end
			return findings
		end
		if tabId == "places" then return ns.Places.List(char) end
		local list = char.story[tabId] or {}
		for i = #list, 1, -1 do items[#items + 1] = list[i] end
		return items
	end

	-- Continuity's rules run once per refresh: the findings are kept for this
	-- refresh only (records may change between refreshes) and reused for the
	-- tab counts, the list, an examined finding and the search filter.
	function section:Refresh(view)
		self.reviewFindings = view.char and ns.Continuity.Findings(view.char) or nil
		self:RefreshContent(view)
		self.reviewFindings = nil
	end

	function section:RefreshContent(view)
		local char = view.char
		local spec = tabSpec(self.tab)
		local now = ns.ctx and ns.ctx.now and ns.ctx.now() or nil
		local theme = Style.Current() -- the theme being painted (a preview included)
		-- The heading over the section names the tab, as in the mockup.
		if SECTION_DEF then SECTION_DEF.heading = spec.label end
		self.tabs:Select(self.tab)
		local counts = {}
		for i, b in ipairs(self.tabButtons) do
			local tab = ChronicleView.TABS[i]
			counts[i] = char and #self:Items(char, tab.id) or 0
			b:SetText(ChronicleView.TabLabel(tab, counts[i], tab.id == self.tab, theme))
		end
		self:LayoutTabs(counts)

		local places = self.tab == "places"
		if places then
			self.places = self.places or ns.ChroniclePlaces.Create(f, L.width, {
				act = act, openForm = function(s) section:OpenForm(s) end })
		end
		if self.places then self.places.frame:SetShown(places) end
		for _, region in ipairs(self.toolbar) do region:SetShown(not places) end
		if places then
			self.detailKey = nil
			self.detail:Hide()
			self.emptyPanel:Hide()
			self.empty:Hide()
			for _, row in ipairs(self.rows) do row:Hide() end
			self.places:Refresh(char, self:Items(char))
			return
		end

		-- Toolbar.
		local review = self.tab == "review"
		self.new:SetShown(spec.new ~= nil or review)
		self.new:SetVariant(review and "default" or "primary")
		if review then
			local answered = char and #char.story.reviews or 0
			self.new:SetText(self.reviewMode == "open" and string.format("Answered  %d", answered) or "<  All findings")
			self.new:SetEnabled(self.reviewMode ~= "open" or answered > 0)
		elseif spec.new then
			self.new:SetText("+  " .. spec.new)
			self.new:SetEnabled(true)
		end
		self.search:ClearAllPoints()
		self.search:SetPoint("TOPLEFT", L.inset + ((spec.new or review) and (L.newWidth + 10) or 0), -L.toolbarTop)
		self.search.placeholder:SetText(spec.search or "Search")
		local all = self:Items(char)
		local items = {}
		for _, item in ipairs(all) do
			if ChronicleView.Matches(self.tab, item, self.query) then items[#items + 1] = item end
		end

		-- Each card sized to its content, then paged by what fits.
		local contents, layouts, heights = {}, {}, {}
		for i, item in ipairs(items) do
			contents[i], layouts[i] = ChronicleView.ItemLayout(self.tab, item, char, now)
			heights[i] = layouts[i].height
		end
		local pageList = ChronicleView.Paginate(heights)
		local pages
		pages, self.page = ChronicleView.Pages(pageList, self.page)
		self.prev:SetEnabled(self.page > 1)
		self.next:SetEnabled(self.page < pages)
		self.pageLabel:SetText(string.format("Page %d of %d", self.page, pages))
		for _, region in ipairs(self.pager) do region:SetShown(pages > 1) end
		local noun = spec.noun[#all == 1 and 1 or 2]
		if review and self.reviewMode == "answered" then noun = #all == 1 and "answer" or "answers" end
		self.count:ClearAllPoints()
		if pages > 1 then
			self.count:SetPoint("RIGHT", self.prev, "LEFT", -10, 0)
		else
			self.count:SetPoint("RIGHT", f, "TOPRIGHT", -L.inset, -(L.toolbarTop + L.toolbarHeight / 2))
		end
		if self.query ~= "" then
			self.count:SetText(string.format("%d of %d %s", #items, #all, spec.noun[2]))
		else
			self.count:SetText(string.format("%s%d %s", self.tab == "review" and "" or "Newest first · ", #all, noun))
		end
		if review and self.reviewMode == "examine" then
			self.count:SetText("Examining one finding")
		elseif review and self.reviewMode == "answered" then
			self.count:SetText(string.format("Newest first · %d %s", #all, noun))
		end

		-- Empty state.
		local empty = ChronicleView.EMPTY[self.tab]
		if review and self.reviewMode == "answered" then empty = ChronicleView.EMPTY.answered end
		self.emptyPanel:SetShown(#items == 0)
		self.empty:SetShown(#items == 0)
		if #all > 0 and #items == 0 then
			self.emptyPanel:SetTitle("No match")
			self.empty:SetText(string.format("Nothing matches \"%s\". Clear the search to see all %d %s.",
				self.query, #all, spec.noun[#all == 1 and 1 or 2]))
		else
			self.emptyPanel:SetTitle(empty[1])
			self.empty:SetText(empty[2])
		end

		local page = pageList[self.page] or {}
		for i, row in ipairs(self.rows) do
			local at = page[i]
			local item = at and items[at.index]
			row:SetShown(item ~= nil)
			row.record = item
			if item then
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", at.x, -(L.gridTop + at.y))
				fillCard(row, contents[at.index], layouts[at.index], self.tab, item)
			end
		end

		-- The full view stays on its record while it exists (an action may
		-- have changed it); it closes when the record is gone.
		local shownItem
		if self.detailKey then
			for _, item in ipairs(all) do
				if itemKey(item) == self.detailKey then shownItem = item end
			end
			if not shownItem then self.detailKey = nil end
		end
		if shownItem then
			self:ShowDetail(self.tab, shownItem, char, now)
		else
			self.detail:Hide()
		end
	end

	ChronicleView.section = section
	return section
end

SECTION_DEF = { id = "chronicle", label = "Chronicle", order = 4, heading = "Memories",
	icon = "Interface\\Icons\\INV_Misc_Map_01", create = create }
MainWindow.RegisterSection(SECTION_DEF)
