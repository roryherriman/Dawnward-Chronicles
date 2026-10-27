-- L1: weighted location relevance in the Story Director. A place asks a
-- question by how much it matters to this character, not by rule.
local Loader = require("support.loader")

return function(t, expect)
	local function setup()
		local ns = Loader.Core()
		local char = ns.Schema.NewCharacter(1)
		return ns, char
	end

	-- A first visit (or other visit) record as GameEvents would build it.
	local tick = 1000
	local function record(ns, char, visit, kind, at, subzone)
		tick = tick + 1
		at = at or tick
		local r = assert(ns.GameEvents.Record(char, "place", { zone = "Elwynn Forest", subzone = subzone or "Goldshire",
			place = subzone or "Goldshire", visit = visit, placeKind = kind, level = 10 }, at))
		return r
	end

	t:describe("Story Director: location relevance", function()
		t:it("weighs beginnings, capitals, towns and other places differently", function()
			local ns, char = setup()
			local D = ns.Director
			local function score(visit, kind, sub)
				return D.LocationRelevance(char, record(ns, char, visit, kind, 1000, sub)).score
			end
			expect.equal(score("start", "start", "Northshire Valley"), 10)
			expect.equal(score("first", "capital", "Stormwind City"), 3)
			expect.equal(score("first", "town", "Goldshire"), 1)
			expect.equal(score("first", "farm", "The Stonefield Farm"), 0)
			local start = D.LocationRelevance(char, record(ns, char, "start", "start", 1000, "Coldridge Valley"))
			expect.truthy(start.urgent)
			expect.equal(start.chance, 1)
			expect.equal(D.LocationRelevance(char, record(ns, char, "first", "town", 1000, "Kharanos")).chance, 0.2)
		end)

		t:it("ties to the character's own story weigh most: homeland, marks, memories, arcs, goals, people", function()
			local ns, char = setup()
			local D = ns.Director
			local base = D.LocationRelevance(char, record(ns, char, "return", "town")).score
			char.fields.homeland = { value = "Goldshire", visibility = "secret" }
			local r = D.LocationRelevance(char, record(ns, char, "return", "town"))
			expect.equal(r.score, base + D.LOCATION_TIES.homeland)
			ns.Arcs.Add(char, { title = "Shadows over Goldshire" }, "player", 1)
			ns.Goals.Add(char, { title = "Clear Goldshire's name" }, 1)
			ns.People.Add(char, { name = "Brom", kind = "npc", relation = "Innkeeper in Goldshire" }, 1)
			r = D.LocationRelevance(char, record(ns, char, "return", "town"))
			local T = D.LOCATION_TIES
			expect.equal(r.score, base + T.homeland + T.arc + T.goal + T.person)
			expect.truthy(r.urgent, "strongly tied places skip the location cooldown")
			expect.equal(#r.reasons, 4)
		end)

		t:it("proposed, concluded and removed records do not count", function()
			local ns, char = setup()
			local D = ns.Director
			local arc = ns.Arcs.Add(char, { title = "A thread of Goldshire" }, "suggested", 1)
			expect.equal(D.LocationRelevance(char, record(ns, char, "return", "town")).score, 0, "a proposal")
			ns.Arcs.Accept(char, arc.id, 2)
			ns.Arcs.SetState(char, arc.id, "concluded", 3)
			expect.equal(D.LocationRelevance(char, record(ns, char, "return", "town")).score, 0, "a concluded arc")
			local goal = ns.Goals.Add(char, { title = "Return to Goldshire" }, 1)
			expect.equal(D.LocationRelevance(char, record(ns, char, "return", "town")).score, 2)
			ns.Goals.Remove(char, goal.id)
			expect.equal(D.LocationRelevance(char, record(ns, char, "return", "town")).score, 0, "removed at once")
		end)

		t:it("explains the tie by its kind, never with the record's private words", function()
			local ns, char = setup()
			ns.People.Add(char, { name = "Lysa", kind = "family", relation = "Lost sister, last seen in Goldshire",
				feelings = "I blame myself", visibility = "secret" }, 1)
			local why = table.concat(ns.Director.Why(char, record(ns, char, "return", "town")), "; ")
			expect.truthy(why:find("someone your character knows", 1, true), why)
			for _, private in ipairs({ "Lysa", "sister", "blame" }) do
				expect.falsy(why:find(private, 1, true), private)
			end
		end)

		t:it("fewer place moments lowers every score except a beginning", function()
			local ns, char = setup()
			local D = ns.Director
			local fewer = { places = "fewer" }
			expect.equal(D.LocationRelevance(char, record(ns, char, "first", "capital", 1, "Ironforge"), fewer).score, 1)
			expect.equal(D.LocationRelevance(char, record(ns, char, "first", "town", 1, "Kharanos"), fewer).chance, 0)
			expect.equal(D.LocationRelevance(char, record(ns, char, "start", "start", 1, "Coldridge Valley"),
				fewer).score, 10)
		end)

		t:it("decides each event the same way every time, so a moment is never re-rolled", function()
			local ns, char = setup()
			local r = record(ns, char, "first", "town", 1234)
			local a, b = ns.Director.Roll(r), ns.Director.Roll(r)
			expect.equal(a, b)
			expect.truthy(a >= 0 and a < 1)
		end)
	end)

	t:describe("Story Director: eligibility and cooldowns", function()
		local function consider(ns, char, r, now)
			return ns.Reactions.Consider(char, r, now)
		end

		t:it("an ordinary place is logged quietly; a weighted one asks only when its roll allows", function()
			local ns, char = setup()
			local _, why = consider(ns, char, record(ns, char, "first", "farm", 1000, "The Stonefield Farm"), 1000)
			expect.equal(why, "logged quietly")
			ns.Director.Roll = function() return 0.5 end
			_, why = consider(ns, char, record(ns, char, "first", "town", 2000, "Goldshire"), 2000)
			expect.equal(why, "not this time", "0.5 is above a town's 0.2 chance")
			ns.Director.Roll = function() return 0.1 end
			local reaction, outcome = consider(ns, char, record(ns, char, "first", "town", 3000, "Kharanos"), 3000)
			expect.equal(outcome, "queued")
			expect.truthy(reaction)
		end)

		t:it("the location cooldown holds back ordinary places but not a strongly tied one", function()
			local ns, char = setup()
			ns.Director.Roll = function() return 0 end
			local first = consider(ns, char, record(ns, char, "first", "town", 1000, "Goldshire"), 1000)
			expect.truthy(first)
			ns.Reactions.Dismiss(char, first.id)
			local _, why = consider(ns, char, record(ns, char, "first", "town", 1300, "Kharanos"), 1300)
			expect.equal(why, "cooldown")
			char.fields.homeland = { value = "Lakeshire", visibility = "private" }
			local r = assert(ns.GameEvents.Record(char, "place", { zone = "Redridge Mountains", subzone = "Lakeshire",
				place = "Lakeshire", visit = "first", placeKind = "town", level = 15 }, 1400))
			local _, outcome = consider(ns, char, r, 1400)
			expect.equal(outcome, "queued", "a homeland is deferred to a calm moment, not dropped")
		end)

		t:it("prompts off and place moments off still win over any weight", function()
			local ns, char = setup()
			ns.Director.Roll = function() return 0 end
			char.fields.homeland = { value = "Goldshire", visibility = "private" }
			char.story.prefs.places = "off"
			local _, why = consider(ns, char, record(ns, char, "return", "town", 1000), 1000)
			expect.equal(why, "place moments off")
			char.story.prefs.places, char.story.prefs.frequency = "on", "off"
			_, why = consider(ns, char, record(ns, char, "return", "town", 2000), 2000)
			expect.equal(why, "prompts off")
		end)
	end)
end
