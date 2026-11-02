-- L2: v0.10 fidelity of the window shell, the rail and the Journal against
-- docs/design/mockups/journal-dashboard.png and Main.dc.html (audit:
-- docs/design/audit/v10-shell-journal.md). Sizes are UI units in the
-- 1100 x 720 layout, which the window scales as a whole (0.7 - 1.4), so a
-- fit here holds at every scale.
local Boot = require("support.boot")

local function click(button)
	button:GetScript("OnClick")(button)
end

local function lastPoint(region)
	local points = region.__points or {}
	return points[#points]
end

local function open(opts)
	local mock, env, ns = Boot.Start(opts)
	mock.Slash("set name Kyssarra Dawnwhisper")
	mock.Slash("set title Keeper of the Lantern Road")
	mock.Slash("set homeland Goldshire")
	mock.Slash("")
	return mock, env, ns, ns.MainWindow.GetFrame()
end

local function same(a, b)
	return math.abs(a[1] - b[1]) < 1e-6 and math.abs(a[2] - b[2]) < 1e-6 and math.abs(a[3] - b[3]) < 1e-6
end

return function(t, expect)
	t:describe("v0.10 rail (Main.dc.html .rail)", function()
		t:it("sets the wordmark as the star icon and tracked DAWNWARD inside the rail's padding", function()
			local _, _, ns, frame = open()
			local L = ns.MainWindow.LAYOUT
			expect.equal(frame.wordmarkIcon.name, "wordmark")
			local p = lastPoint(frame.wordmarkIcon)
			expect.equal(p[4], L.railPad + L.wordmarkIndent, "18 padding + 4")
			local w = lastPoint(frame.wordmark)
			expect.equal(w[4], L.railPad + L.wordmarkIndent + L.wordmarkIcon + L.wordmarkGap, "8 after the star")
			expect.equal(frame.wordmark:GetText(), "DAWNWARD")
			expect.truthy(w[4] + frame.wordmark:GetStringWidth() <= L.railWidth - L.railPad, "inside the rail")
			expect.truthy(frame.wordmark:GetStringWidth() > ns.Style.TextWidth("DAWNWARD", "eyebrow") + 10,
				"tracked like the design (0.18 em)")
			expect.equal(frame.jewel, nil, "no stand-in jewel when lines are available")
		end)

		t:it("gives every section a line icon that follows the selection colour", function()
			local _, _, ns, frame = open()
			local L = ns.MainWindow.LAYOUT
			local tones = ns.Style.Tones(ns.Style.Current())
			for i, tab in ipairs(frame.tabs) do
				expect.equal(tab.lineIcon.name, ns.MainWindow.NAV_ICONS[tab.id], tab.id)
				expect.equal(tab.icon, nil, "no game icon")
				expect.equal(lastPoint(tab.lineIcon)[2], L.navIconLeft)
				expect.equal(lastPoint(tab.label)[2], L.navLabelLeft, "label 12 after the 20 px icon")
				local want = i == 1 and tones.accentBright or tones.navText
				expect.truthy(same(tab.lineIcon.lines[1].__color, want), tab.id .. " icon colour")
			end
			ns.MainWindow.Select("story")
			expect.truthy(same(frame.tabs[3].lineIcon.lines[1].__color, tones.accentBright))
			expect.truthy(same(frame.tabs[1].lineIcon.lines[1].__color, tones.navText))
			expect.equal(frame.tabs[1].label.__template, ns.Style.FontFor("nav"))
			expect.equal(ns.Style.FONT_BY_STYLE.nav.file, "medium", "17 / 500 as the design")
		end)

		t:it("sets the title in italic and the homeland chip with its house icon inside the rail", function()
			local _, _, ns, frame = open()
			local L = ns.MainWindow.LAYOUT
			expect.equal(frame.charTitle.__template, ns.Style.FontFor("italic"))
			expect.equal(frame.charTitle:GetText(), "Keeper of the Lantern Road")
			local chip = frame.homelandChip
			expect.equal(chip.icon.name, "home")
			expect.truthy(chip:GetWidth() <= L.railWidth - 2 * L.railPad)
			expect.equal(frame.privacyChip, nil, "no privacy chip")
		end)

		t:it("draws Guide and Settings with their icons, and the labels still fit", function()
			local _, _, ns, frame = open()
			for _, pair in ipairs({ { frame.help, "guide" }, { frame.gear, "settings" } }) do
				local b, name = pair[1], pair[2]
				expect.equal(b.icon.name, name)
				expect.truthy(ns.Widgets.LabelFits(b:GetText(), b:GetWidth(), b:GetHeight(), "ghost", true), name)
			end
			expect.equal(frame.close.icon.name, "close", "the close button's line X")
			expect.equal(frame.close.icon.__scale, 1, "18 px in the 36 px button")
		end)

		t:it("reports Total RP 3 sync from the ledger: a quiet dot when off, gold when on", function()
			local _, _, ns, frame = open()
			local ctx = ns.ctx
			local tones = ns.Style.Tones(ns.Style.Current())
			local entry = {}
			ctx.trp3Status = function() return { installed = true, loaded = true, profile = { name = "Kyssarra" } } end
			ctx.trp3Deps = function()
				return { ledger = { optIn = { [ctx.characterKey] = entry } }, characterKey = ctx.characterKey }
			end
			ns.MainWindow.Refresh()
			expect.equal(frame.trp3:GetText(), "Total RP 3 · sync off")
			expect.truthy(same(frame.trp3Dot.__color, tones.dot))
			expect.truthy(frame.trp3Link.tooltipText:find('Active profile: "Kyssarra"', 1, true))
			entry.about = true
			ns.MainWindow.Refresh()
			expect.equal(frame.trp3:GetText(), "Total RP 3 · sync on")
			expect.truthy(same(frame.trp3Dot.__color, ns.Style.Current().accent))
			ctx.trp3Deps = function() error("unavailable") end
			ns.MainWindow.Refresh()
			expect.equal(frame.trp3:GetText(), "Total RP 3 · sync off", "a failing read never breaks the rail")
		end)
	end)

	t:describe("v0.10 window chrome", function()
		t:it("draws the bottom-right ornament as the resize grip, brighter while hovered", function()
			local _, _, ns, frame = open()
			local L = ns.MainWindow.LAYOUT
			local grip = frame.resizeHandle
			expect.equal(grip:GetWidth(), L.grip)
			expect.deepEqual(lastPoint(grip), { "BOTTOMRIGHT", -L.gripInset, L.gripInset })
			expect.equal(#grip.legs, 4, "two Ls, as the top-left ornament")
			for _, leg in ipairs(grip.legs) do
				local p = lastPoint(leg)
				expect.equal(p[1], "BOTTOMRIGHT")
				expect.truthy(leg:GetWidth() <= L.grip and leg:GetHeight() <= L.grip, "inside the grip")
			end
			local theme = ns.Style.Current()
			expect.truthy(same(grip.legs[1].__color, theme.ornament))
			grip:GetScript("OnEnter")(grip)
			expect.truthy(same(grip.legs[1].__color, ns.Style.Tones(theme).accentBright))
			grip:GetScript("OnLeave")(grip)
			expect.equal(grip:GetNormalTexture().__alpha, 0, "the chat grabber art is not shown")
		end)

		t:it("sets the header eyebrow in tracked capitals inside the title column", function()
			local _, _, ns, frame = open()
			local r = ns.MainWindow.ComputeLayout(ns.MainWindow.LAYOUT)
			expect.equal(frame.eyebrow:GetText(), "JOURNAL")
			expect.equal(frame.eyebrow.boxWidth, r.eyebrow.right - r.eyebrow.left)
			expect.truthy(frame.eyebrow:GetStringWidth() <= frame.eyebrow.boxWidth)
		end)
	end)

	t:describe("v0.10 Journal (journal-dashboard.png)", function()
		local function turnIn(mock, id, title)
			mock.quest = { id = id, title = title, level = 20 }
			mock.Fire("QUEST_COMPLETE")
			mock.Fire("QUEST_TURNED_IN", id, 100, 10)
		end

		t:it("lays the toolbar out without overlap: New entry, search with its icon, the fitted filter track", function()
			local _, _, ns = open()
			local section = ns.JournalView.section
			local L = ns.JournalView.LAYOUT
			local W = ns.MainWindow.ContentWidth()
			local searchRight = L.newW + L.toolGap + L.searchW
			expect.truthy(searchRight + 20 <= W - L.trackW, "search and filter apart")
			expect.equal(section.filterTrack:GetWidth(), L.trackW)
			expect.equal(section.filterTrack:GetHeight(), L.toolbarH)
			expect.equal(section.search.icon.name, "search")
			expect.truthy(ns.Widgets.LabelFits("New entry", L.newW, 36, "primary", true))
			expect.truthy(L.newW <= 124, "about the design's 120")
		end)

		t:it("puts the star in the Defining chip and keeps event cards to title and meta", function()
			local mock, env, ns = open()
			local section = ns.JournalView.section
			local L = ns.JournalView.LAYOUT
			mock.Fire("PLAYER_LEVEL_UP", 7)
			mock.Slash("journal add A quiet evening")
			local c = env.DawnwardChroniclesDB.characters["Testchar-TestRealm"]
			ns.Actions.SetEntryImportant(ns.ctx, c.journal[#c.journal].id, true)
			ns.MainWindow.Refresh()
			local note, event
			for i = 1, section.visibleCount do
				local row = section.rows[i]
				if row.entry.kind == "event" then event = row else note = row end
			end
			expect.equal(note.chips[1].label:GetText(), "Defining")
			expect.equal(note.chips[1].icon.name, "star")
			expect.equal(note.mark.iconRole, "accentBright", "the star toggle is gold on a defining moment")
			-- The event card: no footer; its star sits on the meta line, clear of the text.
			expect.falsy(event.edit:IsShown())
			expect.falsy(event.chips[1].icon ~= nil and event.chips[1].icon:IsShown())
			local p = lastPoint(event.mark)
			expect.equal(p[1], "TOPRIGHT")
			expect.equal(p[4], -L.padX)
			local markTop = -p[5]
			expect.truthy(math.abs(markTop + ns.Style.CONTROL.compact / 2 - (event.metaTop + L.metaLine / 2)) <= 1,
				"centred on the meta line")
			expect.truthy(L.textX + event.meta:GetWidth() <= L.cardW - L.padX - event.mark:GetWidth(),
				"the meta line stops before the star")
			expect.truthy(markTop + event.mark:GetHeight() <= event:GetHeight(), "inside the card")
			expect.truthy(event:GetHeight() < note:GetHeight(), "shorter than a card with a footer")
		end)

		t:it("lays the editor out with 36 px controls and room for every error line", function()
			local _, _, ns = open()
			local section = ns.JournalView.section
			local E = ns.JournalView.EDITOR
			local H = ns.MainWindow.ContentHeight()
			click(section.newButton)
			local ed = section.editor
			expect.equal(ed.title:GetHeight(), 36)
			expect.equal(ed.save:GetHeight(), 36)
			expect.equal(ed.cancel:GetHeight(), 36)
			local titleError = E.titleTop + 36 + 3 + 17
			expect.truthy(titleError <= E.textLabelTop, "the title's error line clears the Entry label")
			local areaError = E.areaBottom - 3 - 17
			expect.truthy(areaError >= E.buttonsBottom + 36, "the text's error line clears the buttons")
			expect.truthy(H - E.areaTop - E.areaBottom >= 200, "a generous writing area")
			expect.truthy(ns.Widgets.LabelFits("Cancel", E.buttonW, 36, "ghost"))
		end)

		t:it("shows the callout's sparkle and an empty journal's book icon", function()
			local mock, _, ns = open()
			local section = ns.JournalView.section
			local L = ns.JournalView.LAYOUT
			expect.equal(section.emptyIcon.name, "journal")
			expect.equal(lastPoint(section.empty)[3], -L.emptyTextTop)
			expect.truthy(section.emptyCard:GetHeight() >= L.emptyTextTop + 60 + L.emptyPad)
			turnIn(mock, 10, "The Defias Brotherhood")
			ns.MainWindow.Refresh()
			expect.equal(section.callout.icon.name, "sparkle")
			expect.equal(section.callout.title:GetText():sub(1, 15), "A MOMENT AWAITS")
		end)

		t:it("pads the side panels 16 and keeps their titles clear of the All link", function()
			local _, _, ns = open()
			local section = ns.JournalView.section
			local L = ns.JournalView.LAYOUT
			expect.equal(section.goals.padX, 16)
			expect.equal(section.places.padX, 16)
			expect.equal(L.sideInner, 250 - 32)
			local title = section.goals.title
			expect.truthy(title:GetStringWidth() <= 250 - 32 - 40, "ACTIVE GOALS leaves room for All")
		end)
	end)
end
