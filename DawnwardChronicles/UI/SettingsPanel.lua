-- The settings panel behind the gear button, in four pages (General, Story,
-- Data, Total RP 3) rather than a fourth section: theme gallery, minimap,
-- guide and setup; story moment settings; backup, import and simulation
-- mode; the Total RP 3 sync page (UI/TRP3Page.lua).
-- Actions reuse the slash command code, so behaviour is identical.
local _, ns = ...
local Widgets, MainWindow, Themes, Actions, Commands =
	ns.Widgets, ns.MainWindow, ns.Themes, ns.Actions, ns.Commands

local SettingsPanel = {}
ns.SettingsPanel = SettingsPanel

local INSET = 10

SettingsPanel.BACKUP_HINT = "A backup includes private entries but not secrets "
	.. "(to include them: /dawnward export backup secrets). Sharing exports contain public facts only."

-- Story settings shown as cycle buttons. values are the cycle order; for
-- booleans true/false. tracking settings switch an event category.
SettingsPanel.STORY_SETTINGS = {
	{ key = "frequency", label = "Moments", values = { "rare", "normal", "frequent", "off" },
		help = "How often Dawnward may offer a story moment. Off still records events." },
	{ key = "threshold", label = "Significance", values = { 1, 2, 3 },
		help = "1: any recorded event may become a moment. 3: only major ones." },
	{ key = "approval", label = "Changes", values = { "ask", "auto" },
		help = "Ask: personality changes wait for your approval. Auto: applied at once, still reversible." },
	{ key = "drafts", label = "Drafts", values = { true, false },
		help = "Write a private journal draft for each answer." },
	{ key = "card", label = "Card", values = { true, false },
		help = "Show a small card when a moment is waiting (never in combat). Off: one chat line only." },
	{ key = "flavor", label = "Class flavour", values = { true, false },
		help = "Offer one optional extra answer flavoured by your class. Never changes the others." },
	{ key = "trp3Style", label = "TRP3 style", values = { "neutral", "silverhand", "arcane" },
		help = "How Dawnward's own section looks in Total RP 3 (only if you turned biography sync on)." },
	{ key = "places", label = "Places", values = { "on", "fewer", "off" },
		help = "Moments about places: beginnings, settlements, returns. Fewer: notable places only. "
			.. "Off: places are still recorded, never asked about." },
	{ key = "pace", label = "Story pace", values = { "standard", "brisk", "slow" },
		help = "How much play makes a narrative day: Brisk 1 hour, Standard 2 hours, Slow 4 hours. Returns to a "
			.. "place and story cooldowns count only time you play, never time offline." },
	{ tracking = "quest", label = "Quests", values = { true, false },
		help = "Record completed quests as story events." },
}

local function currentValue(setting, prefs)
	if setting.tracking then
		return prefs.tracking[setting.tracking]
	end
	return prefs[setting.key]
end

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

--- The button shows the setting, its current value, and a "›" saying a
-- click moves on to the next option. Pure.
function SettingsPanel.ButtonText(setting, prefs)
	return setting.label .. ": " .. SettingsPanel.ValueText(currentValue(setting, prefs)) .. "  ›"
end

--- The tooltip: what it does, then every option with the current one
-- marked, and how to change it. Pure.
function SettingsPanel.ButtonHelp(setting, prefs)
	local value = currentValue(setting, prefs)
	local options = {}
	for _, v in ipairs(setting.values) do
		local text = SettingsPanel.ValueText(v)
		options[#options + 1] = v == value and ("[" .. text .. "]") or text
	end
	return setting.help .. "\n\nOptions: " .. table.concat(options, " › ") .. "\nClick to switch to the next option."
end

SettingsPanel.PAGES = {
	{ id = "general", label = "General" },
	{ id = "story", label = "Story" },
	{ id = "data", label = "Data" },
	{ id = "trp3", label = "Total RP 3" },
}

local WIDTH = 600 - 2 * INSET

local function create(parent)
	local panel = { frame = CreateFrame("Frame", nil, parent), labels = {}, pages = {}, page = "general" }
	local f = panel.frame
	panel.background = ns.Style.Fill(f, "panel", "BACKGROUND")
	panel.background:SetAllPoints(f)

	local function run(command)
		Commands.Execute(ns.ctx, command)
		MainWindow.Refresh()
	end

	-- Secondary navigation: one page at a time.
	panel.nav = Widgets.Segmented(f, SettingsPanel.PAGES, 420, 22, function(id)
		panel.page = id
		MainWindow.Refresh()
	end)
	panel.nav.buttons[1]:SetPoint("TOPLEFT", INSET, -8)
	for _, page in ipairs(SettingsPanel.PAGES) do
		local p = CreateFrame("Frame", nil, f)
		p:SetPoint("TOPLEFT", 0, -38)
		p:SetPoint("BOTTOMRIGHT", 0, 40)
		panel.pages[page.id] = p
	end

	local function heading(page, text, y)
		local fs = Widgets.Label(panel.pages[page], "GameFontNormal", false, "heading")
		fs:SetPoint("TOPLEFT", INSET, y)
		fs:SetText(text)
		panel.labels[#panel.labels + 1] = fs
		return fs
	end

	local function note(page, y, width)
		local fs = Widgets.Label(panel.pages[page], "GameFontHighlightSmall", true, "muted")
		fs:SetPoint("TOPLEFT", INSET, y)
		fs:SetWidth(width or WIDTH)
		return fs
	end

	-- General: appearance --------------------------------------------------------
	heading("general", "Appearance", -4)
	note("general", -22):SetText("Changes only how this character's journal looks. Themes never depend on class, "
		.. "race or faction.")
	panel.themeButtons = {}
	local tileWidth = math.floor((WIDTH - 16) / 3)
	for i, theme in ipairs(Themes.LIST) do
		local button = Widgets.Button(panel.pages.general, theme.name, tileWidth, 36, "choice")
		local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
		button:SetPoint("TOPLEFT", INSET + col * (tileWidth + 8), -44 - row * 42)
		-- Three swatches: background, surface and accent of that theme.
		button.swatches = {}
		for k, role in ipairs({ "background", "surface", "accent" }) do
			local sw = Widgets.Solid(button, "ARTWORK")
			sw:SetSize(14, 14)
			sw:SetPoint("RIGHT", -10 - (3 - k) * 16, 0)
			Widgets.SetColor(sw, theme[role])
			button.swatches[k] = sw
		end
		button.themeId = theme.id
		button:SetScript("OnClick", function()
			local _, message = Actions.SetTheme(ns.ctx, theme.id)
			MainWindow.SetStatus(message)
			MainWindow.Refresh()
		end)
		Widgets.Tooltip(button, theme.name, theme.description)
		panel.themeButtons[#panel.themeButtons + 1] = button
	end
	panel.themeDescription = note("general", -134)

	-- General: interface ------------------------------------------------------------
	heading("general", "Interface and help", -170)
	panel.minimap = Widgets.Button(panel.pages.general, "Minimap button: shown", 190, 22)
	panel.minimap:SetPoint("TOPLEFT", INSET, -192)
	panel.minimap:SetScript("OnClick", function() run("minimap") end)
	Widgets.Tooltip(panel.minimap, "Minimap button", "Show or hide the Dawnward button on the minimap. "
		.. "Drag the button to move it.")
	panel.guide = Widgets.Button(panel.pages.general, "Open the guide", 150, 22)
	panel.guide:SetPoint("LEFT", panel.minimap, "RIGHT", 8, 0)
	panel.guide:SetScript("OnClick", function() run("guide") end)
	panel.setup = Widgets.Button(panel.pages.general, "Run setup", 150, 22)
	panel.setup:SetPoint("LEFT", panel.guide, "RIGHT", 8, 0)
	panel.setup:SetScript("OnClick", function() run("setup") end)
	Widgets.Tooltip(panel.setup, "First-time setup", "Walk through the setup steps again: name, story moments, "
		.. "privacy and appearance. Nothing is saved until you choose Finish.")
	panel.resetSize = Widgets.Button(panel.pages.general, "Reset window size", 160, 22)
	panel.resetSize:SetPoint("TOPLEFT", panel.minimap, "BOTTOMLEFT", 0, -8)
	panel.resetSize:SetScript("OnClick", function()
		MainWindow.ResetSize()
		MainWindow.SetStatus("The window is back to its design size (smaller if your screen needs it).")
	end)
	Widgets.Tooltip(panel.resetSize, "Window size", "Drag the gold grip in the bottom-right corner to resize "
		.. "the window. This returns it to its design size.")

	-- Story ---------------------------------------------------------------------------
	heading("story", "Story moments", -4)
	note("story", -22):SetText("Each button shows a setting and its current value for this character. Click it to "
		.. "switch to the next option; hover to see every option.")
	panel.storyButtons = {}
	local storyWidth = math.floor((WIDTH - 16) / 3)
	for i, setting in ipairs(SettingsPanel.STORY_SETTINGS) do
		local button = Widgets.Button(panel.pages.story, setting.label, storyWidth, 22, "choice")
		local col, rowIndex = (i - 1) % 3, math.floor((i - 1) / 3)
		button:SetPoint("TOPLEFT", INSET + col * (storyWidth + 8), -60 - rowIndex * 28)
		button.setting = setting
		button:SetScript("OnClick", function(self)
			local char = Actions.Character(ns.ctx)
			local prefs = char and char.story.prefs or ns.StorySchema.NewPrefs()
			local nextValue = SettingsPanel.NextValue(self.setting, prefs)
			local _, message
			if self.setting.tracking then
				_, message = Actions.SetTracking(ns.ctx, self.setting.tracking, nextValue)
			else
				_, message = Actions.SetStoryPref(ns.ctx, self.setting.key, nextValue)
			end
			MainWindow.SetStatus(message)
			MainWindow.Refresh()
		end)
		Widgets.Tooltip(button, setting.label, setting.help)
		panel.storyButtons[i] = button
	end

	-- Data ------------------------------------------------------------------------------
	heading("data", "Backup and sharing", -4)
	panel.exportBackup = Widgets.Button(panel.pages.data, "Export backup", 140, 22)
	panel.exportBackup:SetPoint("TOPLEFT", INSET, -26)
	panel.exportBackup:SetScript("OnClick", function() run("export backup") end)
	panel.exportShare = Widgets.Button(panel.pages.data, "Export for sharing", 160, 22)
	panel.exportShare:SetPoint("LEFT", panel.exportBackup, "RIGHT", 8, 0)
	panel.exportShare:SetScript("OnClick", function() run("export share") end)
	panel.import = Widgets.Button(panel.pages.data, "Import backup", 140, 22)
	panel.import:SetPoint("LEFT", panel.exportShare, "RIGHT", 8, 0)
	panel.import:SetScript("OnClick", function() run("import") end)
	panel.backupHint = note("data", -56)
	panel.backupHint:SetText(SettingsPanel.BACKUP_HINT)

	heading("data", "Your story", -200)
	panel.importStory = Widgets.Button(panel.pages.data, "Import a story...", 160, 22)
	panel.importStory:SetPoint("TOPLEFT", INSET, -222)
	panel.importStory:SetScript("OnClick", function() ns.ImportWizard.Open({ from = "settings" }) end)
	Widgets.Tooltip(panel.importStory, "Import a story", "Paste a backstory you already wrote, or read your Total RP 3 "
		.. "About text. It is kept exactly as written; you approve each piece before it becomes part of your "
		.. "character.")
	panel.storyState = note("data", -252)

	heading("data", "Simulation mode", -110)
	panel.simState = note("data", -128)
	panel.simToggle = Widgets.Button(panel.pages.data, "Turn on", 120, 22)
	panel.simToggle:SetPoint("TOPLEFT", INSET, -150)
	panel.simToggle:SetScript("OnClick", function()
		run(ns.ctx.store:IsSimulation() and "sim off" or "sim on")
	end)
	panel.simReset = Widgets.Button(panel.pages.data, "Reset test data", 140, 22, "danger")
	panel.simReset:SetPoint("LEFT", panel.simToggle, "RIGHT", 8, 0)
	panel.simReset:SetScript("OnClick", function()
		Widgets.Confirm("Delete ALL simulation test data for every character?\n\nYour real data is not affected.",
			"Reset", function() run("sim reset confirm") end)
	end)

	-- Total RP 3 ------------------------------------------------------------------------
	-- Built by UI/TRP3Page.lua; it reuses the /dawnward trp3 functions.
	panel.trp3Page = ns.TRP3Page.Build(panel.pages.trp3, MainWindow.ContentWidth(), MainWindow.ContentHeight() - 78)
	-- The detected status lines (also shown when Total RP 3 is absent).
	panel.trp3 = panel.trp3Page.absentStatus

	panel.done = Widgets.Button(f, "Done", 90, 22, "primary")
	panel.done:SetPoint("BOTTOMRIGHT", -INSET, 10)
	panel.done:SetScript("OnClick", MainWindow.ToggleSettings)

	-- Every part paints itself (UI/Style.lua).
	function panel.ApplyTheme() end

	function panel:Refresh(view)
		self.nav:Select(self.page)
		for id, p in pairs(self.pages) do
			p:SetShown(id == self.page)
		end
		local current = Actions.ThemeOf(view.char)
		for _, button in ipairs(self.themeButtons) do
			button:SetSelected(button.themeId == current.id)
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
		for _, button in ipairs(self.storyButtons) do
			button:SetText(SettingsPanel.ButtonText(button.setting, prefs))
			Widgets.Tooltip(button, button.setting.label, SettingsPanel.ButtonHelp(button.setting, prefs))
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
