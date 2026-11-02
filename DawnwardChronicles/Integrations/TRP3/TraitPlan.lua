-- Dawnward-owned personality traits inside TRP3's characteristics.PS list.
-- Pure Lua: it works on copies and returns a plan; it never touches TRP3.
--
-- Each public Dawnward personality axis maps to one custom TRP3 trait with
-- Dawnward's own pole labels (LT/RT). Ownership is proven by the ledger: an
-- owned trait is the single custom entry whose LT/RT match the ledger and
-- whose value is the value Dawnward last wrote. Preset traits and traits
-- the player created are never changed, moved or removed. If an owned trait
-- was edited or deleted in TRP3, or the player already has a trait with the
-- same labels, the plan is a conflict and nothing is written.
local _, ns = ...
local Util, Schema = ns.Util, ns.Schema

local TraitPlan = {}
ns.TRP3TraitPlan = TraitPlan

-- TRP3 3.4.1 (Core/Globals.lua): PSYCHO_MAX_VALUE_V2 = 20, and a trait
-- without V2 shows PSYCHO_DEFAULT_VALUE_V2 = 10.
TraitPlan.MIN, TraitPlan.MAX = 0, 20

-- The icon TRP3's editor gives a new custom trait on both sides
-- (RegisterCharacteristics.lua psychoAdd("new"): LI = RI =
-- "INV_Misc_QuestionMark"), so Dawnward's traits never lack an icon. Never
-- compared: a player may pick other icons in TRP3.
TraitPlan.ICON = "INV_Misc_QuestionMark"

--- Dawnward value (0 = left pole, 20 = right pole) to TRP3's V2.
-- In TRP3 3.4.1, V2 is the number of points toward the LEFT trait (LT) and
-- the right trait (RT) gets 20 - V2: refreshPsycho sets leftCount = value,
-- rightCount = PSYCHO_MAX_VALUE_V2 - value, and the bar (0..20) fills from
-- the left (RegisterCharacteristics.lua). MSP sends V2 / 20 the same way
-- (MSP/Fields.lua, PS). So a Dawnward 0 ("fully Cautious") is V2 = 20.
function TraitPlan.ToTRP3(value)
	return TraitPlan.MAX - value
end

--- TRP3's V2 back to a Dawnward value (the inverse of ToTRP3).
function TraitPlan.FromTRP3(v2)
	return TraitPlan.MAX - v2
end

--- Desired owned traits from a public projection:
-- { [axisId] = { LT, RT, V2 } } for public axes only.
function TraitPlan.Desired(public)
	local out = {}
	for axisId, entry in pairs(public and public.personality or {}) do
		local axis = Schema.PERSONALITY_AXIS_BY_ID[axisId]
		if axis then
			out[axisId] = { LT = axis.left, RT = axis.right, V2 = TraitPlan.ToTRP3(entry.value) }
		end
	end
	return out
end

local function isCustom(trait)
	return type(trait) == "table" and trait.ID == nil and type(trait.LT) == "string" and type(trait.RT) == "string"
end

-- Indexes of custom traits with these labels.
local function findByLabels(list, lt, rt)
	local found = {}
	for i, trait in ipairs(list) do
		if isCustom(trait) and trait.LT == lt and trait.RT == rt then
			found[#found + 1] = i
		end
	end
	return found
end

local function sortedKeys(t)
	local keys = {}
	for k in pairs(t) do keys[#keys + 1] = k end
	table.sort(keys)
	return keys
end

--- Plans the owned-trait update.
-- characteristics: a COPY of TRP3's characteristics section (modified in place).
-- record: ledger { owned = { [axisId] = { LT, RT, V2 } } } or nil.
-- desired: from TraitPlan.Desired.
-- maxTraits: the most traits TRP3 allows in the list (nil = no limit known).
-- Returns { action = "noop" | "write" | "conflict", characteristics, record,
-- changes = { "added courage", ... }, reason }.
function TraitPlan.Plan(characteristics, record, desired, maxTraits)
	characteristics.PS = characteristics.PS or {}
	local list = characteristics.PS
	local owned = record and record.owned or {}
	local newOwned, changes, conflicts = {}, {}, {}

	-- Locate every owned trait first; any doubt stops the whole plan.
	local index = {}
	for _, axisId in ipairs(sortedKeys(owned)) do
		local o = owned[axisId]
		local found = findByLabels(list, o.LT, o.RT)
		if #found == 0 then
			conflicts[#conflicts + 1] = axisId .. " was removed in Total RP 3"
		elseif #found > 1 then
			conflicts[#conflicts + 1] = axisId .. " appears more than once in Total RP 3"
		elseif list[found[1]].V2 ~= o.V2 then
			conflicts[#conflicts + 1] = axisId .. " was changed in Total RP 3"
		else
			index[axisId] = found[1]
		end
	end
	for _, axisId in ipairs(sortedKeys(desired)) do
		local d = desired[axisId]
		if not owned[axisId] and #findByLabels(list, d.LT, d.RT) > 0 then
			conflicts[#conflicts + 1] = "a trait named " .. d.LT .. "/" .. d.RT .. " already exists in Total RP 3"
		end
	end
	if #conflicts > 0 then
		return { action = "conflict", record = record, reason = table.concat(conflicts, "; ") }
	end

	-- Update or remove owned traits (highest index first so removals keep positions valid).
	local removals = {}
	for _, axisId in ipairs(sortedKeys(owned)) do
		local d = desired[axisId]
		local trait = list[index[axisId]]
		if d then
			if trait.V2 ~= d.V2 then
				trait.V2 = d.V2
				-- A trait written before Dawnward set icons gets TRP3's own
				-- default with this update (never over an icon the player chose).
				trait.LI = trait.LI or TraitPlan.ICON
				trait.RI = trait.RI or TraitPlan.ICON
				changes[#changes + 1] = "updated " .. axisId
			end
			newOwned[axisId] = { LT = d.LT, RT = d.RT, V2 = d.V2 }
		else
			removals[#removals + 1] = { index = index[axisId], axisId = axisId }
		end
	end
	table.sort(removals, function(a, b) return a.index > b.index end)
	for _, r in ipairs(removals) do
		table.remove(list, r.index)
		changes[#changes + 1] = "removed " .. r.axisId
	end
	for _, axisId in ipairs(sortedKeys(desired)) do
		if not owned[axisId] then
			if maxTraits and #list >= maxTraits then
				return { action = "conflict", record = record,
					reason = "Total RP 3 allows at most " .. maxTraits .. " personality traits" }
			end
			local d = desired[axisId]
			list[#list + 1] = { LT = d.LT, LI = TraitPlan.ICON, RT = d.RT, RI = TraitPlan.ICON, V2 = d.V2 }
			newOwned[axisId] = { LT = d.LT, RT = d.RT, V2 = d.V2 }
			changes[#changes + 1] = "added " .. axisId
		end
	end
	local newRecord = next(newOwned) and { owned = newOwned } or nil
	if #changes == 0 then
		return { action = "noop", characteristics = characteristics, record = newRecord, changes = changes }
	end
	return { action = "write", characteristics = characteristics, record = newRecord, changes = changes }
end

--- Copy of characteristics without Dawnward's owned traits (for checks).
function TraitPlan.WithoutOwned(characteristics, record)
	local copy = Util.DeepCopy(characteristics)
	local plan = TraitPlan.Plan(copy, record, {})
	return plan.characteristics or copy
end
