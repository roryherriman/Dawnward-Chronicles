-- L2 (v0.10.1): the Phase 8 interface refinements (docs/design/audit/
-- v10.1-refinements.md). Story answer cards with long answers, the Showcase
-- controls, Character scrolling when the room changes, empty states, the
-- guide, Settings wording and shared text roles. Mocked client: not in-game
-- evidence.
local Boot = require("support.boot")
local Sweep = require("support.sweep")

local click = Sweep.click

local function turnIn(mock, id, title)
	mock.quest = { id = id, title = title, level = 20 }
	mock.Fire("QUEST_COMPLETE")
	mock.Fire("QUEST_TURNED_IN", id, 100, 10)
end

-- The last TOPLEFT anchor's offsets (x, top as a positive distance).
local function topLeft(region)
	for i = #(region.__points or {}), 1, -1 do
		local p = region.__points[i]
		if p[1] == "TOPLEFT" then return p[#p - 1], -p[#p] end
	end
end

local LONG = {
	"It feels like coming home, and also like the first night she slept under a roof that was not her "
		.. "father's, long ago, before the lanterns went out and the road took her.",
	"Smaller.",
	"She hesitates at the edge of town, counting the windows that are still lit and the ones that are not.",
	"Antidisestablishmentarianismwithoutanybreaksatallanywhereinthisanswer and then some words.",
	"It reminds her of her goal: find the missing courier before the snows close the pass.",
	"Nothing in particular.",
}

return function(t, expect)
	t:describe("Story answer cards with long answers (v0.10.1, L2)", function()
		local function open(scale)
			local mock, _, ns = Boot.Start()
			mock.Slash("set name Kyssarra")
			mock.Slash("")
			turnIn(mock, 70, "Kobold Candles")
			local present = ns.Reactions.Present
			ns.Reactions.Present = function(...)
				local p = present(...)
				if p then
					for i, option in ipairs(p.options) do option.text = LONG[i] or option.text end
				end
				return p
			end
			ns.MainWindow.GetFrame():SetScale(scale or 1)
			ns.MainWindow.Select("story")
			return mock, ns, ns.StoryView.section
		end

		t:it("sizes each row to its longest answer, keeps text, hint and disc inside every card", function()
			for _, scale in ipairs({ 1, 0.7, 1.4 }) do
				local _, ns, section = open(scale)
				local L, layout = ns.StoryView.LAYOUT, section.layout
				local o = L.option
				local shown, discX = 0, nil
				for i, b in ipairs(section.optionButtons) do
					if b:IsShown() then
						shown = shown + 1
						local row = layout.rows[math.floor((i - 1) / 2) + 1]
						expect.equal(b:GetHeight(), row.height, "both cards of a row are as tall as the row")
						local _, textTop = topLeft(b.text)
						local lines = math.min(b.lines, layout.optionLines)
						local bottom = textTop + ns.Style.TextHeight(lines, o.size, o.spacing)
						if b.hint:IsShown() then bottom = bottom + o.hintGap + o.hint end
						expect.truthy(textTop >= layout.padY, "answer " .. i .. " starts inside the card")
						expect.truthy(bottom <= row.height - layout.padY + 1,
							"answer " .. i .. " and its hint end inside the card (scale " .. scale .. ")")
						-- The number disc: same column in every card, centred in it.
						local p = b.key.__points[1]
						expect.equal(p[1], "LEFT")
						discX = discX or p[#p - 1]
						expect.equal(p[#p - 1], discX, "numbers line up")
						expect.equal(p[#p], 0, "the disc is centred on the card's height")
						expect.truthy(o.keyLeft + o.key + o.textGap == b.textLeft, "text starts after the disc")
						-- A cut answer keeps its whole text in the tooltip.
						expect.truthy(b.tooltipText:find(LONG[i], 1, true), "full answer on hover")
					end
				end
				expect.truthy(shown >= 4, "a moment shows its answers")
				-- Rows never overlap, and the own-words field and actions follow.
				local y = layout.gridTop
				for _, row in ipairs(layout.rows) do
					expect.truthy(row.top >= y, "rows in order")
					y = row.top + row.height
				end
				expect.truthy(layout.customLabelTop >= y, "the own-words label under the answers")
				local _, customTop = topLeft(section.customArea.frame)
				expect.equal(customTop, layout.customTop)
				expect.truthy(layout.customTop + layout.customH <= layout.buttonsTop, "the field above the actions")
				expect.truthy(layout.fits, "the moment fits")
			end
		end)

		t:it("counts an unbroken long word as the lines the client breaks it into", function()
			local _, ns = open()
			local word = string.rep("a", 120)
			local width = 200
			local w = ns.Style.TextWidth(word, "reading")
			expect.equal(ns.Style.WrapLines(word, "reading", 16, width), math.ceil(w / width))
			expect.equal(ns.StoryView.WrapLines(word, "reading", 16, width), ns.Style.WrapLines(word, "reading", 16, width))
		end)
	end)

	t:describe("Showcase controls (v0.10.1, L2)", function()
		local function open()
			local mock, _, ns = Boot.Start()
			mock.Slash("")
			ns.MainWindow.Select("character")
			click(ns.CharacterView.section.showcaseButton)
			return mock, ns, ns.CharacterView.section.showcase
		end

		t:it("draws turn and zoom as line icons in their buttons, with hover, pressed and disabled states", function()
			local _, ns, model = open()
			local theme = ns.Style.Current()
			expect.equal(model.zoomIn.icon.name, "plus")
			expect.equal(model.zoomOut.icon.name, "minus")
			expect.equal(model.zoomIn.__text, "", "no glyph beside the icon")
			for _, b in ipairs({ model.left, model.right }) do
				-- Rest: the ghost edge; hover: the gold edge and the heading tone.
				expect.equal(b.edges.top.__color[4], 1)
				b:GetScript("OnEnter")(b)
				expect.equal(b.edges.top.__color[1], theme.border[1], "hover: gold edge")
				-- Pressed: the icon moves down a pixel; released: back.
				local before = b.icon.__points[1][5]
				b:GetScript("OnMouseDown")(b)
				expect.equal(b.icon.__points[1][5], before - 1, "pressed")
				b:GetScript("OnMouseUp")(b)
				expect.equal(b.icon.__points[1][5], before)
				b:GetScript("OnLeave")(b)
			end
			-- Zoom range ends disable the matching button and dim its icon.
			for _ = 1, 10 do model:Zoom(ns.Showcase.ZOOM_STEP) end
			expect.falsy(model.zoomIn:IsEnabled())
			expect.equal(model.zoomIn.icon.lines[1].__color[4], ns.Widgets.BUTTON.disabledAlpha)
			expect.truthy(model.zoomOut:IsEnabled())
		end)

		t:it("keeps the turn buttons and the note in the control bar, clear of each other", function()
			local _, ns, model = open()
			local C = ns.Showcase.CARD
			local leftX = model.left.__points[1][2]
			expect.equal(leftX, C.pad)
			local noteX = model.note.__points[1][2]
			expect.truthy(noteX >= C.pad + 2 * C.button + C.gap, "the note starts after both buttons")
			expect.equal(model.left:GetHeight(), C.button)
			expect.truthy(C.button <= ns.Showcase.BAR_HEIGHT, "buttons inside the bar")
		end)
	end)

	t:describe("Character columns when the room changes (v0.10.1, L2)", function()
		t:it("keeps the left column's place inside its range when the callout comes and goes", function()
			local mock, _, ns = Boot.Start()
			mock.Slash("set name Lirael")
			mock.Slash("set summary " .. string.rep("She keeps a lantern lit for everyone. ", 30))
			mock.Slash("set background " .. string.rep("Born in Lordaeron, raised on the road. ", 30))
			mock.Slash("")
			-- The callout (an older character's one-time question) takes room
			-- from both columns; forced here, then gone.
			local shows = ns.CharacterView.ShowsPublishCallout
			ns.CharacterView.ShowsPublishCallout = function() return true end
			ns.MainWindow.Select("character")
			local section = ns.CharacterView.section
			expect.truthy(section.callout:IsShown(), "the callout takes room")
			ns.Widgets.ScrollTo(section.scroll, 100000)
			local atEnd = section.scroll:GetVerticalScroll()
			expect.truthy(atEnd > 0)
			ns.CharacterView.ShowsPublishCallout = shows
			ns.MainWindow.Refresh()
			expect.falsy(section.callout:IsShown())
			local range = section.scroll:GetVerticalScrollRange()
			expect.truthy(range < atEnd, "a taller view has less to scroll")
			expect.equal(section.scroll:GetVerticalScroll(), range, "the place stops at the new end")
			expect.equal(section.sideScroll:GetVerticalScroll(), 0, "the right column does not move")
		end)
	end)

	t:describe("empty states (v0.10.1, L2)", function()
		t:it("shows the same centred card with icon, title, text and the tab's New action on Chronicle", function()
			local _, _, ns = Sweep.Empty()
			for _, tab in ipairs(ns.ChronicleView.TABS) do
				Sweep.ChronicleTab(ns, tab.id)
				local section = ns.ChronicleView.section
				local state = tab.id == "places" and section.places.empty or section.emptyPanel
				expect.truthy(state:IsShown(), tab.id .. " is empty")
				expect.truthy(state.title:GetText() ~= "", tab.id .. ": a title")
				expect.equal(state.text.__justifyH or "CENTER", "CENTER")
				expect.truthy(state:GetHeight() >= state.height, tab.id .. ": sized to its words")
				if tab.new then
					expect.truthy(state.action:IsShown(), tab.id .. ": one action")
					expect.equal(state.action.__text, tab.new)
					click(state.action)
					expect.truthy(section.form:IsOpen(), tab.id .. ": the action opens its form")
					click(section.form.cancel)
				else
					expect.falsy(state.action:IsShown(), tab.id .. ": no action where none fits")
				end
			end
		end)

		t:it("offers Clear search when a search finds nothing", function()
			local mock, _, ns = Boot.Start()
			mock.Slash("memory add The night the river flooded")
			mock.Slash("")
			Sweep.ChronicleTab(ns, "memories")
			local section = ns.ChronicleView.section
			section.query = "zzzz"
			ns.MainWindow.Refresh()
			expect.truthy(section.emptyPanel:IsShown())
			expect.equal(section.emptyPanel.title:GetText(), "No match")
			click(section.emptyPanel.action)
			expect.equal(section.query, "")
			expect.falsy(section.emptyPanel:IsShown(), "the memory is back")
		end)

		t:it("gives the Character readers an empty card with their action", function()
			local _, _, ns = Sweep.Empty()
			ns.MainWindow.Select("character")
			local section = ns.CharacterView.section
			section:OpenReader("family")
			local reader = section.reader
			expect.truthy(reader.empty:IsShown())
			expect.falsy(reader.action:IsShown(), "the action is in the card, not twice")
			click(reader.empty.action)
			expect.truthy(section.form:IsOpen(), "Add family member")
			click(section.form.cancel)
			section:OpenReader("story")
			expect.equal(reader.empty.title:GetText(), "No story yet")
			expect.equal(reader.empty.action.__text, "Import a story")
		end)

		t:it("puts the Story sparkle over the empty Story card, gone while a moment waits", function()
			local mock, _, ns = Boot.Start()
			mock.Slash("set name Morrow")
			mock.Slash("")
			ns.MainWindow.Select("story")
			local section = ns.StoryView.section
			expect.truthy(section.emptyIcon and section.emptyIcon:IsVisible(), "icon shown")
			expect.truthy(section.summary:GetText():find(" · ", 1, true) or section.summary:GetText() ==
				"Nothing recorded yet.")
			turnIn(mock, 71, "A Moment")
			ns.MainWindow.Refresh()
			expect.falsy(section.emptyIcon:IsShown())
		end)
	end)

	t:describe("guide (v0.10.1, L2)", function()
		t:it("uses the design system's sizes, plain Back and Next, and scrolls long results", function()
			local mock, _, ns = Boot.Start()
			mock.Slash("")
			ns.GuidePanel.Open(1)
			local panel, G = ns.GuidePanel.panel, ns.GuidePanel.LAYOUT
			for _, b in ipairs(panel.topicButtons) do
				expect.equal(b:GetHeight(), ns.Style.CONTROL.compact)
				expect.truthy(ns.Widgets.LabelFits(b.__text, b:GetWidth(), b:GetHeight(), "segment"), b.__text)
			end
			expect.truthy(panel.topicButtons[1].selected)
			expect.equal(panel.back.__text, "Back")
			expect.equal(panel.next.__text, "Next")
			for _, b in ipairs({ panel.back, panel.next, panel.close, panel.searchButton }) do
				expect.equal(b:GetHeight(), G.buttonH)
			end
			-- Everything the command list holds: long, so the column scrolls.
			panel.search:SetText("a")
			click(panel.searchButton)
			expect.equal(panel.title:GetText(), "Search")
			expect.truthy(panel.scroll:GetVerticalScrollRange() > 0, "long results scroll instead of being cut")
			expect.truthy(panel.child:GetHeight() >= panel.body:GetHeight())
			expect.truthy(panel.scroll:IsMouseWheelEnabled(), "the wheel scrolls the guide")
			panel.scroll:GetScript("OnMouseWheel")(panel.scroll, -1)
			expect.truthy(panel.scroll:GetVerticalScroll() > 0)
			-- A new topic starts at the top.
			panel:Show(2)
			expect.equal(panel.scroll:GetVerticalScroll(), 0)
			panel:Show(#ns.Guide.TOPICS)
			expect.equal(panel.next.__text, "Done")
		end)
	end)

	t:describe("Settings and shared text roles (v0.10.1, L2)", function()
		t:it("uses no developer language on the ordinary pages of a release build", function()
			local mock, _, ns = Sweep.Sample()
			-- A release build (no "-dev" tag): the Testing panel is not shown.
			ns.ctx.version = "0.10.1"
			local WORDS = { "simulation", "debug", "dev ", "lua", "savedvariables", "api", "test data", "nil" }
			for _, page in ipairs({ "general", "story", "data", "help" }) do
				ns.SettingsPanel.OpenPage(page)
				for _, f in ipairs(mock.allFrames) do
					if f.__kind ~= "EditBox" and f.IsVisible and f:IsVisible() then
						for _, text in ipairs({ f.__text, f.tooltipTitle, f.tooltipText }) do
							if type(text) == "string" then
								-- The version number may carry its build tag ("0.10.0-dev").
								local lower = text:lower():gsub("%d+%.%d+%.%d+%-?%w*", "")
								for _, word in ipairs(WORDS) do
									expect.falsy(lower:find("%f[%w]" .. word:gsub(" ", "") .. "%f[%W]"),
										page .. ": \"" .. word .. "\" in " .. text)
								end
							end
						end
					end
				end
			end
		end)

		t:it("names Significance options as the controls do", function()
			local _, _, ns = Boot.Start()
			for _, setting in ipairs(ns.SettingsPanel.STORY_SETTINGS) do
				for _, item in ipairs(ns.SettingsPanel.Options(setting)) do
					if setting.key == "threshold" then
						expect.truthy(setting.help:find(item.label, 1, true), "help names " .. item.label)
					end
				end
			end
		end)

		t:it("sets side-panel notes in one style on every screen", function()
			local _, _, ns = Sweep.Empty()
			ns.MainWindow.Select("journal")
			local journal = ns.JournalView.section
			ns.MainWindow.Select("story")
			local story = ns.StoryView.section
			ns.MainWindow.Select("character")
			local character = ns.CharacterView.section
			local font = journal.goals.empty.__template
			expect.equal(story.waitingNote.__template, font)
			expect.equal(character.familyPanel.empty.__template, font)
			expect.equal(font, ns.Style.FontFor("small"))
		end)
	end)
end
