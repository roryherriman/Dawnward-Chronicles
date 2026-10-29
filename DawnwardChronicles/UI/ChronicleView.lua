-- Chronicle section: the character's narrative records in the window.
--
--   Memories, Arcs, Goals, Stances, People   records with their provenance,
--       canon status and visibility; New and Edit open a form, so nothing
--       here needs a slash command
--   Places                                   places Dawnward logged; mark
--       one as meaningful, link it as the homeland, or write a memory there
--   Review                                   continuity findings, answered
--       as growth / unreliable / secret / correction / ignore
--
-- Each record takes two lines: its text has the full width on the first,
-- its status and buttons share the second, so they can never overlap (#46).
-- Long lists are paged. Every button calls the same core functions as the
-- chat commands, through Actions.WithCharacter (read-only data refused).
local _, ns = ...
local Widgets, MainWindow, Actions, Records, Forms = ns.Widgets, ns.MainWindow, ns.Actions, ns.Records, ns.Forms

local ChronicleView = {}
ns.ChronicleView = ChronicleView

ChronicleView.TABS = {
	{ id = "memories", label = "Memories", module = "Memories", new = "New memory" },
	{ id = "arcs", label = "Arcs", module = "Arcs", new = "New arc" },
	{ id = "goals", label = "Goals", module = "Goals", new = "New goal" },
	{ id = "identity", label = "Stances", module = "Identity", new = "New stance" },
	{ id = "people", label = "People", module = "People", new = "New person" },
	{ id = "places", label = "Places" },
	{ id = "review", label = "Review" },
}
ChronicleView.REVIEW_CHOICES = { "growth", "unreliable", "secret", "correction", "ignore" }

-- Layout in section units (the v0.7 content area is 772 x 588). Each row is a
-- card; rowPad is its inner margin, and rowHeight includes the gap below it.
ChronicleView.LAYOUT = {
	inset = 8, width = 756,    -- the v0.7 content column (MainWindow.ContentWidth) less the insets
	tabWidth = 104, tabGap = 2, tabHeight = 30,
	rowsTop = 46, rows = 6, rowHeight = 74, rowGap = 8, rowPad = 10,
	statusWidth = 200,         -- a record's status, top right (Places: Homeland, Meaningful)
	textHeight = 34,           -- line 1: the record, two lines of small text
	lineTwo = 36,              -- line 2 starts this far below the row's top
	metaWidth = 210,
	buttons = 5, buttonWidth = 84, buttonHeight = 28, buttonGap = 6,
}
ChronicleView.ROWS = ChronicleView.LAYOUT.rows

--- Rectangles of one row's parts, relative to the row's top-left corner
-- (y grows downwards): { text, meta, buttons = { ... } } with x, y, w, h.
-- Pure: the frames are placed from it, and tests check nothing overlaps.
function ChronicleView.RowRects(L)
	L = L or ChronicleView.LAYOUT
	local pad = L.rowPad or 0
	local out = {
		text = { x = pad, y = 4, w = L.width - 2 * pad, h = L.textHeight - 4 },
		meta = { x = pad, y = L.lineTwo + 3, w = L.metaWidth, h = 14 },
		buttons = {},
	}
	for b = 1, L.buttons do
		local right = L.width - pad + 2 - (b - 1) * (L.buttonWidth + L.buttonGap)
		out.buttons[b] = { x = right - L.buttonWidth, y = L.lineTwo, w = L.buttonWidth, h = L.buttonHeight }
	end
	return out
end

--- Number of pages for n items, and the clamped page. Pure.
function ChronicleView.Pages(n, page)
	local pages = math.max(1, math.ceil(n / ChronicleView.ROWS))
	page = math.min(math.max(page or 1, 1), pages)
	return pages, page
end

local KIND_LABELS = { start = "starting area", town = "town", inn = "inn", farm = "farmstead", road = "road",
	ruins = "ruins", capital = "capital", wilderness = "wilds", danger = "dangerous ground" }

--- Text and status line for a record. Pure: used by tests.
function ChronicleView.RecordText(listId, r, char)
	local body
	if listId == "memories" then
		body = (r.title and (r.title .. ": ") or "") .. (r.text or "")
	elseif listId == "arcs" then
		body = string.format("%s (%s, %s%s)", r.title, r.kind, r.state,
			#r.turningPoints > 0 and string.format(", %d turning point%s", #r.turningPoints,
				#r.turningPoints == 1 and "" or "s") or "")
	elseif listId == "goals" then
		local p = ns.Goals.Progress(char, r)
		local objective = ns.Goals.ObjectiveText(p)
		body = string.format("%s (%s, %d/%d milestones%s)", r.title, r.state, p.milestonesDone, p.milestonesTotal,
			objective and (", " .. objective) or "")
	elseif listId == "identity" then
		body = string.format("%s - in public: %s / privately (%s): %s", r.subject, r.persona or "-",
			r.convictionVisibility, r.conviction or "-")
	elseif listId == "people" then
		body = string.format("%s%s (%s)%s", r.name, r.realm and ("-" .. r.realm) or "", r.kind,
			r.relation and (": " .. r.relation) or "")
	elseif listId == "places" then
		-- Status is shown apart from the actions that change it (third value).
		local flags = {}
		if ns.Places.IsHomeland(char, r) then flags[#flags + 1] = "HOMELAND" end
		if r.meaningful then flags[#flags + 1] = "MEANINGFUL" end
		return ns.Places.Label(r), string.format("%s%d visit%s", r.kind and (KIND_LABELS[r.kind] .. ", ") or "",
			r.visits, r.visits == 1 and "" or "s"), table.concat(flags, "  -  ")
	end
	return body or "", Records.Label(r), ""
end

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

local function placeMemoryForm(place)
	local name = place.subzone or place.zone
	return {
		title = "A memory of " .. ns.Places.Label(place),
		hint = "Write what this place means to your character. The memory is linked to the place.",
		fields = {
			{ key = "title", label = "Title", kind = "line" },
			{ key = "text", label = "Memory", kind = "area" },
		},
		values = { title = name },
		save = function(char, v, now)
			-- Linked by the place's own key, so returning there recalls it (Places.Linked).
			v.zone = place.zone
			v.links = { events = { "place:" .. ns.Places.Key(place.zone, place.subzone) } }
			return ns.Memories.Add(char, v, "player", now)
		end,
	}
end

local function create(parent)
	local L = ChronicleView.LAYOUT
	local section = { frame = CreateFrame("Frame", nil, parent), tab = "memories", page = 1, rows = {},
		tabButtons = {} }
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

	-- Secondary navigation: a segmented control.
	local tabItems = {}
	for i, tab in ipairs(ChronicleView.TABS) do tabItems[i] = { id = tab.id, label = tab.label } end
	section.tabs = Widgets.Segmented(f, tabItems, L.width + L.tabGap * #tabItems, L.tabHeight, function(id)
		section.tab, section.page = id, 1
		section.form:Close()
	end)
	section.tabs.buttons[1]:SetPoint("TOPLEFT", L.inset, -6)
	for i, b in ipairs(section.tabs.buttons) do
		b.tabId = ChronicleView.TABS[i].id
		section.tabButtons[i] = b
	end

	section.empty = Widgets.Label(f, "GameFontHighlight", true, "muted")
	section.empty:SetPoint("TOPLEFT", L.inset, -(L.rowsTop + 8))
	section.empty:SetWidth(L.width)

	local rects = ChronicleView.RowRects(L)
	for i = 1, L.rows do
		local row = Widgets.Card(f)
		row:SetSize(L.width, L.rowHeight - L.rowGap)
		row:SetPoint("TOPLEFT", L.inset, -L.rowsTop - (i - 1) * L.rowHeight)
		row.text = Widgets.Label(row, "GameFontHighlightSmall", true)
		row.text:SetPoint("TOPLEFT", rects.text.x, -rects.text.y)
		row.text:SetSize(rects.text.w, rects.text.h)
		row.status = Widgets.Label(row, "GameFontNormalSmall", false, "accent")
		row.status:SetJustifyH("RIGHT")
		row.status:SetPoint("TOPRIGHT", -L.rowPad, -6)
		row.status:SetWidth(L.statusWidth)
		row.meta = Widgets.Label(row, "GameFontDisableSmall")
		row.meta:SetPoint("TOPLEFT", rects.meta.x, -rects.meta.y)
		row.meta:SetWidth(rects.meta.w)
		row.buttons = {}
		for b, rect in ipairs(rects.buttons) do
			local button = Widgets.Button(row, "", rect.w, rect.h, "ghost")
			button:SetPoint("TOPLEFT", rect.x, -rect.y)
			row.buttons[b] = button
		end
		section.rows[i] = row
	end

	section.prev = Widgets.Button(f, "< Prev", 70, 22, "ghost")
	section.prev:SetPoint("BOTTOMLEFT", L.inset, 8)
	section.prev:SetScript("OnClick", function() section.page = section.page - 1; MainWindow.Refresh() end)
	section.pageLabel = Widgets.Label(f, "GameFontHighlightSmall", false, "muted")
	section.pageLabel:SetPoint("BOTTOMLEFT", L.inset + 78, 13)
	section.next = Widgets.Button(f, "Next >", 70, 22, "ghost")
	section.next:SetPoint("BOTTOMLEFT", L.inset + 150, 8)
	section.next:SetScript("OnClick", function() section.page = section.page + 1; MainWindow.Refresh() end)
	section.new = Widgets.Button(f, "New", 120, 22, "primary")
	section.new:SetPoint("BOTTOMRIGHT", -L.inset, 8)
	section.new:SetScript("OnClick", function() section:OpenForm(FORMS[section.tab]()) end)

	-- Row actions: Remove is destructive, Accept is the one primary action.
	local VARIANTS = { Remove = "danger", Accept = "primary" }

	local function setButton(button, label, fn)
		button:SetShown(label ~= nil)
		if label then
			button:SetText(label)
			button:SetVariant(VARIANTS[label] or "ghost")
			button:SetScript("OnClick", fn)
		end
	end

	-- Buttons, filled from the right: { label, fn } or false to skip.
	-- An entry may give its own width ({ label, fn, width }) for a longer,
	-- clearer label; buttons are laid out from the record's right edge.
	local function fill(row, list)
		local n = 0
		local right = L.width - L.rowPad + 2
		for _, entry in ipairs(list) do
			if entry then
				n = n + 1
				local button, w = row.buttons[n], entry[3] or L.buttonWidth
				setButton(button, entry[1], entry[2])
				button:SetWidth(w)
				button:ClearAllPoints()
				button:SetPoint("TOPLEFT", right - w, -L.lineTwo)
				right = right - w - L.buttonGap
			end
		end
		for b = n + 1, #row.buttons do
			setButton(row.buttons[b], nil)
		end
	end

	local function recordButtons(row, listId, mod, r)
		local m = ns[mod]
		local removable = r.provenance == "player" or r.status == "proposed"
		local list = {
			removable and { "Remove", function()
				Widgets.Confirm("Remove this record?", "Remove", function()
					act(function(char) return m.Remove(char, r.id) end)
				end)
			end },
			{ ns.Themes.VISIBILITY_LABELS[r.visibility] or r.visibility, function()
				act(function(char, now) return m.SetVisibility(char, r.id, CYCLE[r.visibility], now) end)
			end },
			(r.status == "proposed" or r.status == "disputed") and m.Accept and { "Accept", function()
				act(function(char, now) return m.Accept(char, r.id, now) end)
			end } or r.status == "established" and m.Dispute and { "Dispute", function()
				act(function(char, now) return m.Dispute(char, r.id, now) end)
			end } or false,
			{ "Edit", function() section:OpenForm(FORMS[listId](r)) end },
		}
		if listId == "arcs" then
			list[#list + 1] = { "Turn", function() section:OpenForm(turningPointForm(r)) end }
		elseif listId == "goals" then
			list[#list + 1] = { "Steps", function() section:OpenForm(milestoneForm(r)) end }
		elseif listId == "identity" then
			list[#list + 1] = { "Inner: " .. r.convictionVisibility:sub(1, 3), function()
				act(function(char, now) return ns.Identity.SetConvictionVisibility(char, r.id,
					CYCLE[r.convictionVisibility], now) end)
			end }
		end
		fill(row, list)
	end

	local function placeButtons(row, entry, char)
		local name = entry.subzone or entry.zone
		-- Act on this row's place, looked up by its exact key, never by name.
		local function this(c)
			local place = ns.Places.Entry(c, entry.zone, entry.subzone)
			if not place then return nil, "that place is no longer logged" end
			return place
		end
		fill(row, {
			{ "Write memory", function() section:OpenForm(placeMemoryForm(entry)) end, 112 },
			not ns.Places.IsHomeland(char, entry) and { "Set as homeland", function()
				Widgets.Confirm(string.format("Set your Homeland to %s? This replaces the Homeland on your "
					.. "profile; its visibility stays as it is.", name), "Set", function()
					act(function(c, now)
						local place, err = this(c)
						if not place then return nil, err end
						return ns.Places.SetHomeland(c, place, now)
					end)
				end)
			end, 132 } or false,
			{ entry.meaningful and "Unmark meaningful" or "Mark meaningful", function()
				act(function(c)
					local place, err = this(c)
					if not place then return nil, err end
					place.meaningful = (not place.meaningful) or nil
					return place
				end)
			end, 144 },
		})
	end

	function section:ApplyTheme(theme)
		self.theme = theme
		self.form:ApplyTheme(theme)
		for _, row in ipairs(self.rows) do
			Widgets.TextColor(row.text, theme.text)
			Widgets.TextColor(row.meta, theme.muted)
		end
	end

	local EMPTY = {
		review = "Nothing to review: your story is consistent as far as Dawnward can tell.",
		places = "No places logged yet. Dawnward notes towns, inns and other places as you travel.",
	}

	function section:Items(char)
		local items = {}
		if not char then return items end
		if self.tab == "review" then return ns.Continuity.Findings(char) end
		if self.tab == "places" then return ns.Places.List(char) end
		local list = char.story[self.tab] or {}
		for i = #list, 1, -1 do items[#items + 1] = list[i] end
		return items
	end

	function section:Refresh(view)
		local char = view.char
		self.tabs:Select(self.tab)
		local spec
		for _, tab in ipairs(ChronicleView.TABS) do
			if tab.id == self.tab then spec = tab end
		end
		self.new:SetShown(spec.new ~= nil)
		if spec.new then self.new:SetText(spec.new) end
		local items = self:Items(char)
		local pages
		pages, self.page = ChronicleView.Pages(#items, self.page)
		self.prev:SetEnabled(self.page > 1)
		self.next:SetEnabled(self.page < pages)
		self.pageLabel:SetText(string.format("Page %d of %d", self.page, pages))
		self.empty:SetShown(#items == 0)
		self.empty:SetText(EMPTY[self.tab] or "Nothing here yet. Use the button below to add the first one.")
		local offset = (self.page - 1) * L.rows
		for i, row in ipairs(self.rows) do
			local item = items[offset + i]
			row:SetShown(item ~= nil)
			if item and self.tab == "review" then
				row.status:SetText("")
				row.text:SetWidth(rects.text.w)
				row.text:SetText(item.message)
				row.meta:SetText("What is it?")
				local list = {}
				for b = #ChronicleView.REVIEW_CHOICES, 1, -1 do
					-- Filled from the right, so the choices read in order.
					local choice = ChronicleView.REVIEW_CHOICES[b]
					list[#list + 1] = { choice, function()
						act(function(c, now) return ns.Continuity.Review(c, item.key, choice, nil, now) end)
					end }
				end
				fill(row, list)
			elseif item then
				local text, meta, status = ChronicleView.RecordText(self.tab, item, char)
				-- The status (Places: Homeland, Meaningful) sits top right, apart
				-- from the buttons below that change it; the text makes room for it.
				row.status:SetText(status or "")
				row.text:SetWidth(status and status ~= "" and rects.text.w - L.statusWidth - 8 or rects.text.w)
				row.text:SetText(text)
				row.meta:SetText(meta)
				if self.tab == "places" then
					placeButtons(row, item, char)
				else
					recordButtons(row, self.tab, spec.module, item)
				end
			end
		end
	end

	ChronicleView.section = section
	return section
end

MainWindow.RegisterSection({ id = "chronicle", label = "Chronicle", order = 4, heading = "Chronicle",
	icon = "Interface\\Icons\\INV_Misc_Map_01", create = create })
