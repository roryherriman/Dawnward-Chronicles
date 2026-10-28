-- Developer diagnostics for the Story Director's place moments
-- (development builds only, under /dawnward dev story):
--
--   dev story status            where you are, how the place is tied to the
--                               story, whether a return here can count, the
--                               location cooldown, and why the last arrival
--                               this session did or did not ask
--   dev story simulate [place]  runs a return to the place (default: here)
--                               after a full absence, on a copy of the
--                               character, and shows what would happen
--
-- Read-only: status only reads; simulate works on a deep copy that is
-- discarded, so no place, event, cooldown, moment or journal entry changes.
local _, ns = ...
local Util, Commands, Places, Reactions, Director, GameEvents =
	ns.Util, ns.Commands, ns.Places, ns.Reactions, ns.Director, ns.GameEvents

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
		return string.format("last recorded here %s ago; a return counts only after %s away (%s more)",
			duration(info.away), duration(Places.RETURN_AFTER), duration(info.wait))
	elseif why == "weekly" then
		return string.format("a return here was already recorded within the week; next possible in %s",
			duration(info.wait))
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

local function cooldownLine(char, now)
	local prefs, pacing = char.story.prefs, char.story.pacing
	if prefs.frequency == "off" then
		return "Location cooldown: story prompts are off."
	end
	if prefs.places == "off" then
		return "Location cooldown: place moments are off."
	end
	local a, b = pacing.lastByCategory.zone, pacing.lastByCategory.place
	local last = a and b and math.max(a, b) or a or b
	local cooldown = Reactions.COOLDOWN[prefs.frequency]
	if not last or now - last >= cooldown then
		return string.format("Location cooldown: ready (%s between place moments at '%s').", duration(cooldown),
			prefs.frequency)
	end
	return string.format("Location cooldown: %s left of %s (last place moment %s ago). Urgent places skip it.",
		duration(cooldown - (now - last)), duration(cooldown), duration(now - last))
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
			add(string.format("Logged: %d visit%s; last recorded here %s ago.", entry.visits,
				entry.visits == 1 and "" or "s", duration(now - entry.last)))
			add(string.format("Homeland: %s. Marked meaningful: %s. Memory tie: %s.",
				Places.IsHomeland(char, entry) and "yes" or (Places.Tie(char, entry) == "homeland"
					and "yes (named by the Homeland field)" or "no"),
				entry.meaningful and "yes" or "no", Places.Linked(char.story, entry) and "yes" or "no"))
		else
			add("Logged: not yet. The next location update records a first visit.")
		end
		local target, kind2 = Places.ReturnTarget(char, obs.zone, obs.subzone, obs.areaKind, obs.zoneKind)
		if target then
			local ok, why, info = Places.ReturnCheck(char, target, kind2, now)
			add(string.format("Return to %s, if it happened now: %s.", Places.Label(target),
				ok and "would be recorded" or ("not eligible: " .. StoryDiagnostics.ReturnReason(why, info))))
			if info.tie then add("Tied to your story: " .. TIES[info.tie] .. ".") end
			add((relevanceLine(char, returnRecord(char, target, kind2, now))))
		else
			add("Return: " .. StoryDiagnostics.ReturnReason(entry and "ordinary" or "first") .. ".")
		end
	end
	add(cooldownLine(char, now))
	add(string.format("Waiting moments: %d.", #Reactions.List(char, now)))
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

--- Lines for /dawnward dev story simulate [place]: a return to the place
-- after a full absence, run on a copy of the character. Never saves.
function StoryDiagnostics.SimulateLines(ctx, name)
	local now = ctx.now()
	local char = ctx.store.real.characters[ctx.characterKey]
	if not char then
		return { "This character has no Dawnward record yet, so there is nothing to simulate." }
	end
	local obs = here(ctx) or {}
	local entry, err
	if name and Util.Trim(name) ~= "" then
		entry, err = Places.FindByName(char, name)
	else
		entry = obs.zone and (obs.subzone and Places.Entry(char, obs.zone, obs.subzone) or Places.Entry(char, obs.zone))
		err = obs.zone and "Dawnward has not logged this place yet; visit it first, or name one you have visited "
			.. "(/dawnward dev story simulate Goldshire)" or "your location is unknown; name a visited place"
	end
	if not entry then
		return { "Not simulated: " .. err .. "." }
	end

	local copy = Util.DeepCopy(char)
	local key = Places.Key(entry.zone, entry.subzone)
	local centry = copy.story.places[key]
	-- As if the character left right after its last visit and has been away
	-- long enough; earlier returns no longer count against the weekly limit.
	centry.last = now - Places.RETURN_AFTER - 60
	centry.returnedAt = nil
	local sim = {
		zone = centry.zone, subzone = centry.subzone, mapId = centry.mapId, areaId = centry.areaId,
		level = obs.level, class = obs.class, race = obs.race, faction = obs.faction, source = "SIMULATION",
		client = obs.client or (ctx.client and ctx.client.id),
	}
	local lines = { string.format("Simulating a return to %s after %s away, on a copy of your data.",
		Places.Label(entry), duration(now - centry.last)) }
	local function add(text) lines[#lines + 1] = text end
	if entry.subzone and centry.areaId == nil and not Places.Tie(copy, centry) then
		add("Note: this place has no verified area ID, so only the zone can count as a return.")
	end
	local steps, diag = Places.Observe(copy, sim, now)
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
				add(cooldownLine(char, now))
				local reaction, outcome = Reactions.Consider(copy, record, now)
				add("Result: " .. StoryDiagnostics.OutcomeText(outcome) .. ".")
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
	add("Nothing was saved: places, events, cooldowns, waiting moments and the journal are unchanged.")
	return lines
end

ns.SetupCommands.DEV_AREAS.story = {
	usage = "dev story status | dev story simulate [place]",
	run = function(ctx, rest)
		local word, tail = Util.NextWord(rest or "")
		word = word:lower()
		local lines
		if word == "status" then
			lines = StoryDiagnostics.StatusLines(ctx)
		elseif word == "simulate" then
			lines = StoryDiagnostics.SimulateLines(ctx, tail)
		else
			lines = { "Developer commands: /dawnward dev story status | dev story simulate [place]" }
		end
		for _, line in ipairs(lines) do out(ctx, line) end
	end,
}
