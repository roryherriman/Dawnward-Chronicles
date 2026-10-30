-- L1/L2: verified gameplay events and locations (#11, #14, #18, #35, #48):
-- the in-game atlas evidence, interior and spacing fixes, quest and level
-- robustness, the unverified encounter probe, calm-moment guards and goal
-- context. Mocked client and evidence files only; not in-game evidence.
local Loader = require("support.loader")
local Fixtures = require("fixtures.characters")
local Boot = require("support.boot")

local EVIDENCE = "tools/atlas/evidence/"

local function readFile(name)
	local f = assert(io.open(EVIDENCE .. name, "rb"))
	local text = f:read("*a")
	f:close()
	return text
end

-- The owner's in-game scan: AreaTable ID -> the client's exact name.
local function scan()
	local out = {}
	for id, name in readFile("classic_era_70576_atlas_scan_1-5000.txt"):gmatch('area (%d+) "([^\n]*)"') do
		out[tonumber(id)] = name
	end
	return out
end

return function(t, expect)
	local KEY = "Testchar-TestRealm"

	t:describe("atlas evidence from the game (#48)", function()
		t:it("keeps the owner's export and scan verbatim, and every in-game confirmation is in the export", function()
			local ns = Loader.Core()
			local areas = scan()
			local n = 0
			for _ in pairs(areas) do n = n + 1 end
			expect.equal(n, 1081, "the scan has 1,081 named areas")
			local export = readFile("classic_era_70576_atlas_export.txt")
			expect.truthy(export:find("verify: 66 match, 0 renamed, 0 missing", 1, true))
			for what, ids in pairs(ns.Atlas.CONFIRMED) do
				for id, date in pairs(ids) do
					local label = what == "maps" and "map" or "area"
					local line = string.format('match %s %d expected="%s" got="%s"', label, id,
						ns.Atlas.EXPECTED[what][id], ns.Atlas.EXPECTED[what][id])
					expect.truthy(export:find(line, 1, true), line)
					expect.truthy(date == "2026-10-26" or date == "2026-10-28", "dated " .. tostring(date))
				end
			end
			-- Every expected name is the client's own, exactly.
			for id, name in pairs(ns.Atlas.EXPECTED.areas) do
				expect.equal(areas[id], name, "area " .. id)
			end
		end)

		t:it("promotes all 66 exported entries, and a new entry is never confirmed by default", function()
			local ns = Loader.Core()
			expect.equal(ns.Atlas.Level("classic_era", "areas", 69), "in-game")
			expect.equal(ns.Atlas.Level("classic_era", "maps", 1458), "in-game")
			ns.Atlas.EXPECTED.areas[99998] = "Somewhere New"
			expect.equal(ns.Atlas.Level("classic_era", "areas", 99998), "source")
			expect.equal(ns.Atlas.Level("forever", "areas", 69), "unverified", "Forever stays unverified")
		end)

		t:it("candidates match the scan exactly and are never classified", function()
			local ns = Loader.Core()
			local areas = scan()
			local byName = {}
			for id, name in pairs(areas) do
				local bare = ns.Places.Bare(name)
				byName[bare] = byName[bare] or {}
				byName[bare][#byName[bare] + 1] = id
			end
			local data = ns.Places.Data("classic_era")
			local count = 0
			for id, c in pairs(ns.Atlas.CANDIDATES) do
				count = count + 1
				expect.equal(areas[id], c.name, "candidate " .. id .. " is spelled as the client spells it")
				expect.equal(data.areas[id], nil, "candidate " .. id .. " is not in the place mapping")
				expect.equal(ns.Atlas.EXPECTED.areas[id], nil)
				expect.equal(ns.Atlas.Level("classic_era", "areas", id), "unverified")
				expect.equal(ns.Atlas.Quarantined(id, c.name), nil)
				-- Data issue C: every other ID with the same name is listed.
				local others = {}
				for _, other in ipairs(byName[ns.Places.Bare(c.name)]) do
					if other ~= id then others[#others + 1] = other end
				end
				table.sort(others)
				expect.deepEqual(c.shared or {}, others, "shared IDs of " .. id)
			end
			expect.equal(count, 49)
			expect.equal(ns.Atlas.CANDIDATES[1997].name, "Bloodvenom Post ", "the client's trailing space is kept")
		end)

		t:it("quarantines unused, test, odd, sea and generic battleground IDs, and nothing mapped", function()
			local ns = Loader.Core()
			local buckets = {}
			for id, name in pairs(scan()) do
				local why = ns.Atlas.Quarantined(id, name)
				if why then buckets[why] = (buckets[why] or 0) + 1 end
			end
			expect.deepEqual(buckets, { unused = 43, test = 9, review = 9, sea = 27, battleground = 5 })
			for id in pairs(ns.Places.Data("classic_era").areas) do
				expect.equal(ns.Atlas.Quarantined(id, ns.Atlas.EXPECTED.areas[id]), nil, "mapped area " .. id)
			end
		end)

		t:it("names a candidate from the client's name, ignoring surrounding spaces", function()
			local ns = Loader.Core()
			local client = function(id) return ns.Atlas.CANDIDATES[id] and ns.Atlas.CANDIDATES[id].name end
			expect.equal((ns.Atlas.Candidate("Bloodvenom Post", client)), 1997)
			expect.equal((ns.Atlas.Candidate("Darkshire", client)), 42)
			expect.equal(ns.Atlas.Candidate("Goldshire", client), nil, "mapped places are not candidates")
			expect.equal(ns.Atlas.Candidate(nil, client), nil)
		end)
	end)

	t:describe("location text (#48 data issues A and B)", function()
		local ELWYNN = { name = "Elwynn Forest", mapType = 3 }

		t:it("records a building the client calls the zone as a place inside the map's zone", function()
			local ns = Loader.Core()
			local N = ns.Places.NormalizeLocation
			local zone, subzone, interior = N("Lion's Pride Inn", "", ELWYNN)
			expect.equal(zone, "Elwynn Forest")
			expect.equal(subzone, "Lion's Pride Inn")
			expect.truthy(interior)
			-- Outside, or with a subzone, nothing changes.
			expect.deepEqual({ N("Elwynn Forest", "Goldshire", ELWYNN) }, { "Elwynn Forest", "Goldshire", false })
			expect.deepEqual({ N("Elwynn Forest", "", ELWYNN) }, { "Elwynn Forest", nil, false })
			-- Without a zone-type map the client's text is kept.
			expect.deepEqual({ N("Lion's Pride Inn", nil, nil) }, { "Lion's Pride Inn", nil, false })
			expect.deepEqual({ N("The Great Sea", nil, { name = "Eastern Kingdoms", mapType = 2 }) },
				{ "The Great Sea", nil, false })
			expect.deepEqual({ N("Wailing Caverns", nil, { name = "Wailing Caverns", mapType = 4 }) },
				{ "Wailing Caverns", nil, false })
			expect.deepEqual({ N(nil, "x", ELWYNN) }, { nil, nil, false })
		end)

		t:it("trims names, so a trailing space never logs a place twice", function()
			local ns = Loader.Core()
			local N = ns.Places.NormalizeLocation
			expect.deepEqual({ N("Felwood ", "Bloodvenom Post ", nil) }, { "Felwood", "Bloodvenom Post", false })
			local client = function(id) return id == 87 and "Goldshire " or nil end
			expect.equal(ns.Places.ResolveArea("classic_era", 1429, "Goldshire", client), 87)
			expect.equal(ns.Places.ResolveArea("classic_era", 1429, " Goldshire ", client), 87)
			expect.equal(ns.Places.ResolveArea("classic_era", 1436, "Goldshire", client), nil, "other maps never")
		end)

		local function start()
			local mock, env, ns = Boot.Start()
			env.C_Map = {
				GetBestMapForUnit = function() return mock.mapId or 1429 end,
				GetAreaInfo = function(id) return ns.Atlas.EXPECTED.areas[id] or (ns.Atlas.CANDIDATES[id]
					and ns.Atlas.CANDIDATES[id].name) end,
				GetMapInfo = function(id)
					if id == 1429 then return { name = "Elwynn Forest", parentMapID = 1415, mapType = 3 } end
					if id == 1448 then return { name = "Felwood", parentMapID = 1414, mapType = 3 } end
					return nil
				end,
			}
			mock.Slash("set name Tester")
			return mock, env, ns
		end

		t:it("L2: the inn is logged inside Elwynn Forest, with no zone of its own, and repeat visits stay quiet",
			function()
				local mock, env = start()
				mock.zone, mock.subzone = "Elwynn Forest", "Goldshire"
				mock.Fire("ZONE_CHANGED_NEW_AREA")
				local story = env.DawnwardChroniclesDB.characters[KEY].story
				local before = #story.events
				mock.zone, mock.subzone = "Lion's Pride Inn", ""
				mock.Fire("ZONE_CHANGED_INDOORS")
				expect.truthy(story.places["Elwynn Forest / Lion's Pride Inn"], "logged as a place in Elwynn Forest")
				expect.equal(story.places["Lion's Pride Inn"], nil, "never a zone")
				expect.equal(story.eventKeys["zone:Lion's Pride Inn"], nil)
				expect.equal(#story.events, before, "an unmapped building makes no event")
				mock.zone, mock.subzone = "Elwynn Forest", "Goldshire"
				mock.Fire("ZONE_CHANGED_INDOORS")
				mock.zone, mock.subzone = "Lion's Pride Inn", ""
				mock.Fire("ZONE_CHANGED_INDOORS")
				expect.equal(#story.events, before, "going in and out adds nothing")
				expect.equal(story.places["Elwynn Forest / Lion's Pride Inn"].visits, 1, "the same visit")
			end)

		t:it("L2: a trailing space in the client's name logs one place, also after /reload", function()
			local mock, env, ns = start()
			mock.mapId, mock.zone, mock.subzone = 1448, "Felwood", "Bloodvenom Post "
			mock.Fire("ZONE_CHANGED_NEW_AREA")
			local saved = ns.Util.DeepCopy(env.DawnwardChroniclesDB)
			local mock2, env2 = Boot.Start({ savedVariables = { DawnwardChroniclesDB = saved } })
			env2.C_Map = env.C_Map
			mock2.zone, mock2.subzone = "Felwood", "Bloodvenom Post "
			mock2.Fire("ZONE_CHANGED")
			local places = env2.DawnwardChroniclesDB.characters[KEY].story.places
			local n = 0
			for key in pairs(places) do
				n = n + 1
				expect.falsy(key:find(" $"), "no trailing space in " .. key)
			end
			expect.equal(n, 2, "Felwood and Bloodvenom Post, once each")
			expect.equal(places["Felwood / Bloodvenom Post"].areaId, nil, "a candidate is never classified")
		end)

		t:it("L2: /dawnward atlas names a candidate and the client's own zone text, saving nothing", function()
			local mock, env = start()
			mock.mapId, mock.zone, mock.subzone = 1448, "Felwood", "Bloodvenom Post "
			local reply = mock.Slash("atlas")
			expect.truthy(reply:find("candidate area 1997", 1, true), reply)
			mock.mapId, mock.zone, mock.subzone = 1429, "Lion's Pride Inn", ""
			reply = mock.Slash("atlas")
			expect.truthy(reply:find("Lion's Pride Inn", 1, true), reply)
			expect.truthy(reply:find("named this building as the zone", 1, true), reply)
			expect.equal(env.DawnwardChroniclesDB.characters[KEY].story.places["Lion's Pride Inn"], nil)
		end)
	end)

	t:describe("quests and levels stay single and verified (#11)", function()
		local function start()
			local mock, env, ns = Boot.Start()
			mock.Slash("set name Tester")
			return mock, env, ns
		end
		local function count(story, prefix)
			local n = 0
			for _, e in ipairs(story.events) do
				if e.key:sub(1, #prefix) == prefix then n = n + 1 end
			end
			return n
		end

		t:it("an abandoned quest or a closed reward panel records nothing; a turn-in once", function()
			local mock, env, ns = start()
			mock.quest = { id = 5, title = "Abandoned Errand", level = 3 }
			mock.Fire("QUEST_COMPLETE") -- the panel opened, then closed without turning in
			mock.Fire("QUEST_FINISHED")
			mock.Fire("QUEST_REMOVED", 5)
			local story = env.DawnwardChroniclesDB.characters[KEY].story
			expect.equal(count(story, "quest:"), 0)
			-- Another quest turned in without its panel: never the cached title.
			mock.quest = nil
			mock.questTitles = { [6] = "Wolves Across the Border" }
			mock.Fire("QUEST_TURNED_IN", 6, 100, 5)
			mock.Fire("QUEST_TURNED_IN", 6, 100, 5)
			expect.equal(count(story, "quest:"), 1)
			expect.equal(story.events[#story.events].meta.title, "Wolves Across the Border")
			-- No title at all: recorded as partial, never invented.
			mock.questTitles = {}
			mock.Fire("QUEST_TURNED_IN", 7, 0, 0)
			local last = story.events[#story.events]
			expect.equal(last.key, "quest:7")
			expect.equal(last.meta.title, nil)
			expect.equal(last.confidence, "partial")
			-- After a relog the same quest IDs stay recorded once.
			mock.Fire("PLAYER_LOGOUT")
			local saved = ns.Util.DeepCopy(env.DawnwardChroniclesDB)
			local mock2, env2 = Boot.Start({ savedVariables = { DawnwardChroniclesDB = saved } })
			mock2.Fire("PLAYER_ENTERING_WORLD")
			mock2.Fire("QUEST_TURNED_IN", 6, 100, 5)
			expect.equal(count(env2.DawnwardChroniclesDB.characters[KEY].story, "quest:"), 2)
		end)

		t:it("a level is recorded once, and logging in never records one", function()
			local mock, env, ns = start()
			mock.Fire("PLAYER_LEVEL_UP", 10)
			mock.Fire("PLAYER_LEVEL_UP", 10)
			local story = env.DawnwardChroniclesDB.characters[KEY].story
			expect.equal(count(story, "levelup:"), 1)
			local saved = ns.Util.DeepCopy(env.DawnwardChroniclesDB)
			local mock2, env2 = Boot.Start({ savedVariables = { DawnwardChroniclesDB = saved } })
			mock2.Fire("PLAYER_ENTERING_WORLD")
			mock2.Fire("PLAYER_LEVEL_UP", 10)
			expect.equal(count(env2.DawnwardChroniclesDB.characters[KEY].story, "levelup:"), 1)
			mock2.Fire("PLAYER_LEVEL_UP", 11)
			expect.equal(count(env2.DawnwardChroniclesDB.characters[KEY].story, "levelup:"), 2)
		end)
	end)

	t:describe("dungeon encounters (#11, unverified probe)", function()
		t:it("notes encounter events for this session only and records nothing", function()
			local mock, env, ns = Boot.Start()
			mock.Slash("set name Tester")
			local story = env.DawnwardChroniclesDB.characters[KEY].story
			local before = #story.events
			local saved = ns.Util.DeepCopy(env.DawnwardChroniclesDB)
			mock.Fire("ENCOUNTER_START", 1084, "Onyxia", 9, 40)
			mock.Fire("ENCOUNTER_END", 1084, "Onyxia", 9, 40, 1, {})
			mock.Fire("BOSS_KILL", 1084, "Onyxia")
			expect.equal(#story.events, before)
			expect.equal(#story.reactions, 0)
			saved.characters[KEY].story.clock = story.clock
			expect.deepEqual(env.DawnwardChroniclesDB, saved, "saved data unchanged")
			expect.equal(#ns.ctx.encounters, 3)
			local lines = table.concat(ns.StoryDiagnostics.EncounterLines(ns.ctx), "\n")
			expect.truthy(lines:find("BOSS_KILL 1084 Onyxia", 1, true), lines)
			expect.truthy(lines:find("unverified", 1, true))
			for i = 1, 20 do mock.Fire("BOSS_KILL", i, "Boss " .. i) end
			expect.equal(#ns.ctx.encounters, 10, "bounded")
		end)
	end)

	t:describe("calm moments only (#14)", function()
		local function queued()
			local mock, env, ns = Boot.Start()
			mock.Slash("set name Tester")
			mock.quest = { id = 41, title = "A Task", level = 30 }
			mock.Fire("QUEST_COMPLETE")
			mock.Fire("QUEST_TURNED_IN", 41, 0, 0)
			local story = env.DawnwardChroniclesDB.characters[KEY].story
			expect.equal(#story.reactions, 1)
			return mock, env, ns, story
		end

		t:it("waits while AFK and announces when the player is back", function()
			local mock, _, ns, story = queued()
			mock.afk = true
			mock.Fire("PLAYER_FLAGS_CHANGED", "player")
			mock.chat = {}
			mock.RunTimers()
			expect.equal(ns.SafeTime.Check(ns.ctx), nil)
			expect.equal(story.reactions[1].notifiedAt, nil, "not announced while away")
			mock.afk = false
			mock.Fire("PLAYER_FLAGS_CHANGED", "party1")
			mock.Fire("PLAYER_FLAGS_CHANGED", "player")
			mock.RunTimers()
			expect.truthy(story.reactions[1].notifiedAt, "announced once back")
			expect.equal(#story.reactions, 1, "nothing lost")
		end)

		t:it("waits inside a dungeon or raid and announces after leaving", function()
			local mock, _, _, story = queued()
			mock.instanceType, mock.instanceName = "party", "The Deadmines"
			mock.RunTimers()
			expect.equal(story.reactions[1].notifiedAt, nil, "never inside the dungeon")
			mock.instanceType, mock.instanceName = nil, nil
			mock.zone, mock.subzone = "Westfall", ""
			mock.Fire("ZONE_CHANGED_NEW_AREA")
			mock.RunTimers()
			expect.truthy(story.reactions[1].notifiedAt)
		end)

		t:it("Escape hides the reaction card; the moment keeps waiting", function()
			local mock, env, ns, story = queued()
			story.prefs.card = true
			mock.RunTimers()
			local card = ns.ReactionCard.Frame()
			expect.truthy(card and card:IsShown())
			local listed = false
			for _, name in ipairs(env.UISpecialFrames) do
				if name == card:GetName() then listed = true end
			end
			expect.truthy(listed, "in UISpecialFrames")
			expect.equal(#story.reactions, 1)
		end)
	end)

	t:describe("goals and standings from observed data (#18, #27)", function()
		local function setup()
			local ns = Loader.Core()
			local fx = Fixtures.CHARACTERS[1]
			local char = Fixtures.Character(ns, fx)
			ns.Observed.CompareStandings(char, { { id = 72, name = "Stormwind", standing = 5 } })
			local goal = assert(ns.Goals.Add(char, { title = "Earn the trust of Stormwind" }, 1))
			assert(ns.Goals.SetReputationObjective(char, goal.id, "stormwind", "Honored", 2))
			local other = assert(ns.Goals.Add(char, { title = "Find my brother in Elwynn Forest" }, 3))
			return ns, char, fx, goal, other
		end

		local function standing(ns, char, fx, from, to, at)
			ns.Observed.CompareStandings(char, { { id = 72, name = "Stormwind", standing = from } })
			local change = ns.Observed.CompareStandings(char, { { id = 72, name = "Stormwind", standing = to } })[1]
			return assert(ns.GameEvents.Record(char, "reputation", Fixtures.Context(fx, change), at))
		end

		t:it("a standing that reaches a goal's target says so, and the goal stays the player's", function()
			local ns, char, fx, goal = setup()
			local record = standing(ns, char, fx, 5, 6, 10)
			local why = table.concat(ns.Director.Why(char, record), " | ")
			expect.truthy(why:find("standing with Stormwind as Honored (it was Friendly)", 1, true), why)
			expect.truthy(why:find('reaches the target of your goal "Earn the trust of Stormwind"', 1, true), why)
			expect.truthy(why:find("only you decide", 1, true))
			expect.equal(goal.state, "active", "never completed automatically")
			expect.equal(#goal.milestones, 0)
			local p = ns.Goals.Progress(char, goal)
			expect.truthy(p.objective.met)
			-- The goal's own answer is the one offered, never chosen for the player.
			local options = ns.Director.Options(ns.Director.Context(char, record, nil))
			expect.equal(options[1].goalId, goal.id)
			expect.equal(#goal.links.decisions, 0)
		end)

		t:it("progress below the target, another faction, or a removed goal say nothing more", function()
			local ns, char, fx, goal = setup()
			goal.objective.target = 8
			local record = standing(ns, char, fx, 5, 6, 10)
			local why = table.concat(ns.Director.Why(char, record), " | ")
			expect.truthy(why:find("progress toward your goal", 1, true), why)
			local other = ns.GameEvents.Record(char, "reputation", Fixtures.Context(fx, { factionId = 47,
				factionName = "Ironforge", standing = 6, previous = 5 }), 11)
			expect.falsy(table.concat(ns.Director.Why(char, other), " "):find("goal", 1, true))
			ns.Goals.SetState(char, goal.id, "paused", 12)
			expect.falsy(table.concat(ns.Director.Why(char, record), " "):find("goal", 1, true), "paused goals are quiet")
		end)

		t:it("a level goal shows progress from level-ups only", function()
			local ns = Loader.Core()
			local fx = Fixtures.CHARACTERS[2]
			local char = Fixtures.Character(ns, fx)
			local goal = assert(ns.Goals.Add(char, { title = "Ride a wolf", objective = { kind = "level", target = 40 } },
				1))
			local record = assert(ns.GameEvents.Record(char, "levelup", Fixtures.Context(fx, { level = 30 }), 5))
			local why = table.concat(ns.Director.Why(char, record), " | ")
			expect.truthy(why:find('progress toward your goal "Ride a wolf"', 1, true), why)
			local quest = assert(ns.GameEvents.Record(char, "quest", Fixtures.Context(fx, { questId = 9 }), 6))
			expect.falsy(table.concat(ns.Director.Why(char, quest), " "):find("goal", 1, true))
			expect.equal(goal.state, "active")
		end)

		t:it("names that a stance exists, never what it is", function()
			local ns, char, fx = setup()
			ns.Identity.Add(char, { subject = "Stormwind", persona = "Loyal in public",
				conviction = "Secretly despises the nobles" }, 4)
			local record = standing(ns, char, fx, 5, 6, 10)
			local why = table.concat(ns.Director.Why(char, record), " | ")
			expect.truthy(why:find("your character's own stance toward Stormwind", 1, true), why)
			expect.falsy(why:find("despises", 1, true))
			expect.falsy(why:find("Loyal", 1, true))
			expect.equal(#char.story.identity, 1, "nothing added")
		end)
	end)
end
