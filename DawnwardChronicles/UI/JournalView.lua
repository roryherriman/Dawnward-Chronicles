-- Journal section: entries newest first, ten per page, each with its
-- visibility. Pages keep the number of frames small however large the
-- journal grows (rows are created once and reused).
local _, ns = ...
local Widgets, MainWindow, Actions, Journal = ns.Widgets, ns.MainWindow, ns.Actions, ns.Journal

local JournalView = {}
ns.JournalView = JournalView

JournalView.PAGE_SIZE = 10
JournalView.EMPTY_TEXT = "Your journal is empty.\n\nWrite your first entry with New entry, or keep adventuring: "
	.. "level-ups are recorded here automatically."

local TOOLBAR_HEIGHT = 24
local LIST_TOP = 36       -- list starts this far below the section top
local INSET = 8
local ROW_PAD = 6
local VIS_WIDTH = 72

--- Text for an entry's meta line (date, level, place, origin).
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
	elseif entry.updatedAt then
		parts[#parts + 1] = "edited"
	end
	return table.concat(parts, "  -  ")
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

local function create(parent)
	local section = { frame = CreateFrame("Frame", nil, parent), rows = {}, page = 1 }
	local f = section.frame

	-- Toolbar: page navigation on the right.
	section.older = Widgets.Button(f, "Older", 70, 22)
	section.older:SetPoint("TOPRIGHT", -INSET, -6)
	section.pageLabel = Widgets.Label(f, "GameFontHighlightSmall")
	section.pageLabel:SetJustifyH("CENTER")
	section.pageLabel:SetWidth(90)
	section.pageLabel:SetPoint("RIGHT", section.older, "LEFT", -4, 0)
	section.newer = Widgets.Button(f, "Newer", 70, 22)
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

	section.toolbarLeft = CreateFrame("Frame", nil, f)
	section.toolbarLeft:SetPoint("TOPLEFT", INSET, -6)
	section.toolbarLeft:SetSize(200, TOOLBAR_HEIGHT)

	-- List.
	local scroll = CreateFrame("ScrollFrame", Widgets.NextName("JournalScroll"), f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", INSET, -LIST_TOP)
	scroll:SetPoint("BOTTOMRIGHT", -(INSET + 22), INSET)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(100, 100)
	scroll:SetScrollChild(child)
	section.scroll, section.child = scroll, child

	section.empty = Widgets.Label(f, "GameFontHighlight", true)
	section.empty:SetJustifyH("CENTER")
	section.empty:SetPoint("TOP", 0, -(LIST_TOP + 60))
	section.empty:SetWidth(420)
	section.empty:SetText(JournalView.EMPTY_TEXT)

	local function getRow(index)
		local row = section.rows[index]
		if row then
			return row
		end
		row = CreateFrame("Frame", nil, child)
		row.meta = Widgets.Label(row, "GameFontHighlightSmall")
		row.meta:SetPoint("TOPLEFT", 4, -ROW_PAD)
		row.title = Widgets.Label(row, "GameFontNormal", true)
		row.body = Widgets.Label(row, "GameFontHighlight", true)
		row.vis = Widgets.VisibilityButton(row, function(level)
			local _, message = Actions.SetEntryVisibility(ns.ctx, row.entryId, level)
			MainWindow.SetStatus(message)
			MainWindow.Refresh()
		end)
		row.vis:SetPoint("TOPRIGHT", -2, -2)
		row.separator = Widgets.Solid(row, "ARTWORK")
		row.separator:SetHeight(1)
		row.separator:SetPoint("BOTTOMLEFT", 4, 0)
		row.separator:SetPoint("BOTTOMRIGHT", -4, 0)
		if section.decorateRow then
			section.decorateRow(row)
		end
		section.rows[index] = row
		return row
	end

	-- Lays out one row for entry at vertical offset y; returns its height.
	local function layoutRow(row, entry, y, width, theme)
		row.entryId = entry.id
		row.entry = entry
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
		row:SetWidth(width)

		local textWidth = width - 8
		row.meta:SetWidth(textWidth - VIS_WIDTH - (section.rowActionsWidth or 0) - 8)
		row.meta:SetText(JournalView.MetaText(entry, Widgets.FormatDate))
		Widgets.TextColor(row.meta, theme.muted)

		local height = ROW_PAD + 20
		local anchor = row.meta
		if entry.title then
			row.title:Show()
			row.title:SetWidth(textWidth)
			row.title:SetText(entry.title)
			row.title:ClearAllPoints()
			row.title:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
			Widgets.TextColor(row.title, theme.accent)
			height = height + 6 + row.title:GetStringHeight()
			anchor = row.title
		else
			row.title:Hide()
		end
		if entry.text then
			row.body:Show()
			row.body:SetWidth(textWidth)
			row.body:SetText(entry.text)
			row.body:ClearAllPoints()
			row.body:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
			Widgets.TextColor(row.body, theme.text)
			height = height + 4 + row.body:GetStringHeight()
		else
			row.body:Hide()
		end
		height = height + 10
		row:SetHeight(height)
		row.vis:SetLevel(entry.visibility)
		Widgets.SetColor(row.separator, theme.border)
		if section.updateRowActions then
			section.updateRowActions(row, entry)
		end
		row:Show()
		return height
	end

	function section:ApplyTheme(theme)
		self.theme = theme
		Widgets.TextColor(self.pageLabel, theme.muted)
		Widgets.TextColor(self.empty, theme.muted)
	end

	function section:RenderList(view)
		local char = view.char
		local entries = char and Journal.NewestFirst(char) or {}
		local pages
		self.page, pages = JournalView.ClampPage(self.page, #entries)
		self.pageLabel:SetText(string.format("Page %d of %d", self.page, pages))
		self.newer:SetEnabled(self.page > 1)
		self.older:SetEnabled(self.page < pages)

		self.empty:SetShown(#entries == 0)
		local width = math.max(200, self.scroll:GetWidth())
		self.child:SetWidth(width)
		local first = (self.page - 1) * JournalView.PAGE_SIZE + 1
		local y, shown = 0, 0
		for i = first, math.min(#entries, first + JournalView.PAGE_SIZE - 1) do
			shown = shown + 1
			y = y + layoutRow(getRow(shown), entries[i], y, width, view.theme)
		end
		for i = shown + 1, #self.rows do
			self.rows[i]:Hide()
		end
		self.child:SetHeight(math.max(y, 1))
		self.visibleCount = shown
	end

	function section:Refresh(view)
		self.theme = view.theme
		self:RenderList(view)
	end

	section.getRow = getRow
	JournalView.section = section
	return section
end

MainWindow.RegisterSection({ id = "journal", label = "Journal", order = 1, create = create })
