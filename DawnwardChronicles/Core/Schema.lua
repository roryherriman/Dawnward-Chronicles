-- Saved data layout (schema version 2) and normalisation.
--
-- Normalisation is the single gate for data entering the database, whether
-- it comes from SavedVariables, a migration or an import: unknown keys are
-- dropped, text is cleaned and capped, list sizes are capped and IDs repaired.
--
-- Schema history:
--   1  profile fields, family, history (v0.1)
--   2  adds per-character journal, journal event keys and theme, and
--      account-wide window preferences (v0.2). Purely additive.
local _, ns = ...
local Util, Privacy, Themes = ns.Util, ns.Privacy, ns.Themes

local Schema = {}
ns.Schema = Schema

Schema.VERSION = 2

Schema.LIMITS = {
	short = 100,       -- bytes, single-line fields
	long = 2000,       -- bytes, multi-line fields
	characterKey = 100,
	characters = 200,  -- characters per account-wide database
}

-- Journal retention (docs/ARCHITECTURE.md, "Journal retention"):
--   * at most `limit` entries per character
--   * when full, the oldest automatic entry makes room; entries the player
--     wrote are never removed automatically
--   * event keys (duplicate prevention) outlive pruned entries, capped at keyLimit
Schema.JOURNAL = {
	limit = 500,
	keyLimit = 1000,
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

Schema.SHORT = { kind = "short" }
Schema.LONG = { kind = "long" }

function Schema.NewDatabase()
	return {
		schemaVersion = Schema.VERSION,
		characters = {},
		importBackups = {},
		ui = {},
	}
end

function Schema.NewCharacter(now)
	return {
		createdAt = now or 0,
		updatedAt = now or 0,
		fields = {},
		family = {},
		history = {},
		journal = {},
		journalKeys = {},
		theme = Themes.DEFAULT,
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
	if type(value) == "number" and value >= 0 and value == math.floor(value) and value < 2 ^ 40 then
		return value
	end
	return 0
end

local function claimId(raw, usedIds, report, label)
	local id = raw.id
	if not Util.IsPositiveInteger(id) or usedIds[id] then
		note(report, label .. ": repaired an invalid or duplicate ID")
		return nil -- reassigned once all valid IDs are known
	end
	usedIds[id] = true
	return id
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
				item.id = claimId(raw, usedIds, report, listName)
				out[#out + 1] = item
			end
		end
	end
	return out
end

--- Journal ---------------------------------------------------------------------

--- Cleans automatic-event metadata. Returns nil if it is unusable.
-- Unknown event types are kept (they may come from a newer milestone list).
function Schema.CleanEvent(raw)
	if type(raw) ~= "table" then
		return nil
	end
	if type(raw.type) ~= "string" or #raw.type > 32 or not raw.type:match("^[%a_]+$") then
		return nil
	end
	local key = Schema.CleanValue(Schema.SHORT, raw.key)
	if not key then
		return nil
	end
	local level = raw.level
	if not (Util.IsPositiveInteger(level) and level <= 1000) then
		level = nil
	end
	return {
		type = raw.type,
		key = key,
		source = Schema.CleanValue(Schema.SHORT, raw.source),
		level = level,
		zone = Schema.CleanValue(Schema.SHORT, raw.zone),
		subzone = Schema.CleanValue(Schema.SHORT, raw.subzone),
	}
end

--- Cleans one journal entry. Returns nil if it has no usable content.
function Schema.CleanJournalEntry(raw)
	if type(raw) ~= "table" then
		return nil
	end
	local entry = {
		kind = raw.kind,
		visibility = Privacy.Normalize(raw.visibility),
		createdAt = normalizeTimestamp(raw.createdAt),
		text = Schema.CleanValue(Schema.LONG, raw.text),
	}
	if raw.updatedAt ~= nil then
		entry.updatedAt = normalizeTimestamp(raw.updatedAt)
	end
	if raw.kind == "note" then
		entry.title = Schema.CleanValue(Schema.SHORT, raw.title)
		if not entry.title and not entry.text then
			return nil
		end
	elseif raw.kind == "event" then
		entry.event = Schema.CleanEvent(raw.event)
		if not entry.event or not entry.text then
			return nil
		end
	else
		return nil
	end
	return entry
end

local function chronological(a, b)
	if a.createdAt ~= b.createdAt then
		return a.createdAt < b.createdAt
	end
	local ida = Util.IsPositiveInteger(a.rawId) and a.rawId or 0
	local idb = Util.IsPositiveInteger(b.rawId) and b.rawId or 0
	return ida < idb
end

--- Applies the retention policy to a chronological entry list, in place.
-- Removes the oldest automatic entries first. Player-written entries are only
-- removed here if the list holds more notes than the limit, which normal use
-- cannot produce (adding a note to a full journal is refused instead).
-- Returns the number of automatic and written entries removed.
function Schema.ApplyJournalRetention(entries, limit)
	limit = limit or Schema.JOURNAL.limit
	local removedEvents, removedNotes = 0, 0
	local i = 1
	while #entries > limit and i <= #entries do
		if entries[i].kind == "event" then
			table.remove(entries, i)
			removedEvents = removedEvents + 1
		else
			i = i + 1
		end
	end
	while #entries > limit do
		table.remove(entries, 1)
		removedNotes = removedNotes + 1
	end
	return removedEvents, removedNotes
end

--- Keeps at most limit keys, dropping the oldest.
function Schema.CapJournalKeys(keys, limit)
	limit = limit or Schema.JOURNAL.keyLimit
	local count = Util.CountKeys(keys)
	if count <= limit then
		return 0
	end
	local list = {}
	for key, at in pairs(keys) do
		list[#list + 1] = { key = key, at = at }
	end
	table.sort(list, function(a, b)
		if a.at ~= b.at then
			return a.at < b.at
		end
		return a.key < b.key
	end)
	for i = 1, count - limit do
		keys[list[i].key] = nil
	end
	return count - limit
end

local function normalizeJournal(raw, report, usedIds)
	local out = {}
	if type(raw) ~= "table" then
		return out
	end
	for _, rawEntry in ipairs(raw) do
		local entry = Schema.CleanJournalEntry(rawEntry)
		if entry then
			entry.rawId = rawEntry.id
			out[#out + 1] = entry
		end
	end
	table.sort(out, chronological)
	local events, notes = Schema.ApplyJournalRetention(out)
	if events + notes > 0 then
		note(report, string.format("journal: kept the newest %d entries (removed %d automatic, %d written)",
			Schema.JOURNAL.limit, events, notes))
	end
	-- IDs are claimed only for entries that survived retention.
	for _, entry in ipairs(out) do
		entry.id = claimId({ id = entry.rawId }, usedIds, report, "journal")
		entry.rawId = nil
	end
	return out
end

local function normalizeJournalKeys(raw, report)
	local out = {}
	if type(raw) ~= "table" then
		return out
	end
	for key, at in pairs(raw) do
		local clean = Schema.CleanValue(Schema.SHORT, key)
		if clean and clean == key then
			out[key] = normalizeTimestamp(at)
		end
	end
	if Schema.CapJournalKeys(out) > 0 then
		note(report, "journal keys: dropped the oldest beyond the limit of " .. Schema.JOURNAL.keyLimit)
	end
	return out
end

--- Characters ------------------------------------------------------------------

local ID_LISTS = { "family", "history", "journal" }

--- Returns a cleaned copy of a character. Never modifies raw.
function Schema.NormalizeCharacter(raw, report)
	local char = Schema.NewCharacter()
	if type(raw) ~= "table" then
		return char
	end
	char.createdAt = normalizeTimestamp(raw.createdAt)
	char.updatedAt = normalizeTimestamp(raw.updatedAt)
	char.theme = Themes.IsValid(raw.theme) and raw.theme or Themes.DEFAULT

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
	char.journal = normalizeJournal(raw.journal, report, usedIds)
	char.journalKeys = normalizeJournalKeys(raw.journalKeys, report)

	-- IDs are unique across all lists so commands can never hit the wrong item.
	local maxId = 0
	for _, listName in ipairs(ID_LISTS) do
		for _, item in ipairs(char[listName]) do
			if item.id and item.id > maxId then
				maxId = item.id
			end
		end
	end
	local nextId = maxId + 1
	if Util.IsPositiveInteger(raw.nextId) and raw.nextId > nextId then
		nextId = raw.nextId
	end
	for _, listName in ipairs(ID_LISTS) do
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

local function finiteCoordinate(v)
	return type(v) == "number" and v == v and v > -100000 and v < 100000
end

--- Account-wide window preferences. Only a remembered position for now.
function Schema.NormalizeUi(raw)
	local ui = {}
	if type(raw) == "table" and type(raw.position) == "table"
		and finiteCoordinate(raw.position.left) and finiteCoordinate(raw.position.top) then
		ui.position = { left = raw.position.left, top = raw.position.top }
	end
	return ui
end

--- Returns a cleaned copy of a whole database at the current schema version.
function Schema.NormalizeDatabase(raw, report)
	local db = Schema.NewDatabase()
	if type(raw) ~= "table" then
		return db
	end
	db.characters = normalizeCharacterMap(raw.characters, report, "characters")
	db.importBackups = normalizeCharacterMap(raw.importBackups, report, "import backups")
	db.ui = Schema.NormalizeUi(raw.ui)
	return db
end
