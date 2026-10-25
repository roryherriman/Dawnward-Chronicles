-- Export and import of a character as copy-and-paste text.
--
--   !DWC1!<kind>!<checksum>!<payload>
--
-- kind is "B" (personal backup) or "S" (shareable, public facts only).
-- checksum is Adler-32 of the payload, catching truncated or mangled pastes.
-- payload is Serializer text of { format, kind, schemaVersion, addonVersion,
-- includesSecrets, character }.
local _, ns = ...
local Schema, Privacy, Projection, Serializer, Util, Character =
	ns.Schema, ns.Privacy, ns.Projection, ns.Serializer, ns.Util, ns.Character

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

--- opts: { includeSecrets = bool, addonVersion = string }
function Transfer.Export(char, kind, opts)
	opts = opts or {}
	local data, includesSecrets
	if kind == Transfer.KIND_SHARE then
		data = Projection.GetPublic(char)
		includesSecrets = false
	elseif kind == Transfer.KIND_BACKUP then
		includesSecrets = opts.includeSecrets == true
		data = Projection.Filter(char, { public = true, private = true, secret = includesSecrets })
		-- A personal backup keeps milestone keys so a restore cannot re-record old milestones.
		data.journalKeys = Util.DeepCopy(char.journalKeys)
	else
		return nil, "unknown export kind '" .. tostring(kind) .. "'"
	end
	local payload, err = Serializer.Encode({
		format = Transfer.FORMAT,
		kind = kind,
		schemaVersion = Schema.VERSION,
		addonVersion = opts.addonVersion,
		includesSecrets = includesSecrets,
		character = data,
	})
	if not payload then
		return nil, err
	end
	return Transfer.PREFIX .. KIND_CODE[kind] .. "!" .. Transfer.Checksum(payload) .. "!" .. payload
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
	-- Schema 2 only added parts to a character, so schema 1 exports normalise
	-- directly (with an empty journal and the neutral theme). A future change
	-- that reshapes characters must migrate older exports here first.
	local report = {}
	local character = Schema.NormalizeCharacter(data.character, report)
	return {
		kind = data.kind,
		includesSecrets = data.includesSecrets == true,
		addonVersion = type(data.addonVersion) == "string" and data.addonVersion or nil,
		character = character,
		notes = report,
	}
end

--- Builds the character that replaces current on import.
-- If the backup was exported without secrets, the current character's secret
-- facts are carried over so importing your own backup never loses them.
-- Returns the merged character and the number of secrets carried over.
function Transfer.MergeForImport(current, imported, includesSecrets, now)
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
	end
	return result, carried
end

--- One-line summary of an import plan, for confirmation prompts.
function Transfer.Describe(plan)
	local char = plan.character
	local counts = Character.CountByVisibility(char)
	local name = char.fields.name and char.fields.name.value or "(unnamed)"
	return string.format("%s: %d fields, %d family, %d history, %d journal (%d public, %d private, %d secret)%s",
		name, Util.CountKeys(char.fields), #char.family, #char.history, #char.journal,
		counts.public, counts.private, counts.secret,
		plan.includesSecrets and "" or "; secrets not included in this backup")
end
