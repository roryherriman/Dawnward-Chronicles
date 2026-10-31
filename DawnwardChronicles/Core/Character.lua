-- Edits to a character's profile, family and history.
-- Every write goes through Schema.CleanValue, so stored data always satisfies
-- the schema. Functions return true on success, or nil plus a message.
local _, ns = ...
local Schema, Privacy = ns.Schema, ns.Privacy

local Character = {}
ns.Character = Character

local function touch(char, now)
	if now then
		char.updatedAt = now
	end
end

--- Profile fields ------------------------------------------------------------

function Character.SetField(char, key, value, now)
	local spec = Schema.FIELD_BY_KEY[key]
	if not spec then
		return nil, "unknown field '" .. tostring(key) .. "'"
	end
	local cleaned = Schema.CleanValue(spec, value)
	if not cleaned then
		return nil, "value is empty"
	end
	local existing = char.fields[key]
	char.fields[key] = {
		value = cleaned,
		visibility = existing and existing.visibility or Privacy.DefaultFor(char, "field"),
	}
	touch(char, now)
	return true
end

function Character.ClearField(char, key, now)
	if not Schema.FIELD_BY_KEY[key] then
		return nil, "unknown field '" .. tostring(key) .. "'"
	end
	if not char.fields[key] then
		return nil, "field '" .. key .. "' is already empty"
	end
	char.fields[key] = nil
	touch(char, now)
	return true
end

function Character.SetFieldVisibility(char, key, level, now)
	if not Privacy.IsValid(level) then
		return nil, "visibility must be public, private or secret"
	end
	local entry = char.fields[key]
	if not entry then
		return nil, "field '" .. tostring(key) .. "' has no value"
	end
	entry.visibility = level
	touch(char, now)
	return true
end

--- Lists (family, history) --------------------------------------------------

function Character.FindItem(char, listName, id)
	local list = char[listName]
	if type(list) ~= "table" then
		return nil
	end
	for index, item in ipairs(list) do
		if item.id == id then
			return item, index
		end
	end
	return nil
end

--- Adds an item. values maps field names to raw values. Returns the item.
function Character.AddItem(char, listName, values, now)
	local spec = Schema.LISTS[listName]
	if not spec then
		return nil, "unknown list '" .. tostring(listName) .. "'"
	end
	if #char[listName] >= spec.limit then
		return nil, listName .. " is full (limit " .. spec.limit .. ")"
	end
	local item = { visibility = Privacy.DefaultFor(char, listName) }
	local hasContent = false
	for fieldName, fieldSpec in pairs(spec.fields) do
		local raw = values[fieldName]
		local cleaned = Schema.CleanValue(fieldSpec, raw)
		if raw ~= nil and cleaned == nil and fieldSpec.kind == "enum" then
			return nil, "invalid " .. fieldName .. " '" .. tostring(raw) .. "'"
		end
		if cleaned == nil then
			cleaned = fieldSpec.default
		elseif fieldSpec.kind ~= "enum" then
			hasContent = true
		end
		item[fieldName] = cleaned
	end
	if not hasContent then
		return nil, "nothing to add"
	end
	item.id = char.nextId
	char.nextId = char.nextId + 1
	local list = char[listName]
	list[#list + 1] = item
	touch(char, now)
	return item
end

function Character.UpdateItem(char, listName, id, fieldName, value, now)
	local spec = Schema.LISTS[listName]
	local fieldSpec = spec and spec.fields[fieldName]
	if not fieldSpec then
		return nil, "unknown " .. tostring(listName) .. " field '" .. tostring(fieldName) .. "'"
	end
	local item = Character.FindItem(char, listName, id)
	if not item then
		return nil, "no " .. listName .. " entry #" .. tostring(id)
	end
	local cleaned = Schema.CleanValue(fieldSpec, value)
	if cleaned == nil then
		if fieldSpec.kind == "enum" then
			return nil, "invalid " .. fieldName .. " '" .. tostring(value) .. "'"
		end
		item[fieldName] = nil
	else
		item[fieldName] = cleaned
	end
	touch(char, now)
	return true
end

function Character.SetItemVisibility(char, listName, id, level, now)
	if not Privacy.IsValid(level) then
		return nil, "visibility must be public, private or secret"
	end
	local item = Character.FindItem(char, listName, id)
	if not item then
		return nil, "no " .. tostring(listName) .. " entry #" .. tostring(id)
	end
	item.visibility = level
	touch(char, now)
	return true
end

function Character.RemoveItem(char, listName, id, now)
	local item, index = Character.FindItem(char, listName, id)
	if not item then
		return nil, "no " .. tostring(listName) .. " entry #" .. tostring(id)
	end
	table.remove(char[listName], index)
	touch(char, now)
	return item
end

--- Counts facts by visibility, for summaries.
function Character.CountByVisibility(char)
	local counts = { public = 0, private = 0, secret = 0 }
	for _, entry in pairs(char.fields) do
		local level = Privacy.Normalize(entry.visibility)
		counts[level] = counts[level] + 1
	end
	for _, listName in ipairs({ "family", "history", "journal", "facts" }) do
		for _, item in ipairs(char[listName] or {}) do
			local level = Privacy.Normalize(item.visibility)
			counts[level] = counts[level] + 1
		end
	end
	return counts
end

--- Character foundations summary: facts, open suggestions, whether a
-- biography source is stored.
function Character.FoundationCounts(char)
	local sources = char.sources
	return {
		facts = #(char.facts or {}),
		suggestions = #(char.interpretations or {}),
		biography = sources ~= nil and sources.current ~= nil,
	}
end
