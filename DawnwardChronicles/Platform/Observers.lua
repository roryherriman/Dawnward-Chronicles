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
-- Character context: UnitLevel, UnitClass, UnitRace, UnitFactionGroup.
-- Nothing here parses chat text or the combat log.
local _, ns = ...
local Actions, Events = ns.Actions, ns.Events

local Observers = {}
ns.Observers = Observers

local pendingQuest -- details cached at QUEST_COMPLETE, used at QUEST_TURNED_IN

local function call(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, a, b, c, d, e, f, g, h = pcall(fn, ...)
	if ok then
		return a, b, c, d, e, f, g, h
	end
	return nil
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

--- Records one observed event. onQueued(reaction) runs when a reaction was
-- queued, so the safe-time scheduler can consider announcing it.
function Observers.Handle(ctx, event, onQueued, ...)
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
