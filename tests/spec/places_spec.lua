-- L1/L2: character origins and places (#20, #11, #14). Mocked client and
-- Classic Era IDs from the 1.15.9.70576 client tables; not in-game evidence.
local Loader = require("support.loader")
local Boot = require("support.boot")

return function(t, expect)
	local KEY = "Kyssarra-Test"
	local DAY = 24 * 3600

	-- Words that would claim a backstory the player never wrote.
	local BACKSTORY = { "born", "birth", "home", "grew up", "raised", "native", "childhood", "upbringing", "family",
		"hometown", "loyal" }

	local function setup(opts)
		opts = opts or {}
		local ns = opts.trp3 and Loader.WithTRP3() or Loader.Core()
		-- These specs test what can become a moment; the weighted chance of
		-- asking is tested separately (director_relevance_spec), so here
		-- every eligible place asks.
		if not opts.roll then ns.Director.Roll = function() return 0 end end
		local char = ns.Schema.NewCharacter(1)
		char.fields.name = { value = opts.name or "Kyssarra", visibility = "public" }
		if opts.pronouns ~= false then
			char.fields.pronouns = { value = opts.pronouns or "she/her", visibility = "public" }
		end
		local clock = { now = 100 }
		local ctx = { store = { real = { characters = { [KEY] = char } }, realReadOnly = false }, characterKey = KEY,
			now = function() return clock.now end }
		return ns, char, ctx, clock
	end

	-- A location observation as Platform/Observers builds it.
	local function where(zone, subzone, mapId, areaId, extra)
		local obs = { zone = zone, subzone = subzone, mapId = mapId, areaId = areaId, level = 1, race = "Human",
			class = "PALADIN", faction = "Alliance", client = "classic_era" }
		for k, v in pairs(extra or {}) do obs[k] = v end
		return obs
	end

	local NORTHSHIRE = { "Elwynn Forest", "Northshire Valley", 1429, 9 }
	local GOLDSHIRE = { "Elwynn Forest", "Goldshire", 1429, 87 }
	local STONEFIELD = { "Elwynn Forest", "The Stonefield Farm", 1429, 63 }
	local LAKESHIRE = { "Redridge Mountains", "Lakeshire", 1433, 69 }

	-- These specs model a character that plays the whole time between two
	-- observations: the narrative clock (seconds of play) keeps pace with
	-- the real clock. Offline time is tested in narrative_clock_spec.
	local function observe(ns, ctx, clock, at, place, extra)
		clock.now = at
		local char = ctx.store.real.characters[KEY]
		if char.story.clock.played < at then char.story.clock.played = at end
		return ns.Actions.ObserveLocation(ctx, where(place[1], place[2], place[3], place[4], extra))
	end

	local function present(ns, char, made)
		return assert(ns.Reactions.Present(char, made.reaction))
	end

	local function answer(ns, char, reaction, optionId, at)
		return assert(ns.Decisions.Decide(char, reaction.id, { optionId = optionId }, at))
	end

	local function noBackstory(text)
		local lower = text:lower()
		for _, word in ipairs(BACKSTORY) do
			expect.falsy(lower:find(word, 1, true), string.format("'%s' claims a backstory ('%s')", text, word))
		end
	end

	t:describe("character origins (#20)", function()
		t:it("a new Human in Northshire begins a journey, not an arrival", function()
			local ns, char, ctx, clock = setup()
			local made = observe(ns, ctx, clock, 100, NORTHSHIRE)
			expect.equal(#made, 2, "the named area and the zone are both recorded")
			expect.equal(made[1].record.category, "place")
			expect.equal(made[1].record.meta.visit, "start")
			expect.equal(made[1].record.significance, 3)
			expect.equal(made[1].outcome, "queued")
			expect.equal(made[2].record.meta.visit, "start")
			expect.equal(made[2].record.status, "recorded", "only one question")
			expect.equal(#char.story.reactions, 1)
			local view = present(ns, char, made[1])
			expect.equal(view.question,
				"Every story begins somewhere. As Kyssarra's journey begins in Northshire Valley, what occupies her thoughts?")
			local ids = {}
			for _, o in ipairs(view.options) do ids[#ids + 1] = o.id end
			expect.deepEqual(ids, { "curious", "duty", "uncertain", "ambition", "nothing" })
			noBackstory(view.question)
			for _, o in ipairs(view.options) do noBackstory(o.text); noBackstory(o.phrase) end
			local result = answer(ns, char, made[1].reaction, "duty", 200)
			expect.truthy(result.entry.text:find(
				"The journey begins in Northshire Valley, Elwynn Forest, at level 1 (a known starting area).", 1, true),
				result.entry.text)
			expect.equal(result.entry.title, "The journey begins: Northshire Valley")
			expect.equal(result.entry.visibility, "private")
			noBackstory(result.entry.text)
			expect.truthy(table.concat(view.why, "; "):find("known starting area", 1, true))
		end)

		t:it("level 1 in open country on the starting map begins at the zone, with neutral pronouns", function()
			local ns, char, ctx, clock = setup({ pronouns = false })
			local made = observe(ns, ctx, clock, 100, { "Elwynn Forest", nil, 1429, nil })
			expect.equal(#made, 1)
			expect.equal(made[1].record.category, "zone")
			expect.equal(made[1].record.meta.visit, "start")
			expect.equal(present(ns, char, made[1]).question,
				"Every story begins somewhere. As Kyssarra's journey begins in Elwynn Forest, what occupies their thoughts?")
		end)

		t:it("Orc, Troll, Night Elf, Tauren, Dwarf and Undead starting areas are recognised", function()
			local cases = {
				{ "Orc", { "Durotar", "Valley of Trials", 1411, 363 } },
				{ "Troll", { "Durotar", "The Den", 1411, 364 } },
				{ "NightElf", { "Teldrassil", "Shadowglen", 1438, 188 } },
				{ "Tauren", { "Mulgore", "Camp Narache", 1412, 221 } },
				{ "Dwarf", { "Dun Morogh", "Coldridge Valley", 1426, 132 } },
				{ "Gnome", { "Dun Morogh", "Anvilmar", 1426, 77 } },
				{ "Scourge", { "Tirisfal Glades", "Deathknell", 1420, 154 } },
			}
			for _, case in ipairs(cases) do
				local ns, char, ctx, clock = setup({ pronouns = "they/them" })
				local made = observe(ns, ctx, clock, 100, case[2], { race = case[1] })
				expect.equal(made[1].record.meta.visit, "start", case[1])
				expect.equal(present(ns, char, made[1]).question, string.format(
					"Every story begins somewhere. As Kyssarra's journey begins in %s, what occupies their thoughts?",
					case[2][2]), case[1])
			end
		end)

		t:it("an alternate start is only 'first recorded', never a beginning or a homeland", function()
			-- A level 1 Human in Coldridge Valley (a custom server, or any other start).
			local ns, char, ctx, clock = setup()
			local made = observe(ns, ctx, clock, 100, { "Dun Morogh", "Coldridge Valley", 1426, 132 })
			expect.equal(made[1].record.category, "zone")
			expect.equal(made[1].record.meta.visit, "firstseen")
			expect.equal(made[2].record.meta.visit, "firstseen")
			local view = present(ns, char, made[1])
			expect.equal(view.question, "Your chronicle first records Kyssarra in Dun Morogh. What does this place mean to her?")
			noBackstory(view.question)
			local entry = answer(ns, char, made[1].reaction, "passing", 200).entry
			expect.truthy(entry.text:find("First recorded in Dun Morogh at level 1", 1, true), entry.text)
			expect.falsy(entry.text:find("Arrived", 1, true))
			expect.falsy(entry.text:find("journey begins", 1, true))
		end)

		t:it("an established high-level character is first recorded, not arriving", function()
			local ns, char, ctx, clock = setup()
			local made = observe(ns, ctx, clock, 100, GOLDSHIRE, { level = 40 })
			expect.equal(made[1].record.meta.visit, "firstseen")
			expect.equal(made[1].record.significance, 2)
			expect.equal(present(ns, char, made[1]).question,
				"Your chronicle first records Kyssarra in Elwynn Forest. What does this place mean to her?")
			local entry = answer(ns, char, made[1].reaction, "familiar", 200).entry
			expect.truthy(entry.text:find(
				"First recorded in Elwynn Forest at level 40 (where Dawnward's record of this character begins).", 1, true))
			expect.falsy(entry.text:find("Arrived", 1, true))
			-- Goldshire was the first place seen, so it is never "reached" later.
			expect.equal(made[2].record.key, "place:Elwynn Forest / Goldshire")
			expect.equal(made[2].record.meta.visit, "firstseen")
		end)

		t:it("above the starting level, or on another client, a starting area is not a beginning", function()
			local ns, _, ctx, clock = setup()
			expect.equal(observe(ns, ctx, clock, 100, NORTHSHIRE, { level = 6 })[1].record.meta.visit, "firstseen")
			local ns2, char2, ctx2, clock2 = setup()
			local made = observe(ns2, ctx2, clock2, 100, NORTHSHIRE, { client = "forever" })
			expect.equal(#made, 1, "no verified places on an unchecked client")
			expect.equal(made[1].record.meta.visit, "firstseen")
			expect.equal(char2.story.places["Elwynn Forest / Northshire Valley"].kind, nil)
		end)

		t:it("only the first location ever recorded can be an origin", function()
			local ns, char, ctx, clock = setup()
			observe(ns, ctx, clock, 100, GOLDSHIRE, { level = 40 })
			local made = observe(ns, ctx, clock, 5000, NORTHSHIRE, { level = 40 })
			expect.equal(made[1].record.meta.visit, "first", "a later visit to a starting area is just a visit")
			expect.equal(present(ns, char, made[1]).question,
				"Kyssarra comes to Northshire Valley. What is her impression of it?")
		end)
	end)

	t:describe("places within zones (#11)", function()
		-- Northshire, answered, then on into Elwynn and beyond.
		local function journey()
			local ns, char, ctx, clock = setup()
			local made = observe(ns, ctx, clock, 100, NORTHSHIRE)
			answer(ns, char, made[1].reaction, "curious", 150)
			return ns, char, ctx, clock
		end

		t:it("Goldshire is a settlement, Stonefield is farmland, Lakeshire is a new region", function()
			local ns, char, ctx, clock = journey()
			local made = observe(ns, ctx, clock, 5000, GOLDSHIRE)
			expect.equal(#made, 1, "Elwynn Forest is already known")
			expect.equal(made[1].record.meta.placeKind, "town")
			expect.equal(made[1].record.significance, 2)
			local view = present(ns, char, made[1])
			expect.equal(view.question, "Kyssarra reaches Goldshire. What draws her attention?")
			expect.truthy(table.concat(view.why, "; "):find("first recorded visit to Goldshire", 1, true))
			local entry = answer(ns, char, made[1].reaction, "people", 5100).entry
			expect.truthy(entry.text:find("Reached Goldshire, Elwynn Forest, at level 1 (the first visit Dawnward recorded).",
				1, true), entry.text)

			made = observe(ns, ctx, clock, 9000, STONEFIELD)
			expect.equal(made[1].record.meta.placeKind, "farm")
			expect.equal(made[1].outcome, "logged quietly", "ordinary farmland is recorded, not asked about")
			expect.falsy(made[1].reaction)

			made = observe(ns, ctx, clock, 13000, LAKESHIRE, { level = 15 })
			expect.equal(#made, 2)
			expect.equal(made[1].record.key, "place:Redridge Mountains / Lakeshire")
			expect.equal(made[1].record.meta.newRegion, 1)
			expect.equal(made[2].record.key, "zone:Redridge Mountains")
			expect.equal(made[2].record.status, "recorded", "a zone and its settlement ask one question")
			expect.equal(present(ns, char, made[1]).question,
				"Kyssarra reaches Lakeshire. What is her first impression of this new place?")
		end)

		t:it("a zone entry followed by its subzone folds into one moment", function()
			local ns, char, ctx, clock = journey()
			local made = observe(ns, ctx, clock, 5000, { "Redridge Mountains", nil, 1433, nil }, { level = 15 })
			expect.equal(made[1].outcome, "queued")
			local reaction = made[1].reaction
			-- Moments later: Lakeshire, a settlement, is the better question.
			made = observe(ns, ctx, clock, 5030, LAKESHIRE, { level = 15 })
			expect.equal(made[1].outcome, "replaced")
			expect.equal(made[1].reaction, reaction)
			expect.equal(#char.story.reactions, 1)
			expect.equal(ns.GameEvents.Find(char, "zone:Redridge Mountains").status, "recorded")
			expect.equal(present(ns, char, made[1]).question, "Kyssarra reaches Lakeshire. What draws her attention?")
			-- A road right after: recorded only.
			made = observe(ns, ctx, clock, 5060, { "Redridge Mountains", "Three Corners", 1433, 1002 }, { level = 15 })
			expect.equal(made[1].outcome, "logged quietly")
			expect.equal(made[1].record.status, "recorded")
			expect.equal(#char.story.reactions, 1)
		end)

		t:it("travelling back and forth between Goldshire and the farms asks nothing new", function()
			local ns, char, ctx, clock = journey()
			observe(ns, ctx, clock, 5000, GOLDSHIRE)
			observe(ns, ctx, clock, 5600, STONEFIELD)
			local events, reactions = #char.story.events, #char.story.reactions
			for i = 1, 20 do
				local made = observe(ns, ctx, clock, 6000 + i * 600, i % 2 == 0 and GOLDSHIRE or STONEFIELD)
				expect.equal(#made, 0, "visit " .. i)
			end
			expect.equal(#char.story.events, events)
			expect.equal(#char.story.reactions, reactions)
			local goldshire = char.story.places["Elwynn Forest / Goldshire"]
			expect.equal(goldshire.visits, 2, "re-entering within 30 minutes is the same visit")
		end)

		t:it("unknown and custom subzones are logged, never classified or asked about", function()
			local ns, char, ctx, clock = journey()
			local made = observe(ns, ctx, clock, 5000, { "Elwynn Forest", "Kyssarra's Camp", 1429, nil })
			expect.equal(#made, 0)
			local entry = char.story.places["Elwynn Forest / Kyssarra's Camp"]
			expect.equal(entry.kind, nil)
			expect.equal(entry.visits, 1)
			-- An area ID that does not belong to the observed map is ignored.
			made = observe(ns, ctx, clock, 6000, { "Elwynn Forest", "Somewhere", 1429, 69 })
			expect.equal(#made, 0)
			expect.equal(char.story.places["Elwynn Forest / Somewhere"].kind, nil)
		end)

		t:it("subzone names resolve only through the client's own area names, within the map", function()
			local ns = Loader.Core()
			local names = { [87] = "Goldshire", [69] = "Lakeshire" }
			local function areaName(id) return names[id] end
			expect.equal(ns.Places.ResolveArea("classic_era", 1429, "Goldshire", areaName), 87)
			expect.equal(ns.Places.ResolveArea("classic_era", 1429, "Lakeshire", areaName), nil, "wrong map")
			expect.equal(ns.Places.ResolveArea("classic_era", 1429, "Kyssarra's Camp", areaName), nil)
			expect.equal(ns.Places.ResolveArea("forever", 1429, "Goldshire", areaName), nil)
			-- A localised client: the name comes from the client, so it still matches.
			names[87] = "Villedoré"
			expect.equal(ns.Places.ResolveArea("classic_era", 1429, "Villedoré", areaName), 87)
		end)
	end)

	t:describe("returns and the player's own story (#20)", function()
		local function visited()
			local ns, char, ctx, clock = setup()
			local made = observe(ns, ctx, clock, 100, NORTHSHIRE)
			answer(ns, char, made[1].reaction, "curious", 150)
			made = observe(ns, ctx, clock, 5000, GOLDSHIRE)
			answer(ns, char, made[1].reaction, "work", 5050)
			observe(ns, ctx, clock, 9000, STONEFIELD)
			return ns, char, ctx, clock
		end

		t:it("coming back to an ordinary settlement is recorded quietly, at most weekly", function()
			local ns, char, ctx, clock = visited()
			local ND = ns.NarrativeClock.DayLength(char) -- a narrative day of play
			local made = observe(ns, ctx, clock, 9000 + 2 * ND, GOLDSHIRE)
			expect.equal(#made, 1)
			expect.equal(made[1].record.meta.visit, "return")
			expect.equal(made[1].record.significance, 1)
			expect.equal(made[1].outcome, "logged quietly", "no tie to the character's story: no question")
			expect.equal(#char.story.reactions, 0)
			-- Away more narrative days, but within the narrative week: no second return moment.
			observe(ns, ctx, clock, 9000 + 2 * ND + 600, STONEFIELD)
			expect.equal(#observe(ns, ctx, clock, 9000 + 5 * ND, GOLDSHIRE), 0)
			-- Farmland returns are never moments by themselves.
			expect.equal(#observe(ns, ctx, clock, 9000 + 7 * ND, STONEFIELD), 0)
			-- A narrative week after the last return, after a real absence: again.
			expect.equal(observe(ns, ctx, clock, 9000 + 10 * ND, GOLDSHIRE)[1].record.meta.visit, "return")
		end)

		t:it("a place the player marked as meaningful is asked about on return", function()
			local ns, char, ctx, clock = visited()
			local memories, facts, journal = #char.story.memories, #char.facts, #char.journal
			assert(ns.Places.Mark(char, "the stonefield farm", true))
			expect.equal(char.story.places["Elwynn Forest / The Stonefield Farm"].meaningful, true)
			-- Marking creates nothing else: no memory, fact or journal entry.
			expect.equal(#char.story.memories, memories)
			expect.equal(#char.facts, facts)
			expect.equal(#char.journal, journal)
			local made = observe(ns, ctx, clock, 9000 + 3 * DAY, STONEFIELD)
			expect.equal(made[1].record.significance, 2)
			expect.equal(present(ns, char, made[1]).question,
				"Kyssarra has returned to The Stonefield Farm, a place that matters to her. Does it feel any different now?")
			local entry = answer(ns, char, made[1].reaction, "comfort", 9100 + 3 * DAY).entry
			expect.truthy(entry.text:find("(a place you marked as meaningful)", 1, true))
			local _, err = ns.Places.Mark(char, "Lakeshire", true)
			expect.truthy(err:find("no visited place", 1, true))
		end)

		t:it("a return to a place tied to an established memory asks if the view has changed", function()
			local ns, char, ctx, clock = visited()
			assert(ns.Memories.Add(char, { title = "The night at the inn",
				links = { events = { "place:Elwynn Forest / Goldshire" } } }, "player", 9500))
			local made = observe(ns, ctx, clock, 9000 + 3 * DAY, GOLDSHIRE)
			expect.equal(made[1].record.meta.linked, 1)
			expect.equal(made[1].record.significance, 2)
			local view = present(ns, char, made[1])
			expect.equal(view.question,
				"Kyssarra has returned to Goldshire, a place tied to one of her memories. Has her view of it changed?")
			expect.truthy(table.concat(view.why, "; "):find("one of your memories", 1, true))
		end)

		t:it("an active goal adds its own answer to a place moment; the universal answers stay", function()
			local ns, char, ctx, clock = visited()
			-- The goal names the place, so the return is relevant to it.
			local goal = assert(ns.Goals.Add(char, { title = "Find the missing courier in Goldshire" }, 9500))
			local view = present(ns, char, observe(ns, ctx, clock, 9000 + 3 * DAY, GOLDSHIRE)[1])
			local ids = {}
			for _, o in ipairs(view.options) do ids[#ids + 1] = o.id end
			expect.deepEqual(ids, { "changed", "comfort", "reluctant", "measure", "goal:" .. goal.id, "nothing" })
		end)

		t:it("a quest turned in right after arriving takes precedence over the arrival", function()
			local ns, char, ctx, clock = setup()
			local made = observe(ns, ctx, clock, 100, NORTHSHIRE)
			answer(ns, char, made[1].reaction, "curious", 150)
			made = observe(ns, ctx, clock, 5000, GOLDSHIRE)
			expect.equal(#char.story.reactions, 1)
			local quest = assert(ns.GameEvents.Record(char, "quest", { questId = 60, title = "Kobold Candles",
				zone = "Elwynn Forest", subzone = "Goldshire", level = 3 }, 5040))
			local reaction, outcome = ns.Reactions.Consider(char, quest, 5040, 5040)
			expect.equal(outcome, "queued")
			expect.equal(#char.story.reactions, 1, "the task, not the town")
			expect.equal(char.story.reactions[1], reaction)
			expect.equal(made[1].record.status, "recorded")
			expect.equal(ns.Reactions.Present(char, reaction).question,
				"Kyssarra has finished \"Kobold Candles\" in Elwynn Forest. How did it sit with them?")
		end)

		t:it("place moments can be reduced or switched off; places are still recorded", function()
			local ns, char, ctx, clock = setup()
			local made = observe(ns, ctx, clock, 100, NORTHSHIRE)
			answer(ns, char, made[1].reaction, "curious", 150)
			char.story.prefs.places = "fewer"
			expect.equal(observe(ns, ctx, clock, 5000, STONEFIELD)[1].outcome, "logged quietly")
			expect.equal(observe(ns, ctx, clock, 9000, GOLDSHIRE)[1].outcome, "logged quietly",
				"with fewer, an ordinary town is only logged")
			char.fields.homeland = { value = "Lakeshire", visibility = "private" }
			made = observe(ns, ctx, clock, 20000, LAKESHIRE, { level = 15 })
			expect.equal(made[1].outcome, "queued", "a homeland still asks")
			ns.Reactions.Dismiss(char, char.story.reactions[1].id)
			char.story.prefs.places = "off"
			made = observe(ns, ctx, clock, 40000, { "Westfall", nil, 1436, nil }, { level = 15 })
			expect.equal(#made, 1)
			expect.equal(#char.story.reactions, 0)
			expect.truthy(ns.GameEvents.Find(char, "zone:Westfall"))
		end)

		t:it("turning off zone and place tracking stops logging places", function()
			local ns, char, ctx, clock = setup()
			char.story.prefs.tracking.zone, char.story.prefs.tracking.place = false, false
			expect.equal(#observe(ns, ctx, clock, 100, NORTHSHIRE), 0)
			expect.equal(next(char.story.places), nil)
		end)
	end)

	t:describe("privacy and saved data", function()
		t:it("places, origins and place moments never reach public output or TRP3", function()
			local ns, char, ctx, clock = setup({ trp3 = true })
			local made = observe(ns, ctx, clock, 100, NORTHSHIRE)
			local entry = answer(ns, char, made[1].reaction, "curious", 150).entry
			observe(ns, ctx, clock, 5000, GOLDSHIRE)
			ns.Places.Mark(char, "Goldshire", true)
			expect.equal(entry.visibility, "private")
			local public = ns.Projection.GetPublic(char)
			local block = ns.TRP3AboutBlock.Compose(public) or ""
			for _, word in ipairs({ "Northshire", "Goldshire", "Elwynn", "journey" }) do
				expect.falsy(block:find(word, 1, true), word)
			end
			expect.equal(#public.journal, 0)
		end)

		t:it("v4 data upgrades to v5 without touching events, approvals or journal text", function()
			local ns = Loader.Core()
			ns.Director.Roll = function() return 0 end
			local stale = "Arrived in Elwynn Forest at level 1 (the first visit Dawnward recorded).\n\n"
				.. "Kyssarra wanted to see all of it.\n\nNew places draw them on.\n\n"
				.. "Development: toward Bold (Courage +1) (waiting for your approval)."
			local v4 = { schemaVersion = 4, ui = {}, importBackups = {}, characters = { [KEY] = {
				createdAt = 1, updatedAt = 2, nextId = 10, theme = "neutral",
				fields = { name = { value = "Kyssarra", visibility = "public" } }, family = {}, history = {},
				journal = { { id = 4, kind = "story", status = "approved", title = "Elwynn Forest", text = stale,
					visibility = "private", createdAt = 3, story = { category = "zone", decisionId = 2,
						eventKey = "zone:Elwynn Forest" } } },
				journalKeys = {}, facts = {}, personality = { courage = { value = 11, visibility = "private", updatedAt = 3 } },
				sources = { nextId = 1, versions = {} }, interpretations = {}, interpretationKeys = {}, wizard = {},
				story = { events = { { key = "zone:Elwynn Forest", category = "zone", at = 1, zone = "Elwynn Forest",
					level = 1, meta = {}, source = "ZONE_CHANGED_NEW_AREA", confidence = "verified", significance = 1,
					status = "reacted" } }, eventKeys = { ["zone:Elwynn Forest"] = 1 },
					decisions = { { id = 2, category = "zone", eventKeys = { "zone:Elwynn Forest" }, templateId = "zone.arrival",
						optionId = "curious", at = 2, effects = { courage = 1 }, journalId = 4 } },
					changes = { { id = 3, axis = "courage", delta = 1, decisionId = 2, status = "applied", from = 10, to = 11,
						proposedAt = 2, decidedAt = 3 } },
					nextId = 5 },
			} } }
			local before = ns.Util.DeepCopy(v4)
			local db, info = ns.Migrations.Load(v4)
			expect.equal(info.status, "migrated")
			expect.equal(db.schemaVersion, 5)
			expect.deepEqual(v4, before, "the saved table is never modified")
			local char = db.characters[KEY]
			expect.equal(char.journal[1].text, stale, "approved text is never rewritten")
			expect.equal(char.journal[1].status, "approved")
			expect.deepEqual(char.story.places, {})
			expect.equal(char.story.events[1].meta.visit, nil, "past events are not reclassified")
			expect.equal(char.story.prefs.places, "on")
			-- The journal shows the change's real status instead of the stale words.
			local shown = ns.Narrative.DisplayText(char, char.journal[1])
			expect.truthy(shown:find("Development: toward Bold (Courage +1) (approved).", 1, true), shown)
			expect.falsy(shown:find("waiting", 1, true))
			-- And it was the first location, so travel from here is ordinary travel.
			local clock = { now = 50 }
			local ctx = { store = { real = db }, characterKey = KEY, now = function() return clock.now end }
			local made = ns.Actions.ObserveLocation(ctx, where("Westfall", nil, 1436, nil, { level = 12 }))
			expect.equal(made[1].record.meta.visit, "first")
			expect.equal(ns.Reactions.Present(char, made[1].reaction).question,
				"Kyssarra has come to Westfall. What do they make of it?")
		end)

		t:it("an older v0.4 build opens schema 5 data read-only instead of dropping place events", function()
			local ns = Loader.Core()
			local _, info = ns.Migrations.Load({ schemaVersion = 5, characters = {} }, ns.Migrations.steps, 4)
			expect.equal(info.status, "readOnly")
		end)

		t:it("the places log is cleaned and capped, keeping places the player marked", function()
			local ns = Loader.Core()
			local raw = { bad = { zone = "" }, junk = 3 }
			for i = 1, ns.Places.LIMIT + 20 do
				raw["Z / " .. i] = { zone = "Z", subzone = "S" .. i, first = i, last = i, visits = 1, kind = "nonsense" }
			end
			raw.keep = { zone = "Z", subzone = "Kept", first = 0, last = 0, visits = 1, meaningful = true }
			local clean = ns.Places.CleanAll(raw)
			local n = 0
			for _, e in pairs(clean) do
				n = n + 1
				expect.equal(e.kind, nil)
			end
			expect.equal(n, ns.Places.LIMIT)
			expect.truthy(clean["Z / Kept"], "a meaningful place is never pruned")
		end)
	end)

	t:describe("journal development status (in-game finding)", function()
		local function decided(approval)
			local ns, char = setup()
			char.story.prefs.approval = approval or "ask"
			local record = assert(ns.GameEvents.Record(char, "quest", { questId = 7, title = "A Task", zone = "Elwynn Forest",
				level = 2 }, 10))
			local reaction = assert(ns.Reactions.Consider(char, record, 10, 10))
			local result = answer(ns, char, reaction, "resolve", 20)
			return ns, char, result
		end

		t:it("a draft shows the change's current status, and its stored text never changes", function()
			local ns, char, result = decided()
			local entry, change = result.entry, result.changes[1]
			local stored = entry.text
			expect.falsy(stored:find("waiting", 1, true), "the status is not written into the text")
			expect.truthy(stored:find("Development: " .. ns.Evolution.Describe(change) .. ".", 1, true), stored)
			expect.truthy(ns.Narrative.DisplayText(char, entry):find("(waiting for your approval).", 1, true))
			assert(ns.Evolution.Apply(char, change.id, 30))
			local shown = ns.Narrative.DisplayText(char, entry)
			expect.truthy(shown:find(ns.Evolution.Describe(change) .. " (approved).", 1, true), shown)
			expect.falsy(shown:find("waiting", 1, true))
			expect.equal(entry.text, stored)
			ns.Journal.Approve(char, entry.id, 40)
			assert(ns.Evolution.Reverse(char, change.id, 50))
			expect.truthy(ns.Narrative.DisplayText(char, entry):find("(reversed).", 1, true))
			expect.equal(entry.text, stored)
		end)

		t:it("rejected and auto-applied changes read correctly", function()
			local ns, char, result = decided()
			assert(ns.Evolution.Reject(char, result.changes[1].id, 30))
			expect.truthy(ns.Narrative.DisplayText(char, result.entry):find("(rejected).", 1, true))
			local ns2, char2, auto = decided("auto")
			expect.truthy(ns2.Narrative.DisplayText(char2, auto.entry):find("(approved).", 1, true))
		end)

		t:it("the player's own edited text is shown exactly as written", function()
			local ns, char, result = decided()
			result.entry.text = "In my own words: it was a hard day.\n\nDevelopment is a slow thing."
			expect.equal(ns.Narrative.DisplayText(char, result.entry), result.entry.text)
			local note = { kind = "note", text = "Development: mine." }
			expect.equal(ns.Narrative.DisplayText(char, note), note.text)
		end)
	end)

	t:describe("observers through the addon (L2)", function()
		local AREAS = { [9] = "Northshire Valley", [87] = "Goldshire", [63] = "The Stonefield Farm" }

		local function start(saved)
			local mock, env, ns = Boot.Start(saved and { savedVariables = { DawnwardChroniclesDB = saved } } or nil)
			env.C_Map = {
				GetBestMapForUnit = function(unit) return unit == "player" and mock.mapId or nil end,
				GetAreaInfo = function(id) return AREAS[id] end,
			}
			mock.raceToken, mock.level, mock.mapId = "Human", 1, 1429
			mock.zone, mock.subzone = "Elwynn Forest", "Northshire Valley"
			return mock, env, ns
		end

		t:it("zone and subzone events record one beginning; a reload records nothing twice", function()
			local mock, env = start()
			mock.Slash("set name Kyssarra")
			mock.Fire("ZONE_CHANGED_NEW_AREA")
			mock.Fire("ZONE_CHANGED")
			mock.Fire("ZONE_CHANGED_INDOORS")
			local key = "Testchar-TestRealm"
			local story = env.DawnwardChroniclesDB.characters[key].story
			expect.equal(#story.events, 2)
			expect.equal(story.events[1].key, "place:Elwynn Forest / Northshire Valley")
			expect.equal(story.events[1].meta.visit, "start")
			expect.equal(story.events[1].meta.areaId, 9)
			expect.equal(story.events[1].meta.mapId, 1429)
			expect.equal(#story.reactions, 1)
			local events = mock.Slash("story events")
			expect.truthy(events:find("Journey begins: Northshire Valley (starting area)", 1, true), events)

			local mock2, env2 = start(env.DawnwardChroniclesDB)
			mock2.Fire("PLAYER_ENTERING_WORLD")
			mock2.Fire("ZONE_CHANGED_NEW_AREA")
			local story2 = env2.DawnwardChroniclesDB.characters[key].story
			expect.equal(#story2.events, 2, "nothing recorded twice after a reload")
			expect.equal(#story2.reactions, 1)
			expect.truthy(story2.places["Elwynn Forest / Northshire Valley"])
			mock2.subzone = "Goldshire"
			mock2.Fire("ZONE_CHANGED")
			expect.equal(story2.events[3].key, "place:Elwynn Forest / Goldshire")
			expect.equal(story2.events[3].meta.visit, "first")
			local places = mock2.Slash("places")
			expect.truthy(places:find("Goldshire, Elwynn Forest (settlement)", 1, true), places)
			expect.truthy(mock2.Slash("place mark Goldshire"):find("meaningful", 1, true))
			expect.truthy(story2.places["Elwynn Forest / Goldshire"].meaningful)
			expect.truthy(mock2.Slash("place mark Nowhere"):find("no visited place", 1, true))
		end)

		t:it("a character that never used Dawnward is not recorded anywhere", function()
			local mock, env = start()
			mock.Fire("ZONE_CHANGED_NEW_AREA")
			mock.Fire("PLAYER_ENTERING_WORLD")
			expect.equal(env.DawnwardChroniclesDB.characters["Testchar-TestRealm"], nil)
		end)

		t:it("story set places and story track place work from chat", function()
			local mock, env = start()
			mock.Slash("set name Kyssarra")
			expect.truthy(mock.Slash("story set places fewer"):find("fewer", 1, true))
			expect.truthy(mock.Slash("story set places sometimes"):find("invalid", 1, true))
			expect.truthy(mock.Slash("story track place off"):find("off", 1, true))
			local prefs = env.DawnwardChroniclesDB.characters["Testchar-TestRealm"].story.prefs
			expect.equal(prefs.places, "fewer")
			expect.equal(prefs.tracking.place, false)
			expect.truthy(mock.Slash("story settings"):find("places fewer", 1, true))
		end)
	end)
end
