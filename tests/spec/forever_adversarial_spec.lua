-- L2 (issue #24): adversarial and fuzz tests through the whole addon in the
-- WoW Forever 1.60.1 mock with the Total RP 3 3.5.4 fake (and the Classic
-- Era mock where the behaviour is shared). Deterministic: every input comes
-- from tests/support/fuzz.lua with a fixed seed, so a failure names the
-- seed that reproduces it. Disposable fixtures only.
--
-- Invariants asserted throughout: no Lua error reaches the player, no
-- approved record is lost, nothing is written under another character's
-- key, and nothing unapproved, private or simulated reaches Total RP 3.
-- Evidence label: L2 mocked / automated (Pending Live Forever Verification).
local Boot = require("support.boot")
local Loader = require("support.loader")
local Fake = require("fakes.trp3_354")
local Fuzz = require("support.fuzz")
local Kyssarra = require("fixtures.kyssarra_level6")
local Harness = require("harness")

local CHAR = "Testchar-TestRealm"

local deepCopy = Fuzz.DeepCopy

local function contains(tbl, needle)
	if type(tbl) == "string" then return tbl:find(needle, 1, true) ~= nil end
	if type(tbl) ~= "table" then return false end
	for k, v in pairs(tbl) do
		if contains(k, needle) or contains(v, needle) then return true end
	end
	return false
end

-- opts: client ("forever" default | "classic"), fake (options) or
-- fakeInstance, savedVariables, extra (client globals), noTRP3,
-- beforeLogin(mock, env) (e.g. to hand out mock.Secret values).
local function boot(opts)
	opts = opts or {}
	local fake = opts.fakeInstance or Fake.new(opts.fake or (opts.noTRP3 and { notInstalled = true } or {}))
	local extra = {}
	for k, v in pairs(fake.env) do
		if k ~= "C_AddOns" then extra[k] = v end
	end
	for k, v in pairs(opts.extra or {}) do extra[k] = v end
	local mockOpts = { extra = extra, savedVariables = opts.savedVariables }
	if opts.client ~= "classic" then mockOpts.client = "forever" end
	local mock, env, ns = Boot.Load(mockOpts)
	mock.env.C_AddOns.IsAddOnLoaded = function(name) return fake.env.C_AddOns.IsAddOnLoaded(name) end
	local meta = mock.env.C_AddOns.GetAddOnMetadata
	mock.env.C_AddOns.GetAddOnMetadata = function(name, field)
		return fake.env.C_AddOns.GetAddOnMetadata(name, field) or meta(name, field)
	end
	if opts.beforeLogin then opts.beforeLogin(mock, env) end
	Boot.Login(mock)
	if ns.ctx then
		ns.SetupLaunch.Reset()
		ns.SetupWizard.SkipAutoLaunchThisSession(ns.ctx.characterKey)
	end
	return mock, env, ns, fake
end

local function chat(mock) return table.concat(mock.chat, "\n") end

local function noErrors(expect, mock, label)
	local text = chat(mock)
	for _, needle in ipairs({ "failed safely", "unexpected error", "stack traceback", "attempt to " }) do
		expect.falsy(text:find(needle, 1, true), (label or "") .. " no Lua error (" .. needle .. "): " .. text:sub(-600))
	end
end

local function saved(env)
	return { DawnwardChroniclesDB = env.DawnwardChroniclesDB, DawnwardChroniclesSimDB = env.DawnwardChroniclesSimDB,
		DawnwardChroniclesTRP3DB = env.DawnwardChroniclesTRP3DB }
end

local function connect(mock, ns)
	mock.Slash("set summary Public overview.")
	assert(ns.TRP3Commands.ConnectAll(ns.ctx))
	mock.RunTimers()
end

-- Every write Dawnward makes to Total RP 3 fires REGISTER_DATA_UPDATED (or
-- goes through a setter): a watcher that records the combat state of each.
local function watchWrites(mock, fake)
	local log = {}
	local fire = fake.fire
	fake.fire = function(event, ...)
		log[#log + 1] = { event = event, combat = mock.inCombat == true }
		return fire(event, ...)
	end
	return log
end

local function turnIn(mock, id, title, level)
	mock.quest = { id = id, title = title, level = level }
	mock.Fire("QUEST_COMPLETE")
	mock.Fire("QUEST_TURNED_IN", id, 0, 0)
end

-- A realistic saved database: Kyssarra (tests/fixtures/kyssarra_level6.lua)
-- and a second character on another realm with the same record shape.
local OTHER = "Kyssarra-OtherRealm"
local function realisticDB()
	local core = Loader.Core()
	local db = core.Schema.NewDatabase()
	db.characters[Kyssarra.KEY] = Kyssarra.Character(core)
	db.characters[OTHER] = Kyssarra.Character(core)
	db.characters[OTHER].fields.name.value = "Kyssarra of OtherRealm"
	return db
end

local KYSSARRA = { UnitName = function() return "Kyssarra" end }

return function(t, expect)
	t:describe("fuzz: imported biographies and profile text (L2, Forever + 3.5.4)", function()
		t:it("40 seeded biographies with markup, unicode and odd line breaks: imported, synced, read back", function()
			local mock, env, ns, fake = boot()
			mock.Slash("set name Aelin")
			connect(mock, ns)
			mock.Slash("journal add PRIVATEJOURNALMARKER")
			for seed = 1, 40 do
				local rng = Fuzz.Rng(seed)
				local bio = Fuzz.Biography(rng)
				local ok, r = pcall(ns.StoryImport.Import, ns.ctx, "paste", bio)
				expect.truthy(ok, "seed " .. seed .. ": " .. tostring(r))
				local char = env.DawnwardChroniclesDB.characters[CHAR]
				for _, item in ipairs(ns.StoryImport.Waiting(char)) do
					if rng.chance(2) then
						ns.StoryImport.ApproveAction(ns.ctx, item.key)
					else
						ns.StoryImport.SkipAction(ns.ctx, item.key)
					end
				end
				mock.Slash("set summary " .. Fuzz.Line(rng, 20):gsub("\n", " "))
				mock.Slash("trp3 glance title 1 " .. Fuzz.Line(rng, 6):gsub("\n", " "))
				mock.Slash("trp3 glance text 1 " .. Fuzz.Line(rng, 10):gsub("\n", " "))
				mock.Slash("trp3 currently " .. Fuzz.Line(rng, 8):gsub("\n", " "))
				mock.RunTimers()
				mock.Slash("trp3 sync")
				noErrors(expect, mock, "seed " .. seed)
				-- Read back: everything Dawnward wrote is in place; another run writes nothing.
				for _, feature in ipairs(ns.TRP3Sync.ORDER) do
					local check = ns.TRP3Sync.Check(ns.ctx.trp3Deps(), feature)
					expect.truthy(check.state ~= "ready", "seed " .. seed .. ": " .. feature .. " churns ("
						.. tostring(check.state) .. ")")
				end
				expect.falsy(contains(fake.profile.player, "PRIVATEJOURNALMARKER"), "seed " .. seed)
				for _, line in ipairs(env.DawnwardChroniclesTRP3DB.log) do
					expect.falsy(line.text:find("did not read back", 1, true), "seed " .. seed .. ": " .. line.text)
				end
			end
		end)

		t:it("oversized input is refused or bounded, never cut silently into Total RP 3", function()
			local mock, env, ns, fake = boot()
			mock.Slash("set name Aelin")
			connect(mock, ns)
			local limit = ns.Schema.FOUNDATION.bioBytes
			local r = ns.StoryImport.Import(ns.ctx, "paste", Fuzz.Oversized(limit + 1))
			expect.falsy(r, "a story over the limit is refused")
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			expect.equal(#char.sources.versions, 0, "nothing stored")
			local exact = Fuzz.Oversized(limit, 3)
			expect.truthy(ns.StoryImport.Import(ns.ctx, "paste", exact), "exactly at the limit is accepted")
			expect.equal(ns.Sources.Current(char).text, exact, "stored byte for byte")
			for _, n in ipairs({ 5000, 70000 }) do
				mock.Slash("set summary " .. Fuzz.Oversized(n, n))
				mock.Slash("trp3 currently " .. Fuzz.Oversized(n, n + 1))
				mock.Slash("trp3 glance text 1 " .. Fuzz.Oversized(n, n + 2))
			end
			mock.RunTimers()
			mock.Slash("trp3 sync")
			noErrors(expect, mock)
			expect.truthy(#(fake.profile.player.character.CU or "") <= ns.RPStatus.LIMITS.text,
				"Currently stays within Dawnward's limit")
			expect.truthy(#(env.DawnwardChroniclesDB.characters[CHAR].fields.summary.value or "") < 70000,
				"an over-long overview is bounded")
		end)
	end)

	t:describe("fuzz: corrupted, truncated and partial saved variables (L2, Forever)", function()
		-- The control run: the same session on the unmutated database.
		local function session(db)
			local mock, env, ns = boot({ savedVariables = { DawnwardChroniclesDB = db }, extra = KYSSARRA, noTRP3 = true })
			mock.Fire("PLAYER_LEVEL_UP", 7)
			turnIn(mock, 9001, "After the crash", 7)
			mock.Fire("ZONE_CHANGED_NEW_AREA")
			mock.RunTimers()
			mock.Slash("status")
			mock.Slash("journal")
			if ns.MainWindow then
				ns.MainWindow.Show()
				for _, id in ipairs({ "journal", "story", "character", "chronicle", "settings" }) do
					pcall(ns.MainWindow.Select, id)
				end
				local ok, err = pcall(ns.MainWindow.Refresh)
				assert(ok, err)
			end
			mock.Fire("PLAYER_LOGOUT")
			return mock, env, ns
		end

		local function approved(char)
			local out = {}
			if type(char) ~= "table" or type(char.story) ~= "table" then return out end
			for i, m in pairs(type(char.story.memories) == "table" and char.story.memories or {}) do
				if type(m) == "table" and m.status == "established" then
					out[#out + 1] = { index = i, id = m.id, text = m.text }
				end
			end
			return out
		end

		local function overlaps(a, b)
			for i = 1, math.min(#a, #b) do
				if a[i] ~= b[i] then return false end
			end
			return true
		end

		t:it("60 seeds of random deletion, type swaps and truncation: no error, no loss, no cross-character write", function()
			local base = realisticDB()
			local _, controlEnv = session(deepCopy(base))
			local control = controlEnv.DawnwardChroniclesDB.characters[OTHER]
			expect.truthy(control, "the control run kept the other character")
			for seed = 1, 60 do
				local within = seed % 7 == 0 and {} or (seed % 5 == 0 and { "characters" }
					or { "characters", Kyssarra.KEY })
				local db, log = Fuzz.Mutate(base, seed, 1 + seed % 4, { within = within })
				local input = deepCopy(db)
				local ok, mock, env = pcall(session, db)
				expect.truthy(ok, "seed " .. seed .. " (" .. table.concat(log, "; ") .. "): " .. tostring(mock))
				if ok then
					noErrors(expect, mock, "seed " .. seed .. " (" .. table.concat(log, "; ") .. ")")
					local after = env.DawnwardChroniclesDB
					local readOnly = chat(mock):find("could not be loaded safely", 1, true)
					if readOnly then
						expect.deepEqual(after, input, "seed " .. seed .. ": read-only data stays exactly as saved")
					else
						local touchedOther = false
						for _, entry in ipairs(log) do
							if entry:find(" characters." .. OTHER, 1, true) or entry:match(" characters$")
								or not entry:find(" characters", 1, true) then
								touchedOther = true
							end
						end
						if not touchedOther then
							expect.deepEqual(after.characters[OTHER], control,
								"seed " .. seed .. ": the other character is exactly as in the control run")
						end
						-- Approved memories whose records were not mutated are all kept.
						local mutated = {}
						for _, entry in ipairs(log) do
							local p = {}
							for part in entry:match("^%a+ (.*)$"):gmatch("[^%.]+") do p[#p + 1] = part end
							mutated[#mutated + 1] = p
						end
						local keptChar = after.characters[Kyssarra.KEY]
						for _, m in ipairs(approved(input.characters[Kyssarra.KEY])) do
							local path = { "characters", Kyssarra.KEY, "story", "memories", tostring(m.index) }
							local hit = false
							for _, p in ipairs(mutated) do
								if overlaps(p, path) then hit = true end
							end
							if not hit then
								local found = false
								for _, k in ipairs(approved(keptChar)) do
									if k.id == m.id and k.text == m.text then found = true end
								end
								expect.truthy(found, "seed " .. seed .. " (" .. table.concat(log, "; ")
									.. "): approved memory " .. tostring(m.id) .. " kept")
							end
						end
					end
				end
			end
		end)

		t:it("a saved database that is not a table, has no characters, or is cut short: no error", function()
			local base = realisticDB()
			local cases = { "garbage", 42, true, {}, { schemaVersion = base.schemaVersion },
				{ schemaVersion = base.schemaVersion, characters = "x" },
				{ schemaVersion = base.schemaVersion, characters = { [Kyssarra.KEY] = "x", [OTHER] = 7 } } }
			for i, db in ipairs(cases) do
				local input = deepCopy(db)
				local ok, mock, env = pcall(session, db)
				expect.truthy(ok, "case " .. i .. ": " .. tostring(mock))
				if ok then
					noErrors(expect, mock, "case " .. i)
					if chat(mock):find("could not be loaded safely", 1, true) then
						expect.deepEqual(env.DawnwardChroniclesDB, input, "case " .. i .. ": untouched")
					end
				end
			end
		end)

		t:it("any schema version stamped on today's data (an interrupted migration) loads or stays untouched", function()
			local base = realisticDB()
			local core = Loader.Core()
			for version = 0, core.Schema.VERSION + 1 do
				local db = deepCopy(base)
				db.schemaVersion = version
				local input = deepCopy(db)
				local ok, mock, env = pcall(session, db)
				expect.truthy(ok, "schema " .. version .. ": " .. tostring(mock))
				if ok then
					noErrors(expect, mock, "schema " .. version)
					if chat(mock):find("could not be loaded safely", 1, true) then
						expect.deepEqual(env.DawnwardChroniclesDB, input, "schema " .. version .. ": untouched")
					else
						local before = approved(input.characters[Kyssarra.KEY])
						local after = approved(env.DawnwardChroniclesDB.characters[Kyssarra.KEY])
						expect.truthy(#after >= #before, "schema " .. version .. ": no approved memory lost")
					end
				end
			end
		end)

		t:it("a corrupted Total RP 3 ledger pauses sync, is left untouched, and writes nothing", function()
			for seed = 1, 20 do
				local fake = Fake.new({})
				local mock, env, ns = boot({ fakeInstance = fake })
				mock.Slash("set name Aelin")
				connect(mock, ns)
				mock.Fire("PLAYER_LOGOUT")
				local ledger = Fuzz.Mutate(env.DawnwardChroniclesTRP3DB, seed, 2)
				local input = deepCopy(ledger)
				local sv = saved(env)
				sv.DawnwardChroniclesTRP3DB = ledger
				local before = fake.snapshot()
				local writes = watchWrites(mock, fake)
				local mock2, env2 = boot({ fakeInstance = fake, savedVariables = deepCopy(sv) })
				mock2.Slash("set summary Changed after the corruption " .. seed)
				mock2.RunTimers()
				mock2.Slash("trp3 sync")
				mock2.RunTimers()
				noErrors(expect, mock2, "ledger seed " .. seed)
				if chat(mock2):find("Total RP 3 sync is paused", 1, true) then
					expect.deepEqual(env2.DawnwardChroniclesTRP3DB, input, "ledger seed " .. seed .. ": untouched")
					expect.deepEqual(fake.snapshot(), before, "ledger seed " .. seed .. ": nothing written")
					expect.equal(#writes, 0)
				end
			end
		end)
	end)

	t:describe("character identity: realms, collisions and unreadable names (L2)", function()
		t:it("same name on two realms (with spaces and hyphens) keeps two records; neither writes the other", function()
			local sv = {}
			local realms = { { "Azjol-Nerub", nil }, { "Twisting Nether", "TwistingNether" }, { "Test Realm", nil } }
			local keys = {}
			for i, r in ipairs(realms) do
				local mock, env = boot({ noTRP3 = true, savedVariables = deepCopy(sv), extra = {
					GetRealmName = function() return r[1] end,
					GetNormalizedRealmName = function() return r[2] end,
				} })
				mock.Slash("set name Aelin of realm " .. i)
				mock.Fire("PLAYER_LEVEL_UP", 10 + i)
				mock.Fire("PLAYER_LOGOUT")
				sv = deepCopy(saved(env))
				noErrors(expect, mock)
			end
			for key, char in pairs(sv.DawnwardChroniclesDB.characters) do
				keys[#keys + 1] = key .. "=" .. char.fields.name.value
			end
			table.sort(keys)
			expect.deepEqual(keys, { "Testchar-AzjolNerub=Aelin of realm 1", "Testchar-TestRealm=Aelin of realm 3",
				"Testchar-TwistingNether=Aelin of realm 2" })
			local a = sv.DawnwardChroniclesDB.characters["Testchar-AzjolNerub"]
			expect.truthy(a.journalKeys["levelup:11"])
			expect.falsy(a.journalKeys["levelup:12"], "no event of another realm's character")
		end)

		t:it("unreadable (secret or missing) name or realm: read-only, nothing saved, Total RP 3 untouched", function()
			-- Regression (issue #24 gate): the key used to fall back to
			-- "Unknown-<realm>", shared by every character whose name could not
			-- be read, so events and Total RP 3 syncs went to one record.
			local fake = Fake.new({})
			local mock, env, ns = boot({ fakeInstance = fake })
			mock.Slash("set name Aelin")
			connect(mock, ns)
			mock.Fire("PLAYER_LOGOUT")
			local sv = deepCopy(saved(env))
			-- A previous session already wrote under the shared fallback key.
			sv.DawnwardChroniclesDB.characters["Unknown-TestRealm"] = deepCopy(sv.DawnwardChroniclesDB.characters[CHAR])
			sv.DawnwardChroniclesTRP3DB.optIn["Unknown-TestRealm"] = deepCopy(sv.DawnwardChroniclesTRP3DB.optIn[CHAR])
			local cases = {
				{ UnitName = function() return nil end },
				{ UnitName = function() return "" end },
				{ UnitName = function() error("no unit") end },
				{ secretName = true },
				{ GetNormalizedRealmName = function() return nil end, GetRealmName = function() return nil end },
				{ GetNormalizedRealmName = function() return "" end, GetRealmName = function() return " - " end },
			}
			for i, c in ipairs(cases) do
				local input = deepCopy(sv)
				local before = fake.snapshot()
				local extra = {}
				for k, v in pairs(c) do if k ~= "secretName" then extra[k] = v end end
				local m2, env2, ns2 = boot({ fakeInstance = fake, savedVariables = deepCopy(sv), extra = extra,
					beforeLogin = c.secretName and function(m, e)
						e.UnitName = function() return m.Secret("Aelin") end
					end or nil })
				if c.secretName then
					expect.truthy(m2.UncheckedSecrets() == 0, "the secret name was checked, never used")
				end
				m2.Slash("set summary Written by an unidentified character " .. i)
				m2.Fire("PLAYER_LEVEL_UP", 30)
				turnIn(m2, 777, "Whose quest?", 30)
				m2.Slash("trp3 sync")
				m2.Slash("trp3 rollback confirm")
				m2.RunTimers()
				m2.Fire("PLAYER_LOGOUT")
				noErrors(expect, m2, "case " .. i)
				expect.truthy(chat(m2):find("cannot tell whose data this is", 1, true), "case " .. i .. ": explained")
				expect.deepEqual(saved(env2), input, "case " .. i .. ": saved variables untouched")
				expect.deepEqual(fake.snapshot(), before, "case " .. i .. ": Total RP 3 untouched")
				expect.truthy(ns2.ctx.store.realReadOnly)
			end
		end)

		t:it("Classic Era keeps the same identity rules (normalized realm first, then the realm name)", function()
			local mock, _, ns = boot({ client = "classic", noTRP3 = true, extra = {
				GetNormalizedRealmName = function() return nil end, GetRealmName = function() return "Mirage Raceway" end } })
			expect.equal(ns.ctx.characterKey, "Testchar-MirageRaceway")
			expect.falsy(ns.ctx.store.realReadOnly)
			noErrors(expect, mock)
		end)

		t:it("two characters on one account: each sees and syncs only its own record and profile", function()
			local fake = Fake.new({ characters = {} })
			local mock, env, ns = boot({ fakeInstance = fake })
			mock.Slash("set name Aelin")
			connect(mock, ns)
			mock.Fire("PLAYER_LOGOUT")
			local sv = deepCopy(saved(env))
			local aelinRecord = deepCopy(sv.DawnwardChroniclesDB.characters[CHAR])
			local aelinProfile = fake.snapshot()
			-- Bob logs in on the same account; Total RP 3 gives him the same profile (shared).
			local fake2 = Fake.new({ playerId = "Bob-TestRealm", profileId = fake.profileId })
			fake2.profile.player = deepCopy(aelinProfile.player)
			local m2, env2, ns2 = boot({ fakeInstance = fake2, savedVariables = deepCopy(sv),
				extra = { UnitName = function() return "Bob" end } })
			expect.equal(ns2.ctx.characterKey, "Bob-TestRealm")
			m2.Slash("set name Bob")
			m2.Slash("set summary BOBMARKER")
			m2.Fire("PLAYER_LEVEL_UP", 40)
			local ok = ns2.TRP3Commands.ConnectAll(ns2.ctx)
			expect.falsy(ok, "a profile another character keeps up to date is never taken over")
			m2.RunTimers()
			m2.Slash("trp3 sync")
			expect.deepEqual(env2.DawnwardChroniclesDB.characters[CHAR], aelinRecord, "Aelin's record untouched")
			expect.falsy(contains(fake2.profile.player, "BOBMARKER"), "Bob's text never reaches the shared profile")
			noErrors(expect, m2)
		end)
	end)

	t:describe("secret values from the Forever client (review H1, L2)", function()
		-- UnitIsAFK is SecretInChatMessagingLockdown on Forever (Blizzard_
		-- APIDocumentationGenerated/UnitDocumentation.lua). A boolean test of
		-- a secret can raise an error in the client; plain Lua cannot, so the
		-- mock counts secrets the addon used without issecretvalue first.
		t:it("a secret UnitIsAFK is never tested directly and counts as away (cards and the clock wait)", function()
			local mock, env, ns = Boot.Load({ client = "forever" })
			env.UnitIsAFK = function() return mock.Secret(false) end
			Boot.Login(mock)
			mock.Slash("set name Aelin")
			local reasons = table.concat(ns.SafeTime.Reasons(), ",")
			expect.truthy(reasons:find("away", 1, true), reasons)
			mock.Fire("PLAYER_FLAGS_CHANGED", "player")
			turnIn(mock, 610, "While away", 20)
			mock.RunTimers()
			expect.falsy(chat(mock):find("A moment for your story", 1, true), "no card while away is unknown")
			expect.truthy(ns.ctx.narrative.paused, "the narrative clock waits")
			expect.equal(mock.UncheckedSecrets(), 0, "every secret was checked before use")
			noErrors(expect, mock)
		end)

		t:it("a plain UnitIsAFK still decides as before (Forever and Classic Era)", function()
			for _, client in ipairs({ "forever", "classic" }) do
				local mock, _, ns = Boot.Start(client == "forever" and { client = "forever" } or nil)
				mock.afk = false
				expect.falsy(table.concat(ns.SafeTime.Reasons(), ","):find("away", 1, true), client)
				mock.afk = true
				expect.truthy(table.concat(ns.SafeTime.Reasons(), ","):find("away", 1, true), client)
				expect.equal(ns.Compat.IsAway(), true, client)
			end
		end)

		t:it("secret race, class and name values are not shown as the game's values", function()
			local mock, env, ns = Boot.Start({ client = "forever" })
			mock.Slash("set name Aelin")
			env.UnitRace = function() return mock.Secret("Human"), mock.Secret("Human"), 1 end
			env.UnitClass = function() return mock.Secret("Paladin"), mock.Secret("PALADIN"), 2 end
			env.UnitName = function() return mock.Secret("Testchar") end
			for _, key in ipairs({ "race", "class", "firstName" }) do
				expect.equal(ns.Character.GameValue(key), nil, key)
			end
			ns.MainWindow.Show()
			for _, id in ipairs({ "character", "journal", "story" }) do
				local ok, err = pcall(ns.MainWindow.Select, id)
				expect.truthy(ok, id .. ": " .. tostring(err))
			end
			noErrors(expect, mock)
		end)
	end)

	t:describe("game events: odd metadata, bursts and interrupted notifications (L2, Forever)", function()
		t:it("nil, secret, huge and negative quest data: recorded safely or ignored", function()
			local mock, env = boot({ noTRP3 = true })
			mock.Slash("set name Aelin")
			local cases = {
				{ id = 1 }, { id = 2, title = Fuzz.Oversized(20000), level = 2 ^ 53 },
				{ id = 3, title = "|cffff0000Red|r {h1}x", level = -5 }, { id = 4, title = "", level = 0 / 0 },
				{ id = 5, title = "ok", level = 1.5 }, { id = 6, title = mock.Secret("s"), level = mock.Secret(3) },
				{ id = 2 ^ 53, title = "big", level = 10 }, { id = -1, title = "neg", level = 10 },
				{ id = 7, title = Fuzz.Biography(Fuzz.Rng(7)), level = math.huge },
			}
			for _, c in ipairs(cases) do
				turnIn(mock, c.id, c.title, c.level)
			end
			mock.Fire("QUEST_TURNED_IN", nil, nil, nil)
			mock.Fire("QUEST_TURNED_IN", "abc", {}, true)
			noErrors(expect, mock)
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			for _, e in ipairs(char.story.events) do
				local lvl = e.meta and e.meta.questLevel
				expect.truthy(lvl == nil or (lvl >= 1 and lvl <= 1000 and lvl % 1 == 0), e.key .. " level " .. tostring(lvl))
				local title = e.meta and e.meta.title
				expect.truthy(title == nil or #title <= 200, e.key .. " title bounded")
			end
			expect.truthy(char.journalKeys and true)
		end)

		t:it("duplicate bursts and 1000 zone changes: one record each, bounded storage, no error", function()
			local mock, env = boot({ noTRP3 = true })
			mock.Slash("set name Aelin")
			for _ = 1, 200 do
				turnIn(mock, 42, "Again", 20)
				mock.Fire("PLAYER_LEVEL_UP", 21)
			end
			for i = 1, 1000 do
				mock.zone = (i % 2 == 0) and "Elwynn Forest" or "Westfall"
				mock.subzone = "Sub" .. (i % 13)
				mock.Fire("ZONE_CHANGED_NEW_AREA")
				mock.Fire("ZONE_CHANGED")
			end
			mock.RunTimers()
			noErrors(expect, mock)
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			local quests = 0
			for _, e in ipairs(char.story.events) do
				if e.key == "quest:42" then quests = quests + 1 end
			end
			expect.equal(quests, 1)
			expect.truthy(#char.story.events <= 40, "zone churn does not grow the story: " .. #char.story.events)
			expect.truthy(#char.journal <= 40, "nor the journal: " .. #char.journal)
		end)

		t:it("a story notice survives a lost timer, a reload mid-queue and a missing C_Timer, and shows once", function()
			local mock, env = boot({ noTRP3 = true })
			mock.Slash("set name Aelin")
			turnIn(mock, 501, "The Missing Letter", 20)
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			expect.truthy(#char.story.reactions >= 1, "the quest left a moment waiting")
			-- Lost: the queued timers never run (the client reloads first).
			expect.truthy(#mock.timers >= 1, "a notice check was queued")
			mock.timers = {}
			mock.Fire("PLAYER_LOGOUT")
			local function announced(m) return select(2, chat(m):gsub("A moment for your story", "")) end
			expect.equal(announced(mock), 0, "never shown before the reload")
			local m2, env2 = boot({ noTRP3 = true, savedVariables = deepCopy(saved(env)) })
			for _ = 1, 3 do
				m2.Play(600)
				m2.RunTimers()
				m2.Fire("ZONE_CHANGED_NEW_AREA")
				m2.Fire("PLAYER_UPDATE_RESTING")
			end
			noErrors(expect, m2)
			expect.equal(announced(m2), 1, "offered once after the reload, not lost and not repeated")
			-- Reload again mid-queue: the moment already announced is not announced again.
			m2.Fire("PLAYER_LOGOUT")
			local m3, env3 = boot({ noTRP3 = true, savedVariables = deepCopy(saved(env2)) })
			m3.Play(600)
			m3.RunTimers()
			expect.equal(announced(m3), 0, "an announced moment is not repeated after another reload")
			-- No client timer at all: the check runs at once instead (Compat.After), once per moment.
			m3.env.C_Timer = nil
			m3.Play(3600)
			turnIn(m3, 502, "Another Letter", 20)
			m3.Fire("ZONE_CHANGED_NEW_AREA")
			m3.Fire("PLAYER_UPDATE_RESTING")
			noErrors(expect, m3)
			local seen = {}
			for _, r in ipairs(env3.DawnwardChroniclesDB.characters[CHAR].story.reactions) do
				expect.falsy(seen[r.id], "one reaction per moment")
				seen[r.id] = true
			end
			expect.truthy(announced(m3) <= 1, "at most one notice for the new moment")
		end)

		t:it("combat toggling during runs: Total RP 3 is never written while in combat", function()
			local mock, _, ns, fake = boot()
			mock.Slash("set name Aelin")
			connect(mock, ns)
			local writes = watchWrites(mock, fake)
			local rng = Fuzz.Rng(99)
			for i = 1, 60 do
				mock.inCombat = rng.chance(2)
				mock.Slash("set summary Overview " .. i)
				if rng.chance(3) then mock.Fire(mock.inCombat and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED") end
				mock.RunTimers()
				if rng.chance(4) then mock.Slash("trp3 sync") end
			end
			mock.inCombat = false
			mock.Fire("PLAYER_REGEN_ENABLED")
			mock.RunTimers()
			for _, w in ipairs(writes) do
				expect.falsy(w.combat, "a Total RP 3 update fired in combat")
			end
			expect.truthy(contains(fake.profile.player.about, "Overview 60"), "the last change is written after combat")
			noErrors(expect, mock)
		end)
	end)

	t:describe("fuzz: malformed Total RP 3 data, traits, icons and glance slots (L2, 3.5.4)", function()
		t:it("30 seeds of malformed profile sections: no error, and every changed section was backed up first", function()
			for seed = 1, 30 do
				local fake = Fake.new({})
				local mock, env, ns = boot({ fakeInstance = fake })
				mock.Slash("set name Aelin")
				mock.Slash("personality set courage 4")
				mock.Slash("trp3 glance title 2 Scar")
				connect(mock, ns)
				local mutated = Fuzz.Mutate(fake.profile.player, seed, 2)
				fake.profile.player = mutated
				local before = deepCopy(mutated)
				local backups = #env.DawnwardChroniclesTRP3DB.backups
				mock.Slash("set summary After corruption " .. seed)
				mock.Slash("personality set courage 16")
				mock.RunTimers()
				mock.Slash("trp3 sync")
				noErrors(expect, mock, "profile seed " .. seed)
				local newBackups = {}
				for i = backups + 1, #env.DawnwardChroniclesTRP3DB.backups do
					newBackups[env.DawnwardChroniclesTRP3DB.backups[i].section] = true
				end
				for _, section in ipairs({ "about", "characteristics", "misc", "character" }) do
					local now = fake.profile.player[section]
					local same = Harness.deepEqual(now, before[section])
					if not same and section ~= "character" then
						expect.truthy(newBackups[section], "seed " .. seed .. ": " .. section .. " changed without a backup")
					end
				end
			end
		end)

		t:it("invalid custom traits and icon identifiers: the player's traits are never touched", function()
			local odd = { 134400, "", "134400", {}, true, Fuzz.Oversized(500), "Interface\\ICONS\\x", "|T", -1, 2 ^ 53 }
			for i, icon in ipairs(odd) do
				local ps = {
					{ LT = "Mine " .. i, RT = "Yours", LI = icon, RI = icon, V2 = "7" },
					{ LT = nil, RT = 5, V2 = {} },
					{ ID = 3, V2 = -40 },
					"not a trait",
				}
				local fake = Fake.new({ characteristics = { v = 3, FN = "Aelin", PS = deepCopy(ps) } })
				local mock, _, ns = boot({ fakeInstance = fake })
				mock.Slash("set name Aelin")
				mock.Slash("personality set courage 3")
				mock.Slash("personality set faith 17")
				mock.Slash("trp3 glance icon 1 " .. tostring(type(icon) == "table" and "x" or icon))
				connect(mock, ns)
				mock.Slash("trp3 sync")
				noErrors(expect, mock, "icon " .. i)
				local now = fake.profile.player.characteristics.PS
				for j = 1, #ps do
					expect.truthy(Harness.deepEqual(now[j], ps[j]), "icon " .. i .. ": player's entry " .. j
						.. " untouched")
				end
				for j = #ps + 1, #now do
					local tr = now[j]
					expect.equal(type(tr.LI), "string", "icon " .. i .. ": Dawnward writes a string icon")
					expect.truthy(#tr.LI < 80 and not tr.LI:find("[|\\]"), "icon " .. i .. ": a plain icon name: " .. tr.LI)
				end
			end
		end)

		t:it("At First Glance: every pattern of occupied slots; the player's slots are never overwritten", function()
			for mask = 0, 31 do
				local pe = {}
				for slot = 1, 5 do
					if math.floor(mask / 2 ^ (slot - 1)) % 2 == 1 then
						pe[tostring(slot)] = { AC = true, TI = "Player slot " .. slot, TX = "Mine", IC = "900015" }
					end
				end
				local fake = Fake.new({ misc = { v = 4, PE = deepCopy(pe), ST = {} } })
				local mock, _, ns = boot({ fakeInstance = fake })
				mock.Slash("set name Aelin")
				for n = 1, 1 + mask % 5 do
					mock.Slash("trp3 glance title " .. n .. " Dawnward " .. n)
					mock.Slash("trp3 glance text " .. n .. " Text " .. n)
				end
				connect(mock, ns)
				mock.Slash("trp3 sync")
				noErrors(expect, mock, "mask " .. mask)
				for slot, entry in pairs(pe) do
					expect.deepEqual(fake.profile.player.misc.PE[slot], entry, "mask " .. mask .. ": slot " .. slot .. " kept")
				end
			end
		end)
	end)

	t:describe("publication and isolation (L2, Forever + 3.5.4)", function()
		t:it("unapproved, draft and private records of a real level-6 save never reach Total RP 3", function()
			local core = Loader.Core()
			local db = core.Schema.NewDatabase()
			db.characters[Kyssarra.KEY] = Kyssarra.Character(core)
			local raw = db.characters[Kyssarra.KEY]
			local private = {}
			local function add(s)
				if type(s) == "string" and #s >= 18 then private[#private + 1] = s end
			end
			for _, m in ipairs(raw.story.memories) do
				if m.status ~= "established" or m.visibility ~= "public" then add(m.text) end
			end
			for _, e in ipairs(raw.journal) do
				if e.kind == "note" or (e.kind == "story" and e.status ~= "approved") then add(e.text) end
			end
			for _, list in ipairs({ raw.story.arcs, raw.story.goals, raw.story.people }) do
				for _, r in ipairs(list) do add(r.title); add(r.relation) end
			end
			expect.truthy(#private >= 8, "the fixture has private material to check")
			local fake = Fake.new({ playerId = Kyssarra.KEY })
			local mock, env, ns = boot({ fakeInstance = fake, savedVariables = { DawnwardChroniclesDB = db },
				extra = KYSSARRA })
			expect.equal(ns.ctx.characterKey, Kyssarra.KEY)
			assert(ns.TRP3Commands.ConnectAll(ns.ctx))
			mock.RunTimers()
			mock.Slash("trp3 sync")
			mock.RunTimers()
			noErrors(expect, mock)
			expect.truthy(contains(fake.profile.player, "Training at Northshire Abbey."), "the public profile is published")
			expect.truthy(contains(fake.profile.player.characteristics, "Elwynn Forest"), "homeland")
			expect.truthy(env.DawnwardChroniclesTRP3DB.optIn[Kyssarra.KEY])
			for _, s in ipairs(private) do
				expect.falsy(contains(fake.profile.player, s), "never published: " .. s)
			end
		end)

		t:it("simulation mode never touches the real database or Total RP 3", function()
			local mock, env, ns, fake = boot()
			mock.Slash("set name Aelin")
			connect(mock, ns)
			local realBefore = deepCopy(env.DawnwardChroniclesDB)
			local trp3Before = fake.snapshot()
			local writes = watchWrites(mock, fake)
			mock.Slash("sim on")
			mock.Slash("set summary SIMULATED OVERVIEW")
			mock.Slash("set race SIMRACE")
			mock.Slash("trp3 currently SIMCURRENTLY")
			mock.Slash("dev levelup 50")
			mock.Slash("sim levelup 50")
			mock.Slash("trp3 sync")
			mock.RunTimers()
			mock.Slash("trp3 enable glance confirm")
			mock.Slash("trp3 rollback confirm")
			mock.RunTimers()
			noErrors(expect, mock)
			expect.deepEqual(env.DawnwardChroniclesDB, realBefore, "the real database is untouched")
			expect.deepEqual(fake.snapshot(), trp3Before, "Total RP 3 is untouched")
			expect.equal(#writes, 0)
			expect.truthy(contains(env.DawnwardChroniclesSimDB, "SIMULATED OVERVIEW"), "the simulation has it")
			mock.Slash("sim off")
			mock.RunTimers()
			expect.falsy(contains(fake.profile.player, "SIMULATED"), "and nothing leaks after simulation ends")
		end)
	end)
end
