-- L2 (WoW Forever track): the Total RP 3 sync against the 3.5.4 fake
-- (fakes/trp3_354.lua: upstream 3.5.4, the closest available substitute
-- for the build Forever players run; mocked, not in-game evidence). Every
-- test names the 3.5.4 behaviour it relies on; the full diff against 3.4.1
-- is in docs/TRP3_INTEGRATION.md ("Total RP 3 3.5.x").
local Loader = require("support.loader")
local Fake = require("fakes.trp3_354")
local Fake341 = require("fakes.trp3_341")

return function(t, expect)
	local KEY = "Testchar-TestRealm"

	local function world(fakeOpts, FakeModule)
		local ns = Loader.WithTRP3()
		local fake = (FakeModule or Fake).new(fakeOpts or {})
		fake.env.UnitName = function() return "Testchar" end
		fake.env.UnitRace = function() return "Human", "Human", 1 end
		fake.env.UnitClass = function() return "Paladin", "PALADIN", 2 end
		local store = ns.Store.new(ns.Schema.NewDatabase(), ns.Schema.NewDatabase())
		local clock = 1000
		local combat = false
		local deps = {
			env = fake.env, ledger = ns.TRP3Ledger.New(), store = store, characterKey = KEY,
			now = function() clock = clock + 1; return clock end,
			inCombat = function() return combat end,
		}
		local w = { ns = ns, fake = fake, deps = deps, Sync = ns.TRP3Sync, TraitPlan = ns.TRP3TraitPlan,
			Adapter = ns.TRP3Adapter }
		w.ctx = { store = store, characterKey = KEY, now = deps.now, trp3Deps = function() return deps end }
		function w.char() return assert(store:EnsureCharacter(KEY, 1)) end
		function w.overview(text)
			assert(ns.Character.SetField(w.char(), "summary", text, 1))
			assert(ns.Character.SetFieldVisibility(w.char(), "summary", "public", 1))
		end
		function w.field(key, value, level)
			assert(ns.Character.SetField(w.char(), key, value, 1))
			assert(ns.Character.SetFieldVisibility(w.char(), key, level or "public", 1))
		end
		function w.trait(axis, value, level)
			ns.Personality.Set(w.char(), axis, value)
			ns.Personality.SetVisibility(w.char(), axis, level or "public")
		end
		function w.glance(n, title, text) return assert(ns.Glance.Set(w.char(), n, title, text, 1)) end
		function w.status(id, value) return ns.TRP3Commands.SetStatus(w.ctx, id, value) end
		function w.enable(feature) return assert(w.Sync.SetOptIn(deps, feature, true)) end
		function w.manage(...)
			for _, id in ipairs({ ... }) do assert(w.Sync.SetPolicy(deps, id, "dawnward")) end
		end
		function w.run(feature) return w.Sync.RunFeature(deps, feature) end
		function w.setCombat(v) combat = v end
		function w.player() return fake.profile.player end
		function w.record() return deps.ledger.profiles[fake.profileId] end
		function w.find(lt)
			for i, tr in ipairs(w.player().characteristics.PS or {}) do
				if tr.LT == lt then return tr, i end
			end
		end
		return w
	end

	local function contains(tbl, needle)
		if type(tbl) == "string" then return tbl:find(needle, 1, true) ~= nil end
		if type(tbl) ~= "table" then return false end
		for k, v in pairs(tbl) do
			if contains(k, needle) or contains(v, needle) then return true end
		end
		return false
	end

	t:describe("Total RP 3 3.5.x: version detection and gating (L2, fake 3.5.4)", function()
		t:it("recognises 3.5.4 as audited (provisional substitute), never verified in game", function()
			local w = world()
			local s = w.ns.TRP3Status.Read(w.fake.env)
			expect.equal(s.version, "3.5.4")
			expect.truthy(s.versionProfile.known)
			expect.truthy(s.versionProfile.audited)
			expect.equal(s.versionProfile.verified, nil, "no runtime pass is claimed")
			expect.truthy(s.versionProfile.label:find("substitute: upstream 3.5.4", 1, true), s.versionProfile.label)
			expect.truthy(s.versionProfile.tiers.experimentalWrite)
			expect.equal(s.versionProfile.adapters.iconStorage, "id")
			expect.truthy(w.Adapter.Probe(w.fake.env).experimental.allowed)
		end)

		t:it("another 3.5.x build, a packager placeholder or no version: read-only, explained", function()
			for _, version in ipairs({ "3.5.3", "3.5.5", "3.5.10", "@project-version@", "3.6.0", "v3.5.4" }) do
				local w = world({ version = version })
				local vp = w.ns.TRP3VersionProfiles.Get(version)
				expect.falsy(vp.known, version)
				expect.falsy(vp.tiers.experimentalWrite, version)
				expect.falsy(vp.tiers.publicSetters, version)
				expect.falsy(vp.tiers.profileTools, version)
				local probe = w.Adapter.Probe(w.fake.env)
				expect.falsy(probe.experimental.allowed, version)
				expect.truthy(contains(probe.experimental.reasons, "not on the list of versions"), version)
				local ok = w.Sync.SetOptIn(w.deps, "about", true)
				expect.falsy(ok, version .. ": no opt-in")
			end
			local vp = Loader.WithTRP3().TRP3VersionProfiles.Get("3.5.3")
			expect.equal(vp.family, "3.5")
			expect.truthy(vp.label:find("no writes", 1, true), vp.label)
		end)

		t:it("an unaudited 3.5.x build gets no write of any kind, even with a ledger from 3.5.4", function()
			-- Connected while 3.5.4 was installed, then Total RP 3 updated to 3.5.5.
			local w = world()
			w.overview("A wandering scholar.")
			w.trait("courage", 5)
			assert(w.status("currently", "Reading."))
			w.enable("about")
			w.enable("traits")
			w.manage("currently")
			w.fake.env.C_AddOns.GetAddOnMetadata = function(name, field)
				if name == "totalRP3" and field == "Version" then return "3.5.5" end
			end
			local before = w.fake.snapshot()
			local events = #w.fake.events
			for _, r in ipairs(w.Sync.Run(w.deps)) do
				expect.truthy(r.state == "blocked" or r.state == "off", r.feature .. " " .. r.state)
			end
			expect.deepEqual(w.fake.snapshot(), before, "nothing written")
			expect.equal(#w.fake.events, events, "nothing announced")
			expect.equal(#w.fake.setterLog, 0, "no setter called")
			expect.falsy(w.Adapter.ApplySetters(w.fake.env, "character",
				{ { key = "CU", setter = "SetCurrentlyText", value = "x" } }, w.fake.profileId))
			expect.deepEqual(w.Adapter.ProfileTools(w.fake.env), { create = false, select = false })
			local copy, why = w.Adapter.ReadAudited(w.fake.env, "about")
			expect.falsy(copy)
			expect.truthy(why:find("has not been audited", 1, true))
		end)

		t:it("/dawnward trp3 diagnose names the version, its read-only rows, and says when nothing is written", function()
			local lines = {}
			local w = world()
			local ctx = { print = function(s) lines[#lines + 1] = s end, store = w.deps.store,
				characterKey = KEY, trp3Deps = function() return w.deps end }
			w.ns.TRP3Commands.Command(ctx, "diagnose")
			local text = table.concat(lines, "\n")
			expect.truthy(text:find("version 3.5.4", 1, true), text)
			expect.truthy(text:find("substitute: upstream 3.5.4", 1, true))
			expect.truthy(text:find("read-only on this version: icon", 1, true))
			local w2 = world({ version = "3.5.2" })
			lines = {}
			ctx.trp3Deps = function() return w2.deps end
			w2.ns.TRP3Commands.Command(ctx, "diagnose")
			text = table.concat(lines, "\n")
			expect.truthy(text:find("read-only for Dawnward: nothing is written", 1, true), text)
			expect.truthy(text:find("3.4.1, 3.5.4", 1, true))
		end)
	end)

	t:describe("Total RP 3 3.5.x: missing, late and disabled (L2, fake 3.5.4)", function()
		t:it("absent or disabled: nothing is read or written", function()
			for _, opts in ipairs({ { notInstalled = true }, { notLoaded = true } }) do
				local w = world(opts)
				local probe = w.Adapter.Probe(w.fake.env)
				expect.falsy(probe.experimental.allowed)
				expect.falsy(w.Sync.SetOptIn(w.deps, "about", true))
				expect.deepEqual(w.Sync.Run(w.deps), {})
				expect.equal(#w.fake.events, 0)
			end
		end)

		t:it("loaded late: allowed only once Total RP 3 reports itself loaded", function()
			local loaded = false
			local w = world()
			w.fake.env.C_AddOns.IsAddOnLoaded = function(name) return name == "totalRP3" and loaded end
			expect.falsy(w.Adapter.Probe(w.fake.env).experimental.allowed)
			expect.falsy(w.Sync.SetOptIn(w.deps, "about", true))
			loaded = true
			expect.truthy(w.Adapter.Probe(w.fake.env).experimental.allowed)
			w.overview("Late but here.")
			w.enable("about")
			expect.equal(w.run("about").state, "written")
		end)
	end)

	t:describe("Total RP 3 3.5.x: About page (L2, fake 3.5.4)", function()
		t:it("writes the overview, bumps v two steps, notifies TRP3 and MSP, and reads back", function()
			-- RegisterAbout.lua 706-718 (unchanged save path), RegisterMSP.lua 676-685.
			local w = world()
			w.overview("A wandering scholar.")
			w.enable("about")
			local r = w.run("about")
			expect.equal(r.state, "written", r.message)
			local about = w.player().about
			expect.truthy(about.T1.TX:find("A wandering scholar.", 1, true))
			expect.truthy(about.T1.TX:find("Private about text", 1, true), "the player's text is kept")
			expect.equal(about.v, 4)
			local e = w.fake.events[#w.fake.events]
			expect.deepEqual(e.args, { w.fake.playerId, w.fake.profileId, "about" })
			expect.equal(w.fake.msp.DE, about.T1.TX)
			expect.equal(#w.deps.ledger.backups, 1)
			expect.equal(w.ns.TRP3Ledger.BackupData(w.deps.ledger.backups[1]).T1.TX, "Private about text")
		end)

		t:it("a write that does not read back is restored from the backup and switched off", function()
			local w = world()
			w.overview("A wandering scholar.")
			w.enable("about")
			table.insert(w.fake.callbacks.REGISTER_DATA_UPDATED, function(_, _, section)
				if section == "about" and w.player().about.T1.TX:find("scholar", 1, true) then
					w.player().about.T1.TX = w.player().about.T1.TX .. " (rewritten by another addon)"
				end
			end)
			local r = w.run("about")
			expect.equal(r.state, "failed")
			expect.equal(w.player().about.T1.TX, "Private about text", "restored exactly")
			expect.equal(w.Sync.Check(w.deps, "about").state, "off")
		end)

		t:it("an open About editor holds the write back (same frames as 3.4.1)", function()
			-- RegisterUIAbout.xml 191, RegisterUIMain.xml 51, RegisterMain.lua 476.
			local w = world()
			w.overview("A wandering scholar.")
			w.enable("about")
			w.fake.openEditor("about")
			local before = w.fake.snapshot()
			expect.equal(w.run("about").state, "deferred")
			expect.deepEqual(w.fake.snapshot(), before)
			w.fake.cancelEditor("about")
			expect.equal(w.run("about").state, "written")
		end)

		t:it("templates 2 and 3 are written in place, as in 3.4.1", function()
			for _, about in ipairs({
				{ v = 5, TE = 2, T2 = { { TX = "Player frame", IC = "900015", BK = 4 } } },
				{ v = 5, TE = 3, T3 = { PH = { TX = "Tall" }, PS = {}, HI = { TX = "Born." } } },
			}) do
				local w = world({ about = about })
				w.overview("A wandering scholar.")
				w.enable("about")
				expect.equal(w.run("about").state, "written")
				expect.truthy(contains(w.player().about, "A wandering scholar."))
				expect.truthy(contains(w.player().about, about.TE == 2 and "Player frame" or "Tall"), "kept")
				if about.TE == 2 then
					expect.equal(w.player().about.T2[1].IC, "900015", "the player's serialised icon is kept")
				end
			end
		end)
	end)

	t:describe("Total RP 3 3.5.x: personality traits and their icons (L2, fake 3.5.4)", function()
		t:it("writes only icons 3.5.4 proves on every client it loads on; the rest fall back", function()
			local w = world()
			for i, axis in ipairs({ "courage", "compassion", "faith", "sociability" }) do w.trait(axis, 2 + 3 * i) end
			w.enable("traits")
			local r = w.run("traits")
			expect.equal(r.state, "written", r.message)
			local TP = w.TraitPlan
			local seen = {}
			for _, tr in ipairs(w.player().characteristics.PS) do
				for _, icon in ipairs({ tr.LI, tr.RI }) do
					expect.truthy(TP.VERIFIED_354[icon], tostring(icon) .. " is on the 3.5.x list")
					seen[icon] = true
				end
			end
			local courage = w.find(w.ns.Schema.PERSONALITY_AXIS_BY_ID.courage.left)
			expect.deepEqual({ courage.LI, courage.RI }, { "spell_shadow_brainwash", "ability_dualwield" })
			local compassion = w.find(w.ns.Schema.PERSONALITY_AXIS_BY_ID.compassion.left)
			expect.deepEqual({ compassion.LI, compassion.RI }, { TP.FALLBACK_ICON, TP.FALLBACK_ICON },
				"older-client icons are not written on 3.5.x")
			expect.falsy(seen["134400"], "never the placeholder")
			expect.falsy(seen[TP.PLACEHOLDER:lower()], "never the placeholder")
			expect.equal(w.record().traits.owned.courage.LI, "spell_shadow_brainwash", "the ledger keeps the icon")
		end)

		t:it("replaces 3.5.4's placeholder (\"134400\") on a Dawnward trait, keeps the player's own icon", function()
			local w = world()
			w.trait("courage", 5)
			w.enable("traits")
			w.run("traits")
			local lt = w.ns.Schema.PERSONALITY_AXIS_BY_ID.courage.left
			-- The player opens the editor, resets one end to the default and picks another icon for the other.
			local draft = w.fake.openEditor("characteristics")
			for _, tr in ipairs(draft.PS) do
				if tr.LT == lt then
					tr.LI = w.fake.serializeIcon(134400)
					w.fake.pickTraitIcon(tr, "right", "inv_misc_bone_01")
				end
			end
			w.fake.saveEditor("characteristics")
			local tr = w.find(lt)
			expect.deepEqual({ tr.LI, tr.RI }, { "134400", "900015" }, "3.5.4 stores file IDs as strings")
			local r = w.run("traits")
			expect.equal(r.state, "written", r.message)
			tr = w.find(lt)
			expect.equal(tr.LI, "spell_shadow_brainwash", "the placeholder is Dawnward's to replace")
			expect.equal(tr.RI, "900015", "the player's own icon stays")
			expect.equal(w.run("traits").state, "noop", "no churn")
		end)

		t:it("an invalid or unverified icon is never written; a player's custom trait is never touched", function()
			local w = world({ characteristics = { v = 3, FN = "Aelin", PS = {
				{ ID = 3, V2 = 12 }, { LT = "Gloomy", RT = "Cheerful", V2 = 4, LI = "134400", RI = "not_an_icon" } } } })
			local TP = w.TraitPlan
			local opts = TP.Options(w.ns.TRP3VersionProfiles.Adapters(w.fake.env))
			expect.equal(TP.SafeIcon("|Tinterface\\icons\\x|t", opts.icons), TP.FALLBACK_ICON)
			expect.equal(TP.SafeIcon("inv_helmet_20", opts.icons), TP.FALLBACK_ICON, "unproven on 3.5.x")
			expect.equal(TP.SafeIcon("inv_helmet_20"), "inv_helmet_20", "3.4.1 keeps its own list")
			expect.equal(TP.SafeIcon("134400", opts.icons), TP.FALLBACK_ICON)
			expect.truthy(TP.Replaceable("134400", nil, opts.placeholders), "3.5.x: TRP3's placeholder")
			expect.falsy(TP.Replaceable("134400", nil), "3.4.1 never wrote it: the player's")
			expect.truthy(TP.Replaceable("INV_Misc_QuestionMark", nil, opts.placeholders), "older traits too")
			w.trait("courage", 5)
			w.enable("traits")
			w.run("traits")
			local ps = w.player().characteristics.PS
			expect.deepEqual(ps[1], { ID = 3, V2 = 12 })
			expect.deepEqual(ps[2], { LT = "Gloomy", RT = "Cheerful", V2 = 4, LI = "134400", RI = "not_an_icon" },
				"a placeholder on the player's own trait is theirs")
		end)

		t:it("a trait edited in Total RP 3 pauses traits; the player's value is kept", function()
			local w = world()
			w.trait("courage", 5)
			w.enable("traits")
			w.run("traits")
			local tr = w.find(w.ns.Schema.PERSONALITY_AXIS_BY_ID.courage.left)
			tr.V2 = 2
			w.trait("courage", 15)
			expect.equal(w.run("traits").state, "conflict")
			expect.equal(w.find(w.ns.Schema.PERSONALITY_AXIS_BY_ID.courage.left).V2, 2)
		end)
	end)

	t:describe("Total RP 3 3.5.x: At First Glance (L2, fake 3.5.4)", function()
		t:it("goes to free slots only; a player's slot (serialised icon) is never overwritten", function()
			local own = { TI = "Tabard", TX = "Argent Dawn colours.", IC = "900015", AC = true }
			local w = world({ misc = { v = 1, PE = { ["1"] = own }, ST = {} } })
			w.glance(1, "Silver scar")
			w.enable("glance")
			expect.equal(w.run("glance").state, "written")
			local pe = w.player().misc.PE
			expect.deepEqual(pe["1"], own)
			expect.equal(pe["2"].TI, "Silver scar")
			expect.equal(w.run("glance").state, "noop")
		end)

		t:it("every slot the player's: nothing written, the player is told", function()
			local pe = {}
			for i = 1, 5 do pe[tostring(i)] = { TI = "Own " .. i, AC = true, IC = "134400" } end
			local w = world({ misc = { v = 1, PE = pe, ST = {} } })
			w.glance(1, "Silver scar")
			w.enable("glance")
			local before = w.fake.snapshot()
			local check = w.Sync.Check(w.deps, "glance")
			expect.equal(check.state, "blocked")
			expect.truthy(contains(check.reasons, "every At First Glance slot"))
			w.run("glance")
			expect.deepEqual(w.fake.snapshot(), before)
		end)

		t:it("the player re-applying Dawnward's slot in 3.5.4 (icon serialised) is a conflict, not an overwrite", function()
			-- RegisterMisc.lua 346: Apply stores SerializeIcon(ic).
			local w = world()
			w.glance(1, "Silver scar", "Across the jaw.")
			w.enable("glance")
			w.run("glance")
			local slot = w.player().misc.PE["1"]
			w.fake.applyPeekSlot("1", slot.IC, slot.AC, slot.TI, "Across the jaw. Healed now.")
			expect.equal(w.player().misc.PE["1"].IC, "134400")
			w.glance(1, "Silver scar", "Fresh again.")
			local r = w.run("glance")
			expect.equal(r.state, "conflict")
			expect.equal(w.player().misc.PE["1"].TX, "Across the jaw. Healed now.", "the player's Apply wins")
		end)
	end)

	t:describe("Total RP 3 3.5.x: status and look through the setters (L2, fake 3.5.4)", function()
		t:it("Currently, OOC, roleplay status and walk-up use the unchanged setters", function()
			-- Core/Player.lua 434-448 (UpdateProfileField 415-432).
			local w = world()
			assert(w.status("currently", "Mending nets."))
			assert(w.status("ooc", "Ask me about the guild."))
			assert(w.status("rpStatus", 1))
			assert(w.status("walkup", 2))
			w.manage("currently", "ooc", "rpStatus", "walkup")
			local r = w.run("status")
			expect.equal(r.state, "written", r.message)
			local ch = w.player().character
			expect.equal(ch.CU, "Mending nets.")
			expect.equal(ch.CO, "Ask me about the guild.")
			expect.equal(ch.RP, 1)
			expect.equal(ch.WU, 2)
			expect.equal(w.run("status").state, "noop")
			-- Edited in Total RP 3: paused, kept.
			w.fake.env.AddOn_TotalRP3.Player.GetCurrentUser():SetCurrentlyText("Edited in TRP3")
			assert(w.status("currently", "Dawnward's"))
			w.run("status")
			expect.equal(w.player().character.CU, "Edited in TRP3")
			expect.truthy(w.record().fieldConflicts.currently)
		end)

		t:it("the profile icon is read-only on 3.5.x; the class colour is written", function()
			-- Core/Player.lua 458-460 (SetCustomIcon serialises), 474-486 (colour unchanged).
			local w = world()
			assert(w.status("icon", "inv_misc_note_02"))
			assert(w.status("classColor", "c41f3b"))
			w.manage("icon", "classColor")
			local check = w.Sync.Check(w.deps, "look")
			expect.truthy(contains(check.notes, "profile icon is read-only"), "the player is told")
			local r = w.run("look")
			expect.equal(r.state, "written", r.message)
			local names = {}
			for _, c in ipairs(w.fake.setterLog) do names[#names + 1] = c.name end
			expect.deepEqual(names, { "SetCustomClassColor" }, "SetCustomIcon is never called")
			expect.equal(w.player().characteristics.CH, "c41f3b")
			expect.falsy(w.player().characteristics.IC == "inv_misc_note_02")
			-- Even asked directly, the adapter refuses the setter on 3.5.4.
			local ok, why = w.Adapter.ApplySetters(w.fake.env, "characteristics",
				{ { key = "IC", setter = "SetCustomIcon", value = "inv_misc_note_02" } }, w.fake.profileId)
			expect.falsy(ok)
			expect.truthy(why:find("does not store what it is given", 1, true))
			expect.equal(#w.fake.setterLog, 1)
		end)

		t:it("why: 3.5.4's SetCustomIcon stores a file ID, which could never read back as written", function()
			local fake = Fake.new()
			local user = fake.env.AddOn_TotalRP3.Player.GetCurrentUser()
			user:SetCustomIcon("inv_misc_note_02")
			expect.equal(fake.profile.player.characteristics.IC, "900014")
			user:SetCustomIcon("unknown_icon_name")
			expect.equal(fake.profile.player.characteristics.IC, "unknown_icon_name", "kept as given when unknown")
		end)
	end)

	t:describe("Total RP 3 3.5.x: profile fields, names and additional information (L2, fake 3.5.4)", function()
		t:it("TRP3's own given and family name count as its defaults, so Dawnward's names replace them", function()
			-- RegisterCharacteristics.lua 48-50, Core/Globals.lua 49-51.
			local w = world({ regionalNames = true, givenName = "Aelin", familyName = "Ashvale",
				characteristics = { v = 2, FN = "Aelin", LN = "Ashvale", PS = {} } })
			local d = w.ns.TRP3FieldPlan.GameDefaults(w.fake.env)
			expect.equal(d.FN, "Aelin")
			expect.equal(d.LN, "Ashvale")
			w.field("lastName", "Brightwater")
			w.manage("lastName")
			local r = w.run("fields")
			expect.equal(r.state, "written", r.message)
			expect.equal(w.player().characteristics.LN, "Brightwater")
			-- 3.4.1 has no family-name default: the same profile is a conflict there.
			local old = world({ characteristics = { v = 2, FN = "Aelin", LN = "Ashvale", PS = {} } }, Fake341)
			expect.equal(old.ns.TRP3FieldPlan.GameDefaults(old.fake.env).LN, nil)
			old.field("lastName", "Brightwater")
			old.manage("lastName")
			expect.equal(old.run("fields").state, "conflict")
			expect.equal(old.player().characteristics.LN, "Ashvale")
		end)

		t:it("a realm-less character ID (regional names) still recognises the player's own hints", function()
			local w = world({ regionalNames = true, givenName = "Aelin", familyName = "Ashvale" })
			expect.equal(w.fake.playerId, "Aelin Ashvale")
			expect.truthy(w.Adapter.IsOwnHint(w.fake.env, "REGISTER_DATA_UPDATED", "Aelin Ashvale", nil, "about"))
			expect.falsy(w.Adapter.IsOwnHint(w.fake.env, "REGISTER_DATA_UPDATED", "Someone Else", "OTHERPROFILE"))
			w.overview("A wandering scholar.")
			w.enable("about")
			expect.equal(w.run("about").state, "written")
			expect.equal(w.fake.events[#w.fake.events].args[1], "Aelin Ashvale")
		end)

		t:it("a new additional-information entry gets TRP3's icon as 3.5.4 stores it (tostring of the ID)", function()
			-- Core/ProfileUtil.lua 157-160 (icon is a number), RegisterCharacteristics.lua 610-617.
			local w = world()
			local icons = w.ns.TRP3MiscPlan.PresetIcons(w.fake.env)
			expect.equal(icons.pronouns, "900017")
			expect.equal(icons.faith, "134400")
			w.field("pronouns", "she/her")
			w.manage("pronouns")
			expect.equal(w.run("misc").state, "written")
			local mi = w.player().characteristics.MI
			expect.equal(mi[1].ID, 7)
			expect.equal(mi[1].IC, "900017")
			-- A number never reaches a version that stores names.
			local old = world({}, Fake341)
			old.fake.env.TRP3_API.GetMiscTypeInfo = function() return { icon = 12345, localizedName = "Pronouns" } end
			expect.equal(old.ns.TRP3MiscPlan.PresetIcons(old.fake.env).pronouns, nil)
		end)

		t:it("a field edited in Total RP 3 is paused and kept (ownership)", function()
			local w = world()
			w.field("age", "31")
			w.manage("age")
			w.run("fields")
			w.player().characteristics.AG = "Thirty-ish"
			w.field("age", "32")
			w.run("fields")
			expect.equal(w.player().characteristics.AG, "Thirty-ish")
			expect.truthy(w.record().fieldConflicts.age)
		end)
	end)

	t:describe("Total RP 3 3.5.x: transactions (L2, fake 3.5.4)", function()
		t:it("rollback restores the exact earlier section, and can itself be undone", function()
			local w = world()
			w.overview("A wandering scholar.")
			w.trait("courage", 5)
			w.enable("about")
			w.enable("traits")
			w.Sync.Run(w.deps)
			local beforeTraits = w.ns.TRP3Ledger.BackupData(w.deps.ledger.backups[2])
			local written = w.ns.Util.DeepCopy(w.player().characteristics)
			assert(w.Sync.Rollback(w.deps, w.deps.ledger.backups[2].id))
			local now = w.ns.Util.DeepCopy(w.player().characteristics)
			now.v, beforeTraits.v = nil, nil
			expect.deepEqual(now, beforeTraits, "everything but the version is back")
			local safety = w.deps.ledger.backups[#w.deps.ledger.backups]
			assert(w.Sync.Rollback(w.deps, safety.id))
			expect.deepEqual(w.player().characteristics.PS, written.PS)
		end)

		t:it("repeated runs write once: no version churn and no event storm", function()
			local w = world()
			w.overview("A wandering scholar.")
			w.trait("courage", 5)
			w.glance(1, "Silver scar")
			assert(w.status("currently", "Reading."))
			w.enable("about")
			w.enable("traits")
			w.enable("glance")
			w.manage("currently")
			w.Sync.Run(w.deps)
			local snap = w.fake.snapshot()
			local events, backups = #w.fake.events, #w.deps.ledger.backups
			for _ = 1, 5 do
				for _, r in ipairs(w.Sync.Run(w.deps)) do
					expect.equal(r.state, "noop", r.feature .. ": " .. tostring(r.message))
				end
			end
			expect.deepEqual(w.fake.snapshot(), snap)
			expect.equal(#w.fake.events, events)
			expect.equal(#w.deps.ledger.backups, backups)
		end)

		t:it("a profile switch in the middle of a run stops every later write", function()
			local w = world({ profiles = { ["1700000099OTHER"] = { profileName = "Other",
				player = { characteristics = { v = 1, FN = "Other", PS = {} }, about = { v = 1, TE = 1, T1 = {} },
					misc = { v = 1, PE = {}, ST = {} }, character = { v = 1, RP = 2, WU = 1 } } } } })
			w.overview("A wandering scholar.")
			w.trait("courage", 5)
			w.enable("about")
			w.enable("traits")
			-- Another addon (or the player) switches profile as soon as the About write lands.
			table.insert(w.fake.callbacks.REGISTER_DATA_UPDATED, function(_, _, section)
				if section == "about" and w.fake.profileId ~= "1700000099OTHER" then
					w.fake.env.TRP3_API.profile.selectProfile("1700000099OTHER")
				end
			end)
			local other = w.ns.Util.DeepCopy(w.fake.profiles["1700000099OTHER"])
			local results = w.Sync.Run(w.deps)
			local byFeature = {}
			for _, r in ipairs(results) do byFeature[r.feature] = r end
			expect.truthy(byFeature.traits.state == "blocked", byFeature.traits.message)
			expect.truthy(byFeature.traits.message:find("not the one sync was enabled for", 1, true))
			local now = w.ns.Util.DeepCopy(w.fake.profiles["1700000099OTHER"])
			expect.deepEqual(now.player, other.player, "the other profile is untouched")
			-- And the driver itself refuses a profile that is not the expected one.
			local ok, why = w.Adapter.WriteSection(w.fake.env, "about", { v = 1, TE = 1, T1 = { TX = "x" } },
				"1700000000ABCDE")
			expect.falsy(ok)
			expect.truthy(why:find("profile changed", 1, true))
		end)

		t:it("malformed or partial profile data blocks the write; nothing is changed", function()
			local cases = {
				{ feature = "about", opts = { about = { v = 2, TE = 9, T1 = { TX = "x" } } } },
				{ feature = "about", opts = { about = { TE = 1, T1 = { TX = "x" } } } },
				{ feature = "traits", opts = { characteristics = { v = 3, PS = { [1] = { LT = "a", RT = "b" }, [3] = {} } } } },
				{ feature = "traits", opts = { characteristics = { v = 3, PS = { { V2 = "high" } } } } },
				{ feature = "glance", opts = { misc = { v = 1, PE = { ["9"] = { TI = "x" } }, ST = {} } } },
				{ feature = "glance", opts = { misc = { v = 1, PE = "broken", ST = {} } } },
			}
			for _, case in ipairs(cases) do
				local w = world(case.opts)
				w.overview("A wandering scholar.")
				w.trait("courage", 5)
				w.glance(1, "Silver scar")
				w.enable(case.feature)
				local before = w.fake.snapshot()
				local r = w.run(case.feature)
				expect.equal(r.state, "blocked", case.feature .. ": " .. tostring(r.message))
				expect.deepEqual(w.fake.snapshot(), before)
			end
			-- A character section with a number for Currently.
			local w = world()
			w.player().character.CU = 42
			assert(w.status("currently", "Reading."))
			w.manage("currently")
			expect.equal(w.run("status").state, "blocked")
			expect.equal(w.player().character.CU, 42)
		end)

		t:it("the default profile is never written on 3.5.x either", function()
			local w = world({ isDefault = true })
			expect.falsy(w.Sync.SetOptIn(w.deps, "about", true))
			local probe = w.Adapter.Probe(w.fake.env)
			expect.truthy(contains(probe.experimental.reasons, "default profile"))
		end)
	end)

	t:describe("Total RP 3 3.5.x: privacy (L2, fake 3.5.4)", function()
		t:it("private, secret and unapproved content never reaches the profile", function()
			local w = world()
			w.overview("A wandering scholar.")
			w.ns.Facts.Add(w.char(), { category = "fear", statement = "PRIVATE-FEAR" })
			w.field("age", "PRIVATE-AGE", "private")
			w.field("homeland", "SECRET-HOME", "secret")
			w.trait("courage", 5)
			w.trait("faith", 18, "private")
			assert(w.ns.Journal.AddNote(w.char(), { text = "PRIVATE-JOURNAL" }, 1))
			assert(w.ns.Journal.AddStoryDraft(w.char(), { title = "UNAPPROVED-DRAFT", text = "UNAPPROVED-STORY",
				story = { category = "origin" } }, 1))
			w.enable("about")
			w.enable("traits")
			w.manage("age", "homeland")
			w.Sync.Run(w.deps)
			local snap = w.fake.snapshot()
			expect.truthy(contains(snap, "A wandering scholar."), "the public overview is published")
			for _, needle in ipairs({ "PRIVATE-FEAR", "PRIVATE-AGE", "SECRET-HOME", "PRIVATE-JOURNAL",
				"UNAPPROVED-DRAFT", "UNAPPROVED-STORY" }) do
				expect.falsy(contains(snap, needle), needle)
			end
			expect.truthy(w.find(w.ns.Schema.PERSONALITY_AXIS_BY_ID.courage.left))
		end)

		t:it("a character still on the older model publishes only what was marked Public", function()
			Loader.Legacy(function()
				local w = world()
				w.trait("courage", 5)
				w.trait("faith", 18, "private")
				w.trait("honour", 3, "secret")
				w.enable("traits")
				expect.equal(w.run("traits").state, "written")
				expect.truthy(w.find(w.ns.Schema.PERSONALITY_AXIS_BY_ID.courage.left))
				expect.falsy(w.find(w.ns.Schema.PERSONALITY_AXIS_BY_ID.faith.left), "a private axis stays private")
				expect.falsy(w.find(w.ns.Schema.PERSONALITY_AXIS_BY_ID.honour.left), "a secret axis stays secret")
			end)
		end)
	end)

	-- Review finding M3: 3.5.4 turns every icon it stores through its own
	-- editors into a file ID (TRP3_IconUtil.SerializeIcon, Core/IconUtil.lua
	-- 39-56; At First Glance Apply, RegisterMisc.lua 346). An icon Dawnward
	-- wrote by name is the same icon when TRP3's own read-only resolver
	-- (TRP3_IconUtil.GetIconID, Core/IconUtil.lua 16-18) gives the stored ID.
	t:describe("Total RP 3 3.5.x: icon equivalence (L2, fake 3.5.4)", function()
		local function glanceWorld(fakeOpts, FakeModule)
			local w = world(fakeOpts, FakeModule)
			w.glance(1, "Silver scar", "Across the jaw.")
			w.enable("glance")
			expect.equal(w.run("glance").state, "written")
			return w
		end
		local function applyUnchanged(w, ic)
			local slot = w.player().misc.PE["1"]
			w.fake.applyPeekSlot("1", ic or slot.IC, slot.AC, slot.TI, slot.TX)
		end

		t:it("Apply pressed unchanged on Dawnward's slot (icon now a file ID) keeps it Dawnward's", function()
			local w = glanceWorld()
			applyUnchanged(w)
			expect.equal(w.player().misc.PE["1"].IC, "134400", "3.5.4 stored the question mark's file ID")
			local check = w.Sync.Check(w.deps, "glance")
			expect.equal(check.state, "noop", table.concat(check.reasons or {}, "; "))
			expect.equal(w.run("glance").state, "noop", "no conflict and no churn")
			expect.falsy(w.record().conflicts.glance, "glance sync is not paused")
			-- Dawnward's next change still reaches the slot.
			w.glance(1, "Silver scar", "Healed now.")
			expect.equal(w.run("glance").state, "written")
			expect.equal(w.player().misc.PE["1"].TX, "Healed now.")
			expect.equal(w.record().glance.slots["1"].IC, "inv_misc_questionmark", "the ledger keeps the name")
		end)

		t:it("a different icon picked in Total RP 3 is still the player's: a conflict", function()
			local w = glanceWorld()
			applyUnchanged(w, "inv_misc_bone_01")
			expect.equal(w.player().misc.PE["1"].IC, "900015")
			local before = w.fake.snapshot()
			expect.equal(w.run("glance").state, "conflict")
			expect.deepEqual(w.fake.snapshot(), before, "nothing written")
		end)

		t:it("without a working TRP3_IconUtil.GetIconID a file ID is never guessed: a conflict", function()
			for _, broken in ipairs({ "missing", "raises", "not a number", "no IconUtil" }) do
				local w = glanceWorld()
				applyUnchanged(w)
				local util = w.fake.env.TRP3_IconUtil
				if broken == "missing" then util.GetIconID = nil
				elseif broken == "raises" then util.GetIconID = function() error("boom") end
				elseif broken == "not a number" then util.GetIconID = function() return "134400" end
				else w.fake.env.TRP3_IconUtil = nil end
				expect.equal(w.run("glance").state, "conflict", broken)
				expect.equal(w.player().misc.PE["1"].IC, "134400", broken .. ": the slot is kept")
			end
		end)

		t:it("resolving an icon only reads: GetIconID is the one TRP3 call, and nothing changes", function()
			local w = glanceWorld()
			applyUnchanged(w)
			local calls = {}
			local util = w.fake.env.TRP3_IconUtil
			local get = util.GetIconID
			util.GetIconID = function(icon) calls[#calls + 1] = icon; return get(icon) end
			util.SerializeIcon = function() error("Dawnward must not serialise icons") end
			local before = w.fake.snapshot()
			expect.equal(w.run("glance").state, "noop")
			expect.deepEqual(w.fake.snapshot(), before)
			expect.truthy(#calls > 0, "the resolver was asked")
			for _, icon in ipairs(calls) do expect.equal(icon, "inv_misc_questionmark", "only Dawnward's own icon") end
		end)

		t:it("Classic (3.4.1) keeps the exact comparison: no resolver, a file ID is a conflict", function()
			local w = glanceWorld({}, Fake341)
			local VP = w.ns.TRP3VersionProfiles
			expect.equal(VP.IconEquivalence(w.fake.env, VP.Get("3.4.1").adapters), nil)
			expect.equal(type(VP.IconEquivalence(w.fake.env, VP.Get("3.5.4").adapters)), "function")
			expect.equal(VP.IconEquivalence(w.fake.env, VP.Get("3.5.9").adapters), nil, "unaudited: none")
			-- Even with a resolver present, 3.4.1 never uses it.
			w.fake.env.TRP3_IconUtil = { GetIconID = function() return 134400 end }
			applyUnchanged(w, "134400")
			expect.equal(w.run("glance").state, "conflict")
		end)

		t:it("pure: IconEquivalence matches the same name or the same resolved file ID, nothing else", function()
			local w = world()
			local VP = w.ns.TRP3VersionProfiles
			local same = VP.IconEquivalence(w.fake.env, VP.Get("3.5.4").adapters)
			expect.truthy(same("inv_misc_questionmark", "inv_misc_questionmark"))
			expect.truthy(same("134400", "inv_misc_questionmark"))
			expect.truthy(same("900018", "inv_misc_book_09"))
			expect.falsy(same("900015", "inv_misc_book_09"))
			expect.falsy(same("134400", "not_an_icon"), "unresolvable: not the same")
			expect.falsy(same("INV_Misc_QuestionMark", "inv_misc_questionmark"), "a different name is not the same")
			expect.falsy(same(nil, "inv_misc_questionmark"))
			expect.falsy(same(134400, "inv_misc_questionmark"), "only TRP3's stringified ID")
			expect.falsy(same("134400.0", "inv_misc_questionmark"))
		end)

		t:it("an About frame the player gave the same icon in 3.5.4 is still Dawnward's to remove", function()
			for _, case in ipairs({ { state = "written" }, { icon = "inv_misc_bone_01", state = "conflict" } }) do
				local w = world({ about = { v = 2, TE = 2, T2 = {} } })
				w.overview("A wandering scholar.")
				w.field("appearance", "Grey eyes.")
				w.enable("about")
				expect.equal(w.run("about").state, "written")
				local frames = w.player().about.T2
				expect.equal(#frames, 2, "overview and appearance")
				-- RegisterAbout.lua 398-401: an icon picked for a frame is SerializeIcon(iconInfo.id).
				frames[2].IC = Fake.SerializeIcon(case.icon or frames[2].IC)
				w.char().story.prefs.trp3Sections = { on = { appearance = false } }
				expect.equal(w.run("about").state, case.state, case.icon or "the same icon")
				if case.state == "written" then
					expect.equal(#w.player().about.T2, 1, "the frame Dawnward no longer needs is removed")
				else
					expect.equal(w.player().about.T2[2].IC, "900015", "the player's own icon is kept")
				end
			end
		end)
	end)

	-- Icons Dawnward names on 3.5.x must be ones 3.5.4 itself proves on every
	-- client it loads on (the ONLY candidate of an interface icon,
	-- Resources/InterfaceIcons.lua, or its built-in default 134400 /
	-- inv_misc_questionmark, lines 6-7), as for trait icons (VERIFIED_354).
	t:describe("Total RP 3 3.5.x: About and At First Glance icon evidence (L2, fake 3.5.4)", function()
		t:it("About frames and Arcane headings use only 3.5.4-proven icons; 3.4.1's choices are unchanged", function()
			local w = world({ about = { v = 2, TE = 2, T2 = {} } })
			local P = w.ns.TRP3Presentation
			w.overview("A wandering scholar.")
			w.field("appearance", "Grey eyes.")
			w.char().story.prefs.trp3Style = "arcane"
			w.enable("about")
			expect.equal(w.run("about").state, "written")
			local frames = w.player().about.T2
			expect.equal(#frames, 2)
			for _, f in ipairs(frames) do
				expect.truthy(P.ICONS_354[f.IC], tostring(f.IC) .. " is proven on 3.5.4")
				for icon in f.TX:gmatch("{icon:([^:}]+):") do
					expect.truthy(P.ICONS_354[icon:lower()], icon .. " (inline) is proven on 3.5.4")
				end
			end
			expect.equal(frames[2].IC, P.FALLBACK_ICON_354, "appearance: spell_nature_strength is unproven")
			expect.falsy(contains(w.player().about, "spell_nature_strength"))
			expect.equal(w.run("about").state, "noop", "no churn")
			-- 3.4.1 (and Dawnward's own preview) keep the original choices.
			expect.equal(P.SafeIcon(nil, "appearance"), "spell_nature_strength")
			expect.equal(P.SafeIcon(nil, "developments"), "inv_scroll_02")
			expect.equal(P.SafeIcon("inv_scroll_02", "overview", P.ICONS_354), "inv_misc_book_09")
			expect.equal(P.SafeIcon("inv_misc_note_06", "overview", P.ICONS_354), "inv_misc_note_06")
			expect.equal(P.SafeIcon(nil, "developments", P.ICONS_354), P.FALLBACK_ICON_354)
			expect.equal(P.IconSet(w.ns.TRP3VersionProfiles.Get("3.4.1").adapters), nil)
			expect.equal(P.IconSet(w.ns.TRP3VersionProfiles.Get("3.5.4").adapters), P.ICONS_354)
			for name in pairs(P.ICONS_354) do expect.truthy(P.ICONS[name], name .. " is also on the 3.4.1 list") end
		end)

		t:it("At First Glance presets unproven on 3.5.4 fall back; the player's typed icon is kept", function()
			for _, case in ipairs({ { icon = "spell_nature_strength", want = "inv_misc_questionmark" },
				{ icon = "inv_misc_note_02", want = "inv_misc_questionmark" },
				{ icon = "spell_arcane_mindmastery", want = "spell_arcane_mindmastery" },
				{ icon = "inv_misc_bone_01", want = "inv_misc_bone_01" } }) do
				local w = world()
				w.glance(1, "Silver scar")
				assert(w.ns.Glance.SetIcon(w.char(), 1, case.icon, 1))
				w.enable("glance")
				expect.equal(w.run("glance").state, "written")
				expect.equal(w.player().misc.PE["1"].IC, case.want, case.icon)
				expect.equal(w.run("glance").state, "noop", case.icon .. ": no churn")
				-- 3.4.1 writes the chosen icon as before.
				local c = world(nil, Fake341)
				c.glance(1, "Silver scar")
				assert(c.ns.Glance.SetIcon(c.char(), 1, case.icon, 1))
				c.enable("glance")
				expect.equal(c.run("glance").state, "written")
				expect.equal(c.player().misc.PE["1"].IC, case.icon, case.icon .. " on 3.4.1")
			end
			local w = world()
			local choices = {}
			for _, choice in ipairs(w.ns.Glance.ICON_CHOICES) do choices[choice] = true end
			for name in pairs(w.ns.TRP3GlancePlan.VERIFIED_354) do
				expect.truthy(choices[name], name .. " is one of Dawnward's presets")
			end
		end)
	end)
end
