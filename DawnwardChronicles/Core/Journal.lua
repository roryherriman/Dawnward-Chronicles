-- The character journal: entries the player writes ("note") and milestones
-- recorded from observed game events ("event").
--
-- Entries are stored oldest first. Retention (Schema.JOURNAL): when the
-- journal is full, the oldest automatic entry makes room; entries the player
-- wrote are never removed automatically. Automatic entries can change
-- visibility but cannot be edited or deleted, so the record of what actually
-- happened stays intact.
local _, ns = ...
local Schema, Privacy = ns.Schema, ns.Privacy

local Journal = {}
ns.Journal = Journal

Journal.FULL_MESSAGE = "the journal is full of entries you wrote (limit "
	.. Schema.JOURNAL.limit .. "). Delete or export older entries first."

local function touch(char, now)
	if now then
		char.updatedAt = now
	end
end

function Journal.Find(char, id)
	for index, entry in ipairs(char.journal) do
		if entry.id == id then
			return entry, index
		end
	end
	return nil
end

--- Entries newest first (a new list; the entries themselves are not copied).
function Journal.NewestFirst(char)
	local out = {}
	local list = char.journal
	for i = #list, 1, -1 do
		out[#out + 1] = list[i]
	end
	return out
end

function Journal.Count(char)
	local notes, events = 0, 0
	for _, entry in ipairs(char.journal) do
		if entry.kind == "note" then
			notes = notes + 1
		else
			events = events + 1
		end
	end
	return notes, events
end

-- Frees a slot if the journal is full by removing the oldest automatic entry.
-- Never removes an entry the player wrote. Returns ok, automatic entries removed.
local function makeRoom(char)
	local list = char.journal
	if #list < Schema.JOURNAL.limit then
		return true, 0
	end
	for _, prunable in ipairs({ function(e) return e.kind == "event" end, Schema.IsPrunable }) do
		for index, entry in ipairs(list) do
			if prunable(entry) and not entry.important then
				table.remove(list, index)
				return #list < Schema.JOURNAL.limit, 1
			end
		end
	end
	return false, 0
end

local function append(char, entry)
	entry.id = char.nextId
	char.nextId = char.nextId + 1
	local list = char.journal
	-- Keep chronological order even if the clock moved backwards.
	local last = list[#list]
	if last and entry.createdAt < last.createdAt then
		entry.createdAt = last.createdAt
	end
	list[#list + 1] = entry
	return entry
end

--- values: { title, text, visibility }. Returns entry, prunedCount or nil, error.
function Journal.AddNote(char, values, now)
	local title = Schema.CleanValue(Schema.SHORT, values.title)
	local text = Schema.CleanValue(Schema.LONG, values.text)
	if not title and not text then
		return nil, "the entry is empty"
	end
	local visibility = values.visibility or Privacy.DEFAULT
	if not Privacy.IsValid(visibility) then
		return nil, "visibility must be public, private or secret"
	end
	local ok, pruned = makeRoom(char)
	if not ok then
		return nil, Journal.FULL_MESSAGE
	end
	local entry = append(char, {
		kind = "note", title = title, text = text, visibility = visibility, createdAt = now or 0,
	})
	touch(char, now)
	return entry, pruned
end

--- values: { title, text, visibility }; nil leaves a part unchanged, "" clears title.
function Journal.UpdateNote(char, id, values, now)
	local entry = Journal.Find(char, id)
	if not entry then
		return nil, "no journal entry #" .. tostring(id)
	end
	if entry.kind ~= "note" and entry.kind ~= "story" then
		return nil, "automatic entries cannot be edited (you can change their visibility)"
	end
	local title, text = entry.title, entry.text
	if values.title ~= nil then
		title = Schema.CleanValue(Schema.SHORT, values.title)
	end
	if values.text ~= nil then
		text = Schema.CleanValue(Schema.LONG, values.text)
	end
	if not title and not text then
		return nil, "the entry would be empty"
	end
	if values.visibility ~= nil and not Privacy.IsValid(values.visibility) then
		return nil, "visibility must be public, private or secret"
	end
	if values.visibility == Privacy.PUBLIC and Journal.NeedsApproval(entry) then
		return nil, Journal.APPROVAL_MESSAGE
	end
	entry.title, entry.text = title, text
	if values.visibility ~= nil then
		entry.visibility = values.visibility
	end
	entry.updatedAt = now or 0
	touch(char, now)
	return entry
end

Journal.APPROVAL_MESSAGE = "this is an unapproved story draft; approve it before making it public"

--- Story drafts are written by Dawnward, so they stay private until approved.
function Journal.NeedsApproval(entry)
	return entry.kind == "story" and entry.status ~= "approved"
end

function Journal.SetVisibility(char, id, level, now)
	if not Privacy.IsValid(level) then
		return nil, "visibility must be public, private or secret"
	end
	local entry = Journal.Find(char, id)
	if not entry then
		return nil, "no journal entry #" .. tostring(id)
	end
	if level == Privacy.PUBLIC and Journal.NeedsApproval(entry) then
		return nil, Journal.APPROVAL_MESSAGE
	end
	entry.visibility = level
	touch(char, now)
	return entry
end

function Journal.RemoveNote(char, id, now)
	local entry, index = Journal.Find(char, id)
	if not entry then
		return nil, "no journal entry #" .. tostring(id)
	end
	if entry.kind ~= "note" and entry.kind ~= "story" then
		return nil, "automatic entries cannot be deleted"
	end
	table.remove(char.journal, index)
	touch(char, now)
	return entry
end

--- Records an observed milestone (built by Milestones). Returns entry, prunedCount,
-- or nil plus "duplicate" / "invalid" / a full-journal message.
function Journal.RecordEvent(char, event, now)
	local meta = Schema.CleanEvent(event)
	local text = Schema.CleanValue(Schema.LONG, event and event.text)
	if not meta or not text then
		return nil, "invalid"
	end
	if char.journalKeys[meta.key] then
		return nil, "duplicate"
	end
	local ok, pruned = makeRoom(char)
	if not ok then
		return nil, Journal.FULL_MESSAGE
	end
	local entry = append(char, {
		kind = "event", text = text, event = meta, visibility = Privacy.DEFAULT, createdAt = now or 0,
	})
	char.journalKeys[meta.key] = now or 0
	Schema.CapJournalKeys(char.journalKeys)
	touch(char, now)
	return entry, pruned
end

--- Adds a private story draft written from a decision (Core/Narrative.lua).
-- values: { title, text, story = { category, decisionId, eventKey } }.
-- Returns entry, prunedCount or nil, error.
function Journal.AddStoryDraft(char, values, now)
	local title = Schema.CleanValue(Schema.SHORT, values.title)
	local text = Schema.CleanValue(Schema.LONG, values.text)
	if not title and not text then
		return nil, "the entry is empty"
	end
	local ok, pruned = makeRoom(char)
	if not ok then
		return nil, Journal.FULL_MESSAGE
	end
	local link = values.story or {}
	local entry = append(char, {
		kind = "story", title = title, text = text, status = "draft", visibility = Privacy.PRIVATE,
		createdAt = now or 0,
		story = { category = link.category, decisionId = link.decisionId, eventKey = link.eventKey },
	})
	touch(char, now)
	return entry, pruned
end

--- The player approves a story draft as part of their character's record.
-- Approval does not publish it; visibility stays as it is until changed.
function Journal.Approve(char, id, now)
	local entry = Journal.Find(char, id)
	if not entry then
		return nil, "no journal entry #" .. tostring(id)
	end
	if entry.kind ~= "story" then
		return nil, "only story entries need approval"
	end
	entry.status = "approved"
	entry.updatedAt = now or 0
	touch(char, now)
	return entry
end

--- Marks any entry as an important memory (a defining moment), or unmarks it.
function Journal.SetImportant(char, id, on, now)
	local entry = Journal.Find(char, id)
	if not entry then
		return nil, "no journal entry #" .. tostring(id)
	end
	entry.important = on and true or nil
	touch(char, now)
	return entry
end

--- Entries matching a filter, newest first.
-- filter: { text = substring (case-insensitive), kind = "note"|"event"|"story",
--   visibility = level, important = true, status = "draft"|"approved" }
function Journal.Search(char, filter)
	filter = filter or {}
	local needle = filter.text and filter.text ~= "" and filter.text:lower() or nil
	local out = {}
	for i = #char.journal, 1, -1 do
		local e = char.journal[i]
		local ok = (not filter.kind or e.kind == filter.kind)
			and (not filter.visibility or e.visibility == filter.visibility)
			and (not filter.important or e.important == true)
			and (not filter.status or e.status == filter.status)
		if ok and needle then
			local hay = ((e.title or "") .. "\n" .. (e.text or "")):lower()
			ok = hay:find(needle, 1, true) ~= nil
		end
		if ok then
			out[#out + 1] = e
		end
	end
	return out
end
