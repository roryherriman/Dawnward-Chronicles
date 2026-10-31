-- L1/L2 (v0.9): first-time setup opens by itself after a new character
-- enters the world, waits for a safe moment, opens only once, offers to
-- resume an unfinished setup, and connects Total RP 3 only when chosen.
-- Mocked client: proves the rules and wiring, not in-game timing.
local Boot = require("support.boot")
local Loader = require("support.loader")
local Fake = require("fakes.trp3_341")

local CHAR = "Testchar-TestRealm"

return function(t, expect)
	-- Boots with the wizard allowed to open by itself (as in game).
	local function start(opts)
		opts = opts or {}
		opts.wizard = true
		local mock, env, ns = Boot.Start(opts)
		ns.SetupLaunch.Reset()
		return mock, env, ns
	end

	-- PLAYER_ENTERING_WORLD, then the launch delay passes.
	local function enterWorld(mock)
		mock.Fire("PLAYER_ENTERING_WORLD", true, false)
		mock.RunTimers()
	end

	local function db(env)
		return env.DawnwardChroniclesDB
	end

	t:describe("first login: the decision (L1)", function()
		t:it("opens for a new character once, then offers to resume, and never for a finished one", function()
			local ns = Loader.Core()
			local O = ns.Onboarding
			expect.equal(O.LoginAction(nil, nil, 100), "open")
			expect.equal(O.LoginAction(nil, 50, 100), "offer", "seen before and unfinished")
			local char = ns.Schema.NewCharacter(1)
			char.wizard = { done = true, version = 2, doneAt = 5 }
			expect.equal(O.LoginAction(char, nil, 100), "none")
			local old = ns.Schema.NewCharacter(1)
			ns.Character.SetField(old, "name", "Lirael", 2)
			expect.equal(O.LoginAction(old, nil, 100), "none", "an established character never gets it")
		end)

		t:it("keeps the newest launch records, and cleans bad ones", function()
			local ns = Loader.Core()
			local raw = { ["A-R"] = 10, ["B-R"] = "x", [5] = 3, ["C-R"] = -1, ["D-R"] = 20 }
			expect.deepEqual(ns.Onboarding.CleanSeen(raw), { ["A-R"] = 10, ["D-R"] = 20 })
		end)
	end)

	t:describe("first login: opening by itself (L2)", function()
		t:it("opens after the world is ready, without the player opening Dawnward", function()
			local mock, env, ns = start()
			expect.falsy(ns.SetupWizard.IsShown(), "nothing at PLAYER_LOGIN")
			enterWorld(mock)
			expect.truthy(ns.SetupWizard.IsShown())
			expect.falsy(ns.MainWindow.IsShown())
			expect.truthy(db(env).ui.setupSeen[CHAR], "remembered, so it opens by itself only once")
			expect.falsy(db(env).characters[CHAR], "no character record before Finish")
			-- Opening Dawnward this session shows the journal, not the wizard again.
			ns.SetupWizard.Close()
			mock.Slash("")
			expect.falsy(ns.SetupWizard.IsShown())
			expect.truthy(ns.MainWindow.IsShown())
		end)

		t:it("waits during combat and opens when combat ends", function()
			local mock, _, ns = start()
			mock.inCombat = true
			enterWorld(mock)
			expect.falsy(ns.SetupWizard.IsShown(), "never in combat")
			mock.inCombat = false
			mock.Fire("PLAYER_REGEN_ENABLED")
			mock.RunTimers()
			expect.truthy(ns.SetupWizard.IsShown())
		end)

		t:it("waits for the intro cinematic and the loading screen", function()
			local cinematic = true
			local mock, _, ns = start({ extra = { InCinematic = function() return cinematic end } })
			enterWorld(mock)
			expect.falsy(ns.SetupWizard.IsShown(), "not over the intro cinematic")
			cinematic = false
			mock.Fire("LOADING_SCREEN_ENABLED")
			mock.Fire("CINEMATIC_STOP")
			mock.RunTimers()
			expect.falsy(ns.SetupWizard.IsShown(), "not while a loading screen is up")
			mock.Fire("LOADING_SCREEN_DISABLED")
			mock.RunTimers()
			expect.truthy(ns.SetupWizard.IsShown())
		end)

		t:it("gives up quietly after waiting too long, leaving the wizard for later", function()
			local mock, _, ns = start()
			mock.inCombat = true
			mock.Fire("PLAYER_ENTERING_WORLD", true, false)
			for _ = 1, ns.SetupLaunch.MAX_TRIES + 2 do mock.RunTimers() end
			expect.falsy(ns.SetupWizard.IsShown())
			expect.equal(#mock.timers, 0, "no endless retries")
		end)

		t:it("opens only once: a later login with setup unfinished offers to resume instead", function()
			local mock, env, ns = start()
			enterWorld(mock)
			ns.SetupWizard.Go(2)
			ns.SetupWizard.Frame().inputs[1]:SetText("Lirael")
			ns.SetupWizard.Go(3)
			ns.SetupWizard.Close() -- abandoned: the draft is kept
			local saved = ns.Util.DeepCopy(db(env))

			local mock2, _, ns2 = start({ savedVariables = { DawnwardChroniclesDB = saved } })
			enterWorld(mock2)
			expect.falsy(ns2.SetupWizard.IsShown(), "not opened by itself again")
			expect.truthy(table.concat(mock2.chat, "\n"):find("unfinished", 1, true))
			local asked = mock2.AcceptPopup()
			expect.truthy(asked.text:find("Continue setting up", 1, true))
			expect.truthy(ns2.SetupWizard.IsShown(), "Resume opens it")
			expect.equal(ns2.SetupWizard.Frame().title:GetText(), "Story", "where it was left")
			expect.equal(ns2.SetupWizard.Frame().inputs[1]:GetText(), "Lirael", "with the answers kept")
		end)

		t:it("does nothing once setup is complete, also after a reload", function()
			local mock, env, ns = start()
			enterWorld(mock)
			ns.SetupWizard.Go(6)
			ns.SetupWizard.Next()
			expect.truthy(db(env).characters[CHAR].wizard.done)
			local saved = ns.Util.DeepCopy(db(env))
			local mock2, _, ns2 = start({ savedVariables = { DawnwardChroniclesDB = saved } })
			enterWorld(mock2)
			expect.falsy(ns2.SetupWizard.IsShown())
			expect.falsy(ns2.Widgets.dialog and ns2.Widgets.dialog:IsShown(), "no offer either")
		end)

		t:it("never opens for an established character, in simulation mode or on read-only data", function()
			local mock, _, ns = start()
			mock.Slash("set name Lirael")
			ns.MainWindow.Hide()
			enterWorld(mock)
			expect.falsy(ns.SetupWizard.IsShown())
			local mock2, _, ns2 = start({ savedVariables = { DawnwardChroniclesDB = { schemaVersion = 999 } } })
			enterWorld(mock2)
			expect.falsy(ns2.SetupWizard.IsShown())
			local mock3, _, ns3 = start()
			mock3.Slash("sim on")
			enterWorld(mock3)
			expect.falsy(ns3.SetupWizard.IsShown())
		end)

		t:it("keeps characters, realms and accounts apart", function()
			-- Another realm's character of the same name has finished setup and been seen.
			local other = "Testchar-OtherRealm"
			local seeded = { schemaVersion = 5, characters = {}, importBackups = {},
				ui = { setupSeen = { [other] = 5 } } }
			local mock, env, ns = start({ savedVariables = { DawnwardChroniclesDB = seeded } })
			enterWorld(mock)
			expect.truthy(ns.SetupWizard.IsShown(), "a record for another realm does not count")
			expect.truthy(db(env).ui.setupSeen[CHAR])
			expect.equal(db(env).ui.setupSeen[other], 5, "the other realm's record is untouched")
			-- A second account has its own saved variables: nothing carries over.
			local mock2, _, ns2 = start()
			enterWorld(mock2)
			expect.truthy(ns2.SetupWizard.IsShown())
		end)
	end)

	t:describe("first login: connecting Total RP 3 from setup (L2, fake 3.4.1)", function()
		local function startWithTRP3(fakeOpts)
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
			ns.SetupLaunch.Reset()
			return mock, env, ns, fake
		end

		t:it("shows the stage with the active profile and connects on Finish only when chosen", function()
			local mock, env, ns, fake = startWithTRP3()
			local before = fake.snapshot()
			enterWorld(mock)
			local w = ns.SetupWizard.Frame()
			expect.truthy(w.steps[5]:IsShown(), "Total RP 3 is installed")
			ns.SetupWizard.Go(5)
			expect.equal(w.title:GetText(), "Total RP 3")
			expect.truthy(w.trp3:GetText():find("Active profile: Main", 1, true))
			expect.truthy(w.trp3Cycles.trp3:IsEnabled())
			expect.deepEqual(fake.snapshot(), before, "nothing is sent before Finish")
			ns.SetupWizard.Go(6)
			expect.truthy(w.choices:GetText():find("Total RP 3: connect", 1, true))
			ns.SetupWizard.Next()
			local entry = env.DawnwardChroniclesTRP3DB.optIn[CHAR]
			expect.truthy(entry, "authorised once")
			for _, id in ipairs(ns.TRP3Ledger.MAPPINGS) do
				expect.equal(ns.TRP3Ledger.Policy(entry, id), "dawnward", id)
			end
			expect.equal(entry.profileId, fake.profileId)
			expect.falsy(entry.adopt, "keep: nothing is taken over")
			expect.equal(#mock.timers, 1, "the normal debounced run does the writing")
		end)

		t:it("connects nothing when the player chooses Not now", function()
			local mock, env, ns = startWithTRP3()
			enterWorld(mock)
			ns.SetupWizard.Go(5)
			ns.SetupWizard.Frame().trp3Cycles.trp3:GetScript("OnClick")(ns.SetupWizard.Frame().trp3Cycles.trp3)
			expect.equal(ns.SetupWizard.Frame().values.trp3, "later")
			ns.SetupWizard.Go(6)
			ns.SetupWizard.Next()
			expect.falsy(env.DawnwardChroniclesTRP3DB.optIn[CHAR])
			expect.truthy(db(env).characters[CHAR].wizard.done, "setup still completes")
		end)

		t:it("records Replace as a one-time takeover choice", function()
			local mock, env, ns = startWithTRP3()
			enterWorld(mock)
			ns.SetupWizard.Go(5)
			local b = ns.SetupWizard.Frame().trp3Cycles.trp3Existing
			b:GetScript("OnClick")(b)
			ns.SetupWizard.Go(6)
			ns.SetupWizard.Next()
			expect.deepEqual(env.DawnwardChroniclesTRP3DB.optIn[CHAR].adopt, { about = true, traits = true, fields = true })
		end)

		t:it("cannot connect the default profile: says why, and setup still completes", function()
			local mock, env, ns = startWithTRP3({ isDefault = true })
			enterWorld(mock)
			ns.SetupWizard.Go(5)
			local w = ns.SetupWizard.Frame()
			expect.falsy(w.trp3Cycles.trp3:IsEnabled())
			expect.truthy(w.trp3Warn:GetText():find("default profile", 1, true))
			ns.SetupWizard.Go(6)
			ns.SetupWizard.Next()
			expect.falsy(env.DawnwardChroniclesTRP3DB.optIn[CHAR])
			expect.truthy(db(env).characters[CHAR].wizard.done)
		end)
	end)
end
