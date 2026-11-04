-- Observes gameplay for the living chronicle and hands verified data to
-- Actions.RecordRealEvent. Event-driven only; each handler gathers a small
-- table and returns.
--
-- Classic Era 1.15.9 sources (docs/COMPATIBILITY.md):
--   QUEST_COMPLETE      the reward panel opened: GetQuestID(), GetTitleText(),
--                       and the quest's level from the log (GetQuestLogIndexByID,
--                       GetQuestLogTitle) while the quest is still in it
--   QUEST_TURNED_IN     (questID, xpReward, moneyReward): the turn-in happened
--   PLAYER_DEAD         the character died (the cause is not recorded)
--   PLAYER_LEVEL_UP     (level): the new level
--   ZONE_CHANGED_NEW_AREA   arriving in a zone, and IsInInstance /
--                       GetInstanceInfo for a party or raid instance (first
--                       recorded entry)
--   ZONE_CHANGED, ZONE_CHANGED_INDOORS   moving between named areas inside
--                       a zone (the events Blizzard's own zone text uses)
--   PLAYER_ENTERING_WORLD   login and /reload: the current location
--   Locations: GetRealZoneText, GetSubZoneText, C_Map.GetBestMapForUnit
--                       ("player") for the uiMapID, C_Map.GetAreaInfo(areaID)
--                       to resolve a subzone name to a mapped area (Core/Places)
--   UPDATE_FACTION      GetNumFactions / GetFactionInfo: tier changes against
--                       a snapshot; the first reading is a silent baseline
--   PLAYER_GUILD_UPDATE GetGuildInfo("player") with IsInGuild(): guild
--                       changes; inconclusive readings are ignored
--   C_Map.GetMapInfo    the uiMap's name and type, to tell a building the
--                       client reports as the zone from the zone (Core/Places)
--   ENCOUNTER_START, ENCOUNTER_END, BOSS_KILL   unverified probe only, see below
--
-- Quests (#11): only QUEST_TURNED_IN records one, so an abandoned quest, or a
-- reward panel closed without turning in, never does. The key is the quest
-- ID, so a relog, a /reload or a repeated event cannot record it twice.
-- Character context: UnitLevel, UnitClass, UnitRace, UnitFactionGroup.
-- Nothing here parses chat text or the combat log.
--
-- WoW Forever 1.60.1 (camelot) has no GetQuestLogTitle, GetNumFactions,
-- GetFactionInfo or C_QuestLog.GetQuestInfo; Platform/Compat.lua uses its
-- C_QuestLog and C_Reputation replacements there (docs/COMPATIBILITY.md).
local _, ns = ...
local Actions, Events = ns.Actions, ns.Events

local Observers = {}
ns.Observers = Observers

local pendingQuest -- details cached at QUEST_COMPLETE, used at QUEST_TURNED_IN

-- Client calls go through Platform/Compat.lua: errors, missing functions
-- and (on Forever) secret values all read as nil.
local Compat = ns.Compat
local call, plain = Compat.Call, Compat.Plain

-- A client token (class file, race file, faction group): text or nil.
local function token(v)
	v = plain(v)
	return type(v) == "string" and v ~= "" and v or nil
end

--- Current context: zone, subzone, level and the client's class, race and
-- faction tokens (stored only for optional flavour).
function Observers.Context()
	local zone, subzone = Events.Location()
	local _, classToken = call(UnitClass, "player")
	local _, raceToken = call(UnitRace, "player")
	local faction = call(UnitFactionGroup, "player")
	local level = plain(call(UnitLevel, "player"))
	return {
		zone = ns.Places.Bare(zone), subzone = ns.Places.Bare(subzone),
		level = type(level) == "number" and level or nil,
		class = token(classToken), race = token(raceToken), faction = token(faction),
	}
end

-- Quest level and title: Classic Era's quest log functions, or Forever's
-- C_QuestLog replacements (Platform/Compat.lua).
local questLevel, questTitle = Compat.QuestLevel, Compat.QuestTitle

Observers.HANDLERS = {
	QUEST_COMPLETE = function()
		local id = plain(call(GetQuestID))
		if type(id) == "number" and id > 0 then
			local title = plain(call(GetTitleText))
			pendingQuest = { questId = id, title = type(title) == "string" and title ~= "" and title or nil,
				questLevel = questLevel(id) }
		end
		return nil
	end,
	QUEST_TURNED_IN = function(questId, xp, money)
		if type(questId) ~= "number" then
			return nil
		end
		local data = Observers.Context()
		local cached = pendingQuest and pendingQuest.questId == questId and pendingQuest or {}
		pendingQuest = nil
		data.questId = questId
		data.title = cached.title or questTitle(questId)
		data.questLevel = cached.questLevel
		data.xp = type(xp) == "number" and xp or nil
		data.money = type(money) == "number" and money or nil
		data.source = "QUEST_TURNED_IN"
		return "quest", data
	end,
	PLAYER_DEAD = function()
		local data = Observers.Context()
		data.at = time()
		data.source = "PLAYER_DEAD"
		return "death", data
	end,
	PLAYER_LEVEL_UP = function(level)
		local data = Observers.Context()
		data.level = level
		data.source = "PLAYER_LEVEL_UP"
		return "levelup", data
	end,
}

--- Reputation standings as listed by the client (factions under a collapsed
-- header are not listed, and are left unchanged): Classic Era's
-- GetFactionInfo, or Forever's C_Reputation (Platform/Compat.lua). An empty
-- list when the client has neither, which changes no snapshot.
function Observers.ReadFactions()
	return Compat.ReadFactions()
end

--- The guild, if the reading is conclusive: { name, rank }, false (not in a
-- guild), or nil (unknown yet, e.g. guild data still loading at login).
function Observers.ReadGuild()
	local inGuild = plain(call(IsInGuild))
	local name, rank = call(GetGuildInfo, "player")
	name, rank = plain(name), plain(rank)
	if type(name) == "string" and name ~= "" then
		return { name = name, rank = rank }
	end
	if inGuild == false then
		return false
	end
	return nil
end

local function notify(onQueued, reaction, outcome)
	if reaction and outcome == "queued" and onQueued then
		onQueued(reaction)
	end
end

local clientId    -- Platform/Detect: which client's place data applies
local areaNames = {} -- AreaTable ID -> the client's own name (C_Map.GetAreaInfo)

local function areaName(id)
	if areaNames[id] == nil then
		local name = plain(call(Compat.API("C_Map.GetAreaInfo"), id))
		areaNames[id] = type(name) == "string" and name or false
	end
	return areaNames[id] or nil
end

local mapInfos = {} -- uiMapID -> { name, mapType } (C_Map.GetMapInfo), per session

local function mapInfo(id)
	if not id then return nil end
	if mapInfos[id] == nil then
		-- A malformed reply (not a table, or fields of the wrong type) reads as no information.
		local info = call(Compat.API("C_Map.GetMapInfo"), id)
		if type(info) == "table" then
			local name, mapType = plain(info.name), plain(info.mapType)
			mapInfos[id] = { name = type(name) == "string" and name or nil,
				mapType = type(mapType) == "number" and mapType or nil }
		else
			mapInfos[id] = false
		end
	end
	return mapInfos[id] or nil
end

--- The player's location: zone and subzone text, the uiMapID, and the
-- subzone's area ID when it resolves through Core/Places' mapping. Names
-- are trimmed, and a building the client reports as the zone becomes a
-- subzone of the uiMap's zone (Places.NormalizeLocation; rawZone keeps the
-- client's own zone text when that happens).
function Observers.Location()
	local data = Observers.Context()
	if not clientId then
		clientId = ns.Detect.Client(_G).id
	end
	data.client = clientId
	local mapId = plain(call(Compat.API("C_Map.GetBestMapForUnit"), "player"))
	data.mapId = type(mapId) == "number" and mapId or nil
	local rawZone = data.zone
	local interior
	data.zone, data.subzone, interior = ns.Places.NormalizeLocation(data.zone, data.subzone, mapInfo(data.mapId))
	data.rawZone = interior and rawZone or nil
	data.areaId = ns.Places.ResolveArea(clientId, data.mapId, data.subzone, areaName)
	return data
end

-- A location change: a dungeon or raid entry, or a place in the world.
local function observeLocation(ctx, onQueued)
	local data = Observers.Location()
	if not data.zone then
		return
	end
	local inInstance, instanceType = call(IsInInstance)
	inInstance, instanceType = plain(inInstance), plain(instanceType)
	if inInstance and (instanceType == "party" or instanceType == "raid") then
		local instanceName = plain(call(GetInstanceInfo))
		data.instanceName = type(instanceName) == "string" and instanceName ~= "" and instanceName or data.zone
		data.instanceType = instanceType
		data.source = "ZONE_CHANGED_NEW_AREA"
		local record, reaction, outcome = Actions.RecordRealEvent(ctx, "instance", data)
		if record then
			notify(onQueued, reaction, outcome)
		end
		return
	end
	if inInstance then
		return -- battlegrounds and other instances are not places in the story
	end
	for _, made in ipairs(Actions.ObserveLocation(ctx, data)) do
		notify(onQueued, made.reaction, made.outcome)
	end
end

-- Encounter probe (#11, dungeon completion). ENCOUNTER_START,
-- ENCOUNTER_END (encounterID, encounterName, difficultyID, groupSize,
-- success) and BOSS_KILL (encounterID, encounterName) are defined for
-- Classic Era 1.15.9.70576 (Blizzard_APIDocumentationGenerated/
-- EncounterInfoDocumentation.lua), but no Blizzard Classic Era UI code
-- registers them (grep of the classic_era interface source), so whether
-- they fire for Classic dungeon and raid bosses is unverified. Until an
-- in-game run shows they do, they are only noted for this session (shown by
-- /dawnward dev story status): nothing is saved, nothing becomes an event or
-- a memory, and nothing is asked. Evidence level: unverified.
-- Kept in ctx.encounters (session only, at most ENCOUNTER_LIMIT).
Observers.ENCOUNTER_LIMIT = 10

local function noteEncounter(ctx, event, id, name, success)
	ctx.encounters = ctx.encounters or {}
	local list = ctx.encounters
	list[#list + 1] = { event = event, id = type(id) == "number" and id or nil,
		name = type(name) == "string" and ns.Util.CleanText(name, 100) or nil,
		success = type(success) == "number" and success or nil, at = call(time) }
	while #list > Observers.ENCOUNTER_LIMIT do
		table.remove(list, 1)
	end
end

-- Events that compare snapshots or produce several records.
Observers.SPECIAL = {
	ENCOUNTER_START = function(ctx, _, id, name) noteEncounter(ctx, "ENCOUNTER_START", id, name) end,
	ENCOUNTER_END = function(ctx, _, id, name, _, _, success)
		noteEncounter(ctx, "ENCOUNTER_END", id, name, success)
	end,
	BOSS_KILL = function(ctx, _, id, name) noteEncounter(ctx, "BOSS_KILL", id, name) end,
	UPDATE_FACTION = function(ctx, onQueued)
		for _, made in ipairs(Actions.ObserveStandings(ctx, Observers.ReadFactions(), Observers.Context())) do
			notify(onQueued, made.reaction, made.outcome)
		end
	end,
	PLAYER_GUILD_UPDATE = function(ctx, onQueued)
		local guild = Observers.ReadGuild()
		if guild == nil then
			return
		end
		local _, reaction, outcome = Actions.ObserveGuild(ctx, guild or nil, Observers.Context())
		notify(onQueued, reaction, outcome)
	end,
	ZONE_CHANGED_NEW_AREA = observeLocation,
	ZONE_CHANGED = observeLocation,
	ZONE_CHANGED_INDOORS = observeLocation,
	PLAYER_ENTERING_WORLD = function(ctx, onQueued)
		Observers.SPECIAL.PLAYER_GUILD_UPDATE(ctx, onQueued)
		observeLocation(ctx, onQueued)
	end,
}

--- Records one observed event. onQueued(reaction) runs when a reaction was
-- queued, so the safe-time scheduler can consider announcing it.
function Observers.Handle(ctx, event, onQueued, ...)
	local special = Observers.SPECIAL[event]
	if special then
		return special(ctx, onQueued, ...)
	end
	local handler = Observers.HANDLERS[event]
	if not handler then
		return nil
	end
	local category, data = handler(...)
	if not category then
		return nil
	end
	local record, reaction, outcome = Actions.RecordRealEvent(ctx, category, data)
	if record and reaction and outcome == "queued" and onQueued then
		onQueued(reaction)
	end
	return record, reaction, outcome
end

function Observers.Init(ctx, onQueued)
	local frame = CreateFrame("Frame")
	for event in pairs(Observers.HANDLERS) do
		frame:RegisterEvent(event)
	end
	for event in pairs(Observers.SPECIAL) do
		frame:RegisterEvent(event)
	end
	frame:SetScript("OnEvent", function(_, event, ...)
		-- An observer must never break the game or the journal.
		local ok, err = pcall(Observers.Handle, ctx, event, onQueued, ...)
		if not ok and ctx.debug then
			ctx.print("Story observer error: " .. tostring(err))
		end
	end)
	Observers.frame = frame
	return frame
end
