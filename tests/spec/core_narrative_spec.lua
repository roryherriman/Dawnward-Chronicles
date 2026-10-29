-- L1/L2: narrative records (#12, #19, #27, #30), the Story Director (#20,
-- #25) and continuity review (#42), across varied characters.
local Loader = require("support.loader")
local Fixtures = require("fixtures.characters")
local Boot = require("support.boot")

return function(t, expect)
	local function setup(fixture)
		local ns = Loader.WithTRP3()
		fixture = fixture or Fixtures.CHARACTERS[1]
		return ns, Fixtures.Character(ns, fixture), fixture
	end

	-- One quest through the loop; returns the decision result.
	local function answer(ns, char, fx, id, optionId, overrides, now)
		char.story.pacing.playByCategory = {}
		char.story.pacing.recentTemplates = {}
		local data = Fixtures.Context(fx, overrides)
		data.questId, data.title = id, data.title or ("Quest " .. id)
		local record = assert(ns.GameEvents.Record(char, "quest", data, now or id))
		local reaction = assert(ns.Reactions.Consider(char, record, now or id, now or id))
		return assert(ns.Decisions.Decide(char, reaction.id, optionId, now or id))
	end

	t:describe("records contract (provenance, canon status, visibility)", function()
		t:it("suggestions start proposed and private; public needs an established record", function()
			local ns, char = setup()
			local m = assert(ns.Memories.Add(char, { text = "A suggestion", visibility = "public" }, "suggested", 1))
			expect.equal(m.provenance, "suggested")
			expect.equal(m.status, "proposed")
			expect.equal(m.visibility, "private")
			local _, err = ns.Memories.SetVisibility(char, m.id, "public", 2)
			expect.truthy(err:find("established"))
			assert(ns.Memories.Accept(char, m.id, 3))
			assert(ns.Memories.SetVisibility(char, m.id, "public", 4))
			assert(ns.Memories.Dispute(char, m.id, 5))
			expect.equal(m.visibility, "private", "disputing withdraws it from public")
		end)

		t:it("player-authored records are established; established suggestions cannot be deleted", function()
			local ns, char = setup()
			local own = assert(ns.Memories.Add(char, { text = "Mine" }, "player", 1))
			expect.equal(own.status, "established")
			local s = ns.Memories.Add(char, { text = "Theirs" }, "suggested", 2)
			ns.Memories.Accept(char, s.id, 3)
			local _, err = ns.Memories.Remove(char, s.id)
			expect.truthy(err:find("dispute or supersede"))
			assert(ns.Memories.Supersede(char, s.id, own.id, 4))
			expect.equal(s.status, "superseded")
			expect.equal(s.supersededBy, own.id)
			assert(ns.Memories.Remove(char, own.id))
		end)

		t:it("loading repairs records: unknown provenance becomes suggested, public non-canon becomes private", function()
			local ns, char = setup()
			char.story.memories = { { id = 5, provenance = "magic", status = "proposed", visibility = "public", text = "x" },
				{ id = 6, status = "nonsense", text = "y" }, { id = "bad", text = "z" } }
			local clean = ns.Schema.NormalizeCharacter(char)
			expect.equal(#clean.story.memories, 2)
			expect.equal(clean.story.memories[1].provenance, "suggested")
			expect.equal(clean.story.memories[1].visibility, "private")
			expect.equal(clean.story.memories[2].status, "proposed")
			expect.truthy(clean.story.nextId > 6)
		end)
	end)

	t:describe("memories and arcs (#12, #19)", function()
		t:it("a notable answer is suggested as a memory; a routine one is not", function()
			local ns, char, fx = setup()
			local first = answer(ns, char, fx, 1, { optionId = "resolve" })      -- first quest in a zone: notable
			expect.truthy(first.memory)
			expect.equal(first.memory.status, "proposed")
			expect.deepEqual(first.memory.tags, { "protecting others" })
			expect.equal(first.memory.links.decisions[1], first.decision.id)
			local routine = answer(ns, char, fx, 2, { optionId = "resolve" })    -- same zone: routine
			expect.equal(routine.memory, nil)
			local custom = answer(ns, char, fx, 3, { custom = "They lied to the guard." })
			expect.truthy(custom.memory, "the player's own words are always worth suggesting")
		end)

		t:it("the same quests with different answers give different arcs", function()
			local arcs = {}
			for i, choice in ipairs({ "resolve", "ambition" }) do
				local ns, char, fx = setup(Fixtures.CHARACTERS[i])
				for q = 1, 3 do
					answer(ns, char, fx, q, { optionId = choice }, { zone = "Zone" .. q })
				end
				expect.equal(#char.story.arcs, 1)
				arcs[i] = char.story.arcs[1]
				expect.equal(arcs[i].status, "proposed")
				expect.equal(#arcs[i].links.decisions, 3)
			end
			expect.equal(arcs[1].title, "A thread of protecting others")
			expect.equal(arcs[2].title, "A thread of ambition")
		end)

		t:it("arcs can be accepted, renamed, paused, given turning points and concluded", function()
			local ns, char = setup()
			local arc = assert(ns.Arcs.Add(char, { title = "Debt to the Syndicate", kind = "conflict" }, "player", 1))
			assert(ns.Arcs.Rename(char, arc.id, "The Syndicate debt", 2))
			assert(ns.Arcs.SetState(char, arc.id, "paused", 3))
			assert(ns.Arcs.AddTurningPoint(char, arc.id, "Paid half of it back", nil, 4))
			assert(ns.Arcs.SetState(char, arc.id, "concluded", 5))
			expect.equal(arc.title, "The Syndicate debt")
			expect.equal(#arc.turningPoints, 1)
			expect.falsy(ns.Arcs.SetState(char, arc.id, "won", 6))
		end)
	end)

	t:describe("goals (#27)", function()
		t:it("objective progress is verified from events but never completes the goal", function()
			local ns, char, fx = setup()
			local goal = assert(ns.Goals.Add(char, { title = "Become strong enough to return home",
				objective = { kind = "level", target = 30 } }, 1))
			expect.equal(goal.visibility, "private")
			expect.falsy(ns.Goals.Progress(char, goal).objective.met)
			ns.GameEvents.Record(char, "levelup", Fixtures.Context(fx, { level = 30 }), 2)
			local p = ns.Goals.Progress(char, goal)
			expect.truthy(p.objective.met)
			expect.equal(goal.state, "active", "only the player decides it is achieved")
		end)

		t:it("subjective milestones are marked only by the player", function()
			local ns, char = setup()
			local goal = ns.Goals.Add(char, { title = "Earn forgiveness" }, 1)
			ns.Goals.AddMilestone(char, goal.id, "Apologise to my brother", 2)
			expect.equal(ns.Goals.Progress(char, goal).milestonesDone, 0)
			ns.Goals.SetMilestone(char, goal.id, 1, true, 3)
			expect.equal(ns.Goals.Progress(char, goal).milestonesDone, 1)
			expect.equal(ns.Goals.Progress(char, goal).objective, nil)
			assert(ns.Goals.SetState(char, goal.id, "unresolved", 4))
		end)
	end)

	t:describe("public persona vs private convictions (#30)", function()
		t:it("a public stance can hide a private resentment from every public output", function()
			local ns, char = setup(Fixtures.CHARACTERS[4])
			local stance = assert(ns.Identity.Add(char, { subject = "Undercity", persona = "Loyal servant of the Dark Lady",
				conviction = "PRIVATE-RESENTMENT of everything she did", visibility = "public" }, 1))
			expect.equal(stance.convictionVisibility, "private")
			local public = ns.Projection.GetPublic(char)
			expect.deepEqual(public.stances, { { subject = "Undercity", persona = "Loyal servant of the Dark Lady" } })
			local block = ns.TRP3AboutBlock.Compose(public)
			expect.truthy(block:find("Where they stand:", 1, true))
			expect.falsy(block:find("PRIVATE", 1, true))
			local share = ns.Transfer.Export(char, "share", {})
			expect.falsy(share:find("PRIVATE-RESENTMENT", 1, true))
		end)

		t:it("observed standing never becomes a stance by itself", function()
			local ns, char, fx = setup()
			ns.GameEvents.Record(char, "levelup", Fixtures.Context(fx, { level = 60 }), 1)
			expect.equal(#char.story.identity, 0)
			expect.deepEqual(ns.Projection.GetPublic(char).stances, {})
		end)
	end)

	t:describe("Story Director (#20, #25)", function()
		t:it("the same event gives different prompts for different histories", function()
			local views = {}
			for i = 1, 2 do
				local ns, char, fx = setup()
				if i == 2 then
					ns.Goals.Add(char, { title = "Find my sister" }, 1)
					ns.Arcs.Add(char, { title = "The long road home" }, "player", 1)
				end
				local record = ns.GameEvents.Record(char, "quest", Fixtures.Context(fx, { questId = 1, title = "Same" }), 2)
				views[i] = ns.Reactions.Present(char, ns.Reactions.Consider(char, record, 2, 2), 2)
			end
			expect.equal(views[1].question, views[2].question, "the universal question is the same")
			expect.equal(#views[2].options, #views[1].options + 2)
			expect.truthy(views[2].options[#views[2].options - 2].text:find("Find my sister", 1, true))
			expect.truthy(views[2].options[#views[2].options - 1].text:find("The long road home", 1, true))
			expect.equal(views[2].options[#views[2].options].id, "nothing", "neutral answer stays last")
		end)

		t:it("only established records count, and a removed record stops mattering at once", function()
			local ns, char, fx = setup()
			local proposed = ns.Arcs.Add(char, { title = "Suggested arc" }, "suggested", 1)
			local goal = ns.Goals.Add(char, { title = "Temporary goal" }, 1)
			local record = ns.GameEvents.Record(char, "quest", Fixtures.Context(fx, { questId = 1, title = "Q" }), 2)
			local reaction = ns.Reactions.Consider(char, record, 2, 2)
			local view = ns.Reactions.Present(char, reaction, 2)
			for _, o in ipairs(view.options) do
				expect.falsy(o.arcId == proposed.id, "a proposed arc has no influence")
			end
			expect.truthy(ns.Reactions.FindOption(view, "goal:" .. goal.id))
			ns.Goals.Remove(char, goal.id)
			view = ns.Reactions.Present(char, reaction, 2)
			expect.falsy(ns.Reactions.FindOption(view, "goal:" .. goal.id))
		end)

		t:it("choosing a contextual answer links it to the goal or arc, without marking progress", function()
			local ns, char, fx = setup()
			local arc = ns.Arcs.Add(char, { title = "Atonement" }, "player", 1)
			local result = answer(ns, char, fx, 1, { optionId = "arc:" .. arc.id })
			expect.equal(#arc.turningPoints, 1)
			expect.equal(arc.links.decisions[1], result.decision.id)
			expect.equal(#result.changes, 0, "contextual answers have no personality effect")
		end)

		t:it("recalls a relevant memory and explains why a moment appeared", function()
			local ns, char, fx = setup()
			ns.Memories.Add(char, { title = "The burning farm", zone = "Westfall", importance = 3 }, "player", 1)
			local record = ns.GameEvents.Record(char, "quest", Fixtures.Context(fx, { questId = 1, title = "Q",
				questLevel = 23 }), 2)
			local view = ns.Reactions.Present(char, ns.Reactions.Consider(char, record, 2, 2), 2)
			expect.equal(view.recall, "Remembering: The burning farm")
			expect.truthy(view.why[1]:find("level 23", 1, true))
		end)
	end)

	t:describe("continuity review (#42)", function()
		t:it("finds contradictions and asks; it never changes canon by itself", function()
			local ns, char = setup(Fixtures.CHARACTERS[6]) -- courage 2 (Cautious)
			ns.Facts.Add(char, { category = "trait", statement = "Bold beyond reason" }, nil, 1)
			ns.Identity.Add(char, { subject = "The Horde", persona = "Proud warrior", conviction = "Wants to desert" }, 1)
			local findings = ns.Continuity.Findings(char)
			local kinds = {}
			for _, f in ipairs(findings) do kinds[f.kind] = true end
			expect.truthy(kinds.personality and kinds.persona)
			local before = ns.Util.DeepCopy(char.facts)
			for _, f in ipairs(findings) do
				if f.kind == "persona" then
					assert(ns.Continuity.Review(char, f.key, "secret", nil, 2))
				else
					assert(ns.Continuity.Review(char, f.key, "growth", nil, 2))
				end
			end
			expect.deepEqual(char.facts, before, "canon is untouched")
			expect.equal(#ns.Continuity.Findings(char), 0, "answered findings do not come back")
			expect.equal(char.story.identity[1].convictionVisibility, "secret")
			expect.falsy(ns.Continuity.Review(char, "nope", "growth"))
		end)

		t:it("flags a met goal, duplicate memories and public records linked to secrets", function()
			local ns, char, fx = setup()
			ns.Goals.Add(char, { title = "Reach 10", objective = { kind = "level", target = 10 } }, 1)
			ns.GameEvents.Record(char, "levelup", Fixtures.Context(fx, { level = 10 }), 2)
			ns.Memories.Add(char, { title = "Same" }, "player", 3)
			local secret = ns.Memories.Add(char, { title = "Same", visibility = "secret" }, "player", 4)
			local public = ns.Memories.Add(char, { title = "Open", visibility = "public", links = { memories = { secret.id } } },
				"player", 5)
			expect.truthy(public)
			local kinds = {}
			for _, f in ipairs(ns.Continuity.Findings(char)) do kinds[f.kind] = true end
			expect.truthy(kinds.goal and kinds.duplicate and kinds.privacy)
		end)
	end)

	t:describe("narrative commands (L2)", function()
		t:it("memory, arc, goal, stance and continuity work from chat and persist", function()
			local mock, env = Boot.Start()
			mock.Slash("set name Zanjin")
			expect.truthy(mock.Slash("memory add The night the river flooded"):find("Added memory"))
			expect.truthy(mock.Slash("arc add Finding a home"):find("Added arc"))
			local goal = mock.Slash("goal add Master the old songs")
			local goalId = goal:match("#(%d+)")
			expect.truthy(mock.Slash("goal level " .. goalId .. " 40"):find("level 40"))
			expect.truthy(mock.Slash("goal milestone " .. goalId .. " Learn the first song"):find("milestone"))
			expect.truthy(mock.Slash("stance add Orgrimmar; Loyal to the Warchief; Doubts the Warchief")
				:find("Added stance"))
			expect.truthy(mock.Slash("continuity"):find("Doubts the Warchief", 1, true))
			expect.truthy(mock.Slash("continuity 1 unreliable"):find("unreliable"))
			local story = env.DawnwardChroniclesDB.characters["Testchar-TestRealm"].story
			expect.equal(#story.memories, 1)
			expect.equal(#story.arcs, 1)
			expect.equal(story.goals[1].objective.target, 40)
			expect.equal(#story.reviews, 1)
			expect.truthy(mock.Slash("memory remove 1"):find("confirm"))
			expect.truthy(mock.Slash("stance list"):find("Orgrimmar", 1, true))
		end)
	end)
end
