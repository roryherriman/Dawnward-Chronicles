-- The roleplay style preferences the player explicitly hands to Dawnward
-- -> Total RP 3's misc.ST (v0.10.1). Pure Lua: it works on copies and
-- returns a plan; it never touches TRP3.
--
-- Verified in the TRP3 3.4.1 source (Modules/Register/Characters/
-- RegisterMisc.lua): player.misc.ST holds the six preferences keyed by
-- STYLE_FIELDS ids "2", "3", "4", "7", "8" and "6" (lines 33-99), each a
-- number from that field's values (0 "Do not show", 1, 2, 3; guild
-- membership 0, 1, 2); a missing key reads as 0 (line 160). Total RP 3 has
-- NO public setter for them: its own editor writes the live table directly
-- (onEditStyle, 104-120: ST[id] = choice, then incrementNumber(v, 2) and
-- REGISTER_DATA_UPDATED(player_id, profileID, "misc")). So Dawnward writes
-- them only through its guarded internal misc write (backup, read-back,
-- restore; Adapter.WriteSection), and only for a preference the player
-- opted in to ("Let Dawnward manage", per preference, off by default).
-- Every other preference is shown read-only.
--
-- Ownership is as for profile fields: Dawnward owns a preference only
-- while Total RP 3 still holds exactly what Dawnward last wrote; anything
-- else pauses that preference until the player chooses.
local _, ns = ...
local Util = ns.Util

local StylePlan = {}
ns.TRP3StylePlan = StylePlan

StylePlan.MAPPINGS = {}
StylePlan.BY_ID = {}
for _, s in ipairs(ns.RPStatus.STYLE) do
	local m = { id = s.id, key = s.key, label = s.label, trp3 = s.label, options = s.options, kind = "style" }
	StylePlan.MAPPINGS[#StylePlan.MAPPINGS + 1] = m
	StylePlan.BY_ID[m.id] = m
end

local function valid(m, v)
	return ns.RPStatus.OptionLabel(m.options, v) ~= nil
end
StylePlan.Valid = valid

--- What Total RP 3 holds for a preference (nil: never chosen).
function StylePlan.Current(misc, m)
	return type(misc) == "table" and type(misc.ST) == "table" and misc.ST[m.key] or nil
end

--- The preference as the player reads it ("Do not show" for nil or 0).
function StylePlan.Display(m, value)
	return ns.RPStatus.OptionLabel(m.options, value or 0) or tostring(value)
end

--- Desired values: { [id] = value } from public.status.style (by key).
function StylePlan.Desired(public)
	local out = {}
	local style = public and public.status and public.status.style or {}
	for _, m in ipairs(StylePlan.MAPPINGS) do
		if valid(m, style[m.key]) then
			out[m.id] = style[m.key]
		end
	end
	return out
end

--- Plans the update of the preferences Dawnward manages.
-- misc: a COPY of TRP3's misc section (modified in place). record: ledger
-- { [id] = { value } } or nil. Other arguments as FieldPlan.Plan.
-- Returns { action, misc, record, rows, changes, conflicts, claim }.
function StylePlan.Plan(misc, record, desired, policies, paused)
	record, policies, paused = record or {}, policies or {}, paused or {}
	local newRecord, rows, changes, conflicts = {}, {}, {}, {}
	local claim = false
	for id, owned in pairs(record) do newRecord[id] = { value = owned.value } end
	local function set(m, value, verb)
		if type(misc.ST) ~= "table" then misc.ST = {} end
		misc.ST[m.key] = value
		changes[#changes + 1] = verb .. " " .. m.id
	end
	for _, m in ipairs(StylePlan.MAPPINGS) do
		if policies[m.id] == "dawnward" then
			local current = StylePlan.Current(misc, m)
			local want = desired[m.id]
			local owned = record[m.id] and record[m.id].value
			local row = { id = m.id, current = current, desired = want }
			rows[#rows + 1] = row
			if paused[m.id] then
				row.state, row.reason = "conflict", paused[m.id]
			elseif current ~= nil and not valid(m, current) then
				row.state, row.reason = "conflict", m.label .. " has a value in Total RP 3 that Dawnward cannot track"
				conflicts[m.id] = row.reason
			elseif owned ~= nil then
				if current ~= owned then
					row.state = "conflict"
					row.reason = m.label .. " was changed in Total RP 3 since Dawnward last wrote it"
					conflicts[m.id] = row.reason
				elseif want == nil then
					-- No longer Dawnward's: its choice comes out ("Do not show").
					set(m, nil, "cleared")
					newRecord[m.id] = nil
					row.state = "clear"
				elseif want == current then
					row.state = "noop"
				else
					set(m, want, "updated")
					newRecord[m.id] = { value = want }
					row.state = "write"
				end
			elseif want == nil then
				row.state = "empty"
			elseif current == nil then
				set(m, want, "added")
				newRecord[m.id] = { value = want }
				row.state = "write"
			elseif current == want then
				newRecord[m.id] = { value = current }
				row.state = "matches"
				claim = true
			else
				row.state = "conflict"
				row.reason = m.label .. " already has your own choice in Total RP 3"
				conflicts[m.id] = row.reason
			end
		end
	end
	local out = { misc = misc, record = next(newRecord) and newRecord or nil, rows = rows, changes = changes,
		conflicts = conflicts }
	out.action = #changes > 0 and "write" or "noop"
	out.claim = (claim and #changes == 0) or nil
	return out
end

--- Copy of misc with Dawnward's owned preferences removed (only those still
-- exactly as Dawnward wrote them). Returns the copy, or nil plus a reason.
function StylePlan.WithoutOwned(misc, record)
	local copy = Util.DeepCopy(misc)
	for id, owned in pairs(record or {}) do
		local m = StylePlan.BY_ID[id]
		if m then
			if StylePlan.Current(copy, m) ~= owned.value then
				return nil, m.label .. " no longer holds Dawnward's choice"
			end
			copy.ST[m.key] = nil
		end
	end
	return copy
end

--- Whether a value could have been written by Dawnward for mapping m.
function StylePlan.IsOwnedValue(m, value)
	return valid(m, value)
end
