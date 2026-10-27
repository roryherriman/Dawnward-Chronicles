-- Personal goals and ambitions (#27). Goals are the player's own. Two kinds
-- of progress are kept apart:
--   objective   verified from recorded gameplay (today: reaching a level,
--               from level-up events); shown, never decides the outcome
--   subjective  milestones the player ticks off; Dawnward may suggest that
--               an answer relates to a goal, but never marks progress itself
-- A goal is never completed automatically: even when its objective is met,
-- the player decides whether it is achieved ("earn forgiveness" cannot be
-- verified by the game at all).
local _, ns = ...
local Records, RecordTypes = ns.Records, ns.RecordTypes

local Goals = {}
ns.Goals = Goals

local function list(char)
	return char.story.goals
end

--- values: { title, text, visibility, objective = { kind = "level", target } }.
function Goals.Add(char, values, now)
	local g = Records.New(char.story, "player", now, values.visibility)
	g.title = values.title
	g.text = values.text
	g.state = "active"
	g.milestones = {}
	g.objective = values.objective
	local clean = RecordTypes.CleanGoal(g)
	if not clean then
		return nil, "a goal needs a title"
	end
	if not Records.Append(list(char), clean, RecordTypes.LIMITS.goals) then
		return nil, "there are too many goals; resolve some first"
	end
	return clean
end

function Goals.Find(char, id) return Records.Find(list(char), id) end
function Goals.Remove(char, id) return Records.Remove(list(char), id) end
function Goals.SetVisibility(char, id, level, now) return Records.Visibility(list(char), id, level, now) end

function Goals.SetState(char, id, state, now)
	local g = Goals.Find(char, id)
	if not g then return nil, "no goal #" .. tostring(id) end
	if not RecordTypes.GOAL_STATES[state] then
		return nil, "a goal can be active, paused, abandoned, achieved or unresolved"
	end
	g.state, g.updatedAt = state, now or 0
	return g
end

--- The player edits a goal: { title, text, target } (nil leaves a field as
-- it is; "" clears the text; target 0 or false removes the level objective).
function Goals.Edit(char, id, values, now)
	local g = Goals.Find(char, id)
	if not g then return nil, "no goal #" .. tostring(id) end
	local title = g.title
	if values.title ~= nil then
		title = Records.Text(values.title, Records.LIMITS.title)
		if not title then return nil, "a goal needs a title" end
	end
	local objective = g.objective
	if values.target ~= nil then
		local t = values.target
		if t == false or t == 0 then
			objective = nil
		elseif type(t) == "number" and t == math.floor(t) and t >= 2 and t <= 100 then
			objective = { kind = "level", target = t }
		else
			return nil, "a target level is a whole number from 2 to 100 (0 for none)"
		end
	end
	g.title, g.objective = title, objective
	if values.text ~= nil then g.text = Records.Text(values.text, Records.LIMITS.text, true) end
	g.updatedAt = now or 0
	return g
end

function Goals.AddMilestone(char, id, text, now)
	local g = Goals.Find(char, id)
	if not g then return nil, "no goal #" .. tostring(id) end
	local clean = Records.Text(text, 200)
	if not clean then return nil, "a milestone needs text" end
	if #g.milestones >= RecordTypes.LIMITS.milestones then return nil, "this goal has the maximum number of milestones" end
	g.milestones[#g.milestones + 1] = { text = clean }
	g.updatedAt = now or 0
	return g
end

--- The player marks a milestone done (or not). Never done automatically.
function Goals.SetMilestone(char, id, index, done, now)
	local g = Goals.Find(char, id)
	local m = g and g.milestones[index]
	if not m then return nil, "no such milestone" end
	m.done = done and true or nil
	m.doneAt = done and (now or 0) or nil
	g.updatedAt = now or 0
	return g
end

--- Highest level the character is verified to have reached (from events).
local function verifiedLevel(char)
	local best
	for _, e in ipairs(char.story.events) do
		if e.level and (not best or e.level > best) then best = e.level end
	end
	return best
end

--- Progress report: { objective = { current, target, met } or nil,
-- milestonesDone, milestonesTotal }. Pure; never changes the goal.
function Goals.Progress(char, goal)
	local p = { milestonesDone = 0, milestonesTotal = #goal.milestones }
	for _, m in ipairs(goal.milestones) do
		if m.done then p.milestonesDone = p.milestonesDone + 1 end
	end
	if goal.objective and goal.objective.kind == "level" then
		local current = verifiedLevel(char)
		p.objective = { current = current, target = goal.objective.target,
			met = current ~= nil and current >= goal.objective.target }
	end
	return p
end

function Goals.Active(char)
	local out = {}
	for _, g in ipairs(list(char)) do
		if g.state == "active" and g.status == "established" then out[#out + 1] = g end
	end
	return out
end
