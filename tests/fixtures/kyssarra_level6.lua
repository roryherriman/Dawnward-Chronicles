-- A realistic level-6 save as 0.10.2 stored it (v0.10.3 migration tests):
-- Kyssarra Dawnward, Human Paladin, Pronouns "She/Her", played from level
-- 1 to 6 in Elwynn Forest. Six Story Director answers left six SUGGESTED
-- memories (their texts as 0.10.2 wrote them, with a literal "their"), next
-- to approved, edited and disputed memories, decisions, story drafts, an
-- approved and a pending personality change, an arc, a goal, a person, a
-- stance, At First Glance entries and a Currently text.
local Kyssarra = {}

Kyssarra.KEY = "Kyssarra-TestRealm"
Kyssarra.T0 = 1761000000

-- The six suggestions the owner saw, as stored (never rewritten).
Kyssarra.SUGGESTED = {
	{ id = 40, title = "The journey begins: Northshire Valley",
		text = "Kyssarra Dawnward began with curiosity about the world ahead.", decision = 21,
		event = "place:Elwynn Forest / Northshire Valley", importance = 3, tag = "discovery" },
	{ id = 41, title = "A Threat Within", text = "Kyssarra Dawnward took quiet pride in a job done properly.",
		decision = 22, event = "quest:783", importance = 2, tag = "craftsmanship" },
	{ id = 42, title = "Level 5", text = "Kyssarra Dawnward relished the freedom their strength brings.",
		decision = 23, event = "levelup:5", importance = 2, tag = "freedom" },
	{ id = 43, title = "Goldshire", text = "Kyssarra Dawnward paid attention to the people there.",
		decision = 24, event = "place:Elwynn Forest / Goldshire", importance = 2, tag = "companionship" },
	{ id = 44, title = "Kobold Camp Cleanup", text = "Kyssarra Dawnward felt their resolve to help others grow.",
		decision = 25, event = "quest:7", importance = 2, tag = "protecting others" },
	{ id = 45, title = "Elwynn Forest", text = "Kyssarra Dawnward wanted to see all of it.", decision = 26,
		event = "zone:Elwynn Forest", importance = 2, tag = "discovery" },
}

local PHRASES = {
	[21] = { "origin.beginning", "curious", "began with curiosity about the world ahead", "discovery", "place" },
	[22] = { "quest.meaning", "craft", "took quiet pride in a job done properly", "craftsmanship", "quest" },
	[23] = { "levelup.strength", "freedom", "relished the freedom their strength brings", "freedom", "levelup" },
	[24] = { "place.settlement", "people", "paid attention to the people there", "companionship", "place" },
	[25] = { "quest.meaning", "resolve", "felt their resolve to help others grow", "protecting others", "quest" },
	[26] = { "zone.arrival", "curious", "wanted to see all of it", "discovery", "zone" },
}

local function event(category, key, at, sig, fields, meta)
	local e = { category = category, key = key, at = at, significance = sig, confidence = "verified",
		source = "TEST", status = "reacted", meta = meta or {}, level = fields.level, zone = fields.zone,
		subzone = fields.subzone, class = "PALADIN", race = "Human", faction = "Alliance" }
	return e
end

--- The raw character (before loading) in namespace ns.
function Kyssarra.Character(ns)
	local T = Kyssarra.T0
	local raw = ns.Schema.NewCharacter(T)
	raw.fields.name = { value = "Kyssarra Dawnward", visibility = "public" }
	raw.fields.pronouns = { value = "She/Her", visibility = "public" }
	raw.fields.homeland = { value = "Elwynn Forest", visibility = "public" }
	raw.personality.courage = { value = 11, visibility = "public", updatedAt = T + 900 }
	raw.personality.discipline = { value = 10, visibility = "public", updatedAt = T + 100 }
	local story = raw.story
	story.nextId = 80
	story.baselines = { courage = 10, discipline = 10 }
	local ev = story.events
	ev[#ev + 1] = event("place", "place:Elwynn Forest / Northshire Valley", T + 10, 3,
		{ level = 1, zone = "Elwynn Forest", subzone = "Northshire Valley" },
		{ visit = "start", placeName = "Northshire Valley", placeKind = "start" })
	ev[#ev + 1] = event("quest", "quest:783", T + 200, 2, { level = 1, zone = "Elwynn Forest",
		subzone = "Northshire Valley" }, { questId = 783, title = "A Threat Within", questLevel = 1 })
	ev[#ev + 1] = event("levelup", "levelup:2", T + 400, 1, { level = 2, zone = "Elwynn Forest" })
	ev[#ev + 1] = event("quest", "quest:7", T + 500, 2, { level = 2, zone = "Elwynn Forest" },
		{ questId = 7, title = "Kobold Camp Cleanup", questLevel = 2 })
	ev[#ev + 1] = event("levelup", "levelup:3", T + 700, 1, { level = 3, zone = "Elwynn Forest" })
	ev[#ev + 1] = event("levelup", "levelup:4", T + 900, 1, { level = 4, zone = "Elwynn Forest" })
	ev[#ev + 1] = event("levelup", "levelup:5", T + 1100, 2, { level = 5, zone = "Elwynn Forest" })
	ev[#ev + 1] = event("zone", "zone:Elwynn Forest", T + 1200, 2, { level = 5, zone = "Elwynn Forest" },
		{ visit = "firstseen" })
	ev[#ev + 1] = event("place", "place:Elwynn Forest / Goldshire", T + 1300, 2,
		{ level = 5, zone = "Elwynn Forest", subzone = "Goldshire" },
		{ visit = "first", placeName = "Goldshire", placeKind = "town" })
	ev[#ev + 1] = event("quest", "quest:47", T + 1400, 1, { level = 5, zone = "Elwynn Forest" },
		{ questId = 47, title = "Gold Dust Exchange", questLevel = 5 })
	ev[#ev + 1] = event("levelup", "levelup:6", T + 1500, 1, { level = 6, zone = "Elwynn Forest" })
	for _, e in ipairs(ev) do story.eventKeys[e.key] = e.at end
	-- The six answers, with their phrases as 0.10.2 stored them.
	for id = 21, 26 do
		local p = PHRASES[id]
		local s = Kyssarra.SUGGESTED[id - 20]
		story.decisions[#story.decisions + 1] = { id = id, category = p[5], eventKeys = { s.event },
			templateId = p[1], optionId = p[2], phrase = p[3], theme = p[4], at = T + 1600 + id, effects = {},
			journalId = 100 + id }
	end
	story.decisions[3].effects = { discipline = -1 }
	story.decisions[1].effects = { courage = 1 }
	story.changes = {
		{ id = 30, axis = "courage", delta = 1, reason = "Kyssarra Dawnward began with curiosity about the world ahead",
			decisionId = 21, status = "applied", at = T + 1621, decidedAt = T + 1700, from = 10, to = 11 },
		{ id = 31, axis = "discipline", delta = -1, reason = "Kyssarra Dawnward relished the freedom their strength "
			.. "brings", decisionId = 23, status = "pending", at = T + 1623 },
	}
	-- The six suggestions, then the player's own records.
	for _, s in ipairs(Kyssarra.SUGGESTED) do
		story.memories[#story.memories + 1] = { id = s.id, provenance = "suggested", status = "proposed",
			visibility = "private", title = s.title, text = s.text, tags = { s.tag }, importance = s.importance,
			zone = "Elwynn Forest", at = T + 1600 + s.decision,
			links = { events = { s.event }, decisions = { s.decision }, journal = { 100 + s.decision }, memories = {},
				arcs = {}, goals = {} } }
	end
	local function memory(id, values)
		local m = { id = id, visibility = "private", tags = {}, importance = 1, at = T + 2000 + id,
			links = { events = {}, decisions = {}, journal = {}, memories = {}, arcs = {}, goals = {} } }
		for k, v in pairs(values) do m[k] = v end
		return m
	end
	story.memories[#story.memories + 1] = memory(50, { provenance = "player", status = "established",
		title = "The Abbey bells", text = "The bells of Northshire Abbey at dawn, the first morning.", importance = 3,
		visibility = "public" })
	story.memories[#story.memories + 1] = memory(51, { provenance = "suggested", status = "established",
		title = "Brother Sammuel", text = "Kyssarra Dawnward listened to Brother Sammuel's lesson." })
	-- A suggestion the player rewrote in her own words and accepted.
	story.memories[#story.memories + 1] = memory(52, { provenance = "player", status = "established",
		title = "Wolves at the gate", text = "I did not run. I want to remember that.", updatedAt = T + 2100 })
	-- One the player rejected (disputed).
	story.memories[#story.memories + 1] = memory(53, { provenance = "suggested", status = "disputed",
		title = "Kobold candles", text = "Kyssarra Dawnward felt uneasy there.", updatedAt = T + 2200 })
	story.arcs[1] = { id = 60, provenance = "player", status = "established", visibility = "private",
		title = "The Light's question", kind = "conviction", state = "active", tags = { "faith" }, at = T + 2300,
		turningPoints = { { note = "Kyssarra Dawnward took quiet pride in a job done properly.", at = T + 2310 } },
		links = { events = {}, decisions = { 22 }, journal = {}, memories = {}, arcs = {}, goals = {} } }
	story.goals[1] = { id = 61, provenance = "player", status = "established", visibility = "private",
		title = "Earn a place in the Order", state = "active", milestones = { { text = "Train at the Abbey" } },
		objective = { kind = "level", target = 10 }, at = T + 2400,
		links = { events = {}, decisions = {}, journal = {}, memories = {}, arcs = {}, goals = {} } }
	story.people[1] = { id = 62, provenance = "player", status = "established", visibility = "private",
		name = "Brother Sammuel", kind = "npc", relation = "Her first teacher", at = T + 2500,
		links = { events = {}, decisions = {}, journal = {}, memories = {}, arcs = {}, goals = {} } }
	story.identity[1] = { id = 63, provenance = "player", status = "established", visibility = "public",
		subject = "Stormwind", persona = "A loyal subject", conviction = "Unsure of the nobility", at = T + 2600,
		links = { events = {}, decisions = {}, journal = {}, memories = {}, arcs = {}, goals = {} } }
	-- The journal: the level-up milestones, the six story drafts (one
	-- approved), and a note of her own.
	local j = raw.journal
	for level = 2, 6 do
		assert(ns.Milestones.Record(raw, "levelup", { level = level, zone = "Elwynn Forest" }, T + 200 * level))
	end
	for id = 21, 26 do
		local s = Kyssarra.SUGGESTED[id - 20]
		j[#j + 1] = { id = 100 + id, kind = "story", title = s.title, text = "Something happened.\n\n" .. s.text,
			status = id == 21 and "approved" or "draft", visibility = "private", createdAt = T + 1600 + id,
			story = { category = PHRASES[id][5], decisionId = id, eventKey = s.event } }
	end
	j[#j + 1] = { id = 130, kind = "note", title = "First night", text = "The Abbey is quiet.", visibility = "private",
		createdAt = T + 3000 }
	raw.nextId = 131
	raw.glance[1] = { title = "Tabard of the Abbey", text = "Northshire colours, freshly washed.",
		icon = "inv_shirt_guildtabard_01", active = true }
	raw.glance[2] = { title = "Holy symbol", active = true }
	raw.trp3status = { currently = "Training at Northshire Abbey.", ooc = "New to RP, say hi!", style = {} }
	raw.updatedAt = T + 3000
	return raw
end

return Kyssarra
