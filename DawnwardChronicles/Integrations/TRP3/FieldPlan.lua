-- Dawnward profile fields -> Total RP 3 characteristics fields
-- (docs/TRP3_INTEGRATION.md, "Field mappings"). Pure Lua: it works on
-- copies and returns a plan; it never touches TRP3.
--
-- Every mapping below was checked against the TRP3 3.4.1 source (tag 3.4.1,
-- commit 4c25cb0):
--   * each destination is a top-level string of player.characteristics that
--     TRP3's own characteristics editor writes (RegisterCharacteristics.lua
--     saveInDraft: draftData.FT/RA/CL/AG/BP = stEtN(strtrim(text)), so an
--     empty value is stored as nil), with no length limit (letters="0");
--   * FT, RA and CL also have public setters (Player.lua: SetFullTitle,
--     SetCustomRace, SetCustomClass); AG and BP have none;
--   * the MSP bridge sends them as NT, RA, RC, AG and HB (RegisterMSP.lua);
--   * TRP3 sanitises them when a profile loads (sanitizeCharacteristics:
--     Utils.str.sanitize strips colour, link, texture and line codes), so
--     Dawnward only ever writes values that sanitising leaves unchanged.
--
-- Ownership: Dawnward owns a field only while TRP3 still holds the exact
-- value Dawnward last wrote (recorded in the ledger). A value that merely
-- happens to match is never claimed. Anything else is a conflict that pauses
-- that field until the player chooses.
local _, ns = ...
local Util = ns.Util

local FieldPlan = {}
ns.TRP3FieldPlan = FieldPlan

FieldPlan.MAX_BYTES = 100 -- Dawnward's short-field limit (Schema.LIMITS.short)

-- Supported mappings, in display order. risk = "high" marks identity
-- fields players usually curate themselves in TRP3; every mapping starts as
-- "Managed by Total RP 3" whatever its risk.
FieldPlan.MAPPINGS = {
	{ id = "title", source = "title", key = "FT", label = "Title", trp3 = "Full title", msp = "NT",
		setter = "SetFullTitle", risk = "high" },
	{ id = "race", source = "race", key = "RA", label = "Race", trp3 = "Race", msp = "RA",
		setter = "SetCustomRace", risk = "high" },
	{ id = "class", source = "class", key = "CL", label = "Class", trp3 = "Class", msp = "RC",
		setter = "SetCustomClass", risk = "high" },
	{ id = "age", source = "age", key = "AG", label = "Age", trp3 = "Age", msp = "AG" },
	{ id = "homeland", source = "homeland", key = "BP", label = "Homeland", trp3 = "Birthplace", msp = "HB" },
}
FieldPlan.BY_ID = {}
for _, m in ipairs(FieldPlan.MAPPINGS) do
	FieldPlan.BY_ID[m.id] = m
end

-- What Dawnward does NOT synchronise automatically, and why (shown on the
-- Total RP 3 page; the manual "trp3 paste" text still carries the public
-- Dawnward values that have a source).
FieldPlan.UNSUPPORTED = {
	{ label = "First and last name", source = "name",
		reason = "Dawnward keeps one name; splitting it into TRP3's first and last name would be a guess" },
	{ label = "Short title (prefix)", reason = "Dawnward's Title maps to TRP3's full title; the prefix stays yours" },
	{ label = "Pronouns", source = "pronouns",
		reason = "stored in TRP3's additional-information list, not a field Dawnward can own safely" },
	{ label = "Faith, occupation", source = "faith",
		reason = "TRP3 has no field for them (only custom additional information)" },
	{ label = "Appearance", source = "appearance",
		reason = "TRP3 keeps it inside the About template (physical description); Dawnward never edits your text" },
	{ label = "Summary, motivation", source = "summary",
		reason = "long text; public facts, stances and defining moments go into the biography block instead" },
	{ label = "Currently, OOC, RP status", reason = "a live status you set in TRP3; Dawnward has no source for it" },
	{ label = "Eye colour, height, weight, residence, relationship status",
		reason = "Dawnward has no field for them" },
}

--- A value TRP3's sanitiser and editor leave exactly as written: one line,
-- no "|" escape codes, trimmed, at most MAX_BYTES. nil when nothing is left.
function FieldPlan.Clean(value)
	if type(value) ~= "string" then
		return nil
	end
	local v = value:gsub("|", ""):gsub("%c", " "):gsub("%s+", " ")
	v = v:match("^%s*(.-)%s*$")
	-- Dawnward's short fields never exceed this; anything longer is not
	-- shortened (that would publish text the player never wrote).
	if v == "" or #v > FieldPlan.MAX_BYTES then
		return nil
	end
	return v
end

--- Whether a value can be written exactly as it is: returns the value, or
-- nil plus the reason. Dawnward never writes a rewritten value (Clean is
-- only used to recognise values that are already clean).
function FieldPlan.Check(value)
	if type(value) ~= "string" or value == "" then
		return nil, "it is empty"
	end
	if #value > FieldPlan.MAX_BYTES then
		return nil, "it is longer than " .. FieldPlan.MAX_BYTES .. " bytes"
	end
	if value:find("|", 1, true) then
		return nil, "it contains \"|\", which Total RP 3 treats as a formatting code"
	end
	if value:find("%c") then
		return nil, "it contains a line break or control character"
	end
	if FieldPlan.Clean(value) ~= value then
		return nil, "it has extra spaces that Total RP 3 would remove"
	end
	return value
end

--- Desired values from a public projection: { [id] = value } for fields
-- whose Dawnward value is Public and writable as it is, plus
-- { [id] = reason } for Public values that cannot be written unchanged.
-- Never reads anything else.
function FieldPlan.Desired(public)
	local out, unwritable = {}, {}
	local fields = public and public.fields or {}
	for _, m in ipairs(FieldPlan.MAPPINGS) do
		local entry = fields[m.source]
		if type(entry) == "table" and entry.visibility == "public" then
			local value, why = FieldPlan.Check(entry.value)
			if value then
				out[m.id] = value
			else
				unwritable[m.id] = "your " .. m.label .. " cannot be written to Total RP 3 unchanged: " .. why
			end
		end
	end
	return out, unwritable
end

--- Plans the update of the Dawnward-managed fields.
-- characteristics: a COPY of TRP3's characteristics (modified in place).
-- record: ledger { [id] = { value } } of what Dawnward last wrote, or nil.
-- desired: from FieldPlan.Desired.
-- policies: { [id] = "dawnward" | "trp3" | "off" }; only "dawnward" fields
--   are planned.
-- paused: { [id] = reason } fields already in conflict (left untouched).
-- unwritable: { [id] = reason } Public values that cannot be written
--   unchanged (left untouched: never written, never cleared).
-- Returns { action = "write" | "noop", characteristics, record, rows,
--   changes, conflicts = { [id] = reason } (new ones) }.
-- rows[i] = { id, state, current, desired, reason }, state one of
--   "write", "clear", "noop", "matches", "empty", "conflict", "unwritable".
function FieldPlan.Plan(characteristics, record, desired, policies, paused, unwritable)
	record, policies, paused, unwritable = record or {}, policies or {}, paused or {}, unwritable or {}
	local newRecord, rows, changes, conflicts = {}, {}, {}, {}
	for id, owned in pairs(record) do
		newRecord[id] = { value = owned.value }
	end
	for _, m in ipairs(FieldPlan.MAPPINGS) do
		if policies[m.id] == "dawnward" then
			local current = characteristics[m.key]
			local want = desired[m.id]
			local owned = record[m.id] and record[m.id].value
			local row = { id = m.id, current = current, desired = want }
			rows[#rows + 1] = row
			if paused[m.id] then
				row.state, row.reason = "conflict", paused[m.id]
			elseif unwritable[m.id] then
				-- Neither written nor cleared: Dawnward's earlier value (if any)
				-- stays, and the player is told why.
				row.state, row.reason = "unwritable", unwritable[m.id]
			elseif current ~= nil and type(current) ~= "string" then
				row.state, row.reason = "conflict", m.trp3 .. " has an unexpected value in Total RP 3"
				conflicts[m.id] = row.reason
			elseif current == "" then
				-- TRP3's editor never stores "" (stEtN); treat it as foreign.
				row.state, row.reason = "conflict", m.trp3 .. " has an unexpected empty value in Total RP 3"
				conflicts[m.id] = row.reason
			elseif owned ~= nil then
				if current ~= owned then
					row.state = "conflict"
					row.reason = m.trp3 .. " was changed in Total RP 3 since Dawnward last wrote it"
					conflicts[m.id] = row.reason
				elseif want == nil then
					-- No longer Public in Dawnward: take Dawnward's value back out.
					characteristics[m.key] = nil
					newRecord[m.id] = nil
					row.state = "clear"
					changes[#changes + 1] = "cleared " .. m.id
				elseif want == current then
					row.state = "noop"
				else
					characteristics[m.key] = want
					newRecord[m.id] = { value = want }
					row.state = "write"
					changes[#changes + 1] = "updated " .. m.id
				end
			elseif want == nil then
				row.state = "empty"
			elseif current == nil then
				characteristics[m.key] = want
				newRecord[m.id] = { value = want }
				row.state = "write"
				changes[#changes + 1] = "added " .. m.id
			elseif current == want then
				-- Same text, but not written by Dawnward: never claimed.
				row.state = "matches"
			else
				row.state = "conflict"
				row.reason = m.trp3 .. " already has your own value in Total RP 3"
				conflicts[m.id] = row.reason
			end
		end
	end
	local out = { characteristics = characteristics, record = next(newRecord) and newRecord or nil, rows = rows,
		changes = changes, conflicts = conflicts }
	out.action = #changes > 0 and "write" or "noop"
	return out
end

--- Copy of characteristics with Dawnward's owned values removed (only those
-- still exactly as Dawnward wrote them). Returns copy, or nil plus a reason
-- when an owned value cannot be separated.
function FieldPlan.WithoutOwned(characteristics, record)
	local copy = Util.DeepCopy(characteristics)
	for id, owned in pairs(record or {}) do
		local m = FieldPlan.BY_ID[id]
		if m then
			if copy[m.key] ~= owned.value then
				return nil, m.trp3 .. " no longer holds Dawnward's value"
			end
			copy[m.key] = nil
		end
	end
	return copy
end
