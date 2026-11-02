-- L2 (v0.10.1): the Total RP 3 profile editor's sections (UI/TRP3Page.lua,
-- UI/TRP3MiscSections.lua) under the WoW mock and the TRP3 3.4.1 fake
-- (mocked client; not in-game evidence): At First Glance, Status and OOC
-- (Currently, OOC, roleplay status, walk-up, roleplay style), the profile
-- icon and colour, Synchronization's switch, and the layout at window
-- scale 0.7 and 1.4. Every save goes through Actions and every write
-- through the guarded sync.
local Boot = require("support.boot")
local Fake = require("fakes.trp3_341")

local CHAR = "Testchar-TestRealm"

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
		local text = d.text:GetText()
		d.accept:GetScript("OnClick")(d.accept)
		return text
	end
	ns.SettingsPanel.OpenPage("trp3")
	local page = ns.SettingsPanel.panel.trp3Page
	return mock, env, ns, fake, page
end

local function status(ns)
	return ns.MainWindow.GetFrame().status:GetText() or ""
end

local function choose(seg, id)
	for _, b in ipairs(seg.buttons) do
		if b.segmentId == id then click(b) end
	end
end

-- A widget's rectangle from its TOPLEFT point (x, y offsets) and size.
local function rect(widget)
	for _, p in ipairs(widget.__points or {}) do
		if p[1] == "TOPLEFT" and type(p[#p]) == "number" then
			return p[#p - 1], -p[#p], widget:GetWidth(), widget:GetHeight()
		end
	end
	return nil
end

return function(t, expect)
	t:describe("Total RP 3 profile editor: Status and OOC (L2)", function()
		t:it("saves Currently in Dawnward, and Total RP 3 follows only once kept in sync", function()
			local mock, env, ns, fake, page = start()
			fake.profile.player.character.CU = nil
			ns.TRP3Page.Open(page, "status")
			expect.equal(page.title:GetText(), "Status and OOC")
			expect.falsy(page.explain:IsShown(), "the switch takes the explanation's place")
			expect.truthy(page.statusNav.buttons[1]:IsShown())
			local b = page.statusText.currently
			b.edit:SetText("Mending nets by the dock.")
			click(b.save)
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			expect.equal(char.trp3status.currently, "Mending nets by the dock.")
			mock.RunTimers()
			expect.equal(fake.profile.player.character.CU, nil, "not kept in sync: nothing written")
			choose(b.sync, "dawnward")
			local asked = mock.AcceptPopup()
			expect.truthy(asked:find("never over a value you set in Total RP 3", 1, true), asked)
			mock.RunTimers()
			expect.equal(fake.profile.player.character.CU, "Mending nets by the dock.")
			expect.equal(fake.setterLog[#fake.setterLog].name, "SetCurrentlyText")
			ns.MainWindow.Refresh()
			expect.truthy(b.detail:GetText():find("kept up to date by Dawnward", 1, true), b.detail:GetText())
			expect.equal(b.sync.selected, "dawnward")
			expect.truthy(b.count:GetText():find("25 / 140", 1, true))
			-- Clear empties Total RP 3's copy on the next sync.
			click(b.clear)
			mock.RunTimers()
			expect.equal(fake.profile.player.character.CU, "")
		end)

		t:it("Suggest only fills the editor; nothing is saved until Save", function()
			local mock, env, ns, _, page = start()
			mock.zone = "Elwynn Forest"
			ns.TRP3Page.Open(page, "status")
			local before = ns.Util.DeepCopy(env.DawnwardChroniclesDB.characters[CHAR] or {})
			click(page.statusText.currently.suggest)
			expect.equal(page.statusText.currently.edit:GetText(), "In Elwynn Forest.")
			expect.truthy(status(ns):find("nothing is saved until you press Save", 1, true))
			expect.deepEqual(env.DawnwardChroniclesDB.characters[CHAR] or {}, before, "nothing saved")
			ns.MainWindow.Refresh()
			expect.equal(page.statusText.currently.edit:GetText(), "In Elwynn Forest.", "a refresh keeps the draft")
		end)

		t:it("imports an existing Total RP 3 OOC note only after confirmation", function()
			local mock, env, ns, fake, page = start()
			fake.profile.player.character.CO = "Ask me about the guild."
			ns.TRP3Page.Open(page, "status")
			local b = page.statusText.ooc
			expect.truthy(b.import:IsEnabled())
			expect.truthy(b.detail:GetText():find("Ask me about the guild.", 1, true))
			click(b.import)
			mock.AcceptPopup()
			expect.equal(env.DawnwardChroniclesDB.characters[CHAR].trp3status.ooc, "Ask me about the guild.")
			expect.equal(b.edit:GetText(), "Ask me about the guild.")
			expect.equal(#fake.setterLog, 0, "nothing written to Total RP 3")
		end)

		t:it("roleplay status and walk-up are set by the player, separate from Currently", function()
			local mock, env, ns, fake, page = start()
			ns.TRP3Page.Open(page, "status")
			click(page.statusNav.buttons[2])
			expect.truthy(page.statusSub.style:IsShown())
			expect.falsy(page.statusSub.text:IsShown())
			local r = page.statusChoice.rpStatus
			expect.equal(r.seg.selected, 1, "shows Total RP 3's in character")
			expect.truthy(r.detail:GetText():find("not set in Dawnward", 1, true))
			choose(r.seg, 2)
			expect.equal(env.DawnwardChroniclesDB.characters[CHAR].trp3status.rpStatus, 2)
			expect.equal(env.DawnwardChroniclesDB.characters[CHAR].trp3status.currently, nil, "Currently untouched")
			mock.RunTimers()
			expect.equal(fake.profile.player.character.RP, 1, "not in sync: Total RP 3 keeps its own")
		end)

		t:it("roleplay style: read only until the player hands a preference over", function()
			local mock, env, ns, fake, page = start({ misc = { v = 1, PE = {}, ST = { ["4"] = 2 } } })
			ns.TRP3Page.Open(page, "status")
			click(page.statusNav.buttons[2])
			local romance = page.styleRows[3]
			expect.equal(romance.value:GetText(), "No", "Total RP 3's value, its own label")
			expect.equal(page.styleRows[1].value:GetText(), "Do not show", "unset reads as Do not show")
			for _, r in ipairs(page.styleRows) do
				expect.falsy(r.value:IsEnabled(), "read only by default")
				expect.equal(r.manage.selected, "trp3")
			end
			local injury = page.styleRows[1]
			choose(injury.manage, "dawnward")
			local asked = mock.AcceptPopup()
			expect.truthy(asked:find("EXPERIMENTAL", 1, true))
			ns.MainWindow.Refresh()
			expect.truthy(injury.value:IsEnabled())
			click(injury.value) -- Do not show -> No
			click(injury.value) -- No -> With player permission
			expect.equal(env.DawnwardChroniclesDB.characters[CHAR].trp3status.style["2"], 3)
			mock.RunTimers()
			expect.equal(fake.profile.player.misc.ST["2"], 3)
			expect.equal(fake.profile.player.misc.ST["4"], 2, "the other preferences are untouched")
			expect.equal(injury.value:GetText(), "With player permission")
		end)

		t:it("Open in Total RP 3 opens the player's page, never over an unsaved draft", function()
			local _, _, ns, fake, page = start()
			ns.TRP3Page.Open(page, "status")
			click(page.statusNav.buttons[2])
			fake.openEditor("about")
			fake.opened = {}
			click(page.openTRP3)
			expect.equal(#fake.opened, 0, "a draft would be lost: refused")
			expect.truthy(status(ns):find("unsaved changes", 1, true))
			fake.saveEditor("about")
			click(page.openTRP3)
			expect.deepEqual(fake.opened, { "openMainFrame", "main_12_player_character" })
			expect.equal(fake.nav.pageId, "player_main")
		end)
	end)

	t:describe("Total RP 3 profile editor: At First Glance and the profile look (L2)", function()
		t:it("writes an entry with an icon from the picker, moves it, hides it and removes it", function()
			local mock, env, ns, fake, page = start()
			ns.TRP3Page.Open(page, "glance")
			expect.equal(page.title:GetText(), "At First Glance")
			click(page.glanceRows[2])
			page.glanceTitle:SetText("Scarred hands")
			page.glanceText:SetText("Old burns across both palms.")
			click(page.glanceChoose)
			expect.truthy(page.iconPicker:IsShown())
			click(page.iconPicker.cells[2])
			expect.falsy(page.iconPicker:IsShown())
			expect.equal(page.glanceIconEdit:GetText(), ns.Glance.ICON_CHOICES[2])
			click(page.glanceSave)
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			expect.deepEqual(char.glance[2], { title = "Scarred hands", text = "Old burns across both palms.",
				icon = ns.Glance.ICON_CHOICES[2], active = true })
			expect.equal(page.glanceRows[2].title:GetText(), "Scarred hands")
			click(page.glanceUp)
			expect.truthy(char.glance[1] and not char.glance[2], "moved to first")
			expect.equal(page.glanceSel, 1)
			-- Sync on: written to Total RP 3 after the confirmation.
			choose(page.glanceSync, "dawnward")
			mock.AcceptPopup()
			mock.RunTimers()
			expect.equal(fake.profile.player.misc.PE["1"].TI, "Scarred hands")
			-- Hidden: Total RP 3 keeps it but does not send it.
			choose(page.glanceShown, "hidden")
			click(page.glanceSave)
			mock.RunTimers()
			expect.equal(fake.profile.player.misc.PE["1"].AC, false)
			click(page.glanceRemove)
			mock.AcceptPopup()
			mock.RunTimers()
			expect.equal(char.glance[1], nil)
			expect.equal(fake.profile.player.misc.PE["1"], nil, "Dawnward's slot removed")
		end)

		t:it("saves the profile icon and class colour, written through the setters once kept in sync", function()
			local mock, env, ns, fake, page = start()
			ns.TRP3Page.Open(page, "profile")
			expect.truthy(page.look:IsVisible())
			page.look.iconEdit:SetText("inv_misc_note_02")
			page.look.colorEdit:SetText("#C41F3B")
			click(page.look.save)
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			expect.equal(char.trp3status.icon, "inv_misc_note_02")
			expect.equal(char.trp3status.classColor, "c41f3b")
			mock.Slash("trp3 sync-status icon on")
			mock.Slash("trp3 sync-status classColor on")
			mock.RunTimers()
			expect.equal(fake.profile.player.characteristics.IC, "inv_misc_note_02")
			expect.equal(fake.profile.player.characteristics.CH, "c41f3b")
		end)
	end)

	t:describe("Total RP 3 profile editor: layout (L2)", function()
		t:it("every new control fits its card, the same at window scale 0.7 and 1.4", function()
			local _, _, ns, _, page = start()
			local cardW, cardH = page.card:GetWidth(), page.card:GetHeight()
			local function snapshot()
				local s = {}
				local widgets = { page.look, page.glanceTitle, page.glanceArea.frame, page.glanceChoose,
					page.glanceSave, page.glanceRemove, page.glancePreview, page.glanceUp, page.glanceDown,
					page.openTRP3, page.disconnect }
				for _, r in ipairs(page.glanceRows) do widgets[#widgets + 1] = r end
				for _, b in pairs(page.statusText) do
					widgets[#widgets + 1] = b.area.frame
					widgets[#widgets + 1] = b.save
					widgets[#widgets + 1] = b.import
				end
				for _, r in ipairs(page.styleRows) do widgets[#widgets + 1] = r.value end
				for _, w in ipairs(widgets) do
					local x, y, wd, h = rect(w)
					if x then
						-- page.disconnect hangs from the right edge.
						if w == page.disconnect then x = cardW - x - wd end
						expect.truthy(x >= 0 and x + wd <= cardW, "inside the card's width")
						expect.truthy(y >= 0 and y + h <= cardH - 14 + 0.5, "above the card's bottom")
						s[#s + 1] = x; s[#s + 1] = y; s[#s + 1] = wd; s[#s + 1] = h
					end
				end
				return s
			end
			ns.TRP3Page.Open(page, "status")
			local base = snapshot()
			expect.truthy(#base > 40, "measured the controls")
			local frame = ns.MainWindow.GetFrame()
			for _, scale in ipairs({ 0.7, 1.4 }) do
				frame:SetScale(scale)
				ns.MainWindow.Refresh()
				expect.deepEqual(snapshot(), base, "scale " .. scale)
			end
			-- Each row's controls never overlap.
			local r = page.styleRows[1]
			expect.truthy(ns.TRP3MiscSections.STYLE_LABEL + ns.TRP3MiscSections.STYLE_VALUE + 8 + 140 <= page.innerWidth)
			expect.truthy(ns.Widgets.LabelFits("With player permission", r.value:GetWidth(), r.value:GetHeight()))
			for _, b in ipairs(page.statusNav.buttons) do
				expect.truthy(ns.Widgets.LabelFits(b:GetText(), b:GetWidth(), b:GetHeight(), "segment"), b:GetText())
			end
			for _, b in ipairs(page.syncNav.buttons) do
				expect.truthy(ns.Widgets.LabelFits(b:GetText(), b:GetWidth(), b:GetHeight(), "segment"), b:GetText())
			end
			-- The icon picker fits the card beside the rail.
			expect.truthy(page.iconPicker:GetWidth() <= page.innerWidth)
			expect.truthy(ns.TRP3Page.HEAD_HEIGHT + page.iconPicker:GetHeight() <= cardH)
		end)

		t:it("Disconnect… stops every part after a confirmation, leaving Total RP 3 as it is", function()
			local mock, env, ns, fake, page = start()
			mock.Slash("fact add origin Born in Stormwind")
			mock.Vis("fact vis 1 public")
			assert(ns.TRP3Commands.ConnectAll(ns.ctx, {}))
			mock.RunTimers()
			local about = fake.profile.player.about.T1.TX
			ns.TRP3Page.Open(page, "connection")
			expect.truthy(page.disconnect:IsShown())
			click(page.disconnect)
			local asked = mock.AcceptPopup()
			expect.truthy(asked:find("stops keeping it up to date", 1, true), asked)
			local entry = env.DawnwardChroniclesTRP3DB.optIn[CHAR]
			for _, id in ipairs(ns.TRP3Ledger.MAPPINGS) do
				expect.truthy(ns.TRP3Ledger.Policy(entry, id) ~= "dawnward", id)
			end
			expect.equal(fake.profile.player.about.T1.TX, about, "what Dawnward wrote stays")
			expect.falsy(page.disconnect:IsShown())
		end)

		t:it("Synchronization holds Connection, Status and Recovery behind one switch", function()
			local _, _, _, _, page = start()
			click(page.nav.buttons[6])
			expect.equal(page.feature, "connection")
			expect.truthy(page.syncNav.buttons[1]:IsShown())
			click(page.syncNav.buttons[3])
			expect.equal(page.feature, "recovery")
			expect.truthy(page.backups:IsVisible())
			click(page.nav.buttons[1])
			expect.falsy(page.syncNav.buttons[1]:IsShown())
			click(page.nav.buttons[6])
			expect.equal(page.feature, "recovery", "the rail remembers the last view")
			expect.equal(page.title:GetText(), "Synchronization")
		end)
	end)
end
