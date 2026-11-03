-- Profile suggestions (v0.10.2): the one link from the character's approved
-- development to the public Total RP 3 profile.
--
--   verified gameplay event -> the player's answer (Core/Decisions.lua)
--   -> approved development (an applied personality change, an established
--      memory, an achieved goal, an established goal)
--   -> a SUGGESTED profile change, kept here
--   -> the player accepts it (as offered, or in their own words)
--   -> Dawnward's own copy changes (Core/Glance.lua, Core/RPStatus.lua) and
--      the existing guarded sync publishes it (Integrations/TRP3/Sync.lua)
--
-- Nothing here touches Total RP 3, and nothing is published until the
-- player accepts it. The one exception is the Automatic Currently mode,
-- which the player confirms explicitly; it is applied by
-- Core/ProfileActions.lua only while Dawnward owns Currently in Total RP 3
-- without a conflict, and can always be undone.
--
-- Two kinds:
--   glance     an At First Glance entry: a new one in a free Dawnward entry,
--              or a revision of an entry Dawnward suggested and the player
--              accepted unchanged (never an entry the player wrote or
--              edited, never a slot the player filled in Total RP 3)
--   currently  a Currently text, only in the Suggested or Automatic mode
--              (RPStatus.CurrentlyMode; Manual, the default, offers none)
--
-- Every suggestion is occasional, meaningful and explainable:
--   * At First Glance only from cumulative evidence: AXIS_STEPS approved
--     story changes in one direction on one axis (one step toward Bold never
--     reads "fearless"), a memory the player marked defining and
--     established, or a goal the player marked achieved. Never from levels,
--     quests or other content alone. The wording only describes the
--     approved direction; it never claims a physical trait.
--   * Currently only from verified facts (the zone, a completed quest, an
--     instance, a reputation standing) and the player's own goals, after a
--     new zone, a major moment the player answered, or a new goal; with a
--     cooldown, and never the same text twice.
--   * Each one names the records behind it (sources) and why, in plain words.
--   * A theme (an axis, a memory, a goal, a zone) is offered once: accepted
--     or dismissed, it is not offered again unless the evidence grows
--     materially (a higher tier), and at most one suggestion of a kind waits
--     at a time.
--
-- Stored per character as char.profileSuggestions (absent until the first
-- suggestion; cleaned by Schema.NormalizeCharacter through Clean):
--   { nextId, list = { suggestion }, keys = { [key] = { status, tier, at } },
--     managed = { [key] = { title, text, theme } }, texts = { recent
--     Currently texts }, lastCurrentlyAt, autoFrom, lastAuto = { previous,
--     text, at, id } }
-- suggestion = { id, kind, key, theme, tier, status, title?, text, icon?,
--   target = { n?, revises? }, why = { line }, sources = { decisions,
--   changes, memories, goals = { id }, events = { key } }, createdAt,
--   decidedAt?, laterUntil?, private?, automatic? (made in the Automatic
--   mode), held? (why Automatic left it for the player), result? = { n?,
--   title?, text } }
-- status: pending | postponed (laterUntil) | accepted | edited | dismissed |
--   superseded | auto (applied by the Automatic mode) | undone
--
-- Loaded before Core/Schema.lua. The other modules it reads (Evolution,
-- Memories, Goals, Places) are looked up when it runs.
local _, ns = ...
local Util = ns.Util

local PS = {}
ns.ProfileSuggestions = PS

PS.KINDS = { glance = true, currently = true }
PS.STATUS = { pending = true, postponed = true, accepted = true, edited = true, dismissed = true, superseded = true,
	auto = true, undone = true }
-- Waiting for the player (a postponed one again once its time has come).
PS.OPEN = { pending = true, postponed = true }
PS.KEY_STATUS = { offered = true, accepted = true, dismissed = true }
PS.SOURCE_LISTS = { "decisions", "changes", "memories", "goals" }

PS.LIMITS = { list = 40, keys = 200, texts = 10, why = 4, sources = 12, key = 120, title = 100, text = 300,
	line = 200 }
-- Approved story steps in one direction on one axis before an At First
-- Glance entry is offered, and the stronger second tier.
PS.AXIS_STEPS = 3
PS.AXIS_STRONG = 6
-- Seconds between two Currently suggestions, and how long "Later" waits.
PS.CURRENTLY_COOLDOWN = 30 * 60
-- The Automatic mode applies only a fresh suggestion; an older one (held
-- back for a while) waits for the player instead.
PS.AUTO_FRESH = 60 * 60
PS.POSTPONE = 24 * 3600
-- The major moments a Currently text may mention (verified facts only).
PS.MOMENT_CATEGORIES = { quest = true, instance = true, reputation = true }

local function ts(v)
	if type(v) == "number" and v >= 0 and v == math.floor(v) and v < 2 ^ 40 then
		return v
	end
	return nil
end

local function text(v, limit, multiline)
	local s = Util.CleanText(v, limit, multiline)
	return s ~= nil and s ~= "" and s or nil
end

local function isKey(v)
	return type(v) == "string" and v ~= "" and #v <= PS.LIMITS.key and not v:find("[%z\1-\31\127|]")
end

local function idList(raw)
	local out = {}
	for _, v in ipairs(type(raw) == "table" and raw or {}) do
		if Util.IsPositiveInteger(v) and #out < PS.LIMITS.sources then out[#out + 1] = v end
	end
	return out
end

local function keyList(raw)
	local out = {}
	for _, v in ipairs(type(raw) == "table" and raw or {}) do
		if isKey(v) and #out < PS.LIMITS.sources then out[#out + 1] = v end
	end
	return out
end

--- Cleaning ---------------------------------------------------------------------

--- One cleaned suggestion, or nil when it is unusable.
function PS.CleanSuggestion(raw)
	if type(raw) ~= "table" or not Util.IsPositiveInteger(raw.id) or not PS.KINDS[raw.kind]
		or not isKey(raw.key) or not PS.STATUS[raw.status] then
		return nil
	end
	local s = { id = raw.id, kind = raw.kind, key = raw.key, status = raw.status,
		theme = isKey(raw.theme) and raw.theme or raw.key,
		tier = (raw.tier == 2) and 2 or 1,
		title = text(raw.title, PS.LIMITS.title, false),
		text = text(raw.text, PS.LIMITS.text, true),
		icon = ns.Glance.CleanIcon(raw.icon),
		createdAt = ts(raw.createdAt) or 0, decidedAt = ts(raw.decidedAt), laterUntil = ts(raw.laterUntil),
		private = raw.private == true or nil, automatic = raw.automatic == true or nil,
		held = text(raw.held, PS.LIMITS.line, false) }
	if not s.text then
		return nil
	end
	local target = type(raw.target) == "table" and raw.target or {}
	s.target = { n = ns.Glance.Index(target.n), revises = target.revises == true or nil }
	s.why = {}
	for _, line in ipairs(type(raw.why) == "table" and raw.why or {}) do
		local clean = text(line, PS.LIMITS.line, false)
		if clean and #s.why < PS.LIMITS.why then s.why[#s.why + 1] = clean end
	end
	local sources = type(raw.sources) == "table" and raw.sources or {}
	s.sources = { events = keyList(sources.events) }
	for _, name in ipairs(PS.SOURCE_LISTS) do s.sources[name] = idList(sources[name]) end
	if type(raw.result) == "table" then
		local r = raw.result
		s.result = { n = ns.Glance.Index(r.n), title = text(r.title, PS.LIMITS.title, false),
			text = text(r.text, ns.Glance.LIMITS.text, true) }
	end
	if s.status == "postponed" and not s.laterUntil then
		s.status = "pending"
	end
	return s
end

--- Cleans char.profileSuggestions on load. Returns nil when there is
-- nothing (a character that never had a suggestion keeps no table).
function PS.Clean(raw)
	if type(raw) ~= "table" then
		return nil
	end
	local out = { list = {}, keys = {}, managed = {}, texts = {} }
	local used, maxId = {}, 0
	for _, item in ipairs(type(raw.list) == "table" and raw.list or {}) do
		local s = PS.CleanSuggestion(item)
		if s and not used[s.id] then
			used[s.id] = true
			if s.id > maxId then maxId = s.id end
			out.list[#out.list + 1] = s
		end
	end
	out.nextId = math.max(maxId + 1, Util.IsPositiveInteger(raw.nextId) and raw.nextId or 1)
	for key, k in pairs(type(raw.keys) == "table" and raw.keys or {}) do
		if isKey(key) and type(k) == "table" and PS.KEY_STATUS[k.status] then
			out.keys[key] = { status = k.status, tier = k.tier == 2 and 2 or 1, at = ts(k.at) or 0 }
		end
	end
	for key, m in pairs(type(raw.managed) == "table" and raw.managed or {}) do
		if isKey(key) and type(m) == "table" then
			local entry = { title = text(m.title, ns.Glance.LIMITS.title, false),
				text = text(m.text, ns.Glance.LIMITS.text, true), theme = isKey(m.theme) and m.theme or key,
				edited = m.edited == true or nil }
			if entry.title or entry.text then out.managed[key] = entry end
		end
	end
	for _, t in ipairs(type(raw.texts) == "table" and raw.texts or {}) do
		local clean = text(t, ns.RPStatus.LIMITS.text, true)
		if clean and #out.texts < PS.LIMITS.texts then out.texts[#out.texts + 1] = clean end
	end
	out.lastCurrentlyAt = ts(raw.lastCurrentlyAt)
	if type(raw.autoFrom) == "string" then
		out.autoFrom = ns.RPStatus.CleanText(raw.autoFrom)
	end
	if type(raw.lastAuto) == "table" and type(raw.lastAuto.text) == "string" then
		local a = raw.lastAuto
		out.lastAuto = { text = ns.RPStatus.CleanText(a.text),
			previous = type(a.previous) == "string" and ns.RPStatus.CleanText(a.previous) or nil,
			at = ts(a.at) or 0, id = Util.IsPositiveInteger(a.id) and a.id or nil }
	end
	PS.Prune(out)
	return out
end

--- Bounded retention, in place: at most LIMITS.list suggestions (the oldest
-- settled ones go first; waiting ones are kept) and LIMITS.keys keys.
function PS.Prune(store)
	local i = 1
	while #store.list > PS.LIMITS.list and i <= #store.list do
		if PS.OPEN[store.list[i].status] then
			i = i + 1
		else
			table.remove(store.list, i)
		end
	end
	local count = Util.CountKeys(store.keys)
	if count > PS.LIMITS.keys then
		local byAge = {}
		for key, k in pairs(store.keys) do byAge[#byAge + 1] = { key = key, at = k.at } end
		table.sort(byAge, function(a, b)
			if a.at ~= b.at then return a.at < b.at end
			return a.key < b.key
		end)
		for n = 1, count - PS.LIMITS.keys do store.keys[byAge[n].key] = nil end
	end
	return store
end

--- Reading ----------------------------------------------------------------------

--- The character's store, created on first use (only when a suggestion or
-- a mode change needs it).
function PS.Store(char)
	local store = char.profileSuggestions
	if type(store) ~= "table" then
		store = { nextId = 1, list = {}, keys = {}, managed = {}, texts = {} }
		char.profileSuggestions = store
	end
	store.list, store.keys, store.managed, store.texts = store.list or {}, store.keys or {}, store.managed or {},
		store.texts or {}
	store.nextId = store.nextId or 1
	return store
end

function PS.Find(char, id)
	local store = char and char.profileSuggestions
	for _, s in ipairs(store and store.list or {}) do
		if s.id == id then return s end
	end
	return nil
end

--- Whether a suggestion waits for the player now (a postponed one once its time has come).
function PS.IsWaiting(s, now)
	return s.status == "pending" or (s.status == "postponed" and (s.laterUntil or 0) <= (now or 0))
end

--- Suggestions waiting for the player, newest first (kind: optional filter).
function PS.Waiting(char, now, kind)
	local out = {}
	local store = char and char.profileSuggestions
	local list = store and store.list or {}
	for i = #list, 1, -1 do
		local s = list[i]
		if PS.IsWaiting(s, now) and (not kind or s.kind == kind) then out[#out + 1] = s end
	end
	return out
end

function PS.Count(char, now, kind)
	return #PS.Waiting(char, now, kind)
end

-- Whether any suggestion of a kind is still open (waiting or postponed).
local function anyOpen(store, kind)
	for _, s in ipairs(store.list) do
		if s.kind == kind and PS.OPEN[s.status] then return s end
	end
	return nil
end

--- Wording ------------------------------------------------------------------------

-- Subject, object and possessive words from the character's Pronouns field
-- ("she/her", "he/him", "they/them"); with none, the character's name and
-- neutral words. plural: the verbs agree with "they".
function PS.Voice(char)
	local fields = char and char.fields or {}
	local name = fields.name and fields.name.value
	local pronouns = fields.pronouns and fields.pronouns.value
	local first = type(pronouns) == "string" and pronouns:lower():match("^%s*(%a+)") or nil
	local v = { o = "them", p = "their" }
	if first == "she" or first == "her" then
		v.o, v.p, v.subject = "her", "her", "She"
	elseif first == "he" or first == "him" then
		v.o, v.p, v.subject = "him", "his", "He"
	end
	if type(name) == "string" and name ~= "" then
		v.S = Util.CleanText(name, 40, false)
	else
		v.S = v.subject or "They"
		v.plural = v.subject == nil
	end
	return v
end

local PLURAL = { has = "have", carries = "carry", is = "are", acts = "act", holds = "hold", keeps = "keep",
	meets = "meet", weighs = "weigh", takes = "take", shows = "show", seems = "seem" }

--- Fills a template: {S} the subject, {o} {p} object and possessive, and
-- {verb} a verb that agrees with the subject. Pure.
function PS.Render(template, voice)
	return (template:gsub("{(%a+)}", function(word)
		if word == "S" then return voice.S end
		if word == "o" then return voice.o end
		if word == "p" then return voice.p end
		if voice.plural and PLURAL[word] then return PLURAL[word] end
		return word
	end))
end

-- At First Glance wording per axis and direction, two tiers. Each describes
-- only the direction the player approved, as an outward impression.
PS.AXIS_WORDS = {
	courage = {
		up = { { "Growing resolve", "{S} {carries} an increasingly steady determination, readier to step forward "
			.. "than before." }, { "Steady resolve", "{S} {meets} danger with a steadiness that has grown over many "
			.. "choices." } },
		down = { { "A careful eye", "{S} {has} grown more careful, weighing a situation before acting." },
			{ "Measured caution", "{S} {is} noticeably cautious, rarely acting before the ground is known." } },
	},
	compassion = {
		up = { { "A kinder manner", "{S} {has} grown gentler with those in need." },
			{ "Evident compassion", "{S} {shows} kindness readily, and it is plain to those around {o}." } },
		down = { { "A harder edge", "{S} {has} grown harder, less moved by pleas than before." },
			{ "Hard-hearted", "{S} {keeps} a hard edge; pleas rarely move {o}." } },
	},
	discipline = {
		up = { { "Growing discipline", "{S} {has} become more composed and deliberate in {p} manner." },
			{ "Disciplined bearing", "{S} {carries} a disciplined, orderly bearing." } },
		down = { { "Restless energy", "{S} {acts} on impulse more readily than before." },
			{ "Quick to act", "{S} {is} quick to act, and rarely pauses for long." } },
	},
	faith = {
		up = { { "Deepening faith", "Faith {seems} to matter more and more to {o}." },
			{ "Devout", "{S} {is} openly devout." } },
		down = { { "A doubting look", "{S} {has} grown sceptical, slow to take things on faith." },
			{ "Sceptical", "{S} {takes} little on faith." } },
	},
	honour = {
		up = { { "Firmer principles", "{S} {holds} more firmly to {p} principles than before." },
			{ "Principled", "{S} {holds} to {p} principles, even when it costs {o}." } },
		down = { { "A practical streak", "{S} {has} grown more practical, ready to bend a rule when it helps." },
			{ "Pragmatic", "{S} {weighs} results over rules." } },
	},
	sociability = {
		up = { { "More open", "{S} {has} grown more open and easier to approach." },
			{ "Outgoing", "{S} {is} outgoing and easy to approach." } },
		down = { { "More reserved", "{S} {has} grown quieter and more reserved." },
			{ "Reserved", "{S} {keeps} to {p} own counsel." } },
	},
}

--- Evidence -------------------------------------------------------------------------

-- The axis is part of what the profile already shows (Projection.GetPublic).
local function axisPublic(char, axis)
	if not ns.Projection then return false end
	local ok, public = pcall(ns.Projection.GetPublic, char)
	return ok and public and public.personality and public.personality[axis] ~= nil
end

local function axisName(axis)
	return axis:sub(1, 1):upper() .. axis:sub(2)
end

-- Candidates from approved personality changes: per axis, the applied
-- story changes (not the player's own settings, not reversed ones).
local function axisCandidates(char)
	local out = {}
	local changes = char.story and char.story.changes or {}
	for _, axis in ipairs(ns.Personality.AXES) do
		local net, list = 0, {}
		for _, c in ipairs(changes) do
			if c.axis == axis.id and c.status == "applied" and not c.manual and c.decisionId then
				net = net + c.delta
				list[#list + 1] = c
			end
		end
		local dir = net > 0 and 1 or -1
		local steps = {}
		for _, c in ipairs(list) do
			if c.delta * dir > 0 then steps[#steps + 1] = c end
		end
		if math.abs(net) >= PS.AXIS_STEPS and #steps >= PS.AXIS_STEPS then
			local way = dir > 0 and "up" or "down"
			local tier = math.abs(net) >= PS.AXIS_STRONG and 2 or 1
			local words = PS.AXIS_WORDS[axis.id][way][tier]
			local sources = { changes = {}, decisions = {} }
			for i = math.max(1, #steps - PS.LIMITS.sources + 1), #steps do
				sources.changes[#sources.changes + 1] = steps[i].id
				sources.decisions[#sources.decisions + 1] = steps[i].decisionId
			end
			local label = ns.Evolution.AxisLabel(axis.id, dir)
			local why = { string.format("%d approved personality changes toward %s (%s), each from one of your "
				.. "answers.", #steps, label, axisName(axis.id)) }
			local latest = steps[#steps].reason
			if latest then why[#why + 1] = "Latest: " .. latest .. "." end
			out[#out + 1] = { key = "glance:axis:" .. axis.id .. ":" .. way, theme = "glance:axis:" .. axis.id,
				axis = axis.id,
				tier = tier, title = words[1], template = words[2], why = why, sources = sources,
				icon = "spell_arcane_mindmastery" }
		end
	end
	return out
end

local function memoryCandidates(char)
	local out = {}
	for _, m in ipairs(char.story and char.story.memories or {}) do
		if m.status == "established" and m.importance == 3 and m.title then
			local title = Util.CleanText(m.title, 80, false)
			out[#out + 1] = { key = "glance:memory:" .. m.id, theme = "glance:memory:" .. m.id, tier = 1,
				title = "A memory that stays", template = "{S} {carries} the memory of \"" .. title .. "\".",
				why = { "An established memory you marked as defining: \"" .. title .. "\".",
					"Memories stay private in Dawnward; accepting shares only this wording." },
				sources = { memories = { m.id }, decisions = m.links and m.links.decisions or nil },
				icon = "inv_misc_book_09" }
		end
	end
	return out
end

local function goalCandidates(char)
	local out = {}
	for _, g in ipairs(char.story and char.story.goals or {}) do
		if g.status == "established" and g.state == "achieved" and g.title then
			local title = Util.CleanText(g.title, 80, false)
			out[#out + 1] = { key = "glance:goal:" .. g.id, theme = "glance:goal:" .. g.id, tier = 1,
				title = "An aim fulfilled", template = "{S} {has} seen an aim through: " .. title .. ".",
				why = { "You marked your goal \"" .. title .. "\" as achieved." },
				sources = { goals = { g.id } }, icon = "inv_misc_note_06" }
		end
	end
	return out
end

-- Whether a candidate may be offered given what was offered, accepted or
-- dismissed before: only as new evidence (a higher tier than before).
local function offerable(store, cand)
	local k = store.keys[cand.key]
	return k == nil or cand.tier > (k.tier or 1)
end

--- The Dawnward entry number holding the accepted, unchanged suggestion of
-- a theme (so it may be revised), or nil. Never an entry the player wrote
-- or changed: the entry must still read exactly as it was accepted.
function PS.ManagedSlot(char, theme)
	local store = char.profileSuggestions
	for key, m in pairs(store and store.managed or {}) do
		if m.theme == theme and not m.edited then
			for n = 1, ns.Glance.SLOTS do
				local e = char.glance and char.glance[n]
				if e and e.title == m.title and e.text == m.text then return n, key end
			end
		end
	end
	return nil
end

local function freeSlot(char, preferred)
	local entries = char.glance or {}
	if preferred and not entries[preferred] then return preferred end
	for n = 1, ns.Glance.SLOTS do
		if not entries[n] then return n end
	end
	return nil
end

-- Where a glance candidate would go: the Dawnward entry it revises, a free
-- entry, or nowhere (it waits). opts.trp3Free: free Total RP 3 slots, when known.
local function glanceTarget(char, cand, opts)
	local n = PS.ManagedSlot(char, cand.theme)
	if n then
		return { n = n, revises = true }
	end
	if opts and opts.trp3Free == 0 then
		return nil
	end
	n = freeSlot(char)
	return n and { n = n } or nil
end

local function add(store, s, now)
	s.id = store.nextId
	s.status, s.createdAt = "pending", now or 0
	s = PS.CleanSuggestion(s)
	if not s then return nil end
	store.nextId = store.nextId + 1
	store.list[#store.list + 1] = s
	store.keys[s.key] = { status = "offered", tier = s.tier, at = now or 0 }
	PS.Prune(store)
	return s
end

--- The next At First Glance suggestion, if the evidence is sufficient and
-- nothing of the kind is waiting. Adds it and returns it, or nil.
function PS.GenerateGlance(char, now, opts)
	local existing = char.profileSuggestions
	if existing and anyOpen(PS.Store(char), "glance") then
		return nil
	end
	local voice = PS.Voice(char)
	local groups = { axisCandidates(char), memoryCandidates(char), goalCandidates(char) }
	for _, group in ipairs(groups) do
		for _, cand in ipairs(group) do
			local store = char.profileSuggestions or { keys = {}, managed = {} }
			if offerable(store, cand) then
				local target = glanceTarget(char, cand, opts)
				if target then
					-- Checked only for the one offered (it copies the profile).
					if cand.axis and not axisPublic(char, cand.axis) then
						cand.why[#cand.why + 1] = "Your " .. axisName(cand.axis) .. " value stays private; accepting "
							.. "shares only this wording."
					end
					return add(PS.Store(char), { kind = "glance", key = cand.key, theme = cand.theme, tier = cand.tier,
						title = cand.title, text = PS.Render(cand.template, voice), icon = cand.icon, target = target,
						why = cand.why, sources = cand.sources }, now)
				end
			end
		end
	end
	return nil
end

--- Currently ------------------------------------------------------------------------

local function lastZone(char)
	local places = char.story and char.story.places
	if not places or not ns.Places then return nil end
	local list = ns.Places.List(char)
	return list[1] and list[1].zone or nil
end

local function same(a, b)
	return type(a) == "string" and type(b) == "string" and Util.Trim(a):lower() == Util.Trim(b):lower()
end

-- A verified fact from a major moment's record, or nil.
local function momentFact(record)
	local m = record and record.meta or {}
	if record.category == "quest" and m.title then
		return "Recently completed " .. Util.CleanText(m.title, 80, false) .. "."
	elseif record.category == "instance" and m.instanceName then
		return "Recently entered " .. Util.CleanText(m.instanceName, 80, false) .. "."
	elseif record.category == "reputation" and m.factionName and m.standing then
		return "Recently became " .. (ns.GameEvents.STANDINGS[m.standing] or "?") .. " with "
			.. Util.CleanText(m.factionName, 80, false) .. "."
	end
	return nil
end

--- What a Currently suggestion for a trigger would say, or nil. Pure.
-- trigger: { kind = "zone", record } | { kind = "goal", goal } |
-- { kind = "decision", decision, reaction, record }.
-- Returns { key, text, why, sources, private }.
function PS.CurrentlyCandidate(char, trigger)
	trigger = trigger or {}
	local zone, fact, goal, key
	local why, sources = {}, {}
	if trigger.kind == "zone" then
		local r = trigger.record
		if not r or r.category ~= "zone" or not r.zone then return nil end
		zone, key = r.zone, "currently:zone:" .. r.zone
		why[#why + 1] = "Your first recorded visit to " .. r.zone .. " (verified by the game)."
		sources.events = { r.key }
	elseif trigger.kind == "goal" then
		goal = trigger.goal
		if not goal or goal.status ~= "established" or goal.state ~= "active" or not goal.title then return nil end
		zone, key = lastZone(char), "currently:goal:" .. goal.id
		why[#why + 1] = "You set a new goal: \"" .. goal.title .. "\"."
		sources.goals = { goal.id }
	elseif trigger.kind == "decision" then
		local r, reaction = trigger.record, trigger.reaction
		if not r or not reaction or (reaction.significance or 0) < 3 or not PS.MOMENT_CATEGORIES[r.category] then
			return nil
		end
		fact = momentFact(r)
		if not fact then return nil end
		zone, key = r.zone, "currently:event:" .. r.key
		why[#why + 1] = "A major moment you answered in the Story Director: " .. fact
		sources.events = { r.key }
		sources.decisions = trigger.decision and { trigger.decision.id } or nil
	else
		return nil
	end
	if not goal then
		local active = ns.Goals and char.story and ns.Goals.Active(char) or {}
		goal = active[1]
		if goal then sources.goals = { goal.id } end
	end
	local parts = {}
	if zone then parts[#parts + 1] = "In " .. Util.CleanText(zone, 80, false) .. "." end
	if fact then parts[#parts + 1] = fact end
	local private
	if goal and goal.title then
		parts[#parts + 1] = "Working towards: " .. Util.CleanText(goal.title, 120, false) .. "."
		if goal.visibility ~= "public" then
			private = true
			why[#why + 1] = "It names your goal, which stays private in Dawnward until you accept this wording."
		end
	end
	if #parts == 0 then return nil end
	return { key = key, text = table.concat(parts, " "), why = why, sources = sources, private = private }
end

--- A Currently suggestion for a trigger, in the Suggested or Automatic
-- mode only, outside the cooldown, and never a text already shown or
-- offered. An older waiting one gives way. Adds it and returns it, or nil.
function PS.GenerateCurrently(char, now, trigger)
	local mode = ns.RPStatus.CurrentlyMode(char)
	if mode == "manual" then
		return nil
	end
	local cand = PS.CurrentlyCandidate(char, trigger)
	if not cand then
		return nil
	end
	local store = char.profileSuggestions or { keys = {}, texts = {}, list = {} }
	if store.keys[cand.key] then
		return nil
	end
	-- A new goal is the player's own act; other triggers wait out the cooldown.
	if trigger.kind ~= "goal" and store.lastCurrentlyAt and (now or 0) - store.lastCurrentlyAt < PS.CURRENTLY_COOLDOWN then
		return nil
	end
	local current = char.trp3status and char.trp3status.currently
	if same(current, cand.text) then
		return nil
	end
	for _, t in ipairs(store.texts) do
		if same(t, cand.text) then return nil end
	end
	for _, s in ipairs(store.list) do
		if s.kind == "currently" and PS.OPEN[s.status] then
			s.status, s.decidedAt = "superseded", now or 0
		end
	end
	store = PS.Store(char)
	store.lastCurrentlyAt = now or 0
	table.insert(store.texts, 1, cand.text)
	while #store.texts > PS.LIMITS.texts do table.remove(store.texts) end
	return add(store, { kind = "currently", key = cand.key, theme = cand.key, tier = 1, text = cand.text,
		why = cand.why, sources = cand.sources, private = cand.private, target = {},
		automatic = mode == "automatic" or nil }, now)
end

--- Runs every generator for one approved development or verified event.
-- trigger.kind: "decision", "change", "memory", "goal", "zone". Returns the
-- new suggestions (often none). Never touches Total RP 3.
function PS.Generate(char, now, trigger)
	trigger = trigger or {}
	if type(char) ~= "table" or type(char.story) ~= "table" then
		return {}
	end
	local out = {}
	if trigger.kind ~= "zone" then
		local g = PS.GenerateGlance(char, now, trigger.opts)
		if g then out[#out + 1] = g end
	end
	if trigger.kind == "zone" or trigger.kind == "goal" or trigger.kind == "decision" then
		local c = PS.GenerateCurrently(char, now, trigger)
		if c then out[#out + 1] = c end
	end
	return out
end

--- The player's decisions --------------------------------------------------------------

local function open(char, id)
	local s = PS.Find(char, id)
	if not s or not PS.OPEN[s.status] then
		return nil, "no profile suggestion #" .. tostring(id) .. " is waiting"
	end
	return s
end

--- Accepts a suggestion as offered, or (values = { title, text }) in the
-- player's own words. Only Dawnward's own copy changes; Total RP 3 follows
-- through the guarded sync. Returns the suggestion, or nil plus a reason.
function PS.Accept(char, id, now, values)
	local s, err = open(char, id)
	if not s then return nil, err end
	local store = PS.Store(char)
	local edited = values ~= nil
	values = values or {}
	if s.kind == "glance" then
		local title = values.title ~= nil and values.title or s.title
		local body = values.text ~= nil and values.text or s.text
		if not ns.Glance.CleanEntry({ title = title, text = body }) then
			return nil, "write a title or a text"
		end
		local n, oldKey
		if s.target.revises then
			n, oldKey = PS.ManagedSlot(char, s.theme)
		end
		if not n then
			n = freeSlot(char, s.target.n and not s.target.revises and s.target.n or nil)
		end
		if not n then
			return nil, "all five At First Glance entries in Dawnward are in use; remove one first"
		end
		local existing = char.glance and char.glance[n]
		local entry, why = ns.Glance.Save(char, n, { title = title, text = body,
			icon = values.icon or (existing and existing.icon) or s.icon, active = true }, now)
		if type(entry) ~= "table" then return nil, why or "write a title or a text" end
		if oldKey then store.managed[oldKey] = nil end
		store.managed[s.key] = { title = entry.title, text = entry.text, theme = s.theme, edited = edited or nil }
		s.result = { n = n, title = entry.title, text = entry.text }
	else
		local body = values.text ~= nil and values.text or s.text
		local check = ns.RPStatus.CleanText(body)
		if not check or check == "" then return nil, "write some text" end
		local clean, why = ns.RPStatus.Set(char, "currently", body, now)
		if not clean then return nil, why end
		s.result = { text = clean }
	end
	s.status, s.decidedAt, s.laterUntil = edited and "edited" or "accepted", now or 0, nil
	store.keys[s.key] = { status = "accepted", tier = s.tier, at = now or 0 }
	return s
end

--- "Later": the suggestion waits a day before it is shown again.
function PS.Postpone(char, id, now)
	local s, err = open(char, id)
	if not s then return nil, err end
	s.status, s.laterUntil = "postponed", (now or 0) + PS.POSTPONE
	return s
end

--- Dismisses a suggestion: its theme is not offered again unless the
-- evidence grows materially (a higher tier).
function PS.Dismiss(char, id, now)
	local s, err = open(char, id)
	if not s then return nil, err end
	s.status, s.decidedAt, s.laterUntil = "dismissed", now or 0, nil
	PS.Store(char).keys[s.key] = { status = "dismissed", tier = s.tier, at = now or 0 }
	return s
end

--- Currently mode ------------------------------------------------------------------------

--- Sets the Currently mode (RPStatus.SetCurrentlyMode). Turning Automatic
-- on remembers Dawnward's Currently text at that moment: Automatic replaces
-- only that text, an empty one, or its own last text, never one the player
-- wrote afterwards. Manual takes back any Currently suggestion still waiting.
function PS.SetCurrentlyMode(char, mode, now, confirmed)
	local before = ns.RPStatus.CurrentlyMode(char)
	local ok, err = ns.RPStatus.SetCurrentlyMode(char, mode, now, confirmed)
	if not ok then return nil, err end
	if mode == "automatic" and before ~= "automatic" then
		local store = PS.Store(char)
		store.autoFrom = char.trp3status.currently or ""
	elseif mode ~= "automatic" and char.profileSuggestions then
		char.profileSuggestions.autoFrom = nil
	end
	if mode == "manual" and char.profileSuggestions then
		for _, s in ipairs(char.profileSuggestions.list) do
			if s.kind == "currently" and PS.OPEN[s.status] then
				s.status, s.decidedAt = "superseded", now or 0
			end
		end
	end
	return mode
end

--- Why the Automatic mode may not replace Dawnward's Currently text now
-- (from Dawnward's own data), or nil when it may. Pure.
function PS.AutoBlocked(char, s, now)
	if ns.RPStatus.CurrentlyMode(char) ~= "automatic" then
		return "Automatic updates are off"
	end
	if s and s.private then
		return "it names a private goal, so it waits for your approval"
	end
	if s and now and now - (s.createdAt or 0) > PS.AUTO_FRESH then
		return "it is more than an hour old, so it waits for your approval"
	end
	local store = char.profileSuggestions or {}
	local current = char.trp3status and char.trp3status.currently
	if current == nil or current == "" or current == store.autoFrom
		or (store.lastAuto and current == store.lastAuto.text) then
		return nil
	end
	return "you wrote your own Currently since, so Dawnward does not replace it"
end

--- Applies a waiting Currently suggestion by itself (Automatic mode; the
-- caller checked Total RP 3 ownership). Keeps what it replaced, so it can be
-- undone. Returns the suggestion, or nil plus a reason.
function PS.ApplyAutomatic(char, id, now)
	local s, err = open(char, id)
	if not s or s.kind ~= "currently" then return nil, err or "not a Currently suggestion" end
	local blocked = PS.AutoBlocked(char, s, now)
	if blocked then return nil, blocked end
	local previous = char.trp3status and char.trp3status.currently
	local clean = ns.RPStatus.Set(char, "currently", s.text, now)
	if not clean then return nil, "that text cannot be used" end
	local store = PS.Store(char)
	store.lastAuto = { previous = previous, text = clean, at = now or 0, id = s.id }
	s.status, s.decidedAt, s.result = "auto", now or 0, { text = clean }
	store.keys[s.key] = { status = "accepted", tier = s.tier, at = now or 0 }
	return s
end

--- Undoes the last automatic Currently change: the previous text comes
-- back, if Currently still holds what Automatic wrote. Returns the
-- restored text ("" when there was none), or nil plus a reason.
function PS.UndoAutomatic(char, now)
	local store = char.profileSuggestions
	local last = store and store.lastAuto
	if not last then
		return nil, "there is no automatic Currently change to undo"
	end
	local current = char.trp3status and char.trp3status.currently
	if current ~= last.text then
		store.lastAuto = nil
		return nil, "Currently was changed since; nothing was undone"
	end
	local previous = last.previous or ""
	if previous == "" then
		ns.RPStatus.Clear(char, "currently", now)
	else
		ns.RPStatus.Set(char, "currently", previous, now)
	end
	local s = last.id and PS.Find(char, last.id)
	if s and s.status == "auto" then s.status, s.decidedAt = "undone", now or 0 end
	-- Nothing else is applied in its place: a waiting one gives way too.
	for _, other in ipairs(store.list) do
		if other.kind == "currently" and PS.OPEN[other.status] then
			other.status, other.decidedAt = "superseded", now or 0
		end
	end
	store.lastAuto = nil
	if store.autoFrom ~= nil then store.autoFrom = previous end
	return previous
end

--- Plain words for the player -----------------------------------------------------------

--- What accepting changes in Total RP 3, in one line. Pure.
function PS.Effect(char, s)
	if s.kind == "currently" then
		return "Replaces your Currently text. Total RP 3 shows it while Currently is kept in sync."
	end
	local managed = s.target.revises and PS.ManagedSlot(char, s.theme)
	if managed then
		return "Replaces Dawnward's At First Glance entry " .. managed .. ", which you accepted earlier."
	end
	return "Adds At First Glance entry " .. tostring(freeSlot(char, s.target.n) or s.target.n)
		.. ". Total RP 3 shows it while At First Glance sync is on."
end

--- A short label for a suggestion's kind ("At First Glance", "Currently").
function PS.KindLabel(s)
	return s.kind == "currently" and "Currently" or "At First Glance"
end
