-- Gameplay event records: what the game verifiably reported, normalised.
--
-- Platform observers gather data from Classic Era APIs and call
-- GameEvents.Record. Each category validates its data and returns a record
-- with a stable key, so the same event is never recorded twice, across
-- reloads and sessions (story.eventKeys outlives pruned records).
--
-- A record holds only what the client told us. Nothing is inferred: no
-- story, no outcome, no enemy name. Fields that were unavailable stay nil
-- and lower the record's confidence to "partial".
--
-- Significance (1 routine, 2 notable, 3 major) comes from explicit rules on
-- verified data only; the game has no "this quest mattered" flag.
local _, ns = ...
local Util, StorySchema = ns.Util, ns.StorySchema

local GameEvents = {}
ns.GameEvents = GameEvents

GameEvents.CATEGORIES = {}
GameEvents.MAX_LEVEL = 100

local function context(data)
	return {
		zone = data.zone, subzone = data.subzone, level = data.level,
		class = data.class, race = data.race, faction = data.faction,
	}
end

local function withContext(record, data)
	for k, v in pairs(context(data)) do
		record[k] = v
	end
	return record
end

local function anyDeath(story)
	for k in pairs(story.eventKeys) do
		if k:sub(1, 6) == "death:" then
			return true
		end
	end
	return false
end

GameEvents.CATEGORIES.quest = {
	label = "Quest completed",
	-- data: { questId, title?, questLevel?, xp?, money?, source, + context }
	build = function(data)
		if not Util.IsPositiveInteger(data.questId) then
			return nil, "invalid quest ID"
		end
		local meta = StorySchema.CleanMeta({ questId = data.questId, title = data.title, questLevel = data.questLevel,
			xp = data.xp, money = data.money })
		return withContext({
			category = "quest",
			key = "quest:" .. data.questId,
			source = data.source or "QUEST_TURNED_IN",
			confidence = meta.title and "verified" or "partial",
			meta = meta,
		}, data)
	end,
	significance = function(record, story)
		local s = 1
		local q, l = record.meta.questLevel, record.level
		-- A quest well above the character's level is a verified challenge.
		if q and l and q >= l + 2 then
			s = s + 1
		end
		-- The first quest completed in a zone opens a new chapter.
		if record.zone and not story.pacing.questZones[record.zone] then
			s = s + 1
		end
		return math.min(s, 3)
	end,
	after = function(record, story)
		if record.zone then
			local zones, n = story.pacing.questZones, 0
			for _ in pairs(zones) do n = n + 1 end
			if n < StorySchema.LIMITS.questZones then
				zones[record.zone] = true
			end
		end
	end,
}

GameEvents.CATEGORIES.levelup = {
	label = "Level reached",
	-- data: { level (the new level), source, + context }
	build = function(data)
		local level = data.level
		if not Util.IsPositiveInteger(level) or level < 2 or level > GameEvents.MAX_LEVEL then
			return nil, "invalid level"
		end
		return withContext({
			category = "levelup", key = "levelup:" .. level, source = data.source or "PLAYER_LEVEL_UP",
			confidence = "verified", meta = {},
		}, data)
	end,
	significance = function(record)
		local l = record.level
		if l % 10 == 0 then return 3 end
		if l % 5 == 0 then return 2 end
		return 1
	end,
}

GameEvents.CATEGORIES.death = {
	label = "Death",
	-- data: { at, source, + context }. The cause of death is not recorded:
	-- Classic Era offers no reliable, unrestricted way to know it.
	build = function(data, now)
		local at = data.at or now
		if not Util.IsPositiveInteger(at) then
			return nil, "invalid time"
		end
		return withContext({
			category = "death", key = "death:" .. at, source = data.source or "PLAYER_DEAD",
			confidence = data.zone and "verified" or "partial", meta = {},
		}, data)
	end,
	significance = function(_, story)
		return anyDeath(story) and 2 or 3
	end,
}

function GameEvents.Label(category)
	local def = GameEvents.CATEGORIES[category]
	return def and def.label or tostring(category)
end

function GameEvents.Build(category, data, now)
	local def = GameEvents.CATEGORIES[category]
	if not def then
		return nil, "unknown event category '" .. tostring(category) .. "'"
	end
	return def.build(data or {}, now)
end

function GameEvents.Find(char, key)
	for _, record in ipairs(char.story.events) do
		if record.key == key then
			return record
		end
	end
	return nil
end

-- Drops the oldest record that no reaction is waiting on.
local function makeRoom(story)
	if #story.events < StorySchema.LIMITS.events then
		return
	end
	for index, record in ipairs(story.events) do
		if record.status ~= "queued" then
			table.remove(story.events, index)
			return
		end
	end
	table.remove(story.events, 1)
end

--- Records a gameplay event. Returns record, or nil plus "duplicate",
-- "not tracked" or a validation error.
function GameEvents.Record(char, category, data, now)
	local story = char.story
	if story.prefs.tracking[category] == false then
		return nil, "not tracked"
	end
	local built, err = GameEvents.Build(category, data, now)
	if not built then
		return nil, err
	end
	built.at = now or 0
	built.status = "new"
	local record = StorySchema.CleanEvent(built)
	if not record then
		return nil, "invalid event"
	end
	if story.eventKeys[record.key] then
		return nil, "duplicate"
	end
	local def = GameEvents.CATEGORIES[category]
	record.significance = def.significance(record, story)
	if def.after then
		def.after(record, story)
	end
	makeRoom(story)
	story.events[#story.events + 1] = record
	story.eventKeys[record.key] = now or 0
	StorySchema.CapEventKeys(story.eventKeys)
	return record
end

--- The newest records first, at most limit.
function GameEvents.Recent(char, limit)
	local out, list = {}, char.story.events
	for i = #list, math.max(1, #list - (limit or 10) + 1), -1 do
		out[#out + 1] = list[i]
	end
	return out
end
