-- L1/L2: returns to meaningful places (manual test M16) and the developer
-- diagnostics /dawnward dev story status | simulate. Mocked client; Classic
-- Era IDs from the 1.15.9.70576 client tables.
local Loader = require("support.loader")
local Boot = require("support.boot")

return function(t, expect)
	local KEY = "Kyssarra-Test"
	local DAY = 24 * 3600

	local GOLDSHIRE = { "Elwynn Forest", "Goldshire", 1429, 87 }
	local NORTHSHIRE = { "Elwynn Forest", "Northshire Valley", 1429, 9 }
	local STORMWIND = { "Stormwind City", nil, 1453, nil }
	-- A real Elwynn subzone (AreaTable 18) that is not in Dawnward's mapping, so it
	-- has no verified area ID. (Not Lion's Pride Inn: indoors, the client reports
	-- the inn as the zone itself; see issue #48.)
	local INN = { "Elwynn Forest", "Crystal Lake", 1429, nil }
	local STONEFIELD = { "Elwynn Forest", "The Stonefield Farm", 1429, 63 }

	local function where(place, level)
		return { zone = place[1], subzone = place[2], mapId = place[3], areaId = place[4], level = level or 10,
			race = "Human", class = "PALADIN", faction = "Alliance", client = "classic_era" }
	end

	local function setup()
		local ns = Loader.Core()
		ns.Director.Roll = function() return 0.99 end -- only urgent places ask: no luck involved
		local char = ns.Schema.NewCharacter(1)
		char.fields.name = { value = "Kyssarra", visibility = "public" }
		char.fields.pronouns = { value = "she/her", visibility = "public" }
		local clock = { now = 100, place = NORTHSHIRE }
		local ctx = { store = { real = { characters = { [KEY] = char } }, realReadOnly = false }, characterKey = KEY,
			now = function() return clock.now end, version = "0.6.0-dev",
			location = function() return where(clock.place) end }
		return ns, char, ctx, clock
	end

	local function observe(ns, ctx, clock, at, place)
		clock.now, clock.place = at, place
		return ns.Actions.ObserveLocation(ctx, where(place))
	end

	local function joined(lines)
		return table.concat(lines, "\n")
	end

	-- The M16 reproduction: Goldshire first visit, marked and set as Homeland,
	-- then Stormwind, then straight back to Goldshire.
	local function m16()
		local ns, char, ctx, clock = setup()
		observe(ns, ctx, clock, 100, NORTHSHIRE)
		for _, r in ipairs(char.story.reactions) do ns.Reactions.Dismiss(char, r.id) end
		observe(ns, ctx, clock, 5000, GOLDSHIRE)
		assert(ns.Places.Mark(char, "Goldshire", true))
		assert(ns.Places.SetHomeland(char, ns.Places.FindByName(char, "Goldshire"), 5100))
		for _, r in ipairs(char.story.reactions) do ns.Reactions.Dismiss(char, r.id) end
		observe(ns, ctx, clock, 9000, STORMWIND)
		return ns, char, ctx, clock
	end

	t:describe("returns to a meaningful place (M16)", function()
		t:it("a same-session return to the Homeland records nothing: two days away are required", function()
			local ns, char, ctx, clock = m16()
			local events = #char.story.events
			local made = observe(ns, ctx, clock, 9000 + 1800, GOLDSHIRE)
			expect.equal(#made, 0, "no event")
			expect.equal(#char.story.events, events, "story events unchanged")
			expect.equal(ctx.lastLocation.diag.why, "away")
			expect.equal(ctx.lastLocation.diag.target, "Goldshire, Elwynn Forest")
			local status = joined(ns.StoryDiagnostics.StatusLines(ctx))
			expect.truthy(status:find("Return to Goldshire, Elwynn Forest: not recorded: last recorded here", 1, true),
				status)
			expect.truthy(status:find("a return counts only after 2 days away", 1, true), status)
		end)

		t:it("after two days away the Homeland return asks, even right after another place moment", function()
			local ns, char, ctx, clock = m16()
			-- A new place moment just now starts the shared location cooldown.
			char.story.pacing.lastByCategory.place = 3 * DAY - 60
			local made = observe(ns, ctx, clock, 3 * DAY, GOLDSHIRE)
			expect.equal(made[1].record.meta.visit, "return")
			expect.equal(made[1].record.significance, 2)
			expect.equal(made[1].outcome, "queued", "urgent: Homeland and marked skip the cooldown")
			local view = assert(ns.Reactions.Present(char, made[1].reaction))
			expect.truthy(view.question:find("returned to Goldshire", 1, true), view.question)
			-- Another return within the week: none.
			observe(ns, ctx, clock, 3 * DAY + 600, STORMWIND)
			expect.equal(#observe(ns, ctx, clock, 6 * DAY, GOLDSHIRE), 0)
			expect.equal(ctx.lastLocation.diag.why, "weekly")
		end)

		t:it("return events are listed with the other story events", function()
			local ns, char, ctx, clock = m16()
			observe(ns, ctx, clock, 3 * DAY, GOLDSHIRE)
			local recent = ns.GameEvents.Recent(char, 10)
			expect.equal(recent[1].meta.visit, "return")
			expect.truthy(ns.GameEvents.RecordLabel(recent[1]):find("Goldshire", 1, true))
		end)

		t:it("fix: an unmapped place tied by a memory can return (it used to fall through to the zone)", function()
			local ns, char, ctx, clock = setup()
			observe(ns, ctx, clock, 100, NORTHSHIRE)
			observe(ns, ctx, clock, 5000, INN)
			assert(ns.Memories.Add(char, { title = "A warm night",
				links = { events = { "place:Elwynn Forest / Crystal Lake" } } }, "player", 5100))
			local made = observe(ns, ctx, clock, 3 * DAY, INN)
			expect.equal(#made, 1)
			expect.equal(made[1].record.meta.placeName, "Crystal Lake")
			expect.equal(made[1].record.meta.linked, 1)
		end)

		t:it("fix: an unmapped place named by the Homeland field can return", function()
			local ns, char, ctx, clock = setup()
			observe(ns, ctx, clock, 100, NORTHSHIRE)
			observe(ns, ctx, clock, 5000, INN)
			char.fields.homeland = { value = "Crystal Lake", visibility = "private" }
			expect.equal(ns.Places.Tie(char, ns.Places.FindByName(char, "Crystal Lake")), "homeland")
			local made = observe(ns, ctx, clock, 3 * DAY, INN)
			expect.equal(made[1].record.meta.placeName, "Crystal Lake")
			-- Named only by the field it weighs 4 (an 80% chance, not urgent); the
			-- roll here is 0.99, so it is recorded without asking.
			expect.equal(ns.Director.LocationRelevance(char, made[1].record, char.story.prefs).chance, 0.8)
			expect.equal(made[1].outcome, "not this time")
		end)

		t:it("an unmapped place with no tie still never returns by itself", function()
			local ns, _, ctx, clock = setup()
			observe(ns, ctx, clock, 100, NORTHSHIRE)
			observe(ns, ctx, clock, 5000, INN)
			expect.equal(#observe(ns, ctx, clock, 3 * DAY, INN), 0)
		end)
	end)

	t:describe("dev story status", function()
		t:it("reports location, ties, eligibility, cooldown and the last decision", function()
			local ns, _, ctx, clock = m16()
			observe(ns, ctx, clock, 9000 + 600, GOLDSHIRE)
			local status = joined(ns.StoryDiagnostics.StatusLines(ctx))
			for _, want in ipairs({
				"Location: Goldshire, Elwynn Forest (map 1429, area 87): settlement.",
				"Homeland: yes. Marked meaningful: yes. Memory tie: no.",
				"Tied to your story: it is your Homeland.",
				"urgent: skips the location cooldown",
				"Location cooldown:",
				"Waiting moments: 0.",
				"Last arrival this session: Goldshire, Elwynn Forest",
				"Return to Goldshire, Elwynn Forest: not recorded: last recorded here",
				"Return to Goldshire, Elwynn Forest, if it happened now: not eligible: last recorded here",
			}) do
				expect.truthy(status:find(want, 1, true), "missing: " .. want .. "\n" .. status)
			end
		end)

		t:it("explains why an ordinary place never asks on return", function()
			local ns, _, ctx, clock = setup()
			observe(ns, ctx, clock, 100, NORTHSHIRE)
			observe(ns, ctx, clock, 5000, STONEFIELD)
			observe(ns, ctx, clock, 3 * DAY, STONEFIELD)
			local status = joined(ns.StoryDiagnostics.StatusLines(ctx))
			expect.truthy(status:find("returns count only for settlements", 1, true), status)
		end)

		t:it("shows the cooldown left after a place moment", function()
			local ns, char, ctx, clock = m16()
			char.story.pacing.lastByCategory.place = clock.now - 600
			local status = joined(ns.StoryDiagnostics.StatusLines(ctx))
			expect.truthy(status:find("Location cooldown: 35 min left of 45 min", 1, true), status)
		end)
	end)

	t:describe("dev story simulate", function()
		t:it("runs a Homeland return on a copy: shows the question and changes nothing", function()
			local ns, char, ctx, clock = m16()
			clock.now = 9000 + 60
			char.story.pacing.lastByCategory.place = clock.now - 30 -- a cooldown in force
			local before = ns.Util.DeepCopy(char)
			local text = joined(ns.StoryDiagnostics.SimulateLines(ctx, "Goldshire"))
			expect.truthy(text:find("Simulating a return to Goldshire, Elwynn Forest after 2 days", 1, true), text)
			expect.truthy(text:find("Result: a moment was queued.", 1, true), text)
			expect.truthy(text:find("Question: Kyssarra has returned to Goldshire", 1, true), text)
			expect.truthy(text:find("Nothing was saved", 1, true), text)
			expect.deepEqual(char, before, "the character is exactly as before")
		end)

		t:it("defaults to the current place and reports a suppressed result plainly", function()
			local ns, char, ctx, clock = setup()
			observe(ns, ctx, clock, 100, NORTHSHIRE)
			observe(ns, ctx, clock, 5000, GOLDSHIRE)
			local before = ns.Util.DeepCopy(char)
			local text = joined(ns.StoryDiagnostics.SimulateLines(ctx))
			expect.truthy(text:find("Result: suppressed: the Director gave it no weight", 1, true), text)
			expect.deepEqual(char, before)
		end)

		t:it("refuses a place never visited", function()
			local ns, _, ctx = setup()
			local text = joined(ns.StoryDiagnostics.SimulateLines(ctx, "Lakeshire"))
			expect.truthy(text:find("Not simulated: no visited place called 'Lakeshire'", 1, true), text)
		end)
	end)

	t:describe("dev story commands (L2)", function()
		t:it("are available only in development builds", function()
			local mock = Boot.Start({ version = "0.6.0" })
			mock.Slash("set name Kyssarra")
			expect.truthy(mock.Slash("dev story status"):find("only available in development builds", 1, true))
			expect.truthy(mock.Slash("dev story simulate"):find("only available", 1, true))
			expect.falsy(mock.Slash("help all"):find("dev story", 1, true))
			local dev = Boot.Start()
			dev.Slash("set name Kyssarra")
			expect.truthy(dev.Slash("dev story status"):find("Story Director: places", 1, true))
			expect.truthy(dev.Slash("dev story"):find("dev story simulate", 1, true))
			expect.truthy(dev.Slash("help all"):find("dev story status", 1, true))
		end)
	end)
end
