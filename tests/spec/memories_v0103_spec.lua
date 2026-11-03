-- L1/L2 (v0.10.3): Dawnward remembers what happened; the player decides
-- what it meant. Verified gameplay records are kept automatically and
-- worded neutrally (Core/Memories.lua over Core/GameEvents.lua); the
-- player's Story Director answer is kept faithfully as established;
-- interpretations stay suggestions with their support shown (Accept, Edit,
-- Later, Dismiss); profile suggestions count only approved development.
local Loader = require("support.loader")

return function(t, expect)
	local NOW = 1761000000

	local function setup(pronouns)
		local ns = Loader.WithTRP3()
		local char = ns.Schema.NewCharacter(1)
		char.fields.name = { value = "Kyssarra Dawnward", visibility = "public" }
		if pronouns ~= false then
			char.fields.pronouns = { value = pronouns or "She/Her", visibility = "public" }
		end
		return ns, char
	end

	-- Records an event and asks about it at once (pacing reset).
	local function ask(ns, char, category, data, at)
		char.story.pacing.playByCategory, char.story.pacing.lastByCategory = {}, {}
		char.story.pacing.recentTemplates, char.story.pacing.asked = {}, {}
		local record = assert(ns.GameEvents.Record(char, category, data, at))
		return record, (ns.Reactions.Consider(char, record, at, at))
	end

	local function count(list, status)
		local n = 0
		for _, r in ipairs(list) do if not status or r.status == status then n = n + 1 end end
		return n
	end

	local FEELINGS = { "felt", "feel", "pride", "proud", "relish", "curious", "fear", "afraid", "brave", "hope",
		"wanted", "glad", "sad", "angry", "believ", "resolve" }
	local function neutral(text)
		local lower = text:lower()
		for _, w in ipairs(FEELINGS) do
			if lower:find(w, 1, true) then return false, w end
		end
		return true
	end

	t:describe("verified gameplay records", function()
		t:it("are recorded automatically, in neutral words, with nothing to approve", function()
			local ns, char = setup()
			local M = ns.Memories
			assert(ns.GameEvents.Record(char, "levelup", { level = 4, zone = "Elwynn Forest" }, NOW))
			local five = assert(ns.GameEvents.Record(char, "levelup", { level = 5, zone = "Elwynn Forest" }, NOW + 1))
			local recorded = M.Recorded(char)
			expect.equal(#recorded, 1, "level 4 is routine: it stays in the history only")
			expect.equal(recorded[1], five)
			expect.equal(M.RecordedText(char, five), "Kyssarra Dawnward reached level 5 in Elwynn Forest.")
			expect.equal(M.RecordedTitle(five), "Level 5")
			expect.equal(#char.story.memories, 0, "never copied into memories: nothing to accept")
			expect.equal(char.profileSuggestions, nil, "no profile suggestion from a level")
			expect.truthy(neutral(M.RecordedText(char, five)))
		end)

		t:it("say only what was reported: a missing zone or title is left out, never guessed", function()
			local ns, char = setup()
			local M = ns.Memories
			local five = assert(ns.GameEvents.Record(char, "levelup", { level = 5 }, NOW))
			expect.equal(M.RecordedText(char, five), "Kyssarra Dawnward reached level 5.")
			local q = assert(ns.GameEvents.Record(char, "quest", { questId = 9, zone = "Westfall", level = 10,
				questLevel = 13 }, NOW + 1))
			expect.equal(q.significance, 3, "first in a zone and well above level: defining")
			expect.equal(M.RecordedText(char, q), "Kyssarra Dawnward completed a quest in Westfall.")
			local named = assert(ns.GameEvents.Record(char, "quest", { questId = 10, title = "The Defias Brotherhood",
				zone = "Westfall", level = 10, questLevel = 14 }, NOW + 2))
			expect.equal(named.significance, 2)
			expect.falsy(M.IsRecorded(named), "a notable quest stays in the history")
			local death = assert(ns.GameEvents.Record(char, "death", { zone = "Duskwood", level = 12 }, NOW + 3))
			expect.equal(M.RecordedText(char, death), "Kyssarra Dawnward fell in Duskwood, and came back.")
			local dungeon = assert(ns.GameEvents.Record(char, "instance", { instanceName = "The Deadmines",
				instanceType = "party", zone = "Westfall", level = 18 }, NOW + 4))
			expect.equal(M.RecordedText(char, dungeon),
				"Kyssarra Dawnward entered The Deadmines (the first entry Dawnward recorded).")
			local rep = assert(ns.GameEvents.Record(char, "reputation", { factionId = 72, factionName = "Stormwind",
				standing = 6, previous = 5 }, NOW + 5))
			expect.equal(M.RecordedText(char, rep), "Kyssarra Dawnward reached Honored standing with Stormwind.")
			for _, e in ipairs(M.Recorded(char)) do
				local ok, word = neutral(M.RecordedText(char, e))
				expect.truthy(ok, "no feeling claimed: " .. tostring(word))
			end
			local nameless = ns.Schema.NewCharacter(1)
			local e = assert(ns.GameEvents.Record(nameless, "levelup", { level = 10 }, NOW))
			expect.equal(M.RecordedText(nameless, e), "Your character reached level 10.")
		end)

		t:it("are never duplicated, across reloads too", function()
			local ns, char = setup()
			assert(ns.GameEvents.Record(char, "levelup", { level = 10, zone = "Westfall" }, NOW))
			local _, err = ns.GameEvents.Record(char, "levelup", { level = 10, zone = "Westfall" }, NOW + 50)
			expect.equal(err, "duplicate")
			local reloaded = ns.Schema.NormalizeCharacter(ns.Util.DeepCopy(char))
			local _, again = ns.GameEvents.Record(reloaded, "levelup", { level = 10, zone = "Westfall" }, NOW + 99)
			expect.equal(again, "duplicate", "the key outlives the session")
			expect.equal(#ns.Memories.Recorded(reloaded), 1)
			expect.deepEqual(ns.Memories.Recorded(reloaded)[1], ns.Memories.Recorded(char)[1])
		end)

		t:it("outlast routine events when the event list is full", function()
			local ns, char = setup()
			local limit = ns.StorySchema.LIMITS.events
			assert(ns.GameEvents.Record(char, "levelup", { level = 10 }, 1))
			for i = 1, limit do
				assert(ns.GameEvents.Record(char, "quest", { questId = 1000 + i, title = "Q" .. i, level = 10 }, 1 + i))
			end
			expect.equal(#char.story.events, limit)
			expect.truthy(ns.GameEvents.Find(char, "levelup:10"), "the milestone is kept; a routine quest made room")
			expect.equal(ns.GameEvents.Find(char, "quest:1001"), nil)
		end)
	end)

	t:describe("the player's Story Director answer", function()
		t:it("is kept faithfully as established, linked to its decision, event and draft; the draft stays a draft",
			function()
			local ns, char = setup()
			local record, reaction = ask(ns, char, "levelup", { level = 5, zone = "Elwynn Forest" }, NOW)
			local result = assert(ns.Decisions.Decide(char, reaction.id, { optionId = "freedom" }, NOW + 1))
			local m = result.memory
			expect.equal(m.status, "established", "no second confirmation")
			expect.equal(m.kind, "answer")
			expect.equal(m.provenance, "player")
			expect.equal(m.visibility, "private", "an answer is never published by itself")
			expect.equal(m.title, "Level 5")
			expect.equal(m.text, "Kyssarra Dawnward has grown stronger (level 5). What does that strength mean to her? "
				.. "Kyssarra Dawnward answered: \"Freedom: fewer people can tell her what to do.\"")
			expect.deepEqual(m.links.decisions, { result.decision.id })
			expect.deepEqual(m.links.events, { record.key })
			expect.deepEqual(m.links.journal, { result.entry.id })
			expect.equal(result.entry.status, "draft", "the journal draft still waits for approval")
			expect.equal(result.changes[1].status, "pending", "the personality change still waits for approval")
			expect.equal(result.reflection, nil, "a notable level suggests no interpretation")
			expect.equal(count(char.story.memories, "proposed"), 0, "nothing waits")
			-- One entry for the level: the answer, showing the recorded fact it rests on.
			expect.deepEqual(ns.Memories.Recorded(char), {})
			expect.equal(ns.Memories.Basis(char, m), "Recorded: Kyssarra Dawnward reached level 5 in Elwynn Forest.")
			-- The answer in the player's chosen words; the draft is still only a draft.
			expect.truthy(m.text:find("\"Freedom: fewer people can tell her what to do.\"", 1, true))
		end)

		t:it("keeps the player's own words exactly, and nothing for 'nothing worth remembering'", function()
			local ns, char = setup()
			local _, reaction = ask(ns, char, "levelup", { level = 5, zone = "Elwynn Forest" }, NOW)
			local own = assert(ns.Decisions.Decide(char, reaction.id, { custom = "I swore to Brother Sammuel." }, NOW))
			expect.equal(own.memory.text, "I swore to Brother Sammuel.")
			expect.equal(own.memory.status, "established")
			expect.equal(own.reflection, nil, "her own words are never interpreted")
			local _, again = ask(ns, char, "levelup", { level = 10, zone = "Westfall" }, NOW + 10)
			local nothing = assert(ns.Decisions.Decide(char, again.id, { optionId = "nothing" }, NOW + 11))
			expect.equal(nothing.memory, nil)
			expect.equal(nothing.reflection, nil)
		end)

		t:it("is kept once per decision", function()
			local ns, char = setup()
			local _, reaction = ask(ns, char, "levelup", { level = 5, zone = "Elwynn Forest" }, NOW)
			local result = assert(ns.Decisions.Decide(char, reaction.id, { optionId = "freedom" }, NOW + 1))
			local args = { significance = 2, title = "Level 5", option = { text = "x", phrase = "x", meaning = "y" },
				name = "Kyssarra Dawnward", decisionId = result.decision.id, eventKeys = { "levelup:5" } }
			local again = ns.Memories.FromDecision(char, args, NOW + 2)
			expect.equal(again, result.memory, "the same record, not a second one")
			expect.equal(#char.story.memories, 1)
		end)

		t:it("does not make a place a story tie or a Director memory by itself", function()
			local ns, char = setup()
			local _, reaction = ask(ns, char, "levelup", { level = 5, zone = "Elwynn Forest" }, NOW)
			assert(ns.Decisions.Decide(char, reaction.id, { optionId = "freedom" }, NOW + 1))
			expect.falsy(ns.Places.Linked(char.story, { zone = "Elwynn Forest" }))
			expect.deepEqual(ns.Director.Context(char, nil, nil).memories, {})
		end)
	end)

	t:describe("narrative interpretations", function()
		local function defining(ns, char)
			local _, reaction = ask(ns, char, "levelup", { level = 10, zone = "Westfall" }, NOW)
			return assert(ns.Decisions.Decide(char, reaction.id, { optionId = "burden" }, NOW + 1))
		end

		t:it("are suggested only for a defining answer, private and proposed, showing what they rest on", function()
			local ns, char = setup()
			local result = defining(ns, char)
			local r = result.reflection
			expect.truthy(r, "level 10 is defining")
			expect.equal(r.status, "proposed")
			expect.equal(r.provenance, "suggested")
			expect.equal(r.visibility, "private")
			expect.equal(r.kind, "reflection")
			expect.equal(r.title, "Level 10")
			expect.equal(r.text, "Strength has a cost she feels.")
			expect.deepEqual(r.links.memories, { result.memory.id })
			expect.equal(ns.Memories.Basis(char, r),
				"From your answer: Kyssarra Dawnward has grown stronger (level 10). What does that strength mean to her? "
					.. "Kyssarra Dawnward answered: \"A weight she never asked for.\"")
			local _, err = ns.Memories.SetVisibility(char, r.id, "public", NOW)
			expect.truthy(err, "never public before it is accepted")
			expect.falsy(ns.Projection.GetPublic(char).memories, "nothing of it reaches the profile")
		end)

		t:it("Accept, Edit, Later and Dismiss", function()
			local ns, char = setup()
			local M = ns.Memories
			local r = defining(ns, char).reflection
			-- Later: still a suggestion, after the others.
			local other = assert(M.Add(char, { title = "Another", text = "x" }, "suggested", NOW + 5))
			assert(M.Later(char, r.id, NOW + 6))
			expect.equal(r.status, "proposed")
			expect.equal(r.laterAt, NOW + 6)
			expect.equal(M.Suggestions(char)[1], other)
			expect.equal(M.Suggestions(char)[2], r)
			local again = ns.Schema.NormalizeCharacter(ns.Util.DeepCopy(char))
			expect.equal(ns.Memories.Find(again, r.id).laterAt, NOW + 6, "Later survives a reload")
			-- Accept: established, no longer waiting.
			assert(M.Accept(char, r.id, NOW + 7))
			expect.equal(r.status, "established")
			expect.equal(r.laterAt, nil)
			expect.truthy(select(2, M.Later(char, r.id, NOW + 8)), "an established memory cannot wait")
			expect.truthy(select(2, M.Dismiss(char, r.id)), "an established memory is never dismissed")
			-- Edit: the player's own words.
			assert(M.Edit(char, other.id, { text = "In my words." }, NOW + 9))
			expect.equal(other.provenance, "player")
			-- Dismiss: gone, the answer it rested on stays.
			assert(M.Dismiss(char, other.id))
			expect.equal(M.Find(char, other.id), nil)
		end)

		t:it("never come from routine levels or quests: no backlog", function()
			local ns, char = setup()
			for level = 2, 9 do
				local _, reaction = ask(ns, char, "levelup", { level = level, zone = "Elwynn Forest" }, NOW + level * 10)
				if reaction then assert(ns.Decisions.Decide(char, reaction.id, { optionId = "freedom" }, NOW + level * 10)) end
			end
			for id = 1, 8 do
				local _, reaction = ask(ns, char, "quest", { questId = id, title = "Q" .. id, zone = "Elwynn Forest",
					level = 5, questLevel = 5 }, NOW + 200 + id)
				if reaction then assert(ns.Decisions.Decide(char, reaction.id, { optionId = "craft" }, NOW + 200 + id)) end
			end
			expect.truthy(#char.story.memories >= 2, "the notable answers (level 5, a first quest) were kept")
			expect.equal(count(char.story.memories, "proposed"), 0, "nothing to sort through")
			for _, m in ipairs(char.story.memories) do expect.equal(m.kind, "answer") end
		end)
	end)

	t:describe("profile suggestions count approved development only (v0.10.2 interaction)", function()
		t:it("a level 10, a quest, a dangerous zone and a defeat suggest nothing subjective", function()
			local ns, char = setup()
			ns.GameEvents.Record(char, "levelup", { level = 10, zone = "Westfall" }, NOW)
			ns.GameEvents.Record(char, "quest", { questId = 5, title = "The Defias Brotherhood", zone = "Westfall",
				level = 10, questLevel = 14 }, NOW + 1)
			ns.GameEvents.Record(char, "instance", { instanceName = "The Deadmines", instanceType = "party",
				zone = "Westfall", level = 18 }, NOW + 2)
			ns.GameEvents.Record(char, "death", { zone = "The Deadmines", level = 18 }, NOW + 3)
			ns.ProfileSuggestions.Generate(char, NOW + 4, { kind = "memory" })
			expect.equal(#ns.ProfileSuggestions.Waiting(char, NOW + 4), 0)
			expect.equal(#char.story.memories, 0)
		end)

		t:it("an answer's own record, or an unaccepted suggestion, is never evidence; an accepted one is", function()
			local ns, char = setup()
			local result
			do
				local _, reaction = ask(ns, char, "levelup", { level = 10, zone = "Westfall" }, NOW)
				result = assert(ns.Decisions.Decide(char, reaction.id, { optionId = "burden" }, NOW + 1))
			end
			expect.equal(result.memory.importance, 3)
			expect.equal(#ns.ProfileSuggestions.Waiting(char, NOW + 2, "glance"), 0,
				"the defining answer's record does not suggest an At First Glance entry")
			ns.ProfileSuggestions.Generate(char, NOW + 2, { kind = "memory", memory = result.reflection })
			expect.equal(#ns.ProfileSuggestions.Waiting(char, NOW + 2, "glance"), 0, "an unaccepted suggestion: nothing")
			assert(ns.Memories.Accept(char, result.reflection.id, NOW + 3))
			local s = ns.ProfileSuggestions.Waiting(char, NOW + 3, "glance")[1]
			expect.truthy(s, "the player accepted it: approved development")
			expect.deepEqual(s.sources.memories, { result.reflection.id })
		end)
	end)

	-- Independent review of v0.10.3 (fixed before merge). Each failed first.
	t:describe("fixed before merge (independent review)", function()
		local function fill(ns, char, n, provenance, kind)
			for i = 1, n do
				assert(ns.Memories.Add(char, { title = (kind or provenance) .. " " .. i, text = "x", kind = kind },
					provenance, NOW - 1000 + i))
			end
		end

		local function ids(char, status)
			local out = {}
			for _, m in ipairs(char.story.memories) do
				if m.status == status then out[#out + 1] = m.id end
			end
			return out
		end

		t:it("an automatic answer never evicts a suggestion or a disputed memory when the list is full", function()
			local ns, char = setup()
			local limit = ns.RecordTypes.LIMITS.memories
			fill(ns, char, limit, "suggested")
			assert(ns.Memories.Dispute(char, char.story.memories[2].id, NOW))
			local proposed, disputed = ids(char, "proposed"), ids(char, "disputed")
			local _, reaction = ask(ns, char, "levelup", { level = 5, zone = "Elwynn Forest" }, NOW)
			local result = assert(ns.Decisions.Decide(char, reaction.id, { optionId = "freedom" }, NOW + 1))
			expect.truthy(result.memory, "answers have room of their own")
			expect.equal(result.memory.kind, "answer")
			expect.deepEqual(ids(char, "proposed"), proposed, "every suggestion is still there")
			expect.deepEqual(ids(char, "disputed"), disputed, "the disputed memory is still there")
			-- A reflection (Dawnward's own suggestion) makes no room either.
			local _, defining = ask(ns, char, "levelup", { level = 10, zone = "Westfall" }, NOW + 10)
			local again = assert(ns.Decisions.Decide(char, defining.id, { optionId = "burden" }, NOW + 11))
			expect.truthy(again.memory)
			expect.equal(again.reflection, nil)
			expect.truthy(again.reflectionError, "the reflection could not be suggested, and says why")
			expect.deepEqual(ids(char, "proposed"), proposed, "still every suggestion")
			-- Reloading keeps everything (the saved limit covers both).
			local reloaded = ns.Schema.NormalizeCharacter(ns.Util.DeepCopy(char))
			expect.equal(#reloaded.story.memories, #char.story.memories)
		end)

		t:it("when answers fill their own room, the answer fails visibly and nothing is deleted", function()
			local ns = Loader.WithTRP3()
			local store = ns.Store.new(ns.Schema.NewDatabase(), ns.Schema.NewDatabase())
			local clock = NOW
			local ctx = { store = store, characterKey = "Kyssarra-Realm",
				now = function() clock = clock + 1; return clock end }
			assert(ns.Actions.SetField(ctx, "name", "Kyssarra Dawnward"))
			local char = ns.Actions.Character(ctx)
			fill(ns, char, ns.RecordTypes.LIMITS.answerMemories, "player", "answer")
			fill(ns, char, 3, "suggested")
			local before = ns.Util.DeepCopy(char.story.memories)
			local _, reaction = ask(ns, char, "levelup", { level = 5, zone = "Elwynn Forest" }, NOW)
			local result, message = ns.Actions.Decide(ctx, reaction.id, { optionId = "freedom" })
			expect.truthy(result, message)
			expect.equal(result.memory, nil)
			expect.truthy(result.memoryError)
			expect.truthy(message:find("not kept in Memories", 1, true), message)
			expect.truthy(message:find("saved with the decision", 1, true), message)
			expect.deepEqual(char.story.memories, before, "no memory was removed or changed")
			expect.equal(char.story.decisions[#char.story.decisions].optionId, "freedom", "the answer itself is saved")
		end)

		t:it("an established answer says only what the player chose: no added feeling", function()
			local ns, char = setup()
			local forms = ns.Pronouns.For(char)
			local L = ns.ReactionLibrary
			local options = {}
			for _, template in ipairs(L.TEMPLATES) do
				for _, o in ipairs(template.options) do options[#options + 1] = o end
				for _, o in pairs(L.FLAVOR[template.category] or {}) do options[#options + 1] = o end
			end
			expect.truthy(#options > 40)
			for _, raw in ipairs(options) do
				local o = ns.Reactions.RenderOption(raw, forms)
				local text = ns.Memories.AnswerText({ option = o, name = "Kyssarra Dawnward" })
				expect.equal(text, "Kyssarra Dawnward answered: \"" .. o.text .. "\"", raw.id)
			end
			local alone
			for _, o in ipairs(L.BY_ID["quest.company"].options) do if o.id == "alone" then alone = o end end
			local text = ns.Memories.AnswerText({ option = ns.Reactions.RenderOption(alone, forms),
				name = "Kyssarra Dawnward", question = "Who was on Kyssarra Dawnward's mind after \"Q\"?" })
			expect.equal(text, "Who was on Kyssarra Dawnward's mind after \"Q\"? Kyssarra Dawnward answered: "
				.. "\"No one. She prefers to work alone.\"")
			expect.falsy(text:find("glad", 1, true))
			-- A Director stance answer: "tested", as chosen, not "felt".
			local stance = ns.Reactions.RenderOption({ id = "stance", text = "It tested the gap between what {they} "
				.. "say{s} about Stormwind and what {they} believe{s}.", phrase = "felt the gap", contextual = true }, forms)
			local said = ns.Memories.AnswerText({ option = stance, name = "Kyssarra Dawnward" })
			expect.truthy(said:find("It tested the gap between what she says about Stormwind", 1, true), said)
			expect.falsy(said:find("felt", 1, true))
			expect.equal(ns.Memories.AnswerText({ option = ns.Reactions.RenderOption(L.NEUTRAL, forms) }), nil)
			expect.equal(ns.Memories.AnswerText({ custom = "My own words.", option = alone }), "My own words.")
		end)

		t:it("answer memories that share an event title are not reported as duplicates", function()
			local ns, char = setup()
			fill(ns, char, 2, "player", "answer")
			char.story.memories[1].title, char.story.memories[2].title = "Stormwind", "Stormwind"
			assert(ns.Memories.Add(char, { title = "A fall in Elwynn Forest", text = "a", kind = "answer" }, "player", NOW))
			assert(ns.Memories.Add(char, { title = "A fall in Elwynn Forest", text = "b", kind = "answer" }, "player", NOW))
			for _, f in ipairs(ns.Continuity.Findings(char)) do
				expect.truthy(f.kind ~= "duplicate", f.message)
			end
			-- The player's own memories are still checked.
			assert(ns.Memories.Add(char, { title = "Stormwind", text = "mine" }, "player", NOW + 1))
			assert(ns.Memories.Add(char, { title = "Stormwind", text = "mine too" }, "player", NOW + 2))
			local dup = 0
			for _, f in ipairs(ns.Continuity.Findings(char)) do
				if f.kind == "duplicate" then dup = dup + 1 end
			end
			expect.equal(dup, 1)
		end)

		t:it("an edited answer stays an answer (edited), never defining evidence, across a reload", function()
			local ns, char = setup()
			local _, reaction = ask(ns, char, "levelup", { level = 10, zone = "Westfall" }, NOW)
			local result = assert(ns.Decisions.Decide(char, reaction.id, { optionId = "burden" }, NOW + 1))
			local m = result.memory
			expect.equal(m.importance, 3)
			assert(ns.Memories.Edit(char, m.id, { text = "A weight she never asked for, typo fixed." }, NOW + 2))
			expect.equal(m.kind, "answer")
			expect.equal(m.edited, true)
			ns.ProfileSuggestions.Generate(char, NOW + 3, { kind = "memory", memory = m })
			expect.equal(#ns.ProfileSuggestions.Waiting(char, NOW + 3, "glance"), 0, "not a memory she marked defining")
			local reloaded = ns.Schema.NormalizeCharacter(ns.Util.DeepCopy(char))
			local again = ns.Memories.Find(reloaded, m.id)
			expect.equal(again.kind, "answer")
			expect.equal(again.edited, true)
			local plain = assert(ns.Memories.Add(char, { title = "Mine", text = "x" }, "player", NOW + 4))
			assert(ns.Memories.Edit(char, plain.id, { text = "y" }, NOW + 5))
			expect.equal(plain.edited, nil, "only an answer needs the mark")
		end)

		t:it("a disputed suggestion does not hide the event it was linked to", function()
			local ns, char = setup()
			local e = assert(ns.GameEvents.Record(char, "levelup", { level = 5, zone = "Elwynn Forest" }, NOW))
			local m = assert(ns.Memories.Add(char, { title = "Level 5", text = "An interpretation.",
				links = { events = { e.key } } }, "suggested", NOW + 1))
			expect.deepEqual(ns.Memories.Recorded(char), {}, "a suggestion tells it while it waits")
			assert(ns.Memories.Dispute(char, m.id, NOW + 2))
			expect.deepEqual(ns.Memories.Recorded(char), { e }, "disputed: the event shows as Recorded again")
		end)

		t:it("an accepted reflection reads as the moment it remembers in At First Glance", function()
			local ns, char = setup()
			local _, reaction = ask(ns, char, "levelup", { level = 10, zone = "Westfall" }, NOW)
			local result = assert(ns.Decisions.Decide(char, reaction.id, { optionId = "burden" }, NOW + 1))
			assert(ns.Memories.Accept(char, result.reflection.id, NOW + 2))
			local s = assert(ns.ProfileSuggestions.Waiting(char, NOW + 2, "glance")[1])
			local text = s.text
			expect.equal(text, "Kyssarra Dawnward carries the memory of \"Level 10\".")
			-- A reflection stored with the older title reads the same, its data untouched.
			local ns2, other = setup()
			local old = assert(ns2.Memories.Add(other, { title = "Reflecting on The Deadmines", text = "y",
				importance = 3, kind = "reflection" }, "suggested", NOW + 3))
			assert(ns2.Memories.Accept(other, old.id, NOW + 4))
			local found = assert(ns2.ProfileSuggestions.Waiting(other, NOW + 4, "glance")[1])
			expect.deepEqual(found.sources.memories, { old.id })
			expect.equal(found.text, "Kyssarra Dawnward carries the memory of \"The Deadmines\".")
			expect.equal(old.title, "Reflecting on The Deadmines")
		end)
	end)
end
