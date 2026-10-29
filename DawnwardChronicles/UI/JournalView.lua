-- Journal section: entries newest first, ten per page, each a card with its
-- meta line, title, text, actions and visibility. Pages keep the number of frames small however large the
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
local ROW_PAD = 8
local CARD_GAP = 8
local CARD_INSET = 10
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
	section.older = Widgets.Button(f, "Older >", 76, 22, "ghost")
	section.older:SetPoint("TOPRIGHT", -INSET, -6)
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

	section.empty = Widgets.Label(f, "GameFontHighlight", true, "muted")
	section.empty:SetJustifyH("CENTER")
	section.empty:SetPoint("TOP", 0, -(LIST_TOP + 60))
	section.empty:SetWidth(420)
	section.empty:SetText(JournalView.EMPTY_TEXT)

	local function getRow(index)
		local row = section.rows[index]
		if row then
			return row
		end
		row = Widgets.Card(child)
		row.meta = Widgets.Label(row, "GameFontHighlightSmall")
		row.meta:SetPoint("TOPLEFT", CARD_INSET, -ROW_PAD)
		row.title = Widgets.Label(row, "GameFontNormal", true)
		row.body = Widgets.Label(row, "GameFontHighlight", true)
		row.vis = Widgets.VisibilityButton(row, function(level)
			local _, message = Actions.SetEntryVisibility(ns.ctx, row.entryId, level)
			MainWindow.SetStatus(message)
			MainWindow.Refresh()
		end)
		row.vis:SetPoint("TOPRIGHT", -6, -5)
		if section.decorateRow then
			section.decorateRow(row)
		end
		section.rows[index] = row
		return row
	end

	-- Lays out one row for entry at vertical offset y; returns its height.
	local function layoutRow(row, entry, y, width, theme, char)
		row.entryId = entry.id
		row.entry = entry
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
		row:SetWidth(width)

		local textWidth = width - 2 * CARD_INSET
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
			-- Story drafts show their development's current status (display only).
			row.body:SetText(char and ns.Narrative.DisplayText(char, entry) or entry.text)
			row.body:ClearAllPoints()
			row.body:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
			Widgets.TextColor(row.body, theme.text)
			height = height + 4 + row.body:GetStringHeight()
		else
			row.body:Hide()
		end
		height = height + 12
		row:SetHeight(height)
		row.vis:SetLevel(entry.visibility)
		if section.updateRowActions then
			section.updateRowActions(row, entry)
		end
		row:Show()
		return height + CARD_GAP
	end

	function section:ApplyTheme(theme)
		self.theme = theme
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
		local width = view.contentWidth - 2 * INSET - 22 -- scroll bar sits inside the right inset
		self.child:SetWidth(width)
		local first = (self.page - 1) * JournalView.PAGE_SIZE + 1
		local y, shown = 0, 0
		for i = first, math.min(#entries, first + JournalView.PAGE_SIZE - 1) do
			shown = shown + 1
			y = y + layoutRow(getRow(shown), entries[i], y, width, view.theme, char)
		end
		for i = shown + 1, #self.rows do
			self.rows[i]:Hide()
		end
		self.child:SetHeight(math.max(y, 1))
		self.visibleCount = shown
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

--- Adds the New entry button, row Edit/Delete buttons and the entry editor.
function JournalView.AttachEditing(section)
	local f = section.frame
	section.rowActionsWidth = EDIT_BUTTON_WIDTH + DELETE_BUTTON_WIDTH + APPROVE_BUTTON_WIDTH + MARK_BUTTON_WIDTH + 16

	section.newButton = Widgets.Button(section.toolbarLeft, "New entry", 100, 22, "primary")
	section.newButton:SetPoint("LEFT", 0, 0)
	section.newButton:SetScript("OnClick", function() section:OpenEditor(nil) end)

	function section.decorateRow(row)
		row.delete = Widgets.Button(row, "Delete", DELETE_BUTTON_WIDTH, 20, "danger")
		row.delete:SetPoint("RIGHT", row.vis, "LEFT", -4, 0)
		row.delete:SetScript("OnClick", function() section:ConfirmDelete(row.entry) end)
		row.edit = Widgets.Button(row, "Edit", EDIT_BUTTON_WIDTH, 20, "ghost")
		row.edit:SetPoint("RIGHT", row.delete, "LEFT", -4, 0)
		row.edit:SetScript("OnClick", function() section:OpenEditor(row.entry) end)
		-- Story drafts are Dawnward's words until the player approves them.
		row.approve = Widgets.Button(row, "Approve", APPROVE_BUTTON_WIDTH, 20, "primary")
		row.approve:SetPoint("RIGHT", row.edit, "LEFT", -4, 0)
		row.approve:SetScript("OnClick", function()
			local _, message = Actions.ApproveEntry(ns.ctx, row.entryId)
			MainWindow.SetStatus(message)
			MainWindow.Refresh()
		end)
		Widgets.Tooltip(row.approve, "Approve draft",
			"Accept this draft as part of your character's story. It stays private until you change its visibility.")
		-- Any entry can be marked as a defining moment.
		row.mark = Widgets.Button(row, "Defining", MARK_BUTTON_WIDTH, 20, "ghost")
		row.mark:SetPoint("RIGHT", row.approve, "LEFT", -4, 0)
		row.mark:SetScript("OnClick", function()
			local _, message = Actions.SetEntryImportant(ns.ctx, row.entryId, not (row.entry and row.entry.important))
			MainWindow.SetStatus(message)
			MainWindow.Refresh()
		end)
		Widgets.Tooltip(row.mark, "Defining moment",
			"Mark or unmark this entry as an important memory. Approved, public defining moments can appear in "
				.. "Total RP 3 if you turned biography sync on.")
	end

	-- Only entries the player wrote (or story entries) can be edited or deleted.
	function section.updateRowActions(row, entry)
		local written = entry.kind == "note" or entry.kind == "story"
		row.edit:SetShown(written)
		row.delete:SetShown(written)
		row.approve:SetShown(entry.kind == "story" and entry.status ~= "approved")
		row.mark:SetSelected(entry.important)
	end

	-- Editor panel (replaces the list while open).
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

	local function listParts(shown)
		section.scroll:SetShown(shown)
		section.newer:SetShown(shown)
		section.older:SetShown(shown)
		section.pageLabel:SetShown(shown)
		section.toolbarLeft:SetShown(shown)
		if not shown then
			section.empty:Hide()
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

MainWindow.RegisterSection({ id = "journal", label = "Journal", order = 1, create = create })
