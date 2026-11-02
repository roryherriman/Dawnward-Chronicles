-- L2: Settings -> Total RP 3 sync page, under the WoW mock and the TRP3
-- 3.4.1 fake (mocked client; not in-game evidence). The page must only read
-- on open, and every write must go through the guarded /dawnward trp3 path.
local Boot = require("support.boot")
local Fake = require("fakes.trp3_341")

local CHAR = "Testchar-TestRealm"

-- y offset of a widget's TOPLEFT point relative to its parent (negative down).
local function top(widget)
	for _, p in ipairs(widget.__points or {}) do
		if p[1] == "TOPLEFT" then
			return p[#p]
		end
	end
	return nil
end

local function click(button)
	button:GetScript("OnClick")(button)
end

local function start(fakeOpts)
	local fake = Fake.new(fakeOpts or {})
	local extra = {}
	for k, v in pairs(fake.env) do
		if k ~= "C_AddOns" then extra[k] = v end
	end
	local mock, env, ns = Boot.Load({ extra = extra })
	mock.env.C_AddOns.IsAddOnLoaded = fake.env.C_AddOns.IsAddOnLoaded
	local meta = mock.env.C_AddOns.GetAddOnMetadata
	mock.env.C_AddOns.GetAddOnMetadata = function(name, field)
		return fake.env.C_AddOns.GetAddOnMetadata(name, field) or meta(name, field)
	end
	Boot.Login(mock)
	ns.SetupWizard.SkipAutoLaunchThisSession(ns.ctx.characterKey)
	function mock.AcceptPopup()
		local d = ns.Widgets.dialog
		assert(d and d:IsShown(), "no confirmation dialog is open")
		d.accept:GetScript("OnClick")(d.accept)
	end
	return mock, env, ns, fake
end

local function publicFact(mock)
	mock.Slash("fact add origin Born in Stormwind")
	mock.Vis("fact vis 1 public")
end

local function open(ns)
	ns.SettingsPanel.OpenPage("trp3")
	return ns.SettingsPanel.panel.trp3Page
end

local function status(ns)
	return ns.MainWindow.GetFrame().status:GetText() or ""
end

return function(t, expect)
	t:describe("Total RP 3 page (L2)", function()
		t:it("OpenPage opens the window on Settings with that page selected", function()
			local _, _, ns = Boot.Start()
			expect.falsy(ns.SettingsPanel.OpenPage("nope"))
			expect.truthy(ns.SettingsPanel.OpenPage("trp3"))
			local panel = ns.SettingsPanel.panel
			expect.truthy(ns.MainWindow.IsShown())
			expect.equal(ns.MainWindow.CurrentSection(), "settings")
			expect.truthy(panel.pages.trp3:IsShown())
			expect.falsy(panel.pages.general:IsShown())
			expect.truthy(panel.nav.buttons[4].selected)
			expect.equal(ns.MainWindow.GetFrame().title:GetText(), "Total RP 3")
			-- Calling it again while open keeps Settings open (no toggle back).
			expect.truthy(ns.SettingsPanel.OpenPage("data"))
			expect.equal(ns.MainWindow.CurrentSection(), "settings")
			expect.truthy(panel.pages.data:IsShown())
		end)

		t:it("explains that Total RP 3 is optional when it is absent", function()
			local _, _, ns = Boot.Start()
			local page = open(ns)
			expect.truthy(page.absent:IsShown())
			expect.falsy(page.body:IsShown())
			expect.truthy(page.absentText:GetText():find("optional", 1, true))
			expect.truthy(page.absentText:GetText():find("Dawnward works fully without it", 1, true))
			expect.truthy(page.absentStatus:GetText():find("not installed", 1, true))
			expect.equal(page.columns[1]:GetText(), "Not installed · optional")
			expect.falsy(page.conflict:IsShown())
			expect.truthy(page.experimental:IsShown())
		end)

		t:it("shows version support, the linked profile and per-feature sync state", function()
			local mock, _, ns = start({ profileName = "Aelin (RP)" })
			publicFact(mock)
			local page = open(ns)
			expect.truthy(page.body:IsShown())
			-- Nothing set up yet: the page opens on the first-connection Mappings tab (v0.8).
			expect.equal(page.feature, "mappings")
			expect.truthy(page.map:IsShown())
			click(page.nav.buttons[2])
			expect.falsy(page.map:IsShown())
			expect.equal(page.columns[1]:GetText(), "Installed · 3.4.1 · supported")
			expect.truthy(page.columns[2]:GetText():find("not linked", 1, true))
			expect.equal(page.columns[3]:GetText(), "Off for Biography and Traits")
			expect.equal(page.chip.label:GetText(), "Sync off")
			expect.truthy(page.unsupported:GetText():find("name, pronouns and the other fields never", 1, true))
			mock.Slash("trp3 enable about confirm")
			ns.MainWindow.Refresh()
			expect.truthy(page.columns[2]:GetText():find("\"Aelin (RP)\" · this character only", 1, true))
			expect.equal(page.columns[3]:GetText(), "On for Biography · off for Traits")
			expect.equal(page.chip.label:GetText(), "Needs your approval")
			expect.truthy(page.reasons:GetText():find("Proposed change: insert", 1, true))
			click(page.nav.buttons[3])
			expect.equal(page.title:GetText(), "Traits: sync is off")
		end)

		t:it("writes nothing to Total RP 3 when the page is opened, refreshed or previewed", function()
			local mock, env, ns, fake = start()
			publicFact(mock)
			mock.Slash("trp3 enable about confirm")
			mock.Slash("personality set courage 14")
			mock.Vis("personality vis courage public")
			mock.timers = {}
			local before = fake.snapshot()
			local events = #fake.events
			local page = open(ns)
			ns.MainWindow.Refresh()
			click(page.nav.buttons[3])
			click(page.nav.buttons[2])
			click(page.notNow)
			expect.deepEqual(fake.snapshot(), before)
			expect.equal(#fake.events, events)
			expect.equal(#env.DawnwardChroniclesTRP3DB.backups, 0)
			expect.equal(#mock.timers, 0, "opening the page requests no automatic run")
			expect.equal(#fake.setterCalls, 0)
			expect.truthy(page.previewText:GetText():find("Origin: Born in Stormwind", 1, true))
		end)

		t:it("approve needs the opt-in, asks before turning sync on, then runs the guarded write", function()
			local mock, env, ns, fake = start()
			publicFact(mock)
			local page = open(ns)
			click(page.nav.buttons[2])
			expect.falsy(page.approve:IsEnabled())
			click(page.approve) -- even if forced, nothing is written without the opt-in
			expect.equal(fake.profile.player.about.T1.TX, "Private about text")
			expect.truthy(status(ns):find("sync is off", 1, true))

			click(page.toggle)
			expect.truthy(ns.Widgets.dialog:IsShown())
			expect.truthy(ns.Widgets.dialog.text:GetText():find("EXPERIMENTAL", 1, true))
			expect.equal(env.DawnwardChroniclesTRP3DB.optIn[CHAR], nil, "not on before confirming")
			mock.AcceptPopup()
			expect.truthy(env.DawnwardChroniclesTRP3DB.optIn[CHAR].about)
			mock.timers = {}
			expect.truthy(page.approve:IsEnabled())
			click(page.approve)
			expect.truthy(fake.profile.player.about.T1.TX:find("Origin: Born in Stormwind", 1, true))
			expect.truthy(fake.profile.player.about.T1.TX:find("^Private about text"))
			expect.equal(#env.DawnwardChroniclesTRP3DB.backups, 1, "backup taken before the write")
			expect.truthy(status(ns):find("Updated your Total RP 3 biography", 1, true))
			expect.equal(page.chip.label:GetText(), "Up to date")
			expect.truthy(page.keepText:GetText():find("Private about text", 1, true))
			expect.equal(page.toggle:GetText(), "Stop syncing biography")
			click(page.toggle)
			expect.falsy(env.DawnwardChroniclesTRP3DB.optIn[CHAR].about)
		end)

		t:it("keeps every guard: combat and an open editor hold the write back", function()
			local mock, env, ns, fake = start()
			publicFact(mock)
			mock.Slash("trp3 enable about confirm")
			mock.timers = {}
			mock.inCombat = true
			local page = open(ns)
			expect.equal(page.chip.label:GetText(), "Waiting")
			expect.truthy(page.reasons:GetText():find("in combat", 1, true))
			expect.falsy(page.approve:IsEnabled())
			click(page.approve)
			expect.equal(fake.profile.player.about.T1.TX, "Private about text")
			mock.inCombat = false
			fake.openEditor("about")
			ns.MainWindow.Refresh()
			click(page.approve)
			expect.equal(fake.profile.player.about.T1.TX, "Private about text")
			expect.equal(#env.DawnwardChroniclesTRP3DB.backups, 0)
		end)

		t:it("a conflict blocks approve until the player keeps theirs or lets Dawnward reclaim", function()
			local mock, env, ns, fake = start()
			publicFact(mock)
			mock.Slash("trp3 enable about confirm")
			mock.RunTimers()
			fake.profile.player.about.T1.TX = "Rewritten by the player"
			mock.Slash("fact add belief Protect the weak")
			mock.Vis("fact vis 2 public")
			mock.timers = {}
			local page = open(ns)
			expect.equal(page.chip.label:GetText(), "Conflict")
			expect.truthy(page.conflict:IsShown())
			expect.equal(page.conflict.title:GetText(), "CONFLICT ON BIOGRAPHY")
			expect.truthy(page.conflictText:GetText():find("Nothing will be overwritten", 1, true))
			expect.falsy(page.approve:IsEnabled())
			click(page.approve)
			expect.equal(fake.profile.player.about.T1.TX, "Rewritten by the player")
			click(page.keepYours)
			expect.equal(fake.profile.player.about.T1.TX, "Rewritten by the player")
			expect.falsy(env.DawnwardChroniclesTRP3DB.optIn[CHAR].about, "keep switches sync off")
			expect.falsy(page.conflict:IsShown())
			expect.truthy(status(ns):find("Kept your version", 1, true))
		end)

		t:it("rolls back only after confirmation", function()
			local mock, env, ns, fake = start()
			publicFact(mock)
			mock.Slash("trp3 enable about confirm")
			mock.RunTimers()
			local written = fake.profile.player.about.T1.TX
			expect.truthy(written:find("Chronicle", 1, true))
			local page = open(ns)
			expect.truthy(page.backupRows[1]:IsShown())
			expect.truthy(page.backupRows[1].name:GetText():find("#1 About", 1, true))
			-- v0.8 (the design's backup list): one row, the short date at the right in its own column, so the
			-- name and the date never crowd each other; the full date is the row's tooltip.
			local backupRow = page.backupRows[1]
			expect.truthy(backupRow.date:GetText():find("^%d+ %a%a%a$"), backupRow.date:GetText())
			expect.equal(backupRow.date.__points[1][1], "RIGHT")
			expect.truthy(8 + backupRow.name:GetWidth() + 8 + backupRow.date:GetWidth() + 8 <= backupRow:GetWidth(),
				"name and date columns do not overlap")
			expect.truthy(backupRow.tooltipText:find("%d%d%d%d, %d%d:%d%d"), "the full date on hover")
			expect.truthy(page.rollback:IsEnabled())
			click(page.backupRows[1])
			-- v0.8: the exact restore is a separate button that names the risk;
			-- Roll back… is the safe restore (see the visibility-aware test).
			click(page.exact)
			expect.truthy(ns.Widgets.dialog:IsShown())
			expect.truthy(ns.Widgets.dialog.text:GetText():find("#1", 1, true))
			expect.truthy(ns.Widgets.dialog.text:GetText():find("since made Private or Secret", 1, true),
				"the player is warned that a restore brings back what was public then")
			expect.equal(fake.profile.player.about.T1.TX, written, "nothing restored before confirming")
			click(ns.Widgets.dialog.cancel)
			expect.equal(fake.profile.player.about.T1.TX, written)
			click(page.exact)
			mock.AcceptPopup()
			expect.equal(fake.profile.player.about.T1.TX, "Private about text")
			expect.truthy(status(ns):find("Restored", 1, true))
			expect.equal(#env.DawnwardChroniclesTRP3DB.backups, 2, "the state before the rollback is kept")
		end)

		t:it("never shows Private or Secret content in the preview, only counts", function()
			local mock, _, ns = start()
			publicFact(mock)
			mock.Slash("fact add belief Hidden lover in Duskwood")
			mock.Slash("fact add origin Secret heir of Alterac")
			mock.Vis("fact vis 3 secret")
			mock.Slash("personality set faith 3")
			mock.Slash("personality set courage 15")
			mock.Vis("personality vis courage public")
			local page = open(ns)
			local texts = function()
				local all = {}
				for _, fs in ipairs({ page.title, page.explain, page.reasons, page.keepText, page.previewText,
					page.hiddenText, page.unsupported, page.conflictText }) do
					all[#all + 1] = fs:GetText() or ""
				end
				for _, row in ipairs(page.overviewRows) do
					all[#all + 1] = (row.name:GetText() or "") .. " " .. (row.value:GetText() or "")
				end
				for _, fs in ipairs({}) do
					all[#all + 1] = fs:GetText() or ""
				end
				return table.concat(all, "\n")
			end
			for _, feature in ipairs({ 1, 2, 3 }) do
				click(page.nav.buttons[feature])
				local shown = texts()
				expect.falsy(shown:find("Duskwood", 1, true), "private fact leaked")
				expect.falsy(shown:find("Alterac", 1, true), "secret fact leaked")
				expect.falsy(shown:find("Sceptical", 1, true) or shown:find("Devout", 1, true), "private axis leaked")
			end
			click(page.nav.buttons[2])
			expect.truthy(page.previewText:GetText():find("Born in Stormwind", 1, true))
			expect.truthy(page.hiddenText:GetText():find("1 fact and 1 personality axis are Private", 1, true),
				page.hiddenText:GetText())
			expect.truthy(page.hiddenText:GetText():find("1 fact is Secret", 1, true))
			click(page.nav.buttons[3])
			expect.truthy(page.previewText:GetText():find(" 5 / 15 ", 1, true), page.previewText:GetText())
		end)

		t:it("fits the strip, the feature card and the right column inside the settings page", function()
			local _, _, ns = start()
			local page = open(ns)
			local L = ns.MainWindow.LAYOUT
			local pageHeight = L.height - L.contentTop - L.contentBottom - ns.SettingsPanel.LAYOUT.pageTop
			local cardH = page.card:GetHeight()
			expect.equal(-top(page.card) + cardH, pageHeight, "card ends at the bottom of the page")
			for _, w in ipairs({ page.keep, page.preview, page.hidden }) do
				expect.truthy(-top(w) + w:GetHeight() <= cardH - 46, "above the button row")
			end
			expect.truthy(page.conflict:GetHeight() + ns.TRP3Page.GAP + page.backups:GetHeight() <= cardH)
			expect.equal(page.card:GetWidth() + ns.TRP3Page.COLUMN_GAP + ns.TRP3Page.RIGHT_WIDTH,
				ns.MainWindow.ContentWidth(), "the two columns fill the content width")
			expect.truthy(page.approve:GetWidth() + page.notNow:GetWidth() + page.toggle:GetWidth() + 8 + 28
				< page.card:GetWidth(), "the three actions do not overlap")
			-- Mappings: every row and the note stay above the Authorize row.
			local last = page.mapRows[#page.mapRows]
			expect.truthy(-top(last) + last:GetHeight() + 4 + ns.TRP3Page.LINE <= cardH - 14 - page.authorize:GetHeight(),
				"rows and the one-line note stay above the Authorize row")
			local r = page.mapRows[1]
			expect.truthy(r.name:GetWidth() + ns.TRP3Page.IMPORT_WIDTH + ns.TRP3Page.SELECTOR_WIDTH + 12
				<= r:GetWidth(), "row text, Import and the selector do not overlap")
			expect.truthy(page.authorize:GetWidth() + page.resetChoices:GetWidth() + 8 + 28 < page.card:GetWidth())
		end)

		t:it("v0.8 layout: every Mappings selector item fits \"Dawnward\", and the right column's labels fit", function()
			local _, _, ns = start()
			local page = open(ns)
			for _, r in ipairs(page.mapRows) do
				for _, b in ipairs(r.selector.buttons) do
					expect.truthy(ns.Widgets.LabelFits(b:GetText(), b:GetWidth(), b:GetHeight(), "segment"),
						r.id .. ": " .. b:GetText() .. " in " .. b:GetWidth())
					expect.truthy(b:GetWidth() >= 74, "the shell pass measured ~74 px for Dawnward")
				end
				if r.import then
					expect.truthy(ns.Widgets.LabelFits("Import", r.import:GetWidth(), r.import:GetHeight()))
				end
				expect.equal(r.detail:GetWidth(), r:GetWidth(), "the detail line runs the full row width")
			end
			for _, b in ipairs({ page.keepYours, page.reclaim, page.rollback, page.exact, page.copy, page.approve,
				page.notNow, page.authorize, page.resetChoices }) do
				expect.truthy(ns.Widgets.LabelFits(b:GetText(), b:GetWidth(), b:GetHeight()), b:GetText())
			end
			for _, text in ipairs({ "Stop syncing biography", "Enable syncing biography…", "Enable syncing traits…" }) do
				expect.truthy(ns.Widgets.LabelFits(text, page.toggle:GetWidth(), page.toggle:GetHeight()), text)
			end
			expect.equal(page.approve:GetHeight(), ns.Style.CONTROL.standard)
		end)

		t:it("v0.8 layout: the strip's columns hold the design's values, and the chips do not crowd the title", function()
			local _, _, ns = start()
			local page = open(ns)
			local values = { "Installed · 3.4.1 · supported", "\"Kyssarra (RP)\" · this character only",
				"On for Biography · off for Traits" }
			for i, v in ipairs(values) do
				expect.truthy(ns.Style.TextWidth(v, "body") <= page.columns[i]:GetWidth(), v)
			end
			local W = page.columnWidths
			expect.truthy(16 + W[1] + W[2] + W[3] + 12 + page.experimental:GetWidth() + 16 <= page.width)
			-- The nav and the state chip share the top row of the card.
			expect.truthy(18 + 3 * 92 + 12 + ns.Style.TextWidth("Needs your approval", "small") + 20
				<= page.leftWidth - 18)
			expect.equal(ns.TRP3Page.STATE_CHIP.ready[2], "waiting", "needs-you chips are amber, as the design")
		end)

		t:it("v0.8 layout: the Biography boxes stack without overlapping, above the action row", function()
			local _, _, ns = start()
			local page = open(ns)
			local boxes = { page.keep, page.preview, page.hidden }
			for i = 2, #boxes do
				expect.truthy(-top(boxes[i]) >= -top(boxes[i - 1]) + boxes[i - 1]:GetHeight() + 4, "gap between boxes")
			end
			local actionTop = page.mainHeight - 14 - ns.TRP3Page.ACTION_HEIGHT
			expect.truthy(-top(page.hidden) + page.hidden:GetHeight() + 6 <= actionTop - 8, "above the rule")
			expect.truthy(28 + ns.TRP3Page.PREVIEW_LINES * 16 + 8 <= page.preview:GetHeight(), "preview lines fit")
			-- The two never-shared paragraphs fit their two lines each.
			local w = page.innerWidth - 20
			expect.truthy(ns.Style.TextWidth(ns.TRP3Page.UNSUPPORTED_TEXT, "meta") <= 2 * w)
			expect.truthy(ns.Style.TextWidth(ns.TRP3Page.EXPLAIN.about, "meta") <= 2 * page.innerWidth)
			expect.truthy(ns.Style.TextWidth(ns.TRP3Page.EXPLAIN.traits, "meta") <= 2 * page.innerWidth)
			expect.truthy(ns.Style.TextWidth(ns.TRP3Page.MAPPINGS_EXPLAIN, "meta") <= 2 * page.innerWidth)
			-- Right column: the callout and the backups stay inside the page.
			expect.truthy(page.conflict:GetHeight() + ns.TRP3Page.GAP + page.backups:GetHeight() <= page.mainHeight)
		end)

		t:it("v0.8 look: the preview box uses the Public chip's colours, and the plain boxes the input well", function()
			local _, _, ns = start()
			local page = open(ns)
			local theme = ns.Style.Current()
			local fill, edge = ns.Widgets.ChipColors(ns.Themes.VISIBILITY_COLORS.public, theme, theme.surface)
			expect.equal(page.preview.bg.__color[1], fill[1])
			expect.equal(page.preview.edges.top.__color[2], edge[2])
			expect.equal(page.keep.bg.__color[1], ns.Style.Tones(theme).field[1])
			expect.equal(page.hidden.bg.__color[3], ns.Style.Tones(theme).field[3])
		end)

		t:it("the chat commands still behave as before after the refactor", function()
			local mock, _, _, fake = start()
			publicFact(mock)
			expect.truthy(mock.Slash("trp3 enable about"):find("Type: /dawnward trp3 enable about confirm", 1, true))
			mock.Slash("trp3 enable about confirm")
			local out = mock.Slash("trp3 sync")
			expect.truthy(out:find("Updated your Total RP 3 biography", 1, true))
			expect.truthy(mock.Slash("trp3 sync"):find("already up to date (nothing written)", 1, true))
			expect.truthy(mock.Slash("trp3 backups"):find("  #1 about, profile " .. fake.profileId, 1, true))
			local rollback = mock.Slash("trp3 rollback")
			expect.truthy(rollback:find("newest backup (see /dawnward trp3 backups). Privacy:", 1, true))
			expect.truthy(rollback:find("Type: /dawnward trp3 rollback [#] confirm", 1, true))
			expect.truthy(rollback:find("/dawnward trp3 rollback [#] exact confirm", 1, true))
		end)
	end)

	t:describe("Total RP 3 page: Mappings and first connection (L2)", function()
		local function row(page, id)
			for _, r in ipairs(page.mapRows) do
				if r.id == id then return r end
			end
		end
		local function choose(r, policy)
			for _, b in ipairs(r.selector.buttons) do
				if b.segmentId == policy then click(b) end
			end
		end

		t:it("lists every mapping, stages choices without saving, and writes only after Authorize", function()
			local mock, env, ns, fake = start()
			mock.Slash("set race Elf")
			mock.Vis("vis race public")
			mock.timers = {}
			local page = open(ns)
			expect.equal(page.feature, "mappings")
			expect.equal(#page.mapRows, #ns.TRP3Ledger.MAPPINGS, "every mapping has a row (v0.9: 19)")
			expect.equal(#page.mapRows, 19)
			expect.truthy(page.mapPages > 1, "paged: more than fit at once")
			expect.truthy(page.mapRows[1]:IsShown())
			expect.falsy(page.mapRows[#page.mapRows]:IsShown(), "later rows are on a later page")
			click(page.mapNext)
			expect.truthy(page.mapRows[#page.mapRows]:IsShown() or page.mapPages > 2)
			click(page.mapPrev)
			expect.truthy(page.unsupportedNote:GetText():find("Currently", 1, true), page.unsupportedNote:GetText())
			expect.truthy(page.sharedWarn:GetText():find("this character only", 1, true))
			expect.equal(row(page, "race").selector.selected, "trp3", "a field starts managed by Total RP 3")
			expect.equal(row(page, "about").selector.selected, "off")
			expect.falsy(page.authorize:IsEnabled())
			choose(row(page, "race"), "dawnward")
			expect.equal(env.DawnwardChroniclesTRP3DB.optIn[CHAR], nil, "staged only")
			expect.truthy(row(page, "race").detail:GetText():find("writes \"Elf\"", 1, true))
			expect.truthy(page.authorize:IsEnabled())
			click(page.authorize)
			local text = ns.Widgets.dialog.text:GetText()
			expect.truthy(text:find("+ Race: managed by Dawnward - writes \"Elf\"", 1, true), text)
			expect.truthy(text:find("EXPERIMENTAL", 1, true))
			click(ns.Widgets.dialog.cancel)
			expect.equal(env.DawnwardChroniclesTRP3DB.optIn[CHAR], nil, "cancel saves nothing")
			expect.equal(fake.profile.player.characteristics.RA, nil)
			click(page.authorize)
			mock.AcceptPopup()
			expect.equal(ns.TRP3Ledger.Policy(env.DawnwardChroniclesTRP3DB.optIn[CHAR], "race"), "dawnward")
			expect.falsy(page.authorize:IsEnabled(), "nothing left staged")
			expect.equal(fake.profile.player.characteristics.RA, nil, "the write comes from the guarded run")
			mock.RunTimers()
			expect.equal(fake.profile.player.characteristics.RA, "Elf")
			ns.MainWindow.Refresh()
			expect.truthy(row(page, "race").detail:GetText():find("TRP3: \"Elf\"", 1, true))
		end)

		t:it("never shows a Private or Secret Dawnward value on the Mappings tab or in its confirmation", function()
			local mock, _, ns = start({ characteristics = { v = 3, FN = "Aelin", RA = "Human", PS = {} } })
			mock.Slash("set race SECRETRACE")
			mock.Vis("vis race secret")
			mock.Slash("set age PRIVATEAGE")
			local page = open(ns)
			choose(row(page, "race"), "dawnward")
			choose(row(page, "age"), "dawnward")
			local shown = {}
			for _, r in ipairs(page.mapRows) do
				shown[#shown + 1] = r.name:GetText() .. " " .. r.detail:GetText()
			end
			click(page.authorize)
			shown[#shown + 1] = ns.Widgets.dialog.text:GetText()
			local all = table.concat(shown, "\n")
			expect.falsy(all:find("SECRETRACE", 1, true))
			expect.falsy(all:find("PRIVATEAGE", 1, true))
			expect.truthy(all:find("nothing Public to write", 1, true))
		end)

		t:it("warns when the profile is shared with other characters", function()
			local mock, _, ns = start({ characters = { [CHAR] = { profileID = "1700000000ABCDE" },
				["Alt-TestRealm"] = { profileID = "1700000000ABCDE" } } })
			mock.timers = {}
			local page = open(ns)
			expect.truthy(page.sharedWarn:GetText():find("shared with 1 other character", 1, true))
			choose(row(page, "age"), "dawnward")
			click(page.authorize)
			expect.truthy(ns.Widgets.dialog.text:GetText():find("shared with 1 other character", 1, true))
		end)

		t:it("imports a Total RP 3 value only after confirmation, as Private", function()
			local mock, _, ns, fake = start({ characteristics = { v = 3, FN = "Aelin", CL = "Lightbringer", PS = {} } })
			local page = open(ns)
			local before = fake.snapshot()
			local r = row(page, "class")
			expect.truthy(r.import:IsEnabled())
			expect.falsy(row(page, "age").import:IsEnabled(), "nothing to import")
			click(r.import)
			expect.equal(ns.store.real.characters[CHAR], nil, "nothing imported before confirming")
			mock.AcceptPopup()
			expect.deepEqual(ns.store.real.characters[CHAR].fields.class, { value = "Lightbringer", visibility = "private" })
			expect.deepEqual(fake.snapshot(), before)
			expect.falsy(row(page, "class").import:IsEnabled(), "same value now")
		end)

		t:it("a field conflict shows the callout, and Keep yours hands the field to Total RP 3", function()
			local mock, env, ns, fake = start({ characteristics = { v = 3, FN = "Aelin", AG = "40", PS = {} } })
			mock.Slash("set age 31")
			mock.Vis("vis age public")
			mock.Slash("trp3 field age dawnward confirm")
			mock.RunTimers()
			local page = open(ns)
			expect.truthy(page.conflict:IsShown())
			expect.equal(page.conflict.title:GetText(), "CONFLICT ON AGE")
			click(page.keepYours)
			expect.equal(fake.profile.player.characteristics.AG, "40")
			expect.equal(ns.TRP3Ledger.Policy(env.DawnwardChroniclesTRP3DB.optIn[CHAR], "age"), "trp3")
			expect.falsy(page.conflict:IsShown())
		end)

		t:it("handing back a field that still shows a no-longer-Public value says it will be removed first", function()
			local mock, env, ns, fake = start()
			mock.Slash("set age 31")
			mock.Vis("vis age public")
			mock.Slash("trp3 field age dawnward confirm")
			mock.RunTimers()
			mock.Vis("vis age private")
			mock.timers = {}
			local page = open(ns)
			click(page.nav.buttons[4])
			choose(row(page, "age"), "trp3")
			expect.truthy(row(page, "age").detail:GetText():find("will be removed from TRP3 first", 1, true))
			click(page.authorize)
			local text = ns.Widgets.dialog.text:GetText()
			expect.truthy(text:find("It will be removed from Total RP 3 first", 1, true), text)
			expect.equal(fake.profile.player.characteristics.AG, "31")
			mock.AcceptPopup()
			expect.equal(fake.profile.player.characteristics.AG, nil)
			expect.equal(ns.TRP3Ledger.Policy(env.DawnwardChroniclesTRP3DB.optIn[CHAR], "age"), "trp3")
		end)

		t:it("shows conflicts only for fields Dawnward manages", function()
			local mock, env, ns = start({ characteristics = { v = 3, FN = "Aelin", AG = "40", PS = {} } })
			mock.Slash("set age 31")
			mock.Vis("vis age public")
			mock.Slash("trp3 field age dawnward confirm")
			mock.RunTimers()
			-- A stale conflict left for a field that is no longer managed (older data).
			local db = env.DawnwardChroniclesTRP3DB
			ns.TRP3Ledger.SetPolicy(db.optIn[CHAR], "age", "trp3")
			expect.truthy(db.profiles["1700000000ABCDE"].fieldConflicts.age)
			local page = open(ns)
			expect.falsy(page.conflict:IsShown())
		end)

		t:it("the exact restore names what is no longer Public; Roll back… keeps it hidden", function()
			local mock, _, ns, fake = start()
			mock.Slash("fact add origin Born in Stormwind")
			mock.Vis("fact vis 1 public")
			mock.Slash("fact add belief Loves the Duke")
			mock.Vis("fact vis 2 public")
			mock.Slash("trp3 enable about confirm")
			mock.RunTimers()
			mock.Slash("fact add event Saved a village")
			mock.Vis("fact vis 3 public")
			mock.RunTimers()
			mock.Vis("fact vis 2 secret")
			mock.RunTimers()
			local page = open(ns)
			click(page.backupRows[1]) -- newest: holds the Duke line
			click(page.exact)
			local text = ns.Widgets.dialog.text:GetText()
			expect.truthy(text:find("Loves the Duke", 1, true), text)
			expect.equal(ns.Widgets.dialog.accept:GetText(), "Restore, including these")
			click(ns.Widgets.dialog.cancel)
			click(page.backupRows[1])
			click(page.rollback)
			expect.falsy(ns.Widgets.dialog.text:GetText():find("Loves the Duke", 1, true))
			mock.AcceptPopup()
			local about = fake.profile.player.about.T1.TX
			expect.falsy(about:find("Duke", 1, true))
			expect.truthy(about:find("Saved a village", 1, true))
		end)
	end)

	t:describe("window edits and Total RP 3", function()
		t:it("a change made in the window asks an opted-in sync to catch up, like a slash command", function()
			local mock, _, ns = Boot.Start()
			mock.Slash("set name Aelin")
			local requests = 0
			ns.ctx.trp3RequestSync = function() requests = requests + 1 end
			assert(ns.Actions.SetField(ns.ctx, "name", "Aelin Dawn"))
			expect.equal(requests, 1)
			ns.Actions.SetField(ns.ctx, "nonsense", "x")
			expect.equal(requests, 1, "a refused change asks for nothing")
		end)
	end)
end
