-- Regressions for the pre-merge safety review of the v0.4 branch.
local Loader = require("support.loader")
local Fixtures = require("fixtures.characters")
local Boot = require("support.boot")

return function(t, expect)
	local KEY = "Testchar-TestRealm"

	local function answered(ns, char, n, optionIndex)
		local fx = Fixtures.CHARACTERS[1]
		local now = 1000
		for i = 1, n do
			now = now + 4 * 3600
			char.story.pacing.lastByCategory = {}
			local record = ns.GameEvents.Record(char, "quest", Fixtures.Context(fx, { questId = i,
				title = "A fairly ordinary quest title " .. i, zone = "Zone " .. (i % 40) }), now)
			local reaction = record and ns.Reactions.Consider(char, record, now)
			if reaction then
				local view = ns.Reactions.Present(char, reaction)
				ns.Decisions.Decide(char, reaction.id, { optionId = view.options[optionIndex or 1].id }, now)
			end
		end
		return now
	end

	t:describe("v0.4 review regressions", function()
		t:it("1. a backup without secrets carries no secret story content, and restoring keeps the secrets", function()
			local ns = Loader.WithTRP3()
			local char = Fixtures.Character(ns, Fixtures.CHARACTERS[4])
			ns.Identity.Add(char, { subject = "Undercity", persona = "Loyal", conviction = "SECRET-CONVICTION",
				convictionVisibility = "secret" }, 1)
			local person = ns.People.Add(char, { kind = "npc", name = "Varimathras", feelings = "SECRET-FEELINGS",
				feelingsVisibility = "secret" }, 2)
			ns.Memories.Add(char, { text = "SECRET-MEMORY", visibility = "secret" }, "player", 3)
			local fx = Fixtures.CHARACTERS[4]
			local record = ns.GameEvents.Record(char, "quest", Fixtures.Context(fx, { questId = 1, title = "Q" }), 4)
			local reaction = ns.Reactions.Consider(char, record, 4)
			local result = ns.Decisions.Decide(char, reaction.id, { custom = "SECRET-WORDS" }, 5)
			ns.Journal.SetVisibility(char, result.entry.id, "secret", 6)

			local backup = assert(ns.Transfer.Export(char, "backup", { includeSecrets = false }))
			for _, secret in ipairs({ "SECRET-CONVICTION", "SECRET-FEELINGS", "SECRET-MEMORY", "SECRET-WORDS" }) do
				expect.falsy(backup:find(secret, 1, true), secret .. " must not be in a backup without secrets")
			end
			local plan = assert(ns.Transfer.Decode(backup))
			local restored = ns.Transfer.MergeForImport(char, plan.character, false, 7, false, plan.includesStory)
			local story = restored.story
			expect.equal(story.identity[1].conviction, "SECRET-CONVICTION", "kept from the current character")
			expect.equal(ns.Records.Find(story.people, person.id).feelings, "SECRET-FEELINGS")
			local found = false
			for _, m in ipairs(story.memories) do if m.text == "SECRET-MEMORY" then found = true end end
			expect.truthy(found)
			expect.equal(story.decisions[1].custom, "SECRET-WORDS")

			local full = assert(ns.Transfer.Export(char, "backup", { includeSecrets = true }))
			expect.truthy(full:find("SECRET-CONVICTION", 1, true), "included when the player asks for secrets")
		end)

		t:it("2. a long-played character's backup can always be imported again, or is refused", function()
			local ns = Loader.WithTRP3()
			local char = ns.Schema.NewCharacter(0)
			answered(ns, char, 400)
			local backup = assert(ns.Transfer.Export(char, "backup", {}))
			expect.truthy(#backup <= ns.Serializer.MAX_INPUT)
			local plan, err = ns.Transfer.Decode(backup)
			expect.truthy(plan, err)
			expect.equal(#plan.character.story.decisions, #char.story.decisions)
			local saved = ns.Serializer.MAX_INPUT
			ns.Serializer.MAX_INPUT = 1000
			local refused, why = ns.Transfer.Export(char, "backup", {})
			ns.Serializer.MAX_INPUT = saved
			expect.falsy(refused)
			expect.truthy(why:find("more than can be imported", 1, true))
		end)

		t:it("3. a character that never used Dawnward gets no profile, events or prompts", function()
			local mock, env = Boot.Start()
			mock.Fire("ZONE_CHANGED_NEW_AREA")
			mock.quest = { id = 1, title = "Q", level = 20 }
			mock.Fire("QUEST_COMPLETE")
			mock.Fire("QUEST_TURNED_IN", 1, 0, 0)
			mock.Fire("PLAYER_DEAD")
			mock.chat = {}
			mock.RunTimers()
			expect.equal(env.DawnwardChroniclesDB.characters[KEY], nil)
			expect.falsy(table.concat(mock.chat, "\n"):find("A moment for your story", 1, true))
		end)

		t:it("4. the answers shown are always the answers accepted, whatever the time", function()
			local ns = Loader.WithTRP3()
			local fx = Fixtures.CHARACTERS[1]
			local char = Fixtures.Character(ns, fx)
			ns.Goals.Add(char, { title = "Old goal" }, 1)
			ns.Goals.Add(char, { title = "Recent goal" }, 10 ^ 7)
			local record = ns.GameEvents.Record(char, "quest", Fixtures.Context(fx, { questId = 1, title = "Q" }), 10 ^ 7 + 5)
			local reaction = ns.Reactions.Consider(char, record, 10 ^ 7 + 5)
			local shown = ns.Reactions.Present(char, reaction)
			local goalOption
			for _, o in ipairs(shown.options) do if o.goalId then goalOption = o end end
			-- Decided much later (the chat list and the decision use no clock).
			local result = ns.Decisions.Decide(char, reaction.id, { optionId = goalOption.id }, 10 ^ 9)
			expect.truthy(result, "the shown goal answer is accepted")
		end)

		t:it("5. pending changes stop growing at a cap, and loading never drops them", function()
			local ns = Loader.WithTRP3()
			local char = ns.Schema.NewCharacter(0)
			answered(ns, char, 120)
			local pending = #ns.Evolution.Pending(char)
			expect.equal(pending, ns.Evolution.MAX_PENDING)
			for i = 1, 400 do
				char.story.changes[#char.story.changes + 1] = { id = 100000 + i, axis = "courage", delta = 1,
					status = "applied", at = i, decidedAt = i, from = 1, to = 2 }
			end
			local clean = ns.Schema.NormalizeCharacter(ns.Util.DeepCopy(char))
			expect.equal(#ns.Evolution.Pending(clean), pending, "pending proposals survive normalisation")
		end)

		t:it("6. no notice about a real moment while simulation mode is on; it waits", function()
			local mock = Boot.Start()
			mock.Slash("set name Sim")
			mock.Slash("sim on")
			mock.quest = { id = 9, title = "Real Quest", level = 20 }
			mock.Fire("QUEST_COMPLETE")
			mock.Fire("QUEST_TURNED_IN", 9, 0, 0)
			mock.chat = {}
			mock.RunTimers()
			expect.falsy(table.concat(mock.chat, "\n"):find("A moment for your story", 1, true))
			mock.Slash("sim off")
			mock.Fire("PLAYER_REGEN_ENABLED")
			mock.chat = {}
			mock.RunTimers()
			expect.truthy(table.concat(mock.chat, "\n"):find("Real Quest", 1, true))
		end)

		t:it("disputing a record withdraws every public side at once", function()
			local ns = Loader.WithTRP3()
			local char = Fixtures.Character(ns, Fixtures.CHARACTERS[1])
			local i = ns.Identity.Add(char, { subject = "S", persona = "P", conviction = "C", visibility = "public",
				convictionVisibility = "public" }, 1)
			ns.Records.Dispute(char.story.identity, i.id, 2)
			expect.equal(i.visibility, "private")
			expect.equal(i.convictionVisibility, "private")
		end)

		t:it("7. the import confirmation says the story will be replaced", function()
			local ns = Loader.WithTRP3()
			local char = Fixtures.Character(ns, Fixtures.CHARACTERS[1])
			local plan = assert(ns.Transfer.Decode(assert(ns.Transfer.Export(char, "backup", {}))))
			expect.truthy(ns.Transfer.Describe(plan):find("replaces your story", 1, true))
		end)
	end)
end
