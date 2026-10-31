-- Saved layout of the living chronicle (schema v4): one `story` table per
-- character. Loaded before Schema.lua, which calls StorySchema.New and
-- StorySchema.Normalize for every character.
--
--   events      normalised gameplay event records, oldest first
--   eventKeys   stable event key -> time first seen (duplicate prevention
--               across reloads and sessions; outlives pruned events)
--   reactions   the queue of roleplay opportunities waiting for the player
--   decisions   the player's answers, newest last
--   changes     personality changes: proposed, applied, rejected, reversed
--   baselines   axis -> the player's own value before Dawnward first changed it
--   prefs       tracking, pacing, drafting and approval preferences
--   pacing      timestamps and memory that keep prompts rare and varied
--   clock       the narrative clock: seconds of play (Core/NarrativeClock.lua)
--   memories, arcs, goals, identity
--               narrative records with provenance, canon status and
--               visibility (Core/Records.lua, Core/RecordTypes.lua)
--   reviews     the player's answers to continuity findings
--   places      (schema 5) logged locations: zone or zone / subzone -> first
--               and last visit, visits, verified kind, and whether the
--               player marked it meaningful (Core/Places.lua)
--
-- Everything here is private to the character: none of it is ever part of
-- a projection, a share export or TRP3. Only journal entries the player
-- approves and makes public, and personality values the player makes
-- public, ever leave the core.
local _, ns = ...
local Util, RecordTypes = ns.Util, ns.RecordTypes

local StorySchema = {}
ns.StorySchema = StorySchema

StorySchema.LIMITS = {
	events = 300,
	eventKeys = 2000,
	reactions = 20,
	decisions = 500,
	changes = 300,
	recentTemplates = 6,
	asked = 40,       -- (v0.7.x) questions asked, for repetition control (Core/Reactions.lua)
	questZones = 300,
	text = 300,       -- bytes: titles, phrases, reasons
	custom = 1000,    -- bytes: a custom player response
}

StorySchema.CATEGORIES = { quest = true, levelup = true, death = true, reputation = true, zone = true,
	instance = true, guild = true, moment = true, place = true }
-- How a location event relates to the character's journey (Core/Places.lua):
-- start: the journey begins here (verified starting area, new character);
-- firstseen: the first location Dawnward recorded, nothing more is claimed;
-- first: the first recorded visit during play; return: back after a while.
StorySchema.VISITS = { start = true, firstseen = true, first = true, ["return"] = true }
-- Location moments: on, fewer (notable ones only) or off (still recorded).
StorySchema.PLACE_PROMPTS = { on = true, fewer = true, off = true }
StorySchema.EVENT_STATUS = { new = true, queued = true, recorded = true, reacted = true, dismissed = true }
-- verified: the game reported it; partial: some details were unavailable;
-- player: the player recorded it (a roleplay event, never a game claim).
StorySchema.CONFIDENCE = { verified = true, partial = true, player = true }
StorySchema.REACTION_STATUS = { pending = true, postponed = true }
StorySchema.CHANGE_STATUS = { pending = true, applied = true, rejected = true, reversed = true }
StorySchema.FREQUENCY = { off = true, rare = true, normal = true, frequent = true }
StorySchema.APPROVAL = { ask = true, auto = true }
StorySchema.TRP3_STYLES = { neutral = true, silverhand = true, arcane = true }
-- v0.9: what Dawnward writes to the Total RP 3 About page. "auto": the full
-- profile for a character on the profile publication model, otherwise the
-- v0.3 summary block; "summary": the short Chronicle block; "profile": the
-- whole biography and every Public section (Integrations/TRP3/AboutDoc.lua).
StorySchema.TRP3_ABOUT = { auto = true, summary = true, profile = true }
-- Which Total RP 3 About template it uses: "current" keeps the player's
-- choice in Total RP 3; text, frames and sections pick template 1, 2 or 3.
StorySchema.TRP3_LAYOUTS = { current = true, text = true, frames = true, sections = true }

StorySchema.DEFAULT_PREFS = {
	frequency = "normal",
	threshold = 1,       -- minimum significance (1-3) that may become a reaction
	drafts = true,       -- write a private journal draft for every decision
	approval = "ask",    -- personality changes wait for the player's approval
	flavor = true,       -- optional class-flavoured extra option
	card = true,         -- show the small reaction card at a safe moment
	trp3Style = "neutral",
	trp3About = "auto",
	trp3Layout = "current",
	places = "on",       -- location moments: on, fewer or off
	pace = "standard",   -- narrative day length in play (Core/NarrativeClock.lua): brisk, standard, slow
	repeatDays = 3,      -- (v0.7.x) narrative days before the same question about the same situation (0-14; 0 off)
	tracking = { quest = true, levelup = true, death = true, reputation = true, zone = true, instance = true,
		guild = true, place = true },
}

-- Game tokens such as UnitClass's "WARLOCK" or UnitRace's "NightElf": stored
-- as context for optional flavour only, never as a personality input.
local TOKEN = "^[%a_]+$"

function StorySchema.NewPrefs()
	return Util.DeepCopy(StorySchema.DEFAULT_PREFS)
end

--- Snapshots of observed game state, compared to notice changes
-- (Core/Observed.lua): reputation standings by faction ID, the guild, and
-- whether the first (silent) baseline has been taken.
function StorySchema.NewObserved()
	return { standings = {}, baseline = false, guild = nil, guildSeen = false }
end

local function cleanObserved(raw)
	local out = StorySchema.NewObserved()
	if type(raw) ~= "table" then
		return out
	end
	out.baseline = raw.baseline == true
	out.guildSeen = raw.guildSeen == true
	if type(raw.standings) == "table" then
		local n = 0
		for id, entry in pairs(raw.standings) do
			if Util.IsPositiveInteger(id) and type(entry) == "table" and type(entry.standing) == "number"
				and entry.standing >= 1 and entry.standing <= 8 and entry.standing == math.floor(entry.standing)
				and n < 300 then
				out.standings[id] = { standing = entry.standing, name = Util.CleanText(entry.name, 100) }
				n = n + 1
			end
		end
	end
	if type(raw.guild) == "table" then
		local name = Util.CleanText(raw.guild.name, 100)
		if name and name ~= "" then
			out.guild = { name = name, rank = Util.CleanText(raw.guild.rank, 100) }
		end
	end
	return out
end

function StorySchema.New()
	return {
		events = {},
		eventKeys = {},
		reactions = {},
		decisions = {},
		changes = {},
		baselines = {},
		nextId = 1,
		prefs = StorySchema.NewPrefs(),
		pacing = { lastNoticeAt = 0, lastByCategory = {}, playByCategory = {}, recentTemplates = {}, questZones = {},
			asked = {} },
		clock = ns.NarrativeClock.Clean(nil),
		observed = StorySchema.NewObserved(),
		memories = {},
		arcs = {},
		goals = {},
		identity = {},
		people = {},
		reviews = {},
		places = {},
	}
end

-- Narrative record lists: name -> cleaner and limit.
StorySchema.RECORD_LISTS = {
	memories = { clean = RecordTypes.CleanMemory, limit = RecordTypes.LIMITS.memories },
	arcs = { clean = RecordTypes.CleanArc, limit = RecordTypes.LIMITS.arcs },
	goals = { clean = RecordTypes.CleanGoal, limit = RecordTypes.LIMITS.goals },
	identity = { clean = RecordTypes.CleanIdentity, limit = RecordTypes.LIMITS.identity },
	people = { clean = RecordTypes.CleanPerson, limit = RecordTypes.LIMITS.people },
}

local function ts(v)
	if type(v) == "number" and v >= 0 and v == math.floor(v) and v < 2 ^ 40 then
		return v
	end
	return 0
end

local function text(v, limit, multiline)
	local s = Util.CleanText(v, limit or StorySchema.LIMITS.text, multiline)
	if s == nil or s == "" then
		return nil
	end
	return s
end

local function key(v)
	local s = text(v, 100)
	if s and s == v then
		return s
	end
	return nil
end

local function token(v)
	if type(v) == "string" and #v <= 32 and v:match(TOKEN) then
		return v
	end
	return nil
end

local function smallInt(v, lo, hi)
	if type(v) == "number" and v == math.floor(v) and v >= lo and v <= hi then
		return v
	end
	return nil
end

local function id(v)
	return Util.IsPositiveInteger(v) and v or nil
end

-- Axis deltas: { axis = -1 | 1 }, only known axes, at most 3 entries.
local function effects(raw, axes)
	local out = {}
	if type(raw) ~= "table" then
		return out
	end
	local n = 0
	for axis, delta in pairs(raw) do
		if axes[axis] and (delta == 1 or delta == -1) and n < 3 then
			out[axis] = delta
			n = n + 1
		end
	end
	return out
end

local META_TEXT = { "title", "factionName", "instanceName", "guildName", "guildRank", "placeName" }
local META_INT = { questId = 2 ^ 31, xp = 2 ^ 31, money = 2 ^ 31, questLevel = 1000, factionId = 2 ^ 31, standing = 8,
	previous = 8, mapId = 2 ^ 31, areaId = 2 ^ 31, linked = 1, meaningful = 1, newRegion = 1 }

function StorySchema.CleanMeta(raw)
	local out = {}
	if type(raw) ~= "table" then
		return out
	end
	for _, name in ipairs(META_TEXT) do
		out[name] = text(raw[name], 100)
	end
	for name, hi in pairs(META_INT) do
		out[name] = smallInt(raw[name], 0, hi)
	end
	out.visit = StorySchema.VISITS[raw.visit] and raw.visit or nil
	out.placeKind = ns.Places.KINDS[raw.placeKind] and raw.placeKind or nil
	return out
end

--- Cleans one event record. Returns nil if it is unusable.
function StorySchema.CleanEvent(raw)
	if type(raw) ~= "table" or not StorySchema.CATEGORIES[raw.category] then
		return nil
	end
	local k = key(raw.key)
	if not k then
		return nil
	end
	return {
		key = k,
		category = raw.category,
		at = ts(raw.at),
		zone = text(raw.zone, 100),
		subzone = text(raw.subzone, 100),
		level = smallInt(raw.level, 1, 1000),
		class = token(raw.class),
		race = token(raw.race),
		faction = token(raw.faction),
		meta = StorySchema.CleanMeta(raw.meta),
		source = text(raw.source, 100),
		confidence = StorySchema.CONFIDENCE[raw.confidence] and raw.confidence or "partial",
		significance = smallInt(raw.significance, 1, 3) or 1,
		status = StorySchema.EVENT_STATUS[raw.status] and raw.status or "recorded",
	}
end

local function cleanKeyList(raw)
	local out = {}
	if type(raw) == "table" then
		for _, k in ipairs(raw) do
			local clean = key(k)
			if clean and #out < 20 then
				out[#out + 1] = clean
			end
		end
	end
	return out
end

function StorySchema.CleanReaction(raw)
	if type(raw) ~= "table" or not StorySchema.CATEGORIES[raw.category] then
		return nil
	end
	local reaction = {
		id = id(raw.id),
		category = raw.category,
		eventKeys = cleanKeyList(raw.eventKeys),
		templateId = key(raw.templateId),
		significance = smallInt(raw.significance, 1, 3) or 1,
		status = StorySchema.REACTION_STATUS[raw.status] and raw.status or "pending",
		createdAt = ts(raw.createdAt),
		notifiedAt = raw.notifiedAt ~= nil and ts(raw.notifiedAt) or nil,
		createdPlay = raw.createdPlay ~= nil and ts(raw.createdPlay) or nil,
		expiresPlay = raw.expiresPlay ~= nil and ts(raw.expiresPlay) or nil,
		zone = text(raw.zone, 100),
	}
	if not reaction.id or not reaction.templateId or #reaction.eventKeys == 0 then
		return nil
	end
	return reaction
end

function StorySchema.CleanDecision(raw, axes)
	if type(raw) ~= "table" or not StorySchema.CATEGORIES[raw.category] then
		return nil
	end
	local decision = {
		id = id(raw.id),
		category = raw.category,
		eventKeys = cleanKeyList(raw.eventKeys),
		templateId = key(raw.templateId),
		optionId = key(raw.optionId),
		custom = text(raw.custom, StorySchema.LIMITS.custom, true),
		phrase = text(raw.phrase, StorySchema.LIMITS.text),
		theme = text(raw.theme, 32),
		at = ts(raw.at),
		effects = effects(raw.effects, axes),
		journalId = id(raw.journalId),
	}
	if not decision.id or not (decision.optionId or decision.custom) then
		return nil
	end
	return decision
end

function StorySchema.CleanChange(raw, axes)
	if type(raw) ~= "table" or not axes[raw.axis] or not StorySchema.CHANGE_STATUS[raw.status] then
		return nil
	end
	local delta = raw.delta
	if delta ~= 1 and delta ~= -1 then
		-- Manual adjustments may move further; they are recorded, not proposed.
		delta = smallInt(delta, -20, 20)
		if not delta or delta == 0 then
			return nil
		end
	end
	local change = {
		id = id(raw.id),
		axis = raw.axis,
		delta = delta,
		reason = text(raw.reason, StorySchema.LIMITS.text),
		decisionId = id(raw.decisionId),
		manual = raw.manual == true or nil,
		status = raw.status,
		at = ts(raw.at),
		from = smallInt(raw.from, 0, 20),
		to = smallInt(raw.to, 0, 20),
		decidedAt = raw.decidedAt ~= nil and ts(raw.decidedAt) or nil,
	}
	if not change.id then
		return nil
	end
	return change
end

local function cleanPrefs(raw)
	local prefs = StorySchema.NewPrefs()
	if type(raw) ~= "table" then
		return prefs
	end
	if StorySchema.FREQUENCY[raw.frequency] then prefs.frequency = raw.frequency end
	prefs.threshold = smallInt(raw.threshold, 1, 3) or prefs.threshold
	if StorySchema.APPROVAL[raw.approval] then prefs.approval = raw.approval end
	if StorySchema.TRP3_STYLES[raw.trp3Style] then prefs.trp3Style = raw.trp3Style end
	if StorySchema.TRP3_ABOUT[raw.trp3About] then prefs.trp3About = raw.trp3About end
	if StorySchema.TRP3_LAYOUTS[raw.trp3Layout] then prefs.trp3Layout = raw.trp3Layout end
	if StorySchema.PLACE_PROMPTS[raw.places] then prefs.places = raw.places end
	if ns.NarrativeClock.PACES[raw.pace] then prefs.pace = raw.pace end
	prefs.repeatDays = smallInt(raw.repeatDays, 0, 14) or prefs.repeatDays
	for _, flag in ipairs({ "drafts", "flavor", "card" }) do
		if type(raw[flag]) == "boolean" then prefs[flag] = raw[flag] end
	end
	if type(raw.tracking) == "table" then
		for category in pairs(StorySchema.CATEGORIES) do
			if type(raw.tracking[category]) == "boolean" then
				prefs.tracking[category] = raw.tracking[category]
			end
		end
	end
	return prefs
end

local function cleanPacing(raw)
	local pacing = { lastNoticeAt = 0, lastByCategory = {}, playByCategory = {}, recentTemplates = {}, questZones = {},
		asked = {} }
	if type(raw) ~= "table" then
		return pacing
	end
	pacing.lastNoticeAt = ts(raw.lastNoticeAt)
	-- lastByCategory: real dates (kept for reference); playByCategory: the
	-- narrative clock, which the cooldowns use.
	for _, field in ipairs({ "lastByCategory", "playByCategory" }) do
		if type(raw[field]) == "table" then
			for category in pairs(StorySchema.CATEGORIES) do
				if raw[field][category] ~= nil then
					pacing[field][category] = ts(raw[field][category])
				end
			end
		end
	end
	if type(raw.recentTemplates) == "table" then
		for _, t in ipairs(raw.recentTemplates) do
			local clean = key(t)
			if clean and #pacing.recentTemplates < StorySchema.LIMITS.recentTemplates then
				pacing.recentTemplates[#pacing.recentTemplates + 1] = clean
			end
		end
	end
	-- (v0.7.x, additive) questions asked: { t = template, s = subject, p = play }.
	-- Anything unusable is dropped; a missing list starts empty, so an upgrade
	-- never suppresses (or asks) anything it would not have before.
	if type(raw.asked) == "table" then
		for _, a in ipairs(raw.asked) do
			if type(a) == "table" and key(a.t) and text(a.s, 200) == a.s and type(a.p) == "number"
				and ts(a.p) == a.p then
				pacing.asked[#pacing.asked + 1] = { t = a.t, s = a.s, p = a.p }
			end
		end
		while #pacing.asked > StorySchema.LIMITS.asked do
			table.remove(pacing.asked, 1)
		end
	end
	if type(raw.questZones) == "table" then
		local n = 0
		for zone, v in pairs(raw.questZones) do
			if v == true and text(zone, 100) == zone and n < StorySchema.LIMITS.questZones then
				pacing.questZones[zone] = true
				n = n + 1
			end
		end
	end
	return pacing
end

local function cleanList(raw, cleaner, limit, report, label, axes)
	local out, seen = {}, {}
	if type(raw) ~= "table" then
		return out
	end
	for _, item in ipairs(raw) do
		local clean = cleaner(item, axes)
		if clean and clean.id and seen[clean.id] then
			clean = nil
		end
		if clean then
			if clean.id then seen[clean.id] = true end
			out[#out + 1] = clean
		elseif report then
			report[#report + 1] = "story " .. label .. ": dropped an unusable record"
		end
	end
	-- Oldest records go first when a list is over its limit; pending
	-- personality changes (not yet seen by the player) are kept, as at runtime.
	local i = 1
	while #out > limit and i <= #out do
		if out[i].status == "pending" and label == "changes" then
			i = i + 1
		else
			table.remove(out, i)
			if report then
				report[#report + 1] = "story " .. label .. ": dropped the oldest beyond the limit of " .. limit
			end
		end
	end
	return out
end

--- Keeps at most limit event keys, dropping the oldest.
function StorySchema.CapEventKeys(keys, limit)
	limit = limit or StorySchema.LIMITS.eventKeys
	local list = {}
	for k, at in pairs(keys) do
		list[#list + 1] = { key = k, at = at }
	end
	if #list <= limit then
		return 0
	end
	table.sort(list, function(a, b)
		if a.at ~= b.at then return a.at < b.at end
		return a.key < b.key
	end)
	for i = 1, #list - limit do
		keys[list[i].key] = nil
	end
	return #list - limit
end

--- Returns a cleaned copy of a story table. axes: { [axisId] = true }.
function StorySchema.Normalize(raw, axes, report)
	local story = StorySchema.New()
	if type(raw) ~= "table" then
		return story
	end
	local L = StorySchema.LIMITS
	story.events = cleanList(raw.events, StorySchema.CleanEvent, L.events, report, "events")
	if type(raw.eventKeys) == "table" then
		for k, at in pairs(raw.eventKeys) do
			if key(k) then
				story.eventKeys[k] = ts(at)
			end
		end
	end
	-- Every stored event stays a known key, so it can never be recorded twice.
	for _, event in ipairs(story.events) do
		if story.eventKeys[event.key] == nil then
			story.eventKeys[event.key] = event.at
		end
	end
	StorySchema.CapEventKeys(story.eventKeys)
	story.reactions = cleanList(raw.reactions, StorySchema.CleanReaction, L.reactions, report, "reactions")
	story.decisions = cleanList(raw.decisions, StorySchema.CleanDecision, L.decisions, report, "decisions", axes)
	story.changes = cleanList(raw.changes, StorySchema.CleanChange, L.changes, report, "changes", axes)
	if type(raw.baselines) == "table" then
		for axis, value in pairs(raw.baselines) do
			if axes[axis] and smallInt(value, 0, 20) then
				story.baselines[axis] = value
			end
		end
	end
	story.prefs = cleanPrefs(raw.prefs)
	story.pacing = cleanPacing(raw.pacing)
	story.clock = ns.NarrativeClock.Clean(raw.clock)
	story.observed = cleanObserved(raw.observed)
	story.places = ns.Places.CleanAll(raw.places)
	for name, spec in pairs(StorySchema.RECORD_LISTS) do
		story[name] = cleanList(raw[name], spec.clean, spec.limit, report, name)
	end
	if type(raw.reviews) == "table" then
		for _, review in ipairs(raw.reviews) do
			local clean = RecordTypes.CleanReview(review)
			if clean and #story.reviews < RecordTypes.LIMITS.reviews then
				story.reviews[#story.reviews + 1] = clean
			end
		end
	end
	-- IDs are shared by every story list.
	local maxId = 0
	for _, listName in ipairs({ "reactions", "decisions", "changes", "memories", "arcs", "goals", "identity",
		"people" }) do
		for _, item in ipairs(story[listName]) do
			if item.id > maxId then maxId = item.id end
		end
	end
	story.nextId = math.max(maxId + 1, id(raw.nextId) or 1)
	return story
end
