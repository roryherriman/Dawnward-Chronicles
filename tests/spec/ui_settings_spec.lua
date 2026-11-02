-- L2: the settings panel behind the gear button.
local Boot = require("support.boot")

local CHAR = "Testchar-TestRealm"

local function click(button)
	button:GetScript("OnClick")(button)
end

local function openSettings(opts)
	local mock, env, ns = Boot.Start(opts)
	mock.Slash("")
	local frame = ns.MainWindow.GetFrame()
	click(frame.gear)
	return mock, env, ns, ns.SettingsPanel.panel, frame
end

return function(t, expect)
	t:describe("settings panel (L2)", function()
		t:it("opens from the gear in place of the sections, and closes with Done or a tab", function()
			local _, _, ns, panel, frame = openSettings()
			expect.equal(ns.MainWindow.CurrentSection(), "settings")
			expect.truthy(panel.frame:IsShown())
			for _, def in ipairs(ns.MainWindow.Sections()) do
				expect.falsy(def.instance.frame:IsShown(), def.id .. " hidden")
			end
			for _, tab in ipairs(frame.tabs) do
				expect.falsy(tab.underline:IsShown(), "no section tab looks selected")
			end
			click(panel.done)
			expect.equal(ns.MainWindow.CurrentSection(), "journal")
			click(frame.gear)
			click(frame.tabs[2])
			expect.equal(ns.MainWindow.CurrentSection(), "character")
			expect.falsy(panel.frame:IsShown())
		end)

		t:it("is not a section of its own", function()
			local _, _, ns = openSettings()
			for _, def in ipairs(ns.MainWindow.Sections()) do
				expect.falsy(def.id == "settings")
			end
			expect.equal(#ns.MainWindow.Sections(), 4)
		end)

		t:it("changes the theme for this character only, and only the theme", function()
			local mock, env, ns, panel, frame = openSettings()
			mock.Slash("set name Aelin")
			local fieldsBefore = ns.Util.DeepCopy(env.DawnwardChroniclesDB.characters[CHAR].fields)
			expect.truthy(panel.themeButtons[1].selected, "Classic Dawnward is current")
			expect.equal(#panel.themeButtons, #ns.Themes.LIST)
			click(panel.themeButtons[3])
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			expect.equal(char.theme, "shadowbound")
			expect.deepEqual(char.fields, fieldsBefore)
			expect.truthy(panel.themeButtons[3].selected)
			expect.falsy(panel.themeButtons[1].selected)
			local shadow = ns.Themes.Get("shadowbound")
			expect.equal(frame.background.__color[1], shadow.background[1])
			expect.truthy(panel.themeDescription:GetText():find("Shadowbound"))
			-- Every themed control follows: a default (secondary) button is filled with the raised colour.
			expect.equal(panel.trp3Page.approve.bg.__color[1], shadow.accent[1], "primary button")
			expect.equal(panel.done.bg.__color[1], shadow.surfaceHover[1], "Done is secondary (one gold button per view)")
			expect.equal(panel.guide.bg.__color[1], shadow.surfaceHover[1], "default button")
		end)

		t:it("starts new characters on Classic Dawnward, and keeps the v0.2 themes selectable", function()
			local _, _, ns, panel = openSettings()
			expect.truthy(panel.themeDescription:GetText():find("^Classic Dawnward"))
			local ids = {}
			for _, b in ipairs(panel.themeButtons) do ids[b.themeId] = true end
			expect.truthy(ids.neutral and ids.silverhand and ids.arcane and ids.lightbound and ids.shadowbound)
			expect.truthy(ns.Themes.IsValid("neutral"))
		end)

		t:it("shows one page at a time: General, Story, Data, Total RP 3", function()
			local _, _, _, panel = openSettings()
			expect.truthy(panel.pages.general:IsShown())
			expect.falsy(panel.pages.data:IsShown())
			click(panel.nav.buttons[3])
			expect.truthy(panel.pages.data:IsShown())
			expect.falsy(panel.pages.general:IsShown())
			expect.truthy(panel.nav.buttons[3].selected)
		end)

		t:it("exports and imports through the existing copy window", function()
			local mock, _, ns, panel = openSettings()
			mock.Slash("set name Aelin")
			click(panel.exportBackup)
			local copy = ns.CopyBox.GetFrame()
			expect.truthy(copy:IsShown())
			expect.equal(copy.editBox:GetText():sub(1, 8), "!DWC1!B!")
			click(panel.exportShare)
			expect.equal(copy.editBox:GetText():sub(1, 8), "!DWC1!S!")
			click(panel.import)
			expect.equal(copy.editBox:GetText(), "")
			expect.truthy(copy.title:GetText():find("Import"))
		end)

		t:it("toggles simulation and resets it only after confirmation", function()
			local mock, env, ns, panel = openSettings()
			click(panel.simToggle)
			expect.truthy(ns.ctx.store:IsSimulation())
			expect.equal(panel.simToggle:GetText(), "Turn off")
			mock.Slash("set name Sim")
			click(panel.simReset)
			expect.truthy(env.DawnwardChroniclesSimDB.characters[CHAR], "not reset yet")
			mock.AcceptPopup()
			expect.equal(env.DawnwardChroniclesSimDB.characters[CHAR], nil)
			click(panel.simToggle)
			expect.falsy(ns.ctx.store:IsSimulation())
		end)

		t:it("shows Total RP 3 status as read-only text", function()
			local _, _, ns, panel = openSettings()
			assert(ns.SettingsPanel.OpenPage("trp3"))
			expect.truthy(panel.trp3:GetText():find("Total RP 3"))
			expect.truthy(panel.trp3:GetText():find("not installed"))
		end)
	end)

	t:describe("settings panel v0.8 layout (L2)", function()
		-- The window scales as a whole (MainWindow: SetScale between MIN_SCALE and
		-- MAX_SCALE), so a layout that fits in UI units fits at every window size.
		local function topOf(widget)
			for _, p in ipairs(widget.__points or {}) do
				if p[1] == "TOPLEFT" then return p[#p] end
			end
		end

		t:it("the page switcher and Done share the top row without overlapping", function()
			local _, _, ns, panel = openSettings()
			local L = ns.SettingsPanel.LAYOUT
			local navWidth = #panel.nav.buttons * L.navItem
			expect.truthy(navWidth + 16 + panel.done:GetWidth() <= ns.MainWindow.ContentWidth())
			expect.equal(panel.done:GetHeight(), ns.Style.CONTROL.standard)
			expect.equal(panel.nav.buttons[1]:GetHeight(), L.navHeight)
			for _, b in ipairs(panel.nav.buttons) do
				expect.truthy(ns.Widgets.LabelFits(b:GetText(), b:GetWidth(), b:GetHeight(), "segment"), b:GetText())
			end
		end)

		t:it("every panel of General, Story, Data and Help fits inside its page", function()
			local _, _, ns, panel = openSettings()
			local all = { panel.appearance, panel.interface, panel.backupPanel, panel.storyPanel, panel.helpPanel,
				panel.simPanel }
			for _, p in ipairs(panel.storyPanels) do all[#all + 1] = p end
			for _, p in ipairs(all) do
				expect.truthy(-topOf(p) + p:GetHeight() <= panel.pageHeight, "panel inside the page")
				expect.equal(p:GetWidth(), ns.MainWindow.ContentWidth())
			end
			-- Panels on one page never overlap.
			expect.truthy(-topOf(panel.interface) >= panel.appearance:GetHeight())
			expect.truthy(-topOf(panel.storyPanel) >= panel.backupPanel:GetHeight())
			expect.truthy(-topOf(panel.storyPanels[2]) >= panel.storyPanels[1]:GetHeight())
			expect.truthy(-topOf(panel.simPanel) >= panel.helpPanel:GetHeight() + ns.SettingsPanel.LAYOUT.gap)
		end)

		t:it("v0.10: five pages by purpose; developer tools only in development builds", function()
			local mock, _, ns, panel = openSettings()
			local ids = {}
			for i, b in ipairs(panel.nav.buttons) do ids[i] = b.segmentId end
			expect.deepEqual(ids, { "general", "story", "data", "trp3", "help" })
			expect.truthy(ns.SettingsPanel.OpenPage("help"))
			expect.truthy(panel.guide:IsVisible() and panel.setup:IsVisible() and panel.commands:IsVisible())
			-- A release build hides simulation mode (unless it is on) and the setup preview.
			ns.ctx.version = "1.0.0"
			ns.MainWindow.Refresh()
			expect.falsy(panel.simPanel:IsShown())
			expect.falsy(panel.setupPreview:IsShown())
			mock.Slash("sim on")
			ns.MainWindow.Refresh()
			expect.truthy(panel.simPanel:IsShown(), "while it is on, it can be turned off")
			expect.falsy(panel.setupPreview:IsShown())
			mock.Slash("sim off")
			ns.ctx.version = "0.10.0-dev"
			ns.MainWindow.Refresh()
			expect.truthy(panel.simPanel:IsShown() and panel.setupPreview:IsShown())
			-- No developer words on the ordinary pages.
			for _, row in ipairs(panel.storyRows) do
				expect.falsy(row.setting.label:find("TRP3", 1, true), "the Total RP 3 style lives on its own page")
			end
		end)

		t:it("Story: one row per setting, every option shown and fitting, descriptions on one line", function()
			local _, _, ns, panel = openSettings()
			local S = ns.SettingsPanel
			expect.equal(#panel.storyRows, #S.STORY_SETTINGS)
			local rowsEnd = -topOf(panel.storyRows[#panel.storyRows]) + S.LAYOUT.row
			expect.truthy(rowsEnd <= panel.storyPanels[2]:GetHeight() - 36, "rows inside the second Story panel")
			for _, row in ipairs(panel.storyRows) do
				local seg = row.control
				expect.equal(#seg.buttons, #row.setting.values, row.setting.label .. ": every option")
				expect.truthy(seg.width <= S.LAYOUT.control, row.setting.label .. " fits the control column")
				for _, b in ipairs(seg.buttons) do
					expect.truthy(ns.Widgets.LabelFits(b:GetText(), b:GetWidth(), b:GetHeight(), "segment"),
						row.setting.label .. ": " .. b:GetText())
				end
				expect.truthy(ns.Style.TextWidth(row.setting.short, "meta") <= row.textWidth,
					row.setting.label .. " description fits one line")
				expect.truthy(ns.Style.TextWidth(row.setting.label, "label") <= row.textWidth)
			end
		end)

		t:it("Story: exactly one option is selected per setting, and it follows the saved value", function()
			local mock, _, ns, panel = openSettings()
			mock.Slash("set name A")
			assert(ns.Actions.SetStoryPref(ns.ctx, "pace", "slow"))
			ns.MainWindow.Refresh()
			for _, row in ipairs(panel.storyRows) do
				local selected = 0
				for _, b in ipairs(row.control.buttons) do
					if b.selected then selected = selected + 1 end
				end
				expect.equal(selected, 1, row.setting.label)
			end
			local pace
			for _, row in ipairs(panel.storyRows) do
				if row.setting.key == "pace" then pace = row end
			end
			local labels = {}
			for i, b in ipairs(pace.control.buttons) do labels[i] = b:GetText() end
			expect.deepEqual(labels, { "Brisk (1 h)", "Standard (2 h)", "Slow (4 h)" }, "shortest to longest")
			expect.equal(pace.control.selected, "slow")
		end)

		t:it("General: setting descriptions fit one line and every button label fits its button", function()
			local _, _, ns, panel = openSettings()
			for _, row in ipairs(panel.generalRows) do
				expect.truthy(ns.Style.TextWidth(row.description:GetText(), "meta") <= row.textWidth,
					row.name:GetText())
			end
			local buttons = { panel.guide, panel.setup, panel.commands, panel.resetSize, panel.exportBackup,
				panel.exportShare, panel.import, panel.importStory, panel.simToggle, panel.simReset, panel.setupPreview,
				panel.done }
			for _, b in ipairs(panel.minimap.buttons) do buttons[#buttons + 1] = b end
			for _, row in ipairs(panel.helpRows) do
				expect.truthy(ns.Style.TextWidth(row.description:GetText(), "meta") <= row.textWidth,
					row.name:GetText())
			end
			for _, b in ipairs(buttons) do
				expect.truthy(ns.Widgets.LabelFits(b:GetText(), b:GetWidth(), b:GetHeight()), b:GetText())
				expect.truthy(b:GetHeight() >= ns.Style.CONTROL.compact, b:GetText() .. " uses a design-system height")
			end
			expect.equal(#panel.minimap.buttons * panel.minimap.buttons[1]:GetWidth() <= ns.SettingsPanel.LAYOUT.button,
				true, "the minimap choice fits the control column")
			expect.truthy(ns.Widgets.LabelFits("Turn off", panel.simToggle:GetWidth(), panel.simToggle:GetHeight()))
		end)

		t:it("the theme in use is marked twice: raised tile and a gold bar", function()
			local _, _, _, panel = openSettings()
			for i, b in ipairs(panel.themeButtons) do
				expect.equal(b.mark:IsShown(), i == 1)
				expect.equal(b.selected == true, i == 1)
			end
			click(panel.themeButtons[2])
			expect.truthy(panel.themeButtons[2].mark:IsShown())
			expect.falsy(panel.themeButtons[1].mark:IsShown())
		end)
	end)
end
