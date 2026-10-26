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
--   ZONE_CHANGED_NEW_AREA   arriving in a zone (first recorded visit), and
--                       IsInInstance / GetInstanceInfo for a party or raid
--                       instance (first recorded entry)
--   UPDATE_FACTION      GetNumFactions / GetFactionInfo: tier changes against
--                       a snapshot; the first reading is a silent baseline
--   PLAYER_GUILD_UPDATE GetGuildInfo("player") with IsInGuild(): guild
--                       changes; inconclusive readings are ignored
-- Character context: UnitLevel, UnitClass, UnitRace, UnitFactionGroup.
-- Nothing here parses chat text or the combat log.
local _, ns = ...
local Actions, Events = ns.Actions, ns.Events

local Observers = {}
ns.Observers = Observers

local pendingQuest -- details cached at QUEST_COMPLETE, used at QUEST_TURNED_IN

-- Calls a client function safely, passing every return value through
-- (GetFactionInfo returns the faction ID as its 14th value).
local function results(ok, ...)
	if ok then
		return ...
	end
	return nil
end

local function call(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	return results(pcall(fn, ...))
end

--- Current context: zone, subzone, level and the client's class, race and
-- faction tokens (stored only for optional flavour).
function Observers.Context()
	local zone, subzone = Events.Location()
	local _, classToken = call(UnitClass, "player")
	local _, raceToken = call(UnitRace, "player")
	local faction = call(UnitFactionGroup, "player")
	return {
		zone = zone, subzone = subzone, level = call(UnitLevel, "player"),
		class = classToken, race = raceToken, faction = faction,
	}
end

local function questLevel(questId)
	local index = call(GetQuestLogIndexByID, questId)
	if type(index) == "number" and index > 0 then
		local _, level = call(GetQuestLogTitle, index)
		if type(level) == "number" and level > 0 then
			return level
		end
	end
	return nil
end

local function questTitle(questId)
	if type(C_QuestLog) == "table" then
		local title = call(C_QuestLog.GetQuestInfo, questId)
		if type(title) == "string" and title ~= "" then
			return title
		end
	end
	return nil
end

Observers.HANDLERS = {
	QUEST_COMPLETE = function()
		local id = call(GetQuestID)
		if type(id) == "number" and id > 0 then
			local title = call(GetTitleText)
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
-- header are not listed, and are left unchanged).
function Observers.ReadFactions()
	local out = {}
	local n = call(GetNumFactions) or 0
	for i = 1, n do
		local name, _, standing, _, _, _, _, _, isHeader, _, hasRep, _, _, factionId = call(GetFactionInfo, i)
		if name and type(factionId) == "number" and type(standing) == "number" and (not isHeader or hasRep) then
			out[#out + 1] = { id = factionId, name = name, standing = standing }
		end
	end
	return out
end

--- The guild, if the reading is conclusive: { name, rank }, false (not in a
-- guild), or nil (unknown yet, e.g. guild data still loading at login).
function Observers.ReadGuild()
	local inGuild = call(IsInGuild)
	local name, rank = call(GetGuildInfo, "player")
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

-- Events that compare snapshots or produce several records.
Observers.SPECIAL = {
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
	ZONE_CHANGED_NEW_AREA = function(ctx, onQueued)
		local data = Observers.Context()
		if not data.zone then
			return
		end
		local inInstance, instanceType = call(IsInInstance)
		local category = "zone"
		if inInstance and (instanceType == "party" or instanceType == "raid") then
			category = "instance"
			data.instanceName = call(GetInstanceInfo) or data.zone
			data.instanceType = instanceType
		end
		data.source = "ZONE_CHANGED_NEW_AREA"
		local record, reaction, outcome = Actions.RecordRealEvent(ctx, category, data)
		if record then
			notify(onQueued, reaction, outcome)
		end
	end,
}
Observers.SPECIAL.PLAYER_ENTERING_WORLD = Observers.SPECIAL.PLAYER_GUILD_UPDATE

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
