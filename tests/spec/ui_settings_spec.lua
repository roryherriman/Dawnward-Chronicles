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
			expect.falsy(panel.themeButtons[1]:IsEnabled(), "Neutral is current")
			click(panel.themeButtons[2])
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			expect.equal(char.theme, "silverhand")
			expect.deepEqual(char.fields, fieldsBefore)
			expect.falsy(panel.themeButtons[2]:IsEnabled())
			expect.truthy(panel.themeButtons[1]:IsEnabled())
			local silver = ns.Themes.Get("silverhand")
			expect.equal(frame.background.__color[1], silver.background[1])
			expect.truthy(panel.themeDescription:GetText():find("Silver Hand"))
		end)

		t:it("starts new characters on Neutral", function()
			local _, _, _, panel = openSettings()
			expect.truthy(panel.themeDescription:GetText():find("^Neutral"))
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
			local _, _, _, panel = openSettings()
			expect.truthy(panel.trp3:GetText():find("Total RP 3"))
			expect.truthy(panel.trp3:GetText():find("not installed"))
		end)
	end)
end
