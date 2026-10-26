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
		local visit = record.meta.visit
		if visit == "start" then
			line = string.format("The journey begins in %s%s (a known starting area).", record.zone, level)
		elseif visit == "firstseen" then
			line = string.format("First recorded in %s%s (where Dawnward's record of this character begins).",
				record.zone, level)
		else
			line = string.format("Arrived in %s%s (the first visit Dawnward recorded).", record.zone, level)
		end
	elseif record.category == "place" then
		local m = record.meta
		local where = m.placeName or record.zone
		if record.subzone and record.zone and record.zone ~= where then
			where = where .. ", " .. record.zone
			level = level ~= "" and ("," .. level) or level
		end
		if m.visit == "start" then
			line = string.format("The journey begins in %s%s (a known starting area).", where, level)
		elseif m.visit == "firstseen" then
			line = string.format("First recorded at %s%s.", where, level)
		elseif m.visit == "return" then
			line = string.format("Returned to %s%s%s.", where, level,
				m.meaningful == 1 and " (a place you marked as meaningful)"
				or m.linked == 1 and " (a place tied to one of your memories)" or "")
		else
			line = string.format("Reached %s%s (the first visit Dawnward recorded).", where, level)
		end
	elseif record.category == "instance" then
		line = string.format("Entered %s%s (the first entry Dawnward recorded).", plain(record.meta.instanceName), level)
	elseif record.category == "guild" then
		line = string.format("%s %s.", record.meta.title == "left" and "Left" or "Joined", plain(record.meta.guildName))
	elseif record.category == "moment" then
		line = string.format("A moment you recorded%s: %s.", zone, plain(record.meta.title))
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
		return record.meta.visit == "start" and ("The journey begins: " .. record.zone) or record.zone
	elseif record.category == "place" then
		local name = record.meta.placeName or record.zone
		if record.meta.visit == "start" then
			return "The journey begins: " .. name
		elseif record.meta.visit == "return" then
			return "Back in " .. name
		end
		return name
	elseif record.category == "instance" then
		return plain(record.meta.instanceName)
	elseif record.category == "guild" then
		return plain(record.meta.guildName)
	elseif record.category == "moment" then
		return plain(record.meta.title)
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
	-- The proposed development only. Its approval status changes later, so it
	-- is never written into the text: the journal shows the current status
	-- next to it (Narrative.DisplayText).
	local changes = args.changes or {}
	if #changes > 0 then
		local described = {}
		for _, change in ipairs(changes) do
			described[#described + 1] = Evolution.Describe(change)
		end
		parts[#parts + 1] = string.format("Development: %s.", table.concat(described, ", "))
	end
	return { title = titleFor(args.record), text = table.concat(parts, "\n\n") }
end

local STATUS_WORDS = { pending = "waiting for your approval", applied = "approved", rejected = "rejected",
	reversed = "reversed" }

--- The text to show for a journal entry. For a story entry whose last
-- paragraph is Dawnward's "Development:" line, that line is shown with the
-- current status of the changes the decision proposed (drafts written
-- before this fix carry a stale "(waiting for your approval)"). Display
-- only: the stored text, approved or not, is never rewritten. Any other
-- text, including the player's own edits, is shown exactly as stored.
function Narrative.DisplayText(char, entry)
	local text = entry.text
	local link = entry.kind == "story" and entry.story
	if not text or not link or not link.decisionId then
		return text
	end
	local head = text:match("^(.*\n\n)Development: [^\n]*$")
	if not head and not text:match("^Development: [^\n]*$") then
		return text
	end
	local described = {}
	for _, change in ipairs(char.story and char.story.changes or {}) do
		if change.decisionId == link.decisionId then
			described[#described + 1] = string.format("%s (%s)", Evolution.Describe(change),
				STATUS_WORDS[change.status] or change.status)
		end
	end
	if #described == 0 then
		return text
	end
	return (head or "") .. "Development: " .. table.concat(described, ", ") .. "."
end
