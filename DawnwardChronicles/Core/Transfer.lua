-- Export and import of a character as copy-and-paste text.
--
--   !DWC1!<kind>!<checksum>!<payload>
--
-- kind is "B" (personal backup) or "S" (shareable, public facts only).
-- checksum is Adler-32 of the payload, catching truncated or mangled pastes.
-- payload is Serializer text of { format, kind, schemaVersion, addonVersion,
-- includesSecrets, includesBiography, character, owner? }. owner (v0.7.1+,
-- backups only) is the "Name-Realm" key the backup was made from, so a
-- restore preview can warn before one character's backup replaces another's.
-- Older readers ignore it.
--
-- Share exports carry the public projection only: no biography sources, no
-- interpretations and no key memory. Backups carry facts, interpretations
-- and key memory; biography sources only when asked (includeBiography).
local _, ns = ...
local Schema, Privacy, Projection, Serializer, Util, Character, Facts =
	ns.Schema, ns.Privacy, ns.Projection, ns.Serializer, ns.Util, ns.Character, ns.Facts

local Transfer = {}
ns.Transfer = Transfer

Transfer.PREFIX = "!DWC1!"
Transfer.FORMAT = 1
Transfer.KIND_BACKUP = "backup"
Transfer.KIND_SHARE = "share"

local KIND_CODE = { backup = "B", share = "S" }
local CODE_KIND = { B = "backup", S = "share" }

-- Kept as an alias: the checksum moved to Util so biography hashes can share it.
Transfer.Checksum = Util.Checksum

local SECRET = Privacy.SECRET
-- Stands in for the player's own words when they belong to a secret entry.
Transfer.WITHHELD = "[withheld from this backup: secret]"

--- The story table as it goes into a personal backup.
-- * Compact: full event records are left out (their keys are kept, so a
--   restore can never record an event twice), so the text stays importable.
-- * Without secrets: secret records are left out, and a record's secret
--   side (an identity's private conviction, feelings about a person) is
--   removed; the player's own words in a decision whose journal entry is
--   secret are removed too. MergeForImport carries the current secrets back.
function Transfer.StoryForBackup(char, includeSecrets)
	local story = Util.DeepCopy(char.story or ns.StorySchema.New())
	story.events = {}
	if includeSecrets then
		return story
	end
	local secretEntries = {}
	for _, entry in ipairs(char.journal or {}) do
		if entry.visibility == SECRET then secretEntries[entry.id] = true end
	end
	local function linkedToSecret(r)
		for _, id in ipairs(r.links and r.links.journal or {}) do
			if secretEntries[id] then return true end
		end
		return false
	end
	for name in pairs(ns.StorySchema.RECORD_LISTS) do
		local kept = {}
		for _, r in ipairs(story[name] or {}) do
			if r.visibility ~= SECRET then
				if r.convictionVisibility == SECRET then r.conviction = nil end
				if r.feelingsVisibility == SECRET then r.feelings = nil end
				-- A memory suggested from a secret entry repeats the player's words.
				if r.text and linkedToSecret(r) then r.text = Transfer.WITHHELD end
				kept[#kept + 1] = r
			end
		end
		story[name] = kept
	end
	for _, d in ipairs(story.decisions) do
		if d.journalId and secretEntries[d.journalId] and d.custom then
			d.custom = Transfer.WITHHELD
		end
	end
	-- A review keeps the finding's text, which can quote a record or a
	-- conviction that is Secret; it is rebuilt from the records when shown.
	for _, review in ipairs(story.reviews or {}) do
		if review.message then review.message = Transfer.WITHHELD end
	end
	return story
end

--- opts: { includeSecrets = bool, includeBiography = bool, addonVersion = string,
-- characterKey = string (backups record it as the owner) }
function Transfer.Export(char, kind, opts)
	opts = opts or {}
	local data, includesSecrets, includesBiography
	if kind == Transfer.KIND_SHARE then
		data = Projection.GetPublic(char)
		includesSecrets, includesBiography = false, false
	elseif kind == Transfer.KIND_BACKUP then
		includesSecrets = opts.includeSecrets == true
		local allowed = { public = true, private = true, secret = includesSecrets }
		data = Projection.Filter(char, allowed)
		-- A personal backup keeps milestone and suggestion keys so a restore
		-- cannot re-record old milestones or re-suggest dismissed proposals.
		data.journalKeys = Util.DeepCopy(char.journalKeys)
		data.interpretationKeys = Util.DeepCopy(char.interpretationKeys or {})
		data.interpretations = {}
		for _, item in ipairs(char.interpretations or {}) do
			if Privacy.Allows(allowed, item.visibility) then
				data.interpretations[#data.interpretations + 1] = Util.DeepCopy(item)
			end
		end
		-- The living chronicle travels only in personal backups, filtered
		-- like everything else: no secrets unless asked (Transfer.StoryForBackup).
		data.story = Transfer.StoryForBackup(char, includesSecrets)
		-- The player's own axis words and locks (#21): private, backups only.
		data.axisMeanings = Util.DeepCopy(char.axisMeanings or {})
		-- At First Glance entries the player wrote for Total RP 3 (v0.9): backups only.
		data.glance = Util.DeepCopy(char.glance or {})
		includesBiography = opts.includeBiography == true and char.sources ~= nil
		if includesBiography then
			data.sources = Util.DeepCopy(char.sources)
		end
	else
		return nil, "unknown export kind '" .. tostring(kind) .. "'"
	end
	local payload, err = Serializer.Encode({
		format = Transfer.FORMAT,
		kind = kind,
		schemaVersion = Schema.VERSION,
		addonVersion = opts.addonVersion,
		includesSecrets = includesSecrets,
		includesBiography = includesBiography,
		character = data,
		owner = kind == Transfer.KIND_BACKUP and type(opts.characterKey) == "string" and opts.characterKey or nil,
	})
	if not payload then
		return nil, err
	end
	local text = Transfer.PREFIX .. KIND_CODE[kind] .. "!" .. Transfer.Checksum(payload) .. "!" .. payload
	-- Never hand out text that Decode would refuse: it could not be restored.
	if #text > Serializer.MAX_INPUT then
		return nil, string.format("the export would be %d bytes, more than can be imported again (%d). Nothing was "
			.. "exported; please report this so the limit can be raised", #text, Serializer.MAX_INPUT)
	end
	return text
end

--- Decodes and validates import text.
-- Returns { kind, includesSecrets, addonVersion, character } with the
-- character already normalised, or nil plus a player-facing message.
function Transfer.Decode(text)
	if type(text) ~= "string" then
		return nil, "nothing to import"
	end
	text = Util.Trim(text)
	if text:sub(1, #Transfer.PREFIX) ~= Transfer.PREFIX then
		return nil, "this is not Dawnward Chronicles export text"
	end
	local code, checksum, payload = text:match("^!DWC1!(%u)!(%x+)!(.*)$")
	if not code or not CODE_KIND[code] then
		return nil, "the export header is damaged"
	end
	if Transfer.Checksum(payload) ~= checksum:lower() then
		return nil, "the text is incomplete or was changed after export (checksum mismatch)"
	end
	local data, err = Serializer.Decode(payload)
	if not data then
		return nil, "the export could not be read: " .. tostring(err)
	end
	if type(data) ~= "table" or data.format ~= Transfer.FORMAT or data.kind ~= CODE_KIND[code] then
		return nil, "the export format is not recognised"
	end
	if type(data.schemaVersion) ~= "number" or data.schemaVersion > Schema.VERSION then
		return nil, "this export comes from a newer version of Dawnward Chronicles"
	end
	-- Schemas 2, 3 and 4 only added parts to a character, so older exports
	-- normalise directly (with an empty journal, the neutral theme and empty
	-- foundations). A future change that reshapes characters must migrate
	-- older exports here first.
	local report = {}
	local character = Schema.NormalizeCharacter(data.character, report)
	local includesBiography = data.includesBiography == true and data.kind == Transfer.KIND_BACKUP
	if not includesBiography then
		-- Only a backup made with the biography option may bring sources in.
		character.sources = Schema.NewSources()
	end
	-- Only a v0.4+ personal backup carries a story; a share export never does.
	local includesStory = data.kind == Transfer.KIND_BACKUP and type(data.character) == "table"
		and type(data.character.story) == "table"
	if not includesStory then
		character.story = ns.StorySchema.New()
	end
	return {
		kind = data.kind,
		includesSecrets = data.includesSecrets == true,
		includesBiography = includesBiography,
		includesStory = includesStory,
		addonVersion = type(data.addonVersion) == "string" and data.addonVersion or nil,
		owner = type(data.owner) == "string" and #data.owner <= Schema.LIMITS.characterKey and data.owner or nil,
		character = character,
		notes = report,
	}
end

--- Builds the character that replaces current on import.
-- If the backup was exported without secrets, the current character's secret
-- facts are carried over so importing your own backup never loses them.
-- If it was exported without the biography, the current biography sources
-- are kept, so a restore never discards a stored biography.
-- Returns the merged character and the number of secrets carried over.
-- If it carries no story (an older backup or a share export), the current
-- story is kept; otherwise the imported one is used, and events recorded on
-- either side stay recorded.
function Transfer.MergeForImport(current, imported, includesSecrets, now, includesBiography, includesStory)
	local result = Util.DeepCopy(imported)
	result.createdAt = current and current.createdAt or now or 0
	result.updatedAt = now or 0
	local carried = 0
	if current and not includesSecrets then
		for key, entry in pairs(current.fields) do
			if entry.visibility == Privacy.SECRET and not result.fields[key] then
				result.fields[key] = Util.DeepCopy(entry)
				carried = carried + 1
			end
		end
		local limits = { family = Schema.LISTS.family.limit, history = Schema.LISTS.history.limit,
			journal = Schema.JOURNAL.limit }
		for _, listName in ipairs({ "family", "history", "journal" }) do
			for _, item in ipairs(current[listName] or {}) do
				if item.visibility == Privacy.SECRET and #result[listName] < limits[listName] then
					local copy = Util.DeepCopy(item)
					copy.id = result.nextId
					result.nextId = result.nextId + 1
					local list = result[listName]
					list[#list + 1] = copy
					carried = carried + 1
				end
			end
		end
		for _, fact in ipairs(current.facts or {}) do
			if fact.visibility == Privacy.SECRET and Facts.Restore(result, fact) then
				carried = carried + 1
			end
		end
		table.sort(result.journal, function(a, b)
			if a.createdAt ~= b.createdAt then
				return a.createdAt < b.createdAt
			end
			return a.id < b.id
		end)
	end
	-- Milestones already recorded on either side stay recorded.
	if current then
		for key, at in pairs(current.journalKeys or {}) do
			if result.journalKeys[key] == nil then
				result.journalKeys[key] = at
			end
		end
		Schema.CapJournalKeys(result.journalKeys)
		for key, entry in pairs(current.interpretationKeys or {}) do
			if result.interpretationKeys[key] == nil then
				result.interpretationKeys[key] = Util.DeepCopy(entry)
			end
		end
		Schema.CapKeyMemory(result.interpretationKeys)
		-- A suggestion resolved on either side stays resolved.
		for i = #result.interpretations, 1, -1 do
			if result.interpretationKeys[result.interpretations[i].key] then
				table.remove(result.interpretations, i)
			end
		end
		if not includesBiography then
			result.sources = Util.DeepCopy(current.sources or Schema.NewSources())
		end
		-- A backup from before player-defined axis words (#21) has none:
		-- keep the current ones rather than discarding them.
		if next(result.axisMeanings or {}) == nil and next(current.axisMeanings or {}) ~= nil then
			result.axisMeanings = Util.DeepCopy(current.axisMeanings)
		end
		-- Likewise a backup from before At First Glance entries (v0.9).
		if next(result.glance or {}) == nil and next(current.glance or {}) ~= nil then
			result.glance = Util.DeepCopy(current.glance)
		end
		if current.story then
			if not includesStory then
				result.story = Util.DeepCopy(current.story)
			else
				local rs, cs = result.story, current.story
				for key, at in pairs(cs.eventKeys or {}) do
					if rs.eventKeys[key] == nil then
						rs.eventKeys[key] = at
					end
				end
				ns.StorySchema.CapEventKeys(rs.eventKeys)
				-- The backup leaves full event records out; keep the current ones.
				rs.events = Util.DeepCopy(cs.events or {})
				if not includesSecrets then
					Transfer.CarrySecretStory(rs, cs)
				end
			end
		end
	end
	return result, carried
end

--- Puts the current character's secret story content back into a story
-- restored from a backup made without secrets: secret records, private
-- convictions and feelings kept secret, and withheld answers.
function Transfer.CarrySecretStory(rs, cs)
	local maxId = rs.nextId - 1
	for name in pairs(ns.StorySchema.RECORD_LISTS) do
		local byId = {}
		for _, r in ipairs(rs[name]) do byId[r.id] = r end
		for _, r in ipairs(cs[name] or {}) do
			local mine = byId[r.id]
			if r.visibility == SECRET then
				if not mine then
					local copy = Util.DeepCopy(r)
					if copy.id <= maxId and byId[copy.id] then
						copy.id = rs.nextId
					end
					rs[name][#rs[name] + 1] = copy
					rs.nextId = math.max(rs.nextId, copy.id + 1)
				end
			elseif mine then
				if r.convictionVisibility == SECRET and mine.conviction == nil then mine.conviction = r.conviction end
				if r.feelingsVisibility == SECRET and mine.feelings == nil then mine.feelings = r.feelings end
				if mine.text == Transfer.WITHHELD and r.text then mine.text = r.text end
			end
		end
	end
	local currentDecisions = {}
	for _, d in ipairs(cs.decisions or {}) do currentDecisions[d.id] = d end
	for _, d in ipairs(rs.decisions) do
		local c = currentDecisions[d.id]
		if d.custom == Transfer.WITHHELD and c and c.custom then d.custom = c.custom end
	end
end

--- One-line summary of an import plan, for confirmation prompts.
function Transfer.Describe(plan)
	local char = plan.character
	local counts = Character.CountByVisibility(char)
	local name = char.fields.name and char.fields.name.value or "(unnamed)"
	return string.format("%s: %d fields, %d family, %d history, %d journal, %d facts "
		.. "(%d public, %d private, %d secret)%s%s",
		name, Util.CountKeys(char.fields), #char.family, #char.history, #char.journal, #char.facts,
		counts.public, counts.private, counts.secret,
		plan.includesSecrets and "" or "; secrets not included in this backup",
		plan.includesBiography and "; includes the stored biography"
			or "; no biography in this backup (the current one is kept)")
		.. (plan.includesStory and "; replaces your story (moments, decisions, memories, arcs, goals) with the backup's; "
			.. "events recorded since stay recorded" or "")
end

--- Restore preview ---------------------------------------------------------------

-- What a preview counts, in display order: { label, function(char) -> n }.
local function storyCount(name)
	return function(char) return #((char.story or {})[name] or {}) end
end
Transfer.PREVIEW_ROWS = {
	{ "profile fields", function(char) return Util.CountKeys(char.fields or {}) end },
	{ "facts", function(char) return #(char.facts or {}) end },
	{ "journal entries", function(char) return #(char.journal or {}) end },
	{ "family", function(char) return #(char.family or {}) end },
	{ "history", function(char) return #(char.history or {}) end },
	{ "personality axes", function(char) return Util.CountKeys(char.personality or {}) end },
	{ "decisions", storyCount("decisions") },
	{ "memories", storyCount("memories") },
	{ "arcs", storyCount("arcs") },
	{ "goals", storyCount("goals") },
	{ "stances", storyCount("identity") },
	{ "people", storyCount("people") },
	{ "places", function(char) return Util.CountKeys((char.story or {}).places or {}) end },
	{ "story suggestions waiting", function(char) return #(char.interpretations or {}) end },
}

--- Warning when a backup was made from another character, or nil. Pure.
function Transfer.OwnerWarning(plan, characterKey)
	if plan and plan.owner and characterKey and plan.owner ~= characterKey then
		return "This backup was made from " .. plan.owner .. ", not " .. characterKey .. ". Importing replaces "
			.. characterKey .. "'s profile with it."
	end
	return nil
end

--- A restore preview: one line per record type that differs, "now -> after"
-- (counted on the merged result, so carried-over secrets and kept
-- biographies are included), then the owner warning if any. Pure: it
-- merges copies and changes nothing.
function Transfer.Preview(current, plan, now, characterKey)
	local merged = Transfer.MergeForImport(current, plan.character, plan.includesSecrets, now,
		plan.includesBiography, plan.includesStory)
	local lines = {}
	for _, row in ipairs(Transfer.PREVIEW_ROWS) do
		local before = current and row[2](current) or 0
		local after = row[2](merged)
		if before ~= after or after > 0 then
			lines[#lines + 1] = string.format("  %s: %d now -> %d after%s", row[1], before, after,
				before == after and " (same count)" or "")
		end
	end
	local warning = Transfer.OwnerWarning(plan, characterKey)
	if warning then
		lines[#lines + 1] = "Warning: " .. warning
	end
	return lines
end
