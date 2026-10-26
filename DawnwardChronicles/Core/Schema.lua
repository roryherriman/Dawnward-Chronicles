-- Saved data layout (schema version 3) and normalisation.
--
-- Normalisation is the single gate for data entering the database, whether
-- it comes from SavedVariables, a migration or an import: unknown keys are
-- dropped, text is cleaned and capped, list sizes are capped and IDs repaired.
--
-- Schema history:
--   1  profile fields, family, history (v0.1)
--   2  adds per-character journal, journal event keys and theme, and
--      account-wide window preferences (v0.2). Purely additive.
--   3  adds per-character character foundations (v0.3): verbatim biography
--      sources, open interpretations, interpretation key memory, canon facts,
--      personality axis values and a reserved wizard table. Purely additive. Frozen when v0.3 ships;
--      until then later v0.3 milestones may add fields within v3.
local _, ns = ...
local Util, Privacy, Themes = ns.Util, ns.Privacy, ns.Themes

local Schema = {}
ns.Schema = Schema

Schema.VERSION = 3

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

-- Character foundations (v0.3): limits for canon, proposals and sources.
-- At each limit nothing is silently lost: adding a fact or proposal is
-- refused, a biography over the size limit is refused rather than truncated,
-- and the current biography version is never dropped.
Schema.FOUNDATION = {
	facts = 200,        -- approved facts per character
	pending = 300,      -- open interpretations per character
	keyMemory = 1000,   -- remembered interpretation keys, oldest dropped first
	bioVersions = 3,    -- stored biography versions, including the current one
	bioBytes = 16384,   -- bytes per biography version
	statement = 300,    -- bytes per fact or interpretation statement
	excerpt = 300,      -- bytes per quoted excerpt
	categoryBytes = 24,
	keyBytes = 256,
}

-- Fact categories in display order. Stored facts may carry a well-formed
-- category this build does not know (from a newer build); they are kept and
-- shown under Other. New facts must use one of these.
Schema.FACT_CATEGORIES = {
	{ id = "origin", label = "Origin", order = 1 },
	{ id = "relationship", label = "Relationship", order = 2 },
	{ id = "motivation", label = "Motivation", order = 3 },
	{ id = "fear", label = "Fear", order = 4 },
	{ id = "belief", label = "Belief", order = 5 },
	{ id = "trait", label = "Trait", order = 6 },
	{ id = "event", label = "Event", order = 7 },
	{ id = "place", label = "Place", order = 8 },
	{ id = "other", label = "Other", order = 9 },
}

Schema.FACT_CATEGORY_BY_ID = {}
for _, category in ipairs(Schema.FACT_CATEGORIES) do
	Schema.FACT_CATEGORY_BY_ID[category.id] = category
end

-- Where a fact or proposal came from.
Schema.FACT_ORIGINS = {
	["trp3-field"] = true, ["trp3-biography"] = true, paste = true, written = true, answers = true,
	profile = true, journal = true, decision = true, player = true,
}

-- Personality axes: 0 is the left pole, 20 the right. Dawnward's own labels.
Schema.PERSONALITY_AXES = {
	{ id = "courage", left = "Cautious", right = "Bold", order = 1 },
	{ id = "compassion", left = "Hard-hearted", right = "Compassionate", order = 2 },
	{ id = "discipline", left = "Impulsive", right = "Disciplined", order = 3 },
	{ id = "faith", left = "Sceptical", right = "Devout", order = 4 },
	{ id = "honour", left = "Pragmatic", right = "Principled", order = 5 },
	{ id = "sociability", left = "Reserved", right = "Outgoing", order = 6 },
}

Schema.PERSONALITY_AXIS_BY_ID = {}
for _, axis in ipairs(Schema.PERSONALITY_AXES) do
	Schema.PERSONALITY_AXIS_BY_ID[axis.id] = axis
end

Schema.SOURCE_KINDS = { trp3 = true, paste = true, written = true, answers = true }
Schema.INTERPRETATION_KINDS = { candidate = true, insight = true }
Schema.KEY_STATUS = { rejected = true, promoted = true }

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
		sources = Schema.NewSources(),
		interpretations = {},
		interpretationKeys = {},
		facts = {},
		personality = {},
		wizard = {},
	}
end

function Schema.NewSources()
	return { current = nil, nextId = 1, versions = {} }
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

-- Keeps at most limit entries of a key map, dropping the oldest by ageOf(value).
local function capByAge(keys, limit, ageOf)
	local count = Util.CountKeys(keys)
	if count <= limit then
		return 0
	end
	local list = {}
	for key, value in pairs(keys) do
		list[#list + 1] = { key = key, at = ageOf(value) }
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

local function plainAge(at)
	return at
end

--- Keeps at most limit keys, dropping the oldest.
function Schema.CapJournalKeys(keys, limit)
	return capByAge(keys, limit or Schema.JOURNAL.keyLimit, plainAge)
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

--- Character foundations ------------------------------------------------------
-- Sources are stored verbatim (only their size is checked). Facts and
-- interpretations are cleaned like other player text.

function Schema.IsCategoryId(id)
	return type(id) == "string" and #id <= Schema.FOUNDATION.categoryBytes and id:match("^[a-z_]+$") ~= nil
end

function Schema.CleanStatement(value)
	local cleaned = Util.CleanText(value, Schema.FOUNDATION.statement, true)
	if cleaned == nil or cleaned == "" then
		return nil
	end
	return cleaned
end

--- An excerpt is a quote from a source, not canon: cut at a UTF-8 boundary.
function Schema.CleanExcerpt(value)
	local cleaned = Util.CleanText(value, Schema.FOUNDATION.excerpt, true)
	if cleaned == nil or cleaned == "" then
		return nil
	end
	return cleaned
end

function Schema.IsInterpretationKey(key)
	return type(key) == "string" and #key > 0 and #key <= Schema.FOUNDATION.keyBytes
		and not key:find("[%z\1-\31\127|]")
end

--- Content hash of a biography: Adler-32 plus the length in bytes.
function Schema.SourceHash(text)
	return Util.Checksum(text) .. ":" .. #text
end

local function isSourceHash(value)
	return type(value) == "string" and value:match("^%x%x%x%x%x%x%x%x:%d+$") ~= nil
end

--- Cleans fact provenance. Returns the clean table, or nil if origin is invalid.
function Schema.CleanProvenance(raw)
	if type(raw) ~= "table" or not Schema.FACT_ORIGINS[raw.origin] then
		return nil
	end
	local out = { origin = raw.origin, interpreted = raw.interpreted == true }
	if Util.IsPositiveInteger(raw.sourceId) then
		out.sourceId = raw.sourceId
	end
	if isSourceHash(raw.sourceVersion) then
		out.sourceVersion = raw.sourceVersion
	end
	out.ref = Schema.CleanValue(Schema.SHORT, raw.ref)
	out.excerpt = Schema.CleanExcerpt(raw.excerpt)
	if out.interpreted and Schema.IsInterpretationKey(raw.interpretationKey) then
		out.interpretationKey = raw.interpretationKey
	end
	return out
end

--- Cleans one stored fact (without its ID). Returns fact, repaired or nil.
-- A malformed category becomes "other" rather than dropping canon.
function Schema.CleanFact(raw)
	if type(raw) ~= "table" then
		return nil
	end
	local statement = Schema.CleanStatement(raw.statement)
	if not statement then
		return nil
	end
	local repaired = false
	local category = raw.category
	if not Schema.IsCategoryId(category) then
		category = "other"
		repaired = true
	end
	local provenance = Schema.CleanProvenance(raw.provenance)
	if not provenance then
		provenance = { origin = "player", interpreted = false }
		repaired = true
	end
	local fact = {
		category = category,
		statement = statement,
		subject = Schema.CleanValue(Schema.SHORT, raw.subject),
		visibility = Privacy.Normalize(raw.visibility),
		provenance = provenance,
		createdAt = normalizeTimestamp(raw.createdAt),
	}
	if raw.updatedAt ~= nil then
		fact.updatedAt = normalizeTimestamp(raw.updatedAt)
	end
	return fact, repaired
end

--- Cleans one open interpretation. Returns it, or nil if unusable.
function Schema.CleanInterpretation(raw)
	if type(raw) ~= "table" or not Schema.IsInterpretationKey(raw.key)
		or not Schema.INTERPRETATION_KINDS[raw.kind] or not Schema.FACT_ORIGINS[raw.origin]
		or not Schema.IsCategoryId(raw.category) then
		return nil
	end
	local statement = Schema.CleanStatement(raw.statement)
	if not statement then
		return nil
	end
	return {
		key = raw.key,
		kind = raw.kind,
		category = raw.category,
		statement = statement,
		origin = raw.origin,
		sourceId = Util.IsPositiveInteger(raw.sourceId) and raw.sourceId or nil,
		sourceVersion = isSourceHash(raw.sourceVersion) and raw.sourceVersion or nil,
		ref = Schema.CleanValue(Schema.SHORT, raw.ref),
		excerpt = Schema.CleanExcerpt(raw.excerpt),
		visibility = Privacy.Normalize(raw.visibility),
		status = "open",
		createdAt = normalizeTimestamp(raw.createdAt),
	}
end

-- Source metadata: a few short labels, never content.
Schema.SOURCE_META = { "profile", "version", "note" }

function Schema.CleanSourceMeta(raw)
	local meta = {}
	if type(raw) == "table" then
		for _, key in ipairs(Schema.SOURCE_META) do
			meta[key] = Schema.CleanValue(Schema.SHORT, raw[key])
		end
	end
	return meta
end

--- Cleans one stored biography version. The text is kept byte for byte; a
-- version over the size limit is dropped, never truncated.
function Schema.CleanSourceVersion(raw)
	if type(raw) ~= "table" or not Schema.SOURCE_KINDS[raw.kind] or type(raw.text) ~= "string"
		or raw.text == "" or #raw.text > Schema.FOUNDATION.bioBytes then
		return nil
	end
	return {
		kind = raw.kind,
		text = raw.text,
		hash = Schema.SourceHash(raw.text),
		meta = Schema.CleanSourceMeta(raw.meta),
		capturedAt = normalizeTimestamp(raw.capturedAt),
	}
end

--- Drops the oldest earlier versions beyond the limit. Never drops the current one.
function Schema.RotateSources(sources, limit)
	limit = limit or Schema.FOUNDATION.bioVersions
	local removed = 0
	local i = 1
	while #sources.versions > limit and i <= #sources.versions do
		if sources.versions[i].id ~= sources.current then
			table.remove(sources.versions, i)
			removed = removed + 1
		else
			i = i + 1
		end
	end
	return removed
end

local function normalizeSources(raw, report)
	local out = Schema.NewSources()
	if type(raw) ~= "table" or type(raw.versions) ~= "table" then
		return out
	end
	local used, maxId = {}, 0
	for _, rawVersion in ipairs(raw.versions) do
		local version = Schema.CleanSourceVersion(rawVersion)
		if not version then
			note(report, "sources: dropped an unusable or oversized biography version")
		else
			local id = rawVersion.id
			if Util.IsPositiveInteger(id) and not used[id] then
				version.id = id
				used[id] = true
				if id > maxId then
					maxId = id
				end
			end
			out.versions[#out.versions + 1] = version
		end
	end
	local nextId = maxId + 1
	if Util.IsPositiveInteger(raw.nextId) and raw.nextId > nextId then
		nextId = raw.nextId
	end
	for _, version in ipairs(out.versions) do
		if not version.id then
			note(report, "sources: repaired an invalid or duplicate ID")
			version.id = nextId
			nextId = nextId + 1
		end
	end
	table.sort(out.versions, function(a, b) return a.id < b.id end)
	out.nextId = nextId
	if used[raw.current] then
		out.current = raw.current
	elseif #out.versions > 0 then
		out.current = out.versions[#out.versions].id
		if raw.current ~= nil then
			note(report, "sources: the current biography was missing; using the newest stored version")
		end
	end
	if Schema.RotateSources(out) > 0 then
		note(report, "sources: kept the newest " .. Schema.FOUNDATION.bioVersions .. " biography versions")
	end
	return out
end

local function keyAge(entry)
	return entry.at
end

--- Keeps at most limit remembered interpretation keys, dropping the oldest.
function Schema.CapKeyMemory(keys, limit)
	return capByAge(keys, limit or Schema.FOUNDATION.keyMemory, keyAge)
end

local function normalizeInterpretationKeys(raw, report)
	local out = {}
	if type(raw) ~= "table" then
		return out
	end
	for key, entry in pairs(raw) do
		if Schema.IsInterpretationKey(key) and type(entry) == "table" and Schema.KEY_STATUS[entry.status] then
			out[key] = { status = entry.status, at = normalizeTimestamp(entry.at) }
		end
	end
	if Schema.CapKeyMemory(out) > 0 then
		note(report, "interpretation keys: dropped the oldest beyond the limit of " .. Schema.FOUNDATION.keyMemory)
	end
	return out
end

local function normalizeInterpretations(raw, keys, report)
	local out = {}
	if type(raw) ~= "table" then
		return out
	end
	local seen = {}
	for _, rawItem in ipairs(raw) do
		local item = Schema.CleanInterpretation(rawItem)
		if not item then
			note(report, "interpretations: dropped an unusable suggestion")
		elseif not seen[item.key] and not keys[item.key] then
			if #out >= Schema.FOUNDATION.pending then
				note(report, "interpretations: dropped suggestions beyond the limit of " .. Schema.FOUNDATION.pending)
				break
			end
			seen[item.key] = true
			out[#out + 1] = item
		end
	end
	return out
end

local function normalizePersonality(raw)
	local out = {}
	if type(raw) ~= "table" then
		return out
	end
	for axisId, entry in pairs(raw) do
		if Schema.PERSONALITY_AXIS_BY_ID[axisId] and type(entry) == "table" then
			local v = entry.value
			if type(v) == "number" and v == math.floor(v) and v >= 0 and v <= 20 then
				out[axisId] = { value = v, visibility = Privacy.Normalize(entry.visibility),
					updatedAt = normalizeTimestamp(entry.updatedAt) }
			end
		end
	end
	return out
end

local function normalizeFacts(raw, report, usedIds)
	local out = {}
	if type(raw) ~= "table" then
		return out
	end
	for _, rawFact in ipairs(raw) do
		local fact, repaired = Schema.CleanFact(rawFact)
		if not fact then
			note(report, "facts: dropped a fact with no statement")
		else
			if #out >= Schema.FOUNDATION.facts then
				note(report, "facts: dropped facts beyond the limit of " .. Schema.FOUNDATION.facts)
				break
			end
			if repaired then
				note(report, "facts: repaired a malformed category or provenance")
			end
			fact.id = claimId(rawFact, usedIds, report, "facts")
			out[#out + 1] = fact
		end
	end
	return out
end

--- Characters ------------------------------------------------------------------

local ID_LISTS = { "family", "history", "journal", "facts" }

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
	char.facts = normalizeFacts(raw.facts, report, usedIds)
	char.personality = normalizePersonality(raw.personality)
	char.sources = normalizeSources(raw.sources, report)
	char.interpretationKeys = normalizeInterpretationKeys(raw.interpretationKeys, report)
	char.interpretations = normalizeInterpretations(raw.interpretations, char.interpretationKeys, report)
	-- Reserved for the setup wizard (v0.3 M3); nothing is stored here yet.
	char.wizard = {}

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
