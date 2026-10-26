-- Long-term arcs (#19): threads of a character's story (a goal, a
-- conflict, a conviction, growth, a relationship) with turning points.
-- The player creates arcs, or accepts ones Dawnward suggests when several
-- of their own decisions share a theme. Suggestions are only suggestions:
-- the player renames, pauses, rejects, edits or concludes them. The same
-- quests give different arcs because arcs come from answers, not content.
local _, ns = ...
local Records, RecordTypes = ns.Records, ns.RecordTypes

local Arcs = {}
ns.Arcs = Arcs

-- Decisions sharing a theme before Dawnward suggests an arc about it.
Arcs.PATTERN = 3

local function list(char)
	return char.story.arcs
end

--- values: { title, summary, kind, tags, links, visibility }.
function Arcs.Add(char, values, provenance, now)
	local a = Records.New(char.story, provenance or "player", now, values.visibility)
	a.title = Records.Text(values.title, Records.LIMITS.title)
	if not a.title then
		return nil, "an arc needs a title"
	end
	a.summary = values.summary
	a.kind = values.kind
	a.state = "active"
	a.tags = values.tags
	a.links = values.links
	local clean = RecordTypes.CleanArc(a)
	if not Records.Append(list(char), clean, RecordTypes.LIMITS.arcs) then
		return nil, "there are too many established arcs; conclude or supersede some first"
	end
	return clean
end

function Arcs.Find(char, id) return Records.Find(list(char), id) end
function Arcs.Accept(char, id, now) return Records.Accept(list(char), id, now) end
function Arcs.Dispute(char, id, now) return Records.Dispute(list(char), id, now) end
function Arcs.Remove(char, id) return Records.Remove(list(char), id) end
function Arcs.SetVisibility(char, id, level, now) return Records.Visibility(list(char), id, level, now) end

--- active, paused, concluded or abandoned.
function Arcs.SetState(char, id, state, now)
	local a = Arcs.Find(char, id)
	if not a then return nil, "no arc #" .. tostring(id) end
	if not RecordTypes.ARC_STATES[state] then
		return nil, "an arc can be active, paused, concluded or abandoned"
	end
	a.state = state
	a.updatedAt = now or 0
	return a
end

function Arcs.Rename(char, id, title, now)
	local a = Arcs.Find(char, id)
	if not a then return nil, "no arc #" .. tostring(id) end
	local clean = Records.Text(title, Records.LIMITS.title)
	if not clean then return nil, "an arc needs a title" end
	a.title, a.updatedAt, a.provenance = clean, now or 0, "player"
	return a
end

--- Adds a turning point (a note, optionally a memory). Returns the arc.
function Arcs.AddTurningPoint(char, id, note, memoryId, now)
	local a = Arcs.Find(char, id)
	if not a then return nil, "no arc #" .. tostring(id) end
	local clean = Records.Text(note, 300, true)
	if not clean then return nil, "a turning point needs a note" end
	if #a.turningPoints >= RecordTypes.LIMITS.turningPoints then
		return nil, "this arc has the maximum number of turning points"
	end
	a.turningPoints[#a.turningPoints + 1] = { note = clean, memoryId = memoryId, at = now or 0 }
	a.updatedAt = now or 0
	return a
end

--- Suggests an arc when PATTERN decisions share a theme that no arc covers
-- yet (proposed, private). Returns the suggestion or nil.
function Arcs.SuggestFromPattern(char, now)
	-- Only the player's answers count, each once.
	local counts, decisionsByTheme = {}, {}
	for _, d in ipairs(char.story.decisions) do
		if d.theme then
			counts[d.theme] = (counts[d.theme] or 0) + 1
			decisionsByTheme[d.theme] = decisionsByTheme[d.theme] or {}
			table.insert(decisionsByTheme[d.theme], d.id)
		end
	end
	local covered = {}
	for _, a in ipairs(list(char)) do
		for _, tag in ipairs(a.tags) do covered[tag] = true end
	end
	local themes = {}
	for theme, n in pairs(counts) do
		if n >= Arcs.PATTERN and not covered[theme] then themes[#themes + 1] = theme end
	end
	table.sort(themes)
	local theme = themes[1]
	if not theme then
		return nil
	end
	local ids = decisionsByTheme[theme]
	return Arcs.Add(char, {
		title = "A thread of " .. theme,
		summary = "Several of your answers share this theme. Is it part of who they are becoming?",
		kind = "growth", tags = { theme }, links = { decisions = ids },
	}, "suggested", now)
end

function Arcs.Active(char)
	local out = {}
	for _, a in ipairs(list(char)) do
		if a.status == "established" and a.state == "active" then out[#out + 1] = a end
	end
	return out
end
