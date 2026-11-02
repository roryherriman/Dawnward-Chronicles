-- L2 (v0.9): At First Glance entries the player writes for Total RP 3, the
-- game's own race and class, additional-information icons and names, and
-- the personality direction, against the TRP3 3.4.1 fake (mocked; not
-- in-game evidence). Data shapes are copied from the TRP3 3.4.1 source
-- (tag 3.4.1, commit 4c25cb0); each test names the file it follows.
local Loader = require("support.loader")
local Boot = require("support.boot")
local Fake = require("fakes.trp3_341")

return function(t, expect)
	local KEY = "Testchar-TestRealm"

	local function world(fakeOpts)
		local ns = Loader.WithTRP3()
		local fake = Fake.new(fakeOpts or {})
		fake.env.UnitName = function() return "Testchar" end
		fake.env.UnitRace = function() return "Human", "Human", 1 end
		fake.env.UnitClass = function() return "Paladin", "PALADIN", 2 end
		local store = ns.Store.new(ns.Schema.NewDatabase(), ns.Schema.NewDatabase())
		local clock = 1000
		local deps = {
			env = fake.env, ledger = ns.TRP3Ledger.New(), store = store, characterKey = KEY,
			now = function() clock = clock + 1; return clock end,
			inCombat = function() return false end,
		}
		local w = { ns = ns, fake = fake, deps = deps, Sync = ns.TRP3Sync, Glance = ns.Glance }
		function w.char() return assert(store:EnsureCharacter(KEY, 1)) end
		function w.glance(n, title, text) return assert(ns.Glance.Set(w.char(), n, title, text, 1)) end
		function w.field(key, value, level)
			assert(ns.Character.SetField(w.char(), key, value, 1))
			assert(ns.Character.SetFieldVisibility(w.char(), key, level or "public", 1))
		end
		function w.manage(...)
			for _, id in ipairs({ ... }) do assert(w.Sync.SetPolicy(deps, id, "dawnward")) end
		end
		function w.run(feature) return w.Sync.RunFeature(deps, feature) end
		function w.misc() return fake.profile.player.misc end
		function w.ch() return fake.profile.player.characteristics end
		function w.record() return deps.ledger.profiles[fake.profileId] end
		return w
	end

	t:describe("At First Glance store (Core/Glance.lua)", function()
		t:it("keeps only what the player wrote, cleaned, in five numbered entries", function()
			local w = world()
			local char = w.char()
			expect.deepEqual(char.glance, {}, "a new character has none")
			expect.falsy(w.Glance.Set(char, 6, "Too many"), "TRP3 has five slots")
			expect.falsy(w.Glance.Set(char, 1, "  ", ""), "a title or a text is needed")
			local e = w.glance(2, "Silver |cffff0000scar|r", "Across the jaw.||nOld.")
			expect.deepEqual(e, { title = "Silver scar", text = "Across the jaw.\nOld.", active = true })
			assert(w.Glance.SetIcon(char, 2, "inv_misc_bone_01", 1))
			expect.falsy(w.Glance.SetIcon(char, 2, "|Tbad|t", 1), "an icon is a plain icon name")
			assert(w.Glance.SetActive(char, 2, false, 1))
			expect.deepEqual(w.Glance.Published(char), { { n = 2, TI = "Silver scar", TX = "Across the jaw.\nOld.",
				IC = "inv_misc_bone_01", AC = false } })
			-- Survives a save and load; junk is dropped.
			local raw = w.ns.Util.DeepCopy(char)
			raw.glance[3] = { title = 7 }
			raw.glance[9] = { title = "out of range" }
			local loaded = w.ns.Schema.NormalizeCharacter(raw)
			expect.deepEqual(loaded.glance, { [2] = char.glance[2] })
			assert(w.Glance.Clear(char, 2, 1))
			expect.deepEqual(w.Glance.Published(char), {})
		end)

		t:it("reads the game's race and class for display, guarding missing client functions", function()
			local ns = Loader.WithTRP3()
			local env = { UnitRace = function() return "Human", "Human", 1 end,
				UnitClass = function() return "Paladin", "PALADIN", 2 end }
			expect.equal(ns.Character.GameValue("race", env), "Human")
			expect.equal(ns.Character.GameValue("class", env), "Paladin")
			expect.equal(ns.Character.GameValue("age", env), nil, "the game does not know an age")
			expect.equal(ns.Character.GameValue("firstName", env), nil, "UnitName missing: nothing")
			expect.equal(ns.Character.GameValue("race", { UnitRace = function() error("no") end }), nil)
			local char = { fields = { race = { value = "Quel'dorei", visibility = "private" } } }
			expect.deepEqual({ ns.Character.FieldOrGame(char, "race", env) }, { "Quel'dorei", "player" })
			expect.deepEqual({ ns.Character.FieldOrGame(char, "class", env) }, { "Paladin", "game" })
			-- The WoW mock's own UnitRace/UnitClass, through the default (global) environment.
			local mock, _, booted = Boot.Load({})
			expect.equal(booted.Character.GameValue("race"), mock.env.UnitRace("player"))
			expect.equal(booted.Character.GameValue("class"), "Mage")
		end)
	end)

	t:describe("TRP3 At First Glance sync (glance)", function()
		t:it("writes the player's entries into free slots exactly as TRP3's editor stores them", function()
			-- RegisterMisc.lua: default misc { v = 1, PE = {}, ST = {} }; a slot is
			-- { IC, AC, TI, TX } under tostring(slot) (applyPeekSlot).
			local w = world({ misc = { v = 7, PE = {}, ST = { ["2"] = 1 } } })
			w.glance(1, "Silver scar", "Across the jaw.")
			w.glance(3, "Holy symbol")
			expect.equal(w.Sync.Check(w.deps, "glance").state, "off", "nothing until the player turns it on")
			assert(w.Sync.SetOptIn(w.deps, "glance", true))
			local r = w.run("glance")
			expect.equal(r.state, "written", r.message)
			local misc = w.misc()
			expect.deepEqual(misc.PE, {
				["1"] = { TI = "Silver scar", TX = "Across the jaw.", IC = "inv_misc_questionmark", AC = true },
				["3"] = { TI = "Holy symbol", IC = "inv_misc_questionmark", AC = true },
			})
			expect.deepEqual(misc.ST, { ["2"] = 1 }, "the RP style is never changed")
			expect.equal(misc.v, 9, "two version steps, as for every Dawnward write (Shape.DawnwardVersion)")
			local event = w.fake.events[#w.fake.events]
			expect.deepEqual(event.args, { w.fake.playerId, w.fake.profileId, "misc" },
				"REGISTER_DATA_UPDATED as applyPeekSlot fires it")
			expect.deepEqual(w.fake.remoteRefetch({ about = 2, characteristics = 3, misc = 7 }), { "misc" })
			expect.equal(w.run("glance").state, "noop", "no churn")
			expect.equal(w.misc().v, 9)
		end)

		t:it("never writes over the player's own slots, and never adds an entry twice", function()
			local own = { TI = "Tabard", TX = "Argent Dawn colours.", IC = "inv_shirt_guildtabard_01", AC = true }
			local w = world({ misc = { v = 1, PE = { ["1"] = own, ["2"] = { IC = "spell_holy_holybolt", AC = false } },
				ST = {} } })
			w.glance(1, "Silver scar")
			w.glance(2, "Tabard", "Argent Dawn colours.")
			assert(w.Sync.SetOptIn(w.deps, "glance", true))
			expect.equal(w.run("glance").state, "written")
			local pe = w.misc().PE
			expect.deepEqual(pe["1"], own, "the player's slot is untouched")
			expect.deepEqual(pe["2"], { IC = "spell_holy_holybolt", AC = false }, "an icon-only slot is the player's")
			expect.equal(pe["3"].TI, "Silver scar", "entry 1 went to the first free slot")
			expect.falsy(pe["4"], "the Tabard entry is already shown: not added again")
			expect.deepEqual(w.record().glance.slots["3"].n, 1)
			-- The ledger is lost (an older build): still nothing is duplicated.
			w.record().glance = nil
			expect.equal(w.run("glance").state, "noop")
			expect.falsy(w.misc().PE["4"])
		end)

		t:it("waits when every slot is the player's, and while TRP3's glance editor is open", function()
			local pe = {}
			for i = 1, 5 do pe[tostring(i)] = { TI = "Own " .. i, AC = true, IC = "inv_misc_questionmark" } end
			local w = world({ misc = { v = 1, PE = pe, ST = {} } })
			w.glance(1, "Silver scar")
			assert(w.Sync.SetOptIn(w.deps, "glance", true))
			local before = w.fake.snapshot()
			local check = w.Sync.Check(w.deps, "glance")
			expect.equal(check.state, "blocked")
			expect.truthy(check.reasons[1]:find("every At First Glance slot", 1, true), check.reasons[1])
			expect.equal(w.run("glance").state, "blocked")
			expect.deepEqual(w.fake.snapshot(), before)
			expect.falsy(w.record().conflicts.glance, "not a conflict: it writes once a slot is free")
			-- The player frees one, then opens the editor: deferred until it closes.
			w.misc().PE["5"] = nil
			w.fake.openGlanceEditor()
			expect.equal(w.Sync.Check(w.deps, "glance").state, "deferred")
			w.fake.closeGlanceEditor()
			expect.equal(w.run("glance").state, "written")
			expect.equal(w.misc().PE["5"].TI, "Silver scar")
		end)

		t:it("updates and removes only its own slots, mirrors the active box, and pauses on a hand edit", function()
			local w = world()
			w.glance(1, "Silver scar", "Across the jaw.")
			w.glance(2, "Holy symbol")
			assert(w.Sync.SetOptIn(w.deps, "glance", true))
			expect.equal(w.run("glance").state, "written")
			w.glance(1, "Silver scar", "Across the jaw, healed.")
			assert(w.Glance.SetActive(w.char(), 2, false, 2))
			expect.equal(w.run("glance").state, "written")
			expect.equal(w.misc().PE["1"].TX, "Across the jaw, healed.")
			expect.equal(w.misc().PE["2"].AC, false, "hidden, as TRP3's active box")
			-- getMiscExchangeData: an inactive slot is never sent to others.
			expect.falsy(w.fake.miscExchange().PE["2"])
			assert(w.Glance.Clear(w.char(), 2, 3))
			expect.equal(w.run("glance").state, "written")
			expect.falsy(w.misc().PE["2"], "Dawnward's own slot is emptied")
			-- The player edits Dawnward's slot in TRP3 (applyPeekSlot): a conflict.
			w.fake.applyPeekSlot("1", "inv_misc_questionmark", true, "Silver scar", "My own words.")
			w.glance(1, "Silver scar", "Across the jaw, faded.")
			local before = w.fake.snapshot()
			local r = w.run("glance")
			expect.equal(r.state, "conflict")
			expect.deepEqual(w.fake.snapshot(), before, "nothing written")
			expect.truthy(w.record().conflicts.glance)
			assert(w.Sync.Resolve(w.deps, "glance", "keep"))
			expect.equal(w.ns.TRP3Ledger.Policy(w.deps.ledger.optIn[KEY], "glance"), "off")
			expect.equal(w.misc().PE["1"].TX, "My own words.")
		end)

		t:it("releases its slots, and rolls the misc section back with the player's slots kept", function()
			local own = { TI = "Tabard", IC = "inv_misc_questionmark", AC = true }
			local w = world({ misc = { v = 1, PE = { ["1"] = own }, ST = {} } })
			w.glance(1, "Silver scar")
			assert(w.Sync.SetOptIn(w.deps, "glance", true))
			expect.equal(w.run("glance").state, "written")
			local backup = w.deps.ledger.backups[#w.deps.ledger.backups]
			expect.equal(backup.section, "misc")
			expect.equal(backup.ownerFeature, "glance")
			-- Rollback "own": the backup without Dawnward's part, rebuilt from now.
			w.glance(1, "Silver scar, fading")
			assert(w.Sync.Rollback(w.deps, backup.id, "own"))
			expect.deepEqual(w.misc().PE["1"], own)
			expect.equal(w.misc().PE["2"].TI, "Silver scar, fading")
			-- Release: Dawnward's slots go, the player's stay.
			assert(w.Sync.Release(w.deps, "glance"))
			expect.deepEqual(w.misc().PE, { ["1"] = own })
			expect.equal(w.ns.TRP3Ledger.Policy(w.deps.ledger.optIn[KEY], "glance"), "off")
		end)

		t:it("refuses a misc section with an unexpected layout", function()
			local w = world({ misc = { v = 1, PE = { [1] = { TI = "numeric key" } }, ST = {} } })
			w.glance(1, "Silver scar")
			assert(w.Sync.SetOptIn(w.deps, "glance", true))
			local check = w.Sync.Check(w.deps, "glance")
			expect.equal(check.state, "blocked")
			expect.truthy(check.reasons[1]:find("unexpected layout", 1, true))
			expect.falsy(w.ns.TRP3Shape.Misc({ v = 1, PE = { ["1"] = { AC = "yes" } } }))
			expect.truthy(w.ns.TRP3Shape.Misc({ v = 1, PE = { ["1"] = {} } }), "a swapped empty slot is fine")
		end)
	end)

	t:describe("TRP3 characteristics audit (v0.9)", function()
		t:it("puts the game's race back when Dawnward takes its own race out, without owning it", function()
			-- RegisterCharacteristics.lua default profile: RA = Globals.player_race_loc (UnitRace).
			local w = world({ characteristics = { v = 3, FN = "Testchar", RA = "Human", CL = "Paladin", PS = {} } })
			w.field("race", "Quel'dorei")
			w.manage("race", "class")
			expect.equal(w.run("fields").state, "written")
			expect.equal(w.ch().RA, "Quel'dorei")
			expect.equal(w.ch().CL, "Paladin", "no class written: the game's stays")
			w.field("race", "Quel'dorei", "private")
			local r = w.run("fields")
			expect.equal(r.state, "written", r.message)
			expect.equal(w.ch().RA, "Human", "back to the game's race, not left empty")
			expect.falsy(w.record().fields, "the game's value is never Dawnward's")
			expect.equal(w.run("fields").state, "noop")
			-- The player empties race in TRP3 themselves: never refilled.
			w.ch().RA = nil
			expect.equal(w.run("fields").state, "noop")
			expect.equal(w.ch().RA, nil)
		end)

		t:it("recognises a preset entry TRP3 typed by its localized name, instead of adding another", function()
			-- ProfileUtil.lua GetMiscInfoTypeByName: an entry without ID is typed by
			-- its English or localized name.
			local w = world({ characteristics = { v = 3, PS = {}, MI = { { NA = "Pronomen", VA = "sie/ihr" } } } })
			local real = w.fake.env.TRP3_API.GetMiscTypeInfo
			w.fake.env.TRP3_API.GetMiscTypeInfo = function(miscType)
				local info = real(miscType)
				if miscType == 7 then info.localizedName = "Pronomen" end
				return info
			end
			w.field("pronouns", "she/her")
			w.manage("pronouns")
			expect.equal(w.run("misc").state, "conflict")
			expect.equal(#w.ch().MI, 1, "not duplicated")
			expect.equal(w.ch().MI[1].VA, "sie/ihr")
		end)

		t:it("maps every axis to TRP3's bar the right way round (V2 = points toward the left trait)", function()
			-- RegisterCharacteristics.lua refreshPsycho: leftCount = V2, rightCount =
			-- PSYCHO_MAX_VALUE_V2 (20, Globals.lua) - V2; MSP/Fields.lua sends V2 / 20.
			local TraitPlan = Loader.WithTRP3().TRP3TraitPlan
			local axes = Loader.WithTRP3().Schema.PERSONALITY_AXES
			local pairsSeen = {}
			for _, axis in ipairs(axes) do pairsSeen[#pairsSeen + 1] = axis.left .. "/" .. axis.right end
			expect.deepEqual(pairsSeen, { "Cautious/Bold", "Hard-hearted/Compassionate", "Impulsive/Disciplined",
				"Sceptical/Devout", "Pragmatic/Principled", "Reserved/Outgoing" })
			for value = 0, 20 do
				local v2 = TraitPlan.ToTRP3(value)
				expect.equal(v2, 20 - value)
				expect.equal(TraitPlan.FromTRP3(v2), value)
			end
			local desired = TraitPlan.Desired({ personality = { sociability = { value = 0 }, faith = { value = 20 },
				honour = { value = 10 } } })
			expect.deepEqual(desired.sociability, { LT = "Reserved", RT = "Outgoing", V2 = 20 }, "fully Reserved")
			expect.deepEqual(desired.faith, { LT = "Sceptical", RT = "Devout", V2 = 0 }, "fully Devout")
			expect.equal(desired.honour.V2, 10, "the middle is TRP3's default (PSYCHO_DEFAULT_VALUE_V2)")
		end)

		t:it("gives its new traits TRP3's default icons and keeps an icon the player chose", function()
			-- RegisterCharacteristics.lua psychoAdd("new"): LI = RI = "INV_Misc_QuestionMark".
			local w = world()
			w.ns.Personality.Set(w.char(), "courage", 4)
			w.ns.Personality.SetVisibility(w.char(), "courage", "public")
			assert(w.Sync.SetOptIn(w.deps, "traits", true))
			expect.equal(w.run("traits").state, "written")
			local trait = w.ch().PS[1]
			expect.deepEqual(trait, { LT = "Cautious", LI = "INV_Misc_QuestionMark", RT = "Bold",
				RI = "INV_Misc_QuestionMark", V2 = 16 })
			trait.LI = "spell_holy_auraoflight"
			expect.equal(w.run("traits").state, "noop", "an icon is never compared")
			w.ns.Personality.Set(w.char(), "courage", 12)
			expect.equal(w.run("traits").state, "written")
			expect.equal(w.ch().PS[1].V2, 8)
			expect.equal(w.ch().PS[1].LI, "spell_holy_auraoflight", "the player's icon stays")
		end)
	end)

	-- The whole addon under the WoW mock, with the fake's globals.
	local function boot(fakeOpts)
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
		return mock, env, ns, fake
	end

	t:describe("/dawnward trp3 glance and field commands (L2)", function()
		t:it("sets, lists, shows and clears At First Glance entries, and syncs them once turned on", function()
			local mock, _, ns, fake = boot()
			expect.truthy(mock.Slash("trp3 glance"):find("none yet", 1, true))
			mock.Slash("trp3 glance title 1 Silver scar")
			mock.Slash("trp3 glance text 1 Across the jaw.||nOld, but clean.")
			mock.Slash("trp3 glance icon 1 inv_misc_bone_01")
			local char = ns.ctx.store.real.characters[KEY]
			expect.deepEqual(char.glance[1], { title = "Silver scar", text = "Across the jaw.\nOld, but clean.",
				icon = "inv_misc_bone_01", active = true })
			expect.truthy(mock.Slash("trp3 glance"):find("1. Silver scar - Across the jaw. / Old, but clean. [shown",
				1, true))
			expect.truthy(mock.Slash("trp3 glance icon 1 |Tx|t"):find("icon name", 1, true))
			mock.timers = {}
			mock.RunTimers()
			expect.deepEqual(fake.profile.player.misc.PE, {}, "nothing written while glance sync is off")
			expect.truthy(mock.Slash("trp3 enable glance"):find("EXPERIMENTAL", 1, true), "asks for confirm")
			expect.truthy(mock.Slash("trp3 enable glance confirm"):find("At First Glance", 1, true))
			mock.RunTimers()
			expect.deepEqual(fake.profile.player.misc.PE["1"], { TI = "Silver scar",
				TX = "Across the jaw.\nOld, but clean.", IC = "inv_misc_bone_01", AC = true })
			mock.Slash("trp3 glance hide 1")
			mock.RunTimers()
			expect.equal(fake.profile.player.misc.PE["1"].AC, false)
			expect.truthy(mock.Slash("trp3 glance clear 1"):find("confirm", 1, true))
			expect.truthy(char.glance[1], "not cleared without confirm")
			mock.Slash("trp3 glance clear 1 confirm")
			mock.RunTimers()
			expect.falsy(char.glance[1])
			expect.deepEqual(fake.profile.player.misc.PE, {})
		end)

		t:it("accepts every mapped field name in any case, including additional information", function()
			local mock, _, ns = boot()
			mock.Slash("set firstName Kyssarra")
			mock.Slash("vis firstName public")
			local out = mock.Slash("trp3 field firstname dawnward confirm")
			expect.truthy(out:find("EXPERIMENTAL automatic First name sync is ON", 1, true), out)
			out = mock.Slash("trp3 field Pronouns off")
			expect.truthy(out:find("Pronouns: Not synchronised", 1, true), out)
			local entry = ns.ctx.trp3Deps().ledger.optIn[KEY]
			expect.equal(ns.TRP3Ledger.Policy(entry, "firstName"), "dawnward")
			expect.equal(ns.TRP3Ledger.Policy(entry, "pronouns"), "off")
			expect.truthy(mock.Slash("trp3 import pronouns confirm"):find("This copies", 1, true),
				"import stays limited to characteristics fields")
		end)
	end)
end
