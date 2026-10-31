-- Personality: a few named axes, each a value from 0 (left pole) to 20
-- (right pole), private by default. This is the data model only. How
-- gameplay and story choices move these values (the evolution model) is
-- still under review; for now the player sets them.
--
-- Axis IDs and labels are Dawnward's own, deliberately different from TRP3's
-- preset traits, so a synced trait can always be told apart from the
-- player's own.
local _, ns = ...
local Schema, Privacy = ns.Schema, ns.Privacy

local Personality = {}
ns.Personality = Personality

Personality.MIN, Personality.MAX = 0, 20

Personality.AXES = Schema.PERSONALITY_AXES
Personality.AXIS_BY_ID = Schema.PERSONALITY_AXIS_BY_ID

local function touch(char, now)
	if now then
		char.updatedAt = now
	end
end

function Personality.AxisList()
	local ids = {}
	for _, axis in ipairs(Personality.AXES) do
		ids[#ids + 1] = axis.id
	end
	return table.concat(ids, ", ")
end

--- Sets an axis value (an integer 0-20). A new axis starts private.
function Personality.Set(char, axisId, value, now)
	if not Personality.AXIS_BY_ID[axisId] then
		return nil, "unknown axis '" .. tostring(axisId) .. "' (use " .. Personality.AxisList() .. ")"
	end
	if type(value) ~= "number" or value ~= math.floor(value) or value < Personality.MIN or value > Personality.MAX then
		return nil, "the value must be a whole number from 0 to 20"
	end
	local entry = char.personality[axisId]
	if entry then
		entry.value = value
	else
		entry = { value = value, visibility = Privacy.DefaultFor(char, "personality") }
		char.personality[axisId] = entry
	end
	entry.updatedAt = now or 0
	touch(char, now)
	return entry
end

function Personality.SetVisibility(char, axisId, level, now)
	if not Privacy.IsValid(level) then
		return nil, "visibility must be public, private or secret"
	end
	local entry = char.personality[axisId]
	if not entry then
		return nil, "axis '" .. tostring(axisId) .. "' has no value"
	end
	entry.visibility = level
	touch(char, now)
	return entry
end

function Personality.Clear(char, axisId, now)
	local entry = char.personality[axisId]
	if not entry then
		return nil, "axis '" .. tostring(axisId) .. "' has no value"
	end
	char.personality[axisId] = nil
	touch(char, now)
	return entry
end

--- Axes with values, in registry order: { { axis = <registry entry>, value, visibility }, ... }.
function Personality.List(char)
	local out = {}
	for _, axis in ipairs(Personality.AXES) do
		local entry = char.personality and char.personality[axis.id]
		if entry then
			out[#out + 1] = { axis = axis, value = entry.value, visibility = entry.visibility }
		end
	end
	return out
end
