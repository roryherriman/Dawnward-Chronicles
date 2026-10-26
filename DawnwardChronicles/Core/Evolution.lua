-- Personality evolution: small, explainable changes to the six existing
-- axes (0-20), each linked to a decision the player made.
--
--   * A decision can only *propose* changes of one step (-1 or +1). Nothing
--     changes because a quest was completed; only answers move values.
--   * With approval "ask" (the default) a change waits until the player
--     approves it. With "auto" it applies at once, and is still listed so it
--     can be reversed.
--   * At most DAILY_LIMIT steps per axis per day, so no single evening of
--     play transforms a character. A change that would pass 0 or 20, or the
--     daily limit, waits instead of being clipped.
--   * The player's own value is kept as the axis baseline the first time
--     Dawnward changes it, so their starting point is never lost. An axis the
--     player never set starts from the midpoint (10), private.
--   * Manual adjustments are recorded in the same history, so it explains
--     every value.
-- Class, race and faction are never inputs here.
local _, ns = ...
local Personality, StorySchema = ns.Personality, ns.StorySchema

local Evolution = {}
ns.Evolution = Evolution

Evolution.DAILY_LIMIT = 2
Evolution.DAY = 24 * 3600
Evolution.MIDPOINT = 10

local function newId(story)
	local id = story.nextId
	story.nextId = id + 1
	return id
end

local function trim(list)
	-- Oldest settled changes go first; pending ones are kept.
	local i = 1
	while #list > StorySchema.LIMITS.changes and i <= #list do
		if list[i].status ~= "pending" then
			table.remove(list, i)
		else
			i = i + 1
		end
	end
end

function Evolution.Find(char, id)
	for _, change in ipairs(char.story.changes) do
		if change.id == id then
			return change
		end
	end
	return nil
end

function Evolution.AxisLabel(axisId, delta)
	local axis = Personality.AXIS_BY_ID[axisId]
	if not axis then
		return tostring(axisId)
	end
	return delta > 0 and axis.right or axis.left
end

--- Human-readable direction: "toward Compassionate (Compassion +1)".
function Evolution.Describe(change)
	local axis = Personality.AXIS_BY_ID[change.axis]
	local name = change.axis:sub(1, 1):upper() .. change.axis:sub(2)
	return string.format("toward %s (%s %s%d)", axis and Evolution.AxisLabel(change.axis, change.delta) or name,
		name, change.delta > 0 and "+" or "", change.delta)
end

-- Steps already applied on an axis in the last day (manual edits excluded).
local function stepsToday(char, axis, now)
	local n = 0
	for _, change in ipairs(char.story.changes) do
		if change.axis == axis and change.status == "applied" and not change.manual
			and change.decidedAt and now - change.decidedAt < Evolution.DAY then
			n = n + math.abs(change.delta)
		end
	end
	return n
end

--- Applies a pending change. Returns change or nil, reason (it stays pending).
function Evolution.Apply(char, id, now)
	local change = Evolution.Find(char, id)
	if not change or change.status ~= "pending" then
		return nil, "no pending personality change #" .. tostring(id)
	end
	if stepsToday(char, change.axis, now or 0) + math.abs(change.delta) > Evolution.DAILY_LIMIT then
		return nil, "that axis already changed enough today; it can wait until tomorrow"
	end
	local entry = char.personality[change.axis]
	local from = entry and entry.value or Evolution.MIDPOINT
	local to = from + change.delta
	if to < Personality.MIN or to > Personality.MAX then
		return nil, "that axis is already at its limit"
	end
	local story = char.story
	if story.baselines[change.axis] == nil then
		story.baselines[change.axis] = from
	end
	local ok, err = Personality.Set(char, change.axis, to, now)
	if not ok then
		return nil, err
	end
	change.from, change.to, change.status, change.decidedAt = from, to, "applied", now or 0
	return change
end

--- Records a proposed change from a decision; applies it at once when the
-- player chose automatic approval. Returns the change.
function Evolution.Propose(char, axis, delta, reason, decisionId, now)
	if not Personality.AXIS_BY_ID[axis] or (delta ~= 1 and delta ~= -1) then
		return nil, "invalid change"
	end
	local story = char.story
	local change = { id = newId(story), axis = axis, delta = delta, reason = reason, decisionId = decisionId,
		status = "pending", at = now or 0 }
	story.changes[#story.changes + 1] = change
	trim(story.changes)
	if story.prefs.approval == "auto" then
		Evolution.Apply(char, change.id, now)
	end
	return change
end

function Evolution.Reject(char, id, now)
	local change = Evolution.Find(char, id)
	if not change or change.status ~= "pending" then
		return nil, "no pending personality change #" .. tostring(id)
	end
	change.status, change.decidedAt = "rejected", now or 0
	return change
end

--- Undoes an applied change by stepping the axis back. Returns change or nil, reason.
function Evolution.Reverse(char, id, now)
	local change = Evolution.Find(char, id)
	if not change or change.status ~= "applied" or change.manual then
		return nil, "no applied Dawnward change #" .. tostring(id)
	end
	local entry = char.personality[change.axis]
	if not entry then
		return nil, "that axis has been cleared; set it yourself instead"
	end
	local to = entry.value - change.delta
	if to < Personality.MIN or to > Personality.MAX then
		return nil, "that axis cannot move back any further"
	end
	Personality.Set(char, change.axis, to, now)
	change.status, change.decidedAt = "reversed", now or 0
	return change
end

--- Records a value the player set by hand, so the history explains it.
function Evolution.RecordManual(char, axis, from, to, now)
	if from == to or not to then
		return nil
	end
	local story = char.story
	local change = { id = newId(story), axis = axis, delta = to - (from or Evolution.MIDPOINT), manual = true,
		status = "applied", at = now or 0, decidedAt = now or 0, from = from, to = to,
		reason = "set by you" }
	if change.delta == 0 then
		return nil
	end
	story.changes[#story.changes + 1] = change
	trim(story.changes)
	return change
end

function Evolution.Pending(char)
	local out = {}
	for _, change in ipairs(char.story.changes) do
		if change.status == "pending" then
			out[#out + 1] = change
		end
	end
	return out
end

--- Newest first, at most limit.
function Evolution.History(char, limit)
	local out, list = {}, char.story.changes
	for i = #list, 1, -1 do
		if #out >= (limit or 20) then break end
		out[#out + 1] = list[i]
	end
	return out
end

--- Per axis: { axis, value, baseline, drift } for axes that have a value.
-- drift is how far Dawnward-applied changes have moved it from the baseline.
function Evolution.Summary(char)
	local out = {}
	for _, item in ipairs(Personality.List(char)) do
		local baseline = char.story.baselines[item.axis.id]
		out[#out + 1] = { axis = item.axis, value = item.value, visibility = item.visibility, baseline = baseline,
			drift = baseline and (item.value - baseline) or 0 }
	end
	return out
end
