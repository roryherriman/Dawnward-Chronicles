-- The small settings panel behind the gear button. Everything technical lives
-- here rather than in a fourth section: theme, backup/import/export,
-- simulation mode and the read-only Total RP 3 status.
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

function SettingsPanel.ButtonText(setting, prefs)
	local value = currentValue(setting, prefs)
	if type(value) == "boolean" then
		value = value and "on" or "off"
	end
	return setting.label .. ": " .. tostring(value)
end

local function create(parent)
	local panel = { frame = CreateFrame("Frame", nil, parent), labels = {} }
	local f = panel.frame

	local function heading(text, y)
		local fs = Widgets.Label(f, "GameFontNormal")
		fs:SetPoint("TOPLEFT", INSET, y)
		fs:SetText(text)
		panel.labels[#panel.labels + 1] = fs
		return fs
	end

	local function note(y, width)
		local fs = Widgets.Label(f, "GameFontHighlightSmall", true)
		fs:SetPoint("TOPLEFT", INSET, y)
		fs:SetWidth(width or 560)
		return fs
	end

	local function run(command)
		Commands.Execute(ns.ctx, command)
		MainWindow.Refresh()
	end

	-- Appearance
	heading("Appearance (changes only how this character's journal looks)", -10)
	panel.themeButtons = {}
	local previous
	for _, theme in ipairs(Themes.LIST) do
		local button = Widgets.Button(f, theme.name, 150, 22)
		if previous then
			button:SetPoint("LEFT", previous, "RIGHT", 6, 0)
		else
			button:SetPoint("TOPLEFT", INSET, -30)
		end
		button.themeId = theme.id
		button:SetScript("OnClick", function()
			local _, message = Actions.SetTheme(ns.ctx, theme.id)
			MainWindow.SetStatus(message)
			MainWindow.Refresh()
		end)
		panel.themeButtons[#panel.themeButtons + 1] = button
		previous = button
	end
	panel.themeDescription = note(-58)

	-- Backup and sharing
	heading("Backup and sharing", -90)
	panel.exportBackup = Widgets.Button(f, "Export backup", 130, 22)
	panel.exportBackup:SetPoint("TOPLEFT", INSET, -110)
	panel.exportBackup:SetScript("OnClick", function() run("export backup") end)
	panel.exportShare = Widgets.Button(f, "Export for sharing", 150, 22)
	panel.exportShare:SetPoint("LEFT", panel.exportBackup, "RIGHT", 6, 0)
	panel.exportShare:SetScript("OnClick", function() run("export share") end)
	panel.import = Widgets.Button(f, "Import backup", 130, 22)
	panel.import:SetPoint("LEFT", panel.exportShare, "RIGHT", 6, 0)
	panel.import:SetScript("OnClick", function() run("import") end)
	panel.backupHint = note(-138)
	panel.backupHint:SetText(SettingsPanel.BACKUP_HINT)

	-- Simulation
	heading("Simulation mode", -176)
	panel.simState = note(-196)
	panel.simToggle = Widgets.Button(f, "Turn on", 110, 22)
	panel.simToggle:SetPoint("TOPLEFT", INSET, -214)
	panel.simToggle:SetScript("OnClick", function()
		run(ns.ctx.store:IsSimulation() and "sim off" or "sim on")
	end)
	panel.simReset = Widgets.Button(f, "Reset test data", 130, 22)
	panel.simReset:SetPoint("LEFT", panel.simToggle, "RIGHT", 6, 0)
	panel.simReset:SetScript("OnClick", function()
		Widgets.Confirm("Delete ALL simulation test data for every character?\n\nYour real data is not affected.",
			"Reset", function() run("sim reset confirm") end)
	end)

	-- Minimap button (#45), beside the simulation buttons.
	panel.minimap = Widgets.Button(f, "Minimap button: shown", 180, 22)
	panel.minimap:SetPoint("TOPLEFT", INSET + 380, -214)
	panel.minimap:SetScript("OnClick", function() run("minimap") end)
	Widgets.Tooltip(panel.minimap, "Minimap button", "Show or hide the Dawnward button on the minimap. "
		.. "Drag the button to move it.")

	-- Story prompts (v0.4). Each button cycles one setting.
	heading("Story moments", -252)
	panel.storyButtons = {}
	local SETTINGS = SettingsPanel.STORY_SETTINGS
	for i, setting in ipairs(SETTINGS) do
		local button = Widgets.Button(f, setting.label, 136, 22)
		local col, rowIndex = (i - 1) % 4, math.floor((i - 1) / 4)
		button:SetPoint("TOPLEFT", INSET + col * 140, -272 - rowIndex * 26)
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

	-- Total RP 3
	heading("Total RP 3 (status; sync is experimental: /dawnward trp3 help)", -358)
	panel.trp3 = note(-378)

	panel.done = Widgets.Button(f, "Done", 90, 22)
	panel.done:SetPoint("BOTTOMRIGHT", -INSET, 10)
	panel.done:SetScript("OnClick", MainWindow.ToggleSettings)

	function panel:ApplyTheme(theme)
		for _, fs in ipairs(self.labels) do
			Widgets.TextColor(fs, theme.accent)
		end
		for _, fs in ipairs({ self.themeDescription, self.backupHint, self.simState, self.trp3 }) do
			Widgets.TextColor(fs, theme.text)
		end
	end

	function panel:Refresh(view)
		local current = Actions.ThemeOf(view.char)
		for _, button in ipairs(self.themeButtons) do
			button:SetEnabled(button.themeId ~= current.id)
		end
		self.themeDescription:SetText(current.name .. " (current): " .. current.description)

		local simulation = view.ctx.store:IsSimulation()
		self.simState:SetText(simulation
			and "ON: changes go to separate test data. Your real journal is untouched."
			or "OFF: you are using your real journal. Turn on to experiment safely.")
		self.simToggle:SetText(simulation and "Turn off" or "Turn on")

		local prefs = view.char and view.char.story.prefs or ns.StorySchema.NewPrefs()
		for _, button in ipairs(self.storyButtons) do
			button:SetText(SettingsPanel.ButtonText(button.setting, prefs))
		end

		self.minimap:SetText(Actions.MinimapSettings(view.ctx).hidden and "Minimap button: hidden"
			or "Minimap button: shown")

		local status = view.ctx.trp3Status and view.ctx.trp3Status()
		self.trp3:SetText(table.concat(Commands.Trp3Lines(status), "\n"))
	end

	SettingsPanel.panel = panel
	return panel
end

MainWindow.createSettings = create
