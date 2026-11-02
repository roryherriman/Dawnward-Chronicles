-- The player's status and look -> Total RP 3, through Total RP 3's own
-- public setters (v0.10.1). Pure Lua: it works on copies and returns a
-- plan (including the setter calls to make); it never touches TRP3.
--
-- Two features, one per Total RP 3 section:
--   "status"  player.character: CU (Currently), CO (OOC information),
--             RP (roleplay status), WU (walk-up)
--   "look"    player.characteristics: IC (profile icon), CH (class colour)
-- Verified in the TRP3 3.4.1 source (Core/Player.lua 413-494): each has a
-- CurrentUser setter (SetCurrentlyText, SetOutOfCharacterInfo,
-- SetRoleplayStatus, SetWalkup, SetCustomIcon, SetCustomClassColor) that
-- goes through UpdateProfileField: it refuses every field but RP and WU on
-- the default profile (Dawnward never writes the default profile anyway),
-- does nothing when the value is unchanged, else stores it, bumps the
-- section version (incrementNumber(v, 2)) and fires REGISTER_DATA_UPDATED.
-- SetCustomClassColor only takes a six-digit hex string (it raises
-- otherwise), so a colour is never cleared through it.
--
-- Ownership (as for profile fields, FieldPlan.lua): Dawnward owns a value
-- only after the player set it in Dawnward while sync for it is on, and
-- only while Total RP 3 still holds exactly what Dawnward last wrote (the
-- ledger records it). Total RP 3 holding anything else is a conflict that
-- pauses that row until the player chooses (keep Total RP 3's, use
-- Dawnward's, or import Total RP 3's into Dawnward). A value Total RP 3
-- already shows exactly is taken over without a write (claim). Nothing is
-- written when the value is the same.
local _, ns = ...
local Util = ns.Util

local StatusPlan = {}
ns.TRP3StatusPlan = StatusPlan

-- id, Total RP 3 key, setter, kind, labels (Dawnward's, Total RP 3's enUS).
StatusPlan.STATUS_MAPPINGS = {
	{ id = "currently", key = "CU", setter = "SetCurrentlyText", kind = "text", label = "Currently",
		trp3 = "Currently", msp = "CU" },
	{ id = "ooc", key = "CO", setter = "SetOutOfCharacterInfo", kind = "text", label = "OOC information",
		trp3 = "Other information (OOC)", msp = "CO" },
	{ id = "rpStatus", key = "RP", setter = "SetRoleplayStatus", kind = "choice", label = "Roleplay status",
		trp3 = "Character status" },
	{ id = "walkup", key = "WU", setter = "SetWalkup", kind = "choice", label = "Walk-up",
		trp3 = "Walkup friendly" },
}
StatusPlan.LOOK_MAPPINGS = {
	{ id = "icon", key = "IC", setter = "SetCustomIcon", kind = "icon", label = "Profile icon",
		trp3 = "Icon" },
	{ id = "classColor", key = "CH", setter = "SetCustomClassColor", kind = "color", label = "Class colour",
		trp3 = "Class color" },
}

-- The Total RP 3 keys a status write may change (Adapter.WriteSection uses
-- the setters for exactly these, and only these, in player.character).
StatusPlan.CHARACTER_KEYS = { CU = "SetCurrentlyText", CO = "SetOutOfCharacterInfo", RP = "SetRoleplayStatus",
	WU = "SetWalkup" }

-- Valid values per kind, for what Total RP 3 holds and what Dawnward writes.
local function valid(m, v)
	if m.kind == "text" then
		return type(v) == "string" and ns.RPStatus.CleanText(v) == v
	elseif m.kind == "choice" then
		local f = ns.RPStatus.BY_ID[m.id]
		return ns.RPStatus.OptionLabel(f.options, v) ~= nil
	elseif m.kind == "icon" then
		return ns.Glance.CleanIcon(v) == v
	elseif m.kind == "color" then
		return type(v) == "string" and v:match("^%x%x%x%x%x%x$") ~= nil
	end
	return false
end
StatusPlan.Valid = valid

-- An empty text (nil or "") holds nothing of anyone's.
local function empty(m, v)
	return v == nil or (m.kind == "text" and v == "")
end

-- Total RP 3 colours may be stored in either case; they mean the same.
local function same(m, a, b)
	if m.kind == "color" and type(a) == "string" and type(b) == "string" then
		return a:lower() == b:lower()
	end
	return a == b
end
StatusPlan.Same = same

--- Builds one feature's planner over its mapping list.
local function feature(name, sectionName, mappings)
	local F = { NAME = name, SECTION = sectionName, MAPPINGS = mappings, BY_ID = {} }
	for _, m in ipairs(mappings) do F.BY_ID[m.id] = m end

	--- Desired values from a public projection: { [id] = value } from
	-- public.status (RPStatus.Get, put there by Sync.PublicOf): a text may
	-- be "" (cleared in Dawnward). Values that are not valid are dropped.
	function F.Desired(public)
		local out = {}
		local status = public and public.status or {}
		for _, m in ipairs(mappings) do
			local v = status[m.id]
			if v ~= nil and (empty(m, v) or valid(m, v)) then
				out[m.id] = v
			end
		end
		return out
	end

	--- What Total RP 3 holds for a mapping (from a section copy).
	function F.Current(section, m)
		return section and section[m.key]
	end

	--- Whether a value could have been written by Dawnward for mapping m
	-- (the ledger keeps only such values).
	function F.IsOwnedValue(m, value)
		return value ~= nil and not empty(m, value) and valid(m, value)
	end

	--- Plans the update of the rows Dawnward manages.
	-- section: a COPY of the TRP3 section (modified in place to what it
	-- will read back as). record: ledger { [id] = { value } } or nil.
	-- desired: from F.Desired. policies: { [id] = policy }; paused:
	-- { [id] = reason }. Returns { action = "write" | "noop", [sectionName]
	-- = section, record, rows, changes, conflicts, calls = { { key, setter,
	-- value } }, claim = true when ownership changes without a write }.
	-- rows[i] = { id, state, current, desired, reason }, state one of
	-- "write", "clear", "noop", "matches", "empty", "released", "conflict".
	function F.Plan(section, record, desired, policies, paused)
		record, policies, paused = record or {}, policies or {}, paused or {}
		local newRecord, rows, changes, conflicts, calls = {}, {}, {}, {}, {}
		local claim = false
		for id, owned in pairs(record) do newRecord[id] = { value = owned.value } end
		local function write(m, value, verb)
			section[m.key] = value
			calls[#calls + 1] = { key = m.key, setter = m.setter, value = value }
			changes[#changes + 1] = verb .. " " .. m.id
		end
		for _, m in ipairs(mappings) do
			if policies[m.id] == "dawnward" then
				local current = section[m.key]
				local want = desired[m.id]
				local owned = record[m.id] and record[m.id].value
				local row = { id = m.id, current = current, desired = want }
				rows[#rows + 1] = row
				if paused[m.id] then
					row.state, row.reason = "conflict", paused[m.id]
				elseif owned == nil and (want == nil or empty(m, want)) then
					-- Nothing of Dawnward's and nothing to write: whatever
					-- Total RP 3 holds (even a value Dawnward could not
					-- track) is the player's, and nothing is paused.
					row.state = "empty"
				elseif current ~= nil and not empty(m, current) and not valid(m, current) then
					row.state, row.reason = "conflict", m.trp3 .. " has a value in Total RP 3 that Dawnward cannot track"
					conflicts[m.id] = row.reason
				elseif owned ~= nil then
					if not same(m, current, owned) then
						row.state = "conflict"
						row.reason = m.trp3 .. " was changed in Total RP 3 since Dawnward last wrote it"
						conflicts[m.id] = row.reason
					elseif want == nil and m.kind == "text" then
						-- Taken out of Dawnward's sync (released): Dawnward's
						-- text comes out again, as an emptied Total RP 3 box.
						write(m, "", "cleared")
						newRecord[m.id] = nil
						row.state = "clear"
					elseif want == nil then
						-- A status, icon or colour has no "empty": Total RP 3 keeps
						-- showing it, and Dawnward no longer owns it.
						newRecord[m.id] = nil
						row.state = "released"
						claim = true
					elseif empty(m, want) then
						write(m, "", "cleared")
						newRecord[m.id] = nil
						row.state = "clear"
					elseif same(m, want, current) then
						row.state = "noop"
					else
						write(m, want, "updated")
						newRecord[m.id] = { value = want }
						row.state = "write"
					end
				elseif want == nil or empty(m, want) then
					row.state = "empty"
				elseif empty(m, current) then
					write(m, want, "added")
					newRecord[m.id] = { value = want }
					row.state = "write"
				elseif same(m, current, want) then
					-- Total RP 3 already shows exactly the player's Dawnward value:
					-- Dawnward keeps it from now on, without writing.
					newRecord[m.id] = { value = current }
					row.state = "matches"
					claim = true
				else
					row.state = "conflict"
					row.reason = m.trp3 .. " already has your own value in Total RP 3"
					conflicts[m.id] = row.reason
				end
			end
		end
		local out = { [sectionName] = section, record = next(newRecord) and newRecord or nil, rows = rows,
			changes = changes, conflicts = conflicts, calls = calls, claim = claim and #calls == 0 or nil }
		out.action = #calls > 0 and "write" or "noop"
		return out
	end

	--- Copy of a section with Dawnward's owned texts emptied (only those
	-- still exactly as Dawnward wrote them; a status, icon or colour stays,
	-- as there is no empty value for it). Returns the copy, or nil plus a
	-- reason when an owned value cannot be separated.
	function F.WithoutOwned(section, record)
		local copy = Util.DeepCopy(section)
		for id, owned in pairs(record or {}) do
			local m = F.BY_ID[id]
			if m then
				if not same(m, copy[m.key], owned.value) then
					return nil, m.trp3 .. " no longer holds Dawnward's value"
				end
				if m.kind == "text" then copy[m.key] = "" end
			end
		end
		return copy
	end

	--- Whether two copies of the section agree on every key this feature
	-- writes (a read-back after setters: other keys are Total RP 3's).
	function F.SameKeys(a, b)
		for _, m in ipairs(mappings) do
			local x, y = a and a[m.key], b and b[m.key]
			if not (empty(m, x) and empty(m, y)) and not same(m, x, y) then
				return false
			end
		end
		return true
	end

	return F
end

StatusPlan.STATUS = feature("status", "character", StatusPlan.STATUS_MAPPINGS)
StatusPlan.LOOK = feature("look", "characteristics", StatusPlan.LOOK_MAPPINGS)
StatusPlan.BY_ID = {}
for _, F in ipairs({ StatusPlan.STATUS, StatusPlan.LOOK }) do
	for _, m in ipairs(F.MAPPINGS) do StatusPlan.BY_ID[m.id] = m end
end

--- A value as the player reads it ("In character" for RP 1). Pure.
function StatusPlan.Display(m, value)
	if value == nil or value == "" then
		return nil
	end
	if m.kind == "choice" then
		return ns.RPStatus.OptionLabel(ns.RPStatus.BY_ID[m.id].options, value) or tostring(value)
	end
	return tostring(value)
end

--- Whether a value could have been written by Dawnward for mapping m (the
-- ledger keeps only such values).
function StatusPlan.IsOwnedValue(m, value)
	return value ~= nil and not empty(m, value) and valid(m, value)
end
