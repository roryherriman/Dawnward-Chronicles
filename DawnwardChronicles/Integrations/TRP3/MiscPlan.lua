-- Dawnward profile fields -> entries of Total RP 3's "additional
-- information" list (characteristics.MI), v0.9. Pure Lua: it works on
-- copies and returns a plan; it never touches TRP3.
--
-- Verified in the TRP3 3.4.1 source as installed (Core/ProfileUtil.lua,
-- Modules/Register/Characters/RegisterCharacteristics.lua):
--   * an entry is { ID = type, NA = name, VA = value, IC = icon? }; types:
--     1 custom, 7 pronouns (MiscInfoType); an entry without ID is typed by
--     its name (GetMiscInfoTypeByName), so it counts as custom unless named
--     like a preset;
--   * the editor adds a preset as { ID, NA = localized name, VA, IC = the
--     preset icon } (miscAdd, from GetMiscTypeInfo), its "Create new" entry
--     as { ID = 1, NA, VA, IC = TRP3_InterfaceIcons.Default }, and on Save
--     rewrites NA and VA from its boxes (stEtN(text) or a placeholder),
--     keeping ID and IC;
--   * the profile page shows each entry with IC, else its type's icon, and
--     NA, else its type's name (ProfileUtil.lua CreateMiscFieldInfo), in
--     list order, every entry (setConsultDisplay);
--   * an entry without ID is typed by NA matching a preset's English or
--     localized name (GetMiscInfoTypeByName);
--   * NA and VA are sanitised like the profile fields when a profile loads;
--   * MSP sends the pronouns entry as PN (RegisterMSP.lua).
-- So Dawnward writes one-line clean values only (FieldPlan.Check), always
-- with a name (a missing NA would become "Name" after an editor Save), and
-- recognises its entries by type and value: a preset by ID (or, without
-- ID, by its English or localized name, as TRP3 types it), a custom entry
-- by its name. A new entry gets the icon TRP3's editor would give it
-- (GetMiscTypeInfo(type).icon, resolved for this client); the icon is never
-- compared or rewritten afterwards, so a player can restyle an entry freely.
local _, ns = ...
local FieldPlan = ns.TRP3FieldPlan

local MiscPlan = {}
ns.TRP3MiscPlan = MiscPlan

MiscPlan.CUSTOM = 1
MiscPlan.MAPPINGS = {
	{ id = "pronouns", source = "pronouns", type = 7, name = "Pronouns", label = "Pronouns", trp3 = "Pronouns",
		msp = "PN" },
	{ id = "faith", source = "faith", name = "Faith", label = "Faith", trp3 = "Faith (additional information)" },
	{ id = "occupation", source = "occupation", name = "Occupation", label = "Occupation",
		trp3 = "Occupation (additional information)" },
	{ id = "allegiance", source = "allegiance", name = "Allegiance", label = "Allegiance",
		trp3 = "Allegiance (additional information)" },
}
MiscPlan.BY_ID = {}
for _, m in ipairs(MiscPlan.MAPPINGS) do
	MiscPlan.BY_ID[m.id] = m
end

--- Preset names as this client shows them (TRP3_API.GetMiscTypeInfo), so a
-- written entry looks like one the player added. Read only; falls back to
-- the English names.
function MiscPlan.PresetNames(env)
	local out = {}
	for _, m in ipairs(MiscPlan.MAPPINGS) do
		if m.type then
			local ok, info = pcall(function()
				return env.TRP3_API.GetMiscTypeInfo(m.type)
			end)
			local name = ok and type(info) == "table" and info.localizedName
			out[m.id] = type(name) == "string" and FieldPlan.Check(name) and name or m.name
		end
	end
	return out
end

--- Icons a new entry gets, as TRP3's own editor gives them
-- (TRP3_API.GetMiscTypeInfo(type).icon: the preset's icon, or the custom
-- type's TRP3_InterfaceIcons.Default). Read only; an id is missing when the
-- icon cannot be read (TRP3 then shows the type's icon by itself).
function MiscPlan.PresetIcons(env)
	local out = {}
	for _, m in ipairs(MiscPlan.MAPPINGS) do
		local ok, info = pcall(function()
			return env.TRP3_API.GetMiscTypeInfo(m.type or MiscPlan.CUSTOM)
		end)
		local icon = ok and type(info) == "table" and info.icon
		if type(icon) == "string" and icon:match("^[%w_%-]+$") then
			out[m.id] = icon
		end
	end
	return out
end

--- Desired values: { [id] = value } for Public, writable fields, plus
-- { [id] = reason } for Public values that cannot be written unchanged.
function MiscPlan.Desired(public)
	local out, unwritable = {}, {}
	local fields = public and public.fields or {}
	for _, m in ipairs(MiscPlan.MAPPINGS) do
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

-- Whether a list entry is of mapping m's kind. names: PresetNames (the
-- localized preset names, which TRP3 also types an entry without ID by).
local function sameKind(entry, m, names)
	if type(entry) ~= "table" then
		return false
	end
	if m.type then
		return entry.ID == m.type
			or (entry.ID == nil and (entry.NA == m.name or (names ~= nil and entry.NA == names[m.id])))
	end
	return (entry.ID == nil or entry.ID == MiscPlan.CUSTOM) and type(entry.NA) == "string"
		and entry.NA:lower() == m.name:lower()
end

--- The entries of mapping m's kind: a list of { index, value }.
function MiscPlan.Find(characteristics, m, names)
	local out = {}
	for i, entry in ipairs(type(characteristics.MI) == "table" and characteristics.MI or {}) do
		if sameKind(entry, m, names) then out[#out + 1] = { index = i, value = entry.VA } end
	end
	return out
end

--- Plans the Dawnward-managed additional-information entries.
-- characteristics: a COPY (modified in place). record: ledger
-- { [id] = { value } } of what Dawnward last wrote. desired, unwritable:
-- from Desired. policies: { [id] = policy }. paused: { [id] = reason }.
-- opts: { names = PresetNames, icons = PresetIcons, adopt = bool }.
-- Returns { action = "write" | "noop", characteristics, record, rows,
-- changes, conflicts } like FieldPlan.Plan.
function MiscPlan.Plan(characteristics, record, desired, policies, paused, unwritable, opts)
	record, policies, paused, unwritable, opts = record or {}, policies or {}, paused or {}, unwritable or {},
		opts or {}
	local names, icons = opts.names or {}, opts.icons or {}
	local list = type(characteristics.MI) == "table" and characteristics.MI or {}
	local newRecord, rows, changes, conflicts = {}, {}, {}, {}
	for id, owned in pairs(record) do
		newRecord[id] = { value = owned.value }
	end
	local remove = {}
	for _, m in ipairs(MiscPlan.MAPPINGS) do
		if policies[m.id] == "dawnward" then
			local want = desired[m.id]
			local owned = record[m.id] and record[m.id].value
			local same = {}
			for i, entry in ipairs(list) do
				if sameKind(entry, m, names) then same[#same + 1] = i end
			end
			local row = { id = m.id, desired = want }
			rows[#rows + 1] = row
			local function conflict(reason)
				row.state, row.reason = "conflict", reason
				conflicts[m.id] = reason
			end
			if paused[m.id] then
				row.state, row.reason = "conflict", paused[m.id]
			elseif unwritable[m.id] then
				row.state, row.reason = "unwritable", unwritable[m.id]
			elseif owned ~= nil then
				local mine = {}
				for _, i in ipairs(same) do
					if list[i].VA == owned then mine[#mine + 1] = i end
				end
				if #mine ~= 1 then
					conflict(m.trp3 .. (#mine == 0 and " was changed or removed in Total RP 3 since Dawnward last wrote it"
						or " appears more than once in Total RP 3"))
				elseif want == nil then
					remove[mine[1]] = true
					newRecord[m.id] = nil
					row.state = "clear"
					changes[#changes + 1] = "cleared " .. m.id
				elseif want == owned then
					row.state = "noop"
				else
					list[mine[1]].VA = want
					newRecord[m.id] = { value = want }
					row.state = "write"
					changes[#changes + 1] = "updated " .. m.id
				end
			elseif want == nil then
				row.state = "empty"
			elseif #same == 0 then
				list[#list + 1] = { ID = m.type or MiscPlan.CUSTOM, NA = names[m.id] or m.name, VA = want,
					IC = icons[m.id] }
				newRecord[m.id] = { value = want }
				row.state = "write"
				changes[#changes + 1] = "added " .. m.id
			else
				local matching = false
				for _, i in ipairs(same) do
					if list[i].VA == want then matching = true end
				end
				if matching then
					row.state = "matches"
				elseif opts.adopt and #same == 1 then
					list[same[1]].VA = want
					newRecord[m.id] = { value = want }
					row.state = "write"
					changes[#changes + 1] = "replaced " .. m.id
				else
					conflict(m.trp3 .. " already has your own value in Total RP 3")
				end
			end
		end
	end
	if next(remove) then
		local kept = {}
		for i, entry in ipairs(list) do
			if not remove[i] then kept[#kept + 1] = entry end
		end
		list = kept
	end
	if #changes > 0 then
		characteristics.MI = list
	end
	return { action = #changes > 0 and "write" or "noop", characteristics = characteristics,
		record = next(newRecord) and newRecord or nil, rows = rows, changes = changes, conflicts = conflicts }
end

--- Copy of characteristics without Dawnward's owned entries. Returns the
-- copy, or nil plus a reason when one cannot be found exactly once.
function MiscPlan.WithoutOwned(characteristics, record, names)
	local copy = ns.Util.DeepCopy(characteristics)
	local list = type(copy.MI) == "table" and copy.MI or {}
	for id, owned in pairs(record or {}) do
		local m = MiscPlan.BY_ID[id]
		if m then
			local found
			for i, entry in ipairs(list) do
				if sameKind(entry, m, names) and entry.VA == owned.value then
					if found then return nil, m.trp3 .. " appears more than once" end
					found = i
				end
			end
			if not found then
				return nil, m.trp3 .. " no longer holds Dawnward's value"
			end
			table.remove(list, found)
		end
	end
	return copy
end
