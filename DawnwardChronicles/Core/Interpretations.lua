-- Proposals: candidate facts and insights drawn from sources, waiting for
-- the player's decision. A proposal never becomes canon on its own; only
-- Promote (an explicit player choice) turns one into a fact.
--
-- Each proposal has a stable key built from its origin, category and
-- normalised statement. Rejected and promoted keys are remembered
-- (interpretationKeys), so re-reading an unchanged source suggests nothing
-- twice.
local _, ns = ...
local Schema, Privacy, Util, Facts = ns.Schema, ns.Privacy, ns.Util, ns.Facts

local Interpretations = {}
ns.Interpretations = Interpretations

Interpretations.FULL_MESSAGE = "there are already " .. Schema.FOUNDATION.pending
	.. " open suggestions (the limit). Review some before more can be added."

local KEY_TEXT_LIMIT = 200 -- bytes of normalised text kept readable in a key

--- Normalises a statement for keys: lower case, no punctuation, single spaces.
function Interpretations.NormalizeText(text)
	local s = Util.CleanText(text, nil, false) or ""
	s = s:lower():gsub("%p", ""):gsub("%s+", " ")
	return Util.Trim(s)
end

--- Stable key for a proposal. Long statements keep a readable prefix plus a
-- checksum of the whole normalised text, so keys stay bounded and distinct.
function Interpretations.Key(origin, category, statement)
	local text = Interpretations.NormalizeText(statement)
	if #text > KEY_TEXT_LIMIT then
		text = Util.TruncateUtf8(text, KEY_TEXT_LIMIT - 40) .. "#" .. Util.Checksum(text)
	end
	return tostring(origin) .. ":" .. tostring(category) .. ":" .. text
end

function Interpretations.Find(char, key)
	for index, item in ipairs(char.interpretations) do
		if item.key == key then
			return item, index
		end
	end
	return nil
end

--- Open proposals, oldest first (a new list of the stored records).
function Interpretations.Open(char)
	local out = {}
	for i, item in ipairs(char.interpretations) do
		out[i] = item
	end
	return out
end

--- "open", "rejected", "promoted" or nil.
function Interpretations.Status(char, key)
	if Interpretations.Find(char, key) then
		return "open"
	end
	local memory = char.interpretationKeys[key]
	return memory and memory.status or nil
end

--- values: { kind, category, statement, origin, sourceId?, sourceVersion?,
-- ref?, excerpt?, visibility? }. Returns the proposal, or nil plus "known",
-- "full" or a reason. Nothing changes on failure.
function Interpretations.Propose(char, values, now)
	if not Schema.INTERPRETATION_KINDS[values.kind] then
		return nil, "unknown suggestion kind '" .. tostring(values.kind) .. "'"
	end
	if not Facts.IsRegistered(values.category) then
		return nil, "unknown category '" .. tostring(values.category) .. "'"
	end
	if not Schema.FACT_ORIGINS[values.origin] then
		return nil, "unknown origin '" .. tostring(values.origin) .. "'"
	end
	local visibility = values.visibility or Privacy.DEFAULT
	if not Privacy.IsValid(visibility) then
		return nil, "visibility must be public, private or secret"
	end
	local statement = Schema.CleanStatement(values.statement)
	if not statement then
		return nil, "the statement is empty"
	end
	local key = Interpretations.Key(values.origin, values.category, statement)
	if Interpretations.Status(char, key) then
		return nil, "known"
	end
	if #char.interpretations >= Schema.FOUNDATION.pending then
		return nil, "full"
	end
	local item = Schema.CleanInterpretation({
		key = key, kind = values.kind, category = values.category, statement = statement,
		origin = values.origin, sourceId = values.sourceId, sourceVersion = values.sourceVersion,
		ref = values.ref, excerpt = values.excerpt, visibility = visibility, createdAt = now or 0,
	})
	if not item then
		return nil, "the suggestion is not valid"
	end
	char.interpretations[#char.interpretations + 1] = item
	return item
end

local function remember(char, key, status, now)
	char.interpretationKeys[key] = { status = status, at = now or 0 }
	Schema.CapKeyMemory(char.interpretationKeys)
end

--- Dismisses an open proposal and remembers the key. Returns the proposal.
function Interpretations.Reject(char, key, now)
	local item, index = Interpretations.Find(char, key)
	if not item then
		return nil, "no open suggestion with that key"
	end
	table.remove(char.interpretations, index)
	remember(char, key, "rejected", now)
	return item
end

--- Turns an open proposal into a fact, applying the player's optional edits
-- ({ category?, statement?, subject?, visibility? }). The fact records full
-- provenance. If the fact cannot be created, nothing changes.
function Interpretations.Promote(char, key, edits, now)
	edits = edits or {}
	local item, index = Interpretations.Find(char, key)
	if not item then
		return nil, "no open suggestion with that key"
	end
	local values = {
		category = edits.category or item.category,
		statement = edits.statement or item.statement,
		subject = edits.subject,
		visibility = edits.visibility or item.visibility,
	}
	local provenance = {
		origin = item.origin, sourceId = item.sourceId, sourceVersion = item.sourceVersion,
		ref = item.ref, excerpt = item.excerpt, interpreted = true, interpretationKey = key,
	}
	local fact, err = Facts.AddFromInterpretation(char, values, provenance, now)
	if not fact then
		return nil, err
	end
	table.remove(char.interpretations, index)
	remember(char, key, "promoted", now)
	return fact
end
