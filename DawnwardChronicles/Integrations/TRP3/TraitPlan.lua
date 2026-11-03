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
-- (RegisterCharacteristics.lua:690-692, psychoAdd("new"): LI = RI =
-- "INV_Misc_QuestionMark"). Dawnward 0.10.1 and earlier wrote it on every
-- trait it added: a red question mark at both ends. Now it is only ever
-- recognised (to be replaced), never written.
TraitPlan.PLACEHOLDER = "INV_Misc_QuestionMark"
-- Kept for older callers: the placeholder, not an icon Dawnward writes.
TraitPlan.ICON = TraitPlan.PLACEHOLDER

-- How TRP3 3.4.1 stores and draws a custom trait's icons: LI / RI hold a
-- bare icon file name under Interface\ICONS (no path, no extension), as its
-- presets do (RegisterCharacteristics.lua:1206-1280, LI/RI =
-- TRP3_InterfaceIcons.Trait...); the profile shows them with
-- frame:SetLeftIcon(LI) / SetRightIcon(RI) (RegisterCharacteristics.lua:
-- 451-452 -> Main/RegisterTemplates.lua:36-42 -> UI/IconTemplates.lua:8,
-- LibRPMedia SetTextureToIcon), the editor with LI or TRP3_InterfaceIcons.
-- Default (:1017-1018). TRP3's own names are lower case
-- (Resources/InterfaceIcons.lua), so Dawnward writes lower case too.

-- Every icon Dawnward may write on a trait, each verified for Classic Era
-- 1.15.9 (keys lower case), with the evidence:
--   UI    the Classic Era 1.15.9 UI source draws it (wow-ui-source).
--   OLD   Total RP 3 3.4.1 lists it as the older-client candidate of an
--         interface icon (Resources/InterfaceIcons.lua takes the first
--         candidate the client has; the last is what older clients such as
--         Classic Era fall back to).
--   ONLY  the only candidate of a TRP3 3.4.1 interface icon: no fallback,
--         so every client TRP3 supports has it (InterfaceIcons.lua:229-235
--         reports a missing one). Trait icons of this kind are what TRP3's
--         own preset traits show on Classic Era.
TraitPlan.VERIFIED = {
	spell_shadow_brainwash = "ONLY InterfaceIcons.lua:162 TraitCautious (preset Cautious, "
		.. "RegisterCharacteristics.lua:1264)",
	ability_dualwield = "ONLY InterfaceIcons.lua:80 RelationUnfriendly",
	inv_helmet_20 = "OLD InterfaceIcons.lua:28 CharacterMenuItem",
	spell_holy_healingaura = "OLD InterfaceIcons.lua:219 CreditsOthers",
	spell_fire_burningspeed = "OLD InterfaceIcons.lua:168 TraitImpulsive (preset Impulsive, "
		.. "RegisterCharacteristics.lua:1265)",
	ability_warrior_improveddisciplines = "OLD InterfaceIcons.lua:173 TraitRenegade (RegisterCharacteristics.lua:1258)",
	ability_hunter_snipershot = "ONLY InterfaceIcons.lua:179 TraitVindictive (RegisterCharacteristics.lua:1229)",
	spell_holy_auraoflight = "OLD InterfaceIcons.lua:178 TraitValorous (preset Valorous, "
		.. "RegisterCharacteristics.lua:1276)",
	trade_engineering = "OLD InterfaceIcons.lua:217 CreditsAuthors",
	inv_shield_35 = "OLD InterfaceIcons.lua:169 TraitLawful (preset Lawful, RegisterCharacteristics.lua:1217)",
	ability_rogue_disguise = "ONLY InterfaceIcons.lua:79,165 RelationNone, TraitDeceitful",
	achievement_guildperk_everybodysfriend = "UI Blizzard_UIPanels_Game/Classic/FriendsFrame.lua:2423; "
		.. "OLD InterfaceIcons.lua:54,75 ToolbarStatusOOC, RelationFamily",
	spell_arcane_mindmastery = "ONLY InterfaceIcons.lua:27 TraitSection (TRP3's own personality heading)",
}

-- The icons at both ends of every axis: twelve distinct, verified icons.
TraitPlan.ICONS = {
	courage = { left = "spell_shadow_brainwash",              -- Cautious: a wary, watchful mind
		right = "ability_dualwield" },                         -- Bold: crossed swords
	compassion = { left = "inv_helmet_20",                    -- Hard-hearted: a closed helm
		right = "spell_holy_healingaura" },                    -- Compassionate: healing
	discipline = { left = "spell_fire_burningspeed",          -- Impulsive: burning speed
		right = "ability_warrior_improveddisciplines" },       -- Disciplined: discipline
	faith = { left = "ability_hunter_snipershot",             -- Sceptical: scrutiny, a marked target
		right = "spell_holy_auraoflight" },                    -- Devout: the Holy Light
	honour = { left = "trade_engineering",                    -- Pragmatic: tools
		right = "inv_shield_35" },                             -- Principled: the lawful shield
	sociability = { left = "ability_rogue_disguise",          -- Reserved: a hood
		right = "achievement_guildperk_everybodysfriend" },    -- Outgoing: fellowship
}

-- The verified icon for anything not on the list (never the question mark).
TraitPlan.FALLBACK_ICON = "spell_arcane_mindmastery"

--- A verified icon: the name (lower case) when it is on the list, else the
-- fallback. Pure.
function TraitPlan.SafeIcon(name)
	if type(name) == "string" and TraitPlan.VERIFIED[name:lower()] then
		return name:lower()
	end
	return TraitPlan.FALLBACK_ICON
end

--- An axis's icons: left, right (always verified ones).
function TraitPlan.Icons(axisId)
	local icons = TraitPlan.ICONS[axisId] or {}
	return TraitPlan.SafeIcon(icons.left), TraitPlan.SafeIcon(icons.right)
end

--- Whether an icon on a Dawnward trait may be replaced by Dawnward's: no
-- icon, TRP3's placeholder (any case; what Dawnward 0.10.1 wrote), or the
-- icon Dawnward itself last wrote there (written, from the ledger). Any
-- other icon is the player's choice in Total RP 3 and stays.
function TraitPlan.Replaceable(current, written)
	if current == nil then
		return true
	end
	if type(current) ~= "string" then
		return false
	end
	return current:lower() == TraitPlan.PLACEHOLDER:lower() or (written ~= nil and current == written)
end

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
-- { [axisId] = { LT, RT, V2, LI, RI } } for public axes only.
function TraitPlan.Desired(public)
	local out = {}
	for axisId, entry in pairs(public and public.personality or {}) do
		local axis = Schema.PERSONALITY_AXIS_BY_ID[axisId]
		if axis then
			-- The player's own words for the axis (#21), when the profile has them.
			local words = public.axisWords and public.axisWords[axisId] or {}
			local li, ri = TraitPlan.Icons(axisId)
			out[axisId] = { LT = words.left or axis.left, RT = words.right or axis.right,
				V2 = TraitPlan.ToTRP3(entry.value), LI = li, RI = ri }
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

-- The icons a desired trait carries (verified; the axis's own when the
-- desired entry names none).
local function desiredIcons(axisId, d)
	local li, ri = TraitPlan.Icons(axisId)
	return d.LI and TraitPlan.SafeIcon(d.LI) or li, d.RI and TraitPlan.SafeIcon(d.RI) or ri
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
	-- The names every trait will carry after this plan: an owned trait keeps
	-- its index and takes its desired names (or goes, when no longer desired);
	-- any other trait keeps its own. A desired name already carried by a
	-- different trait, or wanted by two axes, would make two identical traits
	-- (and ownership by names unprovable), so it stops the plan instead.
	local after = {}
	for i, trait in ipairs(list) do
		if isCustom(trait) then after[i] = trait.LT .. "\0" .. trait.RT end
	end
	for axisId, i in pairs(index) do
		local d = desired[axisId]
		after[i] = d and (d.LT .. "\0" .. d.RT) or nil
	end
	local wanted = {}
	for _, axisId in ipairs(sortedKeys(desired)) do
		local d = desired[axisId]
		local name = d.LT .. "\0" .. d.RT
		local clash = wanted[name] ~= nil
		for i, other in pairs(after) do
			if other == name and i ~= index[axisId] then clash = true end
		end
		if clash then
			conflicts[#conflicts + 1] = "a trait named " .. d.LT .. "/" .. d.RT .. " already exists in Total RP 3"
				.. " (or two axes use the same words)"
		end
		wanted[name] = axisId
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
			if trait.LT ~= d.LT or trait.RT ~= d.RT then
				-- The player renamed the axis in Dawnward: the same trait, new words.
				trait.LT, trait.RT = d.LT, d.RT
				changes[#changes + 1] = "renamed " .. axisId
			end
			if trait.V2 ~= d.V2 then
				trait.V2 = d.V2
				changes[#changes + 1] = "updated " .. axisId
			end
			-- Icons: Dawnward's replace no icon, TRP3's placeholder or the
			-- icon Dawnward last wrote; an icon the player chose in Total RP 3
			-- stays. The ledger keeps the icon Dawnward wrote, so a later
			-- restyle by the player is recognised as theirs.
			local o = owned[axisId]
			local li, ri = desiredIcons(axisId, d)
			local restyled = false
			if trait.LI ~= li and TraitPlan.Replaceable(trait.LI, o.LI) then
				trait.LI, restyled = li, true
			end
			if trait.RI ~= ri and TraitPlan.Replaceable(trait.RI, o.RI) then
				trait.RI, restyled = ri, true
			end
			if restyled then
				changes[#changes + 1] = "icons " .. axisId
			end
			newOwned[axisId] = { LT = d.LT, RT = d.RT, V2 = d.V2,
				LI = trait.LI == li and li or o.LI, RI = trait.RI == ri and ri or o.RI }
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
			local li, ri = desiredIcons(axisId, d)
			list[#list + 1] = { LT = d.LT, LI = li, RT = d.RT, RI = ri, V2 = d.V2 }
			newOwned[axisId] = { LT = d.LT, RT = d.RT, V2 = d.V2, LI = li, RI = ri }
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
