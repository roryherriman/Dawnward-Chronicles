-- Chronicle > Places: the approved list-and-detail layout (v0.7,
-- docs/design/mockups/chronicle-places.png).
--
--   left    the places Dawnward logged, most recently visited first: name,
--           zone and kind, an icon for the Homeland or a meaningful place,
--           and the visit count. Paged; click one to select it.
--   right   the selected place: zone, kind, first visit, what it means to
--           the character (Homeland, marked meaningful, tied memories),
--           visits, last visit, when a return there can next become a
--           moment (read-only, Places.ReturnCheck), the tied memories, and
--           the actions: write a memory here, mark or unmark it as
--           meaningful, set it as the homeland (after confirmation).
--
-- Everything shown is the character's own logged data; nothing is
-- classified from a place's name. Every write goes through the section's
-- act(), i.e. Actions.WithCharacter.
local _, ns = ...
local Widgets, Style = ns.Widgets, ns.Style

local ChroniclePlaces = {}
ns.ChroniclePlaces = ChroniclePlaces

-- Section units (the Chronicle content area is 772 x 588; this view starts
-- below the tabs, ChroniclePlaces.dc.html). The detail is laid out top to
-- bottom from its content (DetailLayout): chips wrap, the note and the stat
-- tiles grow with their text, and the tied memories take the room left
-- above the actions.
ChroniclePlaces.LAYOUT = {
	top = 54, listWidth = 300, gap = 16, height = 534,
	listPad = 8, rowHeight = 54, rowGap = 4, rows = 8, pagerHeight = 30,
	detailPad = 20, nameHeight = 34, subHeight = 20, eyebrowHeight = 16, chipGap = 8,
	noteLine = 18, noteLines = 3, statMin = 70, statGap = 10, statPad = 12, statLabelLine = 16, statValueLine = 20,
	tied = 4, tiedHeight = 36, tiedGap = 6, buttonHeight = 36, buttonGap = 8,
}

-- Icons (Classic has no line icons; small textures instead, see
-- UI_DESIGN_V07.md section 3). The raid-target star is the client's own
-- texture (Blizzard_ChatFrameBase/Shared/ChatFrameConstants.lua,
-- "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1").
-- The Hearthstone icon marks the Homeland (in-game check: docs/TESTING.md).
ChroniclePlaces.ICONS = {
	homeland = "Interface\\Icons\\INV_Misc_Rune_01",
	meaningful = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",
}

ChroniclePlaces.UNMAPPED = "not yet mapped"

--- Short date: "Today", "28 Oct", or "28 Oct 2025" in another year; nil when unknown. Pure.
function ChroniclePlaces.ShortDate(timestamp, now)
	if type(timestamp) ~= "number" or timestamp <= 0 then return nil end
	if now and date("%Y%m%d", timestamp) == date("%Y%m%d", now) then return "Today" end
	local text = tostring(tonumber(date("%d", timestamp))) .. " " .. date("%b", timestamp)
	if now and date("%Y", timestamp) ~= date("%Y", now) then
		text = text .. " " .. date("%Y", timestamp)
	end
	return text
end

--- The name a list row shows, and its second line ("Elwynn Forest · settlement"). Pure.
function ChroniclePlaces.Lines(entry)
	local kind = entry.kind and ns.Places.KIND_LABELS[entry.kind] or ChroniclePlaces.UNMAPPED
	if entry.subzone then
		return entry.subzone, entry.zone .. " · " .. kind
	end
	return entry.zone, kind
end

function ChroniclePlaces.VisitText(n)
	return string.format("%d visit%s", n or 0, n == 1 and "" or "s")
end

--- Memories tied to a logged place, newest first: written there from this
-- view (linked by the place's key), suggested from an event there, or (for
-- a whole zone) naming the zone. Like Places.Linked, but every status
-- except superseded, so a suggestion waiting for an answer shows too. Pure.
function ChroniclePlaces.TiedMemories(story, entry)
	local placeKey = "place:" .. ns.Places.Key(entry.zone, entry.subzone)
	local out = {}
	local memories = story.memories or {}
	for i = #memories, 1, -1 do
		local m = memories[i]
		if m.status ~= "superseded" then
			local tied = not entry.subzone and m.zone == entry.zone
			for _, k in ipairs(not tied and m.links and m.links.events or {}) do
				if k == placeKey or (not entry.subzone and k == "zone:" .. entry.zone) then
					tied = true
				else
					local e = ns.GameEvents.Find({ story = story }, k)
					if e and e.zone == entry.zone and (not entry.subzone or e.subzone == entry.subzone) then
						tied = true
					end
				end
				if tied then break end
			end
			if tied then out[#out + 1] = m end
		end
	end
	return out
end

-- Play time in words: "45 min", "2 h 10 min".
local function playTime(seconds)
	seconds = math.max(0, math.floor(seconds or 0))
	local h, m = math.floor(seconds / 3600), math.floor((seconds % 3600) / 60)
	if h == 0 then return math.max(1, m) .. " min" end
	if m == 0 then return h .. " h" end
	return string.format("%d h %d min", h, m)
end

--- When a return to this place can next become a moment, in words, from
-- Places.ReturnCheck (ok, why, info). Pure.
function ChroniclePlaces.ReturnText(ok, why, info)
	info = info or {}
	if ok then return "Your next visit can count" end
	if why == "away" then return "After " .. playTime(info.wait) .. " more play away" end
	if why == "weekly" then return "After " .. playTime(info.wait) .. " more play" end
	if why == "new" then return "Counting from your next visit" end
	if why == "ordinary" then return "Only once it is tied to your story" end
	return "Not known yet"
end

local IMPORTANCE = { "Ordinary", "Notable", "Defining" }
local STATUS = { proposed = "Suggested", disputed = "Disputed", established = "Established" }

--- A tied memory's name (its title, or the start of its text) and status. Pure.
function ChroniclePlaces.MemoryParts(m)
	local name = m.title or (m.text and (#m.text > 48 and (m.text:sub(1, 45) .. "...") or m.text)) or "A memory"
	local note = m.status == "established" and IMPORTANCE[m.importance or 1] or STATUS[m.status] or m.status
	return name, note
end

--- One tied memory's line: its title (or the start of its text) and a status. Pure.
function ChroniclePlaces.MemoryLine(m)
	local name, note = ChroniclePlaces.MemoryParts(m)
	return name .. "  ·  " .. note
end

ChroniclePlaces.ACTIONS = { "Write a memory here", "Unmark meaningful", "Set as homeland" }

--- Widths of the three actions in inner (the longest label of each), with
-- as much padding as fits (16 at most), never less than the button's own
-- inset. Pure.
function ChroniclePlaces.ActionWidths(inner, L)
	L = L or ChroniclePlaces.LAYOUT
	local text, total = {}, 0
	for i, label in ipairs(ChroniclePlaces.ACTIONS) do
		text[i] = math.ceil(Style.TextWidth(label, Widgets.ButtonFontStyle(L.buttonHeight)))
		total = total + text[i]
	end
	local free = inner - total - L.buttonGap * (#text - 1)
	local pad = math.max(Widgets.BUTTON.inset, math.min(16, math.floor(free / (2 * #text))))
	local out = {}
	for i, w in ipairs(text) do out[i] = w + 2 * pad end
	return out
end

local function wrapLines(text, width, style)
	return ns.ChronicleView.WrapLines(text, width, style)
end

--- Where the detail's parts go for its content, relative to the panel's
-- top-left (y downwards): info = { chips = { text }, note, stats = { { label,
-- value } }, tied = number of tied memories }. Returns the rectangles, the
-- chip positions, the stat tiles' common height and how many tied memories
-- fit above the actions (shown). Pure.
function ChroniclePlaces.DetailLayout(info, width, L)
	L = L or ChroniclePlaces.LAYOUT
	local P = L.detailPad
	local inner = width - 2 * P
	local r = { inner = inner, chips = {} }
	local y = P
	r.name = { x = P, y = y, w = inner, h = L.nameHeight }
	y = y + L.nameHeight + 4
	r.sub = { x = P, y = y, w = inner, h = L.subHeight }
	y = y + L.subHeight + 12
	r.means = { x = P, y = y, w = inner, h = L.eyebrowHeight }
	y = y + L.eyebrowHeight + 10
	local x, chipH = 0, Widgets.CHIP_HEIGHT
	for i, text in ipairs(info.chips or {}) do
		local w = math.min(inner, ns.ChronicleView.ChipWidth(text))
		if x > 0 and x + w > inner then x, y = 0, y + chipH + L.chipGap end
		r.chips[i] = { x = P + x, y = y, w = w, h = chipH }
		x = x + w + L.chipGap
	end
	y = y + chipH + 12
	local noteLines = math.max(1, math.min(L.noteLines, wrapLines(info.note, inner, "meta")))
	r.note = { x = P, y = y, w = inner, h = noteLines * L.noteLine, lines = noteLines }
	y = y + r.note.h + 14
	local statW = math.floor((inner - 2 * L.statGap) / 3)
	local statH = L.statMin
	local textW = statW - 2 * L.statPad
	for _, stat in ipairs(info.stats or {}) do
		local h = L.statPad + math.max(1, wrapLines(stat[1]:upper(), textW, "eyebrow")) * L.statLabelLine + 6
			+ math.max(1, wrapLines(stat[2], textW, "reading")) * L.statValueLine + L.statPad
		statH = math.max(statH, h)
	end
	r.stats = {}
	for i = 1, 3 do
		r.stats[i] = { x = P + (i - 1) * (statW + L.statGap), y = y, w = statW, h = statH }
	end
	y = y + statH + 18
	r.tiedLabel = { x = P, y = y, w = inner, h = L.eyebrowHeight }
	y = y + L.eyebrowHeight + 8
	-- From the bottom: the actions, then the divider above them.
	r.buttons = { x = P, y = L.height - P - L.buttonHeight, w = inner, h = L.buttonHeight }
	r.divider = { x = P, y = r.buttons.y - 14, w = inner, h = 1 }
	local room = r.divider.y - 8 - y
	local moreH = 18
	local step = L.tiedHeight + L.tiedGap
	local n = info.tied or 0
	local shown = math.min(n, L.tied, math.max(0, math.floor((room + L.tiedGap) / step)))
	if shown < n then
		-- Leave room for "and N more in Memories".
		shown = math.min(shown, math.max(0, math.floor((room - moreH + L.tiedGap) / step)))
	end
	r.shown = shown
	r.tied = {}
	for i = 1, L.tied do
		r.tied[i] = { x = P, y = y + (i - 1) * step, w = inner, h = L.tiedHeight }
	end
	r.more = { x = P, y = y + shown * step, w = inner, h = moreH }
	r.tiedEmpty = { x = P, y = y, w = inner, h = 2 * L.noteLine }
	return r
end

-- A selectable list row (a button painted like an entry card): an icon
-- for the Homeland or a meaningful place, the name (17) over zone · kind
-- (14, muted), the visits on the right. Hovering shows the full name and
-- line, which a narrow list may cut.
local function listRow(parent, L)
	local row = CreateFrame("Button", nil, parent)
	local w = L.listWidth - 2 * L.listPad
	row:SetSize(w, L.rowHeight)
	row.bg = Style.Solid(row, "BACKGROUND")
	row.bg:SetAllPoints(row)
	row.edges = Style.Edge(row, "BORDER")
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(20, 20)
	row.icon:SetPoint("LEFT", 12, 0)
	row.name = Widgets.Label(row, "nav", false, "body")
	row.name:SetPoint("TOPLEFT", 42, -8)
	row.name:SetWidth(w - 42 - 72)
	row.sub = Widgets.Label(row, "meta", false, "muted")
	row.sub:SetPoint("TOPLEFT", 42, -30)
	row.sub:SetWidth(w - 42 - 72)
	row.visits = Widgets.Label(row, "meta", false, "muted")
	row.visits:SetJustifyH("RIGHT")
	row.visits:SetPoint("RIGHT", -12, 0)
	row.visits:SetWidth(64)
	row:SetScript("OnEnter", function(self) self.hover = true; Style.Repaint(self) end)
	row:SetScript("OnLeave", function(self) self.hover = nil; Style.Repaint(self) end)
	Widgets.Tooltip(row, nil)
	Style.Register(row, function(r, theme)
		local tones = Style.Tones(theme)
		Style.Color(r.bg, r.selected and theme.surfaceHover or tones.cardHover, (r.selected or r.hover) and 1 or 0)
		r.edges:Paint(r.selected and (theme.border or theme.accent) or tones.selectedEdge,
			(r.selected or r.hover) and 1 or 0)
	end)
	return row
end

-- A stat tile: a small eyebrow (wrapping, as "Next return moment" does)
-- over a value.
local function statTile(parent, label, L)
	local tile = CreateFrame("Frame", nil, parent)
	tile.bg = Style.Solid(tile, "BACKGROUND", -1)
	tile.bg:SetAllPoints(tile)
	tile.edges = Style.Edge(tile, "BORDER")
	tile.label = Widgets.Label(tile, nil, true, "eyebrow")
	tile.label:SetPoint("TOPLEFT", L.statPad, -L.statPad)
	tile.label:SetText(label:upper())
	tile.labelText = label
	tile.value = Widgets.Label(tile, "reading", true, "body")
	Style.Register(tile, function(t, theme)
		Style.Color(t.bg, theme.background)
		t.edges:Paint(theme.edge, 1)
	end)
	return tile
end

local function placeRect(region, rect)
	region:ClearAllPoints()
	region:SetPoint("TOPLEFT", rect.x, -rect.y)
	region:SetWidth(rect.w)
	if rect.h then region:SetHeight(rect.h) end
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
ChroniclePlaces.MemoryForm = placeMemoryForm

ChroniclePlaces.STATS = { "Visits", "Last here", "Next return moment" }

--- Builds the view inside parent. api = { act(fn), openForm(spec) }.
function ChroniclePlaces.Create(parent, width, api)
	local L = ChroniclePlaces.LAYOUT
	local view = { page = 1, rows = {}, tiedRows = {} }
	local f = CreateFrame("Frame", nil, parent)
	f:SetPoint("TOPLEFT", 0, -L.top)
	f:SetSize(width, L.height)
	view.frame = f

	-- The list.
	local list = Widgets.Panel(f)
	list:SetPoint("TOPLEFT", 0, 0)
	list:SetSize(L.listWidth, L.height)
	view.list = list
	for i = 1, L.rows do
		local row = listRow(list, L)
		row:SetPoint("TOPLEFT", L.listPad, -L.listPad - (i - 1) * (L.rowHeight + L.rowGap))
		row:SetScript("OnClick", function(self)
			if self.entry then
				view.selected = ns.Places.Key(self.entry.zone, self.entry.subzone)
				ns.MainWindow.Refresh()
			end
		end)
		view.rows[i] = row
	end
	local pagerSize = Style.CONTROL.compact
	view.prev = Widgets.Button(list, "<", pagerSize, pagerSize, "ghost")
	view.prev:SetPoint("BOTTOMLEFT", L.listPad, L.listPad)
	view.prev:SetScript("OnClick", function() view.page = view.page - 1; view.selected = nil; ns.MainWindow.Refresh() end)
	Widgets.Tooltip(view.prev, "Previous page")
	view.pageLabel = Widgets.Label(list, "meta", false, "muted")
	view.pageLabel:SetPoint("BOTTOM", 0, L.listPad + 7)
	view.next = Widgets.Button(list, ">", pagerSize, pagerSize, "ghost")
	view.next:SetPoint("BOTTOMRIGHT", -L.listPad, L.listPad)
	view.next:SetScript("OnClick", function() view.page = view.page + 1; view.selected = nil; ns.MainWindow.Refresh() end)
	Widgets.Tooltip(view.next, "Next page")

	-- The detail panel (placed from DetailLayout on every refresh).
	local dw = width - L.listWidth - L.gap
	local d = Widgets.Panel(f)
	d:SetPoint("TOPLEFT", L.listWidth + L.gap, 0)
	d:SetSize(dw, L.height)
	view.detail = d
	d.width = dw
	d.name = Widgets.Label(d, "GameFontNormalHuge", false, "title")
	d.nameHover = CreateFrame("Frame", nil, d)
	Widgets.Tooltip(d.nameHover, nil)
	d.sub = Widgets.Label(d, "GameFontHighlight", false, "muted")
	d.means = Widgets.Label(d, nil, false, "eyebrow")
	d.means:SetText("WHAT IT MEANS TO YOUR CHARACTER")
	d.chips = {}
	for i = 1, 3 do
		d.chips[i] = Widgets.Chip(d, "", "accent")
	end
	d.note = Widgets.Label(d, "meta", true, "muted")
	d.stats = {}
	for i, label in ipairs(ChroniclePlaces.STATS) do
		d.stats[i] = statTile(d, label, L)
	end
	d.tiedLabel = Widgets.Label(d, nil, false, "eyebrow")
	d.tiedLabel:SetText("TIED MEMORIES")
	for i = 1, L.tied do
		local row = Widgets.Card(d)
		row.text = Widgets.Label(row, "GameFontHighlight", false, "body")
		row.text:SetPoint("LEFT", 14, 0)
		Widgets.Tooltip(row, nil)
		view.tiedRows[i] = row
	end
	d.tiedEmpty = Widgets.Label(d, "meta", true, "muted")
	d.tiedEmpty:SetText("No memories are tied to this place yet. Write one here, and returning will recall it.")
	d.more = Widgets.Label(d, "meta", false, "muted")
	d.divider = Widgets.Divider(d)
	local widths = ChroniclePlaces.ActionWidths(dw - 2 * L.detailPad)
	d.write = Widgets.Button(d, "Write a memory here", widths[1], L.buttonHeight, "primary")
	d.mark = Widgets.Button(d, "Mark meaningful", widths[2], L.buttonHeight)
	d.homeland = Widgets.Button(d, "Set as homeland", widths[3], L.buttonHeight, "ghost")
	d.buttons = { d.write, d.mark, d.homeland }

	-- Empty state: nothing logged yet.
	view.empty = Widgets.Panel(f, "No places yet")
	view.empty:SetPoint("TOPLEFT", 0, 0)
	view.empty:SetSize(width, 120)
	view.emptyText = Widgets.Label(view.empty.inner, "reading", true, "reading")
	view.emptyText:SetPoint("TOPLEFT", 0, 0)
	view.emptyText:SetWidth(width - 2 * Widgets.PANEL_PAD)
	view.emptyText:SetText("No places logged yet. Dawnward notes towns, inns and other places as you travel; "
		.. "each one appears here with its visits, and you can mark it as meaningful, make it your Homeland "
		.. "or write a memory there.")

	-- Acts on the selected place, looked up again by its exact key, never by name.
	local function this(c, entry)
		local place = ns.Places.Entry(c, entry.zone, entry.subzone)
		if not place then return nil, "that place is no longer logged" end
		return place
	end

	--- The places on the current page, and the selected one.
	function view:Refresh(char, items)
		local pages = math.max(1, math.ceil(#items / L.rows))
		self.page = math.min(math.max(self.page or 1, 1), pages)
		local offset = (self.page - 1) * L.rows
		local selected
		for _, e in ipairs(items) do
			if ns.Places.Key(e.zone, e.subzone) == self.selected then selected = e end
		end
		selected = selected or items[offset + 1]
		self.current = selected
		self.selected = selected and ns.Places.Key(selected.zone, selected.subzone) or nil

		local has = #items > 0
		self.empty:SetShown(not has)
		self.emptyText:SetShown(not has)
		self.list:SetShown(has)
		self.detail:SetShown(has)
		for i, row in ipairs(self.rows) do
			local e = items[offset + i]
			row.entry = e
			row:SetShown(e ~= nil)
			if e then
				local name, sub = ChroniclePlaces.Lines(e)
				row.name:SetText(name)
				row.sub:SetText(sub)
				row.visits:SetText(ChroniclePlaces.VisitText(e.visits))
				local homeland = ns.Places.IsHomeland(char, e)
				local icon = homeland and ChroniclePlaces.ICONS.homeland
					or e.meaningful and ChroniclePlaces.ICONS.meaningful or nil
				row.icon:SetShown(icon ~= nil)
				if icon then row.icon:SetTexture(icon) end
				Widgets.Tooltip(row, name, sub .. " · " .. ChroniclePlaces.VisitText(e.visits)
					.. (homeland and "\nYour Homeland" or "") .. (e.meaningful and "\nMarked meaningful" or ""))
				row.selected = e == selected or nil
				Style.Repaint(row)
			end
		end
		self.prev:SetShown(pages > 1)
		self.next:SetShown(pages > 1)
		self.pageLabel:SetShown(pages > 1)
		self.prev:SetEnabled(self.page > 1)
		self.next:SetEnabled(self.page < pages)
		self.pageLabel:SetText(string.format("Page %d of %d", self.page, pages))
		if selected then self:ShowDetail(char, selected) end
	end

	function view:ShowDetail(char, e)
		local now = ns.ctx and ns.ctx.now and ns.ctx.now() or nil
		local name = ChroniclePlaces.Lines(e)
		local parts = {}
		if e.subzone then parts[#parts + 1] = e.zone end
		parts[#parts + 1] = e.kind and ns.Places.KIND_LABELS[e.kind] or ChroniclePlaces.UNMAPPED
		local first = ChroniclePlaces.ShortDate(e.first, now)
		if first then parts[#parts + 1] = "first visited " .. (first == "Today" and "today" or first) end

		local homeland = ns.Places.IsHomeland(char, e)
		local tied = ChroniclePlaces.TiedMemories(char.story, e)
		self.tied = tied
		local chips = {}
		if homeland then chips[#chips + 1] = { "Homeland", "accent" } end
		if e.meaningful then chips[#chips + 1] = { "Marked meaningful", "accent" } end
		chips[#chips + 1] = { #tied == 0 and "No memories tied to it" or
			string.format("%d memor%s tied to it", #tied, #tied == 1 and "y" or "ies"), "muted" }

		local field = char.fields and char.fields.homeland
		local note
		if homeland and field then
			note = string.format("Your Homeland field reads \"%s\". Edit it on the Character page.", field.value)
		else
			note = "Set as homeland writes this place into your Homeland field, part of your profile. Only you "
				.. "decide what a place means."
		end
		local play = ns.NarrativeClock.Current(char, ns.ctx)
		local values = { tostring(e.visits or 0), ChroniclePlaces.ShortDate(e.last, now) or "Unknown",
			ChroniclePlaces.ReturnText(ns.Places.ReturnCheck(char, e, e.kind, play)) }

		local chipTexts, stats = {}, {}
		for i, c in ipairs(chips) do chipTexts[i] = c[1] end
		for i, label in ipairs(ChroniclePlaces.STATS) do stats[i] = { label, values[i] } end
		local r = ChroniclePlaces.DetailLayout({ chips = chipTexts, note = note, stats = stats, tied = #tied }, d.width)
		self.layout = r

		placeRect(d.name, r.name)
		d.name:SetText(name)
		placeRect(d.nameHover, r.name)
		Widgets.Tooltip(d.nameHover, name, table.concat(parts, " · "))
		placeRect(d.sub, r.sub)
		d.sub:SetText(table.concat(parts, " · "))
		placeRect(d.means, r.means)
		for i, chip in ipairs(d.chips) do
			local spec, at = chips[i], r.chips[i]
			chip:SetShown(spec ~= nil)
			if spec then
				chip:SetMaxWidth(at.w)
				chip:SetChip(spec[1], spec[2])
				chip:ClearAllPoints()
				chip:SetPoint("TOPLEFT", at.x, -at.y)
			end
		end
		placeRect(d.note, r.note)
		if d.note.SetMaxLines then d.note:SetMaxLines(r.note.lines) end
		d.note:SetText(note)
		for i, tile in ipairs(d.stats) do
			local at = r.stats[i]
			placeRect(tile, at)
			tile.label:SetWidth(at.w - 2 * L.statPad)
			local labelLines = math.max(1, wrapLines(tile.labelText:upper(), at.w - 2 * L.statPad, "eyebrow"))
			tile.value:ClearAllPoints()
			tile.value:SetPoint("TOPLEFT", L.statPad, -(L.statPad + labelLines * L.statLabelLine + 6))
			tile.value:SetWidth(at.w - 2 * L.statPad)
			tile.value:SetText(values[i])
		end
		placeRect(d.tiedLabel, r.tiedLabel)

		local muted = Style.Current().muted
		local hexMuted = string.format("%02x%02x%02x", math.floor(muted[1] * 255 + 0.5),
			math.floor(muted[2] * 255 + 0.5), math.floor(muted[3] * 255 + 0.5))
		for i, row in ipairs(self.tiedRows) do
			local m = i <= r.shown and tied[i] or nil
			row:SetShown(m ~= nil)
			if m then
				placeRect(row, r.tied[i])
				row.text:SetWidth(r.tied[i].w - 28)
				local mname, mnote = ChroniclePlaces.MemoryParts(m)
				row.text:SetText(string.format("%s  |cff%s·  %s|r", mname, hexMuted, mnote))
				-- The memory whole on hover: its title and text.
				Widgets.Tooltip(row, m.title or mname, m.text)
			end
		end
		placeRect(d.tiedEmpty, r.tiedEmpty)
		d.tiedEmpty:SetShown(#tied == 0)
		placeRect(d.more, r.more)
		d.more:SetShown(#tied > r.shown)
		d.more:SetText(string.format("and %d more in Memories", #tied - r.shown))
		placeRect(d.divider, r.divider)

		local x = r.buttons.x
		for _, b in ipairs(d.buttons) do
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", x, -r.buttons.y)
			x = x + b:GetWidth() + L.buttonGap
		end

		local label = name
		d.write:SetScript("OnClick", function() api.openForm(placeMemoryForm(e)) end)
		d.mark:SetText(e.meaningful and "Unmark meaningful" or "Mark meaningful")
		d.mark:SetScript("OnClick", function()
			api.act(function(c)
				local place, err = this(c, e)
				if not place then return nil, err end
				place.meaningful = (not place.meaningful) or nil
				return place
			end)
		end)
		d.homeland:SetEnabled(not homeland)
		Widgets.Tooltip(d.homeland, "Set as homeland", homeland and "This place is already your Homeland."
			or "Names this place in your Homeland field, after you confirm.")
		d.homeland:SetScript("OnClick", function()
			if ns.Places.IsHomeland(char, e) then return end
			Widgets.Confirm(string.format("Set your Homeland to %s? This replaces the Homeland on your "
				.. "profile.", label), "Set", function()
				api.act(function(c, now2)
					local place, err = this(c, e)
					if not place then return nil, err end
					return ns.Places.SetHomeland(c, place, now2)
				end)
			end)
		end)
	end

	return view
end
