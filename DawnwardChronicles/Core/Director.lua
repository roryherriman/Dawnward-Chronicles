-- The Story Director (#25, with #20): context for a moment, built fresh
-- each time from the character's own approved history. It is deterministic,
-- runs offline, and uses no AI.
--
-- For a reaction it:
--   * ranks established memories, active arcs and active goals by relevance
--     to the event (same zone, shared themes, a record naming the event's
--     place or faction, a goal whose objective is this faction's standing),
--     importance and recency;
--   * finds the established stances whose subject the event names;
--   * adds at most two context-aware answers (a goal, an arc or such a
--     stance, best ranked first) alongside the universal ones, which never
--     change; their wording is authored here, only titles and subjects are
--     the player's;
--   * explains why the moment appeared, from verified data and the kinds of
--     ties to the character's story (homeland, marked places, memories,
--     people, a standing that rose or fell, goals and stances about it);
--   * recalls the player's own earlier answer about the same situation
--     (Echo: the authored phrase of the answer they chose);
--   * helps Reactions choose between authored templates that are equally due
--     (Affinity: themes of established memories and recent answers, strong
--     personality leans, people), and names the situation a question is
--     about (Subject) for repetition control.
-- It never writes a fact, a character, a quest, a place or an outcome: every
-- word shown is authored text, verified game data or the player's own.
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

--- Whether a goal's verified objective concerns this event (#18, #27):
-- a level goal and a level-up, or a reputation goal and a standing change
-- with the same faction ID. The event only shows progress; the goal stays
-- the player's to resolve.
function Director.ObjectiveConcerns(goal, record)
	local o = goal and goal.objective
	if not o or not record then
		return false
	end
	if o.kind == "level" then
		return record.category == "levelup"
	end
	if o.kind == "reputation" then
		return record.category == "reputation" and record.meta ~= nil and record.meta.factionId == o.factionId
	end
	return false
end

local function plain(s)
	return (s:gsub("[{}]", ""))
end

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

-- Names an event is about, lower case, for matching the player's own words:
-- a standing change is about its faction, an instance or guild event about
-- that instance or guild, anything else about where it happened (zone,
-- named place). Only names of four letters or more, so "Inn" never matches
-- "beginning".
local function eventNames(record)
	local out = {}
	if not record then return out end
	local m = record.meta or {}
	local values
	if record.category == "reputation" then
		values = { m.factionName }
	elseif record.category == "instance" then
		values = { m.instanceName }
	elseif record.category == "guild" then
		values = { m.guildName }
	else
		values = { record.zone, record.subzone, m.placeName }
	end
	for i = 1, 3 do
		local v = values[i]
		if type(v) == "string" and #v >= 4 then out[#out + 1] = v:lower() end
	end
	return out
end

local function namedIn(text, names)
	if type(text) ~= "string" then return false end
	local lower = text:lower()
	for _, name in ipairs(names) do
		if lower:find(name, 1, true) then return true end
	end
	return false
end

-- Recency is measured from the event itself, never from the clock, so the
-- answers shown and the answers accepted are always the same list.
-- Beyond place, theme and recency, a record that names the event (its zone,
-- place or faction) ranks higher, and a goal whose verified objective is a
-- standing with this very faction ranks highest.
local function score(item, record, themes, names)
	local s = item.importance or 1
	-- A goal whose verified objective this event concerns comes first, so
	-- its answer is the one offered (Director.Options).
	if Director.ObjectiveConcerns(item, record) then
		s = s + 5
	end
	if record and record.zone and item.zone == record.zone then
		s = s + 3
	end
	for _, tag in ipairs(item.tags or {}) do
		if themes[tag] then s = s + 2 end
	end
	if record and record.at and item.at and record.at - item.at < Director.RECENT then
		s = s + 1
	end
	if names and (namedIn(item.title, names) or namedIn(item.summary, names) or namedIn(item.text, names)) then
		s = s + 3
	end
	local o = item.objective
	if record and record.category == "reputation" and o and o.kind == "reputation" and record.meta
		and o.factionId == record.meta.factionId then
		s = s + 5
	end
	return s
end

local function ranked(list, record, themes)
	local out = {}
	local names = eventNames(record)
	for _, item in ipairs(list) do
		out[#out + 1] = { item = item, score = score(item, record, themes, names) }
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

--- The established stances (Core/Identity.lua) whose subject the event
-- names directly: the faction of a standing change, the zone or place, the
-- instance or guild. Newest first. A stance about something else is not
-- relevant to this moment and is never brought up.
function Director.Stances(char, record)
	local out = {}
	local names = eventNames(record)
	if #names == 0 then return out end
	local list = char.story.identity
	for i = #list, 1, -1 do
		local stance = list[i]
		local subject = stance.status == "established" and stance.subject and stance.subject:lower()
		if subject and #subject >= 4 then
			for _, name in ipairs(names) do
				if name == subject or name:find(subject, 1, true) or subject:find(name, 1, true) then
					out[#out + 1] = stance
					break
				end
			end
		end
	end
	return out
end

--- Context for a record: { memories, arcs, goals, stances } (each ranked,
-- established only) plus why = { reasons from verified data } and echo
-- (the player's own earlier answer to this question about this situation).
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
		stances = Director.Stances(char, record),
		why = Director.Why(char, record),
		echo = Director.Echo(char, record, template),
	}
end

Director.MAX_WHY = 4

local TIE_REASONS = {
	homeland = "it happened in your character's homeland",
	meaningful = "it happened in a place you marked as meaningful",
	memory = "one of your memories is tied to where it happened",
}

-- Reasons from the character's own established story, for any event: the
-- place it happened (homeland, marked, remembered), a standing change and
-- the goals and stances about that faction, and the people tied to the
-- place. Kinds of ties only, never a record's own words; the names used
-- (zone, faction, standings) are what the game reported.
local function contextReasons(char, record, why)
	local function add(reason)
		if #why >= Director.MAX_WHY then return end
		for _, r in ipairs(why) do
			if r == reason then return end
		end
		why[#why + 1] = reason
	end
	local m = record.meta or {}
	local location = record.category == "zone" or record.category == "place"
	if record.category == "reputation" and m.standing then
		local S = ns.GameEvents.STANDINGS
		local faction = m.factionName and plain(m.factionName) or "this faction"
		-- Skip what Director.Why already said more specifically (the observed
		-- standing line, GoalReasons, StanceReasons), so no reason repeats.
		local function said(fragment)
			for _, r in ipairs(why) do
				if r:find(fragment, 1, true) then return true end
			end
			return false
		end
		if m.previous and S[m.previous] and m.previous ~= m.standing then
			add(string.format("your standing with %s %s from %s", faction, m.standing > m.previous and "rose" or "fell",
				S[m.previous]))
		end
		if not said("your goal") then
			for _, g in ipairs(char.story.goals) do
				local o = g.objective
				if g.status == "established" and g.state == "active" and o and o.kind == "reputation"
					and o.factionId == m.factionId then
					add("one of your active goals aims for a standing with " .. faction)
					break
				end
			end
		end
		if not said("own stance toward") and #Director.Stances(char, record) > 0 then
			add("you have a stance about " .. faction)
		end
		return
	end
	if not location and record.zone then
		local entry = ns.Places.Entry(char, record.zone, record.subzone) or ns.Places.Entry(char, record.zone)
		local tie = entry and ns.Places.Tie(char, entry)
		if not tie then
			local homeland = char.fields and char.fields.homeland and char.fields.homeland.value
			if type(homeland) == "string" and homeland:lower() == record.zone:lower() then tie = "homeland" end
		end
		if tie then add(TIE_REASONS[tie]) end
		local needle = #record.zone >= 4 and record.zone:lower() or nil
		if needle and mentionedIn(char.story.people, needle, { "relation", "feelings" }) then
			add("someone your character knows is connected to where it happened")
		end
	end
	if #Director.Stances(char, record) > 0 then
		add("you have a stance about " .. (location and "this place" or "where it happened"))
	end
end

--- Why this moment appeared, in plain words, from verified data and the
-- kinds of ties to the character's own established story.
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
		Director.GoalReasons(char, record, why)
	elseif record.category == "reputation" then
		local m, S = record.meta or {}, ns.GameEvents.STANDINGS
		if m.factionName and S[m.standing or 0] then
			why[#why + 1] = string.format("the game shows your standing with %s as %s%s", m.factionName, S[m.standing],
				S[m.previous or 0] and (" (it was " .. S[m.previous] .. ")") or "")
		end
		Director.GoalReasons(char, record, why)
		Director.StanceReasons(char, record, why)
	elseif record.category == "death" then
		why[#why + 1] = record.significance >= 3 and "it was your first recorded fall" or "you fell"
	elseif record.category == "reputation" then
		local m = record.meta or {}
		if not m.previous then
			why[#why + 1] = "Dawnward saw your standing with " .. (m.factionName and plain(m.factionName)
				or "a faction") .. " change"
		end
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
	contextReasons(char, record, why)
	if #why == 0 then
		why[#why + 1] = "you completed it"
	end
	return why
end

--- Reasons from the player's active goals with a verified objective this
-- event concerns: progress from observed data only. A goal is never
-- completed or changed here; a met target only says so.
function Director.GoalReasons(char, record, why)
	for _, g in ipairs(char.story.goals or {}) do
		if g.status == "established" and g.state == "active" and Director.ObjectiveConcerns(g, record) then
			local o = g.objective
			local current = record.category == "levelup" and record.level or (record.meta and record.meta.standing)
			local title = plain(g.title or "a goal")
			if current and current >= o.target then
				why[#why + 1] = string.format("it reaches the target of your goal \"%s\" (only you decide whether it "
					.. "is achieved)", title)
			elseif current then
				why[#why + 1] = string.format("it is progress toward your goal \"%s\"", title)
			end
		end
	end
end

--- For a standing change: whether the player recorded a stance of their
-- own toward that faction (Core/Identity, matched by the observed name).
-- Only that a stance exists is said, never what it is: the standing is
-- what the faction thinks, the stance what the character does.
function Director.StanceReasons(char, record, why)
	local name = record.meta and record.meta.factionName
	if type(name) ~= "string" then
		return
	end
	name = name:lower()
	for _, i in ipairs(char.story.identity or {}) do
		if i.status == "established" and type(i.subject) == "string" and i.subject:lower() == name then
			why[#why + 1] = "you have written your character's own stance toward " .. record.meta.factionName
			return
		end
	end
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

--- Extra answers drawn from the character's own history, at most
-- MAX_CONTEXT_OPTIONS, best ranked first: the top active goal, the top
-- active arc, and a stance whose subject this very event names. The answer
-- text is authored here; only the record's title or subject is the
-- player's. A stance answer never shows the private conviction: when the
-- public face and the private belief differ, the authored wording only
-- says the moment tested the gap. They carry no personality effect.
Director.STANCE_BONUS = 5

function Director.Options(context)
	local candidates = {}
	local goal = context.goals[1]
	if goal then
		local title = plain(goal.item.title)
		candidates[#candidates + 1] = { score = goal.score, order = 1, option = { id = "goal:" .. goal.item.id,
			text = "It mattered to their goal: " .. title .. ".", phrase = "thought of their goal: " .. title,
			effects = {}, goalId = goal.item.id, contextual = true } }
	end
	local arc = context.arcs[1]
	if arc then
		local title = plain(arc.item.title)
		candidates[#candidates + 1] = { score = arc.score, order = 2, option = { id = "arc:" .. arc.item.id,
			text = "It is part of their story: " .. title .. ".", phrase = "saw it as part of their story: " .. title,
			effects = {}, arcId = arc.item.id, contextual = true } }
	end
	local stance = context.stances and context.stances[1]
	if stance then
		local subject = plain(stance.subject)
		local option
		if ns.Identity.Contradicts(stance) then
			option = { text = "It tested the gap between what they say about " .. subject .. " and what they believe.",
				phrase = "felt the gap between what they say about " .. subject .. " and what they believe" }
		else
			option = { text = "It touched on where they stand on " .. subject .. ".",
				phrase = "thought about where they stand on " .. subject }
		end
		option.id, option.effects, option.stanceId, option.contextual = "stance:" .. stance.id, {}, stance.id, true
		candidates[#candidates + 1] = { score = 1 + Director.STANCE_BONUS, order = 3, option = option }
	end
	table.sort(candidates, function(a, b)
		if a.score ~= b.score then return a.score > b.score end
		return a.order < b.order
	end)
	local chosen = {}
	for i = 1, math.min(#candidates, Director.MAX_CONTEXT_OPTIONS) do chosen[i] = candidates[i] end
	-- Shown in a fixed order (goal, arc, stance), so the list reads the same way every time.
	table.sort(chosen, function(a, b) return a.order < b.order end)
	local out = {}
	for i, c in ipairs(chosen) do out[i] = c.option end
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
	elseif option.stanceId then
		-- Linked only: the stance's words are never changed by an answer.
		local stance = Records.Find(char.story.identity, option.stanceId)
		if stance and #stance.links.decisions < Records.LIMITS.links then
			stance.links.decisions[#stance.links.decisions + 1] = decision.id
		end
	end
end

--- Subjects and repetition (#20) ---------------------------------------------
-- The situation a question is about, so the same question is not asked
-- twice about the same thing within the repeat window (Core/Reactions.lua).
-- Returns key, label or nil (a level or a roleplay moment is never the same
-- situation twice). Quest chains are not reported by the Classic Era
-- client, so quests are grouped by the zone they were turned in.
function Director.Subject(record)
	if not record then return nil end
	local m = record.meta or {}
	local c = record.category
	if c == "reputation" and m.factionId then
		return "faction:" .. m.factionId, m.factionName and plain(m.factionName) or "a faction"
	elseif (c == "zone" or c == "place") and record.zone then
		local subzone = c == "place" and record.subzone or nil
		local key = ns.Places.Key(record.zone, subzone)
		return "place:" .. key, ns.Places.Label({ zone = record.zone, subzone = subzone })
	elseif c == "quest" and record.zone then
		return "quests:" .. record.zone, "quests in " .. record.zone
	elseif c == "death" and record.zone then
		return "death:" .. record.zone, "falling in " .. record.zone
	elseif c == "instance" and m.instanceName then
		return "instance:" .. m.instanceName, m.instanceName
	elseif c == "guild" and m.guildName then
		return "guild:" .. m.guildName, m.guildName
	end
	return nil
end

--- The player's own earlier answer to a question about the same situation:
-- "<name> <the phrase of the answer they chose>", from the newest decision
-- with the same subject (the same template first). Answers in the player's
-- own words are theirs to reread in the journal and are not quoted here.
-- Returns text, sameTemplate or nil.
function Director.Echo(char, record, template)
	local subject = Director.Subject(record)
	if not subject then return nil end
	local decisions = char.story.decisions
	local best, sameTemplate
	-- One pass over the events (bounded), not one per decision.
	local byKey = {}
	for _, e in ipairs(char.story.events) do byKey[e.key] = e end
	for i = #decisions, math.max(1, #decisions - 50), -1 do
		local d = decisions[i]
		if d.phrase and d.eventKeys and d.eventKeys[1] ~= record.key then
			local e = byKey[d.eventKeys[1]]
			if e and Director.Subject(e) == subject then
				if template ~= nil and d.templateId == template.id then
					best, sameTemplate = d, true
					break
				elseif not best then
					best = d
				end
			end
		end
	end
	if not best then return nil end
	local name = char.fields and char.fields.name and char.fields.name.value or "They"
	return plain(name .. " " .. best.phrase), sameTemplate == true
end

--- How well a template's answers fit this character's established story,
-- used only to choose between authored templates that are equally due:
-- +2 for each theme the character's established memories or recent answers
-- share, +1 for each personality axis it explores that the player's
-- approved development has moved (applied changes, the last
-- AFFINITY_CHANGES of them), +1 when it is about other people and the
-- character has people in their story. A personality value on its own (as
-- set at creation) never changes the question: two characters with the
-- same story are asked the same thing, whatever their class, race, faction
-- or starting values. Pure.
Director.AFFINITY_CHANGES = 10

function Director.Affinity(char, template)
	local story = char.story
	local known = {}
	for _, m in ipairs(story.memories) do
		if m.status == "established" then
			for _, tag in ipairs(m.tags or {}) do known[tag] = true end
		end
	end
	local decisions = story.decisions
	for i = #decisions, math.max(1, #decisions - 9), -1 do
		if decisions[i].theme then known[decisions[i].theme] = true end
	end
	local strong = {}
	local changes, seen = story.changes or {}, 0
	for i = #changes, 1, -1 do
		local c = changes[i]
		if c.status == "applied" and not c.manual then
			strong[c.axis] = true
			seen = seen + 1
			if seen >= Director.AFFINITY_CHANGES then break end
		end
	end
	local people = false
	for _, p in ipairs(story.people or {}) do
		if p.status == "established" then people = true; break end
	end
	local fit, seenTheme, seenAxis, peopleCounted = 0, {}, {}, false
	for _, option in ipairs(template.options or {}) do
		local theme = option.theme
		if theme and known[theme] and not seenTheme[theme] then
			seenTheme[theme] = true
			fit = fit + 2
		end
		for axis in pairs(option.effects or {}) do
			if strong[axis] and not seenAxis[axis] then
				seenAxis[axis] = true
				fit = fit + 1
			end
		end
		if people and not peopleCounted and (theme == "companionship" or theme == "loss") then
			peopleCounted = true
			fit = fit + 1
		end
	end
	return fit
end
