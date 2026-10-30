-- Developer diagnostics for the Story Director's place moments
-- (development builds only, under /dawnward dev story):
--
--   dev story status               the narrative clock, where you are, how
--                                  the place is tied to the story, whether a
--                                  return here can count and how much play is
--                                  still needed, the location cooldown, the
--                                  repeat window (what was asked about this
--                                  place, and the last repeat suppressed this
--                                  session), and why the last arrival this
--                                  session did or did not ask
--   dev story simulate [place]     a return to the place (default: here)
--                                  after enough play away, on a copy of the
--                                  character: shows what would happen
--   dev story simulate time <n>[m|h|d] [place]
--                                  plays n minutes, hours or narrative days
--                                  on a copy, then shows what a return to the
--                                  place would do at that point
--
-- Everything is measured on the narrative clock: seconds of play, never
-- offline time (Core/NarrativeClock.lua).
--
-- Read-only: status only reads; simulate works on a deep copy that is
-- discarded, so no place, event, cooldown, clock, moment or journal entry
-- changes.
local _, ns = ...
local Util, Commands, Places, Reactions, Director, GameEvents, NarrativeClock =
	ns.Util, ns.Commands, ns.Places, ns.Reactions, ns.Director, ns.GameEvents, ns.NarrativeClock

local StoryDiagnostics = {}
ns.StoryDiagnostics = StoryDiagnostics

local out = Commands.Out

--- "45 s", "12 min", "3 h 5 min", "2 days 4 h". Pure.
function StoryDiagnostics.Duration(seconds)
	seconds = math.max(0, math.floor(seconds or 0))
	if seconds < 60 then return seconds .. " s" end
	local minutes = math.floor(seconds / 60)
	if minutes < 60 then return minutes .. " min" end
	local hours = math.floor(minutes / 60)
	if hours < 24 then
		local m = minutes % 60
		return hours .. " h" .. (m > 0 and (" " .. m .. " min") or "")
	end
	local days = math.floor(hours / 24)
	local h = hours % 24
	return days .. (days == 1 and " day" or " days") .. (h > 0 and (" " .. h .. " h") or "")
end
local duration = StoryDiagnostics.Duration

--- Seconds of play from "90m", "2h" or "3d" (narrative days for char).
-- Returns seconds or nil. Pure.
function StoryDiagnostics.ParseAmount(char, text)
	local n, unit = tostring(text or ""):lower():match("^%s*(%d+%.?%d*)%s*([mhd]?)%s*$")
	n = tonumber(n)
	if not n or n <= 0 or n > 100000 then
		return nil
	end
	local scale = unit == "m" and 60 or unit == "d" and NarrativeClock.DayLength(char) or 3600
	return math.floor(n * scale)
end

local TIES = {
	homeland = "it is your Homeland",
	meaningful = "you marked it as meaningful",
	memory = "one of your established memories is tied to it",
}

--- Plain words for a Places.ReturnCheck reason. Pure.
function StoryDiagnostics.ReturnReason(why, info)
	info = info or {}
	if why == nil then
		return "a return here counts"
	elseif why == "away" then
		return string.format("away %s of play; a return counts after %s of play away (%s more)",
			duration(info.away), duration(info.needed), duration(info.wait))
	elseif why == "weekly" then
		return string.format("a return here was already recorded this narrative week; next possible after %s more "
			.. "play", duration(info.wait))
	elseif why == "new" then
		return "logged before gameplay time was tracked: time away starts counting from this visit"
	elseif why == "ordinary" then
		return "returns count only for settlements, starting areas, capitals and places tied to your story "
			.. "(Homeland, marked, or a memory), and this place is none of these"
	elseif why == "first" then
		return "nothing here was logged before, so this is a first visit, not a return"
	end
	return tostring(why)
end

-- Plain words for a Reactions.Consider outcome.
local OUTCOMES = {
	queued = "a moment was queued",
	coalesced = "added to a moment already waiting",
	replaced = "it replaced a less meaningful place moment waiting",
	["prompts off"] = "suppressed: story prompts are off (Settings > Story)",
	["place moments off"] = "suppressed: place moments are off (Settings > Story)",
	["below threshold"] = "suppressed: below your significance threshold",
	["logged quietly"] = "suppressed: the Director gave it no weight (nothing ties it to your story)",
	["not this time"] = "suppressed: the Director's weighted chance did not ask this time",
	["folded into a waiting moment"] = "suppressed: folded into a place moment already waiting",
	cooldown = "suppressed: the shared location cooldown",
	["repeat"] = "suppressed: the same question about the same situation was asked within the repeat window",
	["queue full"] = "suppressed: the waiting list is full",
	["no template"] = "suppressed: no question fits this event",
}

function StoryDiagnostics.OutcomeText(outcome)
	if outcome == nil then
		return "recorded only (one moment per arrival)"
	end
	return OUTCOMES[outcome] or tostring(outcome)
end

-- The place the player is in, as Places would log it.
local function here(ctx)
	local obs = ctx.location and ctx.location() or nil
	if not obs or type(obs.zone) ~= "string" or obs.zone == "" then
		return nil
	end
	if obs.subzone == "" or obs.subzone == obs.zone then obs.subzone = nil end
	local areaId = obs.subzone and obs.areaId or nil
	obs.areaKind = areaId and Places.AreaKind(obs.client, obs.mapId, areaId) or nil
	obs.zoneKind = Places.ZoneKind(obs.client, obs.mapId)
	return obs
end

-- A return record for entry, as GameEvents would build it (not recorded).
local function returnRecord(char, entry, kind, now)
	local linked = Places.Linked(char.story, entry)
	return {
		category = "place", key = "return:" .. Places.Key(entry.zone, entry.subzone) .. ":" .. now, at = now,
		zone = entry.zone, subzone = entry.subzone,
		meta = { visit = "return", placeName = entry.subzone or entry.zone, placeKind = kind,
			meaningful = entry.meaningful and 1 or nil, linked = linked and 1 or nil },
	}
end

local function relevanceLine(char, record)
	local r = Director.LocationRelevance(char, record, char.story.prefs)
	return string.format("Director weight: %d (chance %d%%%s)%s", r.score, math.floor(r.chance * 100 + 0.5),
		r.urgent and ", urgent: skips the location cooldown" or "",
		#r.reasons > 0 and (": " .. table.concat(r.reasons, "; ")) or ""), r
end

local function cooldownLine(char, play)
	local prefs, pacing = char.story.prefs, char.story.pacing
	if prefs.frequency == "off" then
		return "Location cooldown: story prompts are off."
	end
	if prefs.places == "off" then
		return "Location cooldown: place moments are off."
	end
	local a, b = pacing.playByCategory.zone, pacing.playByCategory.place
	local last = a and b and math.max(a, b) or a or b
	local cooldown = Reactions.COOLDOWN[prefs.frequency]
	if not last or last > play or play - last >= cooldown then
		return string.format("Location cooldown: ready (%s of play between place moments at '%s').",
			duration(cooldown), prefs.frequency)
	end
	return string.format("Location cooldown: %s of play left of %s (last place moment %s of play ago). "
		.. "Urgent places skip it.", duration(cooldown - (play - last)), duration(cooldown), duration(play - last))
end

--- Repetition control: the window, what was asked about subject (if
-- given) and still blocks a repeat, and the last repeat suppressed this
-- session. Read-only.
function StoryDiagnostics.RepeatLines(char, play, subject, label)
	local lines = {}
	local window = Reactions.RepeatWindow(char)
	local days = char.story.prefs.repeatDays or Reactions.DEFAULT_REPEAT_DAYS
	if window <= 0 then
		lines[1] = "Repeat window: off (story set repeat 0): a question may come back about the same situation."
	else
		lines[1] = string.format("Repeat window: %d narrative day%s (%s of play): the same question about the same "
			.. "situation is not asked again sooner.", days, days == 1 and "" or "s", duration(window))
	end
	if subject and window > 0 then
		local asked = char.story.pacing.asked or {}
		local found = false
		for i = #asked, 1, -1 do
			local a = asked[i]
			if a.s == subject and a.p <= play and play - a.p < window then
				found = true
				lines[#lines + 1] = string.format("  Asked about %s: %s, %s of play ago; not again for %s more play.",
					label or subject, a.t, duration(play - a.p), duration(window - (play - a.p)))
			end
		end
		if not found then
			lines[#lines + 1] = string.format("  Nothing asked about %s within the window.", label or subject)
		end
	end
	local last = Reactions.lastRepeat[char]
	if last then
		lines[#lines + 1] = string.format("Last repeat suppressed this session: %s: the question %s about %s was "
			.. "asked %s of play before (window %s).", last.record or "an event", last.templateId,
			last.label or last.subject or "?", duration(last.ago), duration(last.window))
	end
	return lines
end

--- Lines describing the narrative clock for char at play.
function StoryDiagnostics.ClockLines(ctx, char, play)
	local day = NarrativeClock.DayLength(char)
	local pace = char.story.prefs.pace or NarrativeClock.DEFAULT_PACE
	local lines = {
		string.format("Narrative clock: %s of play · narrative day %d (pace %s: a narrative day is %s of play).",
			duration(play), NarrativeClock.Day(char, play), NarrativeClock.PACE_LABELS[pace] or pace, duration(day)),
	}
	local session = ctx.narrative
	if session then
		lines[#lines + 1] = session.paused and "The clock is paused: you are AFK."
			or "The clock is running: only time you play counts, never time offline."
	end
	return lines
end

--- Encounter events seen this session (Platform/Observers' unverified
-- probe, #11). Nothing here was recorded or saved.
function StoryDiagnostics.EncounterLines(ctx)
	local list = ctx.encounters or {}
	if #list == 0 then
		return { "Encounter events this session: none seen (whether ENCOUNTER_END or BOSS_KILL fire on Classic Era "
			.. "is unverified; nothing is recorded from them)." }
	end
	local lines = { "Encounter events this session (unverified probe; nothing recorded):" }
	for _, e in ipairs(list) do
		lines[#lines + 1] = string.format("  %s %s %s%s", e.event, tostring(e.id or "?"), e.name or "?",
			e.success and (" success=" .. e.success) or "")
	end
	return lines
end

--- Lines for /dawnward dev story status.
function StoryDiagnostics.StatusLines(ctx)
	local now = ctx.now()
	local char = ctx.store.real.characters[ctx.characterKey]
	local lines = { "Story Director: places (development build, read-only)." }
	local function add(text) lines[#lines + 1] = text end
	if not char then
		add("This character has no Dawnward record yet, so places are not logged.")
		return lines
	end
	local play = NarrativeClock.Current(char, ctx)
	for _, line in ipairs(StoryDiagnostics.ClockLines(ctx, char, play)) do add(line) end
	local obs = here(ctx)
	if not obs then
		add("Location: unknown (no zone from the client).")
	else
		local name = obs.subzone and (obs.subzone .. ", " .. obs.zone) or obs.zone
		local kind = obs.areaKind or (not obs.subzone and obs.zoneKind) or nil
		add(string.format("Location: %s (map %s, area %s): %s.", name, tostring(obs.mapId or "?"),
			tostring(obs.subzone and obs.areaId or "-"),
			kind and Places.KIND_LABELS[kind] or "not in the place mapping (logged; never asks by itself)"))
		local entry = obs.subzone and Places.Entry(char, obs.zone, obs.subzone) or Places.Entry(char, obs.zone)
		if entry then
			add(string.format("Logged: %d visit%s; last recorded here %s.", entry.visits,
				entry.visits == 1 and "" or "s", entry.lastPlay
					and (duration(math.max(0, play - entry.lastPlay)) .. " of play ago")
					or "before gameplay time was tracked"))
			add(string.format("Homeland: %s. Marked meaningful: %s. Memory tie: %s.",
				Places.IsHomeland(char, entry) and "yes" or (Places.Tie(char, entry) == "homeland"
					and "yes (named by the Homeland field)" or "no"),
				entry.meaningful and "yes" or "no", Places.Linked(char.story, entry) and "yes" or "no"))
		else
			add("Logged: not yet. The next location update records a first visit.")
		end
		local target, kind2 = Places.ReturnTarget(char, obs.zone, obs.subzone, obs.areaKind, obs.zoneKind)
		if target then
			local ok, why, info = Places.ReturnCheck(char, target, kind2, play)
			add(string.format("Return to %s, if it happened now: %s.", Places.Label(target),
				ok and "would be recorded" or ("not eligible: " .. StoryDiagnostics.ReturnReason(why, info))))
			if info.tie then add("Tied to your story: " .. TIES[info.tie] .. ".") end
			add((relevanceLine(char, returnRecord(char, target, kind2, now))))
		else
			add("Return: " .. StoryDiagnostics.ReturnReason(entry and "ordinary" or "first") .. ".")
		end
	end
	add(cooldownLine(char, play))
	local subject, label
	if obs then
		subject, label = Director.Subject({ category = obs.subzone and "place" or "zone", zone = obs.zone,
			subzone = obs.subzone })
	end
	for _, line in ipairs(StoryDiagnostics.RepeatLines(char, play, subject, label)) do add(line) end
	add(string.format("Waiting moments: %d.", #Reactions.List(char, now, play)))
	for _, line in ipairs(StoryDiagnostics.EncounterLines(ctx)) do add(line) end
	local last = ctx.lastLocation
	if not last then
		add("Last arrival this session: none observed yet.")
	else
		local name = last.subzone and (last.subzone .. ", " .. last.zone) or last.zone or "?"
		add(string.format("Last arrival this session: %s, %s ago.", name, duration(now - last.at)))
		local diag = last.diag or {}
		for i, made in ipairs(last.created) do
			add(string.format("  %s: %s.", GameEvents.RecordLabel(made.record),
				i == 1 and StoryDiagnostics.OutcomeText(made.outcome) or StoryDiagnostics.OutcomeText(nil)))
		end
		if diag.origin then
			add("  The first location Dawnward recorded for this character: no return check.")
		elseif diag.why then
			add(string.format("  Return%s: not recorded: %s.", diag.target and (" to " .. diag.target) or "",
				StoryDiagnostics.ReturnReason(diag.why, diag.info)))
		end
		if #last.created == 0 and not diag.why then
			add("  No event: nothing new to record here.")
		end
	end
	return lines
end

-- The logged place to simulate: a named one, else the current one.
local function simTarget(ctx, char, name)
	local obs = here(ctx) or {}
	if name and Util.Trim(name) ~= "" then
		local entry, err = Places.FindByName(char, name)
		return entry, err, obs
	end
	local entry = obs.zone and (obs.subzone and Places.Entry(char, obs.zone, obs.subzone) or Places.Entry(char, obs.zone))
	return entry, obs.zone and "Dawnward has not logged this place yet; visit it first, or name one you have "
		.. "visited (/dawnward dev story simulate Goldshire)" or "your location is unknown; name a visited place", obs
end

-- Runs one arrival at entry on copy, at real time now and play. Lines added to lines.
local function simulateArrival(lines, ctx, copy, entry, obs, now, play)
	local function add(text) lines[#lines + 1] = text end
	local centry = copy.story.places[Places.Key(entry.zone, entry.subzone)]
	local sim = {
		zone = centry.zone, subzone = centry.subzone, mapId = centry.mapId, areaId = centry.areaId,
		level = obs.level, class = obs.class, race = obs.race, faction = obs.faction, source = "SIMULATION",
		client = obs.client or (ctx.client and ctx.client.id),
	}
	local steps, diag = Places.Observe(copy, sim, now, play)
	local considered = false
	for _, step in ipairs(steps) do
		local record = GameEvents.Record(copy, step.category, step.data, now)
		if record then
			if not considered then
				considered = true
				add(string.format("Event: %s (significance %d).", GameEvents.RecordLabel(record), record.significance))
				if Reactions.LOCATION[record.category] then
					add((relevanceLine(copy, record)))
					add(string.format("Director roll: %.2f (asks when below the chance).", Director.Roll(record)))
				end
				add(cooldownLine(copy, play))
				local reaction, outcome = Reactions.Consider(copy, record, now, play)
				add("Result: " .. StoryDiagnostics.OutcomeText(outcome) .. ".")
				local blocked = outcome == "repeat" and Reactions.lastRepeat[copy]
				if blocked then
					add(string.format("Repeat: the question %s about %s was asked %s of play before (window %s).",
						blocked.templateId, blocked.label or blocked.subject, duration(blocked.ago),
						duration(blocked.window)))
				end
				local view = reaction and Reactions.Present(copy, reaction)
				if view then
					add("Question: " .. tostring(view.question))
					local answers = {}
					for _, option in ipairs(view.options) do answers[#answers + 1] = option.text end
					add("Answers: " .. table.concat(answers, " / "))
				end
			else
				add(string.format("Also recorded: %s.", GameEvents.RecordLabel(record)))
			end
		end
	end
	if not considered then
		add("Result: no event: " .. StoryDiagnostics.ReturnReason(diag and diag.why or "ordinary", diag and diag.info)
			.. ".")
	end
end

local SAVED_NOTHING = "Nothing was saved: places, events, the clock, cooldowns, waiting moments and the journal "
	.. "are unchanged."

--- Lines for /dawnward dev story simulate [place]: a return to the place
-- after enough play away, run on a copy of the character. Never saves.
function StoryDiagnostics.SimulateLines(ctx, name)
	local now = ctx.now()
	local char = ctx.store.real.characters[ctx.characterKey]
	if not char then
		return { "This character has no Dawnward record yet, so there is nothing to simulate." }
	end
	local entry, err, obs = simTarget(ctx, char, name)
	if not entry then
		return { "Not simulated: " .. err .. "." }
	end
	local play = NarrativeClock.Current(char, ctx)
	local copy = Util.DeepCopy(char)
	local centry = copy.story.places[Places.Key(entry.zone, entry.subzone)]
	-- As if the character left right after its last visit and has played long
	-- enough away; earlier returns no longer count against the narrative week.
	local away = Places.RETURN_AFTER_DAYS * NarrativeClock.DayLength(copy) + 60
	centry.lastPlay = math.max(0, play - away)
	centry.returnedPlay = nil
	local lines = { string.format("Simulating a return to %s after %s of play away, on a copy of your data.",
		Places.Label(entry), duration(play - centry.lastPlay)) }
	if play < away then
		-- Too little play so far to be away that long: the copy plays the difference.
		play = away
	end
	simulateArrival(lines, ctx, copy, entry, obs, now, play)
	lines[#lines + 1] = SAVED_NOTHING
	return lines
end

--- Lines for /dawnward dev story simulate time <amount> [place]: plays the
-- amount on a copy (as if the character left the place now), then arrives.
function StoryDiagnostics.SimulateTimeLines(ctx, rest)
	local now = ctx.now()
	local char = ctx.store.real.characters[ctx.characterKey]
	if not char then
		return { "This character has no Dawnward record yet, so there is nothing to simulate." }
	end
	local amountText, name = Util.NextWord(rest or "")
	local amount = StoryDiagnostics.ParseAmount(char, amountText)
	if not amount then
		return { "Usage: /dawnward dev story simulate time <n>m|h|d [place]   (d = narrative days)" }
	end
	local entry, err, obs = simTarget(ctx, char, name)
	if not entry then
		return { "Not simulated: " .. err .. "." }
	end
	local play = NarrativeClock.Current(char, ctx)
	local copy = Util.DeepCopy(char)
	local centry = copy.story.places[Places.Key(entry.zone, entry.subzone)]
	-- Leaving the place now: absence starts here (a place logged before the
	-- clock existed starts counting now, as it would in play).
	centry.lastPlay = centry.lastPlay and math.min(centry.lastPlay, play) or play
	local later = play + amount
	copy.story.clock.played = later
	local lines = {
		string.format("Simulating %s more play, then arriving at %s, on a copy of your data.", duration(amount),
			Places.Label(entry)),
	}
	for _, line in ipairs(StoryDiagnostics.ClockLines({}, copy, later)) do lines[#lines + 1] = "After: " .. line end
	simulateArrival(lines, ctx, copy, entry, obs, now, later)
	lines[#lines + 1] = SAVED_NOTHING
	return lines
end

ns.SetupCommands.DEV_AREAS.story = {
	usage = "dev story status | dev story simulate [place] | dev story simulate time <n>m|h|d [place]",
	run = function(ctx, rest)
		local word, tail = Util.NextWord(rest or "")
		word = word:lower()
		local lines
		if word == "status" then
			lines = StoryDiagnostics.StatusLines(ctx)
		elseif word == "simulate" then
			local sub, more = Util.NextWord(tail or "")
			if sub:lower() == "time" then
				lines = StoryDiagnostics.SimulateTimeLines(ctx, more)
			else
				lines = StoryDiagnostics.SimulateLines(ctx, tail)
			end
		else
			lines = { "Developer commands: /dawnward dev story status | dev story simulate [place] | "
				.. "dev story simulate time <n>m|h|d [place]" }
		end
		for _, line in ipairs(lines) do out(ctx, line) end
	end,
}
