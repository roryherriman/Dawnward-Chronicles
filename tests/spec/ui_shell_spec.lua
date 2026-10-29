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
		local function showcaseOf(ns)
			ns.MainWindow.Select("character")
			local section = ns.CharacterView.section
			click(section.showcaseButton)
			return section.showcase, section
		end

		t:it("opens from the Character header and shows the live model, inside the content area", function()
			local _, _, ns = open()
			ns.MainWindow.Select("character")
			local section = ns.CharacterView.section
			expect.falsy(section.showcase:IsShown(), "the profile does not render the model")
			expect.equal(section.showcase.model.__unit, nil)
			local showcase = showcaseOf(ns)
			expect.equal(section.mode, "showcase")
			expect.truthy(showcase:IsShown())
			expect.truthy(showcase.modelShown, "the model is shown")
			expect.equal(showcase.model.__unit, "player")
			expect.falsy(showcase.fallback:IsShown())
			expect.equal(showcase.chip.label:GetText(), "Live model")
			expect.equal(section.showcaseButton:GetText(), "Profile fields")
			local W = ns.MainWindow.ContentWidth()
			local game = section.showcaseView.game
			expect.truthy(ns.Showcase.MODEL_WIDTH + ns.Showcase.GAP + game:GetWidth() <= W,
				"model and panels fit side by side")
			click(section.showcaseButton)
			expect.equal(section.mode, "profile")
			expect.falsy(showcase:IsShown())
			expect.equal(showcase.model.__unit, nil, "back on the profile, the model is released")
		end)

		t:it("renders nothing while hidden, and turns with the buttons", function()
			local _, _, ns = open()
			local showcase = showcaseOf(ns)
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
			mock.modelFails = true
			local showcase, section = showcaseOf(ns)
			expect.falsy(showcase.modelShown)
			expect.truthy(showcase.fallback:IsShown())
			expect.equal(showcase.fallback.portrait.__portrait, "player")
			expect.equal(showcase.fallbackReason, "unavailable")
			expect.truthy(showcase.chip.label:GetText():find("Portrait", 1, true))
			expect.truthy(section.showcaseView.note.text:GetText():find("could not be shown", 1, true))
			expect.falsy(showcase.zoomIn:IsEnabled(), "no zoom on the portrait")
			-- Tried again when the gear changes.
			mock.modelFails = false
			showcase:GetScript("OnEvent")(showcase, "UNIT_MODEL_CHANGED", "player")
			expect.truthy(showcase.modelShown)
			expect.equal(showcase.model.__unit, "player")
		end)

		t:it("zooms within Blizzard's model range, with the buttons and the mouse wheel", function()
			local _, _, ns = open()
			local showcase = showcaseOf(ns)
			local S = ns.Showcase
			expect.equal(showcase.zoom, S.ZOOM_MIN)
			expect.falsy(showcase.zoomOut:IsEnabled(), "already fully out")
			click(showcase.zoomIn)
			expect.truthy(math.abs(showcase.zoom - S.ZOOM_STEP) < 1e-9)
			for _ = 1, 10 do showcase.model:GetScript("OnMouseWheel")(showcase.model, 1) end
			expect.equal(showcase.zoom, S.ZOOM_MAX, "clamped at the top")
			expect.falsy(showcase.zoomIn:IsEnabled())
			for _ = 1, 10 do showcase.model:GetScript("OnMouseWheel")(showcase.model, -1) end
			expect.equal(showcase.zoom, S.ZOOM_MIN, "clamped at the bottom")
			expect.truthy(S.ZOOM_MIN == 0 and S.ZOOM_MAX == 0.7, "MODELFRAME_MIN_ZOOM / MAX_ZOOM of the 1.15.9 UI")
		end)

		t:it("turns by dragging, with an update handler only while the button is held", function()
			local mock, _, ns = open()
			local showcase = showcaseOf(ns)
			local model = showcase.model
			expect.equal(model:GetScript("OnUpdate"), nil, "no per-frame work while idle")
			mock.cursorX = 500
			model:GetScript("OnMouseDown")(model)
			expect.truthy(model:GetScript("OnUpdate"))
			mock.cursorX = 550
			model:GetScript("OnUpdate")(model, 0.016)
			expect.truthy(math.abs(model:GetRotation() - 50 * ns.Showcase.DRAG_SPEED) < 1e-9)
			model:GetScript("OnMouseUp")(model)
			expect.equal(model:GetScript("OnUpdate"), nil)
			model:GetScript("OnMouseDown")(model)
			showcase:Hide()
			expect.equal(model:GetScript("OnUpdate"), nil, "hiding ends a drag")
		end)

		t:it("lets the player choose the portrait, remembered per character", function()
			local _, env, ns = open()
			local showcase, section = showcaseOf(ns)
			local toggle = section.showcaseView.note.toggle
			expect.equal(toggle:GetText(), "Show portrait instead")
			click(toggle)
			expect.falsy(showcase.modelShown)
			expect.equal(showcase.fallbackReason, "choice")
			expect.equal(showcase.model.__unit, nil, "the model is not rendered")
			expect.truthy(showcase.fallback:IsShown())
			expect.equal(toggle:GetText(), "Show the live model")
			expect.deepEqual(env.DawnwardChroniclesDB.ui.showcase, { [CHAR] = { portrait = true } })
			-- Kept across reopening and across sessions.
			showcase:Hide()
			showcase:Show()
			expect.falsy(showcase.modelShown)
			local _, _, ns2 = Boot.Start({ savedVariables = { DawnwardChroniclesDB = env.DawnwardChroniclesDB } })
			expect.truthy(ns2.Actions.ShowcasePortrait(ns2.ctx))
			click(toggle)
			expect.truthy(showcase.modelShown)
			expect.equal(env.DawnwardChroniclesDB.ui.showcase, nil, "the default leaves no trace")
		end)

		t:it("cleans the stored portrait choice", function()
			local ns = select(3, Boot.Load())
			local ui = ns.Schema.NormalizeUi({ showcase = { ["A-R"] = { portrait = true }, ["B-R"] = { portrait = "yes" },
				[5] = { portrait = true }, ["C-R"] = "x" } })
			expect.deepEqual(ui.showcase, { ["A-R"] = { portrait = true } })
			expect.equal(ns.Schema.NormalizeUi({ showcase = { ["B-R"] = {} } }).showcase, nil)
		end)

		t:it("shows the game's identity apart from what the player wrote", function()
			local mock, _, ns = open()
			mock.guild = { name = "The Lantern Watch", rank = "Member" }
			mock.Slash("set name Aelin Brightwater")
			mock.Slash("set title Keeper of the Road")
			mock.Slash("vis title public")
			mock.Slash("set summary Kind to strangers.")
			local _, section = showcaseOf(ns)
			local view = section.showcaseView
			expect.equal(view.game.title:GetText(), "IN GAME")
			expect.equal(view.own.title:GetText(), "Keeper of the Road")
			local values = {}
			for i, row in ipairs(view.game.rows) do values[i] = row.key:GetText() .. "=" .. row.value:GetText() end
			expect.equal(values[1], "LEVEL=20")
			expect.truthy(values[2]:find("RACE · CLASS=Orc · ", 1, true), values[2])
			expect.truthy(values[2]:find("Mage", 1, true))
			expect.equal(values[3], "GUILD=The Lantern Watch")
			expect.equal(values[4], "REALM=Test Realm")
			expect.equal(view.own.name:GetText(), "Aelin Brightwater")
			expect.equal(view.own.summary:GetText(), "Kind to strangers.")
			local chips = {}
			for _, c in ipairs(view.own.chips) do
				if c:IsShown() then chips[#chips + 1] = c.label:GetText() end
			end
			expect.deepEqual(chips, { "Name is Private", "Title is Public", "Summary is Private" })
			-- Nothing about the game is stored.
			local char = ns.Actions.Character(ns.ctx)
			expect.equal(char.fields.guild, nil)
			mock.guild = nil
			ns.MainWindow.Refresh()
			expect.equal(view.game.rows[3].value:GetText(), "No guild")
		end)

		t:it("colours the class with the game's class colour", function()
			local ns = select(3, Boot.Load())
			local rows = ns.Showcase.GameRows({ level = 3, raceName = "Human", className = "Paladin",
				classColor = { 0.96, 0.55, 0.73 } })
			expect.equal(rows[2].value, "Human · |cfff58cbaPaladin|r")
			local empty = ns.Showcase.GameRows({})
			expect.equal(empty[1].value, "Unknown")
			expect.truthy(empty[3].empty)
		end)

		t:it("listens for guild changes only while the showcase is shown", function()
			local _, _, ns = open()
			local _, section = showcaseOf(ns)
			local view = section.showcaseView
			view:Hide()
			view:Show()
			expect.truthy(view.__events.PLAYER_GUILD_UPDATE)
			click(section.showcaseButton)
			expect.falsy(view.__events.PLAYER_GUILD_UPDATE)
		end)

		t:it("steps aside while a field is being edited, then comes back", function()
			local mock, _, ns = open()
			mock.Slash("set name Aelin")
			local showcase, section = showcaseOf(ns)
			section:OpenEditor(ns.Schema.FIELD_BY_KEY.name)
			expect.falsy(showcase:IsShown())
			expect.equal(showcase.model.__unit, nil)
			expect.falsy(section.header:IsShown(), "header actions wait for the editor")
			click(section.editor.cancel)
			expect.truthy(showcase:IsShown())
			expect.equal(section.mode, "showcase")
			expect.equal(showcase.model.__unit, "player")
			click(section.showcaseView.own.edit)
			expect.equal(section.mode, "profile")
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
