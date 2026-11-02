-- L2 (v0.10): reproduces the owner's in-game report: "the backstory was
-- imported during first-time setup and Total RP 3 was connected, but the
-- About page says No description" while name, race, class, birthplace and
-- pronouns did reach Total RP 3. Drives the real path (first login, setup
-- wizard, Import a story, Finish with Connect, the debounced sync run)
-- against the TRP3 3.4.1 fake instead of calling the sync directly.
local Boot = require("support.boot")
local Fake = require("fakes.trp3_341")
local STORY = require("fixtures.backstory_paragraphs")

local CHAR = "Testchar-TestRealm"

return function(t, expect)
	local function startWithTRP3(fakeOpts, saved, existingFake)
		local fake = existingFake or Fake.new(fakeOpts or { about = { v = 1, TE = 1, BK = 1, T1 = {} } })
		local extra = {}
		for k, v in pairs(fake.env) do
			if k ~= "C_AddOns" then extra[k] = v end
		end
		local mock, env, ns = Boot.Load({ extra = extra, wizard = true, savedVariables = saved })
		mock.env.C_AddOns.IsAddOnLoaded = fake.env.C_AddOns.IsAddOnLoaded
		local meta = mock.env.C_AddOns.GetAddOnMetadata
		mock.env.C_AddOns.GetAddOnMetadata = function(name, field)
			return fake.env.C_AddOns.GetAddOnMetadata(name, field) or meta(name, field)
		end
		Boot.Login(mock)
		ns.SetupLaunch.Reset()
		return mock, env, ns, fake
	end

	local function drain(mock)
		for _ = 1, 20 do
			if #mock.timers == 0 then return end
			mock.RunTimers()
		end
	end

	t:describe("TRP3 About in game: setup imports the story, then connects (L2 repro)", function()
		t:it("publishes the backstory imported during setup to the About page", function()
			local mock, _, ns, fake = startWithTRP3()
			mock.Fire("PLAYER_ENTERING_WORLD", true, false)
			mock.RunTimers()
			expect.truthy(ns.SetupWizard.IsShown(), "setup opened by itself")
			-- Story stage: Import a story..., paste, Save.
			ns.ImportWizard.Open({ from = "setup" })
			ns.ImportWizard.Frame().edit:SetText(STORY)
			expect.truthy(ns.ImportWizard.Save())
			ns.ImportWizard.Close()
			-- Character details, then Finish with Total RP 3 connected.
			local w = ns.SetupWizard.Frame()
			w.values.race = "Human"
			ns.SetupWizard.Go(6)
			ns.SetupWizard.Next()
			drain(mock)
			local char = ns.ctx.store.real.characters[CHAR]
			-- The 0.9 cause: the story was stored before Finish chose the profile
			-- model, so it kept the old Private default, and the About page was
			-- built only from items marked Public. Now a new character is on the
			-- whole-profile model from the start, whatever the order of steps.
			expect.truthy(ns.Publication.IsComplete(char), "a new character publishes its whole profile")
			local tx = fake.profile.player.about.T1 and fake.profile.player.about.T1.TX or ""
			expect.truthy(tx:find("Tamsin Greyhollow was born", 1, true),
				"the About page holds the backstory (TRP3 would show 'No description' otherwise)")
			for p in (STORY .. "\n\n"):gmatch("(.-)\n\n") do
				if p:match("%S") then expect.equal(select(2, tx:gsub(p:gsub("%p", "%%%0"), "")), 1, p:sub(1, 40)) end
			end
		end)

		-- The owner's saved data from 0.9.0-dev: set up with the v0.9 wizard
		-- (the profile model, version 1), the story stored Private by the bug,
		-- Total RP 3 connected, the About page empty.
		local function v09Saved()
			local mock, env, ns, fake = startWithTRP3()
			mock.Fire("PLAYER_ENTERING_WORLD", true, false)
			mock.RunTimers()
			ns.ImportWizard.Open({ from = "setup" })
			ns.ImportWizard.Frame().edit:SetText(STORY)
			ns.ImportWizard.Save()
			ns.ImportWizard.Close()
			ns.SetupWizard.Go(6)
			ns.SetupWizard.Next()
			drain(mock)
			local db = ns.Util.DeepCopy(env.DawnwardChroniclesDB)
			db.characters[CHAR].publication = { mode = "profile", since = 1 } -- as 0.9.0-dev saved it
			db.characters[CHAR].sources.visibility = "private" -- the bug: stored before Finish
			fake.profile.player.about = { v = 1, TE = 1, BK = 1, T1 = {} } -- "No description"
			local ledger = ns.Util.DeepCopy(env.DawnwardChroniclesTRP3DB)
			for _, record in pairs(ledger.profiles) do record.about = nil end -- 0.9 never wrote the page
			return { DawnwardChroniclesDB = db, DawnwardChroniclesTRP3DB = ledger,
				DawnwardChroniclesUI = env.DawnwardChroniclesUI }, fake
		end

		t:it("after updating, the owner's 0.9 character shows why and publishes once confirmed", function()
			local saved, fake = v09Saved()
			local mock, _, ns = startWithTRP3(nil, saved, fake)
			mock.Fire("PLAYER_ENTERING_WORLD", true, false)
			drain(mock)
			local char = ns.ctx.store.real.characters[CHAR]
			expect.equal(ns.Publication.Status(char), "pending", "an item an earlier version kept back is never "
				.. "published without asking")
			expect.falsy(fake.profile.player.about.T1.TX)
			local report = mock.Slash("trp3 diagnose")
			expect.truthy(report:find("biography in the profile Dawnward publishes: no - kept back", 1, true), report)
			expect.truthy(report:find("waiting for your one-time confirmation", 1, true), report)
			expect.falsy(report:find("Tamsin Greyhollow was born", 1, true), "the report never prints the story")
			mock.Slash("publish confirm")
			drain(mock)
			local tx = fake.profile.player.about.T1.TX or ""
			expect.truthy(tx:find("Tamsin Greyhollow was born", 1, true), "published after the confirmation")
			report = mock.Slash("trp3 diagnose")
			expect.truthy(report:find("last read-back: matched what was written", 1, true), report)
			-- /reload: the page stays, and nothing is written twice.
			local after = fake.profile.player.about.v
			local reloaded = { DawnwardChroniclesDB = ns.Util.DeepCopy(mock.env.DawnwardChroniclesDB),
				DawnwardChroniclesTRP3DB = ns.Util.DeepCopy(mock.env.DawnwardChroniclesTRP3DB),
				DawnwardChroniclesUI = mock.env.DawnwardChroniclesUI }
			expect.truthy(reloaded.DawnwardChroniclesDB.characters[CHAR], "the saved character carries over")
			expect.truthy(reloaded.DawnwardChroniclesTRP3DB.optIn[CHAR], "and the connection")
			fake.reload()
			local mock2 = startWithTRP3(nil, reloaded, fake)
			mock2.Fire("PLAYER_ENTERING_WORLD", false, true)
			drain(mock2)
			expect.equal(fake.profile.player.about.v, after, "no second write after the reload")
			expect.equal(fake.profile.player.about.T1.TX, tx)
			expect.equal(mock2.Slash("trp3 diagnose"):match("next About run: ([^\n]*)"), "up to date")
		end)
	end)
end
