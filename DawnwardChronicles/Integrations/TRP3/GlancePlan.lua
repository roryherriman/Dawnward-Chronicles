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
local _, ns = ...
local Util = ns.Util

local GlancePlan = {}
ns.TRP3GlancePlan = GlancePlan

GlancePlan.SLOTS = 5

--- Desired slots from a public projection: public.glance, a list of
-- { n, TI, TX, IC, AC } (Core/Glance.lua Published, put there by
-- Sync.PublicOf). Copies; never reads anything else.
function GlancePlan.Desired(public)
	local out = {}
	for _, entry in ipairs(public and public.glance or {}) do
		out[#out + 1] = { n = entry.n, TI = entry.TI, TX = entry.TX, IC = entry.IC, AC = entry.AC == true }
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

-- Whether a live slot holds exactly what Dawnward recorded.
local function holds(live, owned)
	return type(live) == "table" and live.TI == owned.TI and live.TX == owned.TX and live.IC == owned.IC
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
-- desired: from GlancePlan.Desired.
-- Returns { action = "noop" | "write" | "conflict" | "unsupported", misc,
-- record, changes, reason }. "unsupported": nothing to write because no
-- slot is free for an entry (not stored as a conflict).
function GlancePlan.Plan(misc, record, desired)
	local live = type(misc.PE) == "table" and misc.PE or {}
	local owned = record and record.slots or {}
	local keys = slotKeys()

	-- Every owned slot must still hold Dawnward's content; any doubt stops
	-- the whole plan.
	local conflicts = {}
	for _, key in ipairs(keys) do
		local o = owned[key]
		if o and not holds(live[key], o) then
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
				if not holds(live[key], slotOf(d)) then
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
function GlancePlan.WithoutOwned(misc, record)
	local copy = Util.DeepCopy(misc)
	local live = type(copy.PE) == "table" and copy.PE or {}
	for key, o in pairs(record and record.slots or {}) do
		if not holds(live[key], o) then
			return nil, describe(o) .. " no longer holds Dawnward's entry"
		end
		live[key] = nil
	end
	return copy
end
