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

--- Adler-32 as 8 hex digits. Formatted as two halves because %x on numbers
-- above 2^31 is not portable across Lua 5.1 builds.
function Transfer.Checksum(text)
	local a, b = 1, 0
	local len = #text
	local i = 1
	while i <= len do
		local chunkEnd = math.min(i + 3999, len)
		local bytes = { text:byte(i, chunkEnd) }
		for j = 1, #bytes do
			a = (a + bytes[j]) % 65521
			b = (b + a) % 65521
		end
		i = chunkEnd + 1
	end
	return string.format("%04x%04x", b, a)
end

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
	-- Schema 1 is the only version so far; older character formats would be
	-- migrated here before normalising.
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
		for listName, spec in pairs(Schema.LISTS) do
			for _, item in ipairs(current[listName]) do
				if item.visibility == Privacy.SECRET and #result[listName] < spec.limit then
					local copy = Util.DeepCopy(item)
					copy.id = result.nextId
					result.nextId = result.nextId + 1
					local list = result[listName]
					list[#list + 1] = copy
					carried = carried + 1
				end
			end
		end
	end
	return result, carried
end

--- One-line summary of an import plan, for confirmation prompts.
function Transfer.Describe(plan)
	local char = plan.character
	local counts = Character.CountByVisibility(char)
	local name = char.fields.name and char.fields.name.value or "(unnamed)"
	return string.format("%s: %d fields, %d family, %d history (%d public, %d private, %d secret)%s",
		name, Util.CountKeys(char.fields), #char.family, #char.history,
		counts.public, counts.private, counts.secret,
		plan.includesSecrets and "" or "; secrets not included in this backup")
end
