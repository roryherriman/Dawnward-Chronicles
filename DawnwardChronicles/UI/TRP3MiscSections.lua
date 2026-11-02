-- The Total RP 3 profile editor's own editors (v0.10.1), shown on the
-- Settings > Total RP 3 page (UI/TRP3Page.lua):
--   At First Glance  the five entries: a list (icon, title, shown or hidden,
--                    order), the editor (title, text, icon with Dawnward's
--                    icon picker, shown or hidden, move up or down, save,
--                    remove), a preview of how Total RP 3 shows the entry,
--                    and At First Glance sync on or off
--   Status and OOC   two views behind a switch: Currently and OOC (editors,
--                    Save, Clear, Suggest for Currently, Import), and Status
--                    and style (roleplay status, walk-up, and the six
--                    roleplay style preferences: read only unless the
--                    player lets Dawnward manage one; Open in Total RP 3)
--   Profile look     the profile icon and class colour editors above the
--                    Profile section's rows
-- Every value is the player's own: nothing here is inferred or saved
-- without the player's Save (Suggest only fills the editor). Saving changes
-- Dawnward's copy through the normal Actions path (TRP3Commands.SetStatus,
-- SaveGlance, ...); Total RP 3 follows on the next guarded sync, and only
-- for what the player keeps in sync. Opening or refreshing only reads.
local _, ns = ...
local Widgets, MainWindow, Style = ns.Widgets, ns.MainWindow, ns.Style

local M = {}
ns.TRP3MiscSections = M

-- Layout: At First Glance's list column and the gap to the editor.
M.GLANCE_LIST = 200
M.GLANCE_ROW = 44
M.GLANCE_GAP = 12
M.TEXT_HEIGHT = 66          -- Currently and OOC editors
M.GLANCE_TEXT = 84          -- the At First Glance text editor
M.STYLE_ROW = 34
M.STYLE_LABEL = 170
M.STYLE_VALUE = 180
M.SYNC_ITEM = 64            -- one item of a row's "Sync on / Off" switch
M.PICKER_COLUMNS = 7
M.PICKER_CELL = 36
M.PICKER_GAP = 6

M.STATUS_VIEWS = { { id = "text", label = "Currently and OOC" }, { id = "style", label = "Status and style" } }
M.SYNC_CHOICES = { { id = "dawnward", label = "Sync on" }, { id = "trp3", label = "Off" } }
M.MANAGE_CHOICES = { { id = "dawnward", label = "Dawnward" }, { id = "trp3", label = "TRP3" } }

M.GLANCE_EXPLAIN = "Up to five short entries other players see at first glance. Dawnward writes only the ones you "
	.. "write here, into free slots; slots you filled in Total RP 3 stay as they are."
M.STYLE_NOTE = "Total RP 3 keeps your roleplay style. Hand a preference to Dawnward to edit it here; it has no "
	.. "official setter, so Dawnward writes it with a backup and a read-back."

local function H() return ns.TRP3Page.H end

local function iconPath(name)
	return "Interface\\Icons\\" .. tostring(name or ns.Glance.DEFAULT_ICON)
end

local function iconTexture(parent, size)
	local t = parent:CreateTexture(nil, "ARTWORK")
	t:SetSize(size, size)
	t:SetTexture(iconPath(nil))
	return t
end

local function eyebrow(parent, text)
	local fs = Widgets.TrackedLabel(parent, "eyebrow", "eyebrow")
	fs:SetText(text)
	return fs
end

local function ctx() return ns.ctx end

local function charValues()
	return ns.RPStatus.Get(H().realChar())
end

-- An editor's text, kept while the player is changing it: a refresh puts
-- the saved value in only when the box still shows the last value loaded.
local function load(edit, value)
	value = value or ""
	if edit.loaded == nil or (edit:GetText() or "") == edit.loaded then
		edit:SetText(value)
	end
	edit.loaded = value
end

-- The confirmation before a row is kept in sync (or handed over).
local function askManage(id, on, label, experimental)
	local act = H().act
	if not on then
		act(function()
			local _, message = ns.TRP3Commands.ManageRow(ctx(), id, false)
			return message
		end)
		return
	end
	Widgets.Confirm("Keep your " .. label .. " in sync with Total RP 3?\n\nDawnward writes only what you save here, "
		.. "never over a value you set in Total RP 3 yourself: if Total RP 3 already shows something else, it waits "
		.. "for your choice. A backup is taken before every write."
		.. (experimental and ("\n\nEXPERIMENTAL: Total RP 3 has no official way to change this, so Dawnward uses its "
			.. "internal data, reads it back and restores the backup if anything differs.") or ""), "Keep in sync",
		function()
			act(function()
				local _, message = ns.TRP3Commands.ManageRow(ctx(), id, true)
				return message
			end)
		end)
end

local function askImport(id, label, shown)
	Widgets.Confirm("Copy Total RP 3's " .. label .. " (\"" .. H().plain(H().excerpt(shown, 80)) .. "\") into "
		.. "Dawnward?\n\nNothing is written to Total RP 3.", "Import", function()
		H().act(function()
			local _, message = ns.TRP3Commands.ImportStatus(ctx(), id)
			return message
		end)
	end)
end

--- Icon picker ------------------------------------------------------------------
-- One pooled grid over the card (Glance.ICON_CHOICES), shared by the At
-- First Glance and profile icon editors.

function M.BuildIconPicker(page)
	local P = ns.TRP3Page.CARD_PAD
	local picker = Widgets.Panel(page.card, "Choose an icon")
	local cols, cell, gap = M.PICKER_COLUMNS, M.PICKER_CELL, M.PICKER_GAP
	local rows = math.ceil(#ns.Glance.ICON_CHOICES / cols)
	local w = cols * (cell + gap) - gap + 2 * Widgets.PANEL_PAD
	picker:SetSize(w, rows * (cell + gap) - gap + 2 * Widgets.PANEL_PAD + 22 + 40)
	picker:SetPoint("TOPRIGHT", page.card, "TOPRIGHT", -P, -ns.TRP3Page.HEAD_HEIGHT)
	if picker.SetFrameLevel and page.card.GetFrameLevel then
		picker:SetFrameLevel((page.card:GetFrameLevel() or 1) + 30)
	end
	picker.cells = {}
	for i, name in ipairs(ns.Glance.ICON_CHOICES) do
		local b = Widgets.Button(picker.inner, "", cell, cell, "ghost")
		b:SetPoint("TOPLEFT", ((i - 1) % cols) * (cell + gap), -math.floor((i - 1) / cols) * (cell + gap))
		b.tex = iconTexture(b, cell - 6)
		b.tex:SetPoint("CENTER", 0, 0)
		b.tex:SetTexture(iconPath(name))
		b.iconName = name
		Widgets.Tooltip(b, name, "Choose this icon.")
		b:SetScript("OnClick", function(self)
			picker:Hide()
			if picker.onPick then picker.onPick(self.iconName) end
		end)
		picker.cells[i] = b
	end
	picker.close = Widgets.Button(picker.inner, "Close", 90, Style.CONTROL.compact, "ghost")
	picker.close:SetPoint("BOTTOMRIGHT", 0, 0)
	picker.close:SetScript("OnClick", function() picker:Hide() end)
	picker.note = H().oneLine(picker.inner, "muted", w - 2 * Widgets.PANEL_PAD - 100, "small")
	picker.note:SetPoint("BOTTOMLEFT", 0, 8)
	picker.note:SetText("Or type any icon name in the box.")
	picker:Hide()
	page.iconPicker = picker
	return picker
end

--- Opens the icon picker; onPick(name) runs when an icon is chosen.
function M.OpenIconPicker(page, current, onPick)
	local picker = page.iconPicker
	picker.onPick = onPick
	for _, b in ipairs(picker.cells) do b:SetSelected(b.iconName == current) end
	picker:Show()
	if picker.Raise then picker:Raise() end
end

--- Profile look -------------------------------------------------------------------

function M.BuildLook(page, mv, P, innerW)
	local L = ns.TRP3Page.LOOK_HEIGHT
	local strip = CreateFrame("Frame", nil, mv)
	strip:SetPoint("TOPLEFT", P, -ns.TRP3Page.LOOK_TOP)
	strip:SetSize(innerW, L)
	page.look = strip
	strip.icon = iconTexture(strip, 30)
	strip.icon:SetPoint("LEFT", 0, 0)
	strip.iconEdit = Widgets.EditLine(strip, ns.RPStatus.LIMITS.icon + 1, Style.CONTROL.compact)
	strip.iconEdit:SetWidth(150)
	strip.iconEdit:SetPoint("LEFT", 36, 0)
	Widgets.Tooltip(strip.iconEdit, "Profile icon", "The icon Total RP 3 shows for you (a game icon name).")
	strip.choose = Widgets.Button(strip, "Choose…", 84, Style.CONTROL.compact, "ghost")
	strip.choose:SetPoint("LEFT", 192, 0)
	strip.choose:SetScript("OnClick", function()
		M.OpenIconPicker(page, strip.iconEdit:GetText(), function(name)
			strip.iconEdit:SetText(name)
			strip.icon:SetTexture(iconPath(name))
		end)
	end)
	strip.swatch = Style.Solid(strip, "ARTWORK")
	strip.swatch:SetSize(24, 24)
	strip.swatch:SetPoint("LEFT", 290, 0)
	strip.colorEdit = Widgets.EditLine(strip, 8, Style.CONTROL.compact)
	strip.colorEdit:SetWidth(84)
	strip.colorEdit:SetPoint("LEFT", 320, 0)
	Widgets.Tooltip(strip.colorEdit, "Class colour", "Six hex digits, such as c41f3b: the colour Total RP 3 gives "
		.. "your name and class.")
	strip.save = Widgets.Button(strip, "Save", 80, Style.CONTROL.compact, "primary")
	strip.save:SetPoint("LEFT", 412, 0)
	Widgets.Tooltip(strip.save, "Save icon and colour", "Saves them in Dawnward. Total RP 3 follows while Profile "
		.. "icon and Class colour are kept up to date by Dawnward (below).")
	strip.save:SetScript("OnClick", function()
		H().act(function()
			local messages = {}
			for _, pair in ipairs({ { "icon", strip.iconEdit:GetText() }, { "classColor", strip.colorEdit:GetText() } }) do
				local text = pair[2] or ""
				local ok, message = ns.TRP3Commands.SetStatus(ctx(), pair[1], text ~= "" and text or nil)
				if not ok then return message end
				messages[#messages + 1] = message
			end
			return table.concat(messages, " ")
		end)
	end)
end

function M.RefreshLook(page, view)
	local strip = page.look
	local values = charValues()
	local rows = view.status and view.status.rows or {}
	load(strip.iconEdit, values.icon or "")
	load(strip.colorEdit, values.classColor or "")
	local icon = strip.iconEdit:GetText()
	strip.icon:SetTexture(iconPath(ns.Glance.CleanIcon(icon) or (rows.icon and rows.icon.trp3)))
	local color = ns.RPStatus.CleanColor(strip.colorEdit:GetText()) or (rows.classColor and rows.classColor.trp3)
	local r, g, b = 0.5, 0.5, 0.5
	if type(color) == "string" and color:match("^%x%x%x%x%x%x$") then
		r, g, b = tonumber(color:sub(1, 2), 16) / 255, tonumber(color:sub(3, 4), 16) / 255,
			tonumber(color:sub(5, 6), 16) / 255
	end
	Style.Color(strip.swatch, { r, g, b })
end

--- At First Glance ------------------------------------------------------------------

function M.BuildGlance(page, P, innerW)
	local HEAD = ns.TRP3Page.HEAD_HEIGHT
	local v = CreateFrame("Frame", nil, page.card)
	v:SetAllPoints(page.card)
	v:Hide()
	page.views.glance = v
	page.glanceSel = 1
	local LW, RW = M.GLANCE_LIST, innerW - M.GLANCE_LIST - M.GLANCE_GAP
	local C = Style.CONTROL.compact
	page.glanceRows = {}
	for n = 1, ns.Glance.SLOTS do
		local row = Widgets.Button(v, "", LW, M.GLANCE_ROW - 4, "choice")
		row:SetPoint("TOPLEFT", P, -(HEAD + (n - 1) * M.GLANCE_ROW))
		row.icon = iconTexture(row, 26)
		row.icon:SetPoint("LEFT", 8, 0)
		row.title = H().oneLine(row, "body", LW - 50, "body")
		row.title:SetPoint("TOPLEFT", 40, -4)
		row.state = H().oneLine(row, "muted", LW - 50, "small")
		row.state:SetPoint("TOPLEFT", 40, -22)
		row.n = n
		row:SetScript("OnClick", function(self)
			page.glanceSel = self.n
			page.glanceTitle.loaded, page.glanceText.loaded, page.glanceIconEdit.loaded = nil, nil, nil
			MainWindow.Refresh()
		end)
		page.glanceRows[n] = row
	end
	local syncTop = HEAD + ns.Glance.SLOTS * M.GLANCE_ROW + 6
	page.glanceSync = Widgets.Segmented(v, ns.TRP3Page.BLOCK_CHOICES, LW, Style.CONTROL.segment, function(policy)
		local on = policy == "dawnward"
		local d = H().deps()
		local entry = d and d.ledger.optIn[d.characterKey]
		if (entry and entry.glance == true) == on then return end
		if not on then
			H().act(function()
				local _, message = ns.TRP3Commands.SetFeature(ctx(), H().deps(), "glance", false)
				return message
			end)
			return
		end
		Widgets.Confirm(ns.TRP3Commands.EnableWarning("glance"), "Turn on", function()
			H().act(function()
				local _, message = ns.TRP3Commands.SetFeature(ctx(), H().deps(), "glance", true)
				return message
			end)
		end)
	end)
	page.glanceSync.buttons[1]:SetPoint("TOPLEFT", v, "TOPLEFT", P, -syncTop)
	for _, b in ipairs(page.glanceSync.buttons) do
		Widgets.Tooltip(b, "At First Glance sync", "Dawnward: your entries reach Total RP 3. Off: Dawnward writes "
			.. "nothing there.")
	end
	page.glanceState = H().paragraph(v, "muted", LW, 3, "small")
	page.glanceState:SetPoint("TOPLEFT", P, -(syncTop + Style.CONTROL.segment + 6))
	page.glanceStateHover = H().hoverOver(v, page.glanceState)

	-- The editor, right of the list.
	local x = P + LW + M.GLANCE_GAP
	page.glanceHead = eyebrow(v, "ENTRY 1")
	page.glanceHead:SetPoint("TOPLEFT", x, -HEAD)
	page.glanceTitle = Widgets.EditLine(v, ns.Glance.LIMITS.title + 1, C)
	page.glanceTitle:SetWidth(RW)
	page.glanceTitle:SetPoint("TOPLEFT", x, -(HEAD + 18))
	Widgets.Tooltip(page.glanceTitle, "Title", "A short title, such as \"Scarred hands\".")
	local area = Widgets.TextArea(v, ns.Glance.LIMITS.text + 1, RW)
	area.frame:SetPoint("TOPLEFT", x, -(HEAD + 18 + C + 6))
	area.frame:SetSize(RW, M.GLANCE_TEXT)
	page.glanceArea = area
	page.glanceText = area.edit
	local iconTop = HEAD + 18 + C + 6 + M.GLANCE_TEXT + 6
	page.glanceIcon = iconTexture(v, 30)
	page.glanceIcon:SetPoint("TOPLEFT", x, -iconTop)
	page.glanceIconEdit = Widgets.EditLine(v, ns.Glance.LIMITS.icon + 1, C)
	page.glanceIconEdit:SetWidth(150)
	page.glanceIconEdit:SetPoint("TOPLEFT", x + 36, -iconTop)
	page.glanceChoose = Widgets.Button(v, "Choose…", 84, C, "ghost")
	page.glanceChoose:SetPoint("TOPLEFT", x + 192, -iconTop)
	page.glanceChoose:SetScript("OnClick", function()
		M.OpenIconPicker(page, page.glanceIconEdit:GetText(), function(name)
			page.glanceIconEdit:SetText(name)
			page.glanceIcon:SetTexture(iconPath(name))
		end)
	end)
	local stateTop = iconTop + C + 6
	page.glanceShown = Widgets.Segmented(v, { { id = "shown", label = "Shown" }, { id = "hidden", label = "Hidden" } },
		160, Style.CONTROL.segment, function(id)
			page.glanceShownChoice = id
			page.glanceShown:Select(id)
		end)
	page.glanceShown.buttons[1]:SetPoint("TOPLEFT", v, "TOPLEFT", x, -stateTop)
	for _, b in ipairs(page.glanceShown.buttons) do
		Widgets.Tooltip(b, "Shown or hidden", "Total RP 3 sends only shown entries to other players.")
	end
	page.glanceUp = Widgets.Button(v, "\226\150\178", 30, Style.CONTROL.segment, "ghost")
	page.glanceUp:SetPoint("TOPLEFT", x + RW - 64, -stateTop)
	page.glanceDown = Widgets.Button(v, "\226\150\188", 30, Style.CONTROL.segment, "ghost")
	page.glanceDown:SetPoint("TOPLEFT", x + RW - 30, -stateTop)
	Widgets.Tooltip(page.glanceUp, "Move up", "Total RP 3 shows the entries in this order.")
	Widgets.Tooltip(page.glanceDown, "Move down", "Total RP 3 shows the entries in this order.")
	local function move(dir)
		local n = page.glanceSel
		H().act(function()
			local ok, message = ns.TRP3Commands.MoveGlance(ctx(), n, dir)
			if ok then
				page.glanceSel = n + dir
				page.glanceTitle.loaded, page.glanceText.loaded, page.glanceIconEdit.loaded = nil, nil, nil
			end
			return message
		end)
	end
	page.glanceUp:SetScript("OnClick", function() move(-1) end)
	page.glanceDown:SetScript("OnClick", function() move(1) end)
	local buttonsTop = stateTop + Style.CONTROL.segment + 8
	page.glanceSave = Widgets.Button(v, "Save", 90, C, "primary")
	page.glanceSave:SetPoint("TOPLEFT", x, -buttonsTop)
	page.glanceRemove = Widgets.Button(v, "Remove…", 90, C, "danger")
	page.glanceRemove:SetPoint("TOPLEFT", x + 98, -buttonsTop)
	page.glanceSave:SetScript("OnClick", function()
		local n = page.glanceSel
		local values = { title = page.glanceTitle:GetText(), text = page.glanceText:GetText(),
			icon = page.glanceIconEdit:GetText(), active = page.glanceShownChoice ~= "hidden" }
		H().act(function()
			local _, message = ns.TRP3Commands.SaveGlance(ctx(), n, values)
			return message
		end)
	end)
	page.glanceRemove:SetScript("OnClick", function()
		local n = page.glanceSel
		Widgets.Confirm("Remove At First Glance entry " .. n .. " from Dawnward?\n\nIf Dawnward wrote it to Total RP 3, "
			.. "it is removed there on the next sync (a backup is taken first). Entries you wrote in Total RP 3 stay.",
			"Remove", function()
				H().act(function()
					page.glanceTitle.loaded, page.glanceText.loaded, page.glanceIconEdit.loaded = nil, nil, nil
					page.glanceTitle:SetText("")
					page.glanceText:SetText("")
					local _, message = ns.TRP3Commands.SetGlance(ctx(), "clear", n)
					return message
				end)
			end)
	end)
	-- The preview: how Total RP 3 shows the entry (icon, title, text).
	local previewTop = buttonsTop + C + 10
	page.glancePreview = H().box(v, "add")
	page.glancePreview:SetPoint("TOPLEFT", x, -previewTop)
	page.glancePreview:SetSize(RW, page.mainHeight - previewTop - 14)
	page.glancePreviewIcon = iconTexture(page.glancePreview, 28)
	page.glancePreviewIcon:SetPoint("TOPLEFT", 8, -8)
	page.glancePreviewTitle = H().oneLine(page.glancePreview, "body", RW - 52, "body")
	page.glancePreviewTitle:SetPoint("TOPLEFT", 44, -8)
	page.glancePreviewText = H().paragraph(page.glancePreview, "navText", RW - 52,
		math.max(1, math.floor((page.glancePreview:GetHeight() - 34) / ns.TRP3Page.LINE)), "small")
	page.glancePreviewText:SetPoint("TOPLEFT", 44, -28)
	page.glancePreviewHover = H().hoverOver(page.glancePreview, page.glancePreview)
end

-- Where each of Dawnward's entries is in Total RP 3: { [n] = slotKey }, and
-- how many slots hold the player's own entries. Pure (from view).
function M.GlanceSlots(view)
	local check = view.checks.glance
	local misc = check and check.section
	local record = check and check.profileId and view.ledgerProfiles and view.ledgerProfiles[check.profileId]
	local owned = record and record.glance and record.glance.slots or {}
	local where, own = {}, 0
	for key, o in pairs(owned) do where[o.n] = key end
	for key, slot in pairs(misc and misc.PE or {}) do
		if not owned[key] and type(slot) == "table" and next(slot) ~= nil then own = own + 1 end
	end
	return where, own
end

function M.RefreshGlance(page, view)
	local plain, excerpt = H().plain, H().excerpt
	local char = H().realChar()
	local entries = char and char.glance or {}
	local check = view.checks.glance
	local chip = ns.TRP3Page.STATE_CHIP[check.state] or { check.state, "muted" }
	page.chip:SetChip(chip[1], chip[2])
	page.explain:SetText(M.GLANCE_EXPLAIN)
	local where, own = M.GlanceSlots(view)
	for n, row in ipairs(page.glanceRows) do
		local e = entries[n]
		row:SetSelected(page.glanceSel == n)
		row.icon:SetTexture(iconPath(e and e.icon))
		row.icon:SetShown(e ~= nil)
		row.title:SetText(e and plain(e.title or excerpt(e.text, 30)) or ("Entry " .. n .. " · empty"))
		row.state:SetText(e and ((e.active and "Shown" or "Hidden") .. (where[n] and (" · Total RP 3 slot " .. where[n])
			or "")) or "Write one here")
	end
	local on = view.bound and view.policies.glance == "dawnward"
	page.glanceSync:Select(on and "dawnward" or "off")
	page.glanceState:SetText((on and ("Sync on · " .. chip[1]) or "Sync off · nothing is written")
		.. (own > 0 and (" · " .. H().plural(own, "slot", "slots") .. " you filled in Total RP 3 (kept)") or ""))
	Widgets.Tooltip(page.glanceStateHover, "At First Glance sync", page.glanceState:GetText()
		.. (#(check.reasons or {}) > 0 and ("\n\n" .. plain(table.concat(check.reasons, "; "))) or ""))
	-- The editor for the selected entry.
	local n = page.glanceSel
	local e = entries[n]
	page.glanceHead:SetText("ENTRY " .. n)
	load(page.glanceTitle, e and e.title or "")
	load(page.glanceText, e and e.text or "")
	load(page.glanceIconEdit, e and e.icon or "")
	if page.glanceShownChoice == nil or page.glanceShownFor ~= n then
		page.glanceShownChoice = (e and not e.active) and "hidden" or "shown"
		page.glanceShownFor = n
	end
	page.glanceShown:Select(page.glanceShownChoice)
	local icon = ns.Glance.CleanIcon(page.glanceIconEdit:GetText()) or ns.Glance.DEFAULT_ICON
	page.glanceIcon:SetTexture(iconPath(icon))
	page.glanceUp:SetEnabled(e ~= nil and n > 1)
	page.glanceDown:SetEnabled(e ~= nil and n < ns.Glance.SLOTS)
	page.glanceRemove:SetEnabled(e ~= nil)
	-- The preview of what Total RP 3 shows (the editor's text, as typed).
	local title, text = page.glanceTitle:GetText() or "", page.glanceText:GetText() or ""
	page.glancePreviewIcon:SetTexture(iconPath(icon))
	page.glancePreviewTitle:SetText(title ~= "" and plain(title) or "(no title)")
	page.glancePreviewText:SetText(text ~= "" and plain(text) or "(no text)")
	local hidden = page.glanceShownChoice == "hidden"
	Widgets.Tooltip(page.glancePreviewHover, "How Total RP 3 shows it", hidden
		and "Hidden: Total RP 3 keeps it, but does not send it to other players."
		or "Other players see this icon, title and text at first glance.")
end

--- Status and OOC ------------------------------------------------------------------

local TEXT_IDS = { "currently", "ooc" }

function M.BuildStatus(page, P, innerW)
	local HEAD = ns.TRP3Page.HEAD_HEIGHT
	local v = CreateFrame("Frame", nil, page.card)
	v:SetAllPoints(page.card)
	v:Hide()
	page.views.status = v
	page.statusView = "text"
	page.statusNav = Widgets.Segmented(page.card, M.STATUS_VIEWS, 2 * 150, Style.CONTROL.segment, function(id)
		page.statusView = id
		MainWindow.Refresh()
	end)
	page.statusNav.buttons[1]:SetPoint("TOPLEFT", page.card, "TOPLEFT", P, -ns.TRP3Page.SUBNAV_TOP)
	page.statusSub = {}
	local C = Style.CONTROL.compact
	local S = 2 * M.SYNC_ITEM

	-- Currently and OOC.
	local tv = CreateFrame("Frame", nil, v)
	tv:SetAllPoints(v)
	page.statusSub.text = tv
	page.statusText = {}
	local blockH = 24 + M.TEXT_HEIGHT + 6 + 20 + 6 + C
	for i, id in ipairs(TEXT_IDS) do
		local m = ns.TRP3StatusPlan.STATUS.BY_ID[id]
		local top = HEAD + (i - 1) * (blockH + 12)
		local b = {}
		b.head = eyebrow(tv, m.trp3:upper())
		b.head:SetPoint("TOPLEFT", P, -top)
		b.count = H().oneLine(tv, "muted", 150, "small")
		b.count:SetPoint("TOPLEFT", P + 230, -top)
		b.sync = Widgets.Segmented(tv, M.SYNC_CHOICES, S, 20, function(policy)
			askManage(id, policy == "dawnward", m.label)
		end)
		b.sync.buttons[1]:SetPoint("TOPLEFT", tv, "TOPLEFT", P + innerW - S, -(top - 2))
		for _, btn in ipairs(b.sync.buttons) do
			Widgets.Tooltip(btn, "Keep in sync", "Sync on: what you save here reaches Total RP 3. Off: Total RP 3 "
				.. "keeps its own " .. m.trp3 .. ".")
		end
		b.area = Widgets.TextArea(tv, ns.RPStatus.LIMITS.text + 1, innerW)
		b.area.frame:SetPoint("TOPLEFT", P, -(top + 24))
		b.area.frame:SetSize(innerW, M.TEXT_HEIGHT)
		b.edit = b.area.edit
		local lineTop = top + 24 + M.TEXT_HEIGHT + 6
		b.detail = H().oneLine(tv, "muted", innerW - 80)
		b.detail:SetPoint("TOPLEFT", P, -lineTop)
		b.detailHover = H().hoverOver(tv, b.detail)
		b.import = Widgets.Button(tv, "Import", 72, 20, "ghost")
		b.import:SetPoint("TOPLEFT", tv, "TOPLEFT", P + innerW - 72, -lineTop)
		b.import:SetScript("OnClick", function()
			local row = page.view and page.view.status and page.view.status.rows[id]
			if row then askImport(id, m.trp3, row.trp3) end
		end)
		Widgets.Tooltip(b.import, "Import into Dawnward", "Copies Total RP 3's " .. m.trp3 .. " into this editor's "
			.. "saved value (you confirm first). Never automatic.")
		local buttonsTop = lineTop + 26
		b.save = Widgets.Button(tv, "Save", 80, C, "primary")
		b.save:SetPoint("TOPLEFT", P, -buttonsTop)
		b.save:SetScript("OnClick", function()
			local text = b.edit:GetText() or ""
			H().act(function()
				local _, message = ns.TRP3Commands.SetStatus(ctx(), id, text ~= "" and text or nil)
				return message
			end)
		end)
		b.clear = Widgets.Button(tv, "Clear", 80, C, "ghost")
		b.clear:SetPoint("TOPLEFT", P + 88, -buttonsTop)
		b.clear:SetScript("OnClick", function()
			b.edit:SetText("")
			H().act(function()
				local _, message = ns.TRP3Commands.SetStatus(ctx(), id, nil)
				return message
			end)
		end)
		Widgets.Tooltip(b.clear, "Clear", "Empties it in Dawnward; Total RP 3's copy is emptied on the next sync if "
			.. "Dawnward wrote it.")
		if id == "currently" then
			b.suggest = Widgets.Button(tv, "Suggest", 96, C, "ghost")
			b.suggest:SetPoint("TOPLEFT", P + 176, -buttonsTop)
			b.suggest:SetScript("OnClick", function() M.Suggest(page) end)
			Widgets.Tooltip(b.suggest, "Suggest", "Drafts a Currently text from where you are and your active goal, "
				.. "in the editor only. Nothing is saved until you press Save.")
		end
		page.statusText[id] = b
	end

	-- Status and style.
	local sv = CreateFrame("Frame", nil, v)
	sv:SetAllPoints(v)
	sv:Hide()
	page.statusSub.style = sv
	page.statusChoice = {}
	for i, id in ipairs({ "rpStatus", "walkup" }) do
		local f = ns.RPStatus.BY_ID[id]
		local top = HEAD + (i - 1) * 50
		local r = {}
		r.name = H().oneLine(sv, "body", 140, "body")
		r.name:SetPoint("TOPLEFT", P, -(top + 2))
		r.name:SetText(f.label)
		local items = {}
		for _, o in ipairs(f.options) do items[#items + 1] = { id = o.value, label = o.label } end
		r.seg = Widgets.Segmented(sv, items, 2 * 124, 24, function(value)
			H().act(function()
				local _, message = ns.TRP3Commands.SetStatus(ctx(), id, value)
				return message
			end)
		end)
		r.seg.buttons[1]:SetPoint("TOPLEFT", sv, "TOPLEFT", P + 146, -top)
		r.sync = Widgets.Segmented(sv, M.SYNC_CHOICES, S, 20, function(policy)
			askManage(id, policy == "dawnward", f.label)
		end)
		r.sync.buttons[1]:SetPoint("TOPLEFT", sv, "TOPLEFT", P + innerW - S, -(top + 2))
		r.detail = H().oneLine(sv, "muted", innerW)
		r.detail:SetPoint("TOPLEFT", P, -(top + 28))
		r.detailHover = H().hoverOver(sv, r.detail)
		page.statusChoice[id] = r
	end
	local styleTop = HEAD + 2 * 50 + 4
	local head = eyebrow(sv, "ROLEPLAY STYLE")
	head:SetPoint("TOPLEFT", P, -(styleTop + 6))
	page.openTRP3 = Widgets.Button(sv, "Open in Total RP 3", 160, 24, "ghost")
	page.openTRP3:SetPoint("TOPLEFT", sv, "TOPLEFT", P + innerW - 160, -styleTop)
	page.openTRP3:SetScript("OnClick", function()
		H().act(function()
			local _, message = ns.TRP3Commands.OpenInTRP3(ctx())
			return message
		end)
	end)
	Widgets.Tooltip(page.openTRP3, "Open in Total RP 3", "Opens your profile in Total RP 3; its Miscellaneous tab "
		.. "holds the roleplay style. Not while a Total RP 3 editor holds unsaved changes.")
	page.styleNote = H().oneLine(sv, "muted", innerW, "small")
	page.styleNote:SetPoint("TOPLEFT", P, -(styleTop + 28))
	page.styleNote:SetText(M.STYLE_NOTE)
	page.styleNoteHover = H().hoverOver(sv, page.styleNote)
	Widgets.Tooltip(page.styleNoteHover, "Roleplay style", M.STYLE_NOTE)
	page.styleRows = {}
	for i, s in ipairs(ns.RPStatus.STYLE) do
		local top = styleTop + 50 + (i - 1) * M.STYLE_ROW
		local r = {}
		r.name = H().oneLine(sv, "body", M.STYLE_LABEL - 8, "body")
		r.name:SetPoint("TOPLEFT", P, -(top + 4))
		r.name:SetText(s.label)
		r.hover = H().hoverOver(sv, r.name)
		Widgets.Tooltip(r.hover, s.label, s.help)
		r.value = Widgets.Button(sv, "", M.STYLE_VALUE, 26, "default")
		r.value:SetPoint("TOPLEFT", sv, "TOPLEFT", P + M.STYLE_LABEL, -top)
		r.value:SetScript("OnClick", function() M.CycleStyle(page, s) end)
		r.manage = Widgets.Segmented(sv, M.MANAGE_CHOICES, 2 * 70, 22, function(policy)
			askManage(s.id, policy == "dawnward", "roleplay style preference \"" .. s.label .. "\"", true)
		end)
		r.manage.buttons[1]:SetPoint("TOPLEFT", sv, "TOPLEFT", P + innerW - 140, -(top + 2))
		for _, btn in ipairs(r.manage.buttons) do
			Widgets.Tooltip(btn, "Who manages it", "TRP3 (the default): read only here; change it in Total RP 3. "
				.. "Dawnward: you edit it here and Dawnward keeps Total RP 3 up to date.")
		end
		page.styleRows[i] = r
	end
end

--- Shows or hides the Status and OOC switch (it replaces the explanation).
function M.ShowStatusNav(page, on)
	for _, b in ipairs(page.statusNav.buttons) do b:SetShown(on) end
	if page.statusNav.track then page.statusNav.track:SetShown(on) end
end

--- The next value of a managed style preference (from Dawnward's, else
-- Total RP 3's), saved in Dawnward.
function M.CycleStyle(page, s)
	local values = charValues()
	local row = page.view and page.view.status and page.view.status.rows[s.id]
	local current = values.style[s.key]
	if current == nil then current = row and row.trp3 or 0 end
	local nextValue = s.options[1].value
	for i, o in ipairs(s.options) do
		if o.value == current then nextValue = s.options[i % #s.options + 1].value end
	end
	H().act(function()
		local _, message = ns.TRP3Commands.SetStyle(ctx(), s.key, nextValue)
		return message
	end)
end

--- Suggest: a Currently draft from the zone and the active goal, put in the
-- editor only (never saved by itself, never on a zone change).
function M.Suggest(page)
	local zone
	if type(GetRealZoneText) == "function" then
		local ok, z = pcall(GetRealZoneText)
		zone = ok and z or nil
	end
	local text = ns.RPStatus.Suggest(H().realChar(), zone)
	if not text then
		MainWindow.SetStatus("Nothing to suggest yet: Dawnward knows no zone or active goal.")
		return
	end
	page.statusText.currently.edit:SetText(text)
	MainWindow.SetStatus("Suggestion placed in the editor. Change it as you like; nothing is saved until you press "
		.. "Save.")
end

-- A row's detail line: what Total RP 3 shows, and its state.
local function detailText(row, m, kind)
	local plain, excerpt = H().plain, H().excerpt
	local shown = row and (kind == "style" and ns.TRP3StylePlan.Display(m, row.trp3)
		or ns.TRP3StatusPlan.Display(m, row.trp3))
	local text = "Total RP 3 shows: " .. (shown and ("\"" .. excerpt(shown, 70) .. "\"") or "nothing")
	if row and row.conflict then
		return "Paused: " .. plain(row.conflict) .. ". Choose in Synchronization > Recovery, or Import.", true
	elseif row and row.policy == "dawnward" then
		text = text .. (row.owned and " · kept up to date by Dawnward" or (row.differ and " · differs" or ""))
	else
		text = text .. " · Total RP 3 keeps it"
	end
	return text, false
end

function M.RefreshStatus(page, view)
	local values = charValues()
	local rows = view.status and view.status.rows or {}
	page.statusNav:Select(page.statusView)
	page.statusSub.text:SetShown(page.statusView == "text")
	page.statusSub.style:SetShown(page.statusView == "style")
	local managed, conflicts = 0, 0
	for _, row in pairs(rows) do
		if row.feature ~= "look" then
			if view.bound and row.policy == "dawnward" then managed = managed + 1 end
			if row.conflict then conflicts = conflicts + 1 end
		end
	end
	page.chip:SetChip(conflicts > 0 and H().plural(conflicts, "conflict", "conflicts")
		or (managed > 0 and (managed .. " in sync") or "Total RP 3 keeps these"),
		conflicts > 0 and "waiting" or (managed > 0 and "public" or "muted"))
	page.explain:SetText("")
	for _, id in ipairs(TEXT_IDS) do
		local b = page.statusText[id]
		local m = ns.TRP3StatusPlan.STATUS.BY_ID[id]
		local row = rows[id]
		load(b.edit, values[id] or "")
		local typed = b.edit:GetText() or ""
		b.count:SetText(#typed .. " / " .. ns.RPStatus.TOOLTIP_CHARS .. " in tooltips")
		local text, warn = detailText(row, m, "status")
		b.detail:SetText(text)
		ns.TRP3Page.SetWarning(b.detail, warn)
		Widgets.Tooltip(b.detailHover, m.trp3, row and row.trp3 and H().plain(row.trp3) or "Empty in Total RP 3.")
		b.sync:Select(row and view.bound and row.policy == "dawnward" and "dawnward" or "trp3")
		b.import:SetEnabled(row ~= nil and row.importable == true)
	end
	for _, id in ipairs({ "rpStatus", "walkup" }) do
		local r = page.statusChoice[id]
		local m = ns.TRP3StatusPlan.STATUS.BY_ID[id]
		local row = rows[id]
		r.seg:Select(values[id] or (row and row.trp3))
		local text, warn = detailText(row, m, "status")
		if values[id] == nil then text = text .. " · not set in Dawnward" end
		r.detail:SetText(text)
		ns.TRP3Page.SetWarning(r.detail, warn)
		Widgets.Tooltip(r.detailHover, m.trp3, text)
		r.sync:Select(row and view.bound and row.policy == "dawnward" and "dawnward" or "trp3")
	end
	for i, s in ipairs(ns.RPStatus.STYLE) do
		local r = page.styleRows[i]
		local row = rows[s.id]
		local m = ns.TRP3StylePlan.BY_ID[s.id]
		local on = row ~= nil and view.bound and row.policy == "dawnward"
		local mine = values.style[s.key]
		local shown = on and (mine ~= nil and mine or (row and row.trp3)) or (row and row.trp3)
		r.value:SetText(ns.TRP3StylePlan.Display(m, shown))
		r.value:SetEnabled(on)
		r.manage:Select(on and "dawnward" or "trp3")
		local text = detailText(row, m, "style")
		Widgets.Tooltip(r.value, s.label, (on and "Click to change it (saved in Dawnward; Total RP 3 follows on the "
			.. "next sync). " or "Read only: Total RP 3 manages it. ") .. text)
	end
end
