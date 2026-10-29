-- L2: the v0.7 window shell (character rail), the Character Showcase and
-- the bundled fonts, against the WoW mock. Visual fidelity to the approved
-- mockups needs the game (docs/TESTING.md part R); these prove wiring.
local Boot = require("support.boot")

local CHAR = "Testchar-TestRealm"

local function click(button)
	button:GetScript("OnClick")(button)
end

return function(t, expect)
	local function open(opts)
		local mock, env, ns = Boot.Start(opts)
		mock.Slash("")
		return mock, env, ns, ns.MainWindow.GetFrame()
	end

	t:describe("character rail", function()
		t:it("shows the player's own name, title, race, class, pronouns and level", function()
			local mock, _, _, frame = open()
			expect.equal(frame.charName:GetText(), "Testchar", "the game's name until the profile has one")
			mock.Slash("set name Aelin Brightwater")
			mock.Slash("set title Keeper of the Road")
			mock.Slash("set pronouns she/her")
			expect.equal(frame.charName:GetText(), "Aelin Brightwater")
			expect.equal(frame.charTitle:GetText(), "Keeper of the Road")
			expect.equal(frame.charLine:GetText(), "Orc · Mage · she/her")
			expect.equal(frame.level:GetText(), "20")
			expect.equal(frame.portrait.portrait.__portrait, "player", "the game's own portrait")
		end)

		t:it("navigates with the rail buttons and badges waiting moments on Story", function()
			local mock, env, ns, frame = open()
			mock.Slash("set name Aelin")
			for i, id in ipairs({ "journal", "character", "story", "chronicle" }) do
				click(frame.tabs[i])
				expect.equal(ns.MainWindow.CurrentSection(), id)
				expect.truthy(frame.tabs[i].underline:IsShown(), "selected marker on " .. id)
				expect.truthy(frame.eyebrow:GetText() == ns.MainWindow.Sections()[i].label:upper())
			end
			expect.equal(frame.tabs[3].badge:GetText(), "")
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			local record = ns.GameEvents.Record(char, "quest", { questId = 7, title = "Q", zone = "Z", level = 5 }, 1)
			assert(ns.Reactions.Consider(char, record, 1, 0))
			ns.MainWindow.Refresh()
			expect.equal(frame.tabs[3].badge:GetText(), "1")
			expect.truthy(frame.tabs[3].badgeBg:IsShown())
		end)

		t:it("titles the journal with the character and flags simulation on every section", function()
			local mock, _, ns, frame = open()
			mock.Slash("set name Aelin")
			expect.equal(frame.title:GetText(), "Aelin's Journal")
			ns.MainWindow.Select("character")
			expect.equal(frame.title:GetText(), "Profile")
			mock.Slash("sim on")
			expect.truthy(frame.title:GetText():find("simulation", 1, true))
		end)

		t:it("states Total RP 3 availability without touching it", function()
			local ns = select(3, open())
			expect.equal(ns.MainWindow.TRP3Line({ installed = false }), "Total RP 3 · not installed (optional)")
			expect.equal(ns.MainWindow.TRP3Line({ installed = true, loaded = false }), "Total RP 3 · installed, not loaded")
			expect.equal(ns.MainWindow.TRP3Line({ installed = true, loaded = true, profile = { name = "Aelin RP" } }),
				'Total RP 3 · profile "Aelin RP"')
			expect.equal(ns.MainWindow.GetFrame().trp3:GetText(), "Total RP 3 · not installed (optional)")
		end)

		t:it("keeps Guide and Settings in the rail", function()
			local _, _, ns, frame = open()
			click(frame.gear)
			expect.equal(ns.MainWindow.CurrentSection(), "settings")
			expect.equal(frame.title:GetText(), "Settings")
			click(frame.gear)
			click(frame.help)
			expect.truthy(ns.MainWindow.guide:IsOpen())
		end)
	end)

	t:describe("Character Showcase", function()
		t:it("shows the live model beside the profile, inside the content area", function()
			local _, _, ns = open()
			ns.MainWindow.Select("character")
			local section = ns.CharacterView.section
			local showcase = section.showcase
			showcase:Hide()
			showcase:Show()
			expect.truthy(showcase.modelShown, "the model is shown")
			expect.equal(showcase.model.__unit, "player")
			expect.falsy(showcase.fallback:IsShown())
			local W = ns.MainWindow.ContentWidth()
			expect.truthy(ns.CharacterView.ListWidth(W) + ns.CharacterView.SHOWCASE_WIDTH + 22 <= W,
				"list and showcase fit side by side")
		end)

		t:it("renders nothing while hidden, and turns with the buttons", function()
			local _, _, ns = open()
			ns.MainWindow.Select("character")
			local showcase = ns.CharacterView.section.showcase
			showcase:Hide()
			showcase:Show()
			expect.truthy(showcase.__events.UNIT_MODEL_CHANGED, "listens only while shown")
			click(showcase.right)
			expect.truthy(math.abs(showcase.model:GetRotation() - ns.Showcase.ROTATE_STEP) < 1e-9)
			click(showcase.left)
			click(showcase.left)
			expect.truthy(showcase.model:GetRotation() > math.pi, "wraps around")
			showcase:Hide()
			expect.equal(showcase.model.__unit, nil, "model cleared when hidden")
			expect.falsy(showcase.__events.UNIT_MODEL_CHANGED)
		end)

		t:it("falls back to the portrait when the model cannot be shown", function()
			local mock, _, ns = open()
			ns.MainWindow.Select("character")
			local showcase = ns.CharacterView.section.showcase
			mock.modelFails = true
			showcase:Hide()
			showcase:Show()
			expect.falsy(showcase.modelShown)
			expect.truthy(showcase.fallback:IsShown())
			expect.equal(showcase.fallback.portrait.__portrait, "player")
		end)

		t:it("steps aside while a field is being edited", function()
			local mock, _, ns = open()
			mock.Slash("set name Aelin")
			ns.MainWindow.Select("character")
			local section = ns.CharacterView.section
			for i, spec in ipairs(section.specs) do
				if spec.kind == "field" and spec.field.key == "name" then click(section.rows[i].edit) end
			end
			expect.falsy(section.showcase:IsShown())
			click(section.editor.cancel)
			expect.truthy(section.showcase:IsShown())
		end)
	end)

	t:describe("bundled fonts", function()
		t:it("uses Dawnward's fonts on Latin clients", function()
			local _, _, ns = Boot.Load()
			expect.equal(ns.Style.InitFonts(), #ns.Style.FONTS)
			expect.equal(ns.Style.Font("GameFontHighlight"), "DawnwardFontBody")
			expect.equal(ns.Style.Font("GameFontNormalLarge"), "DawnwardFontTitle")
			expect.truthy(ns.Style.FontObject("GameFontHighlight").__font.file:find("AlegreyaSans-Regular.ttf", 1, true))
			expect.equal(ns.Style.Font("SomeOtherFont"), "SomeOtherFont")
		end)

		t:it("keeps the game's fonts on clients the bundled fonts do not cover", function()
			local mock, _, ns = Boot.Load()
			mock.locale = "ruRU"
			expect.equal(ns.Style.InitFonts(), 0)
			expect.equal(ns.Style.Font("GameFontHighlight"), "GameFontHighlight")
			expect.equal(ns.Style.FontObject("GameFontHighlight"), nil)
		end)

		t:it("falls back per font when a file fails to load", function()
			local mock, _, ns = Boot.Load()
			mock.fontFails = "Cinzel"
			expect.equal(ns.Style.InitFonts(), 5, "the four Cinzel fonts fall back")
			expect.equal(ns.Style.Font("GameFontNormalLarge"), "GameFontNormalLarge")
			expect.equal(ns.Style.Font("GameFontHighlight"), "DawnwardFontBody")
		end)
	end)
end
