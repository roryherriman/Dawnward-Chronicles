-- L2 (issue #24, WoW Forever track): the whole addon, booted from its TOC
-- in the WoW Forever 1.60.1 mock (tests/support/wow_mock.lua, client =
-- "forever") with the Total RP 3 3.5.4 fake (tests/fakes/trp3_354.lua)
-- installed in the same client environment. End to end: first-login setup,
-- story import, a disposable Total RP 3 profile created and kept in sync
-- (About, traits with icons, fields, At First Glance, Currently/OOC,
-- status), read-back, conflicts with manual edits, backup and rollback,
-- /reload and relog, repeated runs, a profile switch mid-run, combat; and
-- Total RP 3 late, disabled, missing or an unknown 3.5.x build.
--
-- Evidence label: L2 mocked / automated. Total RP 3 3.5.4 is the closest
-- available substitute for the build Forever players run (provisional), so
-- every result here is also Pending Live Forever Verification.
local Boot = require("support.boot")
local Fake = require("fakes.trp3_354")

local CHAR = "Testchar-TestRealm"
local DEFAULT_ID = "1700000000ABCD*"

local function click(button)
	button:GetScript("OnClick")(button)
end

local function deepCopy(v)
	if type(v) ~= "table" then return v end
	local out = {}
	for k, x in pairs(v) do out[k] = deepCopy(x) end
	return out
end

local function contains(tbl, needle)
	if type(tbl) == "string" then return tbl:find(needle, 1, true) ~= nil end
	if type(tbl) ~= "table" then return false end
	for k, v in pairs(tbl) do
		if contains(k, needle) or contains(v, needle) then return true end
	end
	return false
end

-- Boots the addon with the 3.5.4 fake in the client's environment.
-- opts.client: "forever" (default) or "classic"; opts.fake: fake options;
-- opts.savedVariables; opts.fakeInstance: reuse a fake (relog keeps
-- Total RP 3's own saved data); opts.loaded(): Total RP 3's load state.
local function boot(opts)
	opts = opts or {}
	local fake = opts.fakeInstance or Fake.new(opts.fake or {})
	local extra = {}
	for k, v in pairs(fake.env) do
		if k ~= "C_AddOns" then extra[k] = v end
	end
	local mockOpts = { extra = extra, savedVariables = opts.savedVariables }
	if opts.client ~= "classic" then mockOpts.client = "forever" end
	local mock, env, ns = Boot.Load(mockOpts)
	local loaded = opts.loaded or fake.env.C_AddOns.IsAddOnLoaded
	mock.env.C_AddOns.IsAddOnLoaded = function(name) return loaded(name) end
	local meta = mock.env.C_AddOns.GetAddOnMetadata
	mock.env.C_AddOns.GetAddOnMetadata = function(name, field)
		return fake.env.C_AddOns.GetAddOnMetadata(name, field) or meta(name, field)
	end
	Boot.Login(mock)
	ns.SetupLaunch.Reset()
	if not opts.wizard then ns.SetupWizard.SkipAutoLaunchThisSession(ns.ctx.characterKey) end
	return mock, env, ns, fake
end

local function chat(mock) return table.concat(mock.chat, "\n") end

-- No Lua error reached the player: the guarded entry points turn one into
-- these messages, so their absence means nothing failed underneath.
local function noErrors(expect, mock)
	local text = chat(mock)
	for _, needle in ipairs({ "failed safely", "unexpected error", "stack traceback", "attempt to " }) do
		expect.falsy(text:find(needle, 1, true), "no Lua error (" .. needle .. "): " .. text)
	end
end

local function saved(env)
	return { DawnwardChroniclesDB = env.DawnwardChroniclesDB, DawnwardChroniclesSimDB = env.DawnwardChroniclesSimDB,
		DawnwardChroniclesTRP3DB = env.DawnwardChroniclesTRP3DB }
end

local function accept(ns)
	local d = ns.Widgets.dialog
	assert(d and d:IsShown(), "no confirmation dialog is open")
	local text = d.text:GetText()
	d.accept:GetScript("OnClick")(d.accept)
	return text
end

-- A connected character on a named (disposable) profile: the overview,
-- three traits, two fields, a glance entry and Currently, all Public.
local function connected(opts)
	local mock, env, ns, fake = boot(opts)
	mock.Slash("set name Aelin")
	mock.Slash("set summary A wandering scholar of the Arathi Highlands.")
	mock.Vis("vis summary public")
	mock.Slash("set race High Elf")
	mock.Vis("vis race public")
	mock.Slash("set age 31")
	mock.Vis("vis age public")
	mock.Slash("personality set courage 5")
	mock.Vis("personality vis courage public")
	mock.Slash("personality set faith 15")
	mock.Vis("personality vis faith public")
	mock.Slash("trp3 glance title 1 Ink-stained hands")
	mock.Slash("trp3 glance text 1 Always writing.")
	mock.Slash("trp3 glance icon 1 inv_misc_note_02")
	mock.Slash("trp3 currently Reading by the fire.")
	mock.Slash("trp3 ooc Happy to RP.")
	mock.Slash("trp3 rpstatus ooc")
	mock.Slash("trp3 walkup yes")
	assert(ns.TRP3Commands.ConnectAll(ns.ctx))
	mock.RunTimers()
	return mock, env, ns, fake
end

return function(t, expect)
	t:describe("Forever + Total RP 3 3.5.4: first login to a synced disposable profile (L2)", function()
		t:it("setup on TRP3's default profile creates a disposable profile; Finish connects and syncs it", function()
			local mock, env, ns, fake = boot({ fake = { isDefault = true, profileId = DEFAULT_ID }, wizard = true })
			local defaultBefore = deepCopy(fake.profiles[DEFAULT_ID])
			mock.Fire("PLAYER_ENTERING_WORLD", true, false)
			mock.RunTimers()
			expect.truthy(ns.SetupWizard.IsShown(), "first login opens setup")
			local w = ns.SetupWizard.Frame()
			ns.SetupWizard.Go(2)
			for _, input in ipairs(w.inputs) do
				if input.fieldKey == "name" then input:SetText("Mirelle") end
				if input.fieldKey == "homeland" then input:SetText("Goldshire") end
			end
			ns.SetupWizard.Go(5)
			expect.equal(w.trp3Chip.label:GetText(), "Total RP 3 3.5.4 · supported")
			expect.falsy(w.trp3Cycles.trp3:IsEnabled(), "the default profile cannot be connected")
			click(w.trp3Create)
			expect.truthy(accept(ns):find("named \"Mirelle\"", 1, true))
			local id = fake.created[1]
			expect.equal(fake.profileId, id, "the character now uses the new disposable profile")
			expect.equal(fake.profiles[id].player.characteristics.FN, "Testchar", "3.5.4's given name default")
			ns.SetupWizard.Go(6)
			ns.SetupWizard.Next()
			local entry = env.DawnwardChroniclesTRP3DB.optIn[CHAR]
			expect.equal(entry.profileId, id)
			mock.RunTimers()
			local ch = fake.profiles[id].player.characteristics
			expect.equal(ch.BP, "Goldshire", "published after Finish")
			-- Dawnward's one-field Name is never split into TRP3's first and last
			-- name (FieldPlan.UNSUPPORTED); 3.5.4's own defaults stay.
			expect.equal(ch.FN, "Testchar", "3.5.4's given-name default is kept")
			expect.deepEqual(fake.profiles[DEFAULT_ID], defaultBefore, "the default profile is never written")
			expect.falsy(fake.env.TRP3_API.profile.openCreateProfileFlow == nil, "3.5.4's new flow exists")
			noErrors(expect, mock)
		end)

		t:it("imports a story, approves a piece; the story publishes as the biography, private records never", function()
			local mock, env, ns, fake = connected()
			local bio = "Aelin was born in Lordaeron.\n\n{h1}NOT A HEADING{/h1} {icon:inv_misc_bone_01:40}\n\nShe has a sister."
			local r = assert(ns.StoryImport.Import(ns.ctx, "paste", bio))
			expect.truthy(r.proposed >= 1)
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			local first = ns.StoryImport.Waiting(char)[1]
			assert(ns.StoryImport.ApproveAction(ns.ctx, first.key))
			expect.equal(#char.facts, 1)
			-- Private by design (docs/PRIVACY.md): a journal note and an
			-- unapproved story suggestion.
			mock.Slash("journal add PRIVATENOTE in the margin")
			mock.Slash("set summary Overview {h1}INJECTED{/h1} {icon:inv_misc_bone_01:40}")
			expect.truthy(contains(char.journal, "PRIVATENOTE"))
			mock.Slash("trp3 sync")
			mock.RunTimers()
			local player = fake.profile.player
			-- v0.10: the profile publishes as a whole, the biography (the story
			-- kept word for word) included (docs/PRIVACY.md, "What is public").
			expect.truthy(contains(player.about, "Aelin was born in Lordaeron."), "the biography is published")
			expect.truthy(contains(player.about, "Overview"), "the overview is")
			expect.falsy(contains(player, "PRIVATENOTE"), "a journal note never is")
			-- The biography is the player's own text word for word, their TRP3
			-- tags included (docs/TRP3_INTEGRATION.md, "Biography"); every other
			-- section escapes braces (Presentation.Escape), so profile text
			-- never becomes TRP3 markup.
			expect.truthy(contains(player.about, "{h1}NOT A HEADING{/h1}"), "the biography is verbatim")
			expect.falsy(contains(player.about, "{h1}INJECTED"), "no heading injected from the overview")
			expect.truthy(contains(player.about, "(h1)INJECTED(/h1)"), "shown as plain text")
			noErrors(expect, mock)
		end)

		t:it("writes About, traits with 3.5.4 icons, fields, glance, Currently/OOC and status, and reads back", function()
			local mock, _, ns, fake = connected()
			local player = fake.profile.player
			expect.truthy(contains(player.about, "A wandering scholar"), "About")
			expect.equal(player.characteristics.RA, "High Elf", "race field")
			expect.equal(player.characteristics.AG, "31", "age field")
			local traits = 0
			for _, tr in ipairs(player.characteristics.PS or {}) do
				if tr.LT then
					traits = traits + 1
					expect.equal(type(tr.LI), "string", "trait icon stored as TRP3 stores it")
				end
			end
			expect.truthy(traits >= 2, "two Public traits")
			local peek = player.misc.PE["1"]
			expect.equal(peek.TI, "Ink-stained hands")
			-- On 3.5.4 Dawnward writes only icons 3.5.4 lists (GlancePlan.VERIFIED_354);
			-- inv_misc_note_02 is not proven there, so TRP3's default stands in.
			expect.truthy(peek.IC == "inv_misc_questionmark" or peek.IC == "134400", tostring(peek.IC))
			expect.equal(player.character.CU, "Reading by the fire.")
			expect.equal(player.character.CO, "Happy to RP.")
			-- The fake's profile already says "in character" (RP = 1), the
			-- player's own choice: paused, never overwritten (ownership).
			expect.equal(player.character.RP, 1, "the player's own roleplay status is kept")
			expect.truthy(chat(mock):find("Paused (your version is kept): Character status", 1, true))
			expect.equal(player.character.WU, 2, "walk-up: yes")
			-- Read-back: a second run finds everything in place.
			for _, feature in ipairs(ns.TRP3Sync.ORDER) do
				local check = ns.TRP3Sync.Check(ns.ctx.trp3Deps(), feature)
				-- (status: "conflict" only for the paused roleplay status above, nothing to write)
				expect.truthy(check.state == "noop" or check.state == "off"
					or (feature == "status" and check.state == "conflict" and #check.reasons == 1),
					feature .. ": " .. tostring(check.state)
					.. " " .. table.concat(check.reasons or {}, "; "))
			end
			-- The profile icon is read-only on 3.5.4: never set through SetCustomIcon.
			mock.Slash("trp3 sync-status icon on")
			mock.Slash("trp3 sync")
			mock.RunTimers()
			for _, call in ipairs(fake.setterLog) do
				expect.falsy(call.name == "SetCustomIcon", "SetCustomIcon is blocked on 3.5.4")
			end
			noErrors(expect, mock)
		end)

		t:it("repeated syncs and event bursts write once: no version churn, no event storm", function()
			local mock, _, _, fake = connected()
			local v = {}
			for _, s in ipairs({ "about", "characteristics", "misc", "character" }) do v[s] = fake.profile.player[s].v end
			local events = #fake.events
			for _ = 1, 25 do
				mock.Slash("trp3 sync")
				mock.Fire("ZONE_CHANGED_NEW_AREA")
				mock.Fire("PLAYER_LEVEL_UP", 21)
				fake.fire("REGISTER_DATA_UPDATED", fake.playerId, fake.profileId, "about")
				mock.RunTimers()
			end
			for s, n in pairs(v) do
				expect.equal(fake.profile.player[s].v, n, s .. " version unchanged")
			end
			expect.equal(#fake.events - events, 25, "only the test's own hints; Dawnward fired nothing")
			noErrors(expect, mock)
		end)
	end)

	t:describe("Forever + Total RP 3 3.5.4: the Total RP 3 page (L2)", function()
		local function profileRows(ns)
			ns.SettingsPanel.OpenPage("trp3")
			local page = ns.SettingsPanel.panel.trp3Page
			ns.TRP3Page.Open(page, "profile")
			ns.MainWindow.Refresh()
			local rows = {}
			for _, r in ipairs(page.mapRows) do rows[r.id] = r end
			return page, rows
		end
		local function button(row, id)
			for _, b in ipairs(row.selector.buttons) do
				if b.segmentId == id then return b end
			end
		end

		t:it("shows the profile icon row as read-only on 3.5.4, with the reason, and cannot hand it to Dawnward", function()
			local mock, env, ns, fake = boot()
			mock.Slash("set name Aelin")
			local page, rows = profileRows(ns)
			local icon = rows.icon
			expect.truthy(icon.detail:GetText():find("Read-only on this Total RP 3 version", 1, true), icon.detail:GetText())
			expect.truthy(icon.hover.tooltipText:find("stores a profile icon as a file number", 1, true),
				"the tooltip gives the whole reason")
			expect.falsy(button(icon, "dawnward"):IsEnabled(), "Dawnward cannot be chosen")
			expect.truthy(button(icon, "trp3"):IsEnabled())
			click(button(icon, "dawnward"))
			expect.equal(page.staged.icon, nil, "nothing staged")
			expect.truthy(ns.MainWindow.GetFrame().status:GetText():find("Read-only on this Total RP 3 version", 1, true))
			expect.truthy(page.look.iconEdit.tooltipText:find("Read-only on this Total RP 3 version", 1, true))
			-- The class colour beside it stays writable.
			expect.falsy(rows.classColor.detail:GetText():find("Read-only", 1, true))
			expect.truthy(button(rows.classColor, "dawnward"):IsEnabled())
			-- Connected (every row handed to Dawnward): still shown read-only, never written.
			assert(ns.TRP3Commands.ConnectAll(ns.ctx))
			mock.RunTimers()
			ns.MainWindow.Refresh()
			expect.truthy(icon.detail:GetText():find("Read-only", 1, true), icon.detail:GetText())
			for _, call in ipairs(fake.setterLog) do expect.falsy(call.name == "SetCustomIcon") end
			expect.truthy(env.DawnwardChroniclesTRP3DB.optIn[CHAR])
		end)

		t:it("on 3.4.1 (Classic Era) the profile icon row is managed as before", function()
			local Fake341 = require("fakes.trp3_341")
			local fake = Fake341.new({})
			local extra = {}
			for k, v in pairs(fake.env) do if k ~= "C_AddOns" then extra[k] = v end end
			local mock, _, ns = Boot.Load({ extra = extra })
			mock.env.C_AddOns.IsAddOnLoaded = fake.env.C_AddOns.IsAddOnLoaded
			local meta = mock.env.C_AddOns.GetAddOnMetadata
			mock.env.C_AddOns.GetAddOnMetadata = function(n, f) return fake.env.C_AddOns.GetAddOnMetadata(n, f) or meta(n, f) end
			Boot.Login(mock)
			ns.SetupWizard.SkipAutoLaunchThisSession(ns.ctx.characterKey)
			local page, rows = profileRows(ns)
			expect.falsy(rows.icon.detail:GetText():find("Read-only", 1, true), rows.icon.detail:GetText())
			expect.truthy(button(rows.icon, "dawnward"):IsEnabled())
			click(button(rows.icon, "dawnward"))
			expect.equal(page.staged.icon, "dawnward")
			expect.equal(ns.TRP3Page.ReadOnlyReason(page.view, "icon"), nil)
		end)
	end)

	t:describe("Forever + Total RP 3 3.5.4: conflicts, backups and rollback (L2)", function()
		t:it("a manual About edit in TRP3 is a conflict: never overwritten, kept after more syncs", function()
			local mock, _, _, fake = connected()
			fake.openEditor("about")
			local draft = fake.drafts and fake.drafts.about
			fake.cancelEditor("about")
			-- The player rewrites the About text in Total RP 3 itself.
			local about = fake.profile.player.about
			about.T1 = { TX = "MY OWN WORDS ONLY" }
			about.v = about.v + 2
			fake.fire("REGISTER_DATA_UPDATED", fake.playerId, fake.profileId, "about")
			mock.Slash("set summary A changed overview.")
			mock.RunTimers()
			mock.Slash("trp3 sync")
			expect.equal(fake.profile.player.about.T1.TX, "MY OWN WORDS ONLY", "the player's text is kept")
			expect.truthy(chat(mock):find("biography sync paused", 1, true), chat(mock))
			for _ = 1, 5 do
				mock.Slash("trp3 sync")
				mock.RunTimers()
			end
			expect.equal(fake.profile.player.about.T1.TX, "MY OWN WORDS ONLY", "still kept after more runs")
			expect.equal(draft, draft)
			noErrors(expect, mock)
		end)

		t:it("a manual field edit pauses only that field; rollback restores the earlier section", function()
			local mock, env, _, fake = connected()
			local ch = fake.profile.player.characteristics
			ch.RA = "Blood Elf (mine)"
			ch.v = ch.v + 2
			mock.Slash("set race Moon Elf")
			mock.RunTimers()
			expect.equal(ch.RA, "Blood Elf (mine)", "never overwritten")
			expect.truthy(env.DawnwardChroniclesTRP3DB.profiles[fake.profileId].fieldConflicts.race)
			expect.equal(fake.profile.player.characteristics.AG, "31", "other fields stay managed")
			-- Rollback: the newest backup restores the section as it was before Dawnward's last write.
			local backups = #env.DawnwardChroniclesTRP3DB.backups
			expect.truthy(backups >= 1, "every write took a backup")
			local aboutBefore = deepCopy(fake.profile.player.about)
			mock.Slash("set summary Another overview.")
			mock.RunTimers()
			expect.falsy(contains(aboutBefore, "Another overview"))
			expect.truthy(contains(fake.profile.player.about, "Another overview"))
			-- Default rollback: the player's own text from the backup, Dawnward's
			-- part rebuilt from the profile as it is now.
			local out = mock.Slash("trp3 rollback confirm")
			expect.truthy(out:find("Restored your own Total RP 3 about text", 1, true), out)
			expect.truthy(contains(fake.profile.player.about, "Another overview"))
			-- An exact rollback of the newest backup (taken by the previous
			-- rollback, so it can itself be undone) and then of the write before.
			local n = #env.DawnwardChroniclesTRP3DB.backups
			out = mock.Slash("trp3 rollback " .. (n - 1) .. " exact confirm")
			expect.truthy(out:find("backup #" .. (n - 1), 1, true), out)
			expect.deepEqual(fake.profile.player.about.T1, aboutBefore.T1, "the earlier About is back exactly")
			noErrors(expect, mock)
		end)
	end)

	t:describe("Forever + Total RP 3 3.5.4: reload, relog, profile switch and combat (L2)", function()
		t:it("/reload and relog keep the connection, the ledger and the backups; the next run writes nothing", function()
			local mock, env, _, fake = connected()
			mock.Fire("PLAYER_LOGOUT")
			local before = fake.snapshot()
			local sv = deepCopy(saved(env))
			local events = #fake.events
			for _ = 1, 3 do
				fake.reload()
				local mock2, env2 = boot({ fakeInstance = fake, savedVariables = deepCopy(sv) })
				mock2.RunTimers()
				mock2.Slash("trp3 sync")
				mock2.RunTimers()
				expect.deepEqual(fake.snapshot(), before, "nothing rewritten after a reload")
				expect.equal(#fake.events, events, "no update events after a reload")
				expect.deepEqual(env2.DawnwardChroniclesTRP3DB.optIn, sv.DawnwardChroniclesTRP3DB.optIn)
				expect.equal(#env2.DawnwardChroniclesTRP3DB.backups, #sv.DawnwardChroniclesTRP3DB.backups)
				expect.equal(env2.DawnwardChroniclesDB.characters[CHAR].fields.name.value, "Aelin")
				noErrors(expect, mock2)
				mock2.Fire("PLAYER_LOGOUT")
				sv = deepCopy(saved(env2))
			end
			noErrors(expect, mock)
		end)

		t:it("a profile switch in the middle of a run stops every later write", function()
			local mock, _, ns, fake = connected()
			mock.Slash("set summary Changed before the switch.")
			mock.Slash("set race Night Elf")
			local other = { characteristics = { v = 7, FN = "Other", RA = "Gnome", PS = {} },
				about = { v = 3, TE = 1, T1 = { TX = "Other profile's own text" } },
				character = { v = 2, RP = 1, CU = "Other's currently" }, misc = { v = 1, PE = {}, ST = {} } }
			local otherCopy = deepCopy(other)
			-- Switch as soon as the first section has been written.
			local switched = false
			fake.callbacks.REGISTER_DATA_UPDATED = fake.callbacks.REGISTER_DATA_UPDATED or {}
			table.insert(fake.callbacks.REGISTER_DATA_UPDATED, 1, function()
				if not switched then
					switched = true
					fake.switchProfile("1700000099OTHER", "Other", other)
				end
			end)
			mock.RunTimers()
			mock.Slash("trp3 sync")
			mock.RunTimers()
			expect.truthy(switched)
			expect.deepEqual(fake.profiles["1700000099OTHER"].player, otherCopy, "the other profile is untouched")
			local probe = ns.TRP3Sync.ProbeOf(ns.ctx.trp3Deps())
			expect.equal(probe.profile.id, "1700000099OTHER")
			noErrors(expect, mock)
		end)

		t:it("in combat nothing is written; the run waits and writes once combat ends", function()
			local mock, _, _, fake = connected()
			mock.inCombat = true
			mock.Slash("set summary Written after the fight.")
			mock.RunTimers()
			expect.falsy(contains(fake.profile.player.about, "Written after the fight"), "held in combat")
			mock.inCombat = false
			mock.Fire("PLAYER_REGEN_ENABLED")
			mock.RunTimers()
			expect.truthy(contains(fake.profile.player.about, "Written after the fight"), "written after combat")
			noErrors(expect, mock)
		end)
	end)

	t:describe("Forever + Total RP 3: missing, disabled, late and unknown builds (L2)", function()
		t:it("missing or disabled: Dawnward works, nothing is read from or written to Total RP 3", function()
			for _, fakeOpts in ipairs({ { notInstalled = true }, { notLoaded = true } }) do
				local mock, env, ns, fake = boot({ fake = fakeOpts })
				local before = fake.snapshot()
				mock.Slash("set name Aelin")
				mock.Slash("set summary Only in Dawnward.")
				mock.Vis("vis summary public")
				local ok = ns.TRP3Commands.ConnectAll(ns.ctx)
				expect.falsy(ok, "nothing to connect to")
				mock.RunTimers()
				mock.Fire("PLAYER_LEVEL_UP", 21)
				expect.deepEqual(fake.snapshot(), before)
				expect.equal(#fake.events, 0)
				expect.equal(env.DawnwardChroniclesTRP3DB.optIn[CHAR], nil)
				expect.truthy(env.DawnwardChroniclesDB.characters[CHAR].journalKeys["levelup:21"])
				expect.truthy(mock.Slash("trp3 diagnose"):len() > 0)
				noErrors(expect, mock)
			end
		end)

		t:it("loaded late (after Dawnward's login): writes only once Total RP 3 reports itself loaded", function()
			local loaded = false
			local mock, env, ns, fake = boot({ loaded = function(name) return name == "totalRP3" and loaded end })
			mock.Slash("set name Aelin")
			mock.Slash("set summary Late but here.")
			mock.Vis("vis summary public")
			expect.falsy(ns.TRP3Commands.ConnectAll(ns.ctx), "not loaded yet: no connection")
			mock.RunTimers()
			expect.equal(#fake.events, 0)
			loaded = true
			mock.Fire("ADDON_LOADED", "totalRP3")
			assert(ns.TRP3Commands.ConnectAll(ns.ctx))
			mock.RunTimers()
			expect.truthy(contains(fake.profile.player.about, "Late but here"))
			expect.equal(env.DawnwardChroniclesTRP3DB.optIn[CHAR].profileId, fake.profileId)
			noErrors(expect, mock)
		end)

		t:it("an unknown 3.5.x build after connecting on 3.5.4: read-only, nothing written, explained", function()
			local mock, env, ns, fake = connected()
			mock.Fire("PLAYER_LOGOUT")
			local sv = deepCopy(saved(env))
			local before = fake.snapshot()
			local events = #fake.events
			for _, version in ipairs({ "3.5.5", "3.5.3", "3.6.0", "@project-version@" }) do
				local f = Fake.new({ version = version })
				f.profile.player = deepCopy(before.player)
				local mock2, _, ns2 = boot({ fakeInstance = f, savedVariables = deepCopy(sv) })
				mock2.Slash("set summary Should never reach Total RP 3.")
				mock2.RunTimers()
				mock2.Slash("trp3 sync")
				mock2.RunTimers()
				expect.deepEqual(f.snapshot().player, before.player, version .. ": nothing written")
				expect.equal(#f.setterLog, 0, version .. ": no setter")
				local diag = mock2.Slash("trp3 diagnose")
				expect.truthy(diag:find("nothing is written", 1, true), version .. ": " .. diag)
				noErrors(expect, mock2)
				expect.truthy(ns2.ctx)
			end
			expect.equal(#fake.events, events)
			expect.truthy(ns)
		end)

		t:it("Classic Era client with 3.5.4 installed: the integration works as audited, never against the TOC", function()
			-- 3.5.4's TOC declares only 120105 and 16001 (no Classic Era), so a
			-- Classic Era client would not load it ("out of date"); a player
			-- who forces it on gets the same audited, guarded path. Dawnward
			-- decides by Total RP 3's own version, not by the client.
			local mock, _, ns, fake = connected({ client = "classic" })
			expect.equal(ns.ctx.client.id, "classic_era")
			expect.truthy(contains(fake.profile.player.about, "A wandering scholar"))
			for _, call in ipairs(fake.setterLog) do
				expect.falsy(call.name == "SetCustomIcon")
			end
			-- And "loaded: false" (the client refused the out-of-date TOC) is a plain absence.
			local mock2, _, ns2, fake2 = boot({ client = "classic", fake = { notLoaded = true } })
			expect.falsy(ns2.TRP3Commands.ConnectAll(ns2.ctx))
			mock2.RunTimers()
			expect.equal(#fake2.events, 0)
			noErrors(expect, mock)
			noErrors(expect, mock2)
		end)
	end)
end
