-- L1/L2: bounded growth and cost under excessive event frequency.
-- Timings are generous upper bounds on a CI machine, not WoW client
-- measurements (no in-game profiling has been done).
local Loader = require("support.loader")
local Fixtures = require("fixtures.characters")
local Boot = require("support.boot")

return function(t, expect)
	t:describe("performance and bounded growth", function()
		t:it("2,000 events keep every saved list within its limit", function()
			local ns = Loader.Core()
			local fx = Fixtures.CHARACTERS[2]
			local char = Fixtures.Character(ns, fx)
			char.story.prefs.frequency = "frequent"
			local started = os.clock()
			for i = 1, 2000 do
				local data = Fixtures.Context(fx, { questId = i, title = "Q" .. i, zone = "Zone" .. (i % 400) })
				local record = ns.GameEvents.Record(char, "quest", data, i * 1000)
				if record then ns.Reactions.Consider(char, record, i * 1000) end
				local reaction = char.story.reactions[1]
				if reaction and i % 3 == 0 then
					ns.Decisions.Decide(char, reaction.id, { optionId = "nothing" }, i * 1000 + 1)
				end
			end
			local elapsed = os.clock() - started
			local L = ns.StorySchema.LIMITS
			expect.truthy(#char.story.events <= L.events, "events " .. #char.story.events)
			expect.truthy(ns.Util.CountKeys(char.story.eventKeys) <= L.eventKeys)
			expect.truthy(#char.story.reactions <= L.reactions)
			expect.truthy(#char.story.decisions <= L.decisions)
			expect.truthy(#char.story.memories <= ns.RecordTypes.LIMITS.memories)
			expect.truthy(#char.journal <= ns.Schema.JOURNAL.limit)
			expect.truthy(elapsed < 20, string.format("took %.2fs", elapsed))
		end)

		t:it("a burst of UPDATE_FACTION and zone events never schedules more than one check", function()
			local mock = Boot.Start()
			mock.Slash("set name A")
			mock.factions = {}
			for i = 1, 60 do mock.factions[i] = { id = i, name = "F" .. i, standing = 4 } end
			for _ = 1, 200 do mock.Fire("UPDATE_FACTION") end
			for i = 1, 60 do mock.factions[i].standing = 5 end
			for i = 1, 50 do
				mock.zone = "Zone" .. i
				mock.Fire("ZONE_CHANGED_NEW_AREA")
				mock.Fire("UPDATE_FACTION")
			end
			expect.truthy(#mock.timers <= 2, "timers " .. #mock.timers)
		end)
	end)
end
