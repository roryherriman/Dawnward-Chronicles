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
			expect.equal(panel.done.bg.__color[1], shadow.accent[1], "primary button")
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
end
