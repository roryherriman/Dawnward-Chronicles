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
-- below the tabs).
ChroniclePlaces.LAYOUT = {
	top = 50, listWidth = 300, gap = 16, height = 538,
	listPad = 8, rowHeight = 56, rowGap = 2, rows = 8, pagerHeight = 28,
	detailPad = 20, statHeight = 62, statGap = 10, tied = 3, tiedHeight = 28, tiedGap = 6,
	buttonHeight = 30, buttonGap = 8,
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

--- One tied memory's line: its title (or the start of its text) and a status. Pure.
function ChroniclePlaces.MemoryLine(m)
	local name = m.title or (m.text and (#m.text > 48 and (m.text:sub(1, 45) .. "...") or m.text)) or "A memory"
	local note = m.status == "established" and IMPORTANCE[m.importance or 1] or STATUS[m.status] or m.status
	return name .. "  ·  " .. note
end

-- A selectable list row (a button painted like an entry card).
local function listRow(parent, L)
	local row = CreateFrame("Button", nil, parent)
	row:SetSize(L.listWidth - 2 * L.listPad, L.rowHeight)
	row.bg = Style.Solid(row, "BACKGROUND")
	row.bg:SetAllPoints(row)
	row.edges = Style.Edge(row, "BORDER")
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(18, 18)
	row.icon:SetPoint("TOPLEFT", 10, -19)
	row.name = Widgets.Label(row, "GameFontHighlight", false, "body")
	row.name:SetPoint("TOPLEFT", 38, -9)
	row.name:SetWidth(L.listWidth - 2 * L.listPad - 38 - 70)
	row.sub = Widgets.Label(row, "GameFontHighlightSmall", false, "muted")
	row.sub:SetPoint("TOPLEFT", 38, -30)
	row.sub:SetWidth(L.listWidth - 2 * L.listPad - 38 - 70)
	row.visits = Widgets.Label(row, "GameFontHighlightSmall", false, "muted")
	row.visits:SetJustifyH("RIGHT")
	row.visits:SetPoint("TOPRIGHT", -10, -20)
	row.visits:SetWidth(64)
	row:SetScript("OnEnter", function(self) self.hover = true; Style.Repaint(self) end)
	row:SetScript("OnLeave", function(self) self.hover = nil; Style.Repaint(self) end)
	Style.Register(row, function(r, theme)
		Style.Color(r.bg, theme.surfaceHover, (r.selected or r.hover) and 1 or 0)
		r.edges:Paint(theme.border or theme.accent, r.selected and 1 or 0)
	end)
	return row
end

-- A stat tile: a small eyebrow over a value.
local function statTile(parent, label)
	local tile = CreateFrame("Frame", nil, parent)
	tile.bg = Style.Solid(tile, "BACKGROUND", -1)
	tile.bg:SetAllPoints(tile)
	tile.edges = Style.Edge(tile, "BORDER")
	tile.label = Widgets.Label(tile, nil, false, "eyebrow")
	tile.label:SetPoint("TOPLEFT", 12, -10)
	tile.label:SetText(label:upper())
	tile.value = Widgets.Label(tile, "GameFontHighlight", true, "body")
	tile.value:SetPoint("TOPLEFT", 12, -28)
	Style.Register(tile, function(t, theme)
		Style.Color(t.bg, theme.surface)
		t.edges:Paint(theme.edge, 1)
	end)
	return tile
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
	view.prev = Widgets.Button(list, "<", 26, 22, "ghost")
	view.prev:SetPoint("BOTTOMLEFT", L.listPad, L.listPad)
	view.prev:SetScript("OnClick", function() view.page = view.page - 1; view.selected = nil; ns.MainWindow.Refresh() end)
	Widgets.Tooltip(view.prev, "Previous page")
	view.pageLabel = Widgets.Label(list, "GameFontHighlightSmall", false, "muted")
	view.pageLabel:SetPoint("BOTTOM", 0, L.listPad + 5)
	view.next = Widgets.Button(list, ">", 26, 22, "ghost")
	view.next:SetPoint("BOTTOMRIGHT", -L.listPad, L.listPad)
	view.next:SetScript("OnClick", function() view.page = view.page + 1; view.selected = nil; ns.MainWindow.Refresh() end)
	Widgets.Tooltip(view.next, "Next page")

	-- The detail panel.
	local dw = width - L.listWidth - L.gap
	local inner = dw - 2 * L.detailPad
	local d = Widgets.Panel(f)
	d:SetPoint("TOPLEFT", L.listWidth + L.gap, 0)
	d:SetSize(dw, L.height)
	view.detail = d
	local P = L.detailPad
	d.name = Widgets.Label(d, "GameFontNormalHuge", false, "body")
	d.name:SetPoint("TOPLEFT", P, -P)
	d.name:SetWidth(inner)
	d.sub = Widgets.Label(d, "GameFontHighlight", false, "muted")
	d.sub:SetPoint("TOPLEFT", P, -P - 34)
	d.sub:SetWidth(inner)
	d.means = Widgets.Label(d, nil, false, "eyebrow")
	d.means:SetPoint("TOPLEFT", P, -P - 64)
	d.means:SetText("WHAT IT MEANS TO YOUR CHARACTER")
	d.chips = {}
	for i = 1, 3 do
		d.chips[i] = Widgets.Chip(d, "", "accent")
	end
	d.note = Widgets.Label(d, "GameFontHighlightSmall", true, "muted")
	d.note:SetPoint("TOPLEFT", P, -P - 112)
	d.note:SetSize(inner, 30)
	local statW = math.floor((inner - 2 * L.statGap) / 3)
	d.stats = {}
	for i, label in ipairs({ "Visits", "Last here", "Next return moment" }) do
		local tile = statTile(d, label)
		tile:SetSize(statW, L.statHeight)
		tile:SetPoint("TOPLEFT", P + (i - 1) * (statW + L.statGap), -P - 152)
		tile.value:SetWidth(statW - 24)
		d.stats[i] = tile
	end
	d.tiedLabel = Widgets.Label(d, nil, false, "eyebrow")
	d.tiedLabel:SetPoint("TOPLEFT", P, -P - 232)
	d.tiedLabel:SetText("TIED MEMORIES")
	for i = 1, L.tied do
		local row = Widgets.Card(d)
		row:SetSize(inner, L.tiedHeight)
		row:SetPoint("TOPLEFT", P, -P - 252 - (i - 1) * (L.tiedHeight + L.tiedGap))
		row.text = Widgets.Label(row, "GameFontHighlightSmall", false, "body")
		row.text:SetPoint("LEFT", 10, 0)
		row.text:SetWidth(inner - 20)
		view.tiedRows[i] = row
	end
	d.tiedEmpty = Widgets.Label(d, "GameFontHighlightSmall", true, "muted")
	d.tiedEmpty:SetPoint("TOPLEFT", P, -P - 254)
	d.tiedEmpty:SetWidth(inner)
	d.tiedEmpty:SetText("No memories are tied to this place yet. Write one here, and returning will recall it.")
	d.more = Widgets.Label(d, "GameFontHighlightSmall", false, "muted")
	d.more:SetPoint("TOPLEFT", P, -P - 252 - L.tied * (L.tiedHeight + L.tiedGap))
	d.divider = Widgets.Divider(d)
	d.divider:SetPoint("BOTTOMLEFT", P, P + L.buttonHeight + 14)
	d.divider:SetWidth(inner)
	d.write = Widgets.Button(d, "Write a memory here", 150, L.buttonHeight, "primary")
	d.write:SetPoint("BOTTOMLEFT", P, P)
	d.mark = Widgets.Button(d, "Mark meaningful", 134, L.buttonHeight)
	d.mark:SetPoint("LEFT", d.write, "RIGHT", L.buttonGap, 0)
	d.homeland = Widgets.Button(d, "Set as homeland", 116, L.buttonHeight, "ghost")
	d.homeland:SetPoint("LEFT", d.mark, "RIGHT", L.buttonGap, 0)
	d.buttons = { d.write, d.mark, d.homeland }

	-- Empty state: nothing logged yet.
	view.empty = Widgets.Panel(f, "No places yet")
	view.empty:SetPoint("TOPLEFT", 0, 0)
	view.empty:SetSize(width, 120)
	view.emptyText = Widgets.Label(view.empty.inner, "GameFontHighlight", true, "body")
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

	local function placeChips(chips, list2, x0, y0)
		local x = x0
		for i, chip in ipairs(chips) do
			local spec = list2[i]
			chip:SetShown(spec ~= nil)
			if spec then
				chip:SetChip(spec[1], spec[2])
				chip:ClearAllPoints()
				chip:SetPoint("TOPLEFT", x, -y0)
				x = x + chip:GetWidth() + 8
			end
		end
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
				local icon = ns.Places.IsHomeland(char, e) and ChroniclePlaces.ICONS.homeland
					or e.meaningful and ChroniclePlaces.ICONS.meaningful or nil
				row.icon:SetShown(icon ~= nil)
				if icon then row.icon:SetTexture(icon) end
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
		d.name:SetText(name)
		local parts = {}
		if e.subzone then parts[#parts + 1] = e.zone end
		parts[#parts + 1] = e.kind and ns.Places.KIND_LABELS[e.kind] or ChroniclePlaces.UNMAPPED
		local first = ChroniclePlaces.ShortDate(e.first, now)
		if first then parts[#parts + 1] = "first visited " .. (first == "Today" and "today" or first) end
		d.sub:SetText(table.concat(parts, " · "))

		local homeland = ns.Places.IsHomeland(char, e)
		local tied = ChroniclePlaces.TiedMemories(char.story, e)
		self.tied = tied
		local chips = {}
		if homeland then chips[#chips + 1] = { "Homeland", "accent" } end
		if e.meaningful then chips[#chips + 1] = { "Marked meaningful", "accent" } end
		chips[#chips + 1] = { #tied == 0 and "No memories tied to it" or
			string.format("%d memor%s tied to it", #tied, #tied == 1 and "y" or "ies"), "muted" }
		placeChips(d.chips, chips, L.detailPad, L.detailPad + 84)

		local field = char.fields and char.fields.homeland
		if homeland and field then
			d.note:SetText(string.format("Your Homeland field reads \"%s\" and stays %s. Setting a homeland never "
				.. "changes its visibility.", field.value, ns.Themes.VISIBILITY_LABELS[field.visibility]
				or field.visibility))
		else
			d.note:SetText("Set as homeland writes this place into your Homeland field; the field's visibility "
				.. "stays as it is. Only you decide what a place means.")
		end

		d.stats[1].value:SetText(tostring(e.visits or 0))
		d.stats[2].value:SetText(ChroniclePlaces.ShortDate(e.last, now) or "Unknown")
		local play = ns.NarrativeClock.Current(char, ns.ctx)
		d.stats[3].value:SetText(ChroniclePlaces.ReturnText(ns.Places.ReturnCheck(char, e, e.kind, play)))

		for i, row in ipairs(self.tiedRows) do
			local m = tied[i]
			row:SetShown(m ~= nil)
			if m then row.text:SetText(ChroniclePlaces.MemoryLine(m)) end
		end
		d.tiedEmpty:SetShown(#tied == 0)
		d.more:SetShown(#tied > L.tied)
		d.more:SetText(string.format("and %d more in Memories", #tied - L.tied))

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
				.. "profile; its visibility stays as it is.", label), "Set", function()
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
