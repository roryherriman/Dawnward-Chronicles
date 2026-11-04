-- L2 (mocked): Dawnward under a WoW Forever 1.60.1 (70755) mock client.
--
-- The Forever mock (tests/support/wow_mock.lua, opts.client = "forever")
-- exposes only what the forever branch of the UI source shows: project 18
-- (camelot), interface 16001, C_QuestLog / C_Reputation instead of the
-- Classic quest log and faction globals, documented events only (an unknown
-- one raises an error) and Forever's region methods. This is mocked
-- evidence, not a runtime pass: every result here is Pending Live Forever
-- Verification.
local Boot = require("support.boot")
local Mock = require("support.wow_mock")
local Sweep = require("support.sweep")

local KEY = "Testchar-TestRealm"

return function(t, expect)
	local function forever(opts)
		opts = opts or {}
		opts.client = "forever"
		return opts
	end

	local function start(opts)
		local mock, env, ns = Boot.Start(forever(opts))
		mock.Slash("set name Aelin")
		return mock, env, ns
	end

	local function chat(mock) return table.concat(mock.chat, "\n") end

	local function turnIn(mock, id, title, level)
		mock.quest = { id = id, title = title, level = level }
		mock.Fire("QUEST_COMPLETE")
		mock.Fire("QUEST_TURNED_IN", id, 420, 90)
	end

	t:describe("Forever mock client (L2)", function()
		t:it("exposes only APIs the Forever source shows", function()
			local mock = Mock.new(forever())
			local env = mock.env
			expect.equal(env.WOW_PROJECT_ID, 18)
			expect.equal(select(4, env.GetBuildInfo()), 16001)
			for _, name in ipairs({ "GetQuestLogTitle", "GetQuestLogIndexByID", "GetNumFactions", "GetFactionInfo",
				"GetAddOnMetadata", "IsAddOnLoaded" }) do
				expect.equal(env[name], nil, name .. " is not a Forever global")
			end
			expect.equal(env.C_QuestLog.GetQuestInfo, nil, "C_QuestLog.GetQuestInfo is not in Forever's docs")
			expect.equal(type(env.C_Reputation.GetFactionDataByIndex), "function")
			expect.equal(type(env.issecretvalue), "function")
			-- The check itself rejects a Classic-only global.
			env.GetQuestLogTitle = function() end
			local ok, err = pcall(Mock.CheckForever, env)
			expect.falsy(ok)
			expect.truthy(tostring(err):find("GetQuestLogTitle", 1, true), tostring(err))
		end)

		t:it("refuses to register an event Forever does not document", function()
			local mock = Mock.new(forever())
			local frame = mock.env.CreateFrame("Frame")
			expect.falsy(pcall(frame.RegisterEvent, frame, "NOT_A_REAL_EVENT"))
			expect.truthy(pcall(frame.RegisterEvent, frame, "QUEST_TURNED_IN"))
		end)
	end)

	t:describe("client detection (Platform/Detect.lua)", function()
		t:it("recognises Forever by project 18 and labels it provisional", function()
			local mock, _, ns = start()
			local c = ns.ctx.client
			expect.equal(c.id, "forever")
			expect.equal(c.provisional, true)
			expect.equal(c.verified, false)
			expect.equal(c.project, 18)
			expect.truthy(mock.Slash("status"):find("provisional"))
		end)

		t:it("recognises Forever by project 18 even with another interface number", function()
			local _, _, ns = start({ interface = 16002 })
			expect.equal(ns.ctx.client.id, "forever")
		end)

		t:it("keeps Classic Era and unknown clients apart", function()
			local _, _, ns = Boot.Start()
			expect.equal(ns.ctx.client.id, "classic_era")
			local d = ns.Detect
			expect.equal(d.Client({ WOW_PROJECT_ID = 1, GetBuildInfo = function() return "12.0", "1", "", 120105 end }).id,
				"unknown")
			expect.equal(d.Client({ GetBuildInfo = function() error("broken") end }).id, "unknown")
			expect.equal(d.Client({ WOW_PROJECT_ID = 18 }).id, "forever")
		end)

		t:it("reads the TOC package target and warns on a mismatch without stopping", function()
			local mock, _, ns = start({ target = "classic" })
			expect.equal(ns.ctx.client.target, "classic")
			expect.equal(ns.ctx.client.targetMismatch, true)
			Boot.Login(mock) -- harmless repeat
			local out = mock.Slash("status")
			expect.truthy(out:find("built for classic - this does NOT match", 1, true), out)
			local _, _, ns2 = Boot.Start(forever({ target = "forever" }))
			expect.equal(ns2.ctx.client.targetMismatch, false)
			local _, _, ns3 = Boot.Start({ target = "forever" })
			expect.equal(ns3.ctx.client.id, "classic_era")
			expect.equal(ns3.ctx.client.targetMismatch, true)
			expect.truthy(ns3.Detect.TargetWarning(ns3.ctx.client):find("packaged for WoW Forever", 1, true))
			local _, _, ns4 = Boot.Start()
			expect.equal(ns4.ctx.client.target, nil, "no target declared: no warning")
			expect.equal(ns4.Detect.TargetWarning(ns4.ctx.client), nil)
		end)

		t:it("prints the mismatch warning once at login", function()
			local mock = Boot.Load(forever({ target = "classic" }))
			Boot.Login(mock)
			expect.truthy(chat(mock):find("packaged for WoW Classic Era", 1, true), chat(mock))
		end)
	end)

	t:describe("Dawnward under the Forever mock (L2)", function()
		t:it("loads, logs in and reports no missing client APIs", function()
			local mock, env, ns = start()
			expect.equal(env.DawnwardChroniclesDB.characters[KEY].fields.name.value, "Aelin")
			expect.equal(ns.Compat.Summary(), nil)
			expect.falsy(mock.Slash("status"):find("not available", 1, true))
		end)

		t:it("opens the journal and walks every screen with Forever's region API", function()
			local mock, _, ns = Sweep.Sample({ boot = forever() })
			expect.truthy(ns.MainWindow.IsShown())
			local visited = 0
			Sweep.Walk(ns, function() visited = visited + 1 end)
			expect.truthy(visited > 20, "visited " .. visited)
			mock.Slash("")
			expect.falsy(ns.MainWindow.IsShown())
		end)

		t:it("records a level-up milestone", function()
			local mock, env = start()
			mock.Fire("PLAYER_LEVEL_UP", 21)
			expect.equal(type(env.DawnwardChroniclesDB.characters[KEY].journalKeys["levelup:21"]), "number")
		end)

		t:it("records a quest with its level and title through C_QuestLog", function()
			local mock, env = start()
			turnIn(mock, 1234, "Burning Blade Medallion", 22)
			local record = env.DawnwardChroniclesDB.characters[KEY].story.events[1]
			expect.equal(record.key, "quest:1234")
			expect.equal(record.meta.title, "Burning Blade Medallion")
			expect.equal(record.meta.questLevel, 22)
			-- Without the reward panel, the title comes from GetTitleForQuestID.
			mock.questTitles = { [77] = "Lost in the Barrens" }
			mock.quest = nil
			mock.Fire("QUEST_TURNED_IN", 77, 10, 0)
			local second = env.DawnwardChroniclesDB.characters[KEY].story.events[2]
			expect.equal(second.meta.title, "Lost in the Barrens")
			expect.equal(second.meta.questLevel, nil)
		end)

		t:it("follows reputation through C_Reputation", function()
			local mock, env = start()
			mock.factions = { { id = 72, name = "Stormwind", standing = 5 },
				{ id = 469, name = "Alliance", header = true, standing = 5 } }
			mock.Fire("UPDATE_FACTION")
			local story = env.DawnwardChroniclesDB.characters[KEY].story
			expect.equal(#story.events, 0, "baseline only")
			expect.equal(story.observed.standings[72].standing, 5)
			expect.equal(story.observed.standings[469], nil, "headers without reputation are skipped")
			mock.factions[1].standing = 6
			mock.Fire("UPDATE_FACTION")
			expect.equal(story.events[1].key, "reputation:72:6")
		end)

		t:it("tracks zones and places with no Classic atlas data applied", function()
			local mock, env, ns = start()
			mock.mapId, mock.zone, mock.subzone = 1429, "Elwynn Forest", "Goldshire"
			-- Even a client that names Classic's area 87 "Goldshire" is not classified on Forever.
			mock.areas = { [87] = "Goldshire" }
			mock.maps = { [1429] = { name = "Elwynn Forest", mapType = 3, parentMapID = 1415 } }
			mock.Fire("ZONE_CHANGED_NEW_AREA")
			local story = env.DawnwardChroniclesDB.characters[KEY].story
			local place = story.places["Elwynn Forest / Goldshire"]
			expect.truthy(place, "the place is logged")
			expect.equal(place.kind, nil, "never classified from Classic data")
			for _, e in ipairs(story.events) do
				expect.equal(e.meta.areaId, nil, "no Classic area ID on Forever")
			end
			local loc = ns.Observers.Location()
			expect.equal(loc.client, "forever")
			expect.equal(loc.mapId, 1429)
			local out = mock.Slash("atlas")
			expect.truthy(out:find("no verified place data", 1, true), out)
			expect.truthy(out:find("uiMap 1429", 1, true), out)
		end)

		t:it("keeps everything through a /reload", function()
			local mock, env = start()
			mock.Fire("PLAYER_LEVEL_UP", 21)
			turnIn(mock, 5, "A Task", 20)
			mock.Fire("PLAYER_LOGOUT")
			local saved = {
				DawnwardChroniclesDB = env.DawnwardChroniclesDB,
				DawnwardChroniclesSimDB = env.DawnwardChroniclesSimDB,
				DawnwardChroniclesTRP3DB = env.DawnwardChroniclesTRP3DB,
			}
			local mock2, env2 = Boot.Start(forever({ savedVariables = saved }))
			local char = env2.DawnwardChroniclesDB.characters[KEY]
			expect.equal(char.fields.name.value, "Aelin")
			expect.equal(type(char.journalKeys["levelup:21"]), "number")
			-- The same events again after the reload record nothing twice.
			local events = #char.story.events
			mock2.Fire("PLAYER_LEVEL_UP", 21)
			turnIn(mock2, 5, "A Task", 20)
			expect.equal(#char.story.events, events)
		end)

		t:it("ignores duplicate events", function()
			local mock, env = start()
			turnIn(mock, 9, "Twice", 20)
			mock.Fire("QUEST_TURNED_IN", 9, 420, 90)
			mock.Fire("PLAYER_LEVEL_UP", 22)
			mock.Fire("PLAYER_LEVEL_UP", 22)
			local char = env.DawnwardChroniclesDB.characters[KEY]
			local quests, levels = 0, 0
			for _, e in ipairs(char.story.events) do
				if e.key == "quest:9" then quests = quests + 1 end
			end
			for _, entry in ipairs(char.journal) do
				if entry.kind == "event" and entry.event and entry.event.key == "levelup:22" then levels = levels + 1 end
			end
			expect.equal(quests, 1)
			expect.truthy(char.journalKeys["levelup:22"])
			expect.equal(levels, 1)
		end)

		t:it("initialises once when the startup events repeat", function()
			local mock, _, ns = start()
			local ctx = ns.ctx
			mock.Fire("ADDON_LOADED", "DawnwardChronicles")
			mock.Fire("PLAYER_LOGIN")
			expect.truthy(ns.ctx == ctx, "the session context is not rebuilt")
			expect.truthy(mock.Slash("status"):find("Dawnward Chronicles", 1, true))
		end)
	end)

	t:describe("degraded Forever clients", function()
		t:it("survives nil and malformed replies", function()
			local mock, env, ns = start()
			env.GetRealZoneText = function() return 42 end
			env.GetSubZoneText = function() return nil end
			env.C_Map.GetBestMapForUnit = function() return "1429" end
			env.C_Map.GetMapInfo = function() return "not a table" end
			env.C_Map.GetAreaInfo = function() error("bad area") end
			env.C_Reputation.GetNumFactions = function() return "many" end
			env.C_QuestLog.GetLogIndexForQuestID = function() return 3 end
			env.C_QuestLog.GetInfo = function() return { level = "high" } end
			env.C_QuestLog.GetTitleForQuestID = function() return {} end
			env.UnitLevel = function() return nil end
			env.UnitClass = function() return nil, 7 end
			env.GetInstanceInfo = function() return nil end
			mock.Fire("ZONE_CHANGED_NEW_AREA")
			mock.Fire("ZONE_CHANGED")
			mock.Fire("UPDATE_FACTION")
			mock.Fire("QUEST_COMPLETE")
			mock.Fire("QUEST_TURNED_IN", 50, 0, 0)
			mock.Fire("PLAYER_LEVEL_UP", 23)
			local char = env.DawnwardChroniclesDB.characters[KEY]
			local quest
			for _, e in ipairs(char.story.events) do
				if e.key == "quest:50" then quest = e end
			end
			expect.truthy(quest, "the quest is still recorded")
			expect.equal(quest.meta.questLevel, nil)
			expect.equal(quest.meta.title, nil)
			expect.equal(quest.class, nil)
			local loc = ns.Observers.Location()
			expect.equal(loc.zone, nil)
			expect.equal(loc.mapId, nil)
			expect.equal(#ns.Compat.ReadFactions(), 0)
			env.C_Reputation.GetNumFactions = function() return 2 end
			env.C_Reputation.GetFactionDataByIndex = function(i) if i == 1 then return "bad" end end
			expect.equal(#ns.Compat.ReadFactions(), 0)
			expect.truthy(mock.Slash("atlas"):find("Atlas:", 1, true))
		end)

		t:it("reads secret values as nothing instead of failing", function()
			local mock, env, ns = start()
			env.UnitClass = function() return "Mage", mock.Secret("MAGE"), 8 end
			env.GetRealZoneText = function() return mock.Secret("Elwynn Forest") end
			env.C_QuestLog.GetInfo = function() return { level = mock.Secret(22) } end
			local c = ns.Observers.Context()
			expect.equal(c.class, nil)
			expect.equal(c.zone, nil)
			turnIn(mock, 60, "Secretive", 22)
			local record = env.DawnwardChroniclesDB.characters[KEY].story.events[1]
			expect.equal(record.key, "quest:60")
			expect.equal(record.meta.questLevel, nil)
			expect.equal(ns.Compat.Plain("plain"), "plain")
		end)

		t:it("degrades each feature with a message when its APIs are missing", function()
			local mock, env = Boot.Load(forever())
			env.C_Reputation = nil
			env.C_QuestLog = nil
			env.C_Map = nil
			env.C_Timer = nil
			env.GetGuildInfo = nil
			Boot.Login(mock)
			local login = chat(mock)
			expect.truthy(login:find("Client APIs not available", 1, true), login)
			expect.truthy(login:find("reputation", 1, true), login)
			expect.truthy(login:find("C_Reputation.GetNumFactions", 1, true), login)
			mock.Slash("set name Aelin")
			-- Nothing raises an error, and what can be recorded still is.
			mock.factions = { { id = 72, name = "Stormwind", standing = 5 } }
			mock.Fire("UPDATE_FACTION")
			turnIn(mock, 70, "No Log", 20)
			mock.Fire("ZONE_CHANGED_NEW_AREA")
			mock.Fire("PLAYER_GUILD_UPDATE")
			mock.Fire("PLAYER_LEVEL_UP", 24)
			local char = env.DawnwardChroniclesDB.characters[KEY]
			local quest
			for _, e in ipairs(char.story.events) do
				if e.key == "quest:70" then quest = e end
			end
			expect.truthy(quest)
			expect.equal(quest.meta.title, "No Log", "the reward panel still names it")
			expect.equal(quest.meta.questLevel, nil)
			expect.truthy(char.journalKeys["levelup:24"])
			expect.equal(next(char.story.observed.standings), nil, "no reputation reading without an API")
			local status = mock.Slash("status")
			expect.truthy(status:find("quest levels", 1, true), status)
			expect.truthy(status:find("timers", 1, true), status)
		end)

		t:it("holds story cards and Total RP 3 writes in combat, and when combat state is unknown", function()
			local mock, env, ns = start()
			mock.inCombat = true
			expect.truthy(ns.Compat.InCombat(false))
			local reasons = table.concat(ns.SafeTime.Reasons(), ",")
			expect.truthy(reasons:find("combat", 1, true), reasons)
			turnIn(mock, 80, "Fight", 20)
			mock.chat = {}
			mock.RunTimers()
			expect.falsy(chat(mock):find("A moment for your story", 1, true))
			mock.inCombat = false
			env.InCombatLockdown = nil
			expect.equal(ns.Compat.InCombat(true), true, "unknown counts as combat for writes and cards")
			expect.equal(ns.Compat.InCombat(false), false)
			reasons = table.concat(ns.SafeTime.Reasons(), ",")
			expect.truthy(reasons:find("combat", 1, true), reasons)
			env.InCombatLockdown = function() error("no") end
			expect.equal(ns.Compat.InCombat(true), true)
		end)
	end)

	t:describe("Classic Era stays as it was", function()
		t:it("uses the Classic quest log and faction functions when they exist", function()
			local mock, env, ns = Boot.Start()
			mock.Slash("set name Classic")
			expect.equal(ns.Compat.Route("questLevel"), 1)
			expect.equal(ns.Compat.Route("questTitle"), 1)
			expect.equal(ns.Compat.Route("reputation"), 1)
			expect.equal(ns.Compat.Summary(), nil)
			-- A Classic client never takes the Forever route, even if both exist.
			env.C_Reputation = { GetNumFactions = function() error("must not be called") end,
				GetFactionDataByIndex = function() error("must not be called") end }
			mock.factions = { { id = 72, name = "Stormwind", standing = 5 } }
			expect.equal(ns.Compat.ReadFactions()[1].id, 72)
			expect.equal(ns.Compat.Plain("x"), "x", "no issecretvalue on Classic: values pass through")
			expect.falsy(mock.Slash("status"):find("Package:", 1, true), "no target declared in the dev TOC")
		end)
	end)
end
