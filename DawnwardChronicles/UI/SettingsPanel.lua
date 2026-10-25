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

	-- Total RP 3
	heading("Total RP 3 (read-only)", -252)
	panel.trp3 = note(-272)

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

		local status = view.ctx.trp3Status and view.ctx.trp3Status()
		self.trp3:SetText(table.concat(Commands.Trp3Lines(status), "\n"))
	end

	SettingsPanel.panel = panel
	return panel
end

MainWindow.createSettings = create
