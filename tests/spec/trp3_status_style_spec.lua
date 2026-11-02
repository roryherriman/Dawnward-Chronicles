-- L2 (v0.10.1): the player's Total RP 3 status and look (Currently, OOC,
-- roleplay status, walk-up, profile icon, class colour) through Total RP
-- 3's own public setters, and the roleplay style preferences the player
-- hands to Dawnward one by one, against the TRP3 3.4.1 fake (mocked; not
-- in-game evidence). Data shapes and behaviour follow the TRP3 3.4.1
-- source: Core/Player.lua 413-494 (UpdateProfileField and the setters),
-- Core/Enums.lua 25-53 (ROLEPLAY_STATUS, WALKUP), Modules/Dashboard/
-- Dashboard.lua 30 (the default character section), Modules/Register/
-- Characters/RegisterMisc.lua 28-120 (STYLE_FIELDS, onEditStyle) and
-- Locales/enUS.lua 142-158, 836-840, 996 (labels).
local Loader = require("support.loader")
local Fake = require("fakes.trp3_341")

return function(t, expect)
	local KEY = "Testchar-TestRealm"

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
		local w = { ns = ns, fake = fake, deps = deps, Sync = ns.TRP3Sync, RPStatus = ns.RPStatus }
		w.ctx = { store = store, characterKey = KEY, now = deps.now, trp3Deps = function() return deps end }
		function w.char() return assert(store:EnsureCharacter(KEY, 1)) end
		function w.set(id, value) return ns.TRP3Commands.SetStatus(w.ctx, id, value) end
		function w.manage(...)
			for _, id in ipairs({ ... }) do assert(w.Sync.SetPolicy(deps, id, "dawnward")) end
		end
		function w.run(feature) return w.Sync.RunFeature(deps, feature) end
		function w.ch() return fake.profile.player.character end
		function w.record() return deps.ledger.profiles[fake.profileId] end
		function w.calls()
			local out = {}
			for _, c in ipairs(fake.setterLog) do out[#out + 1] = c.name end
			return out
		end
		return w
	end

	t:describe("status store (Core/RPStatus.lua)", function()
		t:it("keeps only the player's own values, checked against Total RP 3's value sets", function()
			local w = world()
			local char = w.char()
			expect.deepEqual(char.trp3status, { style = {} }, "a new character has none")
			expect.truthy(w.RPStatus.Set(char, "currently", "Mending nets |cffff0000by|r the |Tx|tdock.", 1))
			expect.equal(char.trp3status.currently, "Mending nets by the dock.", "escape codes TRP3 strips are removed")
			expect.falsy(w.RPStatus.Set(char, "rpStatus", 3, 1), "ROLEPLAY_STATUS is 1 or 2")
			expect.truthy(w.RPStatus.Set(char, "rpStatus", 1, 1))
			expect.falsy(w.RPStatus.Set(char, "walkup", 0, 1), "WALKUP is 1 or 2")
			expect.falsy(w.RPStatus.Set(char, "classColor", "red", 1))
			expect.equal(w.RPStatus.Set(char, "classColor", "#C41F3B", 1), "c41f3b")
			expect.falsy(w.RPStatus.Set(char, "icon", "|Tbad|t", 1))
			expect.falsy(w.RPStatus.SetStyle(char, "2", 4, 1), "injury: 0..3 only")
			expect.falsy(w.RPStatus.SetStyle(char, "6", 3, 1), "guild membership has no 3")
			expect.truthy(w.RPStatus.SetStyle(char, "6", 2, 1))
			assert(w.RPStatus.Clear(char, "currently", 1))
			expect.equal(char.trp3status.currently, "", "a cleared text is kept as a deliberate clear")
			assert(w.RPStatus.Clear(char, "rpStatus", 1))
			expect.equal(char.trp3status.rpStatus, nil, "a status is forgotten")
			-- Total RP 3's exact labels (enUS), in its own order.
			local labels = {}
			for _, s in ipairs(w.RPStatus.STYLE) do labels[#labels + 1] = s.key .. " " .. s.label end
			expect.deepEqual(labels, { "2 Accept character injury", "3 Accept character death",
				"4 Accept character romance", "7 Accept criminal activity", "8 Accept loss of control",
				"6 Guild membership" })
			expect.equal(w.RPStatus.OptionLabel(w.RPStatus.STYLE[1].options, 3), "With player permission")
			expect.equal(w.RPStatus.OptionLabel(w.RPStatus.STYLE[6].options, 2), "OOC membership")
			expect.equal(w.RPStatus.OptionLabel(w.RPStatus.BY_ID.rpStatus.options, 2), "Out of character")
		end)

		t:it("loads older saved data, and drops what is damaged", function()
			local w = world()
			local old = w.ns.Util.DeepCopy(w.char())
			old.trp3status = nil
			expect.deepEqual(w.ns.Schema.NormalizeCharacter(old).trp3status, { style = {} }, "a v0.10 character")
			old.trp3status = { currently = 7, ooc = "Fine", rpStatus = 9, walkup = 2, icon = "inv_misc_note_02",
				classColor = "zzzzzz", style = { ["2"] = 1, ["99"] = 1, ["3"] = "yes" }, junk = true }
			expect.deepEqual(w.ns.Schema.NormalizeCharacter(old).trp3status, { ooc = "Fine", walkup = 2,
				icon = "inv_misc_note_02", style = { ["2"] = 1 } })
		end)

		t:it("Suggest drafts from the zone and the established active goal, and saves nothing", function()
			local w = world()
			local char = w.char()
			expect.equal(w.RPStatus.Suggest(char, nil), nil, "nothing known: no suggestion")
			local before = w.ns.Util.DeepCopy(char)
			expect.equal(w.RPStatus.Suggest(char, "Elwynn Forest"), "In Elwynn Forest.")
			expect.deepEqual(char, before, "a suggestion changes nothing")
		end)
	end)

	t:describe("the fake's setters follow UpdateProfileField (Core/Player.lua 413-436)", function()
		t:it("refuses all but RP and WU on the default profile, and ignores an unchanged value", function()
			local fake = Fake.new({ isDefault = true })
			local user = fake.env.AddOn_TotalRP3.Player.GetCurrentUser()
			local before = fake.snapshot()
			user:SetCurrentlyText("Hello")
			user:SetCustomIcon("inv_misc_note_02")
			expect.deepEqual(fake.snapshot(), before, "CU and IC refused on the default profile")
			user:SetRoleplayStatus(1)
			expect.equal(fake.profile.player.character.RP, 1, "RP is allowed")
			local named = Fake.new()
			local u = named.env.AddOn_TotalRP3.Player.GetCurrentUser()
			local v = named.profile.player.character.v
			u:SetCurrentlyText("Hello")
			expect.equal(named.profile.player.character.v, v + 1)
			expect.equal(named.events[#named.events].args[3], "character")
			u:SetCurrentlyText("Hello")
			expect.equal(named.profile.player.character.v, v + 1, "unchanged: no new version")
			expect.errors(function() u:SetCustomClassColor(nil) end, "expected hex color")
		end)
	end)

	t:describe("status sync through the public setters (L2)", function()
		t:it("writes nothing until the player keeps a value in sync, then only through the setter", function()
			local w = world()
			assert(w.set("currently", "Mending nets by the dock."))
			expect.equal(w.run("status").state, "off", "not kept in sync: nothing")
			expect.equal(#w.fake.setterLog, 0)
			w.manage("currently")
			local v = w.ch().v
			local r = w.run("status")
			expect.equal(r.state, "written", r.message)
			expect.deepEqual(w.calls(), { "SetCurrentlyText" })
			expect.equal(w.ch().CU, "Mending nets by the dock.")
			expect.equal(w.ch().v, v + 1, "TRP3's setter versions it")
			expect.deepEqual(w.record().status, { currently = { value = "Mending nets by the dock." } })
			expect.equal(w.deps.ledger.backups[1].section, "character", "backed up first")
			-- No write when equal.
			expect.equal(w.run("status").state, "noop")
			expect.equal(#w.fake.setterLog, 1)
			-- An update, then a clear.
			assert(w.set("currently", "Asleep at the inn."))
			expect.equal(w.run("status").state, "written")
			expect.equal(w.ch().CU, "Asleep at the inn.")
			assert(w.set("currently", nil))
			expect.equal(w.run("status").state, "written")
			expect.equal(w.ch().CU, "", "emptied as Total RP 3's own editor empties it")
			expect.equal(w.record().status, nil, "nothing of Dawnward's is left")
		end)

		t:it("never touches the other sections or other status values", function()
			local w = world()
			w.fake.profile.player.character.CO = "Player's own OOC note"
			local before = w.fake.snapshot()
			assert(w.set("currently", "Busy"))
			w.manage("currently")
			w.run("status")
			local after = w.fake.snapshot()
			expect.deepEqual(after.player.about, before.player.about)
			expect.deepEqual(after.player.characteristics, before.player.characteristics)
			expect.deepEqual(after.player.misc, before.player.misc)
			expect.equal(after.player.character.CO, "Player's own OOC note")
			expect.equal(after.player.character.RP, before.player.character.RP)
		end)

		t:it("a Total RP 3 edit after Dawnward's write pauses that row; keep or use Dawnward's", function()
			local w = world()
			assert(w.set("ooc", "Ask me about the guild."))
			assert(w.set("currently", "Fishing."))
			w.manage("ooc", "currently")
			w.run("status")
			w.fake.env.AddOn_TotalRP3.Player.GetCurrentUser():SetOutOfCharacterInfo("Edited in TRP3")
			assert(w.set("ooc", "Dawnward's new note"))
			assert(w.set("currently", "Fishing again."))
			local r = w.run("status")
			expect.equal(r.state, "written", "the other row still updates")
			expect.equal(w.ch().CO, "Edited in TRP3", "never overwritten")
			expect.equal(w.ch().CU, "Fishing again.")
			expect.truthy(w.record().fieldConflicts.ooc:find("changed in Total RP 3", 1, true))
			-- Use Dawnward's: a pinned backup keeps the player's value, then the next run writes.
			assert(w.Sync.Resolve(w.deps, "ooc", "reclaim"))
			local pinned = w.deps.ledger.backups[#w.deps.ledger.backups]
			expect.equal(pinned.pin, "reclaim")
			expect.equal(pinned.section, "character")
			expect.equal(w.run("status").state, "written")
			expect.equal(w.ch().CO, "Dawnward's new note")
			-- Edited again, then Keep yours: handed to Total RP 3 for good.
			w.fake.env.AddOn_TotalRP3.Player.GetCurrentUser():SetOutOfCharacterInfo("Mine again")
			w.run("status")
			assert(w.Sync.Resolve(w.deps, "ooc", "keep"))
			expect.equal(w.ns.TRP3Ledger.Policy(w.deps.ledger.optIn[KEY], "ooc"), "trp3")
			w.run("status")
			expect.equal(w.ch().CO, "Mine again")
		end)

		t:it("an existing Total RP 3 value is offered for import, never overwritten", function()
			local w = world()
			w.fake.profile.player.character.CU = "The player's own Currently"
			assert(w.set("currently", "Dawnward's text"))
			w.manage("currently")
			expect.equal(w.run("status").state, "conflict")
			expect.equal(w.ch().CU, "The player's own Currently")
			local view = w.Sync.StatusView(w.deps)
			expect.truthy(view.rows.currently.importable)
			expect.truthy(view.rows.currently.conflict:find("already has your own", 1, true))
			assert(w.ns.TRP3Commands.ImportStatus(w.ctx, "currently"))
			expect.equal(w.char().trp3status.currently, "The player's own Currently")
			expect.equal(w.record().fieldConflicts.currently, nil, "the pause ends")
			expect.equal(w.run("status").state, "noop", "both agree: nothing written")
			assert(w.set("currently", "Now from Dawnward"))
			expect.equal(w.run("status").state, "written", "Dawnward keeps it from now on")
			expect.equal(w.ch().CU, "Now from Dawnward")
		end)

		t:it("takes over a value Total RP 3 already shows exactly, without writing", function()
			local w = world()
			w.fake.profile.player.character.CU = "Same text"
			assert(w.set("currently", "Same text"))
			w.manage("currently")
			expect.equal(w.run("status").state, "noop")
			expect.equal(#w.fake.setterLog, 0)
			expect.deepEqual(w.record().status, { currently = { value = "Same text" } })
		end)

		t:it("sets the roleplay status and walk-up through their setters, never inferring them", function()
			local w = world()
			w.manage("rpStatus", "walkup")
			expect.equal(w.run("status").state, "noop", "not set in Dawnward: nothing")
			-- The fake's profile is in character (RP 1); TRP3's template walk-up is NO (1).
			w.fake.profile.player.character.WU = nil
			assert(w.set("rpStatus", 2))
			assert(w.set("walkup", 2))
			local r = w.run("status")
			expect.equal(r.state, "written", "walk-up was free")
			expect.equal(w.ch().WU, 2)
			expect.equal(w.ch().RP, 1, "TRP3's own status is the player's: paused, not overwritten")
			expect.truthy(w.record().fieldConflicts.rpStatus)
			expect.deepEqual(w.calls(), { "SetWalkup" })
			assert(w.ns.TRP3Commands.ImportStatus(w.ctx, "rpStatus"))
			expect.equal(w.char().trp3status.rpStatus, 1)
			expect.equal(w.run("status").state, "noop")
			assert(w.set("rpStatus", 2))
			w.run("status")
			expect.equal(w.ch().RP, 2)
			expect.equal(w.fake.setterLog[#w.fake.setterLog].name, "SetRoleplayStatus")
		end)

		t:it("never writes the default profile, though Total RP 3 would accept RP there", function()
			local w = world({ isDefault = true })
			assert(w.set("rpStatus", 1))
			expect.falsy(w.Sync.SetPolicy(w.deps, "rpStatus", "dawnward"))
			w.deps.ledger.optIn[KEY] = { profileId = w.fake.profileId, policy = { rpStatus = "dawnward" } }
			expect.equal(w.run("status").state, "blocked")
			expect.equal(#w.fake.setterLog, 0)
		end)

		t:it("writes the profile icon and class colour through their setters; releasing keeps them", function()
			local w = world()
			assert(w.set("icon", "inv_misc_note_02"))
			assert(w.set("classColor", "c41f3b"))
			w.manage("icon", "classColor")
			local r = w.run("look")
			expect.equal(r.state, "written", r.message)
			expect.equal(w.fake.profile.player.characteristics.IC, "inv_misc_note_02")
			expect.equal(w.fake.profile.player.characteristics.CH, "c41f3b")
			expect.deepEqual(w.calls(), { "SetCustomIcon", "SetCustomClassColor" })
			assert(w.Sync.Release(w.deps, "look"))
			expect.equal(w.fake.profile.player.characteristics.IC, "inv_misc_note_02", "an icon has no empty value")
			expect.equal(w.record().look, nil, "no longer Dawnward's")
			expect.equal(w.ns.TRP3Ledger.Policy(w.deps.ledger.optIn[KEY], "icon"), "trp3")
		end)

		t:it("a rollback restores the status section through the setters", function()
			local w = world()
			w.fake.profile.player.character.CU = nil
			assert(w.set("currently", "First"))
			w.manage("currently")
			w.run("status")
			assert(w.set("currently", "Second"))
			w.run("status")
			expect.equal(w.ch().CU, "Second")
			local first = w.deps.ledger.backups[1]
			local ok, message = w.Sync.Rollback(w.deps, first.id, "exact")
			expect.truthy(ok, message)
			expect.equal(w.ch().CU, "", "back to before Dawnward's first write")
			expect.equal(w.fake.setterLog[#w.fake.setterLog].name, "SetCurrentlyText")
			expect.equal(w.ns.TRP3Ledger.Policy(w.deps.ledger.optIn[KEY], "currently"), "trp3", "exact: sync off")
			-- The safe restore rebuilds Dawnward's part from the player's value now.
			w.manage("currently")
			w.run("status")
			local latest = w.deps.ledger.backups[#w.deps.ledger.backups]
			expect.truthy(w.Sync.Rollback(w.deps, latest.id, "own"))
			expect.equal(w.ch().CU, "Second")
		end)

		t:it("follows profile switches, refuses a shared profile's second manager, and never writes in simulation",
			function()
			local w = world()
			assert(w.set("currently", "On the main profile"))
			w.manage("currently")
			w.run("status")
			w.fake.switchProfile("1700000000OTHER", "Other", { characteristics = { v = 1, PS = {} },
				about = { v = 1, TE = 1 }, misc = { v = 1, PE = {}, ST = {} }, character = { v = 1, RP = 2, WU = 1 } })
			assert(w.set("currently", "Changed"))
			local r = w.run("status")
			expect.equal(r.state, "blocked")
			expect.truthy(r.message:find("not the one sync was enabled for", 1, true))
			expect.equal(w.fake.profile.player.character.CU, nil, "the other profile is untouched")
			-- Another character on the same profile cannot manage the same row.
			local other = w.ns.Util.DeepCopy(w.deps)
			other.characterKey = "Second-TestRealm"
			w.fake.switchProfile("1700000000ABCDE", "Main")
			local ok, why = w.Sync.SetPolicy(other, "currently", "dawnward")
			expect.falsy(ok)
			expect.truthy(why:find("already synced by", 1, true))
			-- Simulation: nothing is written, and nothing is imported.
			w.deps.store:SetSimulation(true)
			expect.equal(w.run("status").state, "blocked")
			local imported, reason = w.ns.TRP3Commands.ImportStatus(w.ctx, "currently")
			expect.falsy(imported)
			expect.truthy(reason:find("simulation", 1, true))
		end)
	end)

	t:describe("roleplay style: read only unless handed over (L2)", function()
		t:it("is never written by default or by Connect everything", function()
			local w = world()
			local char = w.char()
			assert(w.RPStatus.SetStyle(char, "2", 1, 1))
			for _, s in ipairs(w.RPStatus.STYLE) do
				expect.equal(w.ns.TRP3Ledger.Policy(nil, s.id), "trp3", "read only by default")
				expect.truthy(w.ns.TRP3Ledger.OPT_IN_ONLY[s.id])
			end
			w.ctx.trp3RequestSync = function() end
			assert(w.ns.TRP3Commands.ConnectAll(w.ctx, {}))
			for _, s in ipairs(w.RPStatus.STYLE) do
				expect.equal(w.ns.TRP3Ledger.Policy(w.deps.ledger.optIn[KEY], s.id), "trp3", s.id)
			end
			expect.equal(w.run("style").state, "off")
			expect.deepEqual(w.fake.profile.player.misc.ST, {})
		end)

		t:it("writes a handed-over preference with a backup and read-back, keeping the glance slots", function()
			local w = world({ misc = { v = 4, PE = { ["1"] = { TI = "Player's slot", TX = "Mine", IC = "x", AC = true } },
				ST = { ["3"] = 2 } } })
			local char = w.char()
			assert(w.RPStatus.SetStyle(char, "2", 3, 1))
			assert(w.RPStatus.SetStyle(char, "3", 1, 1))
			w.manage("styleInjury", "styleDeath")
			local r = w.run("style")
			expect.equal(r.state, "written", r.message)
			local misc = w.fake.profile.player.misc
			expect.equal(misc.ST["2"], 3, "injury: with player permission")
			expect.equal(misc.ST["3"], 2, "death: the player's own choice is kept")
			expect.equal(misc.PE["1"].TI, "Player's slot")
			expect.equal(misc.v, 6, "Dawnward's two-step version")
			expect.equal(w.deps.ledger.backups[1].section, "misc")
			expect.truthy(w.record().fieldConflicts.styleDeath:find("own choice", 1, true))
			expect.equal(#w.fake.setterLog, 0, "no setter exists for the style")
			-- Changed in Total RP 3's own editor (onEditStyle writes ST directly): a pause.
			misc.ST["2"] = 2
			misc.v = misc.v + 1
			assert(w.RPStatus.SetStyle(char, "2", 1, 1))
			expect.equal(w.run("style").state, "conflict")
			expect.equal(misc.ST["2"], 2)
			expect.truthy(w.record().fieldConflicts.styleInjury:find("changed in Total RP 3", 1, true))
		end)
	end)

	t:describe("ledger compatibility (v0.10.1)", function()
		t:it("keeps status, look and style records, drops damaged ones, and reads an older ledger", function()
			local w = world()
			local Ledger = w.ns.TRP3Ledger
			local raw = { schemaVersion = 2, optIn = { [KEY] = { profileId = "P1", policy = { currently = "dawnward",
				styleRomance = "dawnward", bogus = "dawnward" } } },
				profiles = { P1 = { status = { currently = { value = "x" }, rpStatus = { value = 7 } },
					look = { classColor = { value = "c41f3b" }, icon = { value = "|T" } },
					style = { styleRomance = { value = 3 }, styleGuild = { value = 3 } },
					fieldConflicts = { walkup = "changed", nope = "x" } } },
				backups = {} }
			local clean = assert(Ledger.Normalize(raw))
			local p = clean.profiles.P1
			expect.deepEqual(p.status, { currently = { value = "x" } })
			expect.deepEqual(p.look, { classColor = { value = "c41f3b" } })
			expect.deepEqual(p.style, { styleRomance = { value = 3 } })
			expect.equal(p.fieldConflicts.walkup, "changed")
			expect.equal(p.fieldConflicts.nope, nil)
			expect.deepEqual(clean.optIn[KEY].policy, { currently = "dawnward", styleRomance = "dawnward" })
			-- A v0.10 ledger (no new keys) loads unchanged.
			local older = assert(Ledger.Normalize({ schemaVersion = 2, optIn = {}, profiles = { P1 = {} } }))
			expect.equal(older.profiles.P1.status, nil)
		end)
	end)

	t:describe("At First Glance: five entries, order, shown or hidden, icons (L2)", function()
		t:it("moves entries, and Total RP 3's owned slots follow; the player's slots never move", function()
			local w = world({ misc = { v = 1, PE = { ["4"] = { TI = "Player's own", TX = "Kept", IC = "x", AC = true } },
				ST = {} } })
			local Glance = w.ns.Glance
			local char = w.char()
			for n = 1, 3 do assert(Glance.Save(char, n, { title = "Entry " .. n, icon = "inv_misc_note_02" }, 1)) end
			assert(Glance.Save(char, 5, { title = "Hidden one", active = false }, 1))
			assert(w.Sync.SetOptIn(w.deps, "glance", true))
			expect.equal(w.run("glance").state, "written")
			local function PE() return w.fake.profile.player.misc.PE end
			expect.equal(PE()["1"].TI, "Entry 1")
			expect.equal(PE()["5"].AC, false, "hidden: kept but not sent")
			expect.equal(w.fake.miscExchange().PE["5"], nil)
			expect.equal(Glance.Move(char, 1, 1, 2), 2)
			expect.falsy(Glance.Move(char, 5, 1, 2), "already last")
			expect.equal(w.run("glance").state, "written")
			expect.equal(PE()["1"].TI, "Entry 2")
			expect.equal(PE()["2"].TI, "Entry 1")
			expect.equal(PE()["4"].TI, "Player's own")
			-- Saving an empty entry removes it (and Dawnward's slot).
			assert(Glance.Save(char, 3, { title = "", text = "" }, 3))
			w.run("glance")
			expect.equal(PE()["3"], nil)
			expect.equal(PE()["4"].TI, "Player's own")
			-- Every offered icon is a plain icon name.
			for _, name in ipairs(Glance.ICON_CHOICES) do expect.equal(Glance.CleanIcon(name), name) end
		end)
	end)
end
