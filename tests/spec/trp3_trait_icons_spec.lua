-- L1/L2 (0.10.2): the icons at both ends of Dawnward's personality traits.
-- 0.10.1 wrote TRP3's placeholder (RegisterCharacteristics.lua:690-692,
-- psychoAdd("new"): LI = RI = "INV_Misc_QuestionMark") on every trait, so
-- Total RP 3 showed a red question mark at both ends. Shapes follow the
-- TRP3 3.4.1 source: a custom trait is { LT, LI, RT, RI, V2 } with bare icon
-- names (RegisterCharacteristics.lua:451-452, 1206-1280). Fake, not in-game.
local Loader = require("support.loader")
local Fake = require("fakes.trp3_341")

return function(t, expect)
	local KEY = "Testchar-TestRealm"
	local AXES = { "courage", "compassion", "discipline", "faith", "honour", "sociability" }

	local function world(fakeOpts)
		local ns = Loader.WithTRP3()
		local fake = Fake.new(fakeOpts or {})
		fake.env.UnitName = function() return "Testchar" end
		local store = ns.Store.new(ns.Schema.NewDatabase(), ns.Schema.NewDatabase())
		local clock = 1000
		local deps = {
			env = fake.env, ledger = ns.TRP3Ledger.New(), store = store, characterKey = KEY,
			now = function() clock = clock + 1; return clock end,
			inCombat = function() return false end,
		}
		local w = { ns = ns, fake = fake, deps = deps, Sync = ns.TRP3Sync, TraitPlan = ns.TRP3TraitPlan }
		function w.char() return assert(store:EnsureCharacter(KEY, 1)) end
		function w.trait(axis, value)
			ns.Personality.Set(w.char(), axis, value)
			ns.Personality.SetVisibility(w.char(), axis, "public")
		end
		function w.run() return w.Sync.RunFeature(deps, "traits") end
		function w.ch() return fake.profile.player.characteristics end
		function w.record() return deps.ledger.profiles[fake.profileId] end
		function w.owned() return w.record().traits.owned end
		-- The trait with these words, and its index.
		function w.find(lt)
			for i, tr in ipairs(w.ch().PS) do
				if tr.LT == lt then return tr, i end
			end
		end
		return w
	end

	-- Six public axes, Dawnward's traits after the player's own and a preset.
	local function sixTraits()
		local w = world({ characteristics = { v = 5, FN = "Kyssarra", PS = {
			{ ID = 3, V2 = 12 }, { LT = "Gloomy", RT = "Cheerful", V2 = 4, LI = "a", RI = "b" } } } })
		for i, axis in ipairs(AXES) do w.trait(axis, 2 + 3 * i) end
		assert(w.Sync.SetOptIn(w.deps, "traits", true))
		return w
	end

	t:describe("Trait icons: the table (TraitPlan.ICONS)", function()
		t:it("gives all twelve ends distinct, verified icons in TRP3's format, never the placeholder", function()
			local ns = Loader.WithTRP3()
			local TraitPlan = ns.TRP3TraitPlan
			local seen, count = {}, 0
			for _, axis in ipairs(ns.Schema.PERSONALITY_AXES) do
				local icons = TraitPlan.ICONS[axis.id]
				expect.truthy(icons, axis.id .. " has icons")
				for _, side in ipairs({ "left", "right" }) do
					local name = icons[side]
					expect.truthy(name:match("^[a-z0-9_]+$"), name .. ": a bare, lower-case icon file name")
					expect.truthy(TraitPlan.VERIFIED[name], name .. " is on the verified list")
					expect.truthy(TraitPlan.VERIFIED[name]:match("^[A-Z]+ .*%.lua:%d"), name .. " names its evidence")
					expect.falsy(seen[name], name .. " is used once")
					expect.truthy(name ~= TraitPlan.PLACEHOLDER:lower(), "never the question mark")
					seen[name] = true
					count = count + 1
				end
				local li, ri = TraitPlan.Icons(axis.id)
				expect.deepEqual({ li, ri }, { icons.left, icons.right })
			end
			expect.equal(count, 12)
			expect.truthy(TraitPlan.VERIFIED[TraitPlan.FALLBACK_ICON], "the fallback is verified")
			expect.falsy(seen[TraitPlan.FALLBACK_ICON], "the fallback is none of the twelve")
			expect.falsy(TraitPlan.VERIFIED[TraitPlan.PLACEHOLDER:lower()], "the placeholder is never written")
		end)

		t:it("an icon not on the verified list falls back to a verified one", function()
			local TraitPlan = Loader.WithTRP3().TRP3TraitPlan
			expect.equal(TraitPlan.SafeIcon("Spell_Holy_AuraOfLight"), "spell_holy_auraoflight", "case does not matter")
			expect.equal(TraitPlan.SafeIcon("inv_misc_made_up_99"), TraitPlan.FALLBACK_ICON)
			expect.equal(TraitPlan.SafeIcon("INV_Misc_QuestionMark"), TraitPlan.FALLBACK_ICON)
			expect.equal(TraitPlan.SafeIcon(nil), TraitPlan.FALLBACK_ICON)
			TraitPlan.ICONS.courage = { left = "not_a_real_icon", right = "ability_dualwield" }
			expect.deepEqual({ TraitPlan.Icons("courage") }, { TraitPlan.FALLBACK_ICON, "ability_dualwield" })
			expect.deepEqual({ TraitPlan.Icons("unknown") }, { TraitPlan.FALLBACK_ICON, TraitPlan.FALLBACK_ICON })
			local plan = TraitPlan.Plan({ PS = {} }, nil, { courage = { LT = "Cautious", RT = "Bold", V2 = 4 } })
			expect.equal(plan.characteristics.PS[1].LI, TraitPlan.FALLBACK_ICON, "the plan writes the fallback")
		end)

		t:it("replaces only no icon, the placeholder or the icon Dawnward last wrote", function()
			local TraitPlan = Loader.WithTRP3().TRP3TraitPlan
			expect.truthy(TraitPlan.Replaceable(nil))
			expect.truthy(TraitPlan.Replaceable("INV_Misc_QuestionMark"))
			expect.truthy(TraitPlan.Replaceable("inv_misc_questionmark"))
			expect.truthy(TraitPlan.Replaceable("inv_shield_35", "inv_shield_35"), "Dawnward's own earlier icon")
			expect.falsy(TraitPlan.Replaceable("inv_misc_gift_02", "inv_shield_35"), "the player's choice")
			expect.falsy(TraitPlan.Replaceable("inv_misc_gift_02"), "the player's choice (old ledger)")
			expect.falsy(TraitPlan.Replaceable(7))
		end)
	end)

	t:describe("Trait icons: TRP3 sync (fake TRP3 3.4.1)", function()
		t:it("gives new traits their axis icons and records them in the ledger", function()
			local w = sixTraits()
			local r = w.run()
			expect.equal(r.state, "written", r.message)
			expect.deepEqual(w.ch().PS[1], { ID = 3, V2 = 12 })
			expect.deepEqual(w.ch().PS[2], { LT = "Gloomy", RT = "Cheerful", V2 = 4, LI = "a", RI = "b" })
			for _, axis in ipairs(w.ns.Schema.PERSONALITY_AXES) do
				local trait = w.find(axis.left)
				expect.equal(trait.LI, w.TraitPlan.ICONS[axis.id].left, axis.id)
				expect.equal(trait.RI, w.TraitPlan.ICONS[axis.id].right, axis.id)
				expect.equal(w.owned()[axis.id].LI, trait.LI)
				expect.equal(w.owned()[axis.id].RI, trait.RI)
			end
			expect.equal(w.run().state, "noop", "repeated sync writes nothing")
		end)

		t:it("migrates 0.10.1 traits with the placeholder in one write, changing nothing else", function()
			local w = sixTraits()
			assert(w.run().state == "written")
			-- What 0.10.1 left: placeholder icons (one trait with none) and a
			-- ledger without icons, as loaded from SavedVariables.
			for i = 3, #w.ch().PS do
				w.ch().PS[i].LI, w.ch().PS[i].RI = "INV_Misc_QuestionMark", "INV_Misc_QuestionMark"
			end
			w.ch().PS[5].LI = nil
			for _, o in pairs(w.owned()) do o.LI, o.RI = nil, nil end
			local saved = w.ns.Util.DeepCopy(w.deps.ledger)
			w.deps.ledger = assert(w.ns.TRP3Ledger.Normalize(saved))
			expect.equal(w.owned().courage.LI, nil, "an old record loads without icons")
			local before = w.ns.Util.DeepCopy(w.ch())
			local ownedBefore = w.ns.Util.DeepCopy(w.owned())
			local backups = #w.deps.ledger.backups
			local function writes()
				local n = 0
				for _, e in ipairs(w.fake.events) do
					if e.args and e.args[3] == "characteristics" then n = n + 1 end
				end
				return n
			end
			local writesBefore = writes()
			local r = w.run()
			expect.equal(r.state, "written", r.message)
			expect.equal(writes(), writesBefore + 1, "one write")
			expect.equal(#w.deps.ledger.backups, backups + 1, "one backup")
			expect.equal(#w.ch().PS, #before.PS, "no duplicates")
			for i, old in ipairs(before.PS) do
				local now = w.ch().PS[i]
				expect.equal(now.LT, old.LT, "order and words kept")
				expect.equal(now.RT, old.RT)
				expect.equal(now.V2, old.V2, "values kept")
				expect.equal(now.ID, old.ID)
			end
			expect.deepEqual(w.ch().PS[2], before.PS[2], "the player's own trait is untouched")
			for _, axis in ipairs(w.ns.Schema.PERSONALITY_AXES) do
				local trait = w.find(axis.left)
				expect.equal(trait.LI, w.TraitPlan.ICONS[axis.id].left, axis.id .. " left icon")
				expect.equal(trait.RI, w.TraitPlan.ICONS[axis.id].right, axis.id .. " right icon")
				local o = w.owned()[axis.id]
				expect.deepEqual({ o.LT, o.RT, o.V2 }, { ownedBefore[axis.id].LT, ownedBefore[axis.id].RT,
					ownedBefore[axis.id].V2 }, "ownership unchanged")
				expect.equal(o.LI, trait.LI, "the ledger now knows Dawnward's icon")
			end
			expect.equal(w.run().state, "noop", "repeated sync is a no-op")
			-- The ledger with icons survives a save and load.
			local reloaded = assert(w.ns.TRP3Ledger.Normalize(w.ns.Util.DeepCopy(w.deps.ledger)))
			expect.equal(reloaded.profiles[w.fake.profileId].traits.owned.faith.RI, "spell_holy_auraoflight")
		end)

		t:it("keeps an icon the player chose in Total RP 3, even with a 0.10.1 ledger", function()
			local w = sixTraits()
			assert(w.run().state == "written")
			local courage = w.find("Cautious")
			courage.LI = "inv_misc_gift_02"
			expect.equal(w.run().state, "noop", "the player's restyle is theirs")
			w.trait("courage", 12)
			expect.equal(w.run().state, "written")
			courage = w.find("Cautious")
			expect.equal(courage.V2, 8)
			expect.equal(courage.LI, "inv_misc_gift_02", "the player's icon stays")
			expect.equal(courage.RI, "ability_dualwield")
			-- An old record (no icons) with a player's icon and a placeholder.
			local faith = w.find("Sceptical")
			faith.LI, faith.RI = "spell_holy_holyguidance", "INV_Misc_QuestionMark"
			for _, o in pairs(w.owned()) do o.LI, o.RI = nil, nil end
			expect.equal(w.run().state, "written")
			faith = w.find("Sceptical")
			expect.equal(faith.LI, "spell_holy_holyguidance", "kept")
			expect.equal(faith.RI, "spell_holy_auraoflight", "the placeholder is replaced")
			expect.equal(w.find("Cautious").LI, "inv_misc_gift_02")
			expect.equal(w.run().state, "noop")
		end)

		t:it("an icon Dawnward wrote earlier is replaced when Dawnward's icon changes", function()
			local w = sixTraits()
			assert(w.run().state == "written")
			w.find("Cautious").LI = "inv_misc_gift_02"
			w.TraitPlan.ICONS.honour = { left = "spell_arcane_mindmastery", right = "inv_shield_35" }
			w.TraitPlan.ICONS.courage = { left = "spell_holy_auraoflight", right = "ability_dualwield" }
			expect.equal(w.run().state, "written")
			expect.equal(w.find("Pragmatic").LI, "spell_arcane_mindmastery", "Dawnward's earlier icon")
			expect.equal(w.owned().honour.LI, "spell_arcane_mindmastery")
			expect.equal(w.find("Cautious").LI, "inv_misc_gift_02", "never the player's")
		end)

		t:it("reads the icons back: a TRP3 that drops them restores the backup", function()
			local w = sixTraits()
			w.fake.env.TRP3_Addon.TriggerEvent = function(_, _, _, _, section)
				if section == "characteristics" then
					for _, tr in ipairs(w.ch().PS) do
						if tr.LI == "spell_shadow_brainwash" then tr.LI = "INV_Misc_QuestionMark" end
					end
				end
			end
			local r = w.run()
			expect.equal(r.state, "failed", r.message)
			expect.truthy(r.message:find("restored from the backup"))
			expect.equal(#w.ch().PS, 2, "restored")
		end)

		t:it("diagnose lists each owned trait's icons", function()
			local w = sixTraits()
			local Commands = w.ns.TRP3Commands
			expect.truthy(Commands.TraitIconLines(w.deps)[1]:find("owns no traits"))
			assert(w.run().state == "written")
			w.find("Cautious").LI = "inv_misc_gift_02"
			w.find("Reserved").RI = "INV_Misc_QuestionMark"
			local lines = Commands.TraitIconLines(w.deps)
			expect.equal(#lines, 6)
			expect.equal(lines[1], "trait icons courage: Cautious inv_misc_gift_02 (your own, kept) / Bold "
				.. "ability_dualwield (Dawnward's)")
			expect.equal(lines[6], "trait icons sociability: Reserved ability_rogue_disguise (Dawnward's) / "
				.. "Outgoing INV_Misc_QuestionMark (replaced on the next sync)")
		end)
	end)
end
