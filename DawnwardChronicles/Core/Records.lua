-- The shared contract for narrative records (memories, arcs, goals,
-- identity statements). Every record keeps three things apart:
--
--   provenance  where it came from
--                 observed   verified gameplay data
--                 player     written by the player
--                 suggested  proposed by Dawnward from the player's own answers
--   status      its standing in the character's canon
--                 proposed   a suggestion the player has not accepted yet
--                 established accepted as part of the character's story
--                 disputed   the player marked it as doubtful or contested
--                 superseded replaced by a later record (kept for history)
--   visibility  public / private / secret (Core/Privacy.lua)
--
-- Rules shared by every record type:
--   * Suggestions start proposed and private, always. Only the player
--     establishes them, and only the player makes anything public.
--   * A proposed or disputed record can never be public: making it public
--     is refused until it is established, and loading data repairs it.
--   * A character's beliefs are records of what *they* think, never claims
--     about the world. Only provenance "observed" means the game reported it.
local _, ns = ...
local Util, Privacy = ns.Util, ns.Privacy

local Records = {}
ns.Records = Records

Records.PROVENANCE = { observed = true, player = true, suggested = true }
Records.STATUS = { proposed = true, established = true, disputed = true, superseded = true }
Records.PUBLIC_STATUS = { established = true }

Records.LIMITS = { title = 100, text = 1000, tags = 6, links = 20 }

local function ts(v)
	if type(v) == "number" and v >= 0 and v == math.floor(v) and v < 2 ^ 40 then
		return v
	end
	return 0
end
Records.Timestamp = ts

function Records.Text(v, limit, multiline)
	local s = Util.CleanText(v, limit or Records.LIMITS.title, multiline)
	if s == nil or s == "" then
		return nil
	end
	return s
end

local function idList(raw, limit)
	local out = {}
	if type(raw) == "table" then
		for _, v in ipairs(raw) do
			if Util.IsPositiveInteger(v) and #out < (limit or Records.LIMITS.links) then
				out[#out + 1] = v
			end
		end
	end
	return out
end
Records.IdList = idList

local function keyList(raw)
	local out = {}
	if type(raw) == "table" then
		for _, v in ipairs(raw) do
			local k = Records.Text(v, 100)
			if k and k == v and #out < Records.LIMITS.links then
				out[#out + 1] = k
			end
		end
	end
	return out
end

function Records.Tags(raw)
	local out, seen = {}, {}
	if type(raw) == "table" then
		for _, v in ipairs(raw) do
			local tag = Records.Text(v, 32)
			tag = tag and tag:lower()
			if tag and not seen[tag] and #out < Records.LIMITS.tags then
				seen[tag] = true
				out[#out + 1] = tag
			end
		end
	end
	return out
end

--- Links to other records: { events = {keys}, decisions = {ids}, journal = {ids},
-- memories = {ids}, arcs = {ids}, goals = {ids} }.
function Records.CleanLinks(raw)
	raw = type(raw) == "table" and raw or {}
	return {
		events = keyList(raw.events), decisions = idList(raw.decisions), journal = idList(raw.journal),
		memories = idList(raw.memories), arcs = idList(raw.arcs), goals = idList(raw.goals),
	}
end

--- Cleans the common fields onto out. Returns out, or nil if unusable.
-- Repairs: unknown provenance -> suggested (the safest reading), unknown
-- status -> proposed, and anything not established -> never public.
function Records.CleanCommon(raw, out)
	if type(raw) ~= "table" or not Util.IsPositiveInteger(raw.id) then
		return nil
	end
	out.id = raw.id
	out.provenance = Records.PROVENANCE[raw.provenance] and raw.provenance or "suggested"
	out.status = Records.STATUS[raw.status] and raw.status or "proposed"
	out.visibility = Privacy.Normalize(raw.visibility)
	if out.visibility == Privacy.PUBLIC and not Records.PUBLIC_STATUS[out.status] then
		out.visibility = Privacy.PRIVATE
	end
	out.at = ts(raw.at)
	out.updatedAt = raw.updatedAt ~= nil and ts(raw.updatedAt) or nil
	out.links = Records.CleanLinks(raw.links)
	out.supersededBy = Util.IsPositiveInteger(raw.supersededBy) and raw.supersededBy or nil
	return out
end

--- A new record's common fields. A suggestion is always proposed and private.
function Records.New(story, provenance, now, visibility)
	local id = story.nextId
	story.nextId = id + 1
	local suggested = provenance == "suggested"
	return {
		id = id,
		provenance = provenance,
		status = suggested and "proposed" or "established",
		visibility = suggested and Privacy.PRIVATE or Privacy.Normalize(visibility),
		at = now or 0,
		links = Records.CleanLinks(nil),
	}
end

function Records.Find(list, id)
	for index, record in ipairs(list) do
		if record.id == id then
			return record, index
		end
	end
	return nil
end

--- Moves a record between canon states. Returns record or nil, reason.
-- establish: proposed/disputed -> established; dispute: established -> disputed;
-- supersede: any -> superseded (optionally pointing at its replacement).
function Records.SetStatus(record, status, now, replacementId)
	if not Records.STATUS[status] then
		return nil, "status must be proposed, established, disputed or superseded"
	end
	if status == "proposed" then
		return nil, "a record cannot go back to proposed"
	end
	record.status = status
	record.updatedAt = now or 0
	if status == "superseded" then
		record.supersededBy = replacementId
	end
	if not Records.PUBLIC_STATUS[status] then
		-- Every public side of a record is withdrawn, at once.
		for _, field in ipairs({ "visibility", "convictionVisibility", "feelingsVisibility" }) do
			if record[field] == Privacy.PUBLIC then
				record[field] = Privacy.PRIVATE
			end
		end
	end
	return record
end

--- Changes visibility. Public needs an established record.
function Records.SetVisibility(record, level, now)
	if not Privacy.IsValid(level) then
		return nil, "visibility must be public, private or secret"
	end
	if level == Privacy.PUBLIC and not Records.PUBLIC_STATUS[record.status] then
		return nil, "only an established record can be public; accept it first"
	end
	record.visibility = level
	record.updatedAt = now or 0
	return record
end

--- Whether a record may appear in any public output.
function Records.IsPublic(record)
	return record.visibility == Privacy.PUBLIC and Records.PUBLIC_STATUS[record.status] == true
end

--- Records of a list that pass a filter { status, provenance, visibility, tag }.
function Records.Filter(list, filter)
	filter = filter or {}
	local out = {}
	for _, r in ipairs(list or {}) do
		local ok = (not filter.status or r.status == filter.status)
			and (not filter.provenance or r.provenance == filter.provenance)
			and (not filter.visibility or r.visibility == filter.visibility)
		if ok and filter.tag then
			ok = false
			for _, t in ipairs(r.tags or {}) do
				if t == filter.tag then ok = true end
			end
		end
		if ok then
			out[#out + 1] = r
		end
	end
	return out
end

--- Short labels for display: "suggested, proposed, private".
function Records.Label(record)
	return string.format("%s, %s, %s", record.provenance, record.status, record.visibility)
end

--- List operations shared by every record type ----------------------------------

--- Accepts a suggestion (or settles a dispute) as established canon.
function Records.Accept(list, id, now)
	local r = Records.Find(list, id)
	if not r then return nil, "no record #" .. tostring(id) end
	if r.status == "established" then return nil, "#" .. id .. " is already established" end
	if r.status == "superseded" then return nil, "#" .. id .. " was superseded; accept its replacement instead" end
	return Records.SetStatus(r, "established", now)
end

function Records.Dispute(list, id, now)
	local r = Records.Find(list, id)
	if not r then return nil, "no record #" .. tostring(id) end
	return Records.SetStatus(r, "disputed", now)
end

--- Marks a record as replaced by another (kept for history, never public).
function Records.Supersede(list, id, replacementId, now)
	local r = Records.Find(list, id)
	if not r then return nil, "no record #" .. tostring(id) end
	if replacementId and (replacementId == id or not Records.Find(list, replacementId)) then
		return nil, "the replacement must be another record of the same kind"
	end
	return Records.SetStatus(r, "superseded", now, replacementId)
end

--- Removes a record. Only the player's own records and unaccepted
-- suggestions can be removed; established suggestions are disputed or
-- superseded instead, so history stays honest.
function Records.Remove(list, id)
	local r, index = Records.Find(list, id)
	if not r then return nil, "no record #" .. tostring(id) end
	if r.provenance ~= "player" and r.status ~= "proposed" then
		return nil, "#" .. id .. " is part of the established story; dispute or supersede it instead"
	end
	table.remove(list, index)
	return r
end

function Records.Visibility(list, id, level, now)
	local r = Records.Find(list, id)
	if not r then return nil, "no record #" .. tostring(id) end
	return Records.SetVisibility(r, level, now)
end

--- Appends with a cap: the oldest unpinned records that are not established
-- go first; returns false if nothing may make room.
function Records.Append(list, record, limit)
	if #list >= limit then
		local victim
		for index, r in ipairs(list) do
			if r.status ~= "established" then victim = index; break end
		end
		if not victim then
			return false
		end
		table.remove(list, victim)
	end
	list[#list + 1] = record
	return true
end
