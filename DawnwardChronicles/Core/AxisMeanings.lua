-- Player-defined meanings for the six personality axes (#21).
--
-- The axes keep their IDs, values, history and Total RP 3 trait mapping;
-- only the words the player sees change. For each axis the player may:
--   * name its two ends in their own words ("Faith" can be "Doubts the
--     Light" - "Trusts the Ancestors", or anything else)
--   * write what the axis means for this character
--   * lock it, so story answers never propose changes to it (the player
--     can still set it by hand). Unlocking only allows new proposals; it
--     changes no value.
-- Everything here is private: it is kept in personal backups and never
-- appears in a share export or Total RP 3 (the public projection does not
-- include it). Every change is reversible: clearing a label brings back
-- Dawnward's own word, and Reset removes the player's meaning entirely.
--
-- Stored per character as char.axisMeanings[axisId] =
--   { left?, right?, meaning?, locked? }   (an empty entry is not kept)
-- Loaded before Core/Schema.lua (which cleans this table on load), so the
-- schema is looked up when a function runs.
local _, ns = ...
local Util = ns.Util

local function axisById(axisId)
	return ns.Schema.PERSONALITY_AXIS_BY_ID[axisId]
end

local AxisMeanings = {}
ns.AxisMeanings = AxisMeanings

AxisMeanings.LIMITS = { label = 32, meaning = 300 }

local function text(v, limit, multiline)
	local s = Util.CleanText(v, limit, multiline)
	if s == nil or s == "" then
		return nil
	end
	return s
end

--- Cleans one entry; nil when nothing is left.
function AxisMeanings.CleanEntry(raw)
	if type(raw) ~= "table" then
		return nil
	end
	local entry = {
		left = text(raw.left, AxisMeanings.LIMITS.label),
		right = text(raw.right, AxisMeanings.LIMITS.label),
		meaning = text(raw.meaning, AxisMeanings.LIMITS.meaning, true),
		locked = raw.locked == true or nil,
	}
	if not (entry.left or entry.right or entry.meaning or entry.locked) then
		return nil
	end
	return entry
end

--- Cleans the stored table (on load and import): known axes only. Pure.
function AxisMeanings.Clean(raw)
	local out = {}
	if type(raw) ~= "table" then
		return out
	end
	for axisId, entry in pairs(raw) do
		if axisById(axisId) then
			out[axisId] = AxisMeanings.CleanEntry(entry)
		end
	end
	return out
end

function AxisMeanings.Get(char, axisId)
	return char and type(char.axisMeanings) == "table" and char.axisMeanings[axisId] or nil
end

--- The words to show for an axis: left, right, meaning (nil when the
-- player wrote none), custom (true when any word is the player's).
function AxisMeanings.Labels(char, axis)
	local entry = AxisMeanings.Get(char, axis.id)
	if not entry then
		return axis.left, axis.right, nil, false
	end
	return entry.left or axis.left, entry.right or axis.right, entry.meaning,
		(entry.left or entry.right or entry.meaning) ~= nil
end

--- Whether story answers may propose changes to this axis.
function AxisMeanings.IsLocked(char, axisId)
	local entry = AxisMeanings.Get(char, axisId)
	return entry ~= nil and entry.locked == true
end

--- values: { left?, right?, meaning?, locked? }. nil leaves a part as it is;
-- "" clears a word (Dawnward's own comes back). Returns the entry (or an
-- empty table when nothing is left) or nil plus a reason.
function AxisMeanings.Set(char, axisId, values, now)
	if not axisById(axisId) then
		return nil, "unknown axis '" .. tostring(axisId) .. "'"
	end
	values = values or {}
	if type(char.axisMeanings) ~= "table" then
		char.axisMeanings = {}
	end
	local current = char.axisMeanings[axisId] or {}
	local merged = { left = current.left, right = current.right, meaning = current.meaning, locked = current.locked }
	for _, key in ipairs({ "left", "right", "meaning" }) do
		if values[key] ~= nil then
			local limit = key == "meaning" and AxisMeanings.LIMITS.meaning or AxisMeanings.LIMITS.label
			if type(values[key]) == "string" and #Util.Trim(values[key]) > limit then
				return nil, string.format("%s can be at most %d characters", key == "meaning" and "The meaning"
					or "A label", limit)
			end
			merged[key] = values[key]
		end
	end
	if values.locked ~= nil then
		merged.locked = values.locked == true
	end
	char.axisMeanings[axisId] = AxisMeanings.CleanEntry(merged)
	if now then
		char.updatedAt = now
	end
	return char.axisMeanings[axisId] or {}
end

--- Removes the player's words and lock for an axis.
function AxisMeanings.Reset(char, axisId, now)
	if not axisById(axisId) then
		return nil, "unknown axis '" .. tostring(axisId) .. "'"
	end
	if type(char.axisMeanings) == "table" then
		char.axisMeanings[axisId] = nil
	end
	if now then
		char.updatedAt = now
	end
	return {}
end
