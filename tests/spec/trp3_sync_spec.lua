-- L2: automatic TRP3 sync against the 3.4.1 fake (mocked; not in-game evidence).
local Loader = require("support.loader")
local Fake = require("fakes.trp3_341")

return function(t, expect)
	local KEY = "Testchar-TestRealm"

	-- A world: Dawnward core + TRP3 integration + a fake TRP3.
	local function world(fakeOpts)
		local ns = Loader.WithTRP3()
		local fake = Fake.new(fakeOpts or {})
		local store = ns.Store.new(ns.Schema.NewDatabase(), ns.Schema.NewDatabase())
		local clock = 1000
		local combat = false
		local deps = {
			env = fake.env, ledger = ns.TRP3Ledger.New(), store = store, characterKey = KEY,
			now = function() clock = clock + 1; return clock end,
			inCombat = function() return combat end,
		}
		local w = { ns = ns, fake = fake, deps = deps, store = store, Sync = ns.TRP3Sync }
		function w.char()
			return assert(store:EnsureCharacter(KEY, 1))
		end
		function w.publicFact(category, statement)
			return ns.Facts.Add(w.char(), { category = category, statement = statement, visibility = "public" })
		end
		function w.trait(axis, value)
			ns.Personality.Set(w.char(), axis, value)
			ns.Personality.SetVisibility(w.char(), axis, "public")
		end
		function w.setCombat(v) combat = v end
		function w.enable(feature)
			return assert(w.Sync.SetOptIn(deps, feature, true))
		end
		function w.about() return fake.profile.player.about end
		function w.ps() return fake.profile.player.characteristics.PS end
		return w
	end

	t:describe("TRP3 sync: biography (issue #5)", function()
		t:it("does nothing until the player opts in", function()
			local w = world()
			w.publicFact("origin", "Born in Stormwind")
			local before = w.fake.snapshot()
			expect.deepEqual(w.Sync.Run(w.deps), {})
			expect.equal(w.Sync.Check(w.deps, "about").state, "off")
			expect.deepEqual(w.fake.snapshot(), before)
			expect.equal(#w.fake.events, 0)
		end)

		t:it("appends only Dawnward's section, bumps the version and notifies TRP3 and MSP", function()
			local w = world()
			w.publicFact("origin", "Born in Stormwind")
			w.ns.Facts.Add(w.char(), { category = "fear", statement = "PRIVATE-FEAR" })
			w.enable("about")
			local results = w.Sync.Run(w.deps)
			expect.equal(results[1].state, "written", results[1].message)
			local about = w.about()
			expect.equal(about.T1.TX, "Private about text\n\n{h3}Chronicle{/h3}\nOrigin: Born in Stormwind")
			expect.falsy(about.T1.TX:find("PRIVATE-FEAR", 1, true))
			expect.equal(about.v, 4, "bumped two steps from 2")
			expect.equal(about.TE, 1)
			expect.equal(about.BK, 1)
			local e = w.fake.events[#w.fake.events]
			expect.equal(e.event, "REGISTER_DATA_UPDATED")
			expect.deepEqual(e.args, { KEY, w.fake.profileId, "about" })
			expect.equal(w.fake.msp.DE, about.T1.TX, "the MSP description was rebuilt")
			expect.deepEqual(w.fake.remoteRefetch({ about = 2, characteristics = 3 }), { "about" })
			expect.equal(#w.deps.ledger.backups, 1)
			expect.equal(w.ns.TRP3Ledger.BackupData(w.deps.ledger.backups[1]).T1.TX, "Private about text")
		end)

		t:it("writes nothing and keeps the version when nothing changed", function()
			local w = world()
			w.publicFact("origin", "Born in Stormwind")
			w.enable("about")
			w.Sync.Run(w.deps)
			local v, events = w.about().v, #w.fake.events
			local again = w.Sync.Run(w.deps)
			expect.equal(again[1].state, "noop")
			expect.equal(w.about().v, v)
			expect.equal(#w.fake.events, events)
			expect.equal(#w.deps.ledger.backups, 1, "no backup for a no-op")
		end)

		t:it("updates the section as the character develops, keeping the player's text", function()
			local w = world()
			w.publicFact("origin", "Born in Stormwind")
			w.enable("about")
			w.Sync.Run(w.deps)
			w.publicFact("belief", "Protect the weak")
			expect.equal(w.Sync.Run(w.deps)[1].state, "written")
			expect.equal(w.about().T1.TX, "Private about text\n\n{h3}Chronicle{/h3}\nOrigin: Born in Stormwind"
				.. "\nBelief: Protect the weak")
		end)

		t:it("never overwrites the player's edit of Dawnward's section", function()
			local w = world()
			w.publicFact("origin", "Born in Stormwind")
			w.enable("about")
			w.Sync.Run(w.deps)
			w.about().T1.TX = w.about().T1.TX:gsub("Stormwind", "Lakeshire (my edit)")
			local edited = w.fake.snapshot()
			w.publicFact("belief", "Protect the weak")
			local r = w.Sync.Run(w.deps)[1]
			expect.equal(r.state, "conflict")
			expect.truthy(r.message:find("Your version is kept"))
			expect.deepEqual(w.fake.snapshot(), edited)
			-- And it stays paused until the player decides.
			expect.equal(w.Sync.Run(w.deps)[1].state, "conflict")
			expect.deepEqual(w.fake.snapshot(), edited)
		end)

		t:it("resolve keep stops managing; resolve reclaim adds a fresh section without touching the edit", function()
			local w = world()
			w.publicFact("origin", "Born in Stormwind")
			w.enable("about")
			w.Sync.Run(w.deps)
			w.about().T1.TX = w.about().T1.TX .. " (edited)"
			w.Sync.Run(w.deps)
			expect.falsy(w.Sync.Resolve(w.deps, "about", "maybe"))
			assert(w.Sync.Resolve(w.deps, "about", "reclaim"))
			local edited = w.about().T1.TX
			expect.equal(w.Sync.Run(w.deps)[1].state, "written")
			expect.equal(w.about().T1.TX:sub(1, #edited), edited)

			local w2 = world()
			w2.publicFact("origin", "Born in Stormwind")
			w2.enable("about")
			w2.Sync.Run(w2.deps)
			w2.about().T1.TX = "rewritten entirely"
			w2.Sync.Run(w2.deps)
			assert(w2.Sync.Resolve(w2.deps, "about", "keep"))
			expect.equal(w2.Sync.Check(w2.deps, "about").state, "off")
		end)

		t:it("waits while an editor holds a draft, including after TRP3's window is closed mid-edit", function()
			local w = world()
			w.publicFact("origin", "Born in Stormwind")
			w.enable("about")
			w.fake.openEditor("about")
			local r = w.Sync.Run(w.deps)[1]
			expect.equal(r.state, "deferred")
			expect.equal(w.about().T1.TX, "Private about text")
			w.fake.closeEditorWindow("about")
			expect.equal(w.Sync.Run(w.deps)[1].state, "deferred")
			w.fake.cancelEditor("about")
			expect.equal(w.Sync.Run(w.deps)[1].state, "written")
		end)

		t:it("an editor save from an older draft is detected as a conflict and gets a different version", function()
			-- Editor opened while the window was hidden is impossible to see as
			-- open only if the frame flag lies; model the worst case directly.
			local w = world()
			w.publicFact("origin", "Born in Stormwind")
			w.enable("about")
			local draft = w.fake.openEditor("about")
			w.fake.cancelEditor("about") -- flag cleared, but keep the stale draft to save later
			w.Sync.Run(w.deps)
			local ours = w.about().v
			w.fake.aboutEditor.shown = true
			draft.T1.TX = "Draft from before Dawnward wrote"
			w.fake.saveEditor("about")
			expect.truthy(w.about().v ~= ours, "other clients re-fetch the player's save")
			expect.deepEqual(w.fake.remoteRefetch({ about = ours, characteristics = 3 }), { "about" })
			expect.equal(w.Sync.Run(w.deps)[1].state, "conflict", "the lost section is noticed, not re-added silently")
		end)

		t:it("waits in combat", function()
			local w = world()
			w.publicFact("origin", "Born in Stormwind")
			w.enable("about")
			w.setCombat(true)
			expect.equal(w.Sync.Run(w.deps)[1].state, "deferred")
			w.setCombat(false)
			expect.equal(w.Sync.Run(w.deps)[1].state, "written")
		end)

		t:it("supports template 2 (own frame) and template 3 (history), preserving layout", function()
			local w = world({ about = { v = 10, TE = 2, BK = 4, T2 = { { TX = "Mine", IC = "X", BK = 3 } } } })
			w.publicFact("origin", "Born in Stormwind")
			w.enable("about")
			w.Sync.Run(w.deps)
			expect.equal(#w.about().T2, 2)
			expect.deepEqual(w.about().T2[1], { TX = "Mine", IC = "X", BK = 3 })
			expect.equal(w.about().BK, 4)
			local w3 = world({ about = { v = 99, TE = 3, T3 = { PH = { TX = "Tall" }, HI = { TX = "Born." } } } })
			w3.publicFact("origin", "Born in Stormwind")
			w3.enable("about")
			w3.Sync.Run(w3.deps)
			expect.equal(w3.about().T3.HI.TX, "Born.\n\n{h3}Chronicle{/h3}\nOrigin: Born in Stormwind")
			expect.equal(w3.about().T3.PH.TX, "Tall")
			expect.equal(w3.about().v, 2, "99 wraps to 1, then 2")
		end)

		t:it("restores the backup and switches off if the profile does not read back as written", function()
			local w = world()
			w.publicFact("origin", "Born in Stormwind")
			w.enable("about")
			-- A hostile TRP3 that mangles the section right after our write.
			w.fake.env.TRP3_Addon.TriggerEvent = function(_, _, _, _, section)
				if section == "about" and w.about().T1.TX:find("Chronicle") then
					w.about().T1.TX = w.about().T1.TX .. " MANGLED"
				end
			end
			local r = w.Sync.Run(w.deps)[1]
			expect.equal(r.state, "failed")
			expect.truthy(r.message:find("restored from the backup"))
			expect.equal(w.about().T1.TX, "Private about text")
			expect.equal(w.Sync.Check(w.deps, "about").state, "off")
		end)

		t:it("restores the backup when TRP3's notification fails", function()
			local w = world({ triggerFails = true })
			w.publicFact("origin", "Born in Stormwind")
			w.enable("about")
			local r = w.Sync.Run(w.deps)[1]
			expect.equal(r.state, "failed")
			-- The restore also goes through the failing notification, so it reports that.
			expect.truthy(r.message:find("rollback") or r.message:find("restored"))
		end)
	end)

	t:describe("TRP3 sync: guards (issue #3)", function()
		t:it("refuses to opt in on the default profile, unsupported versions, missing TRP3 or missing APIs", function()
			for _, opts in ipairs({ { isDefault = true }, { version = "3.5.3" }, { notLoaded = true },
				{ noEvents = true }, { noEditorFrames = true }, { noPlayerApi = true } }) do
				local w = world(opts)
				local ok, err = w.Sync.SetOptIn(w.deps, "about", true)
				expect.falsy(ok, "should refuse for " .. next(opts))
				expect.truthy(type(err) == "string" and #err > 0)
			end
		end)

		t:it("refuses a malformed section and writes nothing", function()
			local w = world({ about = { v = 2, TE = 7 } })
			w.publicFact("origin", "Born in Stormwind")
			w.enable("about")
			local before = w.fake.snapshot()
			local r = w.Sync.Run(w.deps)[1]
			expect.equal(r.state, "blocked")
			expect.truthy(r.message:find("template"))
			expect.deepEqual(w.fake.snapshot(), before)
		end)

		t:it("pauses after a profile switch and never writes to another profile", function()
			local w = world()
			w.publicFact("origin", "Born in Stormwind")
			w.enable("about")
			w.fake.switchProfile("1700000099ZZZZZ", "Other", { about = { v = 1, TE = 1, T1 = { TX = "Other bio" } },
				characteristics = { v = 1, PS = {} }, character = { v = 1 } })
			local r = w.Sync.Run(w.deps)[1]
			expect.equal(r.state, "blocked")
			expect.truthy(r.message:find("not the one sync was enabled for"))
			expect.equal(w.about().T1.TX, "Other bio")
		end)

		t:it("never publishes in simulation mode, and uses real data only", function()
			local w = world()
			w.publicFact("origin", "Born in Stormwind")
			w.enable("about")
			w.store:SetSimulation(true)
			expect.equal(w.Sync.Run(w.deps)[1].state, "blocked")
			w.ns.Facts.Add(assert(w.store:EnsureCharacter(KEY, 1)), { category = "fear", statement = "SIM-FACT",
				visibility = "public" })
			w.store:SetSimulation(false)
			w.Sync.Run(w.deps)
			expect.falsy(w.about().T1.TX:find("SIM-FACT", 1, true))
		end)

		t:it("names other characters sharing the profile when opting in", function()
			local w = world({ characters = { [KEY] = { profileID = "1700000000ABCDE" },
				["Alt-TestRealm"] = { profileID = "1700000000ABCDE" } } })
			local _, message = w.Sync.SetOptIn(w.deps, "about", true)
			expect.truthy(message:find("shared with 1 other"))
		end)

		t:it("refuses a section too large to back up", function()
			local w = world({ about = { v = 1, TE = 1, T1 = { TX = string.rep("x", 70000) } } })
			w.publicFact("origin", "Born in Stormwind")
			w.enable("about")
			local r = w.Sync.Run(w.deps)[1]
			expect.equal(r.state, "blocked")
			expect.truthy(r.message:find("too large"))
			expect.equal(#w.about().T1.TX, 70000)
		end)

		t:it("a newer or damaged ledger blocks everything", function()
			local w = world()
			w.publicFact("origin", "Born in Stormwind")
			w.enable("about")
			w.deps.ledgerReadOnly = "the TRP3 ledger comes from a newer version"
			expect.equal(w.Sync.Run(w.deps)[1].state, "blocked")
			expect.falsy(w.Sync.SetOptIn(w.deps, "traits", true))
		end)
	end)

	t:describe("TRP3 sync: personality traits (issue #6)", function()
		local function withTraits()
			return world({ characteristics = { v = 5, FN = "Aelin", TI = "Knight", PS = {
				{ ID = 3, V2 = 12 }, { LT = "Gloomy", RT = "Cheerful", V2 = 4, LI = "a", RI = "b" } } } })
		end

		t:it("adds owned traits, keeps presets and the player's traits, and is idempotent", function()
			local w = withTraits()
			w.trait("courage", 15)
			w.char().personality.faith = { value = 2, visibility = "private" }
			w.enable("traits")
			local r = w.Sync.Run(w.deps)[1]
			expect.equal(r.state, "written", r.message)
			local ps = w.ps()
			expect.equal(#ps, 3)
			expect.deepEqual(ps[1], { ID = 3, V2 = 12 })
			expect.deepEqual(ps[2], { LT = "Gloomy", RT = "Cheerful", V2 = 4, LI = "a", RI = "b" })
			expect.deepEqual(ps[3], { LT = "Cautious", RT = "Bold", V2 = 5 }, "15 toward Bold = 5 points toward Cautious")
			expect.equal(w.fake.profile.player.characteristics.TI, "Knight")
			expect.equal(w.fake.profile.player.characteristics.v, 7)
			expect.deepEqual(w.fake.events[#w.fake.events].args, { KEY, w.fake.profileId, "characteristics" })
			local v = w.fake.profile.player.characteristics.v
			expect.equal(w.Sync.Run(w.deps)[1].state, "noop")
			expect.equal(w.fake.profile.player.characteristics.v, v)
		end)

		t:it("updates only changed owned values and pauses if the player moved an owned slider", function()
			local w = withTraits()
			w.trait("courage", 15)
			w.enable("traits")
			w.Sync.Run(w.deps)
			w.trait("courage", 18)
			w.Sync.Run(w.deps)
			expect.equal(w.ps()[3].V2, 2)
			w.ps()[3].V2 = 11
			w.trait("courage", 20)
			expect.equal(w.Sync.Run(w.deps)[1].state, "conflict")
			expect.equal(w.ps()[3].V2, 11)
			assert(w.Sync.Resolve(w.deps, "traits", "reclaim"))
			expect.equal(w.Sync.Run(w.deps)[1].state, "written")
			expect.equal(w.ps()[3].V2, 0)
		end)

		t:it("waits while the characteristics editor is open", function()
			local w = withTraits()
			w.trait("courage", 15)
			w.enable("traits")
			w.fake.openEditor("characteristics")
			expect.equal(w.Sync.Run(w.deps)[1].state, "deferred")
			expect.equal(#w.ps(), 2)
		end)
	end)

	t:describe("TRP3 sync: recovery (issue #4)", function()
		t:it("rollback restores the previous section exactly, and can itself be undone", function()
			local w = world()
			w.publicFact("origin", "Born in Stormwind")
			w.enable("about")
			w.Sync.Run(w.deps)
			local written = w.about().T1.TX
			local ok, message = w.Sync.Rollback(w.deps)
			expect.truthy(ok, message)
			expect.equal(w.about().T1.TX, "Private about text")
			expect.equal(w.Sync.Check(w.deps, "about").state, "off")
			-- Undo the rollback from the safety backup it made.
			local safety = w.deps.ledger.backups[#w.deps.ledger.backups]
			assert(w.Sync.Rollback(w.deps, safety.id))
			expect.equal(w.about().T1.TX, written)
		end)

		t:it("rollback refuses another profile's backup and an open editor", function()
			local w = world()
			w.publicFact("origin", "Born in Stormwind")
			w.enable("about")
			w.Sync.Run(w.deps)
			w.fake.openEditor("about")
			expect.falsy(w.Sync.Rollback(w.deps))
			w.fake.cancelEditor("about")
			w.fake.switchProfile("1700000099ZZZZZ", "Other")
			local ok, err = w.Sync.Rollback(w.deps, w.deps.ledger.backups[1].id)
			expect.falsy(ok)
			expect.truthy(err:find("another"))
		end)

		t:it("release removes only Dawnward's content and turns sync off", function()
			local w = world()
			w.publicFact("origin", "Born in Stormwind")
			w.trait("courage", 15)
			w.enable("about")
			w.enable("traits")
			w.Sync.Run(w.deps)
			assert(w.Sync.Release(w.deps, "about"))
			assert(w.Sync.Release(w.deps, "traits"))
			expect.equal(w.about().T1.TX, "Private about text")
			expect.deepEqual(w.ps(), {})
			expect.equal(w.Sync.Check(w.deps, "about").state, "off")
			expect.equal(w.char().facts[1].statement, "Born in Stormwind", "Dawnward data is untouched")
		end)

		t:it("the ledger survives a save and reload", function()
			local w = world()
			w.publicFact("origin", "Born in Stormwind")
			w.enable("about")
			w.Sync.Run(w.deps)
			local reloaded = assert(w.ns.TRP3Ledger.Normalize(w.ns.Util.DeepCopy(w.deps.ledger)))
			expect.deepEqual(reloaded, w.deps.ledger)
			w.deps.ledger = reloaded
			expect.equal(w.Sync.Run(w.deps)[1].state, "noop")
		end)
	end)
end
