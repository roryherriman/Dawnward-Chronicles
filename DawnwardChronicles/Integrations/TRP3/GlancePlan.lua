-- Dawnward-owned At First Glance slots in Total RP 3's misc section (v0.9).
-- Pure Lua: it works on copies and returns a plan; it never touches TRP3.
--
-- Verified in the TRP3 3.4.1 source (Modules/Register/Characters/
-- RegisterMisc.lua, Modules/Register/Main/RegisterGlance.lua,
-- Modules/Register/MSP/RegisterMSP.lua):
--   * player.misc = { v, PE = { ["1"] .. ["5"] = slot }, ST = { ... } }
--     (default profile: { v = 1, PE = {}, ST = {} }); a slot is
--     { IC = icon name, AC = active, TI = title, TX = text }, written by
--     applyPeekSlot, which bumps v (incrementNumber(v, 2)) and fires
--     REGISTER_DATA_UPDATED(player_id, profileID, "misc");
--   * the editor saves TI and TX as stEtN(text) (empty = nil); TI is
--     sanitised as one line, TX as multi-line text (sanitizeMisc);
--   * only active slots are shown to others: getMiscExchangeData drops
--     AC == false slots before sending, MSP sends only AC slots (PE);
--   * ST (the RP style choices) lives in the same section; Dawnward never
--     changes it, and the whole-section write keeps it as it is.
--
-- Ownership: Dawnward owns a slot only while it still holds exactly what
-- Dawnward last wrote there (recorded per slot in the ledger). A slot the
-- player filled in TRP3 is never written, moved or emptied: a new entry
-- goes into a free slot (nil or an empty table), preferring the slot with
-- its own number. An owned slot that was edited, moved or cleared in TRP3
-- is a conflict and nothing is written. An entry whose title and text a
-- slot already shows is not added again (never duplicated).
--
-- Total RP 3 3.5.x (VersionProfiles adapters.iconStorage = "id"): its
-- Apply stores the icon as TRP3_IconUtil.SerializeIcon(ic) (3.5.4
-- RegisterMisc.lua 346), a stringified file ID for any icon it can
-- resolve. A slot whose icon is the file ID of the name Dawnward wrote
-- (opts.sameIcon, VersionProfiles.IconEquivalence: TRP3's own read-only
-- resolver) still holds Dawnward's entry; any other icon is the player's.
local _, ns = ...
local Util = ns.Util

local GlancePlan = {}
ns.TRP3GlancePlan = GlancePlan

GlancePlan.SLOTS = 5

-- Total RP 3 3.5.x (VersionProfiles adapters.interfaceIcons = "trp354"):
-- the presets of Dawnward's icon picker (Glance.ICON_CHOICES) that Total
-- RP 3 3.5.4 lists as the ONLY candidate of an interface icon
-- (Resources/InterfaceIcons.lua, GetFirstValidIcon 10-27, which reports a
-- missing one as an error), so every client 3.5.4 loads on (Mainline and
-- Forever) must have them, plus its built-in default (6-7: name
-- inv_misc_questionmark, ID 134400). On 3.5.x any other preset is written
-- as Glance.DEFAULT_ICON until a live Forever check promotes it; an icon
-- name the player typed that is not one of the presets is their own
-- choice and is written as typed (TRP3 3.5.4 keeps an icon it cannot
-- resolve and shows its default instead: Core/IconUtil.lua 39-77). Static
-- evidence, 3.5.4 line numbers.
GlancePlan.VERIFIED_354 = {
	inv_misc_questionmark = "DEFAULT InterfaceIcons.lua:6-7 (134400)",
	inv_misc_book_09 = "ONLY InterfaceIcons.lua:48 DirectorySection",
	inv_misc_book_12 = "ONLY InterfaceIcons.lua:49 HistorySection",
	inv_misc_note_06 = "ONLY InterfaceIcons.lua:50 MiscInfoSection",
	inv_misc_grouplooking = "ONLY InterfaceIcons.lua:38,91 ProfileDefault, ModeNormal",
	spell_arcane_mindmastery = "ONLY InterfaceIcons.lua:52 TraitSection",
	spell_nature_sleep = "ONLY InterfaceIcons.lua:92 ModeAFK",
	spell_holy_silence = "ONLY InterfaceIcons.lua:84,179 ToolbarLanguage, MiscInfoVoiceReference",
	spell_nature_swiftness = "ONLY InterfaceIcons.lua:69 TargetOpenMount",
	inv_misc_coin_02 = "ONLY InterfaceIcons.lua:201 TraitSelfish",
	ability_rogue_disguise = "ONLY InterfaceIcons.lua:104,192 RelationNone, TraitDeceitful",
	ability_dualwield = "ONLY InterfaceIcons.lua:105 RelationUnfriendly",
	inv_valentinescandy = "ONLY InterfaceIcons.lua:102 RelationLove",
	inv_jewelry_ring_14 = "ONLY InterfaceIcons.lua:175 MiscInfoPiercings",
	inv_misc_gift_02 = "ONLY InterfaceIcons.lua:185 TraitAltruistic",
	inv_rosebouquet01 = "ONLY InterfaceIcons.lua:193 TraitForgiving",
	spell_holy_holyguidance = "ONLY InterfaceIcons.lua:203 TraitSuperstitious",
	ability_hunter_snipershot = "ONLY InterfaceIcons.lua:206 TraitVindictive",
	inv_misc_cape_18 = "ONLY InterfaceIcons.lua:80 ToolbarCloakOn",
	inv_helmet_13 = "ONLY InterfaceIcons.lua:82 ToolbarHelmetOn",
}

-- Allowlists by VersionProfiles adapters.interfaceIcons (nil: every preset,
-- as 3.4.1).
GlancePlan.ICON_SETS = { trp354 = GlancePlan.VERIFIED_354 }

--- Options for a Total RP 3 version: { icons = allowlist or nil, sameIcon
-- = VersionProfiles.IconEquivalence or nil }. Both nil for 3.4.1 (and any
-- version without adapters): exactly 3.4.1's behaviour. Reads env only
-- through IconEquivalence (read only).
function GlancePlan.Options(adapters, env)
	return {
		icons = adapters and GlancePlan.ICON_SETS[adapters.interfaceIcons] or nil,
		sameIcon = ns.TRP3VersionProfiles.IconEquivalence(env, adapters),
	}
end

-- The icon Dawnward writes for an entry: as chosen, unless an allowlist
-- applies and the icon is one of Dawnward's own presets it does not prove.
local function safeIcon(icon, icons)
	if not icons or type(icon) ~= "string" or icons[icon:lower()] then
		return icon
	end
	local lower = icon:lower()
	for _, choice in ipairs(ns.Glance.ICON_CHOICES) do
		if choice == lower then
			return ns.Glance.DEFAULT_ICON
		end
	end
	return icon
end

--- Desired slots from a public projection: public.glance, a list of
-- { n, TI, TX, IC, AC } (Core/Glance.lua Published, put there by
-- Sync.PublicOf). Copies; never reads anything else. opts: from
-- GlancePlan.Options (nil: 3.4.1's).
function GlancePlan.Desired(public, opts)
	local icons = opts and opts.icons
	local out = {}
	for _, entry in ipairs(public and public.glance or {}) do
		out[#out + 1] = { n = entry.n, TI = entry.TI, TX = entry.TX, IC = safeIcon(entry.IC, icons),
			AC = entry.AC == true }
	end
	return out
end

local function slotKeys()
	local keys = {}
	for i = 1, GlancePlan.SLOTS do keys[i] = tostring(i) end
	return keys
end

-- The slot as Dawnward writes it (no n).
local function slotOf(d)
	return { TI = d.TI, TX = d.TX, IC = d.IC, AC = d.AC }
end

-- Whether a live slot holds exactly what Dawnward recorded. sameIcon
-- (GlancePlan.Options; nil: exact, as 3.4.1) also accepts the icon as
-- Total RP 3 3.5.x re-stores it.
local function holds(live, owned, sameIcon)
	return type(live) == "table" and live.TI == owned.TI and live.TX == owned.TX
		and (live.IC == owned.IC or (sameIcon ~= nil and sameIcon(live.IC, owned.IC) == true))
		and live.AC == owned.AC
end

-- A slot nobody uses: absent, or an empty table (a swap with an unused
-- slot leaves one). A slot with only an icon or the active box is the
-- player's.
local function isFree(live)
	return live == nil or (type(live) == "table" and next(live) == nil)
end

local function describe(d)
	return "At First Glance " .. d.n .. (d.TI and (" (" .. d.TI .. ")") or "")
end

--- Plans the owned-slot update.
-- misc: a COPY of TRP3's misc section (modified in place).
-- record: ledger { slots = { [slotKey] = { n, TI, TX, IC, AC } } } or nil.
-- desired: from GlancePlan.Desired. opts: from GlancePlan.Options (nil:
-- 3.4.1's).
-- Returns { action = "noop" | "write" | "conflict" | "unsupported", misc,
-- record, changes, reason }. "unsupported": nothing to write because no
-- slot is free for an entry (not stored as a conflict).
function GlancePlan.Plan(misc, record, desired, opts)
	local sameIcon = opts and opts.sameIcon
	local live = type(misc.PE) == "table" and misc.PE or {}
	local owned = record and record.slots or {}
	local keys = slotKeys()

	-- Every owned slot must still hold Dawnward's content; any doubt stops
	-- the whole plan.
	local conflicts = {}
	for _, key in ipairs(keys) do
		local o = owned[key]
		if o and not holds(live[key], o, sameIcon) then
			conflicts[#conflicts + 1] = describe(o) .. " in slot " .. key
				.. (isFree(live[key]) and " was removed in Total RP 3" or " was changed in Total RP 3")
		end
	end
	if #conflicts > 0 then
		return { action = "conflict", record = record, reason = table.concat(conflicts, "; ") }
	end

	local wanted = {}
	for _, d in ipairs(desired) do wanted[d.n] = d end
	local newSlots, changes, placed = {}, {}, {}

	-- Owned slots: update in place, or empty them when the entry is gone.
	for _, key in ipairs(keys) do
		local o = owned[key]
		if o then
			local d = wanted[o.n]
			if d then
				if not holds(live[key], slotOf(d), sameIcon) then
					live[key] = slotOf(d)
					changes[#changes + 1] = "updated " .. d.n
				end
				newSlots[key] = { n = d.n, TI = d.TI, TX = d.TX, IC = d.IC, AC = d.AC }
				placed[d.n] = true
			else
				live[key] = nil
				changes[#changes + 1] = "removed " .. o.n
			end
		end
	end

	-- New entries: into a free slot, never over the player's own.
	local skipped = {}
	for _, d in ipairs(desired) do
		if not placed[d.n] then
			local shown = false
			for _, key in ipairs(keys) do
				local slot = live[key]
				if type(slot) == "table" and slot.TI == d.TI and slot.TX == d.TX then shown = true end
			end
			if not shown then
				local target = isFree(live[tostring(d.n)]) and tostring(d.n) or nil
				for _, key in ipairs(keys) do
					if not target and isFree(live[key]) then target = key end
				end
				if target then
					live[target] = slotOf(d)
					newSlots[target] = { n = d.n, TI = d.TI, TX = d.TX, IC = d.IC, AC = d.AC }
					changes[#changes + 1] = "added " .. d.n
				else
					skipped[#skipped + 1] = d.n
				end
			end
		end
	end

	local newRecord = next(newSlots) and { slots = newSlots } or nil
	if #changes == 0 then
		if #skipped > 0 then
			return { action = "unsupported", record = record, reason = "every At First Glance slot in Total RP 3 "
				.. "holds your own entry; free one in Total RP 3 for Dawnward's entry " .. table.concat(skipped, ", ") }
		end
		return { action = "noop", misc = misc, record = newRecord, changes = changes }
	end
	if #skipped > 0 then
		changes[#changes + 1] = "no free slot for " .. table.concat(skipped, ", ")
	end
	misc.PE = live
	return { action = "write", misc = misc, record = newRecord, changes = changes }
end

--- Copy of misc without Dawnward's owned slots. Returns the copy, or nil
-- plus a reason when an owned slot no longer holds Dawnward's content.
-- opts: from GlancePlan.Options (nil: exact, as 3.4.1).
function GlancePlan.WithoutOwned(misc, record, opts)
	local copy = Util.DeepCopy(misc)
	local live = type(copy.PE) == "table" and copy.PE or {}
	for key, o in pairs(record and record.slots or {}) do
		if not holds(live[key], o, opts and opts.sameIcon) then
			return nil, describe(o) .. " no longer holds Dawnward's entry"
		end
		live[key] = nil
	end
	return copy
end
