-- Memories (#12): what the character remembers, each linked to the events
-- and decisions behind it. The player writes memories directly
-- (established), or accepts the ones Dawnward suggests from significant
-- answers (proposed, private). Nothing becomes a memory just because
-- content was completed: only a decision or the player creates one.
local _, ns = ...
local Records, RecordTypes = ns.Records, ns.RecordTypes

local Memories = {}
ns.Memories = Memories

-- An answer is suggested as a memory when the moment was notable or the
-- player answered in their own words.
Memories.SUGGEST_SIGNIFICANCE = 2

local function list(char)
	return char.story.memories
end

--- values: { title, text, tags, importance, zone, links, visibility }.
function Memories.Add(char, values, provenance, now)
	provenance = provenance or "player"
	local m = Records.New(char.story, provenance, now, values.visibility)
	m.title = Records.Text(values.title, Records.LIMITS.title)
	m.text = Records.Text(values.text, Records.LIMITS.text, true)
	if not m.title and not m.text then
		return nil, "a memory needs a title or some text"
	end
	m.tags = Records.Tags(values.tags)
	m.importance = (values.importance == 2 or values.importance == 3) and values.importance or 1
	m.zone = Records.Text(values.zone, 100)
	m.links = Records.CleanLinks(values.links)
	local clean = RecordTypes.CleanMemory(m)
	if not Records.Append(list(char), clean, RecordTypes.LIMITS.memories) then
		return nil, "the memory list is full of established memories; supersede or remove some first"
	end
	return clean
end

--- Suggests a memory from a decision. Returns the proposed memory or nil.
function Memories.SuggestFromDecision(char, args, now)
	local significance = args.significance or 1
	if significance < Memories.SUGGEST_SIGNIFICANCE and not args.custom then
		return nil
	end
	local record = args.record
	return Memories.Add(char, {
		title = args.title,
		text = args.custom or (args.option and (args.name .. " " .. args.option.phrase .. ".")),
		tags = args.option and args.option.theme and { args.option.theme } or {},
		importance = significance,
		zone = record and record.zone,
		links = { events = args.eventKeys, decisions = { args.decisionId }, journal = { args.journalId } },
	}, "suggested", now)
end

function Memories.Find(char, id) return Records.Find(list(char), id) end
function Memories.Accept(char, id, now) return Records.Accept(list(char), id, now) end
function Memories.Dispute(char, id, now) return Records.Dispute(list(char), id, now) end
function Memories.Supersede(char, id, by, now) return Records.Supersede(list(char), id, by, now) end
function Memories.Remove(char, id) return Records.Remove(list(char), id) end
function Memories.SetVisibility(char, id, level, now) return Records.Visibility(list(char), id, level, now) end

--- The player rewrites a memory in their own words: it becomes player-authored.
function Memories.Edit(char, id, values, now)
	local m = Memories.Find(char, id)
	if not m then return nil, "no memory #" .. tostring(id) end
	local title = values.title ~= nil and Records.Text(values.title, Records.LIMITS.title) or m.title
	local text = values.text ~= nil and Records.Text(values.text, Records.LIMITS.text, true) or m.text
	if not title and not text then return nil, "a memory needs a title or some text" end
	m.title, m.text = title, text
	if values.tags then m.tags = Records.Tags(values.tags) end
	m.provenance = "player"
	m.updatedAt = now or 0
	return m
end

--- Established memories, most important and newest first.
function Memories.Established(char)
	local out = Records.Filter(list(char), { status = "established" })
	table.sort(out, function(a, b)
		if a.importance ~= b.importance then return a.importance > b.importance end
		if a.at ~= b.at then return a.at > b.at end
		return a.id > b.id
	end)
	return out
end
