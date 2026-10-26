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

local function score(item, record, themes, now)
	local s = item.importance or 1
	if record and record.zone and item.zone == record.zone then
		s = s + 3
	end
	for _, tag in ipairs(item.tags or {}) do
		if themes[tag] then s = s + 2 end
	end
	if now and item.at and now - item.at < Director.RECENT then
		s = s + 1
	end
	return s
end

local function ranked(list, record, themes, now)
	local out = {}
	for _, item in ipairs(list) do
		out[#out + 1] = { item = item, score = score(item, record, themes, now) }
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
function Director.Context(char, record, template, now)
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
		memories = ranked(memories, record, themes, now),
		arcs = ranked(arcs, record, themes, now),
		goals = ranked(goals, record, themes, now),
		why = Director.Why(char, record),
	}
end

--- Why this moment appeared, in plain words, from verified data only.
function Director.Why(_, record)
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
	end
	if #why == 0 then
		why[#why + 1] = "you completed it"
	end
	return why
end

local function plain(s)
	return (s:gsub("[{}]", ""))
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
