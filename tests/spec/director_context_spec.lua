-- L1: the Story Director's use of established context (#20, #25) and
-- repetition control in narrative days. Deterministic; no client needed.
--
-- "No invented content": every question, answer, reason and recollection is
-- checked to be authored text with only verified game data or the player's
-- own words filled in.
local Loader = require("support.loader")

return function(t, expect)
	local DAY = 7200 -- one narrative day at the Standard pace, in seconds of play

	local function setup(name)
		local ns = Loader.Core()
		local char = ns.Schema.NewCharacter(1)
		char.fields.name = { value = name or "Lirael", visibility = "public" }
		return ns, char
	end

	local function rep(ns, char, standing, previous, at)
		return assert(ns.GameEvents.Record(char, "reputation", { factionId = 72, factionName = "Stormwind",
			standing = standing, previous = previous, zone = "Elwynn Forest", level = 20 }, at or 10))
	end

	local function quest(ns, char, id, zone, at)
		return assert(ns.GameEvents.Record(char, "quest", { questId = id, title = "Quest " .. id, zone = zone or "Westfall",
			level = 20, questLevel = 20 }, at or id))
	end

	local function death(ns, char, at, zone)
		return assert(ns.GameEvents.Record(char, "death", { at = at, zone = zone or "Duskwood", level = 25 }, at))
	end

	local function texts(view)
		local out = {}
		for _, o in ipairs(view.options) do out[#out + 1] = o.text end
		return out
	end

	local function has(list, needle)
		for _, v in ipairs(list) do
			if v:find(needle, 1, true) then return true end
		end
		return false
	end

	-- Authored text -> a Lua pattern with one capture per {token} or %s / %d.
	local function pattern(text)
		local p = text:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
		p = p:gsub("{%a+}", "(.-)"):gsub("%%%%s", "(.-)"):gsub("%%%%d", "(%%d+)")
		return "^" .. p .. "$"
	end

	-- Whether text is one of the authored forms with only allowed values filled in.
	local function authored(text, forms, allowed)
		for _, form in ipairs(forms) do
			-- A form without placeholders must match exactly (match would return the whole text).
			local caps = pattern(form):find("(", 1, true) and { text:match(pattern(form)) } or {}
			if #caps > 0 or text == form then
				local ok = true
				for _, c in ipairs(caps) do
					if not allowed[c] then ok = false end
				end
				if ok then return true end
			end
		end
		return false
	end

	-- Reasons the Director may give (Core/Director.lua), as authored.
	local WHY_FORMS = {
		"the quest was level %d and you were level %d", "it was among your first quests in %s",
		"level %d is a milestone", "it was your first recorded fall", "you fell",
		"Dawnward saw your standing with %s change", "your standing with %s rose from %s",
		"your standing with %s fell from %s", "one of your active goals aims for a standing with %s",
		"you have a stance about %s", "it happened in your character's homeland",
		"it happened in a place you marked as meaningful", "one of your memories is tied to where it happened",
		"someone your character knows is connected to where it happened", "you completed it",
		"a new character, first recorded in a known starting area",
		"it is the first place Dawnward recorded for this character", "you came back to %s after some time away",
		"you marked it as meaningful", "one of your memories is tied to it", "it was your first recorded visit to %s",
		"it is a %s", "it is your character's homeland", "one of your active arcs mentions it",
		"one of your active goals mentions it", "someone your character knows is connected to it",
	}
	local CONTEXT_FORMS = {
		"It mattered to their goal: %s.", "It is part of their story: %s.", "It touched on where they stand on %s.",
		"It tested the gap between what they say about %s and what they believe.",
	}

	-- Every word of a presentation is authored or allowed data.
	local function checkAuthored(ns, char, view, extra)
		local r = view.record
		local m = r.meta or {}
		local allowed = { ["this place"] = true, ["where it happened"] = true, ["this faction"] = true }
		for _, v in pairs({ r.zone, r.subzone, m.title, m.placeName, m.factionName, char.fields.name.value,
			r.level and tostring(r.level), m.questLevel and tostring(m.questLevel), "her", "them", "their" }) do
			if v then allowed[v] = true end
		end
		for _, s in ipairs(ns.GameEvents.STANDINGS) do allowed[s] = true end
		for _, kind in pairs(ns.Places.KIND_LABELS) do allowed[kind] = true end
		for _, list in ipairs({ "goals", "arcs" }) do
			for _, rec in ipairs(char.story[list]) do allowed[rec.title] = true end
		end
		for _, i in ipairs(char.story.identity) do allowed[i.subject] = true end
		for k in pairs(extra or {}) do allowed[k] = true end
		local forms = {}
		for _, q in ipairs(view.template.questions) do forms[#forms + 1] = q.text end
		expect.truthy(authored(view.question, forms, allowed), "question is authored: " .. view.question)
		local optionTexts = {}
		for _, o in ipairs(view.template.options) do optionTexts[o.text] = true end
		optionTexts[ns.ReactionLibrary.NEUTRAL.text] = true
		for _, o in ipairs(view.options) do
			expect.truthy(optionTexts[o.text] or o.flavor or authored(o.text, CONTEXT_FORMS, allowed),
				"answer is authored: " .. o.text)
		end
		for _, why in ipairs(view.why) do
			expect.truthy(authored(why, WHY_FORMS, allowed), "reason is authored: " .. why)
		end
		if view.echo then
			local phrases = {}
			for _, tpl in ipairs(ns.ReactionLibrary.TEMPLATES) do
				for _, o in ipairs(tpl.options) do phrases[#phrases + 1] = char.fields.name.value .. " " .. o.phrase end
			end
			expect.truthy(authored(view.echo, phrases, allowed), "echo is the player's chosen phrase: " .. view.echo)
		end
	end

	local function present(ns, char, record, play)
		local reaction = assert(ns.Reactions.Consider(char, record, record.at, play or record.at))
		return ns.Reactions.Present(char, reaction)
	end

	t:describe("Story Director: established context (#20, #25)", function()
		t:it("the same standing change reads differently with a goal and a stance about the faction", function()
			local ns, plain = setup()
			local viewA = present(ns, plain, rep(ns, plain, 6, 5))
			local ns2, story = setup()
			story.story.observed.standings[72] = { standing = 5, name = "Stormwind" }
			local goal = assert(ns2.Goals.Add(story, { title = "Earn a place at court" }, 1))
			assert(ns2.Goals.SetReputationObjective(story, goal.id, "Stormwind", "Exalted", 1))
			assert(ns2.Arcs.Add(story, { title = "An unrelated thread" }, "player", 1))
			assert(ns2.Identity.Add(story, { subject = "Stormwind", persona = "A loyal subject",
				conviction = "Despises the nobility" }, 1))
			local viewB = present(ns2, story, rep(ns2, story, 6, 5))

			expect.equal(viewA.question, "Lirael is now Honored with Stormwind. What does that standing mean to them?")
			expect.equal(viewB.question, "Lirael is now Honored with Stormwind, a faction they have taken a stance on. "
				.. "What does that standing mean to them?")
			expect.truthy(has(viewA.why, "your standing with Stormwind rose from Friendly"))
			expect.falsy(has(viewA.why, "goal"))
			for _, reason in ipairs({ "rose from Friendly", "one of your active goals aims for a standing with Stormwind",
				"you have a stance about Stormwind" }) do
				expect.truthy(has(viewB.why, reason), reason)
			end
			-- The faction's goal and the stance outrank an unrelated arc.
			local b = texts(viewB)
			expect.truthy(has(b, "It mattered to their goal: Earn a place at court."))
			expect.truthy(has(b, "It tested the gap between what they say about Stormwind and what they believe."))
			expect.falsy(has(b, "An unrelated thread"))
			for _, text in ipairs(b) do
				expect.falsy(text:find("Despises", 1, true), "the private conviction is never shown")
			end
			expect.falsy(has(texts(viewA), "goal"))
			checkAuthored(ns, plain, viewA)
			checkAuthored(ns2, story, viewB)
		end)

		t:it("a disputed or removed stance stops mattering at once", function()
			local ns, char = setup()
			local stance = assert(ns.Identity.Add(char, { subject = "Stormwind", persona = "Loyal", conviction = "Loyal" }, 1))
			local view = present(ns, char, rep(ns, char, 6, 5, 10))
			expect.truthy(has(texts(view), "It touched on where they stand on Stormwind."))
			assert(ns.Records.Dispute(char.story.identity, stance.id, 2))
			view = ns.Reactions.Present(char, char.story.reactions[1])
			expect.falsy(has(texts(view), "Stormwind."))
			expect.falsy(has(view.why, "stance"))
			expect.falsy(view.question:find("stance", 1, true))
			assert(ns.Records.Accept(char.story.identity, stance.id, 3))
			expect.truthy(has(texts(ns.Reactions.Present(char, char.story.reactions[1])), "Stormwind."))
			assert(ns.Identity.Remove(char, stance.id))
			view = ns.Reactions.Present(char, char.story.reactions[1])
			expect.falsy(has(texts(view), "Stormwind."))
		end)

		t:it("choosing the stance answer links the decision to the stance and changes none of its words", function()
			local ns, char = setup()
			local stance = assert(ns.Identity.Add(char, { subject = "Stormwind", persona = "Loyal", conviction = "Wary" }, 1))
			local before = ns.Util.DeepCopy(stance)
			local view = present(ns, char, rep(ns, char, 6, 5, 10))
			local option
			for _, o in ipairs(view.options) do if o.stanceId then option = o end end
			local result = assert(ns.Decisions.Decide(char, view.reaction.id, { optionId = option.id }, 11))
			expect.equal(stance.links.decisions[1], result.decision.id)
			expect.equal(stance.persona, before.persona)
			expect.equal(stance.conviction, before.conviction)
			expect.deepEqual(result.changes, {}, "a context answer proposes no personality change")
		end)

		t:it("a return to the homeland uses the authored homeland wording", function()
			local ns, char = setup()
			ns.Director.Roll = function() return 0 end -- the weighted chance always asks here
			char.fields.homeland = { value = "Goldshire", visibility = "private" }
			char.story.places["Elwynn Forest / Goldshire"] = ns.Places.CleanEntry({ zone = "Elwynn Forest",
				subzone = "Goldshire", visits = 2, first = 1, last = 1 })
			local r = assert(ns.GameEvents.Record(char, "place", { zone = "Elwynn Forest", subzone = "Goldshire",
				place = "Goldshire", visit = "return", placeKind = "town", level = 10 }, 50))
			local view = present(ns, char, r, 50)
			expect.equal(view.question, "Lirael has returned to Goldshire, their homeland. Does it feel any different now?")
			checkAuthored(ns, char, view)
		end)

		t:it("a quest in the homeland says so, without naming the people tied to it; elsewhere it does not", function()
			local ns, char = setup()
			char.fields.homeland = { value = "Westfall", visibility = "private" }
			ns.People.Add(char, { name = "Brom", kind = "npc", relation = "Farmer in Westfall" }, 1)
			local view = present(ns, char, quest(ns, char, 1, "Westfall", 5))
			expect.truthy(has(view.why, "it happened in your character's homeland"))
			expect.truthy(has(view.why, "someone your character knows is connected to where it happened"))
			for _, private in ipairs({ "Brom", "Farmer" }) do
				expect.falsy(table.concat(view.why, ";"):find(private, 1, true), private)
			end
			checkAuthored(ns, char, view)
			local ns2, other = setup()
			local view2 = present(ns2, other, quest(ns2, other, 1, "Westfall", 5))
			expect.falsy(has(view2.why, "homeland"))
		end)

		t:it("chooses between equally due templates by the character's established story", function()
			local ns, char = setup()
			local view = present(ns, char, quest(ns, char, 1, "Westfall", 5))
			expect.equal(view.template.id, "quest.meaning", "no history: library order")
			local ns2, social = setup()
			ns2.Memories.Add(social, { title = "The caravan", tags = { "companionship" } }, "player", 1)
			local view2 = present(ns2, social, quest(ns2, social, 1, "Westfall", 5))
			expect.equal(view2.template.id, "quest.company", "a story about companions: the question about company")
			-- A suggestion (proposed) has no influence until the player accepts it.
			local ns3, suggested = setup()
			ns3.Memories.Add(suggested, { title = "The caravan", tags = { "companionship" } }, "suggested", 1)
			expect.equal(present(ns3, suggested, quest(ns3, suggested, 1, "Westfall", 5)).template.id, "quest.meaning")
			-- Starting personality values alone never change the question.
			local ns4, bold = setup()
			bold.personality.sociability = { value = 1, visibility = "private" }
			expect.equal(present(ns4, bold, quest(ns4, bold, 1, "Westfall", 5)).template.id, "quest.meaning")
			-- Approved development on an axis does.
			local ns5, grown = setup()
			grown.story.changes[1] = { id = 99, axis = "sociability", delta = 1, status = "applied", at = 1 }
			expect.equal(present(ns5, grown, quest(ns5, grown, 1, "Westfall", 5)).template.id, "quest.company")
		end)

		t:it("recalls the player's own earlier answer about the same situation", function()
			local ns, char = setup()
			local view = present(ns, char, death(ns, char, 100))
			expect.equal(view.echo, nil, "nothing earlier")
			assert(ns.Decisions.Decide(char, view.reaction.id, { optionId = "defiant" }, 101))
			-- A later fall in the same zone, after the repeat window.
			local later = 100 + 4 * DAY
			local view2 = present(ns, char, death(ns, char, later), later)
			expect.equal(view2.echo, "Lirael came back more determined")
			checkAuthored(ns, char, view2)
			-- A fall elsewhere recalls nothing; an answer in the player's own words is never quoted.
			local elsewhere = present(ns, char, death(ns, char, later + 3000, "Westfall"), later + 3000)
			expect.equal(elsewhere.echo, nil)
		end)
	end)

	t:describe("Story Director: repetition control in narrative days", function()
		t:it("never asks the same question about the same zone twice within the window", function()
			local ns, char = setup()
			death(ns, char, 1) -- the first fall is major and asks; it is a different event key
			for _, r in ipairs(char.story.reactions) do ns.Reactions.Dismiss(char, r.id) end
			char.story.reactions = {}
			local first = death(ns, char, 100)
			expect.truthy((ns.Reactions.Consider(char, first, 100, 100)))
			-- Past the cooldown, still within the window: suppressed, and explained.
			local again = death(ns, char, 200)
			local reaction, outcome = ns.Reactions.Consider(char, again, 200, 100 + 3000)
			expect.equal(reaction, nil)
			expect.equal(outcome, "repeat")
			expect.equal(again.status, "recorded", "the event stays recorded")
			local why = ns.Reactions.lastRepeat[char]
			expect.equal(why.templateId, "death.return")
			expect.equal(why.label, "falling in Duskwood")
			expect.equal(why.ago, 3000)
			-- Another zone is another situation.
			local elsewhere = death(ns, char, 300, "Westfall")
			expect.truthy((ns.Reactions.Consider(char, elsewhere, 300, 100 + 3000 + 2800)))
		end)

		t:it("counts only play: offline time never ends the window, play does", function()
			local ns, char = setup()
			local first = death(ns, char, 100)
			ns.Reactions.Consider(char, first, 100, 1000)
			-- Thirty real days offline, ten minutes of play: still the same situation.
			local offline = death(ns, char, 100 + 30 * 86400)
			local _, outcome = ns.Reactions.Consider(char, offline, 100 + 30 * 86400, 1000 + 2700)
			expect.equal(outcome, "repeat")
			-- Three narrative days of play later it may be asked again.
			local played = death(ns, char, 200 + 30 * 86400)
			local r2, outcome2 = ns.Reactions.Consider(char, played, 200 + 30 * 86400, 1000 + 3 * DAY)
			expect.truthy(r2, tostring(outcome2))
		end)

		t:it("the window follows the setting and the pace; 0 switches it off", function()
			local ns, char = setup()
			ns.Reactions.Consider(char, death(ns, char, 100), 100, 0)
			char.story.prefs.repeatDays = 1
			expect.equal(ns.Reactions.RepeatWindow(char), DAY)
			char.story.prefs.pace = "brisk"
			expect.equal(ns.Reactions.RepeatWindow(char), 3600)
			local r = ns.Reactions.Consider(char, death(ns, char, 200), 200, 3600)
			expect.truthy(r, "one brisk narrative day later")
			char.story.prefs.repeatDays = 0
			expect.equal(ns.Reactions.RepeatWindow(char), 0)
			char.story.reactions = {}
			expect.truthy((ns.Reactions.Consider(char, death(ns, char, 300), 300, 3600 + 2700)), "off")
		end)

		t:it("prefers another authored question about the same zone before staying silent", function()
			local ns, char = setup()
			local asked = {}
			local play = 0
			for id = 1, 3 do
				char.story.pacing.recentTemplates = {}
				char.story.reactions = {}
				local r, outcome = ns.Reactions.Consider(char, quest(ns, char, id, "Westfall", id), id, play)
				asked[id] = r and r.templateId or outcome
				play = play + 2700
			end
			expect.deepEqual(asked, { "quest.meaning", "quest.company", "repeat" })
		end)

		t:it("never asks more often than without it (no frequency regression)", function()
			local function run(days)
				local ns, char = setup()
				char.story.prefs.repeatDays = days
				local queued, play = 0, 0
				for id = 1, 60 do
					local zone = ({ "Westfall", "Duskwood", "Westfall" })[id % 3 + 1]
					local record = id % 4 == 0 and death(ns, char, 1000 + id, zone) or quest(ns, char, id, zone, 1000 + id)
					local r = ns.Reactions.Consider(char, record, 1000 + id, play)
					if r then
						queued = queued + 1
						ns.Reactions.Dismiss(char, r.id)
					end
					play = play + 1500
				end
				return queued
			end
			local without, with = run(0), run(3)
			expect.truthy(with <= without, string.format("%d with repetition control, %d without", with, without))
			expect.truthy(with < without, "repeats were actually suppressed")
		end)

		t:it("is saved additively: cleaned on load, missing on upgrade means nothing is suppressed", function()
			local ns, char = setup()
			char.story.pacing.asked = { { t = "death.return", s = "death:Duskwood", p = 5 }, { t = 7 }, "junk",
				{ t = "quest.meaning", s = "quests:Westfall", p = -1 } }
			char.story.prefs.repeatDays = 99
			local clean = ns.Schema.NormalizeCharacter(char)
			expect.deepEqual(clean.story.pacing.asked, { { t = "death.return", s = "death:Duskwood", p = 5 } })
			expect.equal(clean.story.prefs.repeatDays, 3)
			local old = ns.Schema.NewCharacter(1)
			old.story.pacing.asked = nil
			old.story.prefs.repeatDays = nil
			local upgraded = ns.Schema.NormalizeCharacter(old)
			expect.deepEqual(upgraded.story.pacing.asked, {})
			expect.equal(upgraded.story.prefs.repeatDays, 3)
			expect.equal(ns.Reactions.RepeatOf(upgraded, "death.return", "death:Duskwood", 10), nil)
			-- A reading ahead of the clock (an older backup restored) suppresses nothing.
			clean.story.pacing.asked = { { t = "death.return", s = "death:Duskwood", p = 50000 } }
			expect.equal(ns.Reactions.RepeatOf(clean, "death.return", "death:Duskwood", 10), nil)
		end)

		t:it("explains a suppressed repeat in the developer diagnostics", function()
			local ns, char = setup()
			ns.Reactions.Consider(char, death(ns, char, 100), 100, 100)
			ns.Reactions.Consider(char, death(ns, char, 200), 200, 3000)
			expect.truthy(ns.StoryDiagnostics.OutcomeText("repeat"):find("repeat window", 1, true))
			local lines = table.concat(ns.StoryDiagnostics.RepeatLines(char, 3000, "death:Duskwood", "falling in Duskwood"),
				"\n")
			expect.truthy(lines:find("Repeat window: 3 narrative days (6 h of play)", 1, true), lines)
			expect.truthy(lines:find("Asked about falling in Duskwood: death.return, 48 min of play ago", 1, true), lines)
			expect.truthy(lines:find("Last repeat suppressed this session: Death: the question death.return about "
				.. "falling in Duskwood was asked 48 min of play before", 1, true), lines)
		end)
	end)
end
