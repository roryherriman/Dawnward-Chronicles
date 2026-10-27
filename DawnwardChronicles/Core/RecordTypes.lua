-- Shapes of the narrative record types stored in `story` (schema v4), and
-- their cleaners. Behaviour lives in Memories, Arcs, Goals and Identity;
-- this file only says what a valid stored record looks like, so loading
-- data never depends on module load order.
local _, ns = ...
local Util, Records = ns.Util, ns.Records

local RecordTypes = {}
ns.RecordTypes = RecordTypes

RecordTypes.LIMITS = { memories = 300, arcs = 40, goals = 60, identity = 60, milestones = 12, turningPoints = 20,
	reviews = 300, people = 200 }

RecordTypes.ARC_KINDS = { goal = true, conflict = true, conviction = true, growth = true, relationship = true,
	other = true }
RecordTypes.ARC_STATES = { active = true, paused = true, concluded = true, abandoned = true }
RecordTypes.GOAL_STATES = { active = true, paused = true, abandoned = true, achieved = true, unresolved = true }
-- Objective progress Dawnward can verify from recorded events.
RecordTypes.OBJECTIVES = { level = true, reputation = true }

local T = Records.Text

local function int(v, lo, hi)
	if type(v) == "number" and v == math.floor(v) and v >= lo and v <= hi then
		return v
	end
	return nil
end

--- A memory: something the character remembers, linked to what happened.
function RecordTypes.CleanMemory(raw)
	local m = Records.CleanCommon(raw, {})
	if not m then return nil end
	m.title = T(raw.title, Records.LIMITS.title)
	m.text = T(raw.text, Records.LIMITS.text, true)
	if not m.title and not m.text then return nil end
	m.tags = Records.Tags(raw.tags)
	m.importance = int(raw.importance, 1, 3) or 1
	m.zone = T(raw.zone, 100)
	return m
end

local function cleanTurningPoint(raw)
	if type(raw) ~= "table" then return nil end
	local note = T(raw.note, 300, true)
	if not note then return nil end
	return { note = note, at = Records.Timestamp(raw.at), memoryId = Util.IsPositiveInteger(raw.memoryId)
		and raw.memoryId or nil }
end

--- An arc: a long-running thread of the character's story.
function RecordTypes.CleanArc(raw)
	local a = Records.CleanCommon(raw, {})
	if not a then return nil end
	a.title = T(raw.title, Records.LIMITS.title)
	if not a.title then return nil end
	a.summary = T(raw.summary, Records.LIMITS.text, true)
	a.kind = RecordTypes.ARC_KINDS[raw.kind] and raw.kind or "other"
	a.state = RecordTypes.ARC_STATES[raw.state] and raw.state or "active"
	a.tags = Records.Tags(raw.tags)
	a.turningPoints = {}
	if type(raw.turningPoints) == "table" then
		for _, tp in ipairs(raw.turningPoints) do
			local clean = cleanTurningPoint(tp)
			if clean and #a.turningPoints < RecordTypes.LIMITS.turningPoints then
				a.turningPoints[#a.turningPoints + 1] = clean
			end
		end
	end
	return a
end

local function cleanMilestone(raw)
	if type(raw) ~= "table" then return nil end
	local text = T(raw.text, 200)
	if not text then return nil end
	return { text = text, done = raw.done == true or nil, doneAt = raw.doneAt ~= nil and Records.Timestamp(raw.doneAt)
		or nil }
end

--- A goal: what the character wants. Objective progress (verified) and the
-- player's own judgement of progress are kept apart.
function RecordTypes.CleanGoal(raw)
	local g = Records.CleanCommon(raw, {})
	if not g then return nil end
	g.title = T(raw.title, Records.LIMITS.title)
	if not g.title then return nil end
	g.text = T(raw.text, Records.LIMITS.text, true)
	g.state = RecordTypes.GOAL_STATES[raw.state] and raw.state or "active"
	g.milestones = {}
	if type(raw.milestones) == "table" then
		for _, m in ipairs(raw.milestones) do
			local clean = cleanMilestone(m)
			if clean and #g.milestones < RecordTypes.LIMITS.milestones then
				g.milestones[#g.milestones + 1] = clean
			end
		end
	end
	local o = raw.objective
	if type(o) == "table" and o.kind == "level" then
		g.objective = { kind = "level", target = int(o.target, 2, 100) }
		if not g.objective.target then g.objective = nil end
	elseif type(o) == "table" and o.kind == "reputation" then
		-- A standing (1-8, Hated to Exalted) with one faction, by its client ID.
		local factionId, target = int(o.factionId, 1, 2 ^ 31), int(o.target, 1, 8)
		if factionId and target then
			g.objective = { kind = "reputation", factionId = factionId, target = target,
				factionName = T(o.factionName, 100) }
		end
	end
	return g
end

--- An identity statement about a subject (a faction, a city, an order, a
-- person, an idea): how the character presents themselves publicly, and
-- what they privately believe. Each side has its own visibility, and
-- they may contradict each other on purpose.
function RecordTypes.CleanIdentity(raw)
	local i = Records.CleanCommon(raw, {})
	if not i then return nil end
	i.subject = T(raw.subject, 100)
	if not i.subject then return nil end
	i.persona = T(raw.persona, 300, true)
	i.conviction = T(raw.conviction, 300, true)
	if not i.persona and not i.conviction then return nil end
	-- The record's own visibility governs the public persona; the private
	-- conviction has its own and defaults to private.
	i.convictionVisibility = ns.Privacy.Normalize(raw.convictionVisibility)
	if i.convictionVisibility == "public" and i.status ~= "established" then
		i.convictionVisibility = "private"
	end
	i.deliberate = raw.deliberate == true or nil
	return i
end

--- A continuity review the player answered (Core/Continuity.lua).
RecordTypes.REVIEW_CHOICES = { growth = true, unreliable = true, secret = true, correction = true, ignore = true }

function RecordTypes.CleanReview(raw)
	if type(raw) ~= "table" or not RecordTypes.REVIEW_CHOICES[raw.choice] then
		return nil
	end
	local key = T(raw.key, 200)
	if not key or key ~= raw.key then return nil end
	return { key = key, choice = raw.choice, at = Records.Timestamp(raw.at), note = T(raw.note, 300, true) }
end

-- People the character knows (#18 NPCs, #28 other players' characters,
-- #37 family and connections). Player-authored only: nothing here is
-- inferred from groups, guilds, reputation or other players' profiles.
-- There is no relationship score; the relation is the player's own words.
RecordTypes.PERSON_KINDS = { npc = true, player = true, family = true, other = true }

function RecordTypes.CleanPerson(raw)
	local p = Records.CleanCommon(raw, {})
	if not p then return nil end
	p.name = T(raw.name, 100)
	if not p.name then return nil end
	p.kind = RecordTypes.PERSON_KINDS[raw.kind] and raw.kind or "other"
	-- Another player's character is identified by name and realm; neither is
	-- ever merged with another record automatically.
	p.realm = p.kind == "player" and T(raw.realm, 100) or nil
	p.relation = T(raw.relation, 300, true)
	p.feelings = T(raw.feelings, 1000, true)
	p.feelingsVisibility = ns.Privacy.Normalize(raw.feelingsVisibility)
	if p.feelingsVisibility == "public" and p.status ~= "established" then
		p.feelingsVisibility = "private"
	end
	return p
end
