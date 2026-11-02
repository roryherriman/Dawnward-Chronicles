-- L2: the living chronicle through the whole addon under the WoW mock
-- (mocked client; not in-game evidence).
local Boot = require("support.boot")

return function(t, expect)
	local KEY = "Testchar-TestRealm"

	local function start(opts)
		local mock, env, ns = Boot.Start(opts)
		mock.Slash("set name Grasha")
		return mock, env, ns
	end

	local function turnIn(mock, id, title, level)
		mock.quest = { id = id, title = title, level = level }
		mock.Fire("QUEST_COMPLETE")
		mock.Fire("QUEST_TURNED_IN", id, 420, 90)
	end

	t:describe("living chronicle loop (L2)", function()
		t:it("quest -> safe notice -> answer -> approval -> draft -> defining moment in the profile", function()
			local mock, env, ns = start()
			turnIn(mock, 1234, "Burning Blade Medallion", 22)
			local char = env.DawnwardChroniclesDB.characters[KEY]
			local record = char.story.events[1]
			expect.equal(record.key, "quest:1234")
			expect.equal(record.meta.title, "Burning Blade Medallion")
			expect.equal(record.meta.questLevel, 22)
			expect.equal(record.class, "MAGE")
			expect.equal(record.faction, "Horde")
			expect.equal(#char.story.reactions, 1)
			-- Announced only once the scheduled safe-time check runs.
			mock.chat = {}
			mock.RunTimers()
			local notice = table.concat(mock.chat, "\n")
			expect.truthy(notice:find("A moment for your story", 1, true), notice)
			expect.truthy(notice:find("Burning Blade Medallion", 1, true), notice)

			local shown = mock.Slash("story 1")
			expect.truthy(shown:find("1%. "), shown)
			local answer = mock.Slash("story 1 1")
			expect.truthy(answer:find("Decision recorded"), answer)
			expect.truthy(answer:find("waiting for your approval"), answer)
			expect.equal(#char.story.reactions, 0)

			local develop = mock.Slash("develop")
			local changeId = tonumber(develop:match("#(%d+) toward"))
			expect.truthy(changeId, develop)
			expect.truthy(mock.Slash("develop approve " .. changeId):find("Applied"))

			local entry = char.journal[#char.journal]
			expect.equal(entry.kind, "story")
			expect.equal(entry.visibility, "private")
			expect.truthy(mock.Slash("journal approve " .. entry.id):find("Approved"))
			expect.truthy(mock.Slash("journal important " .. entry.id):find("defining", 1, true))
			-- v0.10: an approved defining moment is part of the profile.
			ns.Publication.Adopt(char, 1)
			local moments = ns.Projection.GetPublic(char).journal
			expect.equal(#moments, 1)
			expect.equal(moments[1].id, entry.id)
			expect.truthy(mock.Slash("journal list"):find("[story]", 1, true))
		end)

		t:it("never announces during combat or while dead; waits for a calm moment", function()
			local mock = start()
			mock.inCombat = true
			turnIn(mock, 5, "A Task", 20)
			mock.chat = {}
			mock.RunTimers()
			expect.falsy(table.concat(mock.chat, "\n"):find("A moment for your story", 1, true))
			mock.inCombat = false
			mock.dead = true
			mock.Fire("PLAYER_REGEN_ENABLED")
			mock.RunTimers()
			expect.falsy(table.concat(mock.chat, "\n"):find("A moment for your story", 1, true))
			mock.dead = false
			mock.Fire("PLAYER_UNGHOST")
			mock.RunTimers()
			expect.truthy(table.concat(mock.chat, "\n"):find("A moment for your story", 1, true))
		end)

		t:it("is quiet for routine quests during the cooldown, and never records a quest twice", function()
			local mock, env = start()
			turnIn(mock, 1, "First", 20)
			mock.zone = "Durotar"
			turnIn(mock, 2, "Second", 20)
			mock.Fire("QUEST_TURNED_IN", 1, 0, 0)
			local char = env.DawnwardChroniclesDB.characters[KEY]
			expect.equal(#char.story.events, 2)
			expect.equal(#char.story.reactions, 1)
		end)

		t:it("uses the quest log title when the reward panel was not seen, else stays partial", function()
			local mock, env = start()
			mock.questTitles = { [77] = "From The Log" }
			mock.Fire("QUEST_TURNED_IN", 77, 0, 0)
			mock.Fire("QUEST_TURNED_IN", 78, 0, 0)
			local events = env.DawnwardChroniclesDB.characters[KEY].story.events
			expect.equal(events[1].meta.title, "From The Log")
			expect.equal(events[2].confidence, "partial")
		end)

		t:it("records deaths and level-ups alongside the existing milestones", function()
			local mock, env = start()
			mock.Fire("PLAYER_DEAD")
			mock.Fire("PLAYER_LEVEL_UP", 30)
			local char = env.DawnwardChroniclesDB.characters[KEY]
			local cats = {}
			for _, e in ipairs(char.story.events) do cats[e.category] = true end
			expect.truthy(cats.death and cats.levelup)
			expect.truthy(char.journalKeys["levelup:30"], "the v0.2 milestone is still recorded")
		end)

		t:it("real events go to real data in simulation mode; sim quest goes to simulation data", function()
			local mock, env = start()
			mock.Slash("sim on")
			turnIn(mock, 9, "Real Quest", 20)
			expect.equal(#env.DawnwardChroniclesDB.characters[KEY].story.events, 1)
			local message = mock.Slash("sim quest 501 Practice Quest")
			expect.truthy(message:find("story reaction is waiting"), message)
			expect.equal(#env.DawnwardChroniclesSimDB.characters[KEY].story.events, 1)
			expect.truthy(mock.Slash("sim quest 501 Practice Quest"):find("duplicate"))
			expect.truthy(mock.Slash("story"):find("Practice Quest", 1, true))
		end)

		t:it("settings, tracking and dismiss work from chat", function()
			local mock, env = start()
			expect.truthy(mock.Slash("story set frequency rare"):find("rare"))
			expect.truthy(mock.Slash("story set threshold 9"):find("invalid"))
			expect.truthy(mock.Slash("story track quest off"):find("off"))
			turnIn(mock, 3, "Untracked", 20)
			local char = env.DawnwardChroniclesDB.characters[KEY]
			expect.equal(#char.story.events, 0)
			mock.Slash("story track quest on")
			turnIn(mock, 4, "Tracked", 20)
			expect.truthy(mock.Slash("story 1 dismiss"):find("dismissed"))
			expect.equal(#char.story.reactions, 0)
			expect.truthy(mock.Slash("story settings"):find("frequency rare"))
		end)

		t:it("an observer failure never breaks the game", function()
			local mock = start()
			mock.env.UnitClass = function() error("boom") end
			mock.env.GetQuestID = function() error("boom") end
			mock.Fire("QUEST_COMPLETE")
			mock.Fire("QUEST_TURNED_IN", 11, 0, 0)
			expect.truthy(true)
		end)

		t:it("read-only saved data records nothing and announces nothing", function()
			local saved = { schemaVersion = 99, characters = {} }
			local mock, env = Boot.Start({ savedVariables = { DawnwardChroniclesDB = saved } })
			turnIn(mock, 1, "X", 20)
			mock.RunTimers()
			expect.deepEqual(env.DawnwardChroniclesDB, { schemaVersion = 99, characters = {} })
		end)
	end)
end
