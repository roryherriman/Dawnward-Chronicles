-- L2: TRP3 sync through the whole addon under the WoW mock and the 3.4.1
-- fake (mocked client; not in-game evidence).
local Boot = require("support.boot")
local Fake = require("fakes.trp3_341")

return function(t, expect)
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
		return mock, env, ns, fake
	end

	t:describe("TRP3 sync through /dawnward (L2)", function()
		t:it("is off by default: no timers, no writes, no events", function()
			local mock, _, _, fake = start()
			local before = fake.snapshot()
			mock.Slash("fact add origin Born in Stormwind")
			mock.Slash("fact vis 1 public")
			expect.equal(mock.RunTimers(), 0)
			expect.deepEqual(fake.snapshot(), before)
			expect.equal(#fake.events, 0)
			expect.truthy(mock.Slash("trp3"):find("Automatic profile sync: off"))
		end)

		t:it("enable needs confirm; then a debounced run writes once and persists the ledger", function()
			local mock, env, _, fake = start()
			mock.Slash("fact add origin Born in Stormwind")
			mock.Slash("fact vis 1 public")
			expect.truthy(mock.Slash("trp3 enable about"):find("EXPERIMENTAL"))
			expect.equal(env.DawnwardChroniclesTRP3DB.optIn["Testchar-TestRealm"], nil)
			expect.truthy(mock.Slash("trp3 enable about confirm"):find("sync is ON"))
			expect.equal(#mock.timers, 1, "several requests merge into one run")
			mock.Slash("fact add belief Protect the weak")
			mock.Slash("fact vis 2 public")
			expect.equal(#mock.timers, 1)
			mock.chat = {}
			mock.RunTimers()
			expect.truthy(table.concat(mock.chat, "\n"):find("Updated your Total RP 3 biography"))
			expect.truthy(fake.profile.player.about.T1.TX:find("Belief: Protect the weak", 1, true))
			local db = env.DawnwardChroniclesTRP3DB
			expect.equal(#db.backups, 1)
			expect.truthy(db.profiles[fake.profileId].about)
			-- A later command with nothing new writes nothing.
			local v = fake.profile.player.about.v
			mock.Slash("status")
			mock.RunTimers()
			expect.equal(fake.profile.player.about.v, v)
		end)

		t:it("preview after a /reload without opening TRP3 is not 'waiting' (PR #9 in-game report)", function()
			local mock, _, _, fake = start()
			mock.Slash("fact add origin Born in Stormwind")
			mock.Slash("fact vis 1 public")
			mock.Slash("trp3 enable about confirm")
			mock.RunTimers()
			fake.openEditor("about")
			fake.cancelEditor("about")
			fake.closeEditorWindow()
			fake.reload()
			local preview = mock.Slash("trp3 preview")
			expect.truthy(preview:find("biography: up to date", 1, true), preview)
			expect.falsy(preview:find("waiting", 1, true), preview)
		end)

		t:it("trp3 diagnose reports each guard input and writes nothing", function()
			local mock, _, _, fake = start()
			mock.Slash("fact add origin Born in Stormwind")
			mock.Slash("fact vis 1 public")
			mock.Slash("trp3 enable about confirm")
			fake.openEditor("about")
			local before = fake.snapshot()
			local events = #fake.events
			local report = mock.Slash("trp3 diagnose")
			expect.truthy(report:find("about editor: draft yes", 1, true), report)
			expect.truthy(report:find("edit mode yes", 1, true), report)
			expect.truthy(report:find("characteristics editor: draft no", 1, true), report)
			expect.truthy(report:find("biography: opted in yes", 1, true), report)
			expect.truthy(report:find("state waiting", 1, true), report)
			expect.deepEqual(fake.snapshot(), before)
			expect.equal(#fake.events, events)
		end)

		t:it("retries after the editor closes, and reports a conflict once", function()
			local mock, _, _, fake = start()
			mock.Slash("fact add origin Born in Stormwind")
			mock.Slash("fact vis 1 public")
			mock.Slash("trp3 enable about confirm")
			fake.openEditor("about")
			mock.RunTimers()
			expect.equal(fake.profile.player.about.T1.TX, "Private about text")
			expect.equal(#mock.timers, 1, "a retry was scheduled")
			fake.cancelEditor("about")
			mock.RunTimers()
			expect.truthy(fake.profile.player.about.T1.TX:find("Chronicle", 1, true))

			fake.profile.player.about.T1.TX = "Rewritten by the player"
			mock.Slash("fact add belief Protect the weak")
			mock.Slash("fact vis 2 public")
			mock.chat = {}
			mock.RunTimers()
			local first = table.concat(mock.chat, "\n")
			expect.truthy(first:find("paused"), first)
			mock.Slash("status")
			mock.chat = {}
			mock.RunTimers()
			expect.falsy(table.concat(mock.chat, "\n"):find("paused"), "the same conflict is not repeated")
			expect.equal(fake.profile.player.about.T1.TX, "Rewritten by the player")
		end)

		t:it("listens to TRP3 profile switches as hints and pauses for another profile", function()
			local mock, _, _, fake = start()
			mock.Slash("fact add origin Born in Stormwind")
			mock.Slash("fact vis 1 public")
			mock.Slash("trp3 enable about confirm")
			mock.RunTimers()
			fake.switchProfile("1700000099ZZZZZ", "Other", { about = { v = 1, TE = 1, T1 = { TX = "Other" } },
				characteristics = { v = 1, PS = {} }, character = { v = 1 } })
			expect.equal(#mock.timers, 1, "the TRP3 event requested a run")
			mock.RunTimers()
			expect.equal(fake.profile.player.about.T1.TX, "Other")
		end)

		t:it("preview, paste, backups, log and rollback work through /dawnward trp3", function()
			local mock, _, ns, fake = start()
			mock.Slash("fact add origin Born in Stormwind")
			mock.Slash("fact vis 1 public")
			expect.truthy(mock.Slash("trp3 preview"):find("biography: off"))
			mock.Slash("trp3 paste")
			expect.truthy(ns.CopyBox.GetFrame().editBox:GetText():find("Origin: Born in Stormwind", 1, true))
			mock.Slash("trp3 enable about confirm")
			mock.RunTimers()
			expect.truthy(mock.Slash("trp3 backups"):find("#1 about"))
			expect.truthy(mock.Slash("trp3 log"):find("insert"))
			expect.truthy(mock.Slash("trp3 rollback"):find("confirm"))
			-- The safe default restores the player's own text and rebuilds
			-- Dawnward's part from what is Public now (v0.8); "exact" restores
			-- the backup byte for byte.
			local written = fake.profile.player.about.T1.TX
			expect.truthy(mock.Slash("trp3 rollback confirm"):find("Restored your own", 1, true))
			expect.equal(fake.profile.player.about.T1.TX, written)
			expect.truthy(mock.Slash("trp3 rollback 1 exact confirm"):find("Restored"))
			expect.equal(fake.profile.player.about.T1.TX, "Private about text")
			expect.truthy(mock.Slash("trp3 help"):find("enable about"))
		end)

		t:it("a ledger from a newer build is left untouched and blocks sync", function()
			local saved = { schemaVersion = 99, secret = true }
			local mock, env = start({}, { DawnwardChroniclesTRP3DB = saved })
			expect.truthy(table.concat(mock.chat, "\n"):find("sync is paused"))
			expect.truthy(env.DawnwardChroniclesTRP3DB == saved)
			expect.deepEqual(saved, { schemaVersion = 99, secret = true })
			expect.truthy(mock.Slash("trp3 enable about confirm"):find("newer"))
		end)

		t:it("waits in combat", function()
			local mock, _, _, fake = start()
			mock.Slash("fact add origin Born in Stormwind")
			mock.Slash("fact vis 1 public")
			mock.Slash("trp3 enable about confirm")
			mock.inCombat = true
			mock.RunTimers()
			expect.equal(fake.profile.player.about.T1.TX, "Private about text")
			mock.inCombat = false
			mock.RunTimers()
			expect.truthy(fake.profile.player.about.T1.TX:find("Chronicle", 1, true))
		end)
	end)
end
