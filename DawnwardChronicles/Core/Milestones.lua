-- Milestone types: turn observed game facts into journal events.
--
-- Each type has a builder that validates its data and returns an event with a
-- stable de-duplication key. Platform code observes game events and calls
-- Milestones.Record; the journal never needs to know about individual types.
-- Adding quests or discoveries later means registering a new type here and an
-- event handler in Platform/Events.lua.
local _, ns = ...
local Util, Schema, Journal = ns.Util, ns.Schema, ns.Journal

local Milestones = {}
ns.Milestones = Milestones

Milestones.TYPES = {}
Milestones.MAX_LEVEL = 100

--- def.build(data) -> event table, or nil plus an error.
function Milestones.Register(typeName, def)
	assert(type(typeName) == "string" and typeName:match("^[%a_]+$"), "invalid milestone type")
	assert(type(def.build) == "function", "milestone type needs a build function")
	Milestones.TYPES[typeName] = def
end

Milestones.Register("levelup", {
	-- data: { level, zone, subzone, source }
	build = function(data)
		local level = data.level
		if not Util.IsPositiveInteger(level) or level < 2 or level > Milestones.MAX_LEVEL then
			return nil, "invalid level"
		end
		local zone = Schema.CleanValue(Schema.SHORT, data.zone)
		local subzone = Schema.CleanValue(Schema.SHORT, data.subzone)
		local text
		if zone then
			text = string.format("Reached level %d in %s.", level, zone)
		else
			text = string.format("Reached level %d.", level)
		end
		return {
			type = "levelup",
			key = "levelup:" .. level,
			source = data.source or "PLAYER_LEVEL_UP",
			level = level,
			zone = zone,
			subzone = subzone ~= zone and subzone or nil,
			text = text,
		}
	end,
})

function Milestones.Build(typeName, data)
	local def = Milestones.TYPES[typeName]
	if not def then
		return nil, "unknown milestone type '" .. tostring(typeName) .. "'"
	end
	return def.build(data or {})
end

--- Builds and records a milestone. Returns entry, pruned or nil, reason.
function Milestones.Record(char, typeName, data, now)
	local event, err = Milestones.Build(typeName, data)
	if not event then
		return nil, err
	end
	return Journal.RecordEvent(char, event, now)
end
