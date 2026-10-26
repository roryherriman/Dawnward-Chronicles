-- L1/L2: observed reputation, zones, instances and guilds (#11, #18, #36)
-- and people records (#18, #28, #37). Mocked client; not in-game evidence.
local Loader = require("support.loader")
local Fixtures = require("fixtures.characters")
local Boot = require("support.boot")

return function(t, expect)
	local KEY = "Testchar-TestRealm"

	t:describe("observed standings (#18)", function()
		t:it("the first reading is a silent baseline; tier changes become events once", function()
			local ns = Loader.Core()
			local char = Fixtures.Character(ns, Fixtures.CHARACTERS[1])
			expect.deepEqual(ns.Observed.CompareStandings(char, { { id = 72, name = "Stormwind", standing = 7 } }), {})
			expect.deepEqual(ns.Observed.CompareStandings(char, { { id = 72, name = "Stormwind", standing = 7 } }), {})
			local changes = ns.Observed.CompareStandings(char, { { id = 72, name = "Stormwind", standing = 8 } })
			expect.equal(#changes, 1)
			expect.equal(changes[1].previous, 7)
			local record = assert(ns.GameEvents.Record(char, "reputation", changes[1], 10))
			expect.equal(record.key, "reputation:72:8")
			expect.equal(record.significance, 3)
			local _, dup = ns.GameEvents.Record(char, "reputation", changes[1], 11)
			expect.equal(dup, "duplicate")
		end)

		t:it("Exalted is an observation, never an attitude", function()
			local ns = Loader.WithTRP3()
			local char = Fixtures.Character(ns, Fixtures.CHARACTERS[4])
			ns.Observed.CompareStandings(char, { { id = 68, name = "Undercity", standing = 7 } })
			local change = ns.Observed.CompareStandings(char, { { id = 68, name = "Undercity", standing = 8 } })[1]
			ns.GameEvents.Record(char, "reputation", change, 1)
			expect.equal(#char.story.identity, 0, "no stance is created")
			expect.deepEqual(ns.Projection.GetPublic(char).stances, {})
			-- The player may resent a faction they are Exalted with.
			ns.Identity.Add(char, { subject = "Undercity", persona = "Exalted, and says the right things",
				conviction = "Hates what it has become", visibility = "public" }, 2)
			local block = ns.TRP3AboutBlock.Compose(ns.Projection.GetPublic(char))
			expect.falsy(block:find("Hates", 1, true))
		end)

		t:it("the reputation question uses the observed names and stays universal", function()
			local ns = Loader.Core()
			local fx = Fixtures.CHARACTERS[2]
			local char = Fixtures.Character(ns, fx)
			local data = Fixtures.Context(fx, { factionId = 76, factionName = "Orgrimmar", standing = 6, previous = 5 })
			local record = ns.GameEvents.Record(char, "reputation", data, 1)
			local view = ns.Reactions.Present(char, ns.Reactions.Consider(char, record, 1), 1)
			expect.equal(view.question, "Grasha is now Honored with Orgrimmar. What does that standing mean to them?")
		end)
	end)

	t:describe("guild membership (#36)", function()
		t:it("first reading is a baseline; joining and leaving are recorded; rank changes are not", function()
			local ns = Loader.Core()
			local char = Fixtures.Character(ns, Fixtures.CHARACTERS[3])
			expect.equal(ns.Observed.CompareGuild(char, { name = "Wardens", rank = "Member" }), nil)
			expect.equal(ns.Observed.CompareGuild(char, { name = "Wardens", rank = "Officer" }), nil)
			local left = ns.Observed.CompareGuild(char, nil)
			expect.equal(left.previousGuild, "Wardens")
			local joined = ns.Observed.CompareGuild(char, { name = "Ash Pact", rank = "Initiate" })
			expect.equal(joined.guildName, "Ash Pact")
		end)
	end)

	t:describe("people (#18, #28, #37)", function()
		t:it("players are keyed by name and realm and never merged", function()
			local ns = Loader.Core()
			local char = Fixtures.Character(ns, Fixtures.CHARACTERS[5])
			local a = assert(ns.People.Add(char, { kind = "player", name = "Elra", realm = "Argent Dawn",
				relation = "Travelled together" }, 1))
			expect.equal(a.visibility, "private")
			assert(ns.People.Add(char, { kind = "player", name = "Elra", realm = "Shadowmoon" }, 2))
			local _, dup = ns.People.Add(char, { kind = "player", name = "elra", realm = "argent dawn" }, 3)
			expect.truthy(dup:find("already"))
			local _, noRealm = ns.People.Add(char, { kind = "player", name = "Nobody" }, 4)
			expect.truthy(noRealm:find("realm"))
			assert(ns.People.Add(char, { kind = "npc", name = "Old Blanchy", relation = "A horse they once fed" }, 5))
		end)
	end)

	t:describe("observers through the addon (L2)", function()
		local function start()
			local mock, env = Boot.Start()
			mock.Slash("set name Tester")
			return mock, env
		end

		t:it("reputation tier changes after the baseline become story events", function()
			local mock, env = start()
			mock.factions = { { id = 72, name = "Stormwind", standing = 5 }, { name = "Alliance", header = true, id = 469,
				standing = 5 } }
			mock.Fire("UPDATE_FACTION")
			local story = env.DawnwardChroniclesDB.characters[KEY].story
			expect.equal(#story.events, 0, "baseline only")
			expect.truthy(story.observed.baseline)
			expect.equal(story.observed.standings[469], nil, "headers without reputation are skipped")
			mock.factions[1].standing = 6
			mock.Fire("UPDATE_FACTION")
			expect.equal(story.events[1].key, "reputation:72:6")
			mock.Fire("UPDATE_FACTION")
			expect.equal(#story.events, 1, "no repeat")
		end)

		t:it("records first zone visits and instance entries", function()
			local mock, env = start()
			mock.zone = "Ashenvale"
			mock.Fire("ZONE_CHANGED_NEW_AREA")
			mock.Fire("ZONE_CHANGED_NEW_AREA")
			mock.zone, mock.instanceType, mock.instanceName = "Wailing Caverns", "party", "Wailing Caverns"
			mock.Fire("ZONE_CHANGED_NEW_AREA")
			local story = env.DawnwardChroniclesDB.characters[KEY].story
			expect.equal(#story.events, 2)
			expect.equal(story.events[1].key, "zone:Ashenvale")
			expect.equal(story.events[2].key, "instance:Wailing Caverns")
		end)

		t:it("ignores inconclusive guild readings at login", function()
			local mock, env = start()
			mock.guildKnown = false
			mock.Fire("PLAYER_ENTERING_WORLD")
			local story = env.DawnwardChroniclesDB.characters[KEY].story
			expect.falsy(story.observed.guildSeen)
			mock.guildKnown = nil
			mock.guild = { name = "Wardens", rank = "Member" }
			mock.Fire("PLAYER_GUILD_UPDATE")
			expect.truthy(story.observed.guildSeen)
			expect.equal(#story.events, 0, "baseline")
			mock.guild = { name = "New Dawn", rank = "Initiate" }
			mock.Fire("PLAYER_GUILD_UPDATE")
			expect.equal(story.events[1].meta.guildName, "New Dawn")
		end)

		t:it("does not create a record for a character that never used Dawnward", function()
			local mock, env = Boot.Start()
			mock.factions = { { id = 72, name = "Stormwind", standing = 5 } }
			mock.Fire("UPDATE_FACTION")
			mock.guild = { name = "Wardens" }
			mock.Fire("PLAYER_GUILD_UPDATE")
			expect.equal(env.DawnwardChroniclesDB.characters[KEY], nil)
		end)

		t:it("person commands work and keep feelings private", function()
			local mock, env = start()
			expect.truthy(mock.Slash("person add player Elra-ArgentDawn; Saved my life in Stratholme"):find("Added"))
			expect.truthy(mock.Slash("person feel 1 Owes her more than she knows"):find("private"))
			local p = env.DawnwardChroniclesDB.characters[KEY].story.people[1]
			expect.equal(p.realm, "ArgentDawn")
			expect.equal(p.feelingsVisibility, "private")
		end)
	end)
end
