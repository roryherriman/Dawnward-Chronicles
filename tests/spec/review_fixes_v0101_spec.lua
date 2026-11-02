-- L1/L2 (v0.10.1): regressions found by the independent review before the
-- 0.10.1 merge, each run against the code (TRP3 3.4.1 fake and WoW mock;
-- not in-game evidence). Data shapes follow the TRP3 3.4.1 source:
-- Modules/Register/Characters/RegisterAbout.lua (templates 1-3: T1.TX,
-- T2 frames { TX, IC, BK }, T3 PH/PS/HI), Core/Utils.lua 441-711
-- (convertTextTags, toHTML), Core/Player.lua 413-494 (the setters).
local Loader = require("support.loader")
local Boot = require("support.boot")
local Fake = require("fakes.trp3_341")

local KEY = "Testchar-TestRealm"

local function click(button)
	button:GetScript("OnClick")(button)
end

-- The status/look world of trp3_status_style_spec (pure Lua, fake TRP3).
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
	local w = { ns = ns, fake = fake, deps = deps, Sync = ns.TRP3Sync }
	w.ctx = { store = store, characterKey = KEY, now = deps.now, trp3Deps = function() return deps end }
	function w.char() return assert(store:EnsureCharacter(KEY, 1)) end
	function w.set(id, value) return ns.TRP3Commands.SetStatus(w.ctx, id, value) end
	function w.manage(...)
		for _, id in ipairs({ ... }) do assert(w.Sync.SetPolicy(deps, id, "dawnward")) end
	end
	function w.run(feature) return w.Sync.RunFeature(deps, feature) end
	return w
end

-- The add-on booted under the WoW mock with the TRP3 fake (UI specs).
local function boot()
	local fake = Fake.new({})
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

local BIO = { { id = "biography", title = "Biography", chapters = { { body = "Bio text." } } } }

-- What TRP3 3.4.1 shows of a text, by its own order of work (Core/Utils.lua
-- toHTML): structure tags (lines 475-485) and images (503-507, 662-675)
-- become HTML elements first, and the {col} tags become |c...|r last (line
-- 709), so a colour never crosses an element. Returns the visible text
-- outside headings that is NOT in a {col} colour (TRP3's gold), or "".
local function goldText(text)
	local html = text
	html = html:gsub("{img%:[^:]+%:[^:]+%:[^:}]+%:?[^:}]*%}", "<IMG>")
	html = html:gsub("!%[[^%]]-\\[^%]]-%]%([^%)]-%)", "<IMG>")
	html = html:gsub("{h%d:?[cr]?}", "<H>"):gsub("{/h%d}", "</H>")
	html = html:gsub("{p:?[cr]?}", "<P>"):gsub("{/p}", "</P>")
	local gold, coloured, heading, i = {}, false, false, 1
	while i <= #html do
		local tag = html:match("^<[^>]*>", i)
		local col = html:match("^{col:%x%x%x%x%x%x}", i)
		local close = html:match("^{/col}", i)
		if tag then
			coloured = false
			if tag == "<H>" then heading = true elseif tag == "</H>" then heading = false end
			i = i + #tag
		elseif col then
			coloured = true
			i = i + #col
		elseif close then
			coloured = false
			i = i + #close
		else
			local c = html:sub(i, i)
			-- (A line break inside one element keeps its colour code open.)
			if c ~= "\n" and not coloured and not heading and c:match("%S") then
				gold[#gold + 1] = c
			end
			i = i + 1
		end
	end
	return table.concat(gold)
end

return function(t, expect)
	t:describe("About takeover (adopt) never wipes the player's later text (review 1)", function()
		t:it("takes over only the slots Dawnward writes; a slot it does not need stays the player's", function()
			local A = Loader.WithTRP3().TRP3AboutDoc
			local about = { TE = 3, T3 = { PH = { TX = "my phys" }, PS = { TX = "my psycho" }, HI = { TX = "my hist" } } }
			local p = A.Plan(about, nil, BIO, { adopt = true })
			expect.equal(p.action, "insert")
			expect.equal(p.about.T3.PS.TX, "my psycho", "Dawnward has no personality text: PS untouched")
			expect.equal(p.about.T3.PH.TX, "my phys", "no appearance: PH untouched")
			expect.truthy(p.about.T3.HI.TX:find("Bio text.", 1, true), "HI taken over")
			expect.falsy(p.about.T3.HI.TX:find("my hist", 1, true), "the history the player handed over")
			expect.deepEqual(p.record.slots.PS, nil)
			expect.deepEqual(p.record.slots.PH, nil)
			-- The player writes their own personality text afterwards.
			p.about.T3.PS.TX = "new psych written after takeover"
			local p2 = A.Plan(p.about, p.record, BIO, {})
			expect.equal(p2.action, "noop")
			expect.equal(p2.about.T3.PS.TX, "new psych written after takeover", "never wiped")
			-- Later Dawnward has a personality description: appended after the
			-- player's own text, never replacing it, and updated in place.
			local withPs = { BIO[1], { id = "personality", title = "Personality", chapters = { { body = "Calm." } } } }
			local p3 = A.Plan(p2.about, p2.record, withPs, {})
			expect.equal(p3.action, "replace")
			expect.truthy(p3.about.T3.PS.TX:find("^new psych written after takeover\n\n"), p3.about.T3.PS.TX)
			expect.truthy(p3.about.T3.PS.TX:find("Calm.", 1, true))
			local calmer = { BIO[1], { id = "personality", title = "Personality", chapters = { { body = "Calmer." } } } }
			local p4 = A.Plan(p3.about, p3.record, calmer, {})
			expect.equal(p4.action, "replace", tostring(p4.reason))
			expect.truthy(p4.about.T3.PS.TX:find("^new psych written after takeover\n\n"))
			expect.truthy(p4.about.T3.PS.TX:find("Calmer.", 1, true))
			expect.falsy(p4.about.T3.PS.TX:find("Calm.", 1, true))
			-- Dawnward's personality text gone again: only its part comes out.
			local p5 = A.Plan(p4.about, p4.record, BIO, {})
			expect.equal(p5.about.T3.PS.TX, "new psych written after takeover")
		end)

		t:it("a slot Dawnward owned and no longer needs is emptied once, then the player's", function()
			local A = Loader.WithTRP3().TRP3AboutDoc
			local withPs = { BIO[1], { id = "personality", title = "Personality", chapters = { { body = "Calm." } } } }
			local p = A.Plan({ TE = 3, T3 = { PS = { TX = "old" } } }, nil, withPs, { adopt = true })
			expect.truthy(p.record.slots.PS)
			local p2 = A.Plan(p.about, p.record, BIO, {})
			expect.equal(p2.about.T3.PS.TX, nil, "Dawnward's own text comes out")
			p2.about.T3.PS.TX = "The player's own"
			local p3 = A.Plan(p2.about, p2.record, BIO, {})
			expect.equal(p3.action, "noop")
			expect.equal(p3.about.T3.PS.TX, "The player's own")
		end)
	end)

	t:describe("a template change after a takeover appends to the new template (review 2)", function()
		t:it("1 -> 3: the player's physical, personality and history texts stay", function()
			local A = Loader.WithTRP3().TRP3AboutDoc
			local about = { TE = 1, T1 = { TX = "player t1" },
				T3 = { PH = { TX = "my phys" }, PS = { TX = "my psycho" }, HI = { TX = "my hist" } } }
			local p = A.Plan(about, nil, BIO, { adopt = true, template = 1 })
			expect.equal(p.record.mode, "adopt")
			local p2 = A.Plan(p.about, p.record, BIO, { template = 3 })
			expect.equal(p2.about.TE, 3)
			expect.equal(p2.about.T3.PH.TX, "my phys")
			expect.equal(p2.about.T3.PS.TX, "my psycho")
			expect.truthy(p2.about.T3.HI.TX:find("^my hist\n\n"), "appended after the player's history")
			expect.equal(p2.record.mode, "append")
			expect.equal(p2.about.T1.TX, nil, "the taken-over template 1 text is Dawnward's and comes out")
		end)

		t:it("3 -> 2: the player's frames stay", function()
			local A = Loader.WithTRP3().TRP3AboutDoc
			local about = { TE = 3, T3 = { HI = { TX = "my hist" } }, T2 = { { TX = "my frame", IC = "x", BK = 2 } } }
			local p = A.Plan(about, nil, BIO, { adopt = true })
			local p2 = A.Plan(p.about, p.record, BIO, { template = 2 })
			expect.equal(p2.about.TE, 2)
			expect.equal(#p2.about.T2, 2)
			expect.deepEqual(p2.about.T2[1], { TX = "my frame", IC = "x", BK = 2 })
			expect.truthy(p2.about.T2[2].TX:find("Bio text.", 1, true))
			expect.equal(p2.record.mode, "append")
		end)

		t:it("2 -> 1: the player's text stays", function()
			local A = Loader.WithTRP3().TRP3AboutDoc
			local about = { TE = 2, T1 = { TX = "player t1" }, T2 = { { TX = "my frame", IC = "x", BK = 2 } } }
			local p = A.Plan(about, nil, BIO, { adopt = true })
			expect.equal(#p.about.T2, 1, "the frames were taken over")
			local p2 = A.Plan(p.about, p.record, BIO, { template = 1 })
			expect.equal(p2.about.TE, 1)
			expect.truthy(p2.about.T1.TX:find("^player t1\n\n"), p2.about.T1.TX)
			expect.equal(#(p2.about.T2 or {}), 0, "Dawnward's taken-over frames come out")
			expect.equal(p2.record.mode, "append")
		end)
	end)

	t:describe("backups: origins kept, and one section cannot push out another's (review 3)", function()
		local function add(L, led, sec, owner, pin, feat)
			return assert(L.AddBackup(led, "0123456789-ABCDEF", sec, { v = 1 }, { reason = sec, ownerFeature = feat,
				owner = owner, owners = owner and { [feat] = owner } or nil, pin = pin }, 1))
		end
		local function count(led, section, pin)
			local n = 0
			for _, b in ipairs(led.backups) do
				if (not section or b.section == section) and (pin == nil or b.pin == pin) then n = n + 1 end
			end
			return n
		end

		t:it("keeps every section's origin and the reclaim pin through many status writes", function()
			local L = Loader.WithTRP3().TRP3Ledger
			local led = L.Normalize(nil)
			add(L, led, "about", nil, nil, "about")
			add(L, led, "about", { slots = { T1 = "x" }, template = 1, mode = "append", frames = {} }, nil, "about")
			add(L, led, "characteristics", nil, nil, "fields")
			add(L, led, "misc", nil, nil, "glance")
			add(L, led, "character", nil, nil, "status")
			add(L, led, "character", { currently = { value = "x" } }, "reclaim", "status")
			for _ = 1, 25 do add(L, led, "character", { currently = { value = "x" } }, nil, "status") end
			for _, section in ipairs({ "about", "characteristics", "misc", "character" }) do
				expect.equal(count(led, section, "origin"), 1, section .. ": its origin is kept")
			end
			expect.equal(count(led, nil, "reclaim"), 1, "the reclaim pin is kept")
			expect.equal(count(led, "about"), 2, "the About's own later backup is not pushed out")
			expect.equal(#led.backups, L.LIMITS.backups, "still bounded")
			-- Loading keeps all of it (no schema change).
			local again = assert(L.Normalize(led))
			expect.deepEqual(again.backups, led.backups)
		end)

		t:it("bounds reclaim pins on their own, and loads an older ledger with more pins", function()
			local L = Loader.WithTRP3().TRP3Ledger
			local led = L.Normalize(nil)
			add(L, led, "about", nil, nil, "about")
			for _ = 1, L.LIMITS.pinned + 2 do
				add(L, led, "character", { currently = { value = "x" } }, "reclaim", "status")
			end
			expect.equal(count(led, nil, "reclaim"), L.LIMITS.pinned)
			expect.equal(count(led, "about", "origin"), 1, "a reclaim never unpins an origin")
			local old = { schemaVersion = 2, backups = {} }
			for i = 1, 8 do
				old.backups[i] = { id = i, profileId = "0123456789-ABCDEF", section = i % 2 == 0 and "misc" or "about",
					data = led.backups[1].data, pin = "origin" }
			end
			local loaded = assert(L.Normalize(old))
			expect.equal(count(loaded, "about", "origin"), 1, "one origin per section: the newest")
			expect.equal(count(loaded, "misc", "origin"), 1)
			expect.equal(#loaded.backups, 8, "no backup is lost on load")
		end)
	end)

	t:describe("v0.10 frames take a chosen style (review 4)", function()
		t:it("applies the chosen icon and background to a frame in Dawnward's style; a restyled one keeps its own", function()
			local ns = Loader.WithTRP3()
			local A = ns.TRP3AboutDoc
			expect.falsy(ns.TRP3Presentation.ICONS["ability_rogue_sprint"], "an icon Dawnward never writes")
			local doc = { { id = "overview", title = "Character overview", icon = "inv_scroll_02", background = 4,
				chapters = { { body = "Over." } } },
				{ id = "biography", title = "Biography", icon = "inv_scroll_02", background = 4,
					chapters = { { body = "Bio text." } } } }
			local f1 = "{h2}Character overview{/h2}\nOld over."
			local f2 = "{h2}The fall{/h2}\nBio text."
			local about = { TE = 2, T2 = { { TX = "mine", IC = "x", BK = 2 },
				{ TX = f1, IC = "inv_misc_book_09", BK = 1 }, { TX = f2, IC = "ability_rogue_sprint", BK = 1 } } }
			local rec = { template = 2, mode = "append", slots = {}, frames = { f1, f2 } }
			local p = A.Plan(about, rec, doc, {})
			expect.equal(p.action, "replace")
			expect.equal(p.about.T2[2].IC, "inv_scroll_02", "a v0.10 frame in Dawnward's style takes the chosen icon")
			expect.equal(p.about.T2[2].BK, 4)
			expect.equal(p.about.T2[3].IC, "ability_rogue_sprint", "the player's own icon stays")
			expect.equal(p.about.T2[3].BK, 1)
			expect.deepEqual(p.about.T2[1], { TX = "mine", IC = "x", BK = 2 })
			expect.equal(p.record.frameStyles[1], "inv_scroll_02|4", "its style is recorded from now on")
			expect.equal(p.record.frameStyles[2], "", "a restyled frame's style stays unknown")
			local p2 = A.Plan(p.about, p.record, doc, {})
			expect.equal(p2.action, "noop")
		end)
	end)

	t:describe("Biography panel titles (review 5, 10)", function()
		t:it("a title typed before Up/Down is saved to the section it was typed for", function()
			local mock, _, ns = boot()
			mock.Slash("set summary A quiet paladin.")
			local parent = mock.env.CreateFrame("Frame", nil, mock.env.UIParent)
			parent:SetSize(820, 470)
			local panel = ns.TRP3BiographyPanel.Build(parent, 820, 470)
			panel:Refresh(ns.TRP3Commands.Overview(ns.ctx.trp3Deps()))
			local row
			for _, r in ipairs(panel.rows) do if r.id == "biography" then row = r end end
			row.title:SetFocus()
			row.title:SetText("Her long road")
			click(row.up)
			expect.equal(panel.rows[1].id, "biography", "moved up while the box had focus")
			expect.truthy(row.id ~= "biography", "the focused box now belongs to another section")
			row.title:ClearFocus()
			local prefs = ns.ctx.store.real.characters[KEY].story.prefs
			expect.equal(prefs.trp3Sections.titles.biography, "Her long road")
			expect.equal(prefs.trp3Sections.titles[row.id], nil, "the other section keeps its title")
		end)

		t:it("says how to write a personality description (there is a Personality field)", function()
			local _, _, ns = boot()
			local help = ns.TRP3BiographyPanel.HELP.empty.personality
			expect.truthy(help:find("Describe the personality on the Character page", 1, true), help)
			expect.truthy(ns.Schema.FIELD_BY_KEY.personality, "the field exists")
		end)
	end)

	t:describe("status rows with no Dawnward value are never paused (review 6)", function()
		t:it("an untrackable Total RP 3 value the player owns stays unpaused while Dawnward has nothing", function()
			local ns = Loader.WithTRP3()
			local F = ns.TRP3StatusPlan.STATUS
			local policies = { currently = "dawnward", ooc = "dawnward" }
			local big = string.rep("x", 1200)
			for _, value in ipairs({ "Fishing. ", "Line one\n", "a || b", big }) do
				local plan = F.Plan({ CU = value, CO = value }, nil, {}, policies)
				expect.deepEqual(plan.conflicts, {}, "nothing paused for " .. value:sub(1, 20))
				expect.equal(plan.rows[1].state, "empty")
				expect.equal(plan.action, "noop")
			end
			-- With a Dawnward value it still pauses (the player's value is never overwritten).
			local plan = F.Plan({ CU = "Fishing. " }, nil, { currently = "Mine" }, policies)
			expect.truthy(plan.conflicts.currently)
			local S = ns.TRP3StylePlan
			local m = S.MAPPINGS[1]
			local splan = S.Plan({ ST = { [m.key] = 99 } }, nil, {}, { [m.id] = "dawnward" })
			expect.deepEqual(splan.conflicts, {})
			expect.equal(splan.rows[1].state, "empty")
		end)
	end)

	t:describe("backup rows name every section (review 7)", function()
		t:it("labels About, Characteristics, Miscellaneous and Status and OOC", function()
			local _, _, ns, fake = boot()
			local deps = ns.ctx.trp3Deps()
			for _, section in ipairs({ "about", "characteristics", "misc", "character" }) do
				assert(ns.TRP3Ledger.AddBackup(deps.ledger, fake.profileId, section, { v = 1 }, { reason = "test" }, 5))
			end
			ns.SettingsPanel.OpenPage("trp3")
			local page = ns.SettingsPanel.panel.trp3Page
			ns.MainWindow.Refresh()
			local names = {}
			for _, row in ipairs(page.backupRows) do
				if row:IsShown() then names[#names + 1] = row.name:GetText() end
			end
			local all = table.concat(names, "\n")
			for _, label in ipairs({ "About", "Characteristics", "Miscellaneous", "Status and OOC" }) do
				expect.truthy(all:find(" " .. label .. " · ", 1, true), label .. " in:\n" .. all)
			end
		end)
	end)

	t:describe("status view and rollback preview compare as Total RP 3 does (review 8)", function()
		t:it("a colour in another case is the same colour", function()
			local w = world()
			assert(w.set("classColor", "c41f3b"))
			w.manage("classColor")
			expect.equal(w.run("look").state, "written")
			w.fake.profile.player.characteristics.CH = "C41F3B"
			local row = w.Sync.StatusView(w.deps).rows.classColor
			expect.truthy(row.owned, "still Dawnward's")
			expect.falsy(row.differ)
			expect.falsy(row.importable)
			local backup = assert(w.ns.TRP3Ledger.AddBackup(w.deps.ledger, w.fake.profileId, "characteristics",
				{ v = 1 }, { ownerFeature = "look", owner = { classColor = { value = "C41F3B" } } }, 5))
			local preview = assert(w.Sync.RollbackPreview(w.deps, backup.id))
			for _, item in ipairs(preview.items) do
				expect.falsy(item:find("Class colour", 1, true), item)
			end
		end)
	end)

	t:describe("body colour across the player's block markup (review 9)", function()
		t:it("no line of text falls back to Total RP 3's gold", function()
			local P = Loader.WithTRP3().TRP3Presentation
			local style = { body = "e8e0d0" }
			local lines = { "plain", "{p:c}Centered{/p}", "{p:r}Right", "and more{/p}", "a {h1}Head{/h1} b",
				"x {img:Interface\\A:64:64} y", "![Interface\\X](64) z", "{col:ff0000}red{/col} rest", "{p}a{/p} b" }
			for _, line in ipairs(lines) do
				local out = P.Body(style, line)
				expect.equal(goldText(out), "", line .. " -> " .. out)
				expect.equal(P.Visible(out), P.Visible(line), "nothing but colour is added")
			end
			local multi = P.Body(style, "{p:c}one\ntwo{/p}")
			expect.equal(multi, "{p:c}{col:e8e0d0}one{/col}\n{col:e8e0d0}two{/col}{/p}")
			expect.equal(goldText(multi), "")
			expect.equal(P.Body(style, "{p:c}Centered{/p}"), "{p:c}{col:e8e0d0}Centered{/col}{/p}")
			expect.equal(P.Body(style, "a {h1}Head{/h1} b"), "{col:e8e0d0}a {/col}{h1}Head{/h1}{col:e8e0d0} b{/col}",
				"a heading of the player's keeps TRP3's heading colour")
		end)
	end)

	t:describe("simulation mode refuses the Total RP 3 page's choices (review 11)", function()
		t:it("SetStatus, glance, style and About choices are refused with a clear message", function()
			local w = world()
			local C = w.ns.TRP3Commands
			w.char()
			local before = w.ns.Util.DeepCopy(w.deps.store.real)
			w.deps.store:SetSimulation(true)
			local calls = {
				function() return C.SetStatus(w.ctx, "currently", "Fishing.") end,
				function() return C.SaveGlance(w.ctx, 1, { title = "Scar", text = "A burn." }) end,
				function() return C.SetGlance(w.ctx, "title", 1, "Scar") end,
				function() return C.MoveGlance(w.ctx, 1, 1) end,
				function() return C.SetStyle(w.ctx, "2", 1) end,
				function() return C.SetAboutSection(w.ctx, "on", "motivation", true) end,
				function() return C.SetAboutAccent(w.ctx, "violet") end,
				function() return C.SetAboutPref(w.ctx, "trp3Style", "arcane") end,
			}
			for i, call in ipairs(calls) do
				local ok, message = call()
				expect.falsy(ok, "call " .. i)
				expect.truthy(tostring(message):find("simulation mode", 1, true), "call " .. i .. ": " .. tostring(message))
			end
			expect.deepEqual(w.deps.store.real, before, "the real character is unchanged")
			expect.equal(w.deps.store.sim.characters[KEY], nil, "nothing written to the simulated data either")
			w.deps.store:SetSimulation(false)
			expect.truthy(C.SetStatus(w.ctx, "currently", "Fishing."), "allowed again outside simulation")
		end)
	end)

	t:describe("an exact status rollback reads back with kept statuses (review 12)", function()
		t:it("a backup without roleplay status or walk-up restores without a read-back failure", function()
			local w = world()
			local ch = w.fake.profile.player.character
			ch.CU, ch.RP, ch.WU = nil, nil, nil
			assert(w.set("currently", "First"))
			w.manage("currently")
			expect.equal(w.run("status").state, "written")
			local first = w.deps.ledger.backups[1]
			local data = w.ns.TRP3Ledger.BackupData(first)
			expect.equal(data.RP, nil)
			expect.equal(data.WU, nil)
			-- The player sets a status in Total RP 3 afterwards (it has no "empty").
			w.fake.env.AddOn_TotalRP3.Player.GetCurrentUser():SetRoleplayStatus(1)
			local ok, message = w.Sync.Rollback(w.deps, first.id, "exact")
			expect.truthy(ok, message)
			expect.equal(ch.CU, "", "Currently back to empty")
			expect.equal(w.fake.profile.player.character.RP, 1, "the status is kept")
		end)
	end)
end
