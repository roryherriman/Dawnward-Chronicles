-- Dawnward's own record of what it has written to Total RP 3, kept in a
-- separate saved variable (DawnwardChroniclesTRP3DB) so it can never mix
-- with character data, and so a damaged ledger can only ever pause sync.
--
-- It holds:
--   optIn     per character: the TRP3 profile ID sync is bound to, and an
--             ownership policy per mapping (policy[id] = "dawnward" |
--             "trp3" | "off"). about/traits booleans mirror the policy of
--             those two features, so an older build still reads them.
--   profiles  per TRP3 profile ID: the exact content Dawnward last wrote
--             (ownership is proven by an exact match, never by markers),
--             and any unresolved conflict (per feature, and per field)
--   backups   serialised copies of whole TRP3 sections taken before every
--             write, so any write can be rolled back
--   log       the last few diagnostics, for /dawnward trp3 log
--
-- Pure Lua: normalisation follows the same rules as Core/Schema.lua.
local _, ns = ...
local Util, Serializer, FieldPlan, MiscPlan = ns.Util, ns.Serializer, ns.TRP3FieldPlan, ns.TRP3MiscPlan

local Ledger = {}
ns.TRP3Ledger = Ledger

-- 2 (v0.9): additional-information entries (misc) and the full-profile About
-- record (slots, frames, mode). An older build sees a newer ledger and
-- pauses sync instead of misreading it (and duplicating content).
Ledger.VERSION = 2
Ledger.LIMITS = {
	backups = 20,          -- section backups kept in total, oldest unpinned dropped first
	pinned = 4,            -- of those, at most this many pinned (see Ledger.Prune)
	backupBytes = 65536,   -- a section too large to back up is never written
	block = 4100,          -- bytes of an owned biography string (section cap plus separator, with margin)
	ownedTraits = 8,       -- Dawnward-owned personality traits per profile
	log = 30,
	profiles = 200,
	text = 200,            -- short labels and reasons
}

Ledger.SECTIONS = { about = true, characteristics = true }
Ledger.FEATURES = { about = true, traits = true, fields = true, misc = true }

-- Ownership policies. "dawnward": Dawnward writes it automatically (set
-- only by an explicit authorisation). "trp3": Total RP 3 manages it and
-- Dawnward never writes it (the default for every field). "off": not
-- synchronised in either direction.
Ledger.POLICIES = { dawnward = true, trp3 = true, off = true }
-- Every mapping with a policy: the two block features, then each field.
Ledger.MAPPINGS = { "about", "traits" }
for _, m in ipairs(FieldPlan.MAPPINGS) do
	Ledger.MAPPINGS[#Ledger.MAPPINGS + 1] = m.id
end
for _, m in ipairs(MiscPlan.MAPPINGS) do
	Ledger.MAPPINGS[#Ledger.MAPPINGS + 1] = m.id
end
Ledger.MAPPING_SET = {}
for _, id in ipairs(Ledger.MAPPINGS) do
	Ledger.MAPPING_SET[id] = true
end
Ledger.BLOCK_FEATURES = { about = true, traits = true }

--- The policy of one mapping for an opt-in entry (nil entry = defaults).
-- Biography and traits default to "off" (sync off), fields to "trp3".
function Ledger.Policy(entry, id)
	local policy = entry and entry.policy and entry.policy[id]
	if policy then
		return policy
	end
	if Ledger.BLOCK_FEATURES[id] then
		return (entry and entry[id] == true) and "dawnward" or "off"
	end
	return "trp3"
end

--- Sets a mapping's policy, keeping the about/traits booleans in step.
function Ledger.SetPolicy(entry, id, policy)
	entry.policy = entry.policy or {}
	entry.policy[id] = policy
	if Ledger.BLOCK_FEATURES[id] then
		entry[id] = policy == "dawnward"
	end
end

--- True when any field mapping is managed by Dawnward.
function Ledger.AnyFieldManaged(entry)
	for _, m in ipairs(FieldPlan.MAPPINGS) do
		if Ledger.Policy(entry, m.id) == "dawnward" then
			return true
		end
	end
	return false
end

--- True when any additional-information mapping is managed by Dawnward.
function Ledger.AnyMiscManaged(entry)
	for _, m in ipairs(MiscPlan.MAPPINGS) do
		if Ledger.Policy(entry, m.id) == "dawnward" then
			return true
		end
	end
	return false
end

function Ledger.New()
	return { schemaVersion = Ledger.VERSION, optIn = {}, profiles = {}, backups = {}, nextBackupId = 1, log = {} }
end

local function timestamp(v)
	if type(v) == "number" and v >= 0 and v == math.floor(v) and v < 2 ^ 40 then
		return v
	end
	return 0
end

local function shortText(v)
	if type(v) ~= "string" then
		return nil
	end
	local s = Util.CleanText(v, Ledger.LIMITS.text, false)
	if s == "" then
		return nil
	end
	return s
end

--- A TRP3 profile ID we are willing to remember. Default profile IDs end in
-- "*" and change every login, so they are never stored.
function Ledger.IsStorableProfileId(id)
	return type(id) == "string" and id ~= "" and #id <= 100 and id:sub(-1) ~= "*" and not id:find("[%c|]")
end

local function normalizeAbout(raw)
	if type(raw) ~= "table" or type(raw.block) ~= "string" or raw.block == ""
		or #raw.block > Ledger.LIMITS.block then
		return nil
	end
	local template = raw.template
	if template ~= 1 and template ~= 2 and template ~= 3 then
		return nil
	end
	return { block = raw.block, template = template, at = timestamp(raw.at) }
end

local function normalizeTrait(raw)
	if type(raw) ~= "table" or type(raw.LT) ~= "string" or type(raw.RT) ~= "string" then
		return nil
	end
	local v = raw.V2
	if type(v) ~= "number" or v ~= math.floor(v) or v < 0 or v > 20 then
		return nil
	end
	return { LT = raw.LT, RT = raw.RT, V2 = v }
end

local function normalizeTraits(raw)
	if type(raw) ~= "table" or type(raw.owned) ~= "table" then
		return nil
	end
	local owned, count = {}, 0
	for axis, trait in pairs(raw.owned) do
		if type(axis) == "string" and axis:match("^[a-z_]+$") and #axis <= 24 and count < Ledger.LIMITS.ownedTraits then
			local clean = normalizeTrait(trait)
			if clean then
				owned[axis] = clean
				count = count + 1
			end
		end
	end
	return { owned = owned, at = timestamp(raw.at) }
end

-- { [fieldId] = { value } }: the exact value Dawnward last wrote per field.
local function normalizeFields(raw)
	if type(raw) ~= "table" then
		return nil
	end
	local out = {}
	for id, owned in pairs(raw) do
		local m = FieldPlan.BY_ID[id]
		if m and type(owned) == "table" then
			if FieldPlan.IsOwnedValue(m, owned.value) then
				out[id] = { value = owned.value }
			end
		end
	end
	return next(out) and out or nil
end

-- { [miscId] = { value } }: the exact value Dawnward last wrote per entry.
local function normalizeMisc(raw)
	if type(raw) ~= "table" then
		return nil
	end
	local out = {}
	for id, owned in pairs(raw) do
		if MiscPlan.BY_ID[id] and type(owned) == "table" and type(owned.value) == "string"
			and FieldPlan.Clean(owned.value) == owned.value then
			out[id] = { value = owned.value }
		end
	end
	return next(out) and out or nil
end

local function normalizeProfile(raw)
	local out = { conflicts = {}, fieldConflicts = {} }
	if type(raw) ~= "table" then
		return out
	end
	out.about = normalizeAbout(raw.about)
	out.traits = normalizeTraits(raw.traits)
	out.fields = normalizeFields(raw.fields)
	out.misc = normalizeMisc(raw.misc)
	if type(raw.conflicts) == "table" then
		for feature in pairs(Ledger.BLOCK_FEATURES) do
			out.conflicts[feature] = shortText(raw.conflicts[feature])
		end
	end
	if type(raw.fieldConflicts) == "table" then
		for id in pairs(FieldPlan.BY_ID) do
			out.fieldConflicts[id] = shortText(raw.fieldConflicts[id])
		end
		for id in pairs(MiscPlan.BY_ID) do
			out.fieldConflicts[id] = shortText(raw.fieldConflicts[id])
		end
	end
	return out
end

local OWNER_NORMALIZERS = { about = normalizeAbout, traits = normalizeTraits, fields = normalizeFields,
	misc = normalizeMisc }

-- { [feature] = owner record } saved with a backup (all features of its section).
local function normalizeOwners(raw)
	if type(raw) ~= "table" then
		return nil
	end
	local out = {}
	for feature, normalize in pairs(OWNER_NORMALIZERS) do
		out[feature] = normalize(raw[feature])
	end
	return next(out) and out or nil
end
Ledger.NormalizeOwners = normalizeOwners

local function normalizeBackup(raw)
	if type(raw) ~= "table" or not Util.IsPositiveInteger(raw.id) or not Ledger.IsStorableProfileId(raw.profileId)
		or not Ledger.SECTIONS[raw.section] or type(raw.data) ~= "string" or #raw.data > Ledger.LIMITS.backupBytes then
		return nil
	end
	-- A backup that no longer decodes is useless for rollback; drop it.
	if type(Serializer.Decode(raw.data)) ~= "table" then
		return nil
	end
	local out = {
		id = raw.id,
		at = timestamp(raw.at),
		profileId = raw.profileId,
		section = raw.section,
		data = raw.data,
		reason = shortText(raw.reason),
		characterKey = shortText(raw.characterKey),
	}
	-- Which content Dawnward owned when the backup was taken, so a rollback
	-- restores ownership along with the data.
	local normalizeOwner = OWNER_NORMALIZERS[raw.ownerFeature]
	if normalizeOwner then
		out.ownerFeature = raw.ownerFeature
		out.owner = normalizeOwner(raw.owner)
	end
	out.owners = normalizeOwners(raw.owners)
	if raw.pin == "origin" or raw.pin == "reclaim" then
		out.pin = raw.pin
	end
	return out
end

local function normalizePolicy(raw)
	local out = {}
	if type(raw) == "table" then
		for _, id in ipairs(Ledger.MAPPINGS) do
			if Ledger.POLICIES[raw[id]] then
				out[id] = raw[id]
			end
		end
	end
	return out
end

--- Returns a cleaned copy of the ledger. Unknown or damaged parts are dropped.
-- A ledger from a newer build is returned as nil plus a reason (left untouched).
function Ledger.Normalize(raw)
	local out = Ledger.New()
	if raw == nil then
		return out
	end
	if type(raw) ~= "table" then
		return nil, "the TRP3 ledger is not a table"
	end
	if raw.schemaVersion ~= nil and (type(raw.schemaVersion) ~= "number" or raw.schemaVersion > Ledger.VERSION) then
		return nil, "the TRP3 ledger comes from a newer version of Dawnward Chronicles"
	end
	if type(raw.optIn) == "table" then
		for key, entry in pairs(raw.optIn) do
			if type(key) == "string" and #key <= 100 and type(entry) == "table"
				and Ledger.IsStorableProfileId(entry.profileId) then
				local clean = { about = entry.about == true, traits = entry.traits == true,
					profileId = entry.profileId, at = timestamp(entry.at), policy = normalizePolicy(entry.policy) }
				-- v0.9: the player chose "Replace it with Dawnward's" when
				-- connecting; consumed by the first write of each feature.
				if type(entry.adopt) == "table" then
					local adopt = {}
					for feature in pairs(Ledger.FEATURES) do
						if entry.adopt[feature] == true then adopt[feature] = true end
					end
					clean.adopt = next(adopt) and adopt or nil
				end
				-- Migration (v0.7 opt-ins had only the booleans): a feature
				-- that was on becomes "dawnward", with no change in behaviour.
				-- A stored policy wins and the boolean follows it.
				for feature in pairs(Ledger.BLOCK_FEATURES) do
					if clean.policy[feature] or clean[feature] then
						Ledger.SetPolicy(clean, feature, Ledger.Policy(clean, feature))
					end
				end
				out.optIn[key] = clean
			end
		end
	end
	if type(raw.profiles) == "table" then
		local count = 0
		for id, profile in pairs(raw.profiles) do
			if Ledger.IsStorableProfileId(id) and count < Ledger.LIMITS.profiles then
				out.profiles[id] = normalizeProfile(profile)
				count = count + 1
			end
		end
	end
	local maxId = 0
	if type(raw.backups) == "table" then
		local seen = {}
		for _, backup in ipairs(raw.backups) do
			local clean = normalizeBackup(backup)
			if clean and not seen[clean.id] then
				seen[clean.id] = true
				out.backups[#out.backups + 1] = clean
				if clean.id > maxId then maxId = clean.id end
			end
		end
		table.sort(out.backups, function(a, b) return a.id < b.id end)
		Ledger.Prune(out)
	end
	out.nextBackupId = math.max(maxId + 1, Util.IsPositiveInteger(raw.nextBackupId) and raw.nextBackupId or 1)
	if type(raw.log) == "table" then
		for _, line in ipairs(raw.log) do
			if type(line) == "table" and shortText(line.text) then
				out.log[#out.log + 1] = { at = timestamp(line.at), text = shortText(line.text) }
			end
		end
		while #out.log > Ledger.LIMITS.log do
			table.remove(out.log, 1)
		end
	end
	return out
end

--- Profile record (created on demand). Refuses unstorable (default) IDs.
function Ledger.Profile(ledger, profileId)
	if not Ledger.IsStorableProfileId(profileId) then
		return nil
	end
	local profile = ledger.profiles[profileId]
	if not profile then
		profile = { conflicts = {}, fieldConflicts = {} }
		ledger.profiles[profileId] = profile
	end
	profile.fieldConflicts = profile.fieldConflicts or {}
	return profile
end

function Ledger.Log(ledger, now, text)
	ledger.log[#ledger.log + 1] = { at = now or 0, text = shortText(text) or "?" }
	while #ledger.log > Ledger.LIMITS.log do
		table.remove(ledger.log, 1)
	end
end

--- Stores a backup of a whole TRP3 section. meta: { reason, characterKey,
-- ownerFeature ("about" | "traits" | "fields"), owner (that feature's
-- ownership record), owners ({ [feature] = record } for every feature of the
-- section) }. Returns the backup, or nil plus a reason (for example too
-- large), in which case the caller must not write.
function Ledger.AddBackup(ledger, profileId, section, data, meta, now)
	if not Ledger.IsStorableProfileId(profileId) or not Ledger.SECTIONS[section] then
		return nil, "cannot back up this profile or section"
	end
	local text, err = Serializer.Encode(data)
	if not text then
		return nil, "the TRP3 section could not be backed up (" .. tostring(err) .. ")"
	end
	if #text > Ledger.LIMITS.backupBytes then
		return nil, "the TRP3 section is too large to back up safely (" .. #text .. " bytes)"
	end
	local backup = {
		id = ledger.nextBackupId, at = now or 0, profileId = profileId, section = section, data = text,
		reason = shortText(meta and meta.reason), characterKey = shortText(meta and meta.characterKey),
	}
	if meta and OWNER_NORMALIZERS[meta.ownerFeature] then
		backup.ownerFeature = meta.ownerFeature
		backup.owner = OWNER_NORMALIZERS[meta.ownerFeature](Util.DeepCopy(meta.owner))
	end
	backup.owners = normalizeOwners(Util.DeepCopy(meta and meta.owners))
	ledger.nextBackupId = ledger.nextBackupId + 1
	-- Pinning (Ledger.Prune): the state before Dawnward owned anything in
	-- this section (no owners, or the first backup known for it) is kept
	-- until a newer such state exists; so is the player's value replaced by
	-- "Use Dawnward's" (meta.pin = "reclaim").
	local owned = backup.owner ~= nil or backup.owners ~= nil
	local known = Ledger.LatestBackup(ledger, profileId, section) ~= nil
	if meta and meta.pin == "reclaim" then
		backup.pin = "reclaim"
	elseif not owned or not known then
		backup.pin = "origin"
		for _, other in ipairs(ledger.backups) do
			if other.pin == "origin" and other.profileId == profileId and other.section == section then
				other.pin = nil
			end
		end
	end
	ledger.backups[#ledger.backups + 1] = backup
	Ledger.Prune(ledger)
	return backup
end

--- Keeps the backup list bounded: at most LIMITS.backups in total and
-- LIMITS.pinned pinned. The oldest unpinned backup goes first, so many
-- automatic writes never push out the state before Dawnward's first write
-- (or a value the player handed over with "Use Dawnward's"); beyond the
-- pinned limit the oldest pinned one goes.
function Ledger.Prune(ledger)
	local list = ledger.backups
	local pinned = 0
	for _, b in ipairs(list) do
		if b.pin then pinned = pinned + 1 end
	end
	for _, b in ipairs(list) do
		if pinned <= Ledger.LIMITS.pinned then break end
		if b.pin then
			b.pin = nil
			pinned = pinned - 1
		end
	end
	while #list > Ledger.LIMITS.backups do
		local removed = false
		for i, b in ipairs(list) do
			if not b.pin then
				table.remove(list, i)
				removed = true
				break
			end
		end
		if not removed then
			table.remove(list, 1)
		end
	end
end

--- Decoded copy of a backup's section data.
function Ledger.BackupData(backup)
	local data = Serializer.Decode(backup.data)
	if type(data) ~= "table" then
		return nil, "the backup could not be read"
	end
	return data
end

--- Newest backup for a profile (and section, if given).
function Ledger.LatestBackup(ledger, profileId, section)
	for i = #ledger.backups, 1, -1 do
		local b = ledger.backups[i]
		if b.profileId == profileId and (section == nil or b.section == section) then
			return b
		end
	end
	return nil
end

function Ledger.FindBackup(ledger, id)
	for _, b in ipairs(ledger.backups) do
		if b.id == id then
			return b
		end
	end
	return nil
end
