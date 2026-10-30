-- Chronicle section: the character's narrative records in the window
-- (v0.7, docs/design/mockups/chronicle-memories.png and chronicle-places.png).
--
--   Memories, Arcs, Goals, Stances, People   records as cards in a two-column
--       grid: a status chip and the date on top, the title, a meta line, the
--       wrapped text, chips (where it came from, canon status, visibility;
--       the visibility chip is a button that cycles it), a goal's progress
--       from its real milestones or verified objective, and the record's
--       actions in a row at the bottom (Remove on the right). New and Edit
--       open a form, so nothing here needs a slash command. A search box
--       filters the current tab.
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
-- pool and long lists are paged, so a refresh creates no frames.
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

-- Layout in section units (the v0.7 content area is 772 x 588, the mockup's
-- main column). Tabs on top, a toolbar (New, search, count, pager) below
-- them, then a 2 x 2 grid of cards.
ChronicleView.LAYOUT = {
	inset = 0, width = 772,
	tabHeight = 34, tabGap = 4, tabPad = 3,
	toolbarTop = 50, toolbarHeight = 30, searchWidth = 240, newWidth = 150,
	gridTop = 96, cols = 2, gridRows = 2, colGap = 14, rowGap = 12,
	cardWidth = 379, cardHeight = 240, cardPad = 14, dateWidth = 90, chips = 4,
	buttons = 5, buttonHeight = 26, buttonGap = 6,
}
ChronicleView.ROWS = ChronicleView.LAYOUT.cols * ChronicleView.LAYOUT.gridRows

-- Button widths by label (the rest: 64). Long enough for each label.
ChronicleView.BUTTON_WIDTHS = { Accept = 68, Edit = 56, Dispute = 68, Remove = 72, Turn = 58, Steps = 60,
	Growth = 62, Unreliable = 78, Secret = 58, ["Correct it"] = 76, Ignore = 56, ["Explain..."] = 80,
	["Undo answer"] = 96 }
-- The Examine button at a finding card's top right (where a record's date sits).
ChronicleView.EXAMINE_RECT = { w = 80, h = 22, y = 9 }

--- Rectangles of one card's parts, relative to its top-left corner (y grows
-- downwards), with x, y, w, h. opts: { title, meta, progress } say which
-- optional parts the card shows. Pure: the frames are placed from it, and
-- tests check nothing overlaps.
function ChronicleView.CardRects(opts, L)
	L = L or ChronicleView.LAYOUT
	opts = opts or {}
	local pad, w = L.cardPad, L.cardWidth
	local inner = w - 2 * pad
	local r = {
		chip = { x = pad, y = 12, w = inner - L.dateWidth - 8, h = 20 },
		date = { x = w - pad - L.dateWidth, y = 15, w = L.dateWidth, h = 14 },
	}
	local y = 40
	if opts.title then r.title = { x = pad, y = y, w = inner, h = 20 }; y = y + 24 end
	if opts.meta then r.meta = { x = pad, y = y, w = inner, h = 14 }; y = y + 18 end
	local textBottom = opts.progress and 152 or 160
	r.text = { x = pad, y = y, w = inner, h = textBottom - y }
	if opts.progress then r.progress = { x = pad, y = 156, w = inner, h = 4 } end
	r.chips = { x = pad, y = 166, w = inner, h = 20 }
	r.divider = { x = pad, y = 195, w = inner, h = 1 }
	r.buttons = { x = pad, y = 202, w = inner, h = L.buttonHeight }
	return r
end

--- Top-left corner of card i (1-based) in the section. Pure.
function ChronicleView.CardOrigin(i, L)
	L = L or ChronicleView.LAYOUT
	local col, row = (i - 1) % L.cols, math.floor((i - 1) / L.cols)
	return L.inset + col * (L.cardWidth + L.colGap), L.gridTop + row * (L.cardHeight + L.rowGap)
end

--- Number of pages for n items, and the clamped page. Pure.
function ChronicleView.Pages(n, page)
	local pages = math.max(1, math.ceil(n / ChronicleView.ROWS))
	page = math.min(math.max(page or 1, 1), pages)
	return pages, page
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
		c.chip, c.highlight = { "Suggested · needs your call", "accent" }, true
	elseif r.status == "disputed" then
		c.chip, c.highlight = { "Disputed · needs your call", "danger" }, true
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

local function place(region, rect)
	region:ClearAllPoints()
	region:SetPoint("TOPLEFT", rect.x, -rect.y)
	region:SetWidth(rect.w)
	if rect.h then region:SetHeight(rect.h) end
end

local function tabSpec(id)
	for _, tab in ipairs(ChronicleView.TABS) do
		if tab.id == id then return tab end
	end
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

	-- Secondary navigation: a segmented control on a panel bar, each tab
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
		section.form:Close()
		-- Before the refresh, which draws the heading first.
		if SECTION_DEF then SECTION_DEF.heading = tabSpec(id).label end
		MainWindow.Refresh()
	end)
	local barWidth = L.tabPad
	for i, b in ipairs(section.tabs.buttons) do
		local tab = ChronicleView.TABS[i]
		b.tabId = tab.id
		b:SetWidth(tab.width)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", L.inset + barWidth, -L.tabPad)
		barWidth = barWidth + tab.width + L.tabGap
		section.tabButtons[i] = b
	end
	section.tabBar:SetPoint("TOPLEFT", L.inset, 0)
	section.tabBar:SetSize(barWidth - L.tabGap + L.tabPad, L.tabHeight)

	-- Toolbar: New, search, count and pager.
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
	end)
	section.search:SetHeight(L.toolbarHeight)
	section.next = Widgets.Button(f, ">", 26, 24, "ghost")
	section.next:SetPoint("TOPRIGHT", -L.inset, barY - 3)
	section.next:SetScript("OnClick", function() section.page = section.page + 1; MainWindow.Refresh() end)
	Widgets.Tooltip(section.next, "Next page")
	section.pageLabel = Widgets.Label(f, "GameFontHighlightSmall", false, "muted")
	section.pageLabel:SetJustifyH("CENTER")
	section.pageLabel:SetWidth(84)
	section.pageLabel:SetPoint("RIGHT", section.next, "LEFT", -4, 0)
	section.prev = Widgets.Button(f, "<", 26, 24, "ghost")
	section.prev:SetPoint("RIGHT", section.pageLabel, "LEFT", -4, 0)
	section.prev:SetScript("OnClick", function() section.page = section.page - 1; MainWindow.Refresh() end)
	Widgets.Tooltip(section.prev, "Previous page")
	section.count = Widgets.Label(f, "GameFontHighlightSmall", false, "muted")
	section.count:SetJustifyH("RIGHT")
	section.count:SetWidth(200)
	section.toolbar = { section.new, section.search, section.prev, section.pageLabel, section.next, section.count }

	-- Empty state: what the tab holds and how to fill it.
	section.emptyPanel = Widgets.Panel(f, "Nothing here yet")
	section.emptyPanel:SetPoint("TOPLEFT", L.inset, -L.gridTop)
	section.emptyPanel:SetSize(L.width, 110)
	section.empty = Widgets.Label(section.emptyPanel.inner, "GameFontHighlight", true, "body")
	section.empty:SetPoint("TOPLEFT", 0, 0)
	section.empty:SetWidth(L.width - 2 * Widgets.PANEL_PAD)

	-- The card pool.
	for i = 1, ChronicleView.ROWS do
		local row = Widgets.Card(f)
		row:SetSize(L.cardWidth, L.cardHeight)
		local x, y = ChronicleView.CardOrigin(i)
		row:SetPoint("TOPLEFT", x, -y)
		row.chip = Widgets.Chip(row, "", "muted")
		row.date = Widgets.Label(row, "GameFontHighlightSmall", false, "muted")
		row.date:SetJustifyH("RIGHT")
		row.title = Widgets.Label(row, "GameFontHighlightLarge", false, "body")
		-- One line, so a long title is cut with "..."; hovering shows it whole.
		row.titleHover = CreateFrame("Frame", nil, row)
		Widgets.Tooltip(row.titleHover, "", nil)
		-- Hovering the title still highlights its card.
		row.titleHover:HookScript("OnEnter", function() row:SetRowHover(true) end)
		row.titleHover:HookScript("OnLeave", function() row:SetRowHover(false) end)
		row.meta = Widgets.Label(row, "GameFontHighlightSmall", false, "muted")
		row.text = Widgets.Label(row, "GameFontHighlight", true, "body")
		row.progress = Widgets.ProgressBar(row, L.cardWidth - 2 * L.cardPad, 4)
		row.chips = {}
		for c = 1, L.chips do row.chips[c] = Widgets.Chip(row, "", "muted") end
		row.vis = Widgets.VisibilityButton(row, function(level)
			if row.onVisibility then row.onVisibility(level) end
		end)
		row.divider = Widgets.Divider(row)
		-- Review findings only: Examine, where a record card shows its date.
		local er = ChronicleView.EXAMINE_RECT
		row.examine = Widgets.Button(row, "Examine", er.w, er.h, "default")
		row.examine:SetPoint("TOPLEFT", L.cardWidth - L.cardPad - er.w, -er.y)
		Widgets.Tooltip(row.examine, "Examine", ChronicleView.EXAMINE_HELP)
		row.examine:Hide()
		row.actions = {}
		row.buttons = {}
		for b = 1, L.buttons do
			local button = Widgets.Button(row, "", 64, L.buttonHeight, "ghost")
			row.actions[b] = button
			row.buttons[b] = button
		end
		-- The visibility chip is one of the record's buttons too.
		row.buttons[#row.buttons + 1] = row.vis
		section.rows[i] = row
	end

	-- Row actions: Remove is destructive, Accept the one primary action,
	-- Edit the usual one; the rest are quiet.
	local VARIANTS = { Remove = "danger", Accept = "primary", Edit = "default" }

	local function setButton(button, label, fn)
		button:SetShown(label ~= nil)
		if label then
			button:SetText(label)
			button:SetVariant(VARIANTS[label] or "ghost")
			button:SetScript("OnClick", fn)
			button:SetWidth(ChronicleView.BUTTON_WIDTHS[label] or (label:sub(1, 6) == "Inner:" and 84) or 64)
		end
	end

	-- Buttons left to right, { label, fn } or false to skip; right = { label,
	-- fn } sits alone at the card's right edge (Remove).
	local function fill(row, list, right)
		local rect = ChronicleView.CardRects().buttons
		local n, x = 0, rect.x
		for _, entry in ipairs(list) do
			if entry then
				n = n + 1
				local button = row.actions[n]
				setButton(button, entry[1], entry[2])
				button:ClearAllPoints()
				button:SetPoint("TOPLEFT", x, -rect.y)
				x = x + button:GetWidth() + L.buttonGap
			end
		end
		if right then
			n = n + 1
			local button = row.actions[n]
			setButton(button, right[1], right[2])
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", rect.x + rect.w - button:GetWidth(), -rect.y)
		end
		for b = n + 1, #row.actions do
			setButton(row.actions[b], nil)
		end
	end

	local function recordButtons(row, listId, mod, r)
		local m = ns[mod]
		local removable = r.provenance == "player" or r.status == "proposed"
		local list = {
			(r.status == "proposed" or r.status == "disputed") and m.Accept and { "Accept", function()
				act(function(char, now) return m.Accept(char, r.id, now) end)
			end } or false,
			{ "Edit", function() section:OpenForm(ChronicleView.FORMS[listId](r)) end },
			r.status == "established" and m.Dispute and { "Dispute", function()
				act(function(char, now) return m.Dispute(char, r.id, now) end)
			end } or false,
		}
		if listId == "arcs" then
			list[#list + 1] = { "Turn", function() section:OpenForm(ChronicleView.TurningPointForm(r)) end }
		elseif listId == "goals" then
			list[#list + 1] = { "Steps", function() section:OpenForm(ChronicleView.MilestoneForm(r)) end }
		elseif listId == "identity" then
			list[#list + 1] = { "Inner: " .. r.convictionVisibility:sub(1, 3), function()
				act(function(char, now) return ns.Identity.SetConvictionVisibility(char, r.id,
					ChronicleView.CYCLE[r.convictionVisibility], now) end)
			end }
		end
		fill(row, list, removable and { "Remove", function()
			Widgets.Confirm("Remove this record?", "Remove", function()
				act(function(char) return m.Remove(char, r.id) end)
			end)
		end } or nil)
		row.onVisibility = function(level)
			act(function(char, now) return m.SetVisibility(char, r.id, level, now) end)
		end
	end

	-- A Review card's buttons: the five answers on a finding; Edit (and a
	-- goal's Steps) on an examined record; Explain; Undo answer.
	local function reviewButtons(row, item)
		local kind = item.reviewKind
		if kind == "side" then
			local side = item.side
			local list = {}
			if side.editable and not side.missing and ChronicleView.FORMS[side.list] then
				list[#list + 1] = { "Edit", function() section:OpenForm(ChronicleView.FORMS[side.list](side.record)) end }
				if side.list == "goals" then
					list[#list + 1] = { "Steps", function() section:OpenForm(ChronicleView.MilestoneForm(side.record)) end }
				end
			end
			fill(row, list)
			if list[1] then Widgets.Tooltip(row.actions[1], "Edit", "Correct this record yourself, in its own form.") end
			return
		elseif kind == "explain" then
			fill(row, { { "Explain...", function() section:OpenForm(ChronicleView.ExplainForm(item.finding)) end } })
			row.actions[1]:SetVariant("default")
			Widgets.Tooltip(row.actions[1], "Explain", ChronicleView.REVIEW_HELP.explained)
			return
		elseif kind == "answered" then
			fill(row, { { "Undo answer", function()
				act(function(c) return ns.Continuity.Undo(c, item.key) end)
			end } })
			row.actions[1]:SetVariant("default")
			Widgets.Tooltip(row.actions[1], "Undo answer", ChronicleView.UNDO_HELP)
			return
		end
		local list = {}
		for _, choice in ipairs(ChronicleView.REVIEW_CHOICES) do
			list[#list + 1] = { ChronicleView.REVIEW_LABELS[choice], function()
				act(function(c, now2) return ns.Continuity.Review(c, item.key, choice, nil, now2) end)
			end }
		end
		fill(row, list)
		-- Answers are real buttons (filled, with an edge), each explained.
		for b, choice in ipairs(ChronicleView.REVIEW_CHOICES) do
			row.actions[b]:SetVariant("default")
			Widgets.Tooltip(row.actions[b], ChronicleView.REVIEW_LABELS[choice], ChronicleView.REVIEW_HELP[choice])
		end
		row.examine:SetScript("OnClick", function()
			section.reviewMode, section.examineKey, section.page = "examine", item.key, 1
			MainWindow.Refresh()
		end)
	end

	-- Chips left to right; one that would not fit (with the visibility
	-- chip after it) is left out rather than overlapping.
	local function layoutChips(row, list, withVis)
		local rect = ChronicleView.CardRects().chips
		local x, limit = rect.x, rect.x + rect.w - (withVis and (row.vis:GetWidth() + 6) or 0)
		for c, chip in ipairs(row.chips) do
			local spec = list[c]
			local shown = false
			if spec then
				chip:SetChip(spec[1], spec[2])
				if x + chip:GetWidth() <= limit then
					chip:ClearAllPoints()
					chip:SetPoint("TOPLEFT", x, -rect.y)
					x = x + chip:GetWidth() + 6
					shown = true
				end
			end
			chip:SetShown(shown)
		end
		row.vis:SetShown(withVis)
		if withVis then
			row.vis:ClearAllPoints()
			row.vis:SetPoint("TOPLEFT", x, -rect.y)
		end
	end

	local function fillCard(row, content)
		local rects = ChronicleView.CardRects({ title = content.title ~= nil, meta = content.meta ~= nil,
			progress = content.progress ~= nil })
		row.chip:SetShown(content.chip ~= nil)
		if content.chip then
			row.chip:SetChip(content.chip[1], content.chip[2])
			row.chip:ClearAllPoints()
			row.chip:SetPoint("TOPLEFT", rects.chip.x, -rects.chip.y)
		end
		place(row.date, rects.date)
		row.date:SetText(content.date or "")
		row.title:SetShown(content.title ~= nil)
		row.titleHover:SetShown(content.title ~= nil)
		if content.title then
			place(row.title, rects.title)
			row.title:SetText(content.title)
			place(row.titleHover, rects.title)
			Widgets.Tooltip(row.titleHover, content.title, content.meta)
		end
		row.meta:SetShown(content.meta ~= nil)
		if content.meta then place(row.meta, rects.meta); row.meta:SetText(content.meta) end
		place(row.text, rects.text)
		row.text:SetText(content.text or "")
		row.progress:SetShown(content.progress ~= nil)
		if content.progress then
			place(row.progress, rects.progress)
			row.progress:SetValue(content.progress)
		end
		place(row.divider, rects.divider)
		row.highlight = content.highlight or nil
		Style.Repaint(row)
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
		-- The heading over the section names the tab, as in the mockup.
		if SECTION_DEF then SECTION_DEF.heading = spec.label end
		self.tabs:Select(self.tab)
		for i, b in ipairs(self.tabButtons) do
			local tab = ChronicleView.TABS[i]
			local n = char and #self:Items(char, tab.id) or 0
			b:SetText(n > 0 and string.format("%s  %d", tab.label, n) or tab.label)
		end

		local places = self.tab == "places"
		if places then
			self.places = self.places or ns.ChroniclePlaces.Create(f, L.width, {
				act = act, openForm = function(s) section:OpenForm(s) end })
		end
		if self.places then self.places.frame:SetShown(places) end
		for _, region in ipairs(self.toolbar) do region:SetShown(not places) end
		if places then
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
		local pages
		pages, self.page = ChronicleView.Pages(#items, self.page)
		self.prev:SetEnabled(self.page > 1)
		self.next:SetEnabled(self.page < pages)
		self.pageLabel:SetText(string.format("Page %d of %d", self.page, pages))
		local noun = spec.noun[#all == 1 and 1 or 2]
		if review and self.reviewMode == "answered" then noun = #all == 1 and "answer" or "answers" end
		self.count:ClearAllPoints()
		self.count:SetPoint("RIGHT", self.prev, "LEFT", -10, 0)
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

		local offset = (self.page - 1) * ChronicleView.ROWS
		for i, row in ipairs(self.rows) do
			local item = items[offset + i]
			row:SetShown(item ~= nil)
			row.record = item
			if item then
				local content = ChronicleView.CardContent(self.tab, item, char, now)
				fillCard(row, content)
				row.examine:SetShown(self.tab == "review" and item.reviewKind == nil)
				if self.tab == "review" then
					reviewButtons(row, item)
					row.onVisibility = nil
					layoutChips(row, content.chips, false)
				else
					recordButtons(row, self.tab, spec.module, item)
					row.vis:SetLevel(item.visibility)
					layoutChips(row, content.chips, true)
				end
			end
		end
	end

	ChronicleView.section = section
	return section
end

SECTION_DEF = { id = "chronicle", label = "Chronicle", order = 4, heading = "Memories",
	icon = "Interface\\Icons\\INV_Misc_Map_01", create = create }
MainWindow.RegisterSection(SECTION_DEF)
