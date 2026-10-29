-- The reaction queue: turns some gameplay events into roleplay
-- opportunities, paced so they stay rare and welcome.
--
-- An event becomes a reaction only if all of these hold:
--   * prompts are not switched off (prefs.frequency ~= "off")
--   * its significance reaches the player's threshold
--   * the category is not cooling down (major events skip the cooldown)
--   * the queue has room (the least significant, oldest reaction gives way
--     only to a more significant one)
-- Quests in the same zone while a quest reaction is still waiting are
-- folded into it, so a session of questing asks one question, not ten.
--
-- Location moments (zone and place events) are weighted by how much the
-- place matters to this character (Director.LocationRelevance: homeland,
-- marked places, memories, arcs, goals and people weigh most; an ordinary
-- town asks only now and then), share one cooldown that strongly tied
-- places may skip, can be reduced or switched off (prefs.places), and fold
-- together: a location
-- event in the same zone within LOCATION_WINDOW of a waiting, unannounced
-- location moment either replaces it (if it is more significant: entering
-- Goldshire right after Elwynn Forest asks about Goldshire) or is kept as a
-- record only. A quest turned in there soon after takes precedence over a
-- plain arrival, so the question is about the task, not the town.
--
-- Reactions wait until the player answers, postpones or dismisses them, or
-- until they expire. Asking happens elsewhere (Platform/SafeTime decides
-- when); this module never interrupts anything.
local _, ns = ...
local StorySchema, ReactionLibrary, GameEvents = ns.StorySchema, ns.ReactionLibrary, ns.GameEvents

local Reactions = {}
ns.Reactions = Reactions

-- Seconds between reactions of one category, and between two notices.
-- Story pacing runs on the narrative clock (seconds of play, never offline
-- time; Core/NarrativeClock.lua): cooldowns in seconds of play, expiry in
-- narrative days. Notice spacing and the short location window below stay
-- in real time: they are about not interrupting a play session.
Reactions.COOLDOWN = { rare = 7200, normal = 2700, frequent = 900 }
Reactions.EXPIRY_DAYS = 7
Reactions.FREQUENCIES = { "off", "rare", "normal", "frequent" }
Reactions.LOCATION = { zone = true, place = true }
Reactions.LOCATION_WINDOW = 120

local function newId(story)
	local id = story.nextId
	story.nextId = id + 1
	return id
end

function Reactions.Find(char, id)
	for index, r in ipairs(char.story.reactions) do
		if r.id == id then
			return r, index
		end
	end
	return nil
end

local function setEventStatus(char, keys, status)
	for _, k in ipairs(keys) do
		local record = GameEvents.Find(char, k)
		if record then
			record.status = status
		end
	end
end

local function remember(pacing, templateId)
	local recent = pacing.recentTemplates
	table.insert(recent, 1, templateId)
	while #recent > StorySchema.LIMITS.recentTemplates do
		table.remove(recent)
	end
end

local function recentlyUsed(pacing, templateId)
	for _, t in ipairs(pacing.recentTemplates) do
		if t == templateId then
			return true
		end
	end
	return false
end

--- Picks a template deterministically. A template written for this exact
-- situation (one with a `when` condition) comes first; otherwise the general
-- templates take turns, skipping the recently used ones.
function Reactions.ChooseTemplate(char, record)
	local candidates = ReactionLibrary.For(record.category, record.significance, record)
	for _, template in ipairs(candidates) do
		if template.when and not recentlyUsed(char.story.pacing, template.id) then
			return template
		end
	end
	for _, template in ipairs(candidates) do
		if not template.when and not recentlyUsed(char.story.pacing, template.id) then
			return template
		end
	end
	-- Everything was used recently: the least recently used one.
	local recent = char.story.pacing.recentTemplates
	for i = #recent, 1, -1 do
		for _, template in ipairs(candidates) do
			if template.id == recent[i] then
				return template
			end
		end
	end
	return candidates[1]
end

--- Removes reactions waiting longer than EXPIRY_DAYS of play; their events
-- stay recorded. play is the narrative clock (default: the saved total); the
-- second argument (the real date) is kept for callers but not used.
-- Each reaction carries its own deadline (expiresPlay), set when it is
-- created at the pace in force then, so changing the story pace later never
-- removes a moment that is already waiting. A reaction from before the clock
-- existed, or with a reading ahead of the clock (an older backup restored),
-- starts its wait now.
function Reactions.Expire(char, _, play)
	play = play or ns.NarrativeClock.Peek(char)
	local expiry = Reactions.EXPIRY_DAYS * ns.NarrativeClock.DayLength(char)
	local list = char.story.reactions
	local i = 1
	while i <= #list do
		local r = list[i]
		if not r.createdPlay or r.createdPlay > play then
			r.createdPlay, r.expiresPlay = play, play + expiry
			i = i + 1
		else
			if not r.expiresPlay or r.expiresPlay < r.createdPlay then
				r.expiresPlay = r.createdPlay + expiry
			end
			if play > r.expiresPlay then
				setEventStatus(char, r.eventKeys, "recorded")
				table.remove(list, i)
			else
				i = i + 1
			end
		end
	end
end

local function coalesceTarget(char, record)
	if record.category ~= "quest" then
		return nil
	end
	for _, r in ipairs(char.story.reactions) do
		if r.category == "quest" and r.status == "pending" and r.zone == record.zone and #r.eventKeys < 20 then
			return r
		end
	end
	return nil
end

-- A waiting, unannounced location moment in the same zone, from moments ago.
local function recentLocation(char, record, now)
	for index, r in ipairs(char.story.reactions) do
		if Reactions.LOCATION[r.category] and r.status == "pending" and r.notifiedAt == nil and r.zone == record.zone
			and (now or 0) - r.createdAt <= Reactions.LOCATION_WINDOW then
			return r, index
		end
	end
	return nil
end

local function lastLocation(pacing)
	local a, b = pacing.playByCategory.zone, pacing.playByCategory.place
	if a and b then return math.max(a, b) end
	return a or b
end

-- A quest just queued in a zone replaces a plain arrival moment queued
-- moments before (a beginning stays: it is major and happens once).
local function questOverArrival(char, record, now)
	local r, index = recentLocation(char, record, now)
	if r and r.significance < 3 then
		setEventStatus(char, r.eventKeys, "recorded")
		table.remove(char.story.reactions, index)
	end
end

-- Frees a queue slot for a reaction of this significance. Returns ok.
local function makeRoom(char, significance)
	local list = char.story.reactions
	if #list < StorySchema.LIMITS.reactions then
		return true
	end
	local victim
	for index, r in ipairs(list) do
		if r.significance < significance and (not victim or r.significance < list[victim].significance) then
			victim = index
		end
	end
	if not victim then
		return false
	end
	setEventStatus(char, list[victim].eventKeys, "recorded")
	table.remove(list, victim)
	return true
end

--- Considers a freshly recorded event. Returns reaction, outcome where
-- outcome is "queued", "coalesced", or why it stays a plain record
-- ("prompts off", "below threshold", "cooldown", "queue full", "no template").
-- now is the real date; play is the narrative clock (default: the saved total).
function Reactions.Consider(char, record, now, play)
	local story = char.story
	local prefs, pacing = story.prefs, story.pacing
	play = play or ns.NarrativeClock.Peek(char)
	Reactions.Expire(char, now, play)
	local function stay(why)
		record.status = "recorded"
		return nil, why
	end
	if prefs.frequency == "off" then
		return stay("prompts off")
	end
	local location = Reactions.LOCATION[record.category]
	if location and prefs.places == "off" then
		return stay("place moments off")
	end
	if record.significance < prefs.threshold then
		return stay("below threshold")
	end
	-- Locations ask by weight (Director.LocationRelevance), not by rule.
	local urgent = false
	if location then
		local relevance = ns.Director.LocationRelevance(char, record, prefs)
		if relevance.chance <= 0 then
			return stay("logged quietly")
		end
		if ns.Director.Roll(record) >= relevance.chance then
			return stay("not this time")
		end
		urgent = relevance.urgent
	end
	local target = coalesceTarget(char, record)
	if target then
		target.eventKeys[#target.eventKeys + 1] = record.key
		target.significance = math.max(target.significance, record.significance)
		record.status = "queued"
		return target, "coalesced"
	end
	if location then
		local waiting = recentLocation(char, record, now)
		if waiting then
			if record.significance <= waiting.significance then
				return stay("folded into a waiting moment")
			end
			-- The more meaningful place takes the moment's place.
			local template = Reactions.ChooseTemplate(char, record)
			if template then
				setEventStatus(char, waiting.eventKeys, "recorded")
				waiting.category, waiting.eventKeys, waiting.templateId = record.category, { record.key }, template.id
				waiting.significance = record.significance
				remember(pacing, template.id)
				record.status = "queued"
				return waiting, "replaced"
			end
		end
	end
	local last = location and lastLocation(pacing) or pacing.playByCategory[record.category]
	local cooldown = Reactions.COOLDOWN[prefs.frequency]
	if last and record.significance < 3 and not urgent and last <= play and play - last < cooldown then
		return stay("cooldown")
	end
	if not makeRoom(char, record.significance) then
		return stay("queue full")
	end
	local template = Reactions.ChooseTemplate(char, record)
	if not template then
		return stay("no template")
	end
	local reaction = {
		id = newId(story), category = record.category, eventKeys = { record.key }, templateId = template.id,
		significance = record.significance, status = "pending", createdAt = now or 0, createdPlay = play,
		expiresPlay = play and (play + Reactions.EXPIRY_DAYS * ns.NarrativeClock.DayLength(char)) or nil,
		zone = record.zone,
	}
	if record.category == "quest" then
		questOverArrival(char, record, now)
	end
	story.reactions[#story.reactions + 1] = reaction
	if location then
		pacing.lastByCategory.zone, pacing.lastByCategory.place = now or 0, now or 0
		pacing.playByCategory.zone, pacing.playByCategory.place = play, play
	else
		pacing.lastByCategory[record.category] = now or 0
		pacing.playByCategory[record.category] = play
	end
	remember(pacing, template.id)
	record.status = "queued"
	return reaction, "queued"
end

--- Waiting reactions: pending before postponed, then most significant, then oldest.
function Reactions.List(char, now, play)
	Reactions.Expire(char, now, play)
	local out = {}
	for _, r in ipairs(char.story.reactions) do
		out[#out + 1] = r
	end
	table.sort(out, function(a, b)
		if a.status ~= b.status then return a.status == "pending" end
		if a.significance ~= b.significance then return a.significance > b.significance end
		if a.createdAt ~= b.createdAt then return a.createdAt < b.createdAt end
		return a.id < b.id
	end)
	return out
end

local function characterName(char)
	local name = char.fields and char.fields.name and char.fields.name.value
	return name or "Your character"
end

-- Possessive and object pronouns from the profile's Pronouns field, only
-- when it clearly starts with she, he or they; anything else is neutral.
local PRONOUNS = {
	she = { their = "her", them = "her" },
	he = { their = "his", them = "him" },
	they = { their = "their", them = "them" },
}

function Reactions.Pronouns(char)
	local field = char.fields and char.fields.pronouns and char.fields.pronouns.value
	local first = type(field) == "string" and field:lower():match("^%s*(%a+)") or nil
	return PRONOUNS[first] or PRONOUNS.they
end

local function tokensFor(char, record)
	local pronouns = Reactions.Pronouns(char)
	local tokens = { name = characterName(char), their = pronouns.their, them = pronouns.them }
	if record then
		tokens.title = record.meta and record.meta.title
		tokens.zone = record.zone
		tokens.level = record.level and tostring(record.level)
		local meta = record.meta or {}
		tokens.faction = meta.factionName
		tokens.standing = meta.standing and ns.GameEvents.STANDINGS[meta.standing]
		tokens.instance = meta.instanceName
		tokens.guild = meta.guildName
		tokens.guildaction = record.category == "guild" and meta.title or nil
		tokens.place = meta.placeName
		tokens.meaningful = meta.meaningful == 1 and "yes" or nil
		tokens.linked = meta.linked == 1 and "yes" or nil
	end
	return tokens
end

-- Braces in observed text (quest titles) must never become tokens.
local function fill(text, tokens)
	return (text:gsub("{(%a+)}", function(name)
		local v = tokens[name]
		return v and v:gsub("[{}]", "") or ""
	end))
end

local function hasAll(tokens, needs)
	for _, name in ipairs(needs) do
		if not tokens[name] then
			return false
		end
	end
	return true
end

--- What the player sees: { reaction, template, question, context, options,
-- record, recall, why } where options are the universal answers, the
-- optional flavour answer, answers drawn from the character's own history
-- (goals, arcs) and the neutral one, each { id, text, phrase, effects,
-- meaning }. recall names a relevant memory; why explains the moment.
function Reactions.Present(char, reaction)
	local template = ReactionLibrary.BY_ID[reaction.templateId]
	if not template then
		return nil, "this reaction's template is not in this version of Dawnward"
	end
	local record = GameEvents.Find(char, reaction.eventKeys[1])
	local tokens = tokensFor(char, record)
	local question
	for _, variant in ipairs(template.questions) do
		if hasAll(tokens, variant.needs) then
			question = fill(variant.text, tokens)
			break
		end
	end
	local options = {}
	for _, option in ipairs(template.options) do
		options[#options + 1] = option
	end
	if char.story.prefs.flavor and record then
		local flavor = ReactionLibrary.Flavor(template.category, record.class)
		if flavor then
			options[#options + 1] = flavor
		end
	end
	-- Context from the character's own established history (Core/Director.lua).
	local context = ns.Director.Context(char, record, template)
	for _, option in ipairs(ns.Director.Options(context)) do
		options[#options + 1] = option
	end
	options[#options + 1] = ReactionLibrary.NEUTRAL
	local extra = #reaction.eventKeys - 1
	local contextLine
	if extra > 0 then
		contextLine = string.format("(and %d more %s%s)", extra, extra == 1 and "task" or "tasks",
			reaction.zone and (" in " .. reaction.zone) or "")
	end
	return {
		reaction = reaction, template = template, question = question, context = contextLine,
		options = options, record = record, name = tokens.name,
		recall = ns.Director.Recall(context), why = context.why,
	}
end

function Reactions.FindOption(presentation, optionId)
	for index, option in ipairs(presentation.options) do
		if option.id == optionId then
			return option, index
		end
	end
	return nil
end

--- A reflection session (#29): the player chose to sit with their story,
-- so everything kept for later is brought back. Returns how many.
function Reactions.Reflect(char)
	local n = 0
	for _, r in ipairs(char.story.reactions) do
		if r.status == "postponed" then
			r.status = "pending"
			n = n + 1
		end
	end
	return n
end

--- Later: kept in the Story section, never announced again.
function Reactions.Postpone(char, id)
	local r = Reactions.Find(char, id)
	if not r then
		return nil, "no waiting reaction #" .. tostring(id)
	end
	r.status = "postponed"
	r.notifiedAt = r.notifiedAt or r.createdAt
	return r
end

--- Not now: closes the notice; the reaction keeps waiting quietly.
function Reactions.Ignore(char, id, now)
	local r = Reactions.Find(char, id)
	if not r then
		return nil, "no waiting reaction #" .. tostring(id)
	end
	r.notifiedAt = now or 0
	return r
end

--- Dismiss: the reaction is removed and never asked again; the event stays
-- in the record, unchanged.
function Reactions.Dismiss(char, id)
	local r, index = Reactions.Find(char, id)
	if not r then
		return nil, "no waiting reaction #" .. tostring(id)
	end
	setEventStatus(char, r.eventKeys, "dismissed")
	table.remove(char.story.reactions, index)
	return r
end

--- Removes a reaction once the player has answered it.
function Reactions.Resolve(char, id)
	local r, index = Reactions.Find(char, id)
	if not r then
		return nil
	end
	setEventStatus(char, r.eventKeys, "reacted")
	table.remove(char.story.reactions, index)
	return r
end

--- The reaction to announce now, if any: pending, never announced, and the
-- notice cooldown has passed (a major event may be announced at once).
function Reactions.NextNotice(char, now)
	local prefs, pacing = char.story.prefs, char.story.pacing
	if prefs.frequency == "off" then
		return nil
	end
	local cooldown = Reactions.COOLDOWN[prefs.frequency]
	for _, r in ipairs(Reactions.List(char, now)) do
		if r.status == "pending" and r.notifiedAt == nil then
			if r.significance >= 3 or pacing.lastNoticeAt == 0 or now - pacing.lastNoticeAt >= cooldown then
				return r
			end
		end
	end
	return nil
end

function Reactions.MarkNotified(char, id, now)
	local r = Reactions.Find(char, id)
	if r then
		r.notifiedAt = now or 0
		char.story.pacing.lastNoticeAt = now or 0
	end
	return r
end
