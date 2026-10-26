-- Journal drafts written from gameplay events and the player's decisions.
--
-- Every sentence comes from verified event data or from the player: the
-- authored phrase of the answer they chose, or their own words. Nothing is
-- invented about what a quest was about, who was fought or how it ended.
-- When a detail is unknown it is left out, never guessed. "When" is the
-- entry's own timestamp, shown by the journal.
local _, ns = ...
local GameEvents, Evolution = ns.GameEvents, ns.Evolution

local Narrative = {}
ns.Narrative = Narrative

-- Quest titles come from the game; braces would become TRP3 tags later.
local function plain(s)
	return s and (s:gsub("[{}]", "")) or nil
end

local function happened(record, extra)
	if not record then
		return "Something worth remembering happened."
	end
	local zone = record.zone and (" in " .. record.zone) or ""
	local level = record.level and string.format(" at level %d", record.level) or ""
	local line
	if record.category == "quest" then
		local title = plain(record.meta.title)
		line = title and string.format("Completed \"%s\"%s%s.", title, zone, level)
			or string.format("Completed a quest%s%s.", zone, level)
		if extra > 0 then
			line = line .. string.format(" Also completed %d more %s there.", extra, extra == 1 and "quest" or "quests")
		end
	elseif record.category == "levelup" then
		line = string.format("Reached level %d%s.", record.level or 0, zone)
	elseif record.category == "death" then
		line = string.format("Fell%s%s, and came back.", zone, level)
	elseif record.category == "reputation" then
		local m = record.meta
		line = string.format("Reached %s standing with %s.", GameEvents.STANDINGS[m.standing] or "a new",
			plain(m.factionName) or "a faction")
	elseif record.category == "zone" then
		line = string.format("Arrived in %s%s (the first visit Dawnward recorded).", record.zone, level)
	elseif record.category == "instance" then
		line = string.format("Entered %s%s (the first entry Dawnward recorded).", plain(record.meta.instanceName), level)
	elseif record.category == "guild" then
		line = string.format("%s %s.", record.meta.title == "left" and "Left" or "Joined", plain(record.meta.guildName))
	else
		line = GameEvents.Label(record.category) .. "."
	end
	return line
end

local function titleFor(record)
	if not record then
		return "A moment"
	end
	if record.category == "quest" then
		local title = plain(record.meta.title)
		return title or (record.zone and ("A task in " .. record.zone)) or "A task completed"
	elseif record.category == "levelup" then
		return string.format("Level %d", record.level or 0)
	elseif record.category == "death" then
		return record.zone and ("A fall in " .. record.zone) or "A fall"
	elseif record.category == "reputation" then
		return plain(record.meta.factionName) or "A change in standing"
	elseif record.category == "zone" then
		return record.zone
	elseif record.category == "instance" then
		return plain(record.meta.instanceName)
	elseif record.category == "guild" then
		return plain(record.meta.guildName)
	end
	return GameEvents.Label(record.category)
end

--- Builds { title, text } for a decision.
-- args: { name, record, extra (coalesced count), option?, custom?, changes = { change, ... }, approval }
function Narrative.Draft(args)
	local parts = { happened(args.record, args.extra or 0) }
	if args.custom then
		parts[#parts + 1] = string.format("In %s's own words: %s", args.name, args.custom)
	elseif args.option then
		parts[#parts + 1] = string.format("%s %s.", args.name, args.option.phrase)
		if args.option.meaning then
			parts[#parts + 1] = args.option.meaning
		end
	end
	local changes = args.changes or {}
	if #changes > 0 then
		local described = {}
		for _, change in ipairs(changes) do
			described[#described + 1] = Evolution.Describe(change)
		end
		local applied = changes[1].status == "applied"
		parts[#parts + 1] = string.format("Development: %s%s.", table.concat(described, ", "),
			applied and "" or " (waiting for your approval)")
	end
	return { title = titleFor(args.record), text = table.concat(parts, "\n\n") }
end
