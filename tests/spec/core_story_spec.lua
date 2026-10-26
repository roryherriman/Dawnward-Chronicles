-- L1: the living chronicle core (v0.4): events, reactions, decisions,
-- personality evolution and story drafts, across varied characters.
local Loader = require("support.loader")
local Fixtures = require("fixtures.characters")

return function(t, expect)
	local function setup(fixture)
		local ns = Loader.Core()
		fixture = fixture or Fixtures.CHARACTERS[1]
		local char = Fixtures.Character(ns, fixture)
		return ns, char, fixture
	end

	local function quest(ns, char, fixture, id, now, overrides)
		local data = Fixtures.Context(fixture, overrides)
		data.questId = id
		if data.title == nil then data.title = "The Lost Ledger" end
		return ns.GameEvents.Record(char, "quest", data, now)
	end

	t:describe("gameplay events (v0.4)", function()
		t:it("normalises a quest record with context, source and confidence", function()
			local ns, char, fx = setup()
			local r = assert(quest(ns, char, fx, 101, 1000, { questLevel = 21, xp = 450, money = 75 }))
			expect.equal(r.key, "quest:101")
			expect.equal(r.category, "quest")
			expect.equal(r.at, 1000)
			expect.equal(r.zone, "Westfall")
			expect.equal(r.level, 20)
			expect.equal(r.class, "PALADIN")
			expect.equal(r.meta.title, "The Lost Ledger")
			expect.equal(r.meta.xp, 450)
			expect.equal(r.source, "QUEST_TURNED_IN")
			expect.equal(r.confidence, "verified")
			expect.equal(r.status, "new")
		end)

		t:it("never records the same event twice, even after a save and reload", function()
			local ns, char, fx = setup()
			assert(quest(ns, char, fx, 7, 1))
			local _, err = quest(ns, char, fx, 7, 2)
			expect.equal(err, "duplicate")
			local reloaded = ns.Schema.NormalizeCharacter(ns.Util.DeepCopy(char))
			local _, err2 = quest(ns, reloaded, fx, 7, 3)
			expect.equal(err2, "duplicate")
			expect.equal(#reloaded.story.events, 1)
		end)

		t:it("marks missing details as partial instead of inventing them", function()
			local ns, char, fx = setup()
			local r = assert(quest(ns, char, fx, 8, 1, { title = false, zone = false }))
			expect.equal(r.confidence, "partial")
			expect.equal(r.meta.title, nil)
			expect.equal(r.zone, nil)
		end)

		t:it("rates significance only from verified data", function()
			local ns, char, fx = setup()
			expect.equal(quest(ns, char, fx, 1, 1).significance, 2, "first quest in a zone")
			expect.equal(quest(ns, char, fx, 2, 2).significance, 1, "routine")
			expect.equal(quest(ns, char, fx, 3, 3, { questLevel = 23 }).significance, 2, "well above level")
			expect.equal(ns.GameEvents.Record(char, "levelup", Fixtures.Context(fx, { level = 30 }), 4).significance, 3)
			expect.equal(ns.GameEvents.Record(char, "levelup", Fixtures.Context(fx, { level = 31 }), 5).significance, 1)
			expect.equal(ns.GameEvents.Record(char, "death", Fixtures.Context(fx, { at = 6 }), 6).significance, 3)
			expect.equal(ns.GameEvents.Record(char, "death", Fixtures.Context(fx, { at = 7 }), 7).significance, 2)
		end)

		t:it("respects tracking switches and rejects invalid data", function()
			local ns, char, fx = setup()
			char.story.prefs.tracking.quest = false
			local _, err = quest(ns, char, fx, 9, 1)
			expect.equal(err, "not tracked")
			char.story.prefs.tracking.quest = true
			local _, bad = ns.GameEvents.Record(char, "quest", { questId = -1 }, 1)
			expect.truthy(bad:find("invalid"))
			local _, unknown = ns.GameEvents.Record(char, "achievement", {}, 1)
			expect.truthy(unknown:find("unknown"))
		end)
	end)

	t:describe("reaction queue (v0.4)", function()
		t:it("queues a reaction, folds same-zone quests into it, and paces new ones", function()
			local ns, char, fx = setup()
			local r1 = quest(ns, char, fx, 1, 1000)
			local reaction, outcome = ns.Reactions.Consider(char, r1, 1000)
			expect.equal(outcome, "queued")
			expect.equal(r1.status, "queued")
			local r2 = quest(ns, char, fx, 2, 1100)
			local same, outcome2 = ns.Reactions.Consider(char, r2, 1100)
			expect.equal(outcome2, "coalesced")
			expect.equal(same.id, reaction.id)
			expect.equal(#reaction.eventKeys, 2)
			-- Another zone during the cooldown stays a plain record.
			local r3 = quest(ns, char, fx, 3, 1200, { zone = "Duskwood", questLevel = 20 })
			ns.Reactions.Postpone(char, reaction.id)
			local _, why = ns.Reactions.Consider(char, quest(ns, char, fx, 4, 1300, { zone = "Duskwood" }), 1300)
			expect.equal(why, "cooldown")
			expect.equal(r3.status, "new")
			-- After the cooldown a new reaction is allowed.
			local _, later = ns.Reactions.Consider(char, quest(ns, char, fx, 5, 1000 + 2701, { zone = "Redridge" }),
				1000 + 2701)
			expect.equal(later, "queued")
		end)

		t:it("honours the threshold and the off switch", function()
			local ns, char, fx = setup()
			char.story.prefs.threshold = 3
			local _, why = ns.Reactions.Consider(char, quest(ns, char, fx, 1, 1), 1)
			expect.equal(why, "below threshold")
			char.story.prefs.threshold = 1
			char.story.prefs.frequency = "off"
			local _, off = ns.Reactions.Consider(char, quest(ns, char, fx, 2, 2, { zone = "Elsewhere" }), 2)
			expect.equal(off, "prompts off")
			expect.equal(#char.story.reactions, 0)
		end)

		t:it("keeps the queue bounded, preferring significant reactions", function()
			local ns, char, fx = setup()
			char.story.prefs.frequency = "frequent"
			local now = 0
			for i = 1, 25 do
				now = now + 1000
				local r = ns.GameEvents.Record(char, "levelup", Fixtures.Context(fx, { level = i + 1 }), now)
				ns.Reactions.Consider(char, r, now)
			end
			expect.truthy(#char.story.reactions <= ns.StorySchema.LIMITS.reactions)
		end)

		t:it("expires old reactions, and supports later, not now and dismiss", function()
			local ns, char, fx = setup()
			local reaction = ns.Reactions.Consider(char, quest(ns, char, fx, 1, 1000), 1000)
			expect.equal(ns.Reactions.NextNotice(char, 1001).id, reaction.id)
			ns.Reactions.Ignore(char, reaction.id, 1002)
			expect.equal(ns.Reactions.NextNotice(char, 1003), nil, "not announced twice")
			expect.equal(#ns.Reactions.List(char, 1003), 1, "still waiting in the Story section")
			ns.Reactions.Postpone(char, reaction.id)
			expect.equal(ns.Reactions.List(char, 1004)[1].status, "postponed")
			assert(ns.Reactions.Dismiss(char, reaction.id))
			expect.equal(#char.story.reactions, 0)
			expect.equal(ns.GameEvents.Find(char, "quest:1").status, "dismissed")
			local again = ns.Reactions.Consider(char, quest(ns, char, fx, 2, 9000, { zone = "Far" }), 9000)
			ns.Reactions.Expire(char, 9000 + ns.Reactions.EXPIRY + 1)
			expect.equal(#char.story.reactions, 0)
			expect.equal(ns.GameEvents.Find(char, "quest:2").status, "recorded")
			expect.truthy(again)
		end)

		t:it("asks a neutral question when details are uncertain", function()
			local ns, char, fx = setup()
			local r = quest(ns, char, fx, 1, 1, { title = false, zone = false })
			local reaction = ns.Reactions.Consider(char, r, 1)
			local view = ns.Reactions.Present(char, reaction)
			expect.falsy(view.question:find("{", 1, true), view.question)
			expect.falsy(view.question:find("\"\"", 1, true), view.question)
			expect.truthy(view.question:find("Aldric", 1, true), view.question)
		end)

		t:it("never lets observed text become a token or markup", function()
			local ns, char, fx = setup()
			local r = quest(ns, char, fx, 1, 1, { title = "Evil {name} {h1}" })
			local view = ns.Reactions.Present(char, ns.Reactions.Consider(char, r, 1))
			expect.falsy(view.question:find("{", 1, true), view.question)
		end)
	end)

	t:describe("vertical slice: quest -> reaction -> decision -> development -> draft", function()
		t:it("works for every fixture character, with the same choices for all", function()
			for _, fx in ipairs(Fixtures.CHARACTERS) do
				local ns, char = setup(fx)
				local before = char.personality.compassion and char.personality.compassion.value
				local record = quest(ns, char, fx, 500, 1000)
				local reaction = assert(ns.Reactions.Consider(char, record, 1000))
				local view = ns.Reactions.Present(char, reaction)
				expect.truthy(ns.Reactions.FindOption(view, "nothing"), fx.archetype)
				local result = assert(ns.Decisions.Decide(char, reaction.id, { optionId = "resolve" }, 1010))
				expect.equal(#char.story.reactions, 0)
				expect.equal(ns.GameEvents.Find(char, "quest:500").status, "reacted")
				-- A pending proposal, not an applied change.
				expect.equal(#result.changes, 1)
				expect.equal(result.changes[1].status, "pending")
				expect.equal(char.personality.compassion and char.personality.compassion.value, before,
					fx.archetype .. ": nothing changes before approval")
				-- A private draft that cannot be published before approval.
				local entry = result.entry
				expect.equal(entry.kind, "story")
				expect.equal(entry.status, "draft")
				expect.equal(entry.visibility, "private")
				expect.truthy(entry.text:find("The Lost Ledger", 1, true))
				local _, refused = ns.Journal.SetVisibility(char, entry.id, "public", 1011)
				expect.equal(refused, ns.Journal.APPROVAL_MESSAGE)
				-- Approve the change and the draft, then publish.
				assert(ns.Evolution.Apply(char, result.changes[1].id, 1012))
				expect.equal(char.personality.compassion.value, (before or 10) + 1, fx.archetype)
				assert(ns.Journal.Approve(char, entry.id, 1013))
				assert(ns.Journal.SetVisibility(char, entry.id, "public", 1014))
				expect.equal(#ns.Projection.GetPublic(char).journal, 1)
			end
		end)

		t:it("a custom answer is recorded in the player's words and proposes nothing", function()
			local ns, char, fx = setup(Fixtures.CHARACTERS[2])
			local reaction = ns.Reactions.Consider(char, quest(ns, char, fx, 1, 1), 1)
			local result = assert(ns.Decisions.Decide(char, reaction.id, { custom = "She paid the farmer back." }, 2))
			expect.equal(#result.changes, 0)
			expect.truthy(result.entry.text:find("own words: She paid the farmer back.", 1, true))
			expect.equal(result.decision.custom, "She paid the farmer back.")
			local _, err = ns.Decisions.Decide(char, 999, { optionId = "resolve" }, 3)
			expect.truthy(err:find("no waiting"))
		end)

		t:it("drafts say only what was observed and what the player chose", function()
			local ns, char, fx = setup(Fixtures.CHARACTERS[4])
			local reaction = ns.Reactions.Consider(char, quest(ns, char, fx, 1, 1, { title = false }), 1)
			local result = ns.Decisions.Decide(char, reaction.id, { optionId = "nothing" }, 2)
			expect.equal(result.entry.text, "Completed a quest in The Barrens at level 20.\n\n"
				.. "Morrow felt it was nothing worth remembering.")
			expect.equal(result.entry.title, "A task in The Barrens")
		end)

		t:it("drafts can be switched off; decisions still count", function()
			local ns, char, fx = setup()
			char.story.prefs.drafts = false
			local reaction = ns.Reactions.Consider(char, quest(ns, char, fx, 1, 1), 1)
			local result = ns.Decisions.Decide(char, reaction.id, { optionId = "craft" }, 2)
			expect.equal(result.entry, nil)
			expect.equal(#char.journal, 0)
			expect.equal(#char.story.decisions, 1)
		end)
	end)

	t:describe("personality evolution (v0.4)", function()
		-- Each case tests evolution, not pacing: start every decision fresh.
		local function decide(ns, char, fx, id, optionId, now)
			char.story.pacing.recentTemplates = {}
			char.story.pacing.lastByCategory = {}
			local reaction = ns.Reactions.Consider(char, quest(ns, char, fx, id, now, { zone = "Zone" .. id }), now)
			return ns.Decisions.Decide(char, reaction.id, { optionId = optionId }, now)
		end

		t:it("keeps the player's baseline, moves one step, and can be reversed", function()
			local ns, char, fx = setup(Fixtures.CHARACTERS[2]) -- compassion 18
			local result = decide(ns, char, fx, 1, "resolve", 100)
			assert(ns.Evolution.Apply(char, result.changes[1].id, 101))
			expect.equal(char.personality.compassion.value, 19)
			expect.equal(char.story.baselines.compassion, 18)
			assert(ns.Evolution.Reverse(char, result.changes[1].id, 102))
			expect.equal(char.personality.compassion.value, 18)
			expect.equal(ns.Evolution.Find(char, result.changes[1].id).status, "reversed")
			expect.equal(char.personality.compassion.visibility, "private", "visibility is never changed")
		end)

		t:it("starts an unset axis at the midpoint, privately", function()
			local ns, char, fx = setup(Fixtures.CHARACTERS[9])
			local result = decide(ns, char, fx, 1, "craft", 100)
			assert(ns.Evolution.Apply(char, result.changes[1].id, 101))
			expect.equal(char.personality.discipline.value, 11)
			expect.equal(char.personality.discipline.visibility, "private")
			expect.equal(char.story.baselines.discipline, 10)
		end)

		t:it("limits change per day and never passes 0 or 20", function()
			local ns, char, fx = setup()
			char.story.prefs.frequency = "frequent"
			local ids = {}
			for i = 1, 3 do
				local r = decide(ns, char, fx, i, "resolve", i * 1000)
				ids[i] = r.changes[1].id
			end
			assert(ns.Evolution.Apply(char, ids[1], 5000))
			assert(ns.Evolution.Apply(char, ids[2], 5001))
			local _, err = ns.Evolution.Apply(char, ids[3], 5002)
			expect.truthy(err:find("enough today"))
			expect.equal(ns.Evolution.Find(char, ids[3]).status, "pending", "it waits, it is not lost")
			assert(ns.Evolution.Apply(char, ids[3], 5002 + ns.Evolution.DAY))
			char.personality.compassion.value = 20
			local r = decide(ns, char, fx, 9, "resolve", 200000)
			local _, limit = ns.Evolution.Apply(char, r.changes[1].id, 200001)
			expect.truthy(limit:find("limit"))
		end)

		t:it("auto approval applies at once and stays reversible; reject leaves values alone", function()
			local ns, char, fx = setup(Fixtures.CHARACTERS[5])
			char.story.prefs.approval = "auto"
			local result = decide(ns, char, fx, 1, "doubt", 100)
			expect.equal(result.changes[1].status, "applied")
			expect.equal(char.personality.faith.value, 1)
			expect.truthy(result.entry.text:find("Development: toward Sceptical", 1, true))
			char.story.prefs.approval = "ask"
			local second = decide(ns, char, fx, 2, "doubt", 200)
			assert(ns.Evolution.Reject(char, second.changes[1].id, 201))
			expect.equal(char.personality.faith.value, 1)
		end)

		t:it("records manual adjustments in the same history", function()
			local ns, char = setup()
			local change = ns.Evolution.RecordManual(char, "courage", 5, 9, 10)
			expect.equal(change.delta, 4)
			expect.equal(ns.Evolution.History(char)[1].reason, "set by you")
			expect.equal(ns.Evolution.RecordManual(char, "courage", 9, 9, 11), nil)
		end)
	end)

	t:describe("universal content: no class, race or faction assumptions", function()
		local FORBIDDEN = { "Light", "Holy", "Alliance", "Horde", "Stormwind", "Orgrimmar", "Ironforge",
			"Undercity", "Darnassus", "Thunder Bluff", "Paladin", "Human", "Orc", "Elune", "Forsaken", "Kyssarra",
			"Dawnward", "Silver Hand", "honourable", "heroic", "righteous", "sinful", "evil", "good person",
			"%f[%a]he%f[%A]", "%f[%a]she%f[%A]", "%f[%a]his%f[%A]", "%f[%a]her%f[%A]", "%f[%a]him%f[%A]" }
		local AXES = { courage = true, compassion = true, discipline = true, faith = true, honour = true,
			sociability = true }

		local function texts(template)
			local out = {}
			for _, q in ipairs(template.questions) do out[#out + 1] = q.text end
			for _, o in ipairs(template.options) do
				out[#out + 1] = o.text
				out[#out + 1] = o.phrase
				out[#out + 1] = o.meaning
			end
			return out
		end

		t:it("no universal text names a class, race, faction, city, deity or moral label", function()
			local ns = Loader.Core()
			local all = texts({ questions = {}, options = { ns.ReactionLibrary.NEUTRAL } })
			for _, template in ipairs(ns.ReactionLibrary.TEMPLATES) do
				for _, s in ipairs(texts(template)) do all[#all + 1] = s end
			end
			for _, s in ipairs(all) do
				for _, word in ipairs(FORBIDDEN) do
					expect.falsy(s:find(word), string.format("'%s' contains '%s'", s, word))
				end
			end
		end)

		t:it("every template offers several directions, a neutral answer, and only small effects", function()
			local ns = Loader.Core()
			for _, template in ipairs(ns.ReactionLibrary.TEMPLATES) do
				expect.truthy(#template.options >= 4, template.id)
				local up, down = false, false
				for _, option in ipairs(template.options) do
					local n = 0
					for axis, delta in pairs(option.effects) do
						expect.truthy(AXES[axis], template.id .. ": unknown axis " .. axis)
						expect.truthy(delta == 1 or delta == -1, template.id .. "." .. option.id)
						if delta > 0 then up = true else down = true end
						n = n + 1
					end
					expect.truthy(n <= 2, template.id .. "." .. option.id)
				end
				expect.truthy(up and down, template.id .. " offers answers in opposite directions")
				expect.equal(#template.questions[#template.questions].needs, 0,
					template.id .. " has a neutral question for uncertain events")
			end
		end)

		t:it("the universal question and answers are identical for every class, race and faction", function()
			local reference
			for _, fx in ipairs(Fixtures.CHARACTERS) do
				local ns, char = setup(fx)
				char.fields.name = { value = "Same", visibility = "private" }
				char.story.prefs.flavor = false
				local view = ns.Reactions.Present(char, ns.Reactions.Consider(char, quest(ns, char, fx, 1, 1,
					{ zone = "Anywhere" }), 1))
				local shape = { question = view.question, template = view.template.id, options = {} }
				for _, o in ipairs(view.options) do
					shape.options[#shape.options + 1] = { id = o.id, effects = o.effects }
				end
				reference = reference or shape
				expect.deepEqual(shape, reference, fx.archetype)
			end
		end)

		t:it("class flavour only adds an optional answer, with no personality effect", function()
			local ns = Loader.Core()
			local seen = {}
			for _, fx in ipairs(Fixtures.CHARACTERS) do
				local _, char = setup(fx)
				local view = ns.Reactions.Present(char, ns.Reactions.Consider(char, quest(ns, char, fx, 1, 1), 1))
				local universal = #ns.ReactionLibrary.BY_ID[view.template.id].options
				expect.equal(#view.options, universal + 2, fx.archetype .. ": universal + flavour + neutral")
				local flavor = view.options[universal + 1]
				expect.truthy(flavor.flavor, fx.archetype)
				expect.deepEqual(flavor.effects, {})
				seen[fx.class] = true
			end
			for _, class in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK",
				"DRUID" }) do
				expect.truthy(ns.ReactionLibrary.FLAVOR.quest[class], "every class has flavour: " .. class)
			end
			expect.truthy(seen.PALADIN and seen.WARLOCK)
		end)

		t:it("the same answers move the same axes for a paladin and a warlock", function()
			local results = {}
			for _, fx in ipairs({ Fixtures.CHARACTERS[1], Fixtures.CHARACTERS[2] }) do
				local ns, char = setup(fx)
				local reaction = ns.Reactions.Consider(char, quest(ns, char, fx, 1, 1, { zone = "Anywhere" }), 1)
				local r = ns.Decisions.Decide(char, reaction.id, { optionId = "ambition" }, 2)
				results[#results + 1] = { axis = r.changes[1].axis, delta = r.changes[1].delta }
			end
			expect.deepEqual(results[1], results[2])
			expect.deepEqual(results[1], { axis = "honour", delta = -1 })
		end)

		t:it("no story data reaches the public projection", function()
			local ns, char, fx = setup()
			local reaction = ns.Reactions.Consider(char, quest(ns, char, fx, 1, 1), 1)
			ns.Decisions.Decide(char, reaction.id, { custom = "SECRET-THOUGHT" }, 2)
			local public = ns.Projection.GetPublic(char)
			expect.equal(public.story, nil)
			local all = ns.Projection.Filter(char, { public = true, private = true, secret = true })
			expect.equal(all.story, nil, "story records never travel through projections")
		end)
	end)

	t:describe("schema v4", function()
		t:it("migrates v3 data additively: no value or visibility changes", function()
			local ns = Loader.Core()
			local v3 = { schemaVersion = 3, ui = {}, importBackups = {}, characters = { ["A-R"] = {
				createdAt = 1, updatedAt = 2, nextId = 4, theme = "neutral",
				fields = { name = { value = "A", visibility = "private" } }, family = {}, history = {},
				journal = { { id = 1, kind = "note", text = "kept private", visibility = "private", createdAt = 1 },
					{ id = 2, kind = "event", text = "Reached level 2.", visibility = "private", createdAt = 2,
						event = { type = "levelup", key = "levelup:2", level = 2 } } },
				journalKeys = { ["levelup:2"] = 2 },
				facts = { { id = 3, category = "fear", statement = "Deep water", visibility = "secret",
					provenance = { origin = "player" }, createdAt = 1 } },
				personality = { faith = { value = 4, visibility = "private", updatedAt = 1 } },
				sources = { nextId = 1, versions = {} }, interpretations = {}, interpretationKeys = {}, wizard = {},
			} } }
			local before = ns.Util.DeepCopy(v3)
			local db, info = ns.Migrations.Load(v3)
			expect.equal(info.status, "migrated")
			expect.equal(db.schemaVersion, ns.Schema.VERSION)
			expect.deepEqual(v3, before, "the saved table is never modified")
			local char = db.characters["A-R"]
			for _, part in ipairs({ "fields", "journal", "journalKeys", "personality" }) do
				expect.deepEqual(char[part], before.characters["A-R"][part], part)
			end
			expect.equal(char.facts[1].visibility, "secret")
			expect.deepEqual(char.story.reactions, {})
			expect.equal(char.story.prefs.approval, "ask")
			expect.equal(#info.notes, 0)
		end)

		t:it("normalises story data idempotently and repairs bad records", function()
			local ns, char, fx = setup()
			local reaction = ns.Reactions.Consider(char, quest(ns, char, fx, 1, 1), 1)
			ns.Decisions.Decide(char, reaction.id, { optionId = "resolve" }, 2)
			char.story.reactions[1] = { id = "x" }
			char.story.prefs.frequency = "constantly"
			local report = {}
			local once = ns.Schema.NormalizeCharacter(ns.Util.DeepCopy(char), report)
			local twice = ns.Schema.NormalizeCharacter(ns.Util.DeepCopy(once))
			expect.deepEqual(twice, once)
			expect.equal(#once.story.reactions, 0)
			expect.equal(once.story.prefs.frequency, "normal")
			expect.equal(#once.story.decisions, 1)
			expect.equal(once.journal[1].status, "draft")
		end)

		t:it("an unapproved draft loaded as public is made private", function()
			local ns = Loader.Core()
			local entry = ns.Schema.CleanJournalEntry({ kind = "story", text = "x", visibility = "public",
				status = "draft" })
			expect.equal(entry.visibility, "private")
			local approved = ns.Schema.CleanJournalEntry({ kind = "story", text = "x", visibility = "public",
				status = "approved" })
			expect.equal(approved.visibility, "public")
		end)

		t:it("retention removes milestones, then drafts, never approved or important entries", function()
			local ns = Loader.Core()
			local entries = {
				{ kind = "story", status = "approved", createdAt = 1 },
				{ kind = "story", status = "draft", createdAt = 2 },
				{ kind = "event", createdAt = 3 },
				{ kind = "story", status = "draft", important = true, createdAt = 4 },
				{ kind = "note", createdAt = 5 },
			}
			ns.Schema.ApplyJournalRetention(entries, 3)
			expect.equal(#entries, 3)
			expect.equal(entries[1].status, "approved")
			expect.equal(entries[2].important, true)
			expect.equal(entries[3].kind, "note")
		end)

		t:it("personal backups carry the story; share exports and older backups never replace it", function()
			local ns, char, fx = setup()
			local reaction = ns.Reactions.Consider(char, quest(ns, char, fx, 1, 1), 1)
			ns.Decisions.Decide(char, reaction.id, { custom = "PRIVATE-WORDS" }, 2)
			local share = assert(ns.Transfer.Export(char, "share", {}))
			local sharePlan = assert(ns.Transfer.Decode(share))
			expect.falsy(share:find("PRIVATE-WORDS", 1, true), "a share export never carries the story")
			expect.falsy(sharePlan.includesStory)
			local merged = ns.Transfer.MergeForImport(char, sharePlan.character, false, 3, false, sharePlan.includesStory)
			expect.equal(#merged.story.decisions, 1, "importing a share export keeps the current story")
			local backup = assert(ns.Transfer.Export(char, "backup", {}))
			local plan = assert(ns.Transfer.Decode(backup))
			expect.truthy(plan.includesStory)
			local fresh = ns.Schema.NewCharacter(5)
			ns.GameEvents.Record(fresh, "quest", { questId = 99 }, 5)
			local restored = ns.Transfer.MergeForImport(fresh, plan.character, false, 6, false, true)
			expect.equal(restored.story.decisions[1].custom, "PRIVATE-WORDS")
			expect.truthy(restored.story.eventKeys["quest:99"], "events recorded on either side stay recorded")
		end)

		t:it("journal search filters by text, kind, status and importance", function()
			local ns, char, fx = setup()
			local reaction = ns.Reactions.Consider(char, quest(ns, char, fx, 1, 1), 1)
			local entry = ns.Decisions.Decide(char, reaction.id, { optionId = "resolve" }, 2).entry
			ns.Journal.AddNote(char, { text = "A quiet evening" }, 3)
			expect.equal(#ns.Journal.Search(char, { text = "LEDGER" }), 1)
			expect.equal(#ns.Journal.Search(char, { kind = "story", status = "draft" }), 1)
			expect.equal(#ns.Journal.Search(char, { important = true }), 0)
			ns.Journal.SetImportant(char, entry.id, true, 4)
			expect.equal(ns.Journal.Search(char, { important = true })[1].id, entry.id)
		end)
	end)
end
