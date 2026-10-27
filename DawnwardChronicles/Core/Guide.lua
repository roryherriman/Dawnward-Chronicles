-- The guide (#51): a short, optional tour of Dawnward and a searchable help
-- reference. Shown once per character the first time the journal opens,
-- and replayable from the "?" button, Settings or /dawnward guide. It only
-- explains: it never changes story canon, profiles or Total RP 3 data.
--
-- Per character it remembers { done, page } in char.guide (cleaned by
-- Guide.Clean; nothing else is stored).
local _, ns = ...
local Util = ns.Util

local Guide = {}
ns.Guide = Guide

Guide.TOPICS = {
	{ id = "welcome", title = "Welcome", lines = {
		"Dawnward Chronicles keeps a living chronicle of your character: what happens on their travels, the "
			.. "choices you make about it, and who they slowly become.",
		"Everything starts private. Nothing is shared, published or sent to Total RP 3 unless you choose it.",
		"This guide takes a minute. Use Next, or pick a topic on the left. You can reopen it any time from "
			.. "the ? button at the top of the journal, from Settings, or with /dawnward guide.",
	} },
	{ id = "journal", title = "Journal", lines = {
		"The Journal tab holds your character's entries: notes you write, and drafts Dawnward writes from "
			.. "moments you answered.",
		"Drafts only use what really happened and the words you chose. Approve them, edit them, mark the "
			.. "defining ones, or remove them.",
	} },
	{ id = "character", title = "Character", lines = {
		"The Character tab holds the profile: name, homeland, faith, appearance and more, plus family and "
			.. "history. Every field is optional and starts private.",
		"Use Edit beside a field, and the Private / Public / Secret button to choose who may see it. Family and "
			.. "history have their own Add buttons.",
		"Dawnward never decides who your character is from their race, class or faction.",
	} },
	{ id = "story", title = "Story moments", lines = {
		"As you play, Dawnward notices moments: a finished quest, a new level, a fall, a new place. Some of "
			.. "them become a question for you on the Story tab.",
		"Not every moment asks a question. Questions are spaced out by a cooldown, limited by your frequency "
			.. "setting, and held back during combat, cinematics and loading screens. A missing question usually "
			.. "means a cooldown, not a lost moment.",
		"A waiting question can be answered, kept for later, set aside (not now) or dismissed. The minimap "
			.. "button's tooltip says how many are waiting.",
		"Answers may suggest a small change in personality. Nothing changes until you approve it.",
	} },
	{ id = "chronicle", title = "Chronicle", lines = {
		"The Chronicle tab holds your story's threads: memories, arcs, goals, stances (what your character "
			.. "says in public and believes in private) and the people they know.",
		"Use New to add one and Edit to change it. Suggestions from Dawnward stay proposals until you Accept "
			.. "them. Goals are never completed for you: you tick their steps.",
		"The Review tab lists possible contradictions. You decide whether each is growth, an unreliable "
			.. "narrator, a secret, a correction, or nothing.",
	} },
	{ id = "places", title = "Places", lines = {
		"Dawnward logs the towns, inns and other named places your character visits. Logging a visit is "
			.. "quiet; only some visits become a story question.",
		"On the Chronicle's Places tab you can mark a place as meaningful, set it as your Homeland, or write a "
			.. "memory there. Returning to a meaningful place is more likely to prompt a moment.",
		"Place names come from the game. Dawnward never invents where you have been.",
	} },
	{ id = "privacy", title = "Privacy", lines = {
		"Private: only you; included in your personal backups. Secret: only you; left out of backups unless "
			.. "you ask. Public: may be shared through share exports and, if you opt in, Total RP 3.",
		"Suggestions cannot be public until you accept them. Exports for sharing contain public items only.",
	} },
	{ id = "trp3", title = "Total RP 3", lines = {
		"Dawnward complements Total RP 3; it does not replace it. Sync is experimental and off by default.",
		"If you opt in, Dawnward only writes what you made public, takes a backup first, never writes while "
			.. "the TRP3 editor is open, and can roll back. See /dawnward trp3 help.",
	} },
	{ id = "commands", title = "Commands", lines = {
		"Everything above works from the window. Chat commands are optional shortcuts:",
		"/dawnward (or /dwc): open or close the journal. /dawnward guide: this guide.",
		"/dawnward story: waiting questions. /dawnward develop: personality changes to approve.",
		"/dawnward goal add Reach the capital   then   /dawnward goal level 12 20   (goal #12, target level 20)",
		"/dawnward goal milestone 12 Find a ship   then   /dawnward goal done 12 1   (tick step 1)",
		"/dawnward arc add Finding where I belong   then   /dawnward arc turn 7 Left home",
		"/dawnward place mark Goldshire   (mark a place as meaningful)",
		"/dawnward minimap hide | show.  /dawnward help all: every command.",
	} },
}

Guide.BY_ID = {}
for i, topic in ipairs(Guide.TOPICS) do
	topic.index = i
	Guide.BY_ID[topic.id] = topic
end

--- Saved shape: { done = true?, page = 1..#TOPICS? }.
function Guide.Clean(raw)
	if type(raw) ~= "table" then
		return {}
	end
	local page = raw.page
	return {
		done = raw.done == true or nil,
		page = type(page) == "number" and page == math.floor(page) and page >= 1 and page <= #Guide.TOPICS
			and page or nil,
	}
end

--- Whether the guide should open by itself when the journal opens.
function Guide.ShouldAutoOpen(char)
	return not (char and char.guide and char.guide.done)
end

--- Help lines matching every word of the query, across the topics and the
-- command list: { { topic = title, line = text }, ... }. Pure.
function Guide.Search(query, commandLines)
	local words = {}
	for word in (query or ""):lower():gmatch("%S+") do
		words[#words + 1] = word
	end
	local results = {}
	if #words == 0 then
		return results
	end
	local function matches(text)
		local lower = text:lower()
		for _, word in ipairs(words) do
			if not lower:find(word, 1, true) then return false end
		end
		return true
	end
	for _, topic in ipairs(Guide.TOPICS) do
		for _, line in ipairs(topic.lines) do
			if matches(line) then results[#results + 1] = { topic = topic.title, line = line } end
		end
	end
	for _, line in ipairs(commandLines or {}) do
		if matches(line) then results[#results + 1] = { topic = "Commands", line = Util.Trim(line) } end
	end
	return results
end
