-- The settings panel behind the gear button, in four pages (General, Story,
-- Data, Total RP 3) rather than a fourth section: theme gallery, minimap,
-- guide and setup; story moment settings; backup, import and simulation
-- mode; the Total RP 3 sync page (UI/TRP3Page.lua).
-- Actions reuse the slash command code, so behaviour is identical.
--
-- Layout (v0.8, docs/design/mockups/proposed-trp3-sync.png and the design
-- system): the page switcher sits at the top of the content area with Done
-- at its right; each page groups its controls in panels (the design's
-- cards) with an eyebrow heading and a one-line description. A setting is a
-- row: its name and a short description on the left, its control on the
-- right. Story settings show every option at once as a segmented control,
-- the one in use raised and edged (no hidden "click to cycle" state).
local _, ns = ...
local Widgets, Style, MainWindow, Themes, Actions, Commands =
	ns.Widgets, ns.Style, ns.MainWindow, ns.Themes, ns.Actions, ns.Commands

local SettingsPanel = {}
ns.SettingsPanel = SettingsPanel

-- navHeight: the page switcher; pageTop: where a page starts; gap: between
-- panels; row: a setting row; control: the control column of a row;
-- button: an action button in a row; tile: a theme tile.
SettingsPanel.LAYOUT = { navHeight = 36, navItem = 104, done = 96, pageTop = 50, gap = 12, row = 44,
	control = 360, button = 200, tile = 40, minSegment = 64, segmentPad = 20 }
local LAY = SettingsPanel.LAYOUT

SettingsPanel.BACKUP_HINT = "A backup includes private entries but not secrets "
	.. "(to include them: /dawnward export backup secrets). Sharing exports contain public facts only."

-- Story settings, each shown as a segmented control. values: the cycle order
-- (NextValue, the chat commands' order); order: the order on screen when it
-- differs; short: the line under the name; help: the tooltip.
-- tracking settings switch an event category.
SettingsPanel.STORY_SETTINGS = {
	{ key = "frequency", label = "Moments", values = { "rare", "normal", "frequent", "off" },
		short = "How often Dawnward may offer a story moment.",
		help = "How often Dawnward may offer a story moment. Off still records events." },
	{ key = "threshold", label = "Significance", values = { 1, 2, 3 },
		short = "Which recorded events may become a moment.",
		help = "1: any recorded event may become a moment. 3: only major ones." },
	{ key = "places", label = "Places", values = { "on", "fewer", "off" },
		short = "Moments about beginnings, settlements and returns.",
		help = "Moments about places: beginnings, settlements, returns. Fewer: notable places only. "
			.. "Off: places are still recorded, never asked about." },
	{ key = "pace", label = "Story pace", values = { "standard", "brisk", "slow" },
		order = { "brisk", "standard", "slow" },
		short = "How much play makes one narrative day.",
		help = "How much play makes a narrative day: Brisk 1 hour, Standard 2 hours, Slow 4 hours. Returns to a "
			.. "place and story cooldowns count only time you play, never time offline." },
	{ key = "card", label = "Card", values = { true, false },
		short = "A small card when a moment waits (never in combat).",
		help = "Show a small card when a moment is waiting (never in combat). Off: one chat line only." },
	{ key = "flavor", label = "Class flavour", values = { true, false },
		short = "One optional extra answer flavoured by your class.",
		help = "Offer one optional extra answer flavoured by your class. Never changes the others." },
	{ key = "approval", label = "Changes", values = { "ask", "auto" },
		short = "Personality changes wait for you, or apply at once.",
		help = "Ask: personality changes wait for your approval. Auto: applied at once, still reversible." },
	{ key = "drafts", label = "Drafts", values = { true, false },
		short = "A private journal draft for each answer.",
		help = "Write a private journal draft for each answer." },
	{ tracking = "quest", label = "Quests", values = { true, false },
		short = "Record completed quests as story events.",
		help = "Record completed quests as story events." },
	{ key = "trp3Style", label = "TRP3 style", values = { "neutral", "silverhand", "arcane" },
		short = "How Dawnward's own section looks in Total RP 3.",
		help = "How Dawnward's own section looks in Total RP 3 (only if you turned biography sync on)." },
}

local function currentValue(setting, prefs)
	if setting.tracking then
		return prefs.tracking[setting.tracking]
	end
	return prefs[setting.key]
end

--- The value after the current one, in cycle order (as the chat command). Pure.
function SettingsPanel.NextValue(setting, prefs)
	local value = currentValue(setting, prefs)
	for i, v in ipairs(setting.values) do
		if v == value then
			return setting.values[i % #setting.values + 1]
		end
	end
	return setting.values[1]
end

-- How each stored value reads on screen.
SettingsPanel.VALUE_LABELS = {
	rare = "Rare", normal = "Normal", frequent = "Frequent", off = "Off", on = "On", fewer = "Fewer",
	ask = "Ask me", auto = "Automatic", neutral = "Neutral", silverhand = "Silver Hand", arcane = "Arcane",
	standard = "Standard (2 h)", brisk = "Brisk (1 h)", slow = "Slow (4 h)",
	[1] = "Any event", [2] = "Notable", [3] = "Major only",
}

--- A value as the player reads it. Pure.
function SettingsPanel.ValueText(value)
	if type(value) == "boolean" then
		return value and "On" or "Off"
	end
	return SettingsPanel.VALUE_LABELS[value] or tostring(value)
end

--- "Moments: Normal": the setting and its current value. Pure.
function SettingsPanel.ButtonText(setting, prefs)
	return setting.label .. ": " .. SettingsPanel.ValueText(currentValue(setting, prefs))
end

--- The tooltip: what it does, then every option with the current one
-- marked. Pure.
function SettingsPanel.ButtonHelp(setting, prefs)
	local value = currentValue(setting, prefs)
	local options = {}
	for _, v in ipairs(setting.order or setting.values) do
		local text = SettingsPanel.ValueText(v)
		options[#options + 1] = v == value and ("[" .. text .. "]") or text
	end
	return setting.help .. "\n\nOptions: " .. table.concat(options, " · ") .. "\nClick an option to use it."
end

--- The options of a setting as segmented items, in screen order. Pure.
function SettingsPanel.Options(setting)
	local items = {}
	for _, v in ipairs(setting.order or setting.values) do
		items[#items + 1] = { id = v, label = SettingsPanel.ValueText(v) }
	end
	return items
end

--- Width of a setting's segmented control: every option as wide as the
-- widest label needs (Style.TextWidth), never wider than the control
-- column. Pure.
function SettingsPanel.SegmentWidth(setting)
	local widest = LAY.minSegment
	for _, item in ipairs(SettingsPanel.Options(setting)) do
		local need = math.ceil(Style.TextWidth(item.label, "buttonSmall")) + LAY.segmentPad + 2
		if need > widest then widest = need end
	end
	return math.min(LAY.control, widest * #setting.values)
end

SettingsPanel.PAGES = {
	{ id = "general", label = "General" },
	{ id = "story", label = "Story" },
	{ id = "data", label = "Data" },
	{ id = "trp3", label = "Total RP 3" },
}

--- Building blocks ------------------------------------------------------------------

local PAD = Widgets.PANEL_PAD
local TITLE_H = 22   -- a panel's eyebrow title line
local LINE = 17      -- one line of 14 px text

-- A titled panel at y on page, full width, with an optional description
-- (meta, muted, at most two lines). Returns the panel and the y (inside
-- panel.inner) where its controls start.
local function section(page, width, title, y, height, description)
	local p = Widgets.Panel(page, title)
	p:SetPoint("TOPLEFT", 0, y)
	p:SetSize(width, height)
	local top = 0
	if description then
		p.description = Widgets.Label(p.inner, "meta", true, "muted")
		p.description:SetPoint("TOPLEFT", 0, 0)
		p.description:SetWidth(width - 2 * PAD)
		p.description:SetMaxLines(2)
		p.description:SetText(description)
		top = -(description == "" and 2 * LINE or math.max(1, math.ceil(Style.TextWidth(description, "meta")
			/ (width - 2 * PAD))) * LINE) - 10
	end
	return p, top
end

-- One setting row inside a panel: name (field-label tone, bold 14) over a
-- one-line description (meta, muted). The control goes in the right column
-- (callers anchor it to row.control). A 1 px rule separates rows.
local function settingRow(parent, y, width, name, description, help, controlWidth, first)
	local row = CreateFrame("Frame", nil, parent)
	row:SetPoint("TOPLEFT", 0, y)
	row:SetSize(width, LAY.row)
	if not first then
		row.rule = Widgets.Divider(row)
		row.rule:SetPoint("TOPLEFT", 0, 0)
		row.rule:SetPoint("TOPRIGHT", 0, 0)
	end
	local textWidth = width - controlWidth - 16
	row.name = Widgets.Label(row, "GameFontNormal", false, "heading")
	row.name:SetPoint("TOPLEFT", 0, -5)
	row.name:SetWidth(textWidth)
	row.name:SetText(name)
	row.description = Widgets.Label(row, "meta", false, "muted")
	row.description:SetPoint("TOPLEFT", 0, -23)
	row.description:SetWidth(textWidth)
	row.description:SetText(description)
	row.textWidth = textWidth
	-- The text side shows the full help on hover.
	row.hover = CreateFrame("Frame", nil, row)
	row.hover:SetPoint("TOPLEFT", 0, 0)
	row.hover:SetSize(textWidth, LAY.row)
	Widgets.Tooltip(row.hover, name, help or description)
	row.controlX = width - controlWidth
	return row
end

-- A button in a row's control column, vertically centred.
local function rowButton(row, text, width, variant)
	local b = Widgets.Button(row, text, width, Style.CONTROL.compact, variant)
	b:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -math.floor((LAY.row - Style.CONTROL.compact) / 2))
	return b
end

local function create(parent)
	local panel = { frame = CreateFrame("Frame", nil, parent), labels = {}, pages = {}, page = "general" }
	local f = panel.frame
	local W = MainWindow.ContentWidth()
	local H = MainWindow.ContentHeight() - LAY.pageTop
	local innerW = W - 2 * PAD
	panel.width, panel.pageHeight = W, H
	-- The window's ground, so the panels read as cards on it (as the mockup).
	panel.background = Style.Fill(f, "background", "BACKGROUND")
	panel.background:SetAllPoints(f)

	local function run(command)
		Commands.Execute(ns.ctx, command)
		MainWindow.Refresh()
	end

	-- Page switcher (design: sub-tabs in a track), Done at the right.
	panel.nav = Widgets.Segmented(f, SettingsPanel.PAGES, LAY.navItem * #SettingsPanel.PAGES, LAY.navHeight,
		function(id)
			panel.page = id
			MainWindow.Refresh()
		end)
	panel.nav.buttons[1]:SetPoint("TOPLEFT", 0, 0)
	for _, page in ipairs(SettingsPanel.PAGES) do
		local p = CreateFrame("Frame", nil, f)
		p:SetPoint("TOPLEFT", 0, -LAY.pageTop)
		p:SetPoint("BOTTOMRIGHT", 0, 0)
		panel.pages[page.id] = p
	end
	panel.done = Widgets.Button(f, "Done", LAY.done, Style.CONTROL.standard)
	panel.done:SetPoint("TOPRIGHT", 0, 0)
	panel.done:SetScript("OnClick", MainWindow.ToggleSettings)
	Widgets.Tooltip(panel.done, "Done", "Back to the journal. Settings are saved as you change them.")

	-- General: appearance --------------------------------------------------------
	local tileWidth = math.floor((innerW - 16) / 3)
	local themeRows = math.ceil(#Themes.LIST / 3)
	local appearanceH = PAD + TITLE_H + LINE + 10 + themeRows * (LAY.tile + 8) + 2 + 2 * LINE + PAD
	local appearance, y = section(panel.pages.general, W, "Appearance", 0, appearanceH,
		"Changes only how this character's journal looks. Themes never depend on class, race or faction.")
	panel.appearance = appearance
	panel.themeButtons = {}
	for i, theme in ipairs(Themes.LIST) do
		local button = Widgets.Button(appearance.inner, theme.name, tileWidth, LAY.tile, "choice")
		local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
		button:SetPoint("TOPLEFT", col * (tileWidth + 8), y - row * (LAY.tile + 8))
		-- Three round swatches: background, surface and accent of that theme.
		button.swatches = {}
		for k, role in ipairs({ "background", "surface", "accent" }) do
			local ring = Style.Disc(button, "ARTWORK", 0, 16)
			ring:SetPoint("RIGHT", -10 - (3 - k) * 20, 0)
			local sw = Style.Disc(button, "ARTWORK", 1, ring.round and 14 or 16)
			sw:SetPoint("CENTER", ring, "CENTER", 0, 0)
			Widgets.SetColor(sw, theme[role])
			Style.Register(ring, function(t, current) Style.Color(t, current.edge) end)
			button.swatches[k] = sw
		end
		-- The theme in use also carries a gold bar on its left edge.
		button.mark = Style.Solid(button, "ARTWORK", 2)
		button.mark:SetPoint("TOPLEFT", 0, 0)
		button.mark:SetPoint("BOTTOMLEFT", 0, 0)
		button.mark:SetWidth(3)
		Style.Register(button.mark, function(t, current) Style.Color(t, current.accent) end)
		button.mark:Hide()
		button.themeId = theme.id
		button:SetScript("OnClick", function()
			local _, message = Actions.SetTheme(ns.ctx, theme.id)
			MainWindow.SetStatus(message)
			MainWindow.Refresh()
		end)
		Widgets.Tooltip(button, theme.name, theme.description)
		panel.themeButtons[#panel.themeButtons + 1] = button
	end
	panel.themeDescription = Widgets.Label(appearance.inner, "meta", true, "body")
	panel.themeDescription:SetPoint("TOPLEFT", 0, y - themeRows * (LAY.tile + 8) - 2)
	panel.themeDescription:SetWidth(innerW)
	panel.themeDescription:SetMaxLines(2)

	-- General: interface and help ----------------------------------------------------
	local interfaceY = -(appearanceH + LAY.gap)
	local interface = section(panel.pages.general, W, "Interface and help", interfaceY,
		PAD + TITLE_H + 4 * LAY.row + PAD - 6)
	panel.interface = interface
	local rows = {}
	local function generalRow(i, name, description, help)
		rows[i] = settingRow(interface.inner, -(i - 1) * LAY.row, innerW, name, description, help, LAY.button, i == 1)
		return rows[i]
	end
	generalRow(1, "Minimap button", "Show or hide the Dawnward button on the minimap.",
		"Show or hide the Dawnward button on the minimap. Drag the button to move it.")
	panel.minimap = rowButton(rows[1], "Minimap button: shown", LAY.button)
	panel.minimap:SetScript("OnClick", function() run("minimap") end)
	Widgets.Tooltip(panel.minimap, "Minimap button", "Show or hide the Dawnward button on the minimap. "
		.. "Drag the button to move it.")
	generalRow(2, "Guide", "How the journal, story moments, privacy and Total RP 3 work.")
	panel.guide = rowButton(rows[2], "Open the guide", LAY.button)
	panel.guide:SetScript("OnClick", function() run("guide") end)
	generalRow(3, "First-time setup", "Walk through the setup steps again.",
		"Walk through the setup steps again: name, story moments, privacy and appearance. Nothing is saved until "
			.. "you choose Finish.")
	panel.setup = rowButton(rows[3], "Run setup", LAY.button)
	panel.setup:SetScript("OnClick", function() run("setup") end)
	Widgets.Tooltip(panel.setup, "First-time setup", "Walk through the setup steps again: name, story moments, "
		.. "privacy and appearance. Nothing is saved until you choose Finish.")
	generalRow(4, "Window size", "Drag the gold grip in the bottom-right corner to resize.",
		"Drag the gold grip in the bottom-right corner to resize the window. Reset returns it to its design size.")
	panel.resetSize = rowButton(rows[4], "Reset window size", LAY.button)
	panel.resetSize:SetScript("OnClick", function()
		MainWindow.ResetSize()
		MainWindow.SetStatus("The window is back to its design size (smaller if your screen needs it).")
	end)
	Widgets.Tooltip(panel.resetSize, "Window size", "Drag the gold grip in the bottom-right corner to resize "
		.. "the window. This returns it to its design size.")
	panel.generalRows = rows

	-- Story ---------------------------------------------------------------------------
	local storyH = PAD + TITLE_H + LINE + 10 + #SettingsPanel.STORY_SETTINGS * LAY.row + PAD - 6
	local story, storyTop = section(panel.pages.story, W, "Story settings", 0, storyH,
		"For this character only. Every option is shown; the highlighted one is in use. Hover a setting for details.")
	panel.story = story
	panel.storyRows = {}
	for i, setting in ipairs(SettingsPanel.STORY_SETTINGS) do
		local row = settingRow(story.inner, storyTop - (i - 1) * LAY.row, innerW, setting.label, setting.short,
			setting.help, LAY.control, i == 1)
		row.setting = setting
		local width = SettingsPanel.SegmentWidth(setting)
		row.control = Widgets.Segmented(row, SettingsPanel.Options(setting), width, Style.CONTROL.compact,
			function(value)
				local _, message
				if setting.tracking then
					_, message = Actions.SetTracking(ns.ctx, setting.tracking, value)
				else
					_, message = Actions.SetStoryPref(ns.ctx, setting.key, value)
				end
				MainWindow.SetStatus(message)
				MainWindow.Refresh()
			end)
		-- Every control starts at the same column, so the options line up.
		row.control.buttons[1]:SetPoint("TOPLEFT", row.controlX, -math.floor((LAY.row - Style.CONTROL.compact) / 2))
		row.control.width = width
		for _, b in ipairs(row.control.buttons) do
			Widgets.Tooltip(b, setting.label .. ": " .. SettingsPanel.ValueText(b.segmentId), setting.help)
		end
		panel.storyRows[i] = row
	end

	-- Data ------------------------------------------------------------------------------
	local dataH = PAD + TITLE_H + 2 * LINE + 10 + Style.CONTROL.compact + PAD
	local backup = section(panel.pages.data, W, "Backup and sharing", 0, dataH, SettingsPanel.BACKUP_HINT)
	panel.backupPanel = backup
	panel.backupHint = backup.description
	-- Two lines of description are reserved in every Data panel.
	local by = -(2 * LINE + 10)
	panel.exportBackup = Widgets.Button(backup.inner, "Export backup", 150, Style.CONTROL.compact)
	panel.exportBackup:SetPoint("TOPLEFT", 0, by)
	panel.exportBackup:SetScript("OnClick", function() run("export backup") end)
	Widgets.Tooltip(panel.exportBackup, "Export backup", "Everything except secrets, as text to copy and keep.")
	panel.exportShare = Widgets.Button(backup.inner, "Export for sharing", 170, Style.CONTROL.compact)
	panel.exportShare:SetPoint("LEFT", panel.exportBackup, "RIGHT", 8, 0)
	panel.exportShare:SetScript("OnClick", function() run("export share") end)
	Widgets.Tooltip(panel.exportShare, "Export for sharing", "Public facts only, as text to give to someone.")
	panel.import = Widgets.Button(backup.inner, "Import backup", 150, Style.CONTROL.compact)
	panel.import:SetPoint("LEFT", panel.exportShare, "RIGHT", 8, 0)
	panel.import:SetScript("OnClick", function() run("import") end)
	Widgets.Tooltip(panel.import, "Import backup", "Paste a backup you exported earlier. You see what it contains "
		.. "before anything is replaced.")

	local storyPanel = section(panel.pages.data, W, "Your story", -(dataH + LAY.gap), dataH, "")
	panel.storyPanel = storyPanel
	panel.storyState = storyPanel.description
	panel.importStory = Widgets.Button(storyPanel.inner, "Import a story...", 170, Style.CONTROL.compact)
	panel.importStory:SetPoint("TOPLEFT", 0, by)
	panel.importStory:SetScript("OnClick", function() ns.ImportWizard.Open({ from = "settings" }) end)
	Widgets.Tooltip(panel.importStory, "Import a story", "Paste a backstory you already wrote, or read your Total RP 3 "
		.. "About text. It is kept exactly as written; you approve each piece before it becomes part of your "
		.. "character.")

	local sim = section(panel.pages.data, W, "Simulation mode", -2 * (dataH + LAY.gap), dataH, "")
	panel.simPanel = sim
	panel.simState = sim.description
	panel.simToggle = Widgets.Button(sim.inner, "Turn on", 150, Style.CONTROL.compact)
	panel.simToggle:SetPoint("TOPLEFT", 0, by)
	panel.simToggle:SetScript("OnClick", function()
		run(ns.ctx.store:IsSimulation() and "sim off" or "sim on")
	end)
	panel.simReset = Widgets.Button(sim.inner, "Reset test data", 150, Style.CONTROL.compact, "danger")
	panel.simReset:SetPoint("LEFT", panel.simToggle, "RIGHT", 8, 0)
	panel.simReset:SetScript("OnClick", function()
		Widgets.Confirm("Delete ALL simulation test data for every character?\n\nYour real data is not affected.",
			"Reset", function() run("sim reset confirm") end)
	end)

	-- Total RP 3 ------------------------------------------------------------------------
	-- Built by UI/TRP3Page.lua; it reuses the /dawnward trp3 functions.
	panel.trp3Page = ns.TRP3Page.Build(panel.pages.trp3, W, H)
	-- The detected status lines (also shown when Total RP 3 is absent).
	panel.trp3 = panel.trp3Page.absentStatus

	-- Every part paints itself (UI/Style.lua).
	function panel.ApplyTheme() end

	function panel:Refresh(view)
		self.nav:Select(self.page)
		for id, p in pairs(self.pages) do
			p:SetShown(id == self.page)
		end
		local current = Actions.ThemeOf(view.char)
		for _, button in ipairs(self.themeButtons) do
			local on = button.themeId == current.id
			button:SetSelected(on)
			button.mark:SetShown(on)
		end
		self.themeDescription:SetText(current.name .. " (current): " .. current.description)

		local simulation = view.ctx.store:IsSimulation()
		self.simState:SetText(simulation
			and "ON: changes go to separate test data. Your real journal is untouched."
			or "OFF: you are using your real journal. Turn on to experiment safely.")
		self.simToggle:SetText(simulation and "Turn off" or "Turn on")
		local lines = ns.StoryImport.StatusLines(view.char)
		self.storyState:SetText(table.concat(lines, " "))

		local prefs = view.char and view.char.story.prefs or ns.StorySchema.NewPrefs()
		for _, row in ipairs(self.storyRows) do
			row.control:Select(currentValue(row.setting, prefs))
			Widgets.Tooltip(row.hover, row.setting.label, SettingsPanel.ButtonHelp(row.setting, prefs))
		end

		self.minimap:SetText(Actions.MinimapSettings(view.ctx).hidden and "Minimap button: hidden"
			or "Minimap button: shown")

		-- Only while its page is open (it reads Total RP 3); read-only either way.
		if self.page == "trp3" then
			self.trp3Page:Refresh()
			local frame = MainWindow.GetFrame()
			if frame and frame.title then
				frame.title:SetText("Total RP 3")
			end
		end
	end

	SettingsPanel.panel = panel
	return panel
end

MainWindow.createSettings = create

--- Opens the main window on Settings with the given page selected
-- ("general", "story", "data" or "trp3"). Returns true when it is shown.
function SettingsPanel.OpenPage(pageId)
	local known = false
	for _, page in ipairs(SettingsPanel.PAGES) do
		if page.id == pageId then known = true end
	end
	if not known then
		return false
	end
	if not MainWindow.IsShown() then
		MainWindow.Show()
	end
	local panel = SettingsPanel.panel
	if not MainWindow.IsShown() or not panel then
		return false
	end
	panel.page = pageId
	if MainWindow.CurrentSection() ~= "settings" then
		MainWindow.ToggleSettings()
	else
		MainWindow.Refresh()
	end
	return true
end
