-- L2: journal window layout, layering, navigation, level-up capture and
-- themes, driven through the real entry points against the WoW mock.
local Boot = require("support.boot")

local STRATA_ORDER = {
	BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5,
	FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8,
}

local function overlaps(a, b)
	return a.left < b.right and b.left < a.right and a.bottom < b.top and b.bottom < a.top
end

local function inside(inner, outer)
	return inner.left >= outer.left and inner.right <= outer.right
		and inner.bottom >= outer.bottom and inner.top <= outer.top
end

local CHAR = "Testchar-TestRealm"

return function(t, expect)
	t:describe("journal window layout", function()
		local _, _, ns = Boot.Load()
		local MainWindow = ns.MainWindow
		local L = MainWindow.LAYOUT
		local r = MainWindow.ComputeLayout(L)

		t:it("scales itself to fit the smallest screen area the game's UI scale allows, and stays readable", function()
			-- The approved design is 1100 x 720. At the maximum UI scale UIParent is
			-- about 668 units tall and 890 wide: the window scales down to fit both.
			local scale = ns.Style.FitScale(L.height, 668, nil, L.width, 890)
			expect.truthy(L.width * scale <= 890 - 40 and L.height * scale <= 668 - 40, "fits")
			expect.truthy(scale >= 0.75, "not shrunk below three quarters: " .. scale)
			expect.equal(ns.Style.FitScale(L.height, 1080, nil, L.width, 1920), 1, "full size where there is room")
		end)

		t:it("keeps tabs, gear, title, content and status apart and inside the background", function()
			local regions = { r.title, r.tabs[1], r.tabs[2], r.tabs[3], r.tabs[4], r.gear, r.content, r.status }
			for i = 1, #regions do
				expect.truthy(inside(regions[i], r.background), "region " .. i .. " escapes the background")
				for j = i + 1, #regions do
					expect.falsy(overlaps(regions[i], regions[j]), "regions " .. i .. " and " .. j .. " overlap")
				end
			end
		end)

		t:it("keeps the close button in the header, and the rail apart from the content", function()
			expect.truthy(r.title.right <= r.close.left)
			expect.truthy(inside(r.close, r.background))
			for _, rail in ipairs({ r.tabs[1], r.tabs[4], r.help, r.gear, r.trp3, r.portrait, r.name }) do
				expect.truthy(rail.right <= L.railWidth, "rail part inside the rail")
				expect.falsy(overlaps(rail, r.content))
			end
		end)

		t:it("gives the content area a usable reading size", function()
			expect.truthy(r.content.right - r.content.left >= 520)
			expect.truthy(r.content.top - r.content.bottom >= 360)
		end)

		t:it("keeps every rail part apart, top to bottom, inside the rail's padding", function()
			local stack = { r.wordmark, r.portrait, r.name, r.tabs[1], r.tabs[2], r.tabs[3], r.tabs[4], r.trp3, r.help }
			for i, region in ipairs(stack) do
				expect.truthy(region.left >= L.railPad - 0.001 and region.right <= L.railWidth - L.railPad + 0.001,
					"rail part " .. i .. " inside the padding")
				if i > 1 then
					expect.truthy(stack[i - 1].bottom >= region.top, "rail parts " .. (i - 1) .. " and " .. i .. " overlap")
				end
			end
			expect.falsy(overlaps(r.help, r.gear))
			expect.truthy(inside(r.levelBadge, r.rail))
			expect.falsy(overlaps(r.levelBadge, r.name), "the level badge stays above the name")
		end)

		t:it("fits the screen at its smallest and largest scale, and the eyebrow sits above the title", function()
			local M = ns.MainWindow
			-- The largest scale on a 1080p screen at UI scale 1 (UIParent 768 tall).
			local big = M.EffectiveScale(M.MAX_SCALE, 1365, 768)
			expect.truthy(L.width * big <= 1365 - M.FIT_MARGIN + 0.001 and L.height * big <= 768 - M.FIT_MARGIN + 0.001)
			local small = M.EffectiveScale(M.MIN_SCALE, 1365, 768)
			expect.equal(small, M.MIN_SCALE)
			-- At the smallest scale the 13 px minimum style is still 9 px or more on screen.
			expect.truthy(ns.Style.MIN_TEXT * M.MIN_SCALE >= 9)
			expect.truthy(r.eyebrow.bottom >= r.title.top, "eyebrow above the title")
			expect.falsy(overlaps(r.eyebrow, r.close) or overlaps(r.title, r.close))
		end)
	end)

	t:describe("journal window (L2)", function()
		t:it("/dawnward and /dwc open and close the journal; status stays available", function()
			local mock, _, ns = Boot.Start()
			mock.Slash("")
			expect.truthy(ns.MainWindow.IsShown())
			mock.Slash("")
			expect.falsy(ns.MainWindow.IsShown())
			mock.chat = {}
			mock.env.SlashCmdList.DAWNWARD("   ")
			expect.truthy(ns.MainWindow.IsShown(), "/dwc uses the same handler")
			expect.truthy(mock.Slash("status"):find("Dawnward Chronicles"))
		end)

		t:it("sits below game dialogs and tooltips, and below the export window", function()
			local mock, _, ns = Boot.Start()
			mock.Slash("")
			local main = ns.MainWindow.GetFrame()
			expect.equal(main:GetFrameStrata(), "MEDIUM")
			expect.truthy(main.__toplevel)
			expect.truthy(STRATA_ORDER[main:GetFrameStrata()] < STRATA_ORDER.DIALOG)
			mock.Slash("set name A")
			mock.Slash("export backup")
			local copy = ns.CopyBox.GetFrame()
			expect.truthy(STRATA_ORDER[copy:GetFrameStrata()] > STRATA_ORDER[main:GetFrameStrata()])
		end)

		t:it("uses opaque backgrounds and closes with Escape", function()
			local mock, env, ns = Boot.Start()
			mock.Slash("")
			local main = ns.MainWindow.GetFrame()
			expect.equal(main.__backdrop, nil, "no stock dialog border; Dawnward chrome instead")
			expect.truthy(main.chrome)
			expect.equal(main.background.__color[4], 1)
			expect.equal(main.contentWell.__color[4], 1)
			local found = false
			for _, name in ipairs(env.UISpecialFrames) do
				if name == "DawnwardChroniclesJournal" then found = true end
			end
			expect.truthy(found)
		end)

		t:it("shows exactly four sections and switches between them", function()
			local mock, _, ns = Boot.Start()
			mock.Slash("")
			local labels = {}
			for _, def in ipairs(ns.MainWindow.Sections()) do labels[#labels + 1] = def.label end
			expect.deepEqual(labels, { "Journal", "Character", "Story", "Chronicle" })
			expect.equal(ns.MainWindow.CurrentSection(), "journal")
			local frame = ns.MainWindow.GetFrame()
			frame.tabs[2]:GetScript("OnClick")(frame.tabs[2])
			expect.equal(ns.MainWindow.CurrentSection(), "character")
			for _, def in ipairs(ns.MainWindow.Sections()) do
				expect.equal(def.instance.frame:IsShown(), def.id == "character", def.id)
			end
			expect.truthy(frame.tabs[2].underline:IsShown())
			expect.falsy(frame.tabs[1].underline:IsShown())
			ns.MainWindow.Select("story")
			expect.equal(ns.StoryView.HEADING, "Your story is still being written")
		end)

		t:it("remembers its position in real data", function()
			local mock, env, ns = Boot.Start()
			mock.Slash("")
			local frame = ns.MainWindow.GetFrame()
			frame.__left, frame.__top = 222, 555
			frame:GetScript("OnDragStop")(frame)
			expect.deepEqual(env.DawnwardChroniclesDB.ui.position, { left = 222, top = 555, scale = 1 })
			mock.Slash("")
			mock.Slash("")
			local point = frame.__points[#frame.__points]
			expect.deepEqual({ point[1], point[4], point[5] }, { "TOPLEFT", 222, 555 })
		end)

		t:it("titles the journal and flags simulation", function()
			local mock, _, ns = Boot.Start()
			mock.Slash("set name Aelin")
			mock.Slash("")
			local frame = ns.MainWindow.GetFrame()
			expect.equal(frame.title:GetText(), "The road so far", "the journal's own heading; the rail names the character")
			mock.Slash("sim on")
			expect.truthy(frame.title:GetText():find("simulation"), "refreshes after slash commands")
		end)
	end)

	t:describe("level-up capture (L2)", function()
		t:it("records one entry per level with zone and source, refreshing the window", function()
			local mock, env, ns = Boot.Start()
			mock.Slash("")
			mock.chat = {}
			mock.Fire("PLAYER_LEVEL_UP", 12, 10, 5)
			mock.Fire("PLAYER_LEVEL_UP", 12, 10, 5)
			local journal = env.DawnwardChroniclesDB.characters[CHAR].journal
			expect.equal(#journal, 1)
			expect.deepEqual(journal[1].event, { type = "levelup", key = "levelup:12", source = "PLAYER_LEVEL_UP",
				level = 12, zone = "Elwynn Forest", subzone = "Goldshire" })
			expect.equal(#mock.chat, 1, "announced once; the duplicate is silent")
			expect.equal(ns.JournalView.section.visibleCount, 1, "open journal refreshed")
		end)

		t:it("goes to real data even while simulation mode is on", function()
			local mock, env = Boot.Start()
			mock.Slash("sim on")
			mock.Fire("PLAYER_LEVEL_UP", 20)
			expect.equal(#env.DawnwardChroniclesDB.characters[CHAR].journal, 1)
			local simChar = env.DawnwardChroniclesSimDB.characters[CHAR]
			expect.truthy(simChar == nil or #simChar.journal == 0)
		end)

		t:it("is not recorded into read-only data, with a single warning", function()
			local saved = { schemaVersion = 99, characters = {} }
			local mock = Boot.Start({ savedVariables = { DawnwardChroniclesDB = saved } })
			mock.chat = {}
			mock.Fire("PLAYER_LEVEL_UP", 5)
			mock.Fire("PLAYER_LEVEL_UP", 6)
			expect.equal(#mock.chat, 1)
			expect.deepEqual(saved, { schemaVersion = 99, characters = {} })
		end)
	end)

	t:describe("journal list (L2)", function()
		t:it("shows entries newest first in one scrolling list that reaches the oldest", function()
			local mock, _, ns = Boot.Start()
			for i = 1, 25 do
				mock.Slash("journal add Entry number " .. i)
			end
			mock.Slash("")
			local section = ns.JournalView.section
			expect.equal(section.matchCount, 25)
			expect.truthy(section.visibleCount >= 1 and section.visibleCount < 25, "only the cards in view")
			expect.equal(section.rows[1].entry.text, "Entry number 25")
			expect.equal(section.offset, 0)
			section:ScrollTo(math.huge)
			expect.equal(section.offset, section.maxOffset)
			expect.equal(section.rows[section.visibleCount].entry.text, "Entry number 1")
			for i = 2, section.visibleCount do
				local newer = tonumber(section.rows[i - 1].entry.text:match("%d+"))
				expect.equal(tonumber(section.rows[i].entry.text:match("%d+")), newer - 1, "in order")
			end
		end)

		t:it("changes an entry's visibility from its button", function()
			local mock, env, ns = Boot.Start()
			mock.Slash("journal add Something happened")
			mock.Slash("")
			local row = ns.JournalView.section.rows[1]
			expect.equal(row.vis.level, "private")
			row.vis:GetScript("OnClick")(row.vis)
			-- Publishing asks first, showing exactly what becomes public (#13).
			expect.equal(env.DawnwardChroniclesDB.characters[CHAR].journal[1].visibility, "private")
			local asked = mock.AcceptPopup()
			expect.truthy(asked.text:find("Something happened", 1, true))
			expect.equal(env.DawnwardChroniclesDB.characters[CHAR].journal[1].visibility, "public")
			expect.equal(ns.JournalView.section.rows[1].vis.level, "public")
		end)

		t:it("shows an empty state for a new character", function()
			local mock, _, ns = Boot.Start()
			mock.Slash("")
			expect.truthy(ns.JournalView.section.empty:IsShown())
			expect.equal(ns.JournalView.section.visibleCount, 0)
		end)
	end)

	t:describe("character section (L2)", function()
		t:it("lists every profile field, then family and history in readable form", function()
			local mock, _, ns = Boot.Start()
			mock.Slash("set name Aelin")
			mock.Slash("family add mother Ilsa Brightwater")
			mock.Slash("family set 1 status deceased")
			mock.Slash("history add Took the oath")
			mock.Slash("")
			ns.MainWindow.Select("character")
			local specs = ns.CharacterView.section.specs
			local fields, items = 0, {}
			for _, spec in ipairs(specs) do
				if spec.kind == "field" then fields = fields + 1 end
				if spec.kind == "item" then items[#items + 1] = spec.text end
			end
			expect.equal(fields, #ns.Schema.FIELDS)
			expect.deepEqual(items, { "Mother: Ilsa Brightwater (deceased)", "Took the oath" })
		end)
	end)

	t:describe("themes in the window (L2)", function()
		t:it("applies the character's theme and keeps it across sessions", function()
			local mock, env, ns = Boot.Start()
			mock.Slash("theme arcane")
			mock.Slash("")
			local frame = ns.MainWindow.GetFrame()
			local arcane = ns.Themes.Get("arcane")
			expect.deepEqual(frame.background.__color, { arcane.background[1], arcane.background[2], arcane.background[3], 1 })

			-- New session with the saved data.
			local mock2, _, ns2 = Boot.Start({ savedVariables = {
				DawnwardChroniclesDB = env.DawnwardChroniclesDB } })
			mock2.Slash("")
			local frame2 = ns2.MainWindow.GetFrame()
			expect.deepEqual(frame2.background.__color[1], arcane.background[1])
		end)
	end)
end
