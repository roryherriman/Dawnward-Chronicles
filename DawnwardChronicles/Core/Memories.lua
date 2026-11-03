-- Memories (#12): what the character remembers, each linked to the events
-- and decisions behind it.
--
-- v0.10.3: Dawnward remembers what happened; the player decides what it
-- meant. Three kinds of entry show on the Memories screen:
--   Recorded     verified gameplay events (Core/GameEvents.lua) the game
--                reported: a level, a first death, a standing, a defining
--                quest. Shown from story.events as they are (never copied
--                into memories, so never duplicated), in neutral, factual
--                words; nothing to approve. Routine ones stay in the history.
--   Established  the player's own memories, accepted suggestions, and the
--                faithful record of an answer the player chose in the Story
--                Director (kind "answer"): the answer itself was the
--                approval, so it needs no second confirmation.
--   Suggested    Dawnward's interpretations (kind "reflection", and
--                suggestions made before v0.10.3): proposed and private
--                until the player accepts, edits, postpones or dismisses
--                them. A reflection is offered only for a defining answer,
--                and names the answer it rests on.
-- Nothing becomes a memory just because content was completed, and no
-- emotion is ever assumed from an event.
local _, ns = ...
local Records, RecordTypes = ns.Records, ns.RecordTypes

local Memories = {}
ns.Memories = Memories

-- An answer is kept as a memory when the moment was notable or the player
-- answered in their own words.
Memories.SUGGEST_SIGNIFICANCE = 2
-- A reflection on an answer is suggested only for a defining moment.
Memories.REFLECT_SIGNIFICANCE = 3

local function list(char)
	return char.story.memories
end

--- values: { title, text, tags, importance, zone, links, visibility, kind }.
function Memories.Add(char, values, provenance, now)
	provenance = provenance or "player"
	local m = Records.New(char.story, provenance, now, values.visibility)
	m.title = Records.Text(values.title, Records.LIMITS.title)
	m.text = Records.Text(values.text, Records.LIMITS.text, true)
	if not m.title and not m.text then
		return nil, "a memory needs a title or some text"
	end
	m.tags = Records.Tags(values.tags)
	m.importance = (values.importance == 2 or values.importance == 3) and values.importance or 1
	m.zone = Records.Text(values.zone, 100)
	m.links = Records.CleanLinks(values.links)
	m.kind = values.kind
	local clean = RecordTypes.CleanMemory(m)
	if not Records.Append(list(char), clean, RecordTypes.LIMITS.memories) then
		return nil, "the memory list is full of established memories; supersede or remove some first"
	end
	-- An answer's record is not new development of its own: the decision
	-- itself is offered to the profile suggestions (Core/Decisions.lua).
	if clean.status == "established" and clean.kind ~= "answer" then
		ns.ProfileSuggestions.Generate(char, now, { kind = "memory", memory = clean })
	end
	return clean
end

-- The memory of a kind made for a decision, if any (one per decision and
-- kind, so answering never makes two).
local function forDecision(char, decisionId, kind)
	for _, m in ipairs(list(char)) do
		if m.kind == kind then
			for _, id in ipairs(m.links.decisions) do
				if id == decisionId then return m end
			end
		end
	end
	return nil
end
Memories.ForDecision = forDecision

--- The faithful sentence for an answer: "<name> <the phrase they chose>."
-- (the phrase already in the character's pronouns, Core/Reactions.lua), or
-- the player's own words as written. Nil for "nothing worth remembering".
function Memories.AnswerText(args)
	if args.custom then return args.custom end
	local option = args.option
	if not option or not option.phrase or option.phrase == ns.ReactionLibrary.NEUTRAL.phrase then
		return nil
	end
	return (args.name or "Your character") .. " " .. option.phrase .. "."
end

--- After a decision: keeps the answer as an established memory (the
-- player's own choice, worded faithfully, nothing added), and for a
-- defining moment suggests a reflection on it (Dawnward's interpretation,
-- proposed until the player accepts it). Idempotent per decision.
-- args: { significance, record, title, custom, option, name, eventKeys,
-- decisionId, journalId }. Returns answer, reflection (either may be nil).
function Memories.FromDecision(char, args, now)
	local significance = args.significance or 1
	if significance < Memories.SUGGEST_SIGNIFICANCE and not args.custom then
		return nil
	end
	local text = Memories.AnswerText(args)
	if not text then return nil end
	local record = args.record
	local links = { events = args.eventKeys, decisions = { args.decisionId }, journal = { args.journalId } }
	local tags = args.option and args.option.theme and { args.option.theme } or {}
	local answer = forDecision(char, args.decisionId, "answer")
	if not answer then
		answer = Memories.Add(char, { title = args.title, text = text, tags = tags, importance = significance,
			zone = record and record.zone, links = links, kind = "answer", visibility = ns.Privacy.PRIVATE },
			"player", now)
	end
	local reflection
	local meaning = args.option and args.option.meaning
	if answer and meaning and not args.custom and significance >= Memories.REFLECT_SIGNIFICANCE then
		reflection = forDecision(char, args.decisionId, "reflection")
		if not reflection then
			links.memories = { answer.id }
			reflection = Memories.Add(char, {
				title = args.title and ("Reflecting on " .. args.title) or "A reflection", text = meaning,
				tags = tags, importance = significance, zone = record and record.zone, links = links,
				kind = "reflection",
			}, "suggested", now)
		end
	end
	return answer, reflection
end

function Memories.Find(char, id) return Records.Find(list(char), id) end
function Memories.Accept(char, id, now)
	local m, err = Records.Accept(list(char), id, now)
	if m then m.laterAt = nil end
	-- v0.10.2: an established defining memory may suggest a profile change.
	if m then ns.ProfileSuggestions.Generate(char, now, { kind = "memory", memory = m }) end
	return m, err
end
function Memories.Dispute(char, id, now) return Records.Dispute(list(char), id, now) end
function Memories.Supersede(char, id, by, now) return Records.Supersede(list(char), id, by, now) end
function Memories.Remove(char, id) return Records.Remove(list(char), id) end
function Memories.SetVisibility(char, id, level, now) return Records.Visibility(list(char), id, level, now) end

--- The player rewrites a memory in their own words: it becomes player-authored.
function Memories.Edit(char, id, values, now)
	local m = Memories.Find(char, id)
	if not m then return nil, "no memory #" .. tostring(id) end
	local title = values.title ~= nil and Records.Text(values.title, Records.LIMITS.title) or m.title
	local text = values.text ~= nil and Records.Text(values.text, Records.LIMITS.text, true) or m.text
	if not title and not text then return nil, "a memory needs a title or some text" end
	m.title, m.text = title, text
	if values.tags then m.tags = Records.Tags(values.tags) end
	m.provenance = "player"
	-- Rewritten by the player: no longer Dawnward's record of an answer.
	if m.kind == "answer" then m.kind = nil end
	m.updatedAt = now or 0
	return m
end

--- Later: a suggestion waits at the end of the list, still a suggestion.
function Memories.Later(char, id, now)
	local m = Memories.Find(char, id)
	if not m then return nil, "no memory #" .. tostring(id) end
	if m.status ~= "proposed" then return nil, "only a suggestion can wait for later" end
	m.laterAt = now or 0
	return m
end

--- Dismiss: a suggestion the player does not want is removed. Established
-- memories are never dismissed (dispute or supersede them instead).
function Memories.Dismiss(char, id)
	local m = Memories.Find(char, id)
	if not m then return nil, "no memory #" .. tostring(id) end
	if m.status ~= "proposed" then return nil, "#" .. id .. " is not a suggestion" end
	return Records.Remove(list(char), id)
end

--- Suggestions waiting for the player: newest first, those put off with
-- Later after the others.
function Memories.Suggestions(char)
	local out = Records.Filter(list(char), { status = "proposed" })
	table.sort(out, function(a, b)
		if (a.laterAt ~= nil) ~= (b.laterAt ~= nil) then return a.laterAt == nil end
		if a.at ~= b.at then return a.at > b.at end
		return a.id > b.id
	end)
	return out
end

--- Established memories, most important and newest first.
function Memories.Established(char)
	local out = Records.Filter(list(char), { status = "established" })
	table.sort(out, function(a, b)
		if a.importance ~= b.importance then return a.importance > b.importance end
		if a.at ~= b.at then return a.at > b.at end
		return a.id > b.id
	end)
	return out
end

--- Recorded gameplay events -------------------------------------------------------
-- The lowest significance (Core/GameEvents.lua) at which a verified event
-- shows on the Memories screen; everything else stays in the history
-- (Journal, Story). Routine quests, places and returns never show here.
Memories.RECORDED_MIN = { levelup = 2, death = 3, reputation = 2, zone = 2, place = 3, instance = 2, guild = 2,
	quest = 3 }

--- Whether a verified event is shown as Recorded on the Memories screen. Pure.
function Memories.IsRecorded(e)
	local min = type(e) == "table" and Memories.RECORDED_MIN[e.category]
	if not min or e.confidence == "player" then return false end
	if e.meta and e.meta.visit == "return" then return false end
	return (e.significance or 1) >= min
end

local function plain(s)
	return s and (s:gsub("[{}]", "")) or nil
end

--- A neutral, factual sentence for a verified event: only what the game
-- reported (a place only when it was recorded), no feeling, no outcome.
function Memories.RecordedText(char, e)
	local name = ns.Pronouns.Name(char)
	local m = e.meta or {}
	local zone = e.zone and (" in " .. e.zone) or ""
	local c = e.category
	if c == "levelup" then
		return string.format("%s reached level %d%s.", name, e.level or 0, zone)
	elseif c == "quest" then
		local title = plain(m.title)
		return title and string.format("%s completed \"%s\"%s.", name, title, zone)
			or string.format("%s completed a quest%s.", name, zone)
	elseif c == "death" then
		return string.format("%s fell%s, and came back.", name, zone)
	elseif c == "reputation" then
		return string.format("%s reached %s standing with %s.", name, ns.GameEvents.STANDINGS[m.standing] or "a new",
			plain(m.factionName) or "a faction")
	elseif c == "zone" or c == "place" then
		local where = (c == "place" and m.placeName) or e.zone or "a new place"
		if c == "place" and e.zone and e.zone ~= where then where = where .. ", " .. e.zone end
		if m.visit == "start" then
			return string.format("%s's journey began in %s.", name, where)
		elseif m.visit == "firstseen" then
			return string.format("Dawnward first recorded %s in %s.", name, where)
		end
		return string.format("%s reached %s (the first visit Dawnward recorded).", name, where)
	elseif c == "instance" then
		return string.format("%s entered %s (the first entry Dawnward recorded).", name,
			plain(m.instanceName) or "an instance")
	elseif c == "guild" then
		return string.format("%s %s %s.", name, m.title == "left" and "left" or "joined", plain(m.guildName) or "a guild")
	end
	return name .. ": " .. ns.GameEvents.Label(c) .. "."
end

--- The title of a Recorded entry ("Level 5", a quest's title). Pure.
function Memories.RecordedTitle(e)
	return ns.Narrative.Title(e)
end

-- Event keys a memory (not superseded) already tells the story of.
local function linkedEvents(char)
	local keys = {}
	for _, m in ipairs(list(char)) do
		if m.status ~= "superseded" then
			for _, k in ipairs(m.links.events) do keys[k] = true end
		end
	end
	return keys
end

--- Verified events shown as Recorded, newest first. An event a memory
-- already tells is shown with that memory instead (one entry, linked).
function Memories.Recorded(char)
	local out, linked = {}, linkedEvents(char)
	local events = char.story and char.story.events or {}
	for i = #events, 1, -1 do
		local e = events[i]
		if Memories.IsRecorded(e) and not linked[e.key] then out[#out + 1] = e end
	end
	return out
end

--- What a memory rests on, for its card: the answer a reflection
-- interprets, else the recorded event it is linked to. Nil when none.
function Memories.Basis(char, m)
	if m.kind == "reflection" then
		local answer = m.links.memories[1] and Memories.Find(char, m.links.memories[1])
		if answer and answer.text then return "From your answer: " .. answer.text end
	end
	local key = m.links.events[1]
	local e = key and ns.GameEvents.Find(char, key)
	if e then return "Recorded: " .. Memories.RecordedText(char, e) end
	return nil
end
