-- Saved data layout (schema version 1) and normalisation.
--
-- Normalisation is the single gate for data entering the database, whether
-- it comes from SavedVariables, a migration or an import: unknown keys are
-- dropped, text is cleaned and capped, list sizes are capped and IDs repaired.
local _, ns = ...
local Util, Privacy = ns.Util, ns.Privacy

local Schema = {}
ns.Schema = Schema

Schema.VERSION = 1

Schema.LIMITS = {
	short = 100,       -- bytes, single-line fields
	long = 2000,       -- bytes, multi-line fields
	characterKey = 100,
	characters = 200,  -- characters per account-wide database
}

-- Profile fields in display order. Nothing here is specific to any race,
-- class or backstory; every field is optional.
Schema.FIELDS = {
	{ key = "name", kind = "short", label = "Name" },
	{ key = "title", kind = "short", label = "Title" },
	{ key = "race", kind = "short", label = "Race" },
	{ key = "class", kind = "short", label = "Class" },
	{ key = "age", kind = "short", label = "Age" },
	{ key = "pronouns", kind = "short", label = "Pronouns" },
	{ key = "homeland", kind = "short", label = "Homeland" },
	{ key = "faith", kind = "short", label = "Faith" },
	{ key = "occupation", kind = "short", label = "Occupation" },
	{ key = "appearance", kind = "long", label = "Appearance" },
	{ key = "summary", kind = "long", label = "Summary" },
	{ key = "motivation", kind = "long", label = "Motivation" },
}

Schema.FIELD_BY_KEY = {}
for _, field in ipairs(Schema.FIELDS) do
	Schema.FIELD_BY_KEY[field.key] = field
end

Schema.FAMILY_STATUS = { living = true, deceased = true, missing = true, unknown = true }

-- Item lists stored on a character. Each field is short, long, or an enum.
Schema.LISTS = {
	family = {
		limit = 100,
		fieldOrder = { "relation", "name", "status", "notes" },
		fields = {
			relation = { kind = "short" },
			name = { kind = "short" },
			status = { kind = "enum", values = Schema.FAMILY_STATUS, default = "unknown" },
			notes = { kind = "long" },
		},
	},
	history = {
		limit = 200,
		fieldOrder = { "when", "text" },
		fields = {
			when = { kind = "short" },
			text = { kind = "long" },
		},
	},
}

function Schema.NewDatabase()
	return {
		schemaVersion = Schema.VERSION,
		characters = {},
		importBackups = {},
	}
end

function Schema.NewCharacter(now)
	return {
		createdAt = now or 0,
		updatedAt = now or 0,
		fields = {},
		family = {},
		history = {},
		nextId = 1,
	}
end

--- Cleans one value for a field spec. Returns the cleaned value or nil.
function Schema.CleanValue(spec, value)
	if spec.kind == "enum" then
		if type(value) == "string" and spec.values[value] then
			return value
		end
		return nil
	end
	local multiline = spec.kind == "long"
	local cleaned = Util.CleanText(value, Schema.LIMITS[spec.kind], multiline)
	if cleaned == nil or cleaned == "" then
		return nil
	end
	return cleaned
end

local function note(report, message)
	if report then
		report[#report + 1] = message
	end
end

local function normalizeTimestamp(value)
	if type(value) == "number" and value >= 0 and value == math.floor(value) then
		return value
	end
	return 0
end

local function normalizeList(rawList, listName, report, usedIds)
	local spec = Schema.LISTS[listName]
	local out = {}
	if type(rawList) ~= "table" then
		return out
	end
	for _, raw in ipairs(rawList) do
		if #out >= spec.limit then
			note(report, listName .. ": dropped entries beyond the limit of " .. spec.limit)
			break
		end
		if type(raw) == "table" then
			local item = { visibility = Privacy.Normalize(raw.visibility) }
			local hasContent = false
			for fieldName, fieldSpec in pairs(spec.fields) do
				local value = Schema.CleanValue(fieldSpec, raw[fieldName])
				if value == nil and fieldSpec.default then
					value = fieldSpec.default
				end
				item[fieldName] = value
				if value ~= nil and fieldSpec.kind ~= "enum" then
					hasContent = true
				end
			end
			if hasContent then
				local id = raw.id
				if not Util.IsPositiveInteger(id) or usedIds[id] then
					id = nil -- reassigned below, after all valid IDs are known
					note(report, listName .. ": repaired an invalid or duplicate ID")
				end
				item.id = id
				if id then
					usedIds[id] = true
				end
				out[#out + 1] = item
			end
		end
	end
	return out
end

--- Returns a cleaned copy of a character. Never modifies raw.
function Schema.NormalizeCharacter(raw, report)
	local char = Schema.NewCharacter()
	if type(raw) ~= "table" then
		return char
	end
	char.createdAt = normalizeTimestamp(raw.createdAt)
	char.updatedAt = normalizeTimestamp(raw.updatedAt)

	if type(raw.fields) == "table" then
		for key, entry in pairs(raw.fields) do
			local spec = Schema.FIELD_BY_KEY[key]
			if spec and type(entry) == "table" then
				local value = Schema.CleanValue(spec, entry.value)
				if value then
					char.fields[key] = { value = value, visibility = Privacy.Normalize(entry.visibility) }
				end
			end
		end
	end

	local usedIds = {}
	char.family = normalizeList(raw.family, "family", report, usedIds)
	char.history = normalizeList(raw.history, "history", report, usedIds)

	-- IDs are unique across both lists so commands can never hit the wrong item type.
	local maxId = 0
	for id in pairs(usedIds) do
		if id > maxId then
			maxId = id
		end
	end
	local nextId = maxId + 1
	if Util.IsPositiveInteger(raw.nextId) and raw.nextId > nextId then
		nextId = raw.nextId
	end
	for _, listName in ipairs({ "family", "history" }) do
		for _, item in ipairs(char[listName]) do
			if not item.id then
				item.id = nextId
				nextId = nextId + 1
			end
		end
	end
	char.nextId = nextId
	return char
end

local function normalizeCharacterMap(rawMap, report, label)
	local out = {}
	if type(rawMap) ~= "table" then
		return out
	end
	local count = 0
	for key, raw in pairs(rawMap) do
		if type(key) == "string" and key ~= "" and #key <= Schema.LIMITS.characterKey and type(raw) == "table" then
			if count >= Schema.LIMITS.characters then
				note(report, label .. ": dropped characters beyond the limit of " .. Schema.LIMITS.characters)
				break
			end
			out[key] = Schema.NormalizeCharacter(raw, report)
			count = count + 1
		end
	end
	return out
end

--- Returns a cleaned copy of a whole database at the current schema version.
function Schema.NormalizeDatabase(raw, report)
	local db = Schema.NewDatabase()
	if type(raw) ~= "table" then
		return db
	end
	db.characters = normalizeCharacterMap(raw.characters, report, "characters")
	db.importBackups = normalizeCharacterMap(raw.importBackups, report, "import backups")
	return db
end
