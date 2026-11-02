-- L1/L2 (v0.9): connecting Total RP 3 during first-time setup and from
-- Settings > Total RP 3 when the active profile cannot be connected as it
-- is: TRP3's default profile (never written), a profile another character
-- already keeps up to date, an unsupported version, and a profile switched
-- after connecting. Through the whole addon under the WoW mock and the TRP3
-- 3.4.1 fake (its profile functions follow totalRP3/Core/Profiles.lua);
-- not in-game evidence.
local Boot = require("support.boot")
local Fake = require("fakes.trp3_341")

local CHAR = "Testchar-TestRealm"
local OTHER = "Otherchar-TestRealm"
local DEFAULT_ID = "1700000000ABCD*"

local function click(button)
	button:GetScript("OnClick")(button)
end

local function deepCopy(v)
	if type(v) ~= "table" then return v end
	local out = {}
	for k, x in pairs(v) do out[k] = deepCopy(x) end
	return out
end

-- Boots with Total RP 3 (the fake) installed; the wizard may open by itself.
local function start(fakeOpts, savedVariables)
	local fake = Fake.new(fakeOpts or {})
	local extra = {}
	for k, v in pairs(fake.env) do
		if k ~= "C_AddOns" then extra[k] = v end
	end
	local mock, env, ns = Boot.Load({ extra = extra, savedVariables = savedVariables })
	mock.env.C_AddOns.IsAddOnLoaded = fake.env.C_AddOns.IsAddOnLoaded
	local meta = mock.env.C_AddOns.GetAddOnMetadata
	mock.env.C_AddOns.GetAddOnMetadata = function(name, field)
		return fake.env.C_AddOns.GetAddOnMetadata(name, field) or meta(name, field)
	end
	Boot.Login(mock)
	ns.SetupLaunch.Reset()
	return mock, env, ns, fake
end

-- Accepts Dawnward's confirmation dialog and returns what it asked.
local function accept(ns)
	local d = ns.Widgets.dialog
	assert(d and d:IsShown(), "no confirmation dialog is open")
	local text = d.text:GetText()
	d.accept:GetScript("OnClick")(d.accept)
	return text
end

local function openSetup(mock, ns)
	mock.Fire("PLAYER_ENTERING_WORLD", true, false)
	mock.RunTimers()
	assert(ns.SetupWizard.IsShown(), "setup opened by itself")
	ns.SetupWizard.Go(5)
	return ns.SetupWizard.Frame()
end

local function ledger(env)
	return env.DawnwardChroniclesTRP3DB
end

-- A ledger where another character already keeps profile id up to date.
local function linkedLedger(id)
	return { schemaVersion = 2, optIn = { [OTHER] = { about = true, traits = false, profileId = id,
		policy = { about = "dawnward" } } }, profiles = {}, backups = {}, nextBackupId = 1, log = {} }
end

return function(t, expect)
	t:describe("TRP3 profiles: the adapter (L1, fake 3.4.1)", function()
		t:it("offers create and select only where the profile functions were audited", function()
			local _, _, ns = Boot.Start()
			local A = ns.TRP3Adapter
			expect.deepEqual(A.ProfileTools(Fake.new().env), { create = true, select = true })
			expect.deepEqual(A.ProfileTools(Fake.new({ version = "3.5.3" }).env), { create = false, select = false })
			expect.deepEqual(A.ProfileTools(Fake.new({ noProfileApi = true }).env), { create = false, select = false })
			expect.deepEqual(A.ProfileTools(Fake.new({ notLoaded = true }).env), { create = false, select = false })
		end)

		t:it("lists named profiles only, and creates a blank profile without touching any other", function()
			local _, _, ns = Boot.Start()
			local A = ns.TRP3Adapter
			local fake = Fake.new({ isDefault = true, profileId = DEFAULT_ID,
				profiles = { ["1700000005MAINX"] = { profileName = "Main", player = { characteristics = { v = 4 } } } } })
			local before = deepCopy(fake.profiles)
			local list = A.ListProfiles(fake.env)
			expect.equal(#list, 1, "the default profile is never offered")
			expect.equal(list[1].name, "Main")
			expect.equal(A.SuggestProfileName(fake.env, "Main"), "Main 2", "a taken name gets a number")
			local id = assert(A.CreateProfile(fake.env, "Mirelle"))
			expect.equal(fake.profileId, id, "the character now uses it")
			expect.equal(fake.characters[fake.playerId].profileID, id)
			expect.equal(fake.profiles[id].profileName, "Mirelle")
			expect.equal(fake.profiles[id].player.characteristics.v, 1, "TRP3's blank template")
			for oldId, p in pairs(before) do
				expect.deepEqual(fake.profiles[oldId], p, "unchanged: " .. oldId)
			end
			local again, why = A.CreateProfile(fake.env, "Mirelle")
			expect.falsy(again)
			expect.truthy(why:find("already has a profile named", 1, true))
			expect.equal(A.CleanProfileName("|cffff0000Red|r name"), "Red name")
		end)

		t:it("never switches to the default profile, an unknown one, or over an open editor draft", function()
			local _, _, ns = Boot.Start()
			local A = ns.TRP3Adapter
			local fake = Fake.new({ profiles = { ["1700000005ALTXX"] = { profileName = "Alt",
				player = deepCopy(Fake.new().profile.player) } } })
			expect.falsy(A.SelectProfile(fake.env, fake.defaultProfileId))
			expect.falsy(A.SelectProfile(fake.env, "1700000009NOPEX"))
			fake.openEditor("about")
			local ok, why = A.SelectProfile(fake.env, "1700000005ALTXX")
			expect.falsy(ok)
			expect.truthy(why:find("unsaved changes", 1, true))
			fake.cancelEditor("about")
			expect.equal(A.SelectProfile(fake.env, "1700000005ALTXX"), "1700000005ALTXX")
			expect.equal(fake.profileId, "1700000005ALTXX")
			expect.equal(fake.selected, 1)
		end)
	end)

	t:describe("TRP3 setup stage: the default profile (L2, fake 3.4.1)", function()
		t:it("guides to a named profile, creates it after a confirmation, and Finish connects that profile", function()
			local mock, env, ns, fake = start({ isDefault = true, profileId = DEFAULT_ID })
			local defaultBefore = deepCopy(fake.profiles[DEFAULT_ID])
			local w = openSetup(mock, ns)
			expect.equal(w.trp3Chip.label:GetText(), "Total RP 3 3.4.1 · supported")
			expect.truthy(w.trp3:GetText():find("Total RP 3's default profile", 1, true), w.trp3:GetText())
			expect.truthy(w.trp3Warn:GetText():find("never writes to Total RP 3's default profile", 1, true))
			expect.falsy(w.trp3Cycles.trp3:IsEnabled(), "the default profile cannot be connected")
			expect.truthy(w.trp3Create:IsShown())
			expect.truthy(w.trp3Refresh:IsShown())
			expect.falsy(w.trp3Switch:IsShown(), "no other profile to switch to")
			expect.truthy(w.trp3Action:GetText():find("without connecting", 1, true))
			-- The suggested name is the one typed on the Character stage.
			ns.SetupWizard.Go(2)
			for _, input in ipairs(w.inputs) do
				if input.fieldKey == "name" then input:SetText("Mirelle") end
				if input.fieldKey == "homeland" then input:SetText("Goldshire") end
			end
			ns.SetupWizard.Go(5)
			click(w.trp3Create)
			local asked = accept(ns)
			expect.truthy(asked:find("named \"Mirelle\"", 1, true), asked)
			expect.truthy(asked:find("including the default profile, are not changed", 1, true))
			local newId = fake.created[1]
			expect.equal(fake.profileId, newId, "this character now uses the new profile")
			expect.truthy(w.trp3Action:GetText():find("\"Mirelle\" created", 1, true), w.trp3Action:GetText())
			-- Nothing is connected or written before Finish.
			expect.falsy(ledger(env).optIn[CHAR], "no authorisation yet")
			expect.equal(fake.profiles[newId].player.characteristics.FN, "Testchar", "TRP3's own template only")
			expect.deepEqual(fake.profiles[DEFAULT_ID], defaultBefore, "the default profile is untouched")
			expect.truthy(w.trp3Cycles.trp3:IsEnabled(), "connectable now")
			expect.falsy(w.trp3Create:IsShown())
			expect.truthy(w.trp3:GetText():find("Active profile: \"Mirelle\" · this character only", 1, true))
			-- Finish: the single authorisation, bound to the new profile.
			ns.SetupWizard.Go(6)
			expect.truthy(w.finishNote:GetText():find("connects Total RP 3", 1, true))
			ns.SetupWizard.Next()
			local entry = ledger(env).optIn[CHAR]
			expect.equal(entry.profileId, newId)
			for _, id in ipairs(ns.TRP3Ledger.MAPPINGS) do
				expect.equal(ns.TRP3Ledger.Policy(entry, id), "dawnward", id)
			end
			mock.RunTimers()
			expect.equal(fake.profiles[newId].player.characteristics.BP, "Goldshire", "published after Finish")
			expect.deepEqual(fake.profiles[DEFAULT_ID], defaultBefore, "the default profile is never written")
		end)

		t:it("switches to one of the player's profiles, the one named after the character first", function()
			local mock, env, ns, fake = start({ isDefault = true, profileId = DEFAULT_ID, profiles = {
				["1700000005ALTXX"] = { profileName = "Alt", player = { characteristics = { v = 1 } } },
				["1700000006TESTC"] = { profileName = "Testchar", player = { characteristics = { v = 1 } } } } })
			local w = openSetup(mock, ns)
			expect.truthy(w.trp3Switch:IsShown())
			expect.falsy(w.trp3Create:IsShown(), "\"Testchar\" exists; switching to it is offered instead")
			click(w.trp3Switch)
			local first = ns.Widgets.dialog.text:GetText()
			expect.truthy(first:find("\"Testchar\"", 1, true), first)
			expect.truthy(first:find("Profile 1 of 2", 1, true))
			click(w.trp3Switch)
			expect.truthy(ns.Widgets.dialog.text:GetText():find("\"Alt\"", 1, true), "the next one")
			click(w.trp3Switch)
			accept(ns)
			expect.equal(fake.profileId, "1700000006TESTC")
			expect.falsy(ledger(env).optIn[CHAR], "switching connects nothing")
			expect.truthy(w.trp3Cycles.trp3:IsEnabled())
			ns.SetupWizard.Go(6)
			ns.SetupWizard.Next()
			expect.equal(ledger(env).optIn[CHAR].profileId, "1700000006TESTC")
		end)

		t:it("without the profile functions: step-by-step help, then Refresh connection", function()
			local mock, env, ns, fake = start({ isDefault = true, profileId = DEFAULT_ID })
			local tools = fake.env.TRP3_API.profile
			fake.env.TRP3_API.profile = nil
			local w = openSetup(mock, ns)
			expect.truthy(w.trp3Warn:GetText():find("open Profiles and create a profile", 1, true), w.trp3Warn:GetText())
			expect.falsy(w.trp3Create:IsShown())
			expect.falsy(w.trp3Switch:IsShown())
			expect.truthy(w.trp3Refresh:IsShown())
			-- The player creates and selects a profile in Total RP 3 itself.
			local id = tools.createProfile("Mirelle")
			fake.env.TRP3_API.profile = nil
			tools.selectProfile(id)
			click(w.trp3Refresh)
			expect.truthy(w.trp3Action:GetText():find("this profile can be connected", 1, true))
			expect.truthy(w.trp3Cycles.trp3:IsEnabled())
			ns.SetupWizard.Go(6)
			ns.SetupWizard.Next()
			expect.equal(ledger(env).optIn[CHAR].profileId, id)
		end)

		t:it("Finish on the default profile completes setup and writes nothing", function()
			local mock, env, ns, fake = start({ isDefault = true, profileId = DEFAULT_ID })
			local before = deepCopy(fake.profiles)
			openSetup(mock, ns)
			ns.SetupWizard.Go(6)
			ns.SetupWizard.Next()
			mock.RunTimers()
			expect.falsy(ledger(env).optIn[CHAR])
			expect.truthy(env.DawnwardChroniclesDB.characters[CHAR].wizard.done)
			expect.deepEqual(fake.profiles, before, "no profile created or written")
		end)
	end)

	t:describe("TRP3 setup stage: shared, linked and unsupported profiles (L2, fake 3.4.1)", function()
		t:it("a profile other characters use: says so, offers a profile of its own, and connects if kept", function()
			local mock, env, ns, fake = start({ characters = {
				[CHAR] = { profileID = "1700000000ABCDE" }, ["Alt-TestRealm"] = { profileID = "1700000000ABCDE" } } })
			local w = openSetup(mock, ns)
			expect.truthy(w.trp3:GetText():find("also used by 1 other character", 1, true), w.trp3:GetText())
			expect.truthy(w.trp3Warn:GetText():find("would show the same", 1, true))
			expect.truthy(w.trp3Cycles.trp3:IsEnabled(), "still connectable")
			expect.truthy(w.trp3Create:IsShown(), "a profile of its own is offered")
			ns.SetupWizard.Go(6)
			ns.SetupWizard.Next()
			expect.equal(ledger(env).optIn[CHAR].profileId, fake.profileId)
		end)

		t:it("a profile another character keeps up to date: guided like the default profile", function()
			local mock, env, ns, fake = start({}, { DawnwardChroniclesTRP3DB = linkedLedger("1700000000ABCDE") })
			local before = fake.snapshot()
			local w = openSetup(mock, ns)
			expect.truthy(w.trp3:GetText():find("already connected to " .. OTHER, 1, true), w.trp3:GetText())
			expect.truthy(w.trp3Warn:GetText():find("already kept up to date by " .. OTHER, 1, true))
			expect.falsy(w.trp3Cycles.trp3:IsEnabled())
			expect.truthy(w.trp3Create:IsShown())
			ns.SetupWizard.Go(6)
			ns.SetupWizard.Next()
			expect.falsy(ledger(env).optIn[CHAR], "never a second character on the same profile")
			expect.deepEqual(fake.snapshot(), before)
		end)

		t:it("an unsupported version: explained, nothing to connect, nothing written", function()
			local mock, env, ns, fake = start({ version = "3.5.3" })
			local before = fake.snapshot()
			local w = openSetup(mock, ns)
			expect.truthy(w.steps[5]:IsShown(), "installed, so the stage is shown")
			expect.equal(w.trp3Chip.label:GetText(), "Total RP 3 3.5.3 · not supported")
			expect.truthy(w.trp3Warn:GetText():find("connects only to Total RP 3 3.4.1", 1, true))
			expect.falsy(w.trp3Cycles.trp3:IsEnabled())
			expect.falsy(w.trp3Create:IsShown())
			expect.falsy(w.trp3Switch:IsShown())
			ns.SetupWizard.Go(6)
			expect.truthy(w.choices:GetText():find("not connected now", 1, true))
			ns.SetupWizard.Next()
			mock.RunTimers()
			expect.falsy(ledger(env).optIn[CHAR])
			expect.deepEqual(fake.snapshot(), before)
			expect.equal(#fake.created, 0)
		end)

		t:it("resuming an unfinished setup keeps the Total RP 3 choice", function()
			local mock, _, ns = start()
			local w = openSetup(mock, ns)
			click(w.trp3Cycles.trp3)
			expect.equal(w.values.trp3, "later")
			ns.SetupWizard.Close()
			ns.SetupWizard.Open({})
			expect.equal(w.page, 5, "back on the Total RP 3 stage")
			expect.equal(w.values.trp3, "later")
			expect.equal(w.trp3Cycles.trp3:GetText(), "Not now (nothing is sent)")
		end)

		t:it("the stage fits its body and its buttons fit their labels", function()
			local mock, _, ns = start({ isDefault = true, profileId = DEFAULT_ID })
			local w = openSetup(mock, ns)
			local L = ns.SetupWizard.LAYOUT
			local B = ns.SetupWizard.TRP3_BUTTONS
			local fits = ns.Widgets.LabelFits
			expect.truthy(fits("Create a profile…", B.create, L.cycle, "primary"))
			expect.truthy(fits("Switch profile…", B.switch, L.cycle))
			expect.truthy(fits("Switch back…", B.switch, L.cycle))
			expect.truthy(fits("Refresh connection", B.refresh, L.cycle, "ghost"))
			expect.truthy(B.create + B.gap + B.switch + B.gap + B.refresh <= L.bodyWidth - 2 * ns.Widgets.PANEL_PAD,
				"the three buttons share one row")
			local top
			for _, p in ipairs(w.trp3Note.__points or {}) do
				if p[1] == "TOPLEFT" then top = p[#p] end
			end
			-- At most three lines of 15 px for the note.
			expect.truthy(-top + 3 * 15 <= L.bodyHeight, "the note ends above the footer")
		end)
	end)

	t:describe("TRP3 page: the connection area (L2, fake 3.4.1)", function()
		local function page(ns)
			ns.SetupWizard.SkipAutoLaunchThisSession(ns.ctx.characterKey)
			ns.SettingsPanel.OpenPage("trp3")
			return ns.SettingsPanel.panel.trp3Page
		end

		t:it("on the default profile: opens on the Overview, explains, and creates a profile after asking", function()
			local _, env, ns, fake = start({ isDefault = true, profileId = DEFAULT_ID })
			local defaultBefore = deepCopy(fake.profiles[DEFAULT_ID])
			local p = page(ns)
			expect.equal(p.feature, "overview")
			expect.truthy(p.overviewRows[1].value:GetText():find("default profile, never written", 1, true))
			expect.truthy(p.connectionNote:GetText():find("never writes to Total RP 3's default profile", 1, true))
			expect.equal(p.connectAll:GetText(), "Create a profile…")
			expect.truthy(p.refreshConnection:IsShown())
			click(p.connectAll)
			expect.truthy(accept(ns):find("named \"Testchar\"", 1, true))
			expect.equal(fake.profileId, fake.created[1])
			ns.MainWindow.Refresh()
			expect.equal(p.connectAll:GetText(), "Connect everything…")
			expect.truthy(p.connectAll:IsEnabled())
			expect.truthy(p.connectionNote:GetText():find("your one authorisation", 1, true))
			expect.falsy(p.connectionNote:GetText():find("Public", 1, true))
			expect.falsy(ledger(env).optIn[CHAR], "creating connects nothing")
			click(p.connectAll)
			local asked = accept(ns)
			expect.falsy(asked:find("Public", 1, true), "no public-only wording")
			expect.equal(ledger(env).optIn[CHAR].profileId, fake.created[1])
			expect.deepEqual(fake.profiles[DEFAULT_ID], defaultBefore)
		end)

		t:it("after a profile switch: says sync is paused, writes nothing, and switches back after asking", function()
			local mock, env, ns, fake = start({ profiles = {
				["1700000005ALTXX"] = { profileName = "Alt", player = deepCopy(Fake.new().profile.player) } } })
			mock.Slash("set name Mirelle")
			assert(ns.TRP3Commands.ConnectAll(ns.ctx, {}))
			mock.RunTimers()
			local mainId = fake.profileId
			fake.env.TRP3_API.profile.selectProfile("1700000005ALTXX")
			local altBefore = deepCopy(fake.profiles["1700000005ALTXX"])
			mock.Slash("set name Mirelle Dawn")
			mock.RunTimers()
			expect.deepEqual(fake.profiles["1700000005ALTXX"], altBefore, "nothing written to the other profile")
			local p = page(ns)
			expect.equal(p.feature, "overview")
			expect.equal(p.chip.label:GetText(), "Paused")
			expect.truthy(p.overviewRows[2].value:GetText():find("Paused · connected to \"Main\"", 1, true))
			expect.truthy(p.connectionNote:GetText():find("Sync is paused", 1, true), p.connectionNote:GetText())
			expect.truthy(p.columns[2]:GetText():find("sync paused", 1, true))
			expect.equal(p.connectAll:GetText(), "Switch back…")
			expect.equal(p.previewProfile:GetText(), "Reconnect…")
			click(p.refreshConnection)
			expect.equal(p.connectAll:GetText(), "Switch back…", "still paused after a refresh")
			click(p.connectAll)
			expect.truthy(accept(ns):find("sync carries on", 1, true))
			expect.equal(fake.profileId, mainId)
			mock.RunTimers()
			ns.MainWindow.Refresh()
			expect.equal(p.chip.label:GetText(), "Connected", "sync carries on")
			expect.truthy(p.overviewRows[2].value:GetText():find("items kept up to date", 1, true))
			expect.equal(ledger(env).optIn[CHAR].profileId, mainId)
			expect.deepEqual(fake.profiles["1700000005ALTXX"], altBefore, "the other profile was never written")
		end)

		t:it("fits its connection buttons on one row", function()
			local _, _, ns = start()
			local p = page(ns)
			local B = ns.TRP3Page.CONNECTION_BUTTONS
			local h = ns.Style.CONTROL.compact
			for _, label in ipairs({ "Connect everything…", "Create a profile…", "Switch back…", "Reconnect…" }) do
				expect.truthy(ns.Widgets.LabelFits(label, B.primary, h, "primary"), label)
			end
			for _, label in ipairs({ "Preview profile", "Switch profile…", "Create a profile…", "Reconnect…" }) do
				expect.truthy(ns.Widgets.LabelFits(label, B.second, h), label)
			end
			expect.truthy(ns.Widgets.LabelFits("Refresh connection", B.refresh, h, "ghost"))
			expect.truthy(B.primary + 8 + B.second + 8 + B.refresh <= p.innerWidth, "no overlap")
			expect.truthy(ns.TRP3Page.CONNECTION_NOTE_TOP + 2 * ns.TRP3Page.LINE
				<= p.card:GetHeight() - 14 - h - 8, "the note stays above the buttons")
		end)
	end)
end
