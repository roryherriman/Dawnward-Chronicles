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
--   * v0.9 (TRP3 3.4.1 as installed, same files): FN, LN, TI, EC, HE, WE
--     and RE are written by the same saveInDraft (stEtN(strtrim(...)));
--     FN, LN and TI also have public setters (SetFirstName, SetLastName,
--     SetTitle); RS is a number (tonumber of the dropdown value;
--     AddOn_TotalRP3.Enums.RELATIONSHIP_STATUS: 0 unknown/"do not show",
--     1 single, 2 taken, 3 married, 4 divorced, 5 widowed);
--   * the MSP bridge sends them as NT, RA, RC, AG and HB (RegisterMSP.lua),
--     and NA (from FN and LN), PX (TI), AE, AH, AW, HH and RS;
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
	-- v0.9
	{ id = "firstName", source = "firstName", key = "FN", label = "First name", trp3 = "First name", msp = "NA",
		setter = "SetFirstName", risk = "high", gameDefault = "name" },
	{ id = "lastName", source = "lastName", key = "LN", label = "Last name", trp3 = "Last name", msp = "NA",
		setter = "SetLastName", risk = "high" },
	{ id = "honorific", source = "honorific", key = "TI", label = "Title prefix", trp3 = "Title", msp = "PX",
		setter = "SetTitle" },
	{ id = "eyes", source = "eyes", key = "EC", label = "Eye colour", trp3 = "Eye color", msp = "AE" },
	{ id = "height", source = "height", key = "HE", label = "Height", trp3 = "Height", msp = "AH" },
	{ id = "weight", source = "weight", key = "WE", label = "Build", trp3 = "Body shape", msp = "AW" },
	{ id = "residence", source = "residence", key = "RE", label = "Residence", trp3 = "Residence", msp = "HH" },
	{ id = "relationship", source = "relationship", key = "RS", label = "Relationship status",
		trp3 = "Relationship status", msp = "RS", kind = "relationship" },
}

-- Relationship status words (Dawnward's text) and TRP3's numbers.
FieldPlan.RELATIONSHIP = { single = 1, taken = 2, married = 3, divorced = 4, widowed = 5 }
FieldPlan.RELATIONSHIP_UNKNOWN = 0

-- Values Total RP 3 fills in by itself on a new profile (the character's
-- own name, race and class from the game; RegisterCharacteristics.lua's
-- default profile: RA = Globals.player_race_loc, CL = player_class_loc,
-- FN = Globals.player) are not the player's writing: Dawnward may replace
-- them (after a backup). RS 0 means "do not show".
FieldPlan.GAME_DEFAULT_KEYS = { FN = true, RA = true, CL = true }

-- v0.9: fields whose game value stays published when the player has no
-- Public value of their own (none written, or not Public): the game shows
-- every player's race and class anyway, and TRP3 itself starts a profile
-- with them (so on a fresh profile they already show). When Dawnward takes
-- its own value back out (made Private, cleared, released), the field goes
-- back to the game's value instead of being left empty, without claiming
-- ownership (the game's value is never Dawnward's), so the next run sees it
-- as the replaceable default. A field the player emptied or wrote in TRP3
-- is never touched. Nothing is invented for fields the game does not know.
FieldPlan.GAME_FILL = { FN = true, RA = true, CL = true }

--- The game's own values for the replaceable defaults, read from env
-- (UnitName, UnitRace, UnitClass through Character.GameValue). Read only;
-- missing functions are skipped.
function FieldPlan.GameDefaults(env)
	local GameValue = ns.Character.GameValue
	return { RS = FieldPlan.RELATIONSHIP_UNKNOWN, FN = env and GameValue("firstName", env) or nil,
		RA = env and GameValue("race", env) or nil, CL = env and GameValue("class", env) or nil }
end
FieldPlan.BY_ID = {}
for _, m in ipairs(FieldPlan.MAPPINGS) do
	FieldPlan.BY_ID[m.id] = m
end

-- What Dawnward does NOT synchronise automatically, and why (shown on the
-- Total RP 3 page; the manual "trp3 paste" text still carries the public
-- Dawnward values that have a source).
FieldPlan.UNSUPPORTED = {
	{ label = "Name (one field)", source = "name",
		reason = "Dawnward's Name is kept as it is; TRP3's first and last name come from the First name and Last "
			.. "name details instead, never from splitting it" },
	{ label = "Currently, OOC, RP status", reason = "a live status you set in TRP3; Dawnward has no source for it" },
	{ label = "Icon, class colour, eye colour colour, residence map pin", reason = "TRP3 choices with no Dawnward "
		.. "source; they stay yours" },
	{ label = "Walk-up, roleplay experience, music", reason = "TRP3 settings, not character details" },
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

--- Whether value is something Dawnward could have written for mapping m
-- (a clean one-line string, or a relationship number 1-5).
function FieldPlan.IsOwnedValue(m, value)
	if m.kind == "relationship" then
		return type(value) == "number" and value >= 1 and value <= 5 and value == math.floor(value)
	end
	return type(value) == "string" and FieldPlan.Clean(value) == value
end

--- A value as the player reads it ("married" for RS 3). nil stays nil.
function FieldPlan.Display(m, value)
	if m.kind == "relationship" and type(value) == "number" then
		for word, n in pairs(FieldPlan.RELATIONSHIP) do
			if n == value then return word end
		end
		return value == FieldPlan.RELATIONSHIP_UNKNOWN and nil or tostring(value)
	end
	return value
end

--- The TRP3 number for a relationship status word, or nil plus the reason.
function FieldPlan.Relationship(value)
	if type(value) ~= "string" then
		return nil, "it is empty"
	end
	local n = FieldPlan.RELATIONSHIP[value:lower():match("^%s*(.-)%s*$")]
	if not n then
		return nil, "Total RP 3 only offers single, taken, married, divorced or widowed"
	end
	return n
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
			local check = m.kind == "relationship" and FieldPlan.Relationship or FieldPlan.Check
			local value, why = check(entry.value)
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
-- opts (v0.9): { defaults = { [key] = value } (FieldPlan.GameDefaults: a
--   field still holding the game's own value counts as empty), adopt = true
--   (the player chose "Replace it with Dawnward's" when connecting: a field
--   holding the player's own value is written instead of paused) }.
-- Returns { action = "write" | "noop", characteristics, record, rows,
--   changes, conflicts = { [id] = reason } (new ones) }.
-- rows[i] = { id, state, current, desired, reason }, state one of
--   "write", "clear", "noop", "matches", "empty", "conflict", "unwritable".
function FieldPlan.Plan(characteristics, record, desired, policies, paused, unwritable, opts)
	record, policies, paused, unwritable, opts = record or {}, policies or {}, paused or {}, unwritable or {}, opts or {}
	local defaults = opts.defaults or {}
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
			local valueType = m.kind == "relationship" and "number" or "string"
			-- The game's value to publish when the player has none (GAME_FILL).
			local fill = want == nil and FieldPlan.GAME_FILL[m.key] and defaults[m.key] or nil
			-- The game's own default (or "do not show") counts as empty.
			local isDefault = owned == nil and current ~= nil and defaults[m.key] ~= nil and current == defaults[m.key]
			if paused[m.id] then
				row.state, row.reason = "conflict", paused[m.id]
			elseif unwritable[m.id] then
				-- Neither written nor cleared: Dawnward's earlier value (if any)
				-- stays, and the player is told why.
				row.state, row.reason = "unwritable", unwritable[m.id]
			elseif isDefault and want ~= nil and want ~= current then
				characteristics[m.key] = want
				newRecord[m.id] = { value = want }
				row.state = "write"
				changes[#changes + 1] = "added " .. m.id
			elseif isDefault then
				row.state = (want == nil and not fill) and "empty" or "matches"
			elseif current ~= nil and type(current) ~= valueType then
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
				elseif want == nil and fill and current == fill then
					-- Dawnward's value already is the game's: nothing to change.
					row.state = "noop"
				elseif want == nil and fill then
					-- No longer Public in Dawnward: back to the game's own value
					-- (not owned; the next run sees it as the default).
					characteristics[m.key] = fill
					newRecord[m.id] = nil
					row.state = "write"
					changes[#changes + 1] = "restored the game's " .. m.id
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
			elseif opts.adopt then
				-- The player chose to replace their Total RP 3 text when
				-- connecting; the backup taken before this write keeps it.
				characteristics[m.key] = want
				newRecord[m.id] = { value = want }
				row.state = "write"
				changes[#changes + 1] = "replaced " .. m.id
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
