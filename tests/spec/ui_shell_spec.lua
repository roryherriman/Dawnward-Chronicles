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

		t:it("titles the journal as in the design and flags simulation on every section", function()
			local mock, _, ns, frame = open()
			mock.Slash("set name Aelin")
			expect.equal(frame.title:GetText(), "The road so far", "the journal's own heading; the rail names the character")
			ns.MainWindow.Select("character")
			expect.equal(frame.title:GetText(), "Profile")
			mock.Slash("sim on")
			expect.truthy(frame.title:GetText():find("simulation", 1, true))
		end)

		t:it("keeps a section's header controls clear of the title", function()
			local mock, _, ns, frame = open()
			mock.Slash("sim on")
			local function titleRight()
				for _, p in ipairs(frame.title.__points) do
					if p[1] == "TOPRIGHT" then return p[4] end
				end
			end
			local full = frame.titleRect.right
			expect.equal(titleRight(), full, "the journal title uses the whole row")
			ns.MainWindow.Select("character")
			expect.equal(titleRight(), full - 540, "room for Import story, Preview, Showcase and Total RP 3")
			ns.MainWindow.Select("story")
			expect.equal(titleRight(), full - 230, "room for the moment pager")
			ns.MainWindow.Select("journal")
			expect.equal(titleRight(), full)
		end)

		t:it("states Total RP 3 availability without touching it", function()
			local ns = select(3, open())
			expect.equal(ns.MainWindow.TRP3Line({ installed = false }), "Total RP 3 · not installed (optional)")
			expect.equal(ns.MainWindow.TRP3Line({ installed = true, loaded = false }), "Total RP 3 · installed, not loaded")
			expect.equal(ns.MainWindow.TRP3Line({ installed = true, loaded = true, profile = { name = "Aelin RP" } }),
				'Total RP 3 · profile "Aelin RP"')
			expect.equal(ns.MainWindow.GetFrame().trp3:GetText(), "Total RP 3 · not installed (optional)")
			click(ns.MainWindow.GetFrame().trp3Link)
			expect.equal(ns.MainWindow.CurrentSection(), "settings", "the status line opens the Total RP 3 page")
		end)

		t:it("shows homeland and privacy chips from the profile's own data, never invented", function()
			local mock, env, ns, frame = open()
			expect.falsy(frame.homelandChip:IsShown(), "no homeland set: no chip")
			expect.falsy(frame.privacyChip:IsShown(), "no profile field set: nothing to summarise")
			mock.Slash("set name Aelin")
			expect.truthy(frame.privacyChip:IsShown())
			expect.equal(frame.privacyChip.label:GetText(), "Private")
			expect.equal(frame.privacyChip.tone, "private")
			mock.Slash("set homeland Goldshire")
			expect.truthy(frame.homelandChip:IsShown())
			expect.equal(frame.homelandChip.label:GetText(), "Goldshire")
			mock.Slash("vis name public")
			expect.equal(frame.privacyChip.label:GetText(), "1 of 2 public")
			expect.equal(frame.privacyChip.tone, "public")
			expect.truthy(frame.privacyChip.tooltipText:find("1 of your 2 profile fields are Public", 1, true))
			mock.Slash("vis homeland public")
			expect.equal(frame.privacyChip.label:GetText(), "Public")
			-- Showing the chips stores nothing.
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			expect.equal(char.fields.homeland.value, "Goldshire")
			expect.equal(ns.MainWindow.PrivacySummary({ fields = {} }), nil)
		end)

		t:it("keeps the chips inside the rail, cutting a long homeland with its full name on hover", function()
			local mock, _, ns, frame = open()
			mock.Slash("set name Aelin")
			mock.Slash("set homeland The Very Long Named Hamlet Beyond the Northern Hills of Lordaeron")
			local L = ns.MainWindow.LAYOUT
			local width = L.railWidth - 2 * L.railPad
			expect.truthy(frame.chipRow.total <= width, "chips fit the rail: " .. frame.chipRow.total)
			expect.truthy(frame.homelandChip.truncated)
			expect.equal(frame.homelandChip.tooltipTitle,
				"The Very Long Named Hamlet Beyond the Northern Hills of Lordaeron")
		end)

		t:it("colours the class as the game does, lightened only when too dark to read on the rail", function()
			local mock, env, ns, frame = open()
			env.RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
			mock.classToken = "MAGE"
			ns.MainWindow.Refresh()
			expect.equal(frame.charLine:GetText(), "Orc · |cff40c7ebMage|r")
			local panel = ns.Style.Current().panel
			local shaman = { 0, 0.44, 0.87 }
			expect.truthy(ns.Themes.Contrast(shaman, panel) < 4.5, "the Shaman's blue is too dark as it is")
			local readable = ns.MainWindow.ReadableColor(shaman, panel)
			expect.truthy(ns.Themes.Contrast(readable, panel) >= 4.5)
			expect.truthy(readable[3] >= shaman[3], "still the same hue, only lighter")
		end)

		t:it("lays the rail out as the design: wordmark, ring, badge, name block, navigation, status, buttons", function()
			local ns = select(3, open())
			local L = ns.MainWindow.LAYOUT
			local r = ns.MainWindow.ComputeLayout(L)
			expect.equal(L.portraitSize, 116)
			expect.equal(r.portrait.top, L.height - 56)
			-- The level badge sits on the ring's bottom edge: 14 above it, 8 below.
			expect.equal(r.levelBadge.top - r.portrait.bottom, L.badgeHeight - L.badgeDrop)
			expect.equal(r.portrait.bottom - r.levelBadge.bottom, L.badgeDrop)
			-- The name block (two name lines at most, one title line, the identity
			-- line and the chips) ends before the navigation.
			local nameLine = ns.Style.FONT_BY_STYLE.railName.size + 3
			local block = L.nameLines * nameLine + L.identityGap + 18 + L.identityGap + 17 + L.chipGap
				+ ns.Widgets.CHIP_HEIGHT
			expect.truthy(L.nameTop + block <= L.navTop - 8, "name block " .. block .. " fits above the navigation")
			expect.truthy(r.levelBadge.bottom > L.height - L.nameTop, "the badge stays above the name")
			-- Navigation: 44 high, 4 apart, the rail's full inner width.
			for i = 1, L.tabCount do
				expect.equal(r.tabs[i].top - r.tabs[i].bottom, 44)
				expect.equal(r.tabs[i].right - r.tabs[i].left, L.railWidth - 2 * L.railPad)
				if i > 1 then expect.equal(r.tabs[i - 1].bottom - r.tabs[i].top, 4) end
			end
			expect.truthy(r.tabs[L.tabCount].bottom > r.trp3.top + 16, "room between the navigation and the status")
			expect.truthy(r.trp3.bottom >= r.help.top + 8, "status above Guide and Settings")
			expect.equal(r.help.top - r.help.bottom, 30, "compact rail buttons")
			-- Header: eyebrow, then the 28 px screen title, clear of the content.
			expect.truthy(r.title.top - r.title.bottom >= ns.Style.FONT_BY_STYLE.screen.size + 6)
			expect.truthy(r.title.bottom >= r.content.top + 12)
			expect.equal(r.close.top - r.close.bottom, 36)
			expect.equal(ns.MainWindow.ContentWidth(), 772, "main area 772 at the 1100 x 720 window")
		end)

		t:it("marks the selected section with a filled panel and a gold edge", function()
			local _, _, ns, frame = open()
			local theme = ns.Style.Current()
			local tones = ns.Style.Tones(theme)
			local on, off = frame.tabs[1], frame.tabs[2]
			expect.truthy(on.underline:IsShown(), "the selected fill")
			expect.equal(on.underline.__color[1], theme.surfaceHover[1])
			expect.deepEqual(on.edges.top.__color, { theme.border[1], theme.border[2], theme.border[3], 1 })
			expect.equal(on.label.__textColor[1], tones.accentBright[1])
			expect.falsy(off.underline:IsShown())
			expect.equal(off.edges.top.__color[4], 0, "no edge on the others")
			expect.equal(off.label.__textColor[1], tones.navText[1])
			off:GetScript("OnEnter")(off)
			expect.truthy(off.bg.__color[4] > 0, "hover shows a light fill")
			off:GetScript("OnLeave")(off)
			expect.equal(off.bg.__color[4], 0)
		end)

		t:it("draws the portrait ring, badge and chips round where the client has masks, square otherwise", function()
			-- Without masks (the mock): the Showcase's tinted ring and square shapes.
			local _, _, _, frame = open()
			expect.falsy(frame.portraitRing.round)
			expect.truthy(frame.portrait.ring:IsShown())
			expect.equal(frame.levelBadge.pill, nil)
			expect.equal(frame.privacyChip.pill, nil)
			-- With masks (stubbed as the client's CreateMaskTexture would give).
			local mock, _, ns = Boot.Load()
			local masks = 0
			ns.Style.NewMask = function(f)
				masks = masks + 1
				local mask = f:CreateTexture()
				mask.isMask = true
				return mask
			end
			Boot.Login(mock)
			mock.Slash("set name Aelin")
			mock.Slash("")
			local round = ns.MainWindow.GetFrame()
			-- AddMaskTexture is a no-op in the mock, so it is present on textures.
			expect.truthy(round.portraitRing.round, "ring, gap and well are discs")
			expect.falsy(round.portrait.ring:IsShown(), "the tracking-ring stand-in is hidden")
			expect.truthy(round.levelBadge.pill ~= nil, "the level badge is a pill")
			expect.truthy(round.privacyChip.pill ~= nil, "chips are pills")
			expect.falsy(round.privacyChip.bg:IsShown(), "no square fill under a pill")
			expect.truthy(round.tabs[1].badgeBg.round, "the Story badge is a disc")
			expect.truthy(masks > 0)
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

		-- Runs queued retries until none are left (bounded).
		local function drain(mock)
			for _ = 1, 20 do
				if mock.RunTimers() == 0 then return end
			end
		end

		t:it("falls back to the portrait when the model cannot be loaded, after retrying", function()
			local mock, _, ns = open()
			mock.modelFails = true
			local showcase, section = showcaseOf(ns)
			expect.equal(showcase.state, "loading", "a failure is retried before giving up")
			expect.truthy(showcase.chip.label:GetText():find("Loading", 1, true))
			expect.truthy(showcase.fallback:IsShown(), "the portrait is shown meanwhile")
			drain(mock)
			expect.equal(showcase.attempts, #ns.Showcase.RETRY_DELAYS + 1)
			expect.falsy(showcase.modelShown)
			expect.truthy(showcase.fallback:IsShown())
			expect.equal(showcase.fallback.portrait.__portrait, "player")
			expect.equal(showcase.fallbackReason, "unavailable")
			expect.equal(showcase.chip.label:GetText(), "Portrait: live model not available")
			expect.truthy(section.showcaseView.note.text:GetText():find("could not be loaded", 1, true))
			expect.equal(section.showcaseView.note.toggle:GetText(), "Try the live model again")
			expect.falsy(showcase.zoomIn:IsEnabled(), "no zoom on the portrait")
			expect.truthy(showcase.model:IsShown(), "the model frame stays shown so it can load later")
			expect.equal(showcase.model:GetAlpha(), 0, "only made transparent")
			-- Tried again when the gear changes.
			mock.modelFails = false
			showcase:GetScript("OnEvent")(showcase, "UNIT_MODEL_CHANGED", "player")
			expect.truthy(showcase.modelShown)
			expect.equal(showcase.model.__unit, "player")
			expect.equal(showcase.model:GetAlpha(), 1)
			expect.equal(showcase.chip.label:GetText(), "Live model")
		end)

		t:it("recovers by itself when the model loads on a later attempt", function()
			local mock, _, ns = open()
			mock.modelFails = 2 -- the first two calls fail (window just opened)
			local showcase = showcaseOf(ns)
			expect.equal(showcase.state, "loading")
			drain(mock)
			expect.equal(showcase.state, "live")
			expect.truthy(showcase.modelShown)
			expect.equal(showcase.model.__blend, false, "shown at once, as the character frame does")
			expect.equal(#mock.timers, 0, "no retry left once it loaded")
		end)

		t:it("an earlier failure never stops the player asking for the live model again", function()
			local mock, _, ns = open()
			mock.modelFails = true
			local showcase, section = showcaseOf(ns)
			drain(mock)
			expect.equal(showcase.state, "unavailable")
			local toggle = section.showcaseView.note.toggle
			mock.modelFails = false
			click(toggle) -- "Try the live model again"
			expect.equal(showcase.state, "live")
			expect.equal(toggle:GetText(), "Show portrait instead")
		end)

		t:it("switches portrait to live model and back as often as asked", function()
			local mock, _, ns = open()
			local showcase, section = showcaseOf(ns)
			local toggle = section.showcaseView.note.toggle
			for _ = 1, 3 do
				click(toggle)
				expect.equal(showcase.state, "choice")
				expect.equal(showcase.chip.label:GetText(), "Portrait (your choice)")
				expect.equal(showcase.model:GetAlpha(), 0)
				click(toggle)
				expect.equal(showcase.state, "live", "the hidden-model bug: live again after the portrait")
				expect.equal(showcase.model.__unit, "player")
				expect.equal(showcase.chip.label:GetText(), "Live model")
			end
			expect.equal(#mock.timers, 0)
		end)

		t:it("stops retrying when the showcase closes, and tries afresh when it reopens", function()
			local mock, _, ns = open()
			mock.modelFails = true
			local showcase = showcaseOf(ns)
			showcase:Hide()
			local calls = mock.setUnitCalls
			drain(mock)
			expect.equal(mock.setUnitCalls, calls, "no attempts while closed")
			mock.modelFails = false
			showcase:Show()
			expect.equal(showcase.state, "live")
		end)

		t:it("tries again after a loading screen", function()
			local mock, _, ns = open()
			mock.modelFails = true
			local showcase = showcaseOf(ns)
			drain(mock)
			mock.modelFails = false
			showcase:GetScript("OnEvent")(showcase, "PLAYER_ENTERING_WORLD")
			expect.equal(showcase.state, "live")
		end)

		t:it("reports what it knows for /dawnward dev showcase", function()
			local mock, _, ns = open()
			local showcase = showcaseOf(ns)
			local lines = table.concat(showcase.Diagnostics(), "\n")
			expect.truthy(lines:find("Live model", 1, true))
			expect.truthy(lines:find("last SetUnit result: true", 1, true))
			local out = mock.Slash("dev showcase")
			expect.truthy(out:find("Showcase: Live model", 1, true))
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
			local mock2, _, ns2 = Boot.Start({ savedVariables = { DawnwardChroniclesDB = env.DawnwardChroniclesDB } })
			expect.truthy(ns2.Actions.ShowcasePortrait(ns2.ctx))
			mock2.Slash("")
			local after = showcaseOf(ns2)
			expect.equal(after.state, "choice", "after /reload the portrait choice still shows")
			click(ns2.CharacterView.section.showcaseView.note.toggle)
			expect.equal(after.state, "live", "and the live model can be asked for again")
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
			expect.equal(view.game.title:GetText(), "FROM THE GAME", "the mockup's panel title")
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

		t:it("gives the live model the whole stage above the control bar (v0.8 layout)", function()
			local _, _, ns = open()
			local showcase = showcaseOf(ns)
			local S = ns.Showcase
			local stageHeight = showcase:GetHeight() - S.BAR_HEIGHT - 2
			expect.truthy(stageHeight / showcase:GetHeight() >= 0.85, "the model takes most of the card")
			expect.equal(showcase.model.__points[1][1], "TOPLEFT")
			expect.equal(showcase.model.__points[1][2], showcase.stage, "the model fills the stage")
			-- The bar: two 36 px turn buttons, the note on at most two lines.
			expect.equal(showcase.left:GetHeight(), S.CARD.button)
			expect.equal(showcase.right:GetHeight(), S.CARD.button)
			local noteWidth = S.MODEL_WIDTH - 2 * S.CARD.pad - 2 * S.CARD.button - S.CARD.gap - 12
			expect.truthy(ns.Style.TextWidth(S.BAR_NOTE, "small") <= 2 * noteWidth * 0.95, "two lines at 13")
			-- Zoom sits over the stage while the model shows, clear of the chip.
			expect.truthy(showcase.zoomIn:IsShown() and showcase.zoomOut:IsShown())
			expect.truthy(S.CARD.pad + showcase.chip:GetWidth() + S.CARD.gap
				<= S.MODEL_WIDTH - S.CARD.pad - S.CARD.zoomButton, "the chip never runs under the zoom buttons")
			for _, label in pairs(S.MODE_LABELS) do
				showcase.chip:SetChip(label, "muted")
				expect.falsy(showcase.chip.truncated, label .. " fits beside the zoom buttons")
			end
			showcase.chip:SetChip(S.MODE_LABELS.live, "accent")
		end)

		t:it("shows the portrait fallback as a framed, centred round portrait, never stretched", function()
			local mock, _, ns = open()
			mock.modelFails = true
			local showcase, section = showcaseOf(ns)
			local S = ns.Showcase
			local fb = showcase.fallback
			expect.truthy(fb:IsShown())
			expect.equal(fb.badge:GetWidth(), S.CARD.portrait, "a fixed size")
			expect.equal(fb.badge:GetWidth(), fb.badge:GetHeight(), "square, so the round portrait stays round")
			expect.equal(fb.portrait:GetWidth(), fb.portrait:GetHeight())
			expect.truthy(fb.portrait:GetWidth() <= 128, "close to the game's own portrait size, so it stays sharp")
			expect.equal(fb.box.__points[1][1], "CENTER", "centred on the stage")
			local stageHeight = showcase:GetHeight() - S.BAR_HEIGHT - 2
			expect.truthy(fb.box:GetHeight() <= stageHeight - 2 * 40, "the frame leaves room for the chip above it")
			expect.truthy(fb.box:GetWidth() <= S.MODEL_WIDTH - 2 * S.CARD.frameInset)
			expect.equal(fb.text:GetText(), S.FALLBACK_TEXT.loading)
			expect.falsy(showcase.zoomIn:IsShown(), "no zoom buttons over the portrait")
			expect.truthy(showcase.chip:IsShown(), "the mode chip still says what shows")
			for _ = 1, 20 do
				if mock.RunTimers() == 0 then break end
			end
			expect.equal(fb.text:GetText(), S.FALLBACK_TEXT.unavailable)
			mock.modelFails = false
			click(section.showcaseView.note.toggle) -- try again
			click(section.showcaseView.note.toggle) -- choose the portrait
			expect.equal(showcase.state, "choice")
			expect.equal(fb.text:GetText(), S.FALLBACK_TEXT.choice)
		end)

		t:it("lays the game and own-words panels out as the mockup, inside the content area", function()
			local mock, _, ns = open()
			mock.guild = { name = "The Lantern Watch", rank = "Member" }
			mock.Slash("set name Aelin Brightwater")
			mock.Slash("set title Keeper of the Lantern Road")
			mock.Slash("set summary " .. string.rep("She is kind to strangers and sharp with friends. ", 6))
			local _, section = showcaseOf(ns)
			local view = section.showcaseView
			local P = ns.Showcase.PANEL
			for i, row in ipairs(view.game.rows) do
				expect.truthy(ns.Style.TextWidth(row.key:GetText(), "eyebrow") <= P.keyWidth,
					row.key:GetText() .. " fits its column")
				expect.equal(row.value.__template, ns.Style.FontFor("reading"), "values at 16")
				expect.truthy(P.rowsTop + i * P.rowHeight <= view.game:GetHeight(), "row inside the panel")
			end
			expect.equal(view.game.rows[1].value.textRole, "heading", "values in title white")
			expect.equal(view.own.title:GetText(), "Keeper of the Lantern Road")
			expect.equal(view.own.summary.__template, ns.Style.FontFor("reading"))
			local H = ns.MainWindow.ContentHeight()
			local total = view.game:GetHeight() + P.gap + view.own:GetHeight() + P.gap + view.note:GetHeight()
			expect.truthy(total <= H, "the three panels fit the content height with a long summary")
			expect.equal(view.note.toggle:GetHeight(), ns.Style.CONTROL.compact)
			expect.truthy(ns.Widgets.LabelFits("Try the live model again", view.note.toggle:GetWidth(),
				view.note.toggle:GetHeight()))
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
			local cinzel = 0
			for _, f in ipairs(ns.Style.FONTS) do
				if f.file == "display" then cinzel = cinzel + 1 end
			end
			expect.equal(ns.Style.InitFonts(), #ns.Style.FONTS - cinzel, "the Cinzel fonts fall back")
			expect.equal(ns.Style.Font("GameFontNormalLarge"), "GameFontNormalLarge")
			expect.equal(ns.Style.Font("GameFontHighlight"), "DawnwardFontBody")
			expect.equal(ns.Style.FontFor("railName"), "GameFontHighlightLarge", "a named style falls back to its game font")
			expect.equal(ns.Style.FontFor("button"), "DawnwardFontButton")
		end)

		t:it("follows the design system's type scale and never goes below the readable minimum", function()
			local _, _, ns = Boot.Load()
			local S = ns.Style
			local function size(style) return S.FONT_BY_STYLE[style].size end
			expect.equal(size("screen"), 28, "screen title: Cinzel 28")
			expect.equal(size("title"), 18, "entry and section title: Cinzel 18")
			expect.equal(size("railName"), 21, "the rail's name: Cinzel 21")
			expect.equal(size("reading"), 16, "story text: Alegreya Sans 16")
			expect.equal(S.FONT_BY_STYLE.reading.spacing, 4, "with generous leading (16 / 1.5)")
			expect.equal(size("meta"), 14, "meta line: 14")
			expect.equal(size("button"), 15, "buttons: Alegreya Sans Bold 15")
			expect.equal(S.FONT_BY_STYLE.button.file, "bold")
			expect.equal(size("buttonSmall"), 14, "compact buttons: 14")
			expect.equal(size("nav"), 17, "rail navigation: 17")
			for _, f in ipairs(S.FONTS) do
				expect.truthy(f.size >= S.MIN_TEXT, f.name .. " is " .. f.size .. ", below " .. S.MIN_TEXT)
			end
			expect.equal(size("eyebrow"), 13, "eyebrows one size above the design's 12, which relies on letter spacing")
		end)

		t:it("estimates text widths from the bundled fonts' real advance widths", function()
			local _, _, ns = Boot.Load()
			local S = ns.Style
			-- "Approve" in Alegreya Sans Bold is 3.395 em (hmtx); at 15 that is 50.9.
			expect.truthy(math.abs(S.TextWidth("Approve", "button") - 3.395 * 15) < 0.05)
			expect.truthy(S.TextWidth("DAWNWARD", "eyebrow") > S.TextWidth("DAWNWARD", "small"), "Cinzel is wide")
			expect.equal(S.TextWidth("|cffff0000Mage|r", "body"), S.TextWidth("Mage", "body"), "colour codes ignored")
			expect.truthy(S.TextWidth("Human · Paladin", "meta") > S.TextWidth("Human  Paladin", "meta"))
			expect.truthy(ns.Widgets.LabelFits("Settings", 109, 30, "ghost"))
			expect.falsy(ns.Widgets.LabelFits("A very long label for a small button", 80, 30))
		end)
	end)
end
