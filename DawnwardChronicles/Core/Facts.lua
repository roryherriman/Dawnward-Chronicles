-- Canon: the facts the player has approved about their character.
--
-- Only two paths create a fact: Facts.Add (the player writes one) and
-- Interpretations.Promote (the player approves a proposal), which calls
-- Facts.AddFromInterpretation. Nothing promotes automatically, and canon is
-- never removed automatically. tests/spec/architecture_spec.lua enforces this.
--
-- Functions return the fact (or true) on success, or nil plus a short reason.
local _, ns = ...
local Schema, Privacy, Util = ns.Schema, ns.Privacy, ns.Util

local Facts = {}
ns.Facts = Facts

Facts.CATEGORIES = Schema.FACT_CATEGORIES
Facts.FULL_MESSAGE = "you already have " .. Schema.FOUNDATION.facts
	.. " facts (the limit). Remove one first; facts are never removed automatically."

local function touch(char, now)
	if now then
		char.updatedAt = now
	end
end

--- Registered category for display. Unknown stored categories show as Other.
function Facts.DisplayCategory(id)
	return Schema.FACT_CATEGORY_BY_ID[id] or Schema.FACT_CATEGORY_BY_ID.other
end

function Facts.IsRegistered(id)
	return Schema.FACT_CATEGORY_BY_ID[id] ~= nil
end

function Facts.CategoryList()
	local ids = {}
	for _, category in ipairs(Schema.FACT_CATEGORIES) do
		ids[#ids + 1] = category.id
	end
	return table.concat(ids, ", ")
end

function Facts.Find(char, id)
	for index, fact in ipairs(char.facts) do
		if fact.id == id then
			return fact, index
		end
	end
	return nil
end

function Facts.Count(char)
	return #char.facts
end

-- Validates values for a new fact. Returns category, statement, subject,
-- visibility or nil plus a reason.
local function validate(values)
	if not Facts.IsRegistered(values.category) then
		return nil, "unknown category '" .. tostring(values.category) .. "' (use " .. Facts.CategoryList() .. ")"
	end
	local statement = Schema.CleanStatement(values.statement)
	if not statement then
		return nil, "the statement is empty"
	end
	local visibility = values.visibility or Privacy.DEFAULT
	if not Privacy.IsValid(visibility) then
		return nil, "visibility must be public, private or secret"
	end
	return values.category, statement, Schema.CleanValue(Schema.SHORT, values.subject), visibility
end

local function insert(char, values, provenance, now)
	if #char.facts >= Schema.FOUNDATION.facts then
		return nil, Facts.FULL_MESSAGE
	end
	local category, statement, subject, visibility = validate(values)
	if not category then
		return nil, statement
	end
	local fact = {
		id = char.nextId,
		category = category,
		statement = statement,
		subject = subject,
		visibility = visibility,
		provenance = provenance,
		createdAt = now or 0,
	}
	char.nextId = char.nextId + 1
	char.facts[#char.facts + 1] = fact
	touch(char, now)
	return fact
end

--- A fact the player writes. provenance is optional (defaults to "player");
-- it is never marked as interpreted.
-- values: { category, statement, subject?, visibility? }
function Facts.Add(char, values, provenance, now)
	local clean = Schema.CleanProvenance(provenance or { origin = "player" })
	if not clean then
		return nil, "invalid provenance"
	end
	clean.interpreted = false
	clean.interpretationKey = nil
	return insert(char, values, clean, now)
end

--- Internal: only Interpretations.Promote calls this (enforced by a test).
function Facts.AddFromInterpretation(char, values, provenance, now)
	local clean = Schema.CleanProvenance(provenance)
	if not clean or not Schema.IsInterpretationKey(provenance.interpretationKey) then
		return nil, "invalid provenance"
	end
	clean.interpreted = true
	return insert(char, values, clean, now)
end

--- Internal: re-inserts an existing fact record during a backup restore
-- (secret carry-over). It creates no new canon: statement, provenance and
-- timestamps are kept; only the ID is renumbered. Only Transfer calls this.
function Facts.Restore(char, fact)
	if #char.facts >= Schema.FOUNDATION.facts then
		return nil, Facts.FULL_MESSAGE
	end
	local copy = Util.DeepCopy(fact)
	copy.id = char.nextId
	char.nextId = char.nextId + 1
	char.facts[#char.facts + 1] = copy
	return copy
end

--- values: { category?, statement?, subject? }; nil leaves a part unchanged,
-- "" clears the subject.
function Facts.Update(char, id, values, now)
	local fact = Facts.Find(char, id)
	if not fact then
		return nil, "no fact #" .. tostring(id)
	end
	local category, statement, subject = fact.category, fact.statement, fact.subject
	if values.category ~= nil then
		if not Facts.IsRegistered(values.category) then
			return nil, "unknown category '" .. tostring(values.category) .. "' (use " .. Facts.CategoryList() .. ")"
		end
		category = values.category
	end
	if values.statement ~= nil then
		statement = Schema.CleanStatement(values.statement)
		if not statement then
			return nil, "the statement would be empty"
		end
	end
	if values.subject ~= nil then
		subject = Schema.CleanValue(Schema.SHORT, values.subject)
	end
	fact.category, fact.statement, fact.subject = category, statement, subject
	fact.updatedAt = now or 0
	touch(char, now)
	return fact
end

function Facts.SetVisibility(char, id, level, now)
	if not Privacy.IsValid(level) then
		return nil, "visibility must be public, private or secret"
	end
	local fact = Facts.Find(char, id)
	if not fact then
		return nil, "no fact #" .. tostring(id)
	end
	fact.visibility = level
	touch(char, now)
	return fact
end

function Facts.Remove(char, id, now)
	local fact, index = Facts.Find(char, id)
	if not fact then
		return nil, "no fact #" .. tostring(id)
	end
	table.remove(char.facts, index)
	touch(char, now)
	return fact
end

--- Facts grouped by display category, in registry order, oldest first within
-- a group. Returns { { category = <registry entry>, facts = { ... } }, ... }
-- with empty groups left out. The facts are the stored records, not copies.
function Facts.ByCategory(char)
	local groups, byId = {}, {}
	for _, category in ipairs(Schema.FACT_CATEGORIES) do
		byId[category.id] = { category = category, facts = {} }
	end
	for _, fact in ipairs(char.facts) do
		local group = byId[Facts.DisplayCategory(fact.category).id]
		group.facts[#group.facts + 1] = fact
	end
	for _, category in ipairs(Schema.FACT_CATEGORIES) do
		if #byId[category.id].facts > 0 then
			groups[#groups + 1] = byId[category.id]
		end
	end
	return groups
end
