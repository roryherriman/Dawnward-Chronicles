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
-- Reactions wait until the player answers, postpones or dismisses them, or
-- until they expire. Asking happens elsewhere (Platform/SafeTime decides
-- when); this module never interrupts anything.
local _, ns = ...
local StorySchema, ReactionLibrary, GameEvents = ns.StorySchema, ns.ReactionLibrary, ns.GameEvents

local Reactions = {}
ns.Reactions = Reactions

-- Seconds between reactions of one category, and between two notices.
Reactions.COOLDOWN = { rare = 7200, normal = 2700, frequent = 900 }
Reactions.EXPIRY = 7 * 24 * 3600
Reactions.FREQUENCIES = { "off", "rare", "normal", "frequent" }

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

--- Removes reactions older than the expiry; their events stay recorded.
function Reactions.Expire(char, now)
	local list = char.story.reactions
	local i = 1
	while i <= #list do
		if now and now - list[i].createdAt > Reactions.EXPIRY then
			setEventStatus(char, list[i].eventKeys, "recorded")
			table.remove(list, i)
		else
			i = i + 1
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
function Reactions.Consider(char, record, now)
	local story = char.story
	local prefs, pacing = story.prefs, story.pacing
	Reactions.Expire(char, now)
	local function stay(why)
		record.status = "recorded"
		return nil, why
	end
	if prefs.frequency == "off" then
		return stay("prompts off")
	end
	if record.significance < prefs.threshold then
		return stay("below threshold")
	end
	local target = coalesceTarget(char, record)
	if target then
		target.eventKeys[#target.eventKeys + 1] = record.key
		target.significance = math.max(target.significance, record.significance)
		record.status = "queued"
		return target, "coalesced"
	end
	local last = pacing.lastByCategory[record.category]
	local cooldown = Reactions.COOLDOWN[prefs.frequency]
	if last and record.significance < 3 and now - last < cooldown then
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
		significance = record.significance, status = "pending", createdAt = now or 0, zone = record.zone,
	}
	story.reactions[#story.reactions + 1] = reaction
	pacing.lastByCategory[record.category] = now or 0
	remember(pacing, template.id)
	record.status = "queued"
	return reaction, "queued"
end

--- Waiting reactions: pending before postponed, then most significant, then oldest.
function Reactions.List(char, now)
	Reactions.Expire(char, now)
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

local function tokensFor(char, record)
	local tokens = { name = characterName(char) }
	if record then
		tokens.title = record.meta and record.meta.title
		tokens.zone = record.zone
		tokens.level = record.level and tostring(record.level)
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
-- record } where options are the universal answers, the optional flavour
-- answer and the neutral one, each { id, text, phrase, effects, meaning }.
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
