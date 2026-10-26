-- The character's timeline (#26): a view over records that already exist
-- (event records, journal entries, memories, decisions, arc turning points),
-- not a new store. Dated items come from their own timestamps; undated
-- history (the player's backstory, "when" written as text) is listed apart
-- and is never given an invented date.
local _, ns = ...
local Privacy = ns.Privacy

local Timeline = {}
ns.Timeline = Timeline

--- opts: { allowed = { public, private, secret } (default all), limit }.
-- Returns dated (newest first) and undated lists of { at, kind, text, visibility, ref }.
function Timeline.Build(char, opts)
	opts = opts or {}
	local allowed = opts.allowed or { public = true, private = true, secret = true }
	local dated, undated = {}, {}
	local function add(at, kind, text, visibility, ref)
		if text and Privacy.Allows(allowed, visibility) then
			dated[#dated + 1] = { at = at, kind = kind, text = text, visibility = visibility, ref = ref }
		end
	end
	local story = char.story
	for _, e in ipairs(story.events) do
		local what = ns.GameEvents.Label(e.category) .. (e.meta.title and (": " .. e.meta.title) or "")
			.. (e.meta.factionName and (": " .. e.meta.factionName) or "") .. (e.zone and (" in " .. e.zone) or "")
		add(e.at, "event", what, Privacy.PRIVATE, e.key)
	end
	for _, j in ipairs(char.journal) do
		if j.kind ~= "event" then
			add(j.createdAt, "journal", j.title or j.text, j.visibility, j.id)
		end
	end
	for _, m in ipairs(story.memories) do
		if m.status ~= "superseded" then
			add(m.at, "memory", m.title or m.text, m.visibility, m.id)
		end
	end
	for _, a in ipairs(story.arcs) do
		for _, tp in ipairs(a.turningPoints) do
			add(tp.at, "turning point", a.title .. ": " .. tp.note, a.visibility, a.id)
		end
	end
	table.sort(dated, function(a, b)
		if a.at ~= b.at then return a.at > b.at end
		return a.kind < b.kind
	end)
	for _, h in ipairs(char.history or {}) do
		if Privacy.Allows(allowed, h.visibility) then
			undated[#undated + 1] = { when = h.when, kind = "history", text = h.text, visibility = h.visibility, ref = h.id }
		end
	end
	if opts.limit then
		while #dated > opts.limit do table.remove(dated) end
	end
	return dated, undated
end
