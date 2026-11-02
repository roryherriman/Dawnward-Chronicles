-- The settings panel behind the gear button, in five pages organised by
-- purpose (v0.10): General (theme, minimap button, window size), Story (how
-- often and how moments come, and what is recorded), Data (backups, export,
-- import, your story), Total RP 3 (UI/TRP3Page.lua) and Help (guide, setup,
-- chat commands; simulation mode and the setup preview only in development
-- builds, or while simulation is on so it can be turned off).
-- Actions reuse the slash command code, so behaviour is identical.
--
-- Layout (v0.8, docs/design/mockups/proposed-trp3-sync.png and the design
-- system): the page switcher sits at the top of the content area with Done
-- at its right; each page groups its controls in panels (the design's
-- cards) with an eyebrow heading and a one-line description. A setting is a
-- row: its name and a short description on the left, its control on the
-- right. Every choice shows all its options at once as a segmented control,
-- the one in use raised and edged (no hidden "click to cycle" state); the
-- minimap button too since v0.10.
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

SettingsPanel.BACKUP_HINT = "A backup holds everything about this character, so keep it to yourself. "
	.. "An export for sharing holds your profile only."

-- Story settings, each shown as a segmented control. values: the cycle order
-- (NextValue, the chat commands' order); order: the order on screen when it
-- differs; short: the line under the name; help: the tooltip.
-- tracking settings switch an event category.
SettingsPanel.STORY_SETTINGS = {
	{ key = "frequency", group = "moments", label = "Moments", values = { "rare", "normal", "frequent", "off" },
		short = "How often Dawnward may offer a story moment.",
		help = "How often Dawnward may offer a story moment. Off still records events." },
	{ key = "threshold", group = "moments", label = "Significance", values = { 1, 2, 3 },
		short = "Which recorded events may become a moment.",
		help = "1: any recorded event may become a moment. 3: only major ones." },
	{ key = "places", group = "moments", label = "Places", values = { "on", "fewer", "off" },
		short = "Moments about beginnings, settlements and returns.",
		help = "Moments about places: beginnings, settlements, returns. Fewer: notable places only. "
			.. "Off: places are still recorded, never asked about." },
	{ key = "pace", group = "moments", label = "Story pace", values = { "standard", "brisk", "slow" },
		order = { "brisk", "standard", "slow" },
		short = "How much play makes one narrative day.",
		help = "How much play makes a narrative day: Brisk 1 hour, Standard 2 hours, Slow 4 hours. Returns to a "
			.. "place and story cooldowns count only time you play, never time offline." },
	{ key = "card", group = "moments", label = "Card", values = { true, false },
		short = "A small card when a moment waits (never in combat).",
		help = "Show a small card when a moment is waiting (never in combat). Off: one chat line only." },
	{ key = "flavor", group = "moments", label = "Class flavour", values = { true, false },
		short = "One optional extra answer flavoured by your class.",
		help = "Offer one optional extra answer flavoured by your class. Never changes the others." },
	{ key = "approval", group = "answers", label = "Changes", values = { "ask", "auto" },
		short = "Personality changes wait for you, or apply at once.",
		help = "Ask: personality changes wait for your approval. Auto: applied at once, still reversible." },
	{ key = "drafts", group = "answers", label = "Drafts", values = { true, false },
		short = "A journal draft for each answer.",
		help = "Write a journal draft for each answer (only for you, never part of your profile)." },
	{ tracking = "quest", group = "answers", label = "Quests", values = { true, false },
		short = "Record completed quests as story events.",
		help = "Record completed quests as story events." },
}
-- The Total RP 3 style moved to Settings > Total RP 3 > Biography (v0.10),
-- beside the template it styles.

-- The Story page's two panels.
SettingsPanel.STORY_GROUPS = {
	{ id = "moments", title = "Story moments" },
	{ id = "answers", title = "Your answers and records" },
}

-- The minimap button's two states (General > Interface).
SettingsPanel.MINIMAP_OPTIONS = { { id = "shown", label = "Shown" }, { id = "hidden", label = "Hidden" } }

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
	{ id = "help", label = "Help" },
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

	-- General: interface ---------------------------------------------------------------
	local interfaceY = -(appearanceH + LAY.gap)
	local interface = section(panel.pages.general, W, "Interface", interfaceY,
		PAD + TITLE_H + 2 * LAY.row + PAD - 6)
	panel.interface = interface
	local rows = {}
	local function generalRow(i, name, description, help)
		rows[i] = settingRow(interface.inner, -(i - 1) * LAY.row, innerW, name, description, help, LAY.button, i == 1)
		return rows[i]
	end
	generalRow(1, "Minimap button", "Show or hide the Dawnward button on the minimap.",
		"Show or hide the Dawnward button on the minimap. Drag the button to move it.")
	-- Both states visible, the one in use raised (was a "click to cycle" button).
	panel.minimap = Widgets.Segmented(rows[1], SettingsPanel.MINIMAP_OPTIONS, LAY.button, Style.CONTROL.compact,
		function(id) run(id == "hidden" and "minimap hide" or "minimap show") end)
	panel.minimap.buttons[1]:SetPoint("TOPLEFT", rows[1].controlX, -math.floor((LAY.row - Style.CONTROL.compact) / 2))
	for _, b in ipairs(panel.minimap.buttons) do
		Widgets.Tooltip(b, "Minimap button: " .. b:GetText():lower(), "Show or hide the Dawnward button on the "
			.. "minimap. Drag the button to move it.")
	end
	generalRow(2, "Window size", "Drag the gold grip in the bottom-right corner to resize.",
		"Drag the gold grip in the bottom-right corner to resize the window. Reset returns it to its design size.")
	panel.resetSize = rowButton(rows[2], "Reset window size", LAY.button)
	panel.resetSize:SetScript("OnClick", function()
		MainWindow.ResetSize()
		MainWindow.SetStatus("The window is back to its design size (smaller if your screen needs it).")
	end)
	Widgets.Tooltip(panel.resetSize, "Window size", "Drag the gold grip in the bottom-right corner to resize "
		.. "the window. This returns it to its design size.")
	panel.generalRows = rows

	-- Story: two panels (moments, then answers and records) ----------------------------
	panel.storyRows = {}
	panel.storyPanels = {}
	local storyY = 0
	for _, group in ipairs(SettingsPanel.STORY_GROUPS) do
		local settings = {}
		for _, setting in ipairs(SettingsPanel.STORY_SETTINGS) do
			if setting.group == group.id then settings[#settings + 1] = setting end
		end
		local h = PAD + TITLE_H + #settings * LAY.row + PAD - 6
		local p = section(panel.pages.story, W, group.title, storyY, h)
		panel.storyPanels[#panel.storyPanels + 1] = p
		for i, setting in ipairs(settings) do
			local row = settingRow(p.inner, -(i - 1) * LAY.row, innerW, setting.label, setting.short,
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
			panel.storyRows[#panel.storyRows + 1] = row
		end
		storyY = storyY - h - LAY.gap
	end
	panel.story = panel.storyPanels[1]

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
	Widgets.Tooltip(panel.exportBackup, "Export backup", "Everything about this character, as text to copy and "
		.. "keep. Keep it to yourself.")
	panel.exportShare = Widgets.Button(backup.inner, "Export for sharing", 170, Style.CONTROL.compact)
	panel.exportShare:SetPoint("LEFT", panel.exportBackup, "RIGHT", 8, 0)
	panel.exportShare:SetScript("OnClick", function() run("export share") end)
	Widgets.Tooltip(panel.exportShare, "Export for sharing", "Your profile only, as text to give to someone.")
	panel.import = Widgets.Button(backup.inner, "Import backup", 150, Style.CONTROL.compact)
	panel.import:SetPoint("LEFT", panel.exportShare, "RIGHT", 8, 0)
	panel.import:SetScript("OnClick", function() run("import") end)
	Widgets.Tooltip(panel.import, "Import backup", "Paste a backup you exported earlier. You see what it contains "
		.. "before anything is replaced.")

	local storyPanel = section(panel.pages.data, W, "Your story", -(dataH + LAY.gap), dataH, "")
	panel.storyPanel = storyPanel
	panel.storyState = storyPanel.description
	panel.importStory = Widgets.Button(storyPanel.inner, "Import a story…", 170, Style.CONTROL.compact)
	panel.importStory:SetPoint("TOPLEFT", 0, by)
	panel.importStory:SetScript("OnClick", function() ns.ImportWizard.Open({ from = "settings" }) end)
	Widgets.Tooltip(panel.importStory, "Import a story", "Paste a backstory you already wrote, or read your Total RP 3 "
		.. "About text. It is kept exactly as written; you approve each piece before it becomes part of your "
		.. "character.")

	-- Total RP 3 ------------------------------------------------------------------------
	-- Built by UI/TRP3Page.lua; it reuses the /dawnward trp3 functions.
	panel.trp3Page = ns.TRP3Page.Build(panel.pages.trp3, W, H)
	-- The detected status lines (also shown when Total RP 3 is absent).
	panel.trp3 = panel.trp3Page.absentStatus

	-- Help ------------------------------------------------------------------------------
	local helpH = PAD + TITLE_H + 3 * LAY.row + PAD - 6
	local help = section(panel.pages.help, W, "Help and setup", 0, helpH)
	panel.helpPanel = help
	local helpRows = {}
	local function helpRow(i, name, description, tip)
		helpRows[i] = settingRow(help.inner, -(i - 1) * LAY.row, innerW, name, description, tip, LAY.button, i == 1)
		return helpRows[i]
	end
	helpRow(1, "Guide", "How the journal, story moments, your profile and Total RP 3 work.")
	panel.guide = rowButton(helpRows[1], "Open the guide", LAY.button)
	panel.guide:SetScript("OnClick", function() run("guide") end)
	helpRow(2, "First-time setup", "Walk through the setup steps again; your answers are kept.",
		"Walk through the setup steps again: name, story, appearance and Total RP 3. Nothing is saved until "
			.. "you choose Finish.")
	panel.setup = rowButton(helpRows[2], "Run setup", LAY.button)
	panel.setup:SetScript("OnClick", function() run("setup") end)
	Widgets.Tooltip(panel.setup, "First-time setup", "Walk through the setup steps again: name, story, "
		.. "appearance and Total RP 3. Nothing is saved until you choose Finish.")
	helpRow(3, "Chat commands", "Everything in this window can also be typed after /dawnward.",
		"Lists the chat commands in your chat window. /dawnward help all shows every one.")
	panel.commands = rowButton(helpRows[3], "List the commands", LAY.button)
	panel.commands:SetScript("OnClick", function() run("help") end)
	panel.helpRows = helpRows
	panel.version = Widgets.Label(panel.pages.help, "meta", false, "muted")
	panel.version:SetPoint("TOPLEFT", PAD, -(helpH + 10))
	panel.version:SetWidth(innerW)

	-- Testing: simulation mode. Only in development builds, or while it is on
	-- (so it can always be turned off again).
	local simTop = helpH + 10 + LINE + LAY.gap
	local sim = section(panel.pages.help, W, "Testing", -simTop, dataH, "")
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
	panel.setupPreview = Widgets.Button(sim.inner, "Preview setup", 150, Style.CONTROL.compact, "ghost")
	panel.setupPreview:SetPoint("LEFT", panel.simReset, "RIGHT", 8, 0)
	panel.setupPreview:SetScript("OnClick", function() run("dev setup") end)
	Widgets.Tooltip(panel.setupPreview, "Preview setup", "Opens the setup as a preview: nothing is saved unless you "
		.. "choose Save choices. Development builds only.")

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
		local dev = ns.SetupCommands and ns.SetupCommands.DevEnabled(view.ctx) or false
		self.simPanel:SetShown(dev or simulation)
		self.setupPreview:SetShown(dev)
		self.simState:SetText(simulation
			and "Simulation mode is ON: changes go to separate test data. Your real journal is untouched."
			or "Simulation mode is OFF: you are using your real journal. Turn it on to try things safely.")
		self.simToggle:SetText(simulation and "Turn off" or "Turn on")
		self.version:SetText("Dawnward Chronicles " .. tostring(view.ctx.version or "")
			.. " · Total RP 3 is optional; see Settings > Total RP 3.")
		local lines = ns.StoryImport.StatusLines(view.char)
		self.storyState:SetText(table.concat(lines, " "))

		local prefs = view.char and view.char.story.prefs or ns.StorySchema.NewPrefs()
		for _, row in ipairs(self.storyRows) do
			row.control:Select(currentValue(row.setting, prefs))
			Widgets.Tooltip(row.hover, row.setting.label, SettingsPanel.ButtonHelp(row.setting, prefs))
		end

		self.minimap:Select(Actions.MinimapSettings(view.ctx).hidden and "hidden" or "shown")

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
-- ("general", "story", "data", "trp3" or "help"). Returns true when it is shown.
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
