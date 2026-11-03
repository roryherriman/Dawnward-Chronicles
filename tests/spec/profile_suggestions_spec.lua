-- L2 (v0.10.2): approved character development -> suggested public-profile
-- change -> the player's approval -> the existing guarded sync
-- (Core/ProfileSuggestions.lua, Core/ProfileActions.lua), against the TRP3
-- 3.4.1 fake (mocked; not in-game evidence). Total RP 3 shapes follow the
-- 3.4.1 source: At First Glance slots player.misc.PE["1".."5"] = { IC, AC,
-- TI, TX } (Modules/Register/Characters/RegisterMisc.lua 332-357
-- applyPeekSlot; five slots: for i=1,5 at 254 and 457), Currently
-- player.character.CU through CurrentUser:SetCurrentlyText (Core/Player.lua
-- 419-436 UpdateProfileField, 446-448).
local Loader = require("support.loader")
local Fake = require("fakes.trp3_341")

return function(t, expect)
	local KEY = "Testchar-TestRealm"
	local DAY = 24 * 3600

	local function world(fakeOpts)
		local ns = Loader.WithTRP3()
		local fake = Fake.new(fakeOpts or {})
		local store = ns.Store.new(ns.Schema.NewDatabase(), ns.Schema.NewDatabase())
		local clock = 1000
		local deps = {
			env = fake.env, ledger = ns.TRP3Ledger.New(), store = store, characterKey = KEY,
			now = function() clock = clock + 1; return clock end,
			inCombat = function() return false end,
		}
		local w = { ns = ns, fake = fake, deps = deps, Sync = ns.TRP3Sync, PS = ns.ProfileSuggestions,
			PA = ns.ProfileActions }
		w.ctx = { store = store, characterKey = KEY, now = deps.now, trp3Deps = function() return deps end }
		function w.char() return assert(store:EnsureCharacter(KEY, 1)) end
		function w.later(seconds) clock = clock + seconds end
		function w.now() return clock end
		-- n approved story steps on an axis (a day apart: the daily limit).
		function w.approve(axis, delta, n)
			local char = w.char()
			for _ = 1, n do
				clock = clock + DAY
				local c = assert(ns.Evolution.Propose(char, axis, delta, "Testchar stood firm", clock, clock))
				assert(ns.Evolution.Apply(char, c.id, clock))
			end
		end
		function w.waiting(kind) return w.PS.Waiting(w.char(), clock, kind) end
		function w.misc() return fake.profile.player.misc end
		function w.ch() return fake.profile.player.character end
		function w.record() return deps.ledger.profiles[fake.profileId] end
		return w
	end

	t:describe("At First Glance suggestions need sufficient approved evidence", function()
		t:it("one or two steps toward Bold suggest nothing; the third does, with its records and reasons", function()
			local w = world()
			local char = w.char()
			char.fields.name = { value = "Kyssarra", visibility = "public" }
			char.fields.pronouns = { value = "she/her", visibility = "public" }
			w.approve("courage", 1, 2)
			expect.equal(#w.waiting(), 0, "two steps are not enough")
			expect.equal(char.profileSuggestions, nil, "nothing is stored while nothing is suggested")
			w.approve("courage", 1, 1)
			local s = w.waiting("glance")[1]
			expect.truthy(s, "three approved steps one way suggest an entry")
			expect.equal(s.key, "glance:axis:courage:up")
			expect.equal(s.title, "Growing resolve")
			expect.equal(s.text, "Kyssarra carries an increasingly steady determination, readier to step forward than "
				.. "before.")
			expect.falsy(s.text:lower():find("fearless", 1, true), "never more than the evidence")
			expect.equal(#s.sources.changes, 3)
			expect.equal(#s.sources.decisions, 3)
			expect.truthy(s.why[1]:find("3 approved personality changes toward Bold", 1, true), s.why[1])
			expect.truthy(s.why[2]:find("Testchar stood firm", 1, true))
			expect.deepEqual(s.target, { n = 1 })
			expect.deepEqual(char.glance, {}, "a suggestion changes nothing")
		end)

		t:it("counts only approved story steps: never the player's own settings, reversed or rejected ones", function()
			local w = world()
			local char = w.char()
			local ns = w.ns
			for _ = 1, 4 do ns.Evolution.RecordManual(char, "courage", 10, 15, w.now()) end
			local pending = assert(ns.Evolution.Propose(char, "courage", 1, "r", 1, w.now()))
			local rejected = assert(ns.Evolution.Propose(char, "courage", 1, "r", 2, w.now()))
			ns.Evolution.Reject(char, rejected.id, w.now())
			w.approve("courage", 1, 2)
			local last = char.story.changes[#char.story.changes]
			w.later(DAY)
			ns.Evolution.Reverse(char, last.id, w.now())
			w.approve("courage", 1, 1)
			expect.equal(pending.status, "pending")
			expect.equal(#w.waiting(), 0, "two applied steps remain: not enough")
		end)

		t:it("mixed directions need a net three; the wording follows the approved direction only", function()
			local w = world()
			w.approve("compassion", 1, 2)
			w.approve("compassion", -1, 1)
			w.approve("compassion", 1, 1)
			expect.equal(#w.waiting(), 0, "net +2")
			w.approve("compassion", 1, 1)
			local s = w.waiting("glance")[1]
			expect.equal(s.key, "glance:axis:compassion:up")
			expect.equal(s.text, "They have grown gentler with those in need.", "no name or pronouns: neutral")
		end)

		t:it("uses neutral wording without a name, and never claims physical traits", function()
			local w = world()
			w.approve("sociability", -1, 3)
			local s = w.waiting("glance")[1]
			expect.equal(s.text, "They have grown quieter and more reserved.")
			for _, words in pairs(w.PS.AXIS_WORDS) do
				for _, way in pairs(words) do
					for _, pair in ipairs(way) do
						for _, banned in ipairs({ "eyes", "scar", "tall", "face", "hair", "muscle", "fearless" }) do
							expect.falsy(pair[2]:lower():find(banned, 1, true), pair[2])
						end
					end
				end
			end
		end)

		t:it("routine events, levels and quests alone suggest nothing", function()
			local w = world()
			local ns = w.ns
			local char = w.char()
			for level = 2, 12 do
				ns.GameEvents.Record(char, "levelup", { level = level, zone = "Elwynn Forest" }, w.now())
			end
			for q = 1, 20 do
				ns.GameEvents.Record(char, "quest", { questId = q, title = "Quest " .. q, zone = "Elwynn Forest" },
					w.now())
			end
			w.PS.Generate(char, w.now(), { kind = "decision", reaction = { significance = 1 },
				record = { category = "quest", key = "quest:1", zone = "Elwynn Forest", meta = { title = "Quest 1" } } })
			w.PS.Generate(char, w.now(), { kind = "decision", reaction = { significance = 3 },
				record = { category = "levelup", key = "levelup:10", zone = "Elwynn Forest", meta = {} } })
			expect.equal(#w.waiting(), 0)
			expect.equal(char.profileSuggestions, nil)
		end)

		t:it("an established defining memory and an achieved goal can each suggest an entry", function()
			local w = world()
			local ns = w.ns
			local char = w.char()
			assert(ns.Memories.Add(char, { title = "Small memory", importance = 2 }, "player", w.now()))
			expect.equal(#w.waiting(), 0, "only a memory marked defining")
			local m = assert(ns.Memories.Add(char, { title = "The fall of the Light's Hope", importance = 3 }, "suggested",
				w.now()))
			expect.equal(#w.waiting(), 0, "a proposed memory is not established")
			assert(ns.Memories.Accept(char, m.id, w.now()))
			local s = w.waiting("glance")[1]
			expect.equal(s.key, "glance:memory:" .. m.id)
			expect.deepEqual(s.sources.memories, { m.id })
			expect.truthy(s.why[2]:find("private", 1, true))
			assert(w.PS.Dismiss(char, s.id, w.now()))
			local g = assert(ns.Goals.Add(char, { title = "Earn the Libram" }, w.now()))
			expect.equal(#w.waiting(), 0, "a new goal suggests no At First Glance entry")
			assert(ns.Goals.SetState(char, g.id, "achieved", w.now()))
			local gs = w.waiting("glance")[1]
			expect.equal(gs.text, "They have seen an aim through: Earn the Libram.")
		end)
	end)

	t:describe("nothing reaches Total RP 3 until the player approves", function()
		t:it("a waiting suggestion is never written; accepting adds the entry, and the guarded sync publishes it", function()
			local w = world()
			assert(w.Sync.SetOptIn(w.deps, "glance", true))
			w.approve("discipline", 1, 3)
			local s = w.waiting("glance")[1]
			local before = w.ns.Util.DeepCopy(w.misc())
			expect.equal(w.Sync.RunFeature(w.deps, "glance").state, "noop")
			expect.deepEqual(w.misc(), before, "Total RP 3 unchanged while it waits")
			local ok, message = w.PA.Accept(w.ctx, s.id)
			expect.truthy(ok, message)
			expect.truthy(message:find("At First Glance entry 1 saved in Dawnward", 1, true), message)
			expect.equal(s.status, "accepted")
			expect.equal(w.char().glance[1].title, "Growing discipline")
			expect.equal(w.Sync.RunFeature(w.deps, "glance").state, "written")
			expect.equal(w.misc().PE["1"].TI, "Growing discipline")
			expect.equal(w.misc().PE["1"].AC, true)
		end)

		t:it("Later and Dismiss change nothing; Edit accepts the player's own words", function()
			local w = world()
			w.approve("faith", 1, 3)
			local s = w.waiting("glance")[1]
			assert(w.PA.Postpone(w.ctx, s.id))
			expect.equal(#w.waiting(), 0, "postponed: out of sight for a day")
			expect.deepEqual(w.char().glance, {})
			w.later(DAY + 1)
			expect.equal(w.waiting()[1], s, "back after a day")
			local ok = w.PA.Accept(w.ctx, s.id, { title = "Quiet faith", text = "Prays before every journey." })
			expect.truthy(ok)
			expect.equal(s.status, "edited")
			expect.deepEqual(w.char().glance[1], { title = "Quiet faith", text = "Prays before every journey.",
				icon = "spell_arcane_mindmastery", active = true })
			expect.falsy(w.PA.Accept(w.ctx, s.id), "a settled suggestion cannot be accepted twice")
			local blank = world()
			blank.approve("faith", 1, 3)
			local b = blank.waiting("glance")[1]
			expect.falsy(blank.PA.Accept(blank.ctx, b.id, { title = "", text = "" }), "an empty edit is refused")
			expect.deepEqual(blank.char().glance, {})
		end)

		t:it("is refused in simulation mode, where the profile is not the real character's", function()
			local w = world()
			w.approve("honour", 1, 3)
			local s = w.waiting("glance")[1]
			w.deps.store:SetSimulation(true)
			local ok, message = w.PA.Accept(w.ctx, s.id)
			expect.falsy(ok)
			expect.truthy(message:find("simulation", 1, true))
			w.deps.store:SetSimulation(false)
			expect.equal(s.status, "pending")
		end)
	end)

	t:describe("Dawnward-owned entries are revised safely; the player's are never touched", function()
		t:it("stronger evidence revises the accepted entry in place, in Dawnward and in Total RP 3", function()
			local w = world()
			assert(w.Sync.SetOptIn(w.deps, "glance", true))
			w.approve("courage", 1, 3)
			assert(w.PA.Accept(w.ctx, w.waiting("glance")[1].id))
			w.Sync.RunFeature(w.deps, "glance")
			w.approve("courage", 1, 2)
			expect.equal(#w.waiting(), 0, "five steps: still the first tier, already accepted")
			w.approve("courage", 1, 1)
			local s = w.waiting("glance")[1]
			expect.equal(s.tier, 2)
			expect.deepEqual(s.target, { n = 1, revises = true })
			expect.truthy(w.PS.Effect(w.char(), s):find("Replaces Dawnward's At First Glance entry 1", 1, true))
			assert(w.PA.Accept(w.ctx, s.id))
			expect.equal(w.char().glance[1].title, "Steady resolve")
			expect.equal(w.char().glance[2], nil, "revised, not duplicated")
			expect.equal(w.Sync.RunFeature(w.deps, "glance").state, "written")
			expect.equal(w.misc().PE["1"].TI, "Steady resolve")
			expect.equal(w.misc().PE["2"], nil)
		end)

		t:it("an entry the player changed is theirs: a revision becomes a new entry instead", function()
			local w = world()
			w.approve("courage", 1, 3)
			assert(w.PA.Accept(w.ctx, w.waiting("glance")[1].id))
			assert(w.ns.Glance.Save(w.char(), 1, { title = "Growing resolve", text = "My own words now." }, w.now()))
			w.approve("courage", 1, 3)
			local s = w.waiting("glance")[1]
			expect.deepEqual(s.target, { n = 2 })
			assert(w.PA.Accept(w.ctx, s.id))
			expect.equal(w.char().glance[1].text, "My own words now.", "the player's entry is untouched")
			expect.equal(w.char().glance[2].title, "Steady resolve")
		end)

		t:it("with all five entries in use it waits, and never replaces one the player wrote", function()
			local w = world()
			for n = 1, 5 do assert(w.ns.Glance.Set(w.char(), n, "Mine " .. n, nil, 1)) end
			w.approve("discipline", -1, 3)
			expect.equal(#w.waiting(), 0, "no free entry and nothing of Dawnward's to revise: it waits")
			assert(w.ns.Glance.Clear(w.char(), 4, 1))
			w.approve("discipline", -1, 1)
			local s = w.waiting("glance")[1]
			expect.deepEqual(s.target, { n = 4 })
			assert(w.ns.Glance.Set(w.char(), 4, "Mine again", nil, 1))
			local ok, message = w.PA.Accept(w.ctx, s.id)
			expect.falsy(ok, "the free entry was taken meanwhile")
			expect.truthy(message:find("in use", 1, true), message)
			for n = 1, 5 do expect.truthy(w.char().glance[n].title:find("Mine", 1, true)) end
		end)

		t:it("slots the player filled in Total RP 3 stay as they are", function()
			local w = world()
			local own = { TI = "Player's scar", TX = "Across the jaw.", IC = "inv_misc_bone_01", AC = true }
			w.misc().PE = { ["1"] = own }
			assert(w.Sync.SetOptIn(w.deps, "glance", true))
			w.approve("honour", 1, 3)
			assert(w.PA.Accept(w.ctx, w.waiting("glance")[1].id))
			expect.equal(w.Sync.RunFeature(w.deps, "glance").state, "written")
			expect.deepEqual(w.misc().PE["1"], own)
			expect.equal(w.misc().PE["2"].TI, "Firmer principles", "a free slot")
		end)
	end)

	t:describe("duplicates, dismissals and persistence", function()
		t:it("the same development is offered once; a dismissal holds until the evidence grows", function()
			local w = world()
			w.approve("courage", 1, 3)
			for _ = 1, 3 do w.PS.Generate(w.char(), w.now(), { kind = "change" }) end
			expect.equal(#w.char().profileSuggestions.list, 1, "never several for one development")
			local s = w.waiting("glance")[1]
			assert(w.PA.Dismiss(w.ctx, s.id))
			w.approve("courage", 1, 2)
			expect.equal(#w.waiting(), 0, "dismissed: not offered again at the same strength")
			w.approve("courage", 1, 1)
			local again = w.waiting("glance")[1]
			expect.truthy(again, "materially new evidence (the second tier)")
			expect.equal(again.tier, 2)
		end)

		t:it("accept, edit, postpone and dismiss survive a save and load", function()
			local w = world()
			local ns = w.ns
			w.approve("courage", 1, 3)
			local a = w.waiting("glance")[1]
			assert(w.PA.Accept(w.ctx, a.id))
			w.approve("faith", 1, 3)
			local d = w.waiting("glance")[1]
			assert(w.PA.Dismiss(w.ctx, d.id))
			w.approve("honour", 1, 3)
			local p = w.waiting("glance")[1]
			assert(w.PA.Postpone(w.ctx, p.id))
			local raw = ns.Util.DeepCopy(w.char())
			raw.profileSuggestions.list[1].junk = true
			raw.profileSuggestions.keys["bad|key"] = { status = "dismissed" }
			local loaded = ns.Schema.NormalizeCharacter(raw)
			expect.deepEqual(loaded.profileSuggestions, ns.Schema.NormalizeCharacter(loaded).profileSuggestions,
				"stable when loaded again")
			local byId = {}
			for _, s in ipairs(loaded.profileSuggestions.list) do byId[s.id] = s end
			expect.equal(byId[a.id].status, "accepted")
			expect.equal(byId[d.id].status, "dismissed")
			expect.equal(byId[p.id].status, "postponed")
			expect.equal(byId[p.id].laterUntil, p.laterUntil)
			expect.equal(loaded.profileSuggestions.keys["glance:axis:faith:up"].status, "dismissed")
			expect.equal(loaded.profileSuggestions.keys["bad|key"], nil)
			expect.equal(byId[a.id].junk, nil)
			-- After loading, the dismissed theme is still not offered again.
			w.deps.store.real.characters[KEY] = loaded
			w.approve("faith", 1, 1)
			for _, s in ipairs(w.waiting()) do expect.falsy(s.key:find("faith", 1, true)) end
		end)

		t:it("a personal backup keeps them (dismissals too); a shared export never carries them", function()
			local w = world()
			local T = w.ns.Transfer
			w.approve("courage", 1, 3)
			local s = w.waiting("glance")[1]
			assert(w.PA.Dismiss(w.ctx, s.id))
			local char = w.char()
			local decoded = assert(T.Decode(assert(T.Export(char, T.KIND_BACKUP))))
			expect.equal(decoded.character.profileSuggestions.keys["glance:axis:courage:up"].status, "dismissed")
			local older = w.ns.Util.DeepCopy(decoded.character)
			older.profileSuggestions = nil
			local merged = T.MergeForImport(char, older, true, w.now(), true, true)
			expect.equal(merged.profileSuggestions.keys["glance:axis:courage:up"].status, "dismissed",
				"an older backup keeps the current ones")
			local shared = assert(T.Decode(assert(T.Export(char, T.KIND_SHARE))))
			expect.equal(shared.character.profileSuggestions, nil)
		end)

		t:it("keeps at most a bounded number, dropping old settled ones first", function()
			local w = world()
			local char = w.char()
			local store = w.PS.Store(char)
			for i = 1, w.PS.LIMITS.list + 10 do
				store.list[#store.list + 1] = { id = i, kind = "currently", key = "k" .. i, theme = "k" .. i, tier = 1,
					status = i == 3 and "pending" or "dismissed", text = "T" .. i, target = {}, why = {},
					sources = {}, createdAt = i }
			end
			local clean = w.PS.Clean(store)
			expect.equal(#clean.list, w.PS.LIMITS.list)
			expect.equal(clean.list[1].id, 3, "a waiting one is kept")
			expect.equal(clean.list[#clean.list].id, w.PS.LIMITS.list + 10, "the newest settled ones are kept")
		end)
	end)

	t:describe("Currently modes", function()
		local function zone(w, name)
			return w.ns.GameEvents.Record(w.char(), "zone", { zone = name, visit = "first" }, w.now())
		end

		t:it("Manual (the default) suggests nothing; Suggested offers a text from verified facts", function()
			local w = world()
			local char = w.char()
			expect.equal(w.ns.RPStatus.CurrentlyMode(char), "manual")
			w.PS.Generate(char, w.now(), { kind = "zone", record = zone(w, "Westfall") })
			expect.equal(#w.waiting(), 0, "Manual: nothing")
			assert(w.PA.SetCurrentlyMode(w.ctx, "suggested"))
			w.PS.Generate(char, w.now(), { kind = "zone", record = zone(w, "Redridge Mountains") })
			local s = w.waiting("currently")[1]
			expect.equal(s.text, "In Redridge Mountains.")
			expect.truthy(s.why[1]:find("first recorded visit to Redridge Mountains", 1, true))
			expect.equal(char.trp3status.currently, nil, "Suggested changes nothing by itself")
			assert(w.PA.Accept(w.ctx, s.id, { text = "Scouting Redridge for the Watch." }))
			expect.equal(char.trp3status.currently, "Scouting Redridge for the Watch.")
		end)

		t:it("a new goal and a major answered moment are triggers; routine ones are not", function()
			local w = world()
			local char = w.char()
			assert(w.PA.SetCurrentlyMode(w.ctx, "suggested"))
			local g = assert(w.ns.Goals.Add(char, { title = "Find my brother" }, w.now()))
			local s = w.waiting("currently")[1]
			expect.equal(s.text, "Working towards: Find my brother.")
			expect.deepEqual(s.sources.goals, { g.id })
			expect.truthy(s.private, "the goal is private in Dawnward")
			w.later(w.PS.CURRENTLY_COOLDOWN + 1)
			w.PS.Generate(char, w.now(), { kind = "decision", decision = { id = 4 }, reaction = { significance = 3 },
				record = { category = "quest", key = "quest:155", zone = "Westfall",
					meta = { title = "The Defias Brotherhood" } } })
			local m = w.waiting("currently")[1]
			expect.equal(m.text, "In Westfall. Recently completed The Defias Brotherhood. Working towards: Find my "
				.. "brother.")
			expect.equal(s.status, "superseded", "one Currently suggestion waits at a time")
			w.later(w.PS.CURRENTLY_COOLDOWN + 1)
			w.PS.Generate(char, w.now(), { kind = "decision", reaction = { significance = 2 },
				record = { category = "quest", key = "quest:156", zone = "Westfall", meta = { title = "Routine" } } })
			w.PS.Generate(char, w.now(), { kind = "decision", reaction = { significance = 3 },
				record = { category = "death", key = "death:1", zone = "Westfall", meta = {} } })
			expect.equal(w.waiting("currently")[1], m, "not a major moment, or not a verified fact to tell")
		end)

		t:it("waits out a cooldown and never repeats a text", function()
			local w = world()
			local char = w.char()
			assert(w.PA.SetCurrentlyMode(w.ctx, "suggested"))
			w.PS.Generate(char, w.now(), { kind = "zone", record = zone(w, "Duskwood") })
			local first = w.waiting("currently")[1]
			w.PS.Generate(char, w.now(), { kind = "zone", record = zone(w, "Darkshire") })
			expect.equal(w.waiting("currently")[1], first, "inside the cooldown")
			assert(w.PA.Accept(w.ctx, first.id))
			w.later(w.PS.CURRENTLY_COOLDOWN + 1)
			char.profileSuggestions.keys["currently:zone:Duskwood"] = nil
			w.PS.Generate(char, w.now(), { kind = "zone", record = { category = "zone", key = "zone:Duskwood",
				zone = "Duskwood" } })
			expect.equal(#w.waiting("currently"), 0, "the same text again: never")
		end)

		t:it("Automatic needs the player's confirmation; existing characters stay Manual", function()
			local w = world()
			local char = w.char()
			char.trp3status.currently = "My own Currently"
			local raw = w.ns.Util.DeepCopy(char)
			expect.equal(w.ns.RPStatus.CurrentlyMode(w.ns.Schema.NormalizeCharacter(raw)), "manual")
			local ok, message = w.PA.SetCurrentlyMode(w.ctx, "automatic")
			expect.falsy(ok)
			expect.truthy(message:find("confirmation", 1, true), message)
			expect.equal(w.ns.RPStatus.CurrentlyMode(char), "manual")
			assert(w.PA.SetCurrentlyMode(w.ctx, "automatic", true))
			expect.equal(w.ns.RPStatus.CurrentlyMode(char), "automatic")
			expect.equal(w.ns.RPStatus.CurrentlyMode(w.ns.Schema.NormalizeCharacter(w.ns.Util.DeepCopy(char))),
				"automatic", "kept across a reload")
			expect.equal(w.ns.RPStatus.Get(char).currentlyMode, nil, "a setting, never a value for Total RP 3")
			assert(w.PA.SetCurrentlyMode(w.ctx, "manual"))
			expect.equal(char.trp3status.currentlyMode, nil)
		end)
	end)

	t:describe("Automatic Currently: only while Dawnward owns it without a conflict, and always recoverable", function()
		local function setup()
			local w = world()
			local char = w.char()
			assert(w.ns.TRP3Commands.SetStatus(w.ctx, "currently", "Resting in Goldshire."))
			assert(w.Sync.SetPolicy(w.deps, "currently", "dawnward"))
			expect.equal(w.Sync.RunFeature(w.deps, "status").state, "written")
			assert(w.PA.SetCurrentlyMode(w.ctx, "automatic", true))
			return w, char
		end

		local function enter(w, name)
			local record = w.ns.GameEvents.Record(w.char(), "zone", { zone = name, visit = "first" }, w.now())
			return w.PA.OnLocation(w.ctx, w.char(), { { record = record } })
		end

		t:it("updates Dawnward's Currently by itself; the guarded sync publishes it; Undo restores it", function()
			local w, char = setup()
			local s = enter(w, "Westfall")
			expect.equal(s.status, "auto")
			expect.equal(char.trp3status.currently, "In Westfall.")
			expect.equal(w.Sync.RunFeature(w.deps, "status").state, "written")
			expect.equal(w.ch().CU, "In Westfall.")
			local ok, message = w.PA.UndoAutomatic(w.ctx)
			expect.truthy(ok, message)
			expect.equal(char.trp3status.currently, "Resting in Goldshire.")
			expect.equal(s.status, "undone")
			w.Sync.RunFeature(w.deps, "status")
			expect.equal(w.ch().CU, "Resting in Goldshire.")
			expect.falsy(w.PA.UndoAutomatic(w.ctx), "nothing left to undo")
			-- The backup taken before the automatic write is there too.
			local sections = {}
			for _, b in ipairs(w.deps.ledger.backups) do sections[#sections + 1] = b.section end
			expect.truthy(#sections >= 2)
		end)

		t:it("a Total RP 3 edit or conflict blocks it; the suggestion waits for the player with the reason", function()
			local w, char = setup()
			w.fake.env.AddOn_TotalRP3.Player.GetCurrentUser():SetCurrentlyText("Typed in Total RP 3")
			local s = enter(w, "Westfall")
			expect.equal(s.status, "pending")
			expect.truthy(s.held:find("Total RP 3 shows a Currently text you wrote", 1, true), s.held)
			expect.equal(char.trp3status.currently, "Resting in Goldshire.")
			expect.equal(w.Sync.RunFeature(w.deps, "status").state, "conflict")
			expect.equal(w.ch().CU, "Typed in Total RP 3", "never overwritten")
			w.later(w.PS.CURRENTLY_COOLDOWN + 1)
			local s2 = enter(w, "Duskwood")
			expect.truthy(s2.held:find("conflict", 1, true), s2.held)
			expect.equal(w.ch().CU, "Typed in Total RP 3")
		end)

		t:it("never replaces a Currently the player wrote in Dawnward after turning Automatic on", function()
			local w, char = setup()
			assert(w.ns.TRP3Commands.SetStatus(w.ctx, "currently", "On watch tonight."))
			w.Sync.RunFeature(w.deps, "status")
			local s = enter(w, "Westfall")
			expect.equal(s.status, "pending")
			expect.truthy(s.held:find("you wrote your own Currently", 1, true), s.held)
			expect.equal(char.trp3status.currently, "On watch tonight.")
		end)

		t:it("does nothing when Currently is not kept in sync, in simulation, or for a private goal", function()
			local w = world()
			local char = w.char()
			assert(w.PA.SetCurrentlyMode(w.ctx, "automatic", true))
			local s = enter(w, "Westfall")
			expect.equal(s.status, "pending")
			expect.truthy(s.held:find("does not keep your Currently in sync", 1, true), s.held)
			expect.equal(char.trp3status.currently, nil)
			local g = assert(w.ns.Goals.Add(char, { title = "Secret vow" }, w.now()))
			local gs = w.waiting("currently")[1]
			expect.deepEqual(gs.sources.goals, { g.id })
			expect.truthy(w.PS.AutoBlocked(char, gs):find("private goal", 1, true))
			w.deps.store:SetSimulation(true)
			expect.equal(w.PA.CurrentlyGate(w.ctx), "simulation mode is on")
			w.deps.store:SetSimulation(false)
			expect.equal(#w.fake.setterLog, 0, "Total RP 3 never touched")
		end)
	end)

	t:describe("migration: a realistic level-6 character from 0.10.1", function()
		-- Built the way 0.10.1 stored it: decisions, approved personality
		-- changes, an established memory, a goal, glance entries and a
		-- Currently value, with no profile suggestions and no Currently mode.
		local function level6(ns)
			local raw = ns.Schema.NewCharacter(1700000000)
			raw.fields.name = { value = "Kyssarra Dawnward", visibility = "public" }
			raw.fields.pronouns = { value = "she/her", visibility = "public" }
			raw.personality.courage = { value = 12, visibility = "public", updatedAt = 1700100000 }
			raw.personality.faith = { value = 11, visibility = "public", updatedAt = 1700100000 }
			local story = raw.story
			story.nextId = 40
			story.baselines = { courage = 10, faith = 10 }
			for i, key in ipairs({ "zone:Elwynn Forest", "levelup:2", "quest:7", "levelup:5", "quest:33" }) do
				story.events[#story.events + 1] = { category = key:match("^(%a+)"), key = key, at = 1700000000 + i,
					status = "resolved", significance = 1, confidence = "verified", source = "TEST", meta = {},
					zone = "Elwynn Forest", level = i + 1 }
				story.eventKeys[key] = 1700000000 + i
			end
			for i = 1, 3 do
				story.decisions[#story.decisions + 1] = { id = 10 + i, category = "quest", eventKeys = { "quest:7" },
					templateId = "quest-generic", optionId = "brave", phrase = "stood firm", theme = "courage",
					at = 1700000100 + i, effects = { courage = 1 } }
			end
			story.changes = {
				{ id = 20, axis = "courage", delta = 1, reason = "Kyssarra stood firm", decisionId = 11,
					status = "applied", at = 1700000101, decidedAt = 1700000101, from = 10, to = 11 },
				{ id = 21, axis = "courage", delta = 1, reason = "Kyssarra stood firm", decisionId = 12,
					status = "applied", at = 1700090000, decidedAt = 1700090000, from = 11, to = 12 },
				{ id = 22, axis = "faith", delta = 1, reason = "Kyssarra prayed", decisionId = 13,
					status = "applied", at = 1700090001, decidedAt = 1700090001, from = 10, to = 11 },
			}
			story.memories[1] = { id = 30, provenance = "suggested", status = "established", visibility = "private",
				title = "Northshire Abbey", text = "Kyssarra stood firm.", tags = { "courage" }, importance = 2,
				at = 1700000101, links = { events = { "quest:7" }, decisions = { 11 }, journal = {} } }
			story.goals[1] = { id = 31, provenance = "player", status = "established", visibility = "private",
				title = "Join the Silver Hand", state = "active", milestones = {}, at = 1700000200 }
			raw.glance[1] = { title = "Tabard", text = "Northshire colours.", icon = "inv_shirt_guildtabard_01",
				active = true }
			raw.glance[2] = { title = "Holy symbol", active = true }
			raw.trp3status = { currently = "Training at Northshire Abbey.", ooc = "New to RP, say hi!", style = {} }
			return raw
		end

		t:it("loads unchanged, stays Manual, and suggests or publishes nothing by itself", function()
			local w = world()
			local ns = w.ns
			local raw = level6(ns)
			local loaded = ns.Schema.NormalizeCharacter(ns.Util.DeepCopy(raw))
			local again = ns.Schema.NormalizeCharacter(ns.Util.DeepCopy(loaded))
			expect.deepEqual(again, loaded, "loading is stable")
			expect.equal(loaded.profileSuggestions, nil, "no new table for a character that never had a suggestion")
			expect.deepEqual(loaded.glance, raw.glance)
			expect.deepEqual(loaded.trp3status, raw.trp3status)
			expect.equal(#loaded.story.changes, 3)
			expect.equal(#loaded.story.decisions, 3)
			expect.equal(loaded.story.memories[1].title, "Northshire Abbey")
			expect.equal(ns.RPStatus.CurrentlyMode(loaded), "manual")
			w.deps.store.real.characters[KEY] = loaded
			-- Sync for At First Glance and Currently, as the owner had it.
			assert(w.Sync.SetOptIn(w.deps, "glance", true))
			assert(w.Sync.SetPolicy(w.deps, "currently", "dawnward"))
			w.Sync.Run(w.deps)
			local published = ns.Util.DeepCopy(w.fake.snapshot())
			local setters = #w.fake.setterLog
			-- Playing on: a new zone, a routine quest, a level. Nothing new is published.
			local record = ns.GameEvents.Record(loaded, "zone", { zone = "Westfall", visit = "first" }, w.now())
			w.PA.OnLocation(w.ctx, loaded, { { record = record } })
			ns.GameEvents.Record(loaded, "levelup", { level = 7, zone = "Westfall" }, w.now())
			w.Sync.Run(w.deps)
			expect.deepEqual(w.fake.snapshot(), published, "no unsolicited publication")
			expect.equal(#w.fake.setterLog, setters)
			expect.equal(loaded.profileSuggestions, nil, "Manual: no Currently suggestion either")
			-- The next approved step toward Bold is the third: a suggestion, waiting.
			w.later(1700200000)
			local c = assert(ns.Evolution.Propose(loaded, "courage", 1, "Kyssarra stood firm", 14, w.now()))
			assert(ns.Evolution.Apply(loaded, c.id, w.now()))
			local s = w.waiting("glance")[1]
			expect.equal(s.text, "Kyssarra Dawnward carries an increasingly steady determination, readier to step "
				.. "forward than before.")
			expect.deepEqual(s.target, { n = 3 }, "the next free entry; the player's two are untouched")
			w.Sync.Run(w.deps)
			expect.deepEqual(w.fake.snapshot().player.misc, published.player.misc, "still nothing until accepted")
		end)
	end)
end
