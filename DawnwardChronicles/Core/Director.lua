-- The Story Director (#25, with #20): context for a moment, built fresh
-- each time from the character's own approved history. It is deterministic,
-- runs offline, and uses no AI.
--
-- For a reaction it:
--   * ranks established memories, active arcs, active goals and identity
--     statements by relevance to the event (same zone, shared themes),
--     importance and recency;
--   * adds context-aware answers ("it mattered to their goal ...", "it
--     belongs to their story of ...") alongside the universal ones, which
--     never change;
--   * explains why the moment appeared, from verified data only.
--
-- Only established records are used: proposed, disputed and superseded
-- ones have no influence, and a removed record stops mattering at once
-- (nothing is cached). Private context stays private: it shapes questions
-- the player alone sees, and never reaches any public output.
-- There is one prompt system: Reactions calls the Director.
local _, ns = ...
local Records = ns.Records

local Director = {}
ns.Director = Director

Director.MAX_CONTEXT_OPTIONS = 2
Director.RECENT = 30 * 24 * 3600

-- Recency is measured from the event itself, never from the clock, so the
-- answers shown and the answers accepted are always the same list.
local function score(item, record, themes)
	local s = item.importance or 1
	if record and record.zone and item.zone == record.zone then
		s = s + 3
	end
	for _, tag in ipairs(item.tags or {}) do
		if themes[tag] then s = s + 2 end
	end
	if record and record.at and item.at and record.at - item.at < Director.RECENT then
		s = s + 1
	end
	return s
end

local function ranked(list, record, themes)
	local out = {}
	for _, item in ipairs(list) do
		out[#out + 1] = { item = item, score = score(item, record, themes) }
	end
	table.sort(out, function(a, b)
		if a.score ~= b.score then return a.score > b.score end
		return a.item.id > b.item.id
	end)
	return out
end

--- Themes a template's answers touch: { [theme] = true }.
function Director.TemplateThemes(template)
	local themes = {}
	for _, option in ipairs(template and template.options or {}) do
		if option.theme then themes[option.theme] = true end
	end
	return themes
end

--- Context for a record: { memories, arcs, goals, identity } (each ranked,
-- established only) plus why = { reasons from verified data }.
function Director.Context(char, record, template)
	local story = char.story
	local themes = Director.TemplateThemes(template)
	local memories = {}
	for _, m in ipairs(story.memories) do
		if m.status == "established" then memories[#memories + 1] = m end
	end
	local arcs, goals = {}, {}
	for _, a in ipairs(story.arcs) do
		if a.status == "established" and a.state == "active" then arcs[#arcs + 1] = a end
	end
	for _, g in ipairs(story.goals) do
		if g.status == "established" and g.state == "active" then goals[#goals + 1] = g end
	end
	return {
		memories = ranked(memories, record, themes),
		arcs = ranked(arcs, record, themes),
		goals = ranked(goals, record, themes),
		why = Director.Why(char, record),
	}
end

--- Why this moment appeared, in plain words, from verified data only.
function Director.Why(char, record)
	local why = {}
	if not record then
		return why
	end
	if record.category == "quest" then
		local q, l = record.meta and record.meta.questLevel, record.level
		if q and l and q >= l + 2 then
			why[#why + 1] = string.format("the quest was level %d and you were level %d", q, l)
		end
		if record.significance >= 2 and record.zone and #why == 0 then
			why[#why + 1] = "it was among your first quests in " .. record.zone
		end
	elseif record.category == "levelup" and record.level then
		why[#why + 1] = string.format("level %d is a milestone", record.level)
	elseif record.category == "death" then
		why[#why + 1] = record.significance >= 3 and "it was your first recorded fall" or "you fell"
	elseif record.category == "zone" or record.category == "place" then
		local m = record.meta or {}
		local name = m.placeName or record.zone or "this place"
		if m.visit == "start" then
			why[#why + 1] = "a new character, first recorded in a known starting area"
		elseif m.visit == "firstseen" then
			why[#why + 1] = "it is the first place Dawnward recorded for this character"
		elseif m.visit == "return" then
			why[#why + 1] = "you came back to " .. name .. " after some time away"
			if m.meaningful == 1 then
				why[#why + 1] = "you marked it as meaningful"
			elseif m.linked == 1 then
				why[#why + 1] = "one of your memories is tied to it"
			end
		else
			why[#why + 1] = "it was your first recorded visit to " .. name
			if m.placeKind then
				why[#why + 1] = "it is a " .. ns.Places.KIND_LABELS[m.placeKind]
			end
		end
		local seen = {}
		for _, r in ipairs(why) do seen[r] = true end
		for _, r in ipairs(Director.LocationRelevance(char, record).reasons) do
			if not seen[r] then why[#why + 1] = r end
		end
	end
	if #why == 0 then
		why[#why + 1] = "you completed it"
	end
	return why
end

local function plain(s)
	return (s:gsub("[{}]", ""))
end

--- Location relevance --------------------------------------------------------
-- A location becomes a story question by weight, not by rule: a beginning
-- always asks; a place tied to the character's own story (their homeland,
-- a place they marked, one their memories, arcs, goals or people mention)
-- usually asks; an ordinary town only occasionally; other places are only
-- logged. Only established records count, and the reasons name the kind of
-- tie, never a record's private text.

Director.LOCATION_BASE = {
	start = 10, firstseen = 6,
	first = { capital = 3, town = 1, inn = 1, start = 1 },
	zoneFirst = { capital = 3 },
	zoneFirstDefault = 1,
	["return"] = 0,
}
Director.LOCATION_TIES = { homeland = 4, meaningful = 3, memory = 3, arc = 2, goal = 2, person = 2 }
-- Chance of asking by score; at URGENT or more it also skips the location
-- cooldown (the notice itself still waits for a calm moment and its own pacing).
Director.LOCATION_CHANCE = { [1] = 0.2, [2] = 0.4, [3] = 0.6, [4] = 0.8 }
Director.URGENT = 5
Director.FEWER_PENALTY = 2

local function mentions(haystack, needle)
	return type(haystack) == "string" and haystack:lower():find(needle, 1, true) ~= nil
end

local function mentionedIn(list, needle, fields, filter)
	for _, r in ipairs(list) do
		if r.status == "established" and (not filter or filter(r)) then
			for _, k in ipairs(fields) do
				if mentions(r[k], needle) then return true end
			end
		end
	end
	return false
end

--- { score, chance, urgent, reasons = { ... } } for a zone or place record.
-- prefs.places "fewer" lowers the score; "off" is handled by Reactions.
function Director.LocationRelevance(char, record, prefs)
	local m = record.meta or {}
	local story = char.story
	local base = Director.LOCATION_BASE
	local points
	local reasons = {}
	if m.visit == "start" then
		points = base.start
	elseif m.visit == "firstseen" then
		points = base.firstseen
	elseif m.visit == "return" then
		points = base["return"]
	elseif record.category == "zone" then
		points = base.zoneFirst[m.placeKind] or base.zoneFirstDefault
	else
		points = base.first[m.placeKind] or 0
	end

	local name = m.placeName or record.zone
	local key = ns.Places.Key(record.zone or "", record.subzone)
	local entry = story.places[key] or (record.zone and story.places[record.zone])
	local needle = name and #name >= 4 and name:lower() or nil
	local ties = Director.LOCATION_TIES
	local function tie(kind, reason)
		points = points + ties[kind]
		reasons[#reasons + 1] = reason
	end
	local homeland = char.fields and char.fields.homeland and char.fields.homeland.value
	if (entry and ns.Places.IsHomeland(char, entry))
		or (needle and type(homeland) == "string" and homeland:lower() == needle) then
		tie("homeland", "it is your character's homeland")
	end
	if m.meaningful == 1 or (entry and entry.meaningful) then
		tie("meaningful", "you marked it as meaningful")
	end
	if m.linked == 1 or (entry and ns.Places.Linked(story, entry)) then
		tie("memory", "one of your memories is tied to it")
	end
	if needle then
		local function active(r) return r.state == "active" end
		if mentionedIn(story.arcs, needle, { "title", "summary" }, active) then
			tie("arc", "one of your active arcs mentions it")
		end
		if mentionedIn(story.goals, needle, { "title", "text" }, active) then
			tie("goal", "one of your active goals mentions it")
		end
		if mentionedIn(story.people, needle, { "relation", "feelings" }) then
			tie("person", "someone your character knows is connected to it")
		end
	end
	if prefs and prefs.places == "fewer" and m.visit ~= "start" then
		points = points - Director.FEWER_PENALTY
	end
	local chance = points >= Director.URGENT and 1 or Director.LOCATION_CHANCE[points] or 0
	return { score = points, chance = chance, urgent = points >= Director.URGENT, reasons = reasons }
end

--- A number in [0, 1) for this event: fixed per event key, so the same
-- moment is always decided the same way (and tests can replace it).
function Director.Roll(record)
	local h = 5381
	local s = tostring(record.key) .. ":" .. tostring(record.at or 0)
	for i = 1, #s do
		h = (h * 33 + s:byte(i)) % 4294967296
	end
	return (h % 10000) / 10000
end

--- Extra answers drawn from the character's own history, in rank order,
-- at most MAX_CONTEXT_OPTIONS. They carry no personality effect.
function Director.Options(context)
	local out = {}
	local goal = context.goals[1]
	if goal then
		local title = plain(goal.item.title)
		out[#out + 1] = { id = "goal:" .. goal.item.id, text = "It mattered to their goal: " .. title .. ".",
			phrase = "thought of their goal: " .. title, effects = {}, goalId = goal.item.id, contextual = true }
	end
	local arc = context.arcs[1]
	if arc and #out < Director.MAX_CONTEXT_OPTIONS then
		local title = plain(arc.item.title)
		out[#out + 1] = { id = "arc:" .. arc.item.id, text = "It is part of their story: " .. title .. ".",
			phrase = "saw it as part of their story: " .. title, effects = {}, arcId = arc.item.id, contextual = true }
	end
	return out
end

--- A line recalling the most relevant memory, if it is clearly relevant
-- (same place or shared theme).
function Director.Recall(context)
	local top = context.memories[1]
	if top and top.score >= 3 then
		return "Remembering: " .. plain(top.item.title or top.item.text)
	end
	return nil
end

--- After a decision that chose a contextual answer: link it to the goal or
-- arc it named (the player's choice), never marking progress.
function Director.Apply(char, option, decision, now)
	if option.goalId then
		local goal = Records.Find(char.story.goals, option.goalId)
		if goal and #goal.links.decisions < Records.LIMITS.links then
			goal.links.decisions[#goal.links.decisions + 1] = decision.id
			goal.updatedAt = now or 0
		end
	elseif option.arcId then
		local arc = Records.Find(char.story.arcs, option.arcId)
		if arc then
			ns.Arcs.AddTurningPoint(char, arc.id, (decision.phrase or "a moment") .. ".", nil, now)
			if #arc.links.decisions < Records.LIMITS.links then
				arc.links.decisions[#arc.links.decisions + 1] = decision.id
			end
		end
	end
end
