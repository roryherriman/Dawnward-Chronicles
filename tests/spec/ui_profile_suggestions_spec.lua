-- L2 (v0.10.2): profile suggestions in the window (mocked client and the
-- TRP3 3.4.1 fake; not in-game evidence): "Your profile could show this" in
-- the Story Director, the waiting suggestion in the At First Glance editor,
-- Status and OOC > Currently updates (the mode, Accept / Edit / Later /
-- Dismiss, Undo last automatic update), and the count in the Total RP 3
-- page's rail. Nothing reaches Total RP 3 until the player accepts, and then
-- only through the guarded sync.
local Boot = require("support.boot")
local Fake = require("fakes.trp3_341")

local CHAR = "Testchar-TestRealm"
local DAY = 24 * 3600

local function click(button)
	button:GetScript("OnClick")(button)
end

local function choose(seg, id)
	for _, b in ipairs(seg.buttons) do
		if b.segmentId == id then click(b) end
	end
end

local function trp3Start()
	local fake = Fake.new({})
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
	mock.Slash("set name Kyssarra")
	ns.SettingsPanel.OpenPage("trp3")
	return mock, env, ns, fake, ns.SettingsPanel.panel.trp3Page
end

local function status(ns)
	return ns.MainWindow.GetFrame().status:GetText() or ""
end

-- Three approved story steps toward Bold on the real character, long ago.
local function seedCourage(ns, env, n)
	local char = env.DawnwardChroniclesDB.characters[CHAR]
	for i = 1, n do
		local at = i * DAY
		local c = assert(ns.Evolution.Propose(char, "courage", 1, "Kyssarra stood firm", 100 + i, at))
		assert(ns.Evolution.Apply(char, c.id, at))
	end
	return char
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
	t:describe("Story Director: Your profile could show this (L2)", function()
		t:it("appears after approving the growth that completes the evidence; Accept saves it in Dawnward", function()
			local mock, env, ns = Boot.Start()
			mock.Slash("set name Morrow")
			mock.Slash("")
			ns.MainWindow.Select("story")
			local section = ns.StoryView.section
			mock.quest = { id = 10, title = "The Defias Brotherhood", level = 20 }
			mock.Fire("QUEST_COMPLETE")
			mock.Fire("QUEST_TURNED_IN", 10, 100, 10)
			ns.MainWindow.Refresh()
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			local reaction = char.story.reactions[1]
			local view = ns.Reactions.Present(char, reaction, ns.ctx.now())
			local axis, delta = next(view.options[1].effects)
			expect.truthy(axis, "the first answer moves an axis")
			-- Two earlier approved steps the same way.
			for i = 1, 2 do
				local c = assert(ns.Evolution.Propose(char, axis, delta, "Morrow earlier", 50 + i, i * DAY))
				assert(ns.Evolution.Apply(char, c.id, i * DAY))
			end
			expect.falsy(section.profilePanel:IsShown(), "nothing yet")
			click(section.optionButtons[1])
			expect.falsy(section.profilePanel:IsShown(), "an answer only proposes a change")
			for _ = 1, 3 do
				local row = section.changeRows[1]
				if row:IsShown() and not section.profilePanel:IsShown() then click(row.approve) end
			end
			expect.truthy(section.profilePanel:IsShown(), "the approval completed the evidence")
			local s = ns.ProfileSuggestions.Waiting(char, ns.ctx.now())[1]
			expect.equal(section.profileTitle:GetText(), s.title)
			expect.truthy(section.profileText:GetText():find("Morrow", 1, true), section.profileText:GetText())
			expect.truthy(section.profileWhy:GetText():find("approved personality changes", 1, true))
			expect.truthy(section.profileEffect:GetText():find("Adds At First Glance entry 1", 1, true))
			expect.truthy(section.profileEffect:GetText():find("Nothing changes until you accept", 1, true))
			expect.deepEqual(char.glance, {}, "nothing saved yet")
			click(section.profileAccept)
			expect.equal(char.glance[1].title, s.title)
			expect.truthy(status(ns):find("At First Glance entry 1 saved in Dawnward", 1, true), status(ns))
			expect.falsy(section.profilePanel:IsShown())
			-- The side column still fits the content height.
			local _, y = rect(section.growthPanel)
			expect.truthy(y ~= nil)
		end)

		t:it("Later and Dismiss leave the profile unchanged; the side panels stay inside the content", function()
			local mock, env, ns = Boot.Start()
			mock.Slash("set name Morrow")
			mock.Slash("")
			ns.MainWindow.Select("story")
			local section = ns.StoryView.section
			local char = seedCourage(ns, env, 3)
			ns.MainWindow.Refresh()
			expect.truthy(section.profilePanel:IsShown())
			local _, py, _, ph = rect(section.profilePanel)
			expect.truthy(py + ph <= ns.StoryView.LAYOUT.contentH + 0.5, "inside the content height")
			click(section.profileLater)
			expect.falsy(section.profilePanel:IsShown())
			expect.deepEqual(char.glance, {})
			ns.ProfileSuggestions.Find(char, 1).laterUntil = 0
			ns.MainWindow.Refresh()
			expect.truthy(section.profilePanel:IsShown(), "back once its time has come")
			click(section.profileDismiss)
			expect.falsy(section.profilePanel:IsShown())
			expect.equal(ns.ProfileSuggestions.Find(char, 1).status, "dismissed")
			expect.deepEqual(char.glance, {})
		end)
	end)

	t:describe("Settings > Total RP 3: At First Glance suggestions (L2)", function()
		t:it("shows the suggestion in the preview's place; Edit and Save accept it in the player's words", function()
			local mock, env, ns, fake, page = trp3Start()
			local char = seedCourage(ns, env, 3)
			ns.TRP3Page.Open(page, "glance")
			expect.truthy(page.glanceSuggest:IsShown())
			expect.falsy(page.glancePreview:IsShown())
			expect.equal(page.glanceSuggest.title:GetText(), "Growing resolve")
			expect.truthy(page.glanceSuggest.why:GetText():find("approved personality changes", 1, true))
			expect.equal(page.glanceRows[1].state:GetText(), "Dawnward suggests one")
			local railGlance
			for _, b in ipairs(page.nav.buttons) do
				if b.segmentId == "glance" then railGlance = b end
			end
			expect.equal(railGlance.name:GetText(), "At First Glance (1)")
			expect.equal(railGlance.state, "waiting")
			click(page.glanceSuggest.buttons.edit)
			expect.truthy(status(ns):find("in the editor for entry 1", 1, true), status(ns))
			expect.falsy(page.glanceSuggest:IsShown(), "editing: the preview is back")
			expect.equal(page.glanceTitle:GetText(), "Growing resolve")
			ns.MainWindow.Refresh()
			expect.equal(page.glanceTitle:GetText(), "Growing resolve", "a refresh keeps the suggestion in the editor")
			expect.deepEqual(char.glance, {}, "nothing saved by Edit")
			page.glanceText:SetText("Kyssarra stands a little straighter these days.")
			click(page.glanceSave)
			expect.equal(char.glance[1].text, "Kyssarra stands a little straighter these days.")
			expect.equal(ns.ProfileSuggestions.Find(char, 1).status, "edited")
			mock.RunTimers()
			expect.equal(fake.profile.player.misc.PE["1"], nil, "At First Glance sync is off: nothing written")
			expect.equal(railGlance.name:GetText(), "At First Glance")
		end)

		t:it("Accept from the editor's box, and the guarded sync publishes it once At First Glance sync is on", function()
			local mock, env, ns, fake, page = trp3Start()
			local own = { TI = "Player's own", TX = "Written in Total RP 3.", IC = "inv_misc_note_02", AC = true }
			fake.profile.player.misc.PE = { ["1"] = own }
			seedCourage(ns, env, 3)
			ns.TRP3Page.Open(page, "glance")
			choose(page.glanceSync, "dawnward")
			mock.AcceptPopup()
			mock.RunTimers()
			expect.deepEqual(fake.profile.player.misc.PE["1"], own)
			expect.equal(fake.profile.player.misc.PE["2"], nil, "the suggestion is not written while it waits")
			click(page.glanceSuggest.buttons.accept)
			mock.RunTimers()
			expect.deepEqual(fake.profile.player.misc.PE["1"], own, "the player's slot is untouched")
			expect.equal(fake.profile.player.misc.PE["2"].TI, "Growing resolve")
			-- Every new control fits the card.
			local cardW, cardH = page.card:GetWidth(), page.card:GetHeight()
			for _, w in ipairs({ page.glanceSuggest }) do
				local x, y, wd, h = rect(w)
				expect.truthy(x >= 0 and x + wd <= cardW and y >= 0 and y + h <= cardH - 14 + 0.5)
			end
			for _, b in pairs(page.glanceSuggest.buttons) do
				if type(b) == "table" then
					expect.truthy(b.x + b:GetWidth() + 16 <= page.glanceSuggest:GetWidth(), b:GetText())
					expect.truthy(ns.Widgets.LabelFits(b:GetText(), b:GetWidth(), b:GetHeight()), b:GetText())
				end
			end
		end)
	end)

	t:describe("Settings > Total RP 3: At First Glance revisions and Hidden (independent review)", function()
		t:it("Edit on a revision of an entry the player changed since names the entry Save fills; Hidden is kept",
			function()
			-- Review findings 4 (Accept saved the entry shown although the editor
			-- said Hidden) and (c) (the status line named the player's entry).
			local _, env, ns, _, page = trp3Start()
			local char = seedCourage(ns, env, 3)
			local PS = ns.ProfileSuggestions
			assert(ns.ProfileActions.Accept(ns.ctx, PS.Waiting(char, ns.ctx.now(), "glance")[1].id))
			for i = 4, 6 do
				local c = assert(ns.Evolution.Propose(char, "courage", 1, "Kyssarra stood firm", 100 + i, i * DAY))
				assert(ns.Evolution.Apply(char, c.id, i * DAY))
			end
			local s = PS.Waiting(char, ns.ctx.now(), "glance")[1]
			expect.deepEqual(s.target, { n = 1, revises = true })
			-- The player rewrites entry 1 while the revision waits.
			assert(ns.Glance.Save(char, 1, { title = "Growing resolve", text = "My own words now." }, ns.ctx.now()))
			expect.truthy(PS.Effect(char, s):find("Adds At First Glance entry 2", 1, true), PS.Effect(char, s))
			ns.TRP3Page.Open(page, "glance")
			expect.equal(page.glanceRows[2].state:GetText(), "Dawnward suggests one")
			click(page.glanceSuggest.buttons.edit)
			expect.truthy(status(ns):find("in the editor for entry 2", 1, true), status(ns))
			expect.equal(page.glanceSel, 2)
			choose(page.glanceShown, "hidden")
			click(page.glanceSave)
			expect.equal(char.glance[1].text, "My own words now.", "the player's entry is untouched")
			expect.equal(char.glance[2].title, "Steady resolve")
			expect.equal(char.glance[2].active, false, "Hidden, as chosen in the editor")
		end)
	end)

	t:describe("Settings > Total RP 3: Currently updates (L2)", function()
		t:it("Manual by default; Suggested offers a text; Automatic only after confirming", function()
			local mock, env, ns, fake, page = trp3Start()
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			ns.TRP3Page.Open(page, "status")
			click(page.statusNav.buttons[3])
			expect.truthy(page.statusSub.updates:IsShown())
			expect.equal(page.modeSeg.selected, "manual")
			expect.truthy(page.currentlySuggest.empty:GetText():find("Manual", 1, true))
			expect.falsy(page.undoAuto:IsEnabled())
			ns.Actions.ObserveLocation(ns.ctx, { zone = "Westfall" })
			expect.equal(char.profileSuggestions, nil, "Manual: nothing")
			choose(page.modeSeg, "suggested")
			expect.equal(ns.RPStatus.CurrentlyMode(char), "suggested")
			ns.Actions.ObserveLocation(ns.ctx, { zone = "Redridge Mountains" })
			ns.MainWindow.Refresh()
			expect.equal(page.currentlySuggest.text:GetText(), "In Redridge Mountains.")
			expect.truthy(page.currentlySuggest.why:GetText():find("first recorded visit", 1, true))
			local railStatus
			for _, b in ipairs(page.nav.buttons) do
				if b.segmentId == "status" then railStatus = b end
			end
			expect.equal(railStatus.name:GetText(), "Status and OOC (1)")
			click(page.currentlySuggest.buttons.edit)
			expect.truthy(page.statusSub.text:IsShown(), "Edit opens the Currently editor")
			local b = page.statusText.currently
			expect.equal(b.edit:GetText(), "In Redridge Mountains.")
			expect.equal(char.trp3status.currently, nil, "nothing saved by Edit")
			b.edit:SetText("Scouting Redridge.")
			click(b.save)
			expect.equal(char.trp3status.currently, "Scouting Redridge.")
			expect.equal(char.profileSuggestions.list[1].status, "edited")
			mock.RunTimers()
			expect.equal(fake.profile.player.character.CU == "Scouting Redridge.", false,
				"Currently is not kept in sync: Total RP 3 unchanged")
			-- Automatic asks first.
			click(page.statusNav.buttons[3])
			choose(page.modeSeg, "automatic")
			expect.equal(ns.RPStatus.CurrentlyMode(char), "suggested", "not before the confirmation")
			local asked = mock.AcceptPopup()
			expect.truthy(asked:find("never replaces a Currently you wrote yourself", 1, true), asked)
			expect.equal(ns.RPStatus.CurrentlyMode(char), "automatic")
			expect.equal(page.modeSeg.selected, "automatic")
		end)

		t:it("Automatic updates Total RP 3 through the guarded sync, and Undo brings the old text back", function()
			local mock, env, ns, fake, page = trp3Start()
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			assert(ns.TRP3Commands.SetStatus(ns.ctx, "currently", "Resting in Goldshire."))
			assert(ns.TRP3Commands.ManageRow(ns.ctx, "currently", true))
			mock.RunTimers()
			expect.equal(fake.profile.player.character.CU, "Resting in Goldshire.")
			assert(ns.ProfileActions.SetCurrentlyMode(ns.ctx, "automatic", true))
			-- The player's own text (as 0.10.1 left it) is never replaced: the
			-- update waits for them, as the confirmation promises.
			ns.Actions.ObserveLocation(ns.ctx, { zone = "Westfall" })
			expect.equal(char.trp3status.currently, "Resting in Goldshire.")
			mock.RunTimers()
			expect.equal(fake.profile.player.character.CU, "Resting in Goldshire.")
			ns.TRP3Page.Open(page, "status")
			click(page.statusNav.buttons[3])
			expect.equal(page.currentlySuggest.text:GetText(), "In Westfall.")
			expect.truthy(page.currentlySuggest.effect:GetText():find("Waiting for you", 1, true),
				page.currentlySuggest.effect:GetText())
			-- Accepted by hand, Automatic continues from it.
			click(page.currentlySuggest.buttons.accept)
			expect.equal(char.trp3status.currently, "In Westfall.")
			mock.RunTimers()
			expect.equal(fake.profile.player.character.CU, "In Westfall.")
			char.profileSuggestions.lastCurrentlyAt = 0
			ns.Actions.ObserveLocation(ns.ctx, { zone = "Redridge Mountains" })
			expect.equal(char.trp3status.currently, "In Redridge Mountains.")
			mock.RunTimers()
			expect.equal(fake.profile.player.character.CU, "In Redridge Mountains.")
			ns.MainWindow.Refresh()
			expect.truthy(page.undoAuto:IsEnabled())
			expect.truthy(page.autoLine:GetText():find("In Redridge Mountains.", 1, true))
			click(page.undoAuto)
			expect.equal(char.trp3status.currently, "In Westfall.")
			mock.RunTimers()
			expect.equal(fake.profile.player.character.CU, "In Westfall.")
			expect.falsy(page.undoAuto:IsEnabled())
			-- A Currently typed in Total RP 3 is never overwritten.
			fake.env.AddOn_TotalRP3.Player.GetCurrentUser():SetCurrentlyText("Typed in Total RP 3")
			char.profileSuggestions.lastCurrentlyAt = 0
			ns.Actions.ObserveLocation(ns.ctx, { zone = "Duskwood" })
			mock.RunTimers()
			expect.equal(fake.profile.player.character.CU, "Typed in Total RP 3")
			ns.MainWindow.Refresh()
			expect.truthy(page.currentlySuggest.effect:GetText():find("Waiting for you", 1, true),
				page.currentlySuggest.effect:GetText())
			-- The new controls fit the card.
			local cardW, cardH = page.card:GetWidth(), page.card:GetHeight()
			for _, w in ipairs({ page.currentlySuggest, page.undoAuto, page.modeSeg.buttons[1] }) do
				local x, y, wd, h = rect(w)
				expect.truthy(x >= 0 and x + wd <= cardW and y >= 0 and y + h <= cardH - 14 + 0.5)
			end
		end)

		t:it("is refused in simulation mode", function()
			local mock, env, ns, _, page = trp3Start()
			mock.Slash("sim on")
			ns.TRP3Page.Open(page, "status")
			click(page.statusNav.buttons[3])
			choose(page.modeSeg, "suggested")
			expect.truthy(status(ns):find("Turn simulation mode off first", 1, true), status(ns))
			expect.truthy(ns.ctx.store:IsSimulation())
			expect.equal(ns.RPStatus.CurrentlyMode(env.DawnwardChroniclesDB.characters[CHAR]), "manual")
		end)
	end)
end
