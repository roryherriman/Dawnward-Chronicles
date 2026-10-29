-- L1/L2: the narrative clock (Core/NarrativeClock.lua, Platform/PlayClock.lua).
-- Story pacing runs on seconds of play per character, never offline time.
local Loader = require("support.loader")
local Boot = require("support.boot")

return function(t, expect)
	local KEY = "Kyssarra-Test"
	local GOLDSHIRE = { "Elwynn Forest", "Goldshire", 1429, 87 }
	local NORTHSHIRE = { "Elwynn Forest", "Northshire Valley", 1429, 9 }
	local STONEFIELD = { "Elwynn Forest", "The Stonefield Farm", 1429, 63 }

	local function where(place)
		return { zone = place[1], subzone = place[2], mapId = place[3], areaId = place[4], level = 10,
			race = "Human", class = "PALADIN", faction = "Alliance", client = "classic_era" }
	end

	-- A pure context with a session: clock.mono plays the part of GetTime().
	local function setup()
		local ns = Loader.Core()
		ns.Director.Roll = function() return 0 end
		local char = ns.Schema.NewCharacter(1)
		char.fields.name = { value = "Kyssarra", visibility = "public" }
		local clock = { now = 1700000000, mono = 500 }
		local ctx = { store = { real = { characters = { [KEY] = char } }, realReadOnly = false }, characterKey = KEY,
			now = function() return clock.now end, monotonic = function() return clock.mono end,
			narrative = ns.NarrativeClock.NewSession() }
		return ns, char, ctx, clock
	end

	-- Plays for seconds, reading the clock every minute as the game does.
	local function play(ns, char, ctx, clock, seconds)
		ns.NarrativeClock.Read(char, ctx)
		local left = seconds
		while left > 0 do
			local d = math.min(60, left)
			clock.mono, clock.now, left = clock.mono + d, clock.now + d, left - d
			ns.NarrativeClock.Read(char, ctx)
		end
	end

	-- Logs out for seconds of real time, then starts a new session (GetTime
	-- may restart, as after a reboot).
	local function offline(ns, ctx, clock, seconds, newMono)
		clock.now = clock.now + seconds
		clock.mono = newMono or (clock.mono + seconds)
		ctx.narrative = ns.NarrativeClock.NewSession()
	end

	local function observe(ns, ctx, place)
		return ns.Actions.ObserveLocation(ctx, where(place))
	end

	t:describe("narrative clock: counting play", function()
		t:it("counts only play: offline time never advances it", function()
			local ns, char, ctx, clock = setup()
			play(ns, char, ctx, clock, 1800)
			expect.equal(ns.NarrativeClock.Peek(char), 1800)
			offline(ns, ctx, clock, 7 * 24 * 3600)
			expect.equal(ns.NarrativeClock.Read(char, ctx), 1800, "a week offline adds nothing")
			play(ns, char, ctx, clock, 600)
			expect.equal(ns.NarrativeClock.Peek(char), 2400)
		end)

		t:it("adds up several play sessions", function()
			local ns, char, ctx, clock = setup()
			for _ = 1, 3 do
				play(ns, char, ctx, clock, 1200)
				offline(ns, ctx, clock, 5 * 3600, 10) -- the computer restarted: GetTime starts again
			end
			expect.equal(ns.NarrativeClock.Peek(char), 3600)
			expect.equal(ns.NarrativeClock.Day(char), 1, "an hour of play is still narrative day 1 at Standard pace")
			play(ns, char, ctx, clock, 3600)
			expect.equal(ns.NarrativeClock.Day(char), 2)
		end)

		t:it("pauses while AFK", function()
			local ns, char, ctx, clock = setup()
			play(ns, char, ctx, clock, 600)
			ns.NarrativeClock.Pause(char, ctx.narrative, clock.mono)
			clock.mono = clock.mono + 3000
			expect.equal(ns.NarrativeClock.Read(char, ctx), 600, "AFK time is not play")
			ns.NarrativeClock.Resume(char, ctx.narrative, clock.mono)
			play(ns, char, ctx, clock, 120)
			expect.equal(ns.NarrativeClock.Peek(char), 720)
		end)

		t:it("keeps characters apart", function()
			local ns, char, ctx, clock = setup()
			local alt = ns.Schema.NewCharacter(1)
			play(ns, char, ctx, clock, 900)
			expect.equal(ns.NarrativeClock.Peek(alt), 0, "another character's clock does not move")
			ns.NarrativeClock.Read(alt, ctx)
			play(ns, alt, ctx, clock, 300)
			expect.equal(ns.NarrativeClock.Peek(alt), 300)
			expect.equal(ns.NarrativeClock.Peek(char), 900)
		end)

		t:it("never trusts a reading going backwards, a stall, or an invalid value", function()
			local ns, char, ctx, clock = setup()
			play(ns, char, ctx, clock, 600)
			clock.mono = clock.mono - 400 -- GetTime went backwards
			expect.equal(ns.NarrativeClock.Read(char, ctx), 600)
			clock.mono = clock.mono + 8 * 3600 -- one reading eight hours later (sleep, freeze)
			expect.equal(ns.NarrativeClock.Read(char, ctx), 600 + ns.NarrativeClock.MAX_STEP, "capped")
			clock.now = clock.now - 30 * 24 * 3600 -- the computer's date changed: irrelevant
			play(ns, char, ctx, clock, 60)
			expect.equal(ns.NarrativeClock.Peek(char), 960)
			for _, bad in ipairs({ -5, "lots", 0 / 0, math.huge, 2 ^ 41 }) do
				expect.equal(ns.NarrativeClock.Clean({ played = bad }).played, 0, "cleaned: " .. tostring(bad))
			end
			expect.deepEqual(ns.NarrativeClock.Clean({ played = 90.7, extra = true }), { v = 1, played = 90 })
		end)

		t:it("the pace setting decides the narrative day length", function()
			local ns, char = setup()
			expect.equal(ns.NarrativeClock.DayLength(char), 7200)
			char.story.prefs.pace = "brisk"
			expect.equal(ns.NarrativeClock.DayLength(char), 3600)
			char.story.prefs.pace = "slow"
			expect.equal(ns.NarrativeClock.DayLength(char), 14400)
			local cleaned = ns.StorySchema.Normalize({ prefs = { pace = "sometimes" } }, {})
			expect.equal(cleaned.prefs.pace, "standard")
		end)
	end)

	t:describe("narrative clock: returns and cooldowns", function()
		local function visitedGoldshire()
			local ns, char, ctx, clock = setup()
			observe(ns, ctx, NORTHSHIRE)
			for _, r in ipairs(char.story.reactions) do ns.Reactions.Dismiss(char, r.id) end
			play(ns, char, ctx, clock, 600)
			observe(ns, ctx, GOLDSHIRE)
			assert(ns.Places.Mark(char, "Goldshire", true))
			for _, r in ipairs(char.story.reactions) do ns.Reactions.Dismiss(char, r.id) end
			play(ns, char, ctx, clock, 300)
			observe(ns, ctx, STONEFIELD) -- leaves Goldshire
			return ns, char, ctx, clock
		end

		t:it("a return needs a narrative day of play away; days offline do not count", function()
			local ns, char, ctx, clock = visitedGoldshire()
			offline(ns, ctx, clock, 3 * 24 * 3600)
			expect.equal(#observe(ns, ctx, GOLDSHIRE), 0, "three real days offline: no return")
			expect.equal(ctx.lastLocation.diag.why, "away")
			play(ns, char, ctx, clock, 300)
			observe(ns, ctx, STONEFIELD)
			play(ns, char, ctx, clock, ns.NarrativeClock.DayLength(char))
			local made = observe(ns, ctx, GOLDSHIRE)
			expect.equal(made[1].record.meta.visit, "return", "after a narrative day of play away")
			expect.equal(made[1].outcome, "queued")
		end)

		t:it("one return per place per narrative week of play; crossing back and forth farms nothing", function()
			local ns, char, ctx, clock = visitedGoldshire()
			local day = ns.NarrativeClock.DayLength(char)
			play(ns, char, ctx, clock, day)
			expect.equal(observe(ns, ctx, GOLDSHIRE)[1].record.meta.visit, "return")
			local returns = 0
			-- Two narrative days of crossing the boundary every few minutes.
			for _ = 1, 2 * day / 300 do
				play(ns, char, ctx, clock, 150)
				observe(ns, ctx, STONEFIELD)
				play(ns, char, ctx, clock, 150)
				for _, made in ipairs(observe(ns, ctx, GOLDSHIRE)) do
					if made.record.meta.visit == "return" then returns = returns + 1 end
				end
			end
			expect.equal(returns, 0, "short absences never count")
			-- A long absence inside the narrative week: still no second return.
			observe(ns, ctx, STONEFIELD)
			play(ns, char, ctx, clock, 2 * day)
			expect.equal(#observe(ns, ctx, GOLDSHIRE), 0)
			expect.equal(ctx.lastLocation.diag.why, "weekly")
			-- After a narrative week of play since the last return, it may ask again.
			observe(ns, ctx, STONEFIELD)
			play(ns, char, ctx, clock, 3 * day)
			expect.equal(observe(ns, ctx, GOLDSHIRE)[1].record.meta.visit, "return")
		end)

		t:it("story cooldowns count play, not time offline", function()
			local ns, char, ctx, clock = setup()
			char.story.prefs.frequency = "normal"
			local cooldown = ns.Reactions.COOLDOWN.normal
			local quest = function(id)
				return ns.GameEvents.Record(char, "quest", { questId = id, title = "Q" .. id, zone = "Zone" .. id,
					level = 10 }, clock.now)
			end
			local now, playNow = clock.now, ns.NarrativeClock.Read(char, ctx)
			expect.equal(select(2, ns.Reactions.Consider(char, quest(1), now, playNow)), "queued")
			offline(ns, ctx, clock, 24 * 3600)
			local _, why = ns.Reactions.Consider(char, quest(2), clock.now, ns.NarrativeClock.Read(char, ctx))
			expect.equal(why, "cooldown", "a day offline does not end the cooldown")
			play(ns, char, ctx, clock, cooldown)
			local _, ok = ns.Reactions.Consider(char, quest(3), clock.now, ns.NarrativeClock.Read(char, ctx))
			expect.equal(ok, "queued", "the cooldown ends after enough play")
		end)

		t:it("waiting moments expire after narrative days of play, never while offline", function()
			local ns, char, ctx, clock = setup()
			local record = ns.GameEvents.Record(char, "quest", { questId = 1, title = "Q", zone = "Z", level = 10 },
				clock.now)
			assert(ns.Reactions.Consider(char, record, clock.now, ns.NarrativeClock.Read(char, ctx)))
			offline(ns, ctx, clock, 60 * 24 * 3600)
			expect.equal(#ns.Reactions.List(char, clock.now, ns.NarrativeClock.Read(char, ctx)), 1,
				"two months offline: still waiting")
			play(ns, char, ctx, clock, ns.Reactions.EXPIRY_DAYS * ns.NarrativeClock.DayLength(char) + 60)
			expect.equal(#ns.Reactions.List(char, clock.now, ns.NarrativeClock.Read(char, ctx)), 0)
			expect.equal(ns.GameEvents.Find(char, "quest:1").status, "recorded", "the event itself stays")
		end)

		t:it("changing the story pace never removes a moment already waiting", function()
			local ns, char, ctx, clock = setup()
			local record = ns.GameEvents.Record(char, "quest", { questId = 2, title = "Q", zone = "Z", level = 10 },
				clock.now)
			assert(ns.Reactions.Consider(char, record, clock.now, ns.NarrativeClock.Read(char, ctx)))
			-- Ten hours of play at the standard pace: well inside its 7-day (14 h) wait.
			play(ns, char, ctx, clock, 10 * 3600)
			char.story.prefs.pace = "brisk" -- a 1 h day would make the wait 7 h
			expect.equal(#ns.Reactions.List(char, clock.now, ns.NarrativeClock.Read(char, ctx)), 1,
				"its deadline was set when it was created")
			char.story.prefs.pace = "slow"
			expect.equal(#ns.Reactions.List(char, clock.now, ns.NarrativeClock.Read(char, ctx)), 1)
			play(ns, char, ctx, clock, 5 * 3600)
			expect.equal(#ns.Reactions.List(char, clock.now, ns.NarrativeClock.Read(char, ctx)), 0,
				"it still expires on its own deadline")
		end)
	end)

	t:describe("narrative clock: upgrading saved data", function()
		-- A v0.6 character: real timestamps everywhere, no clock.
		local function legacy(ns)
			local now = 1700000000
			local raw = ns.Schema.NewCharacter(now - 30 * 86400)
			raw.fields.homeland = { value = "Goldshire", visibility = "private" }
			raw.story.clock = nil
			raw.story.places = {
				["Elwynn Forest / Goldshire"] = { zone = "Elwynn Forest", subzone = "Goldshire", kind = "town", areaId = 87,
					mapId = 1429, first = now - 30 * 86400, last = now - 10 * 86400, visits = 9,
					returnedAt = now - 20 * 86400, meaningful = true, homeland = true },
				["Elwynn Forest"] = { zone = "Elwynn Forest", mapId = 1429, first = now - 30 * 86400,
					last = now - 10 * 86400, visits = 12 },
			}
			raw.story.pacing.lastByCategory = { place = now - 60, zone = now - 60 }
			raw.story.memories = { { id = 1, title = "Home", text = "The inn.", provenance = "player",
				status = "established", visibility = "private", createdAt = now - 86400, updatedAt = now - 86400,
				links = { events = { "place:Elwynn Forest / Goldshire" } } } }
			raw.story.nextId = 2
			return raw, now
		end

		t:it("keeps every place, mark, Homeland and memory, and reads no real timestamp as play", function()
			local ns = Loader.Core()
			local raw, now = legacy(ns)
			local story = ns.StorySchema.Normalize(raw.story, ns.Schema.PERSONALITY_AXIS_BY_ID)
			expect.deepEqual(story.clock, { v = 1, played = 0 }, "the clock starts at zero")
			local g = story.places["Elwynn Forest / Goldshire"]
			expect.equal(g.visits, 9)
			expect.equal(g.meaningful, true)
			expect.equal(g.homeland, true)
			expect.equal(g.last, now - 10 * 86400, "the real date is kept for display")
			expect.equal(g.lastPlay, nil, "no gameplay reading is invented")
			expect.equal(#story.memories, 1)
			expect.deepEqual(story.pacing.playByCategory, {}, "old real-time cooldowns are not read as play")
		end)

		t:it("an upgraded place starts counting absence at its next visit: no burst of returns", function()
			local ns = Loader.Core()
			ns.Director.Roll = function() return 0 end
			local raw = legacy(ns)
			local char = raw
			char.story = ns.StorySchema.Normalize(raw.story, ns.Schema.PERSONALITY_AXIS_BY_ID)
			local clock = { now = 1700000000, mono = 10 }
			local ctx = { store = { real = { characters = { [KEY] = char } }, realReadOnly = false }, characterKey = KEY,
				now = function() return clock.now end, monotonic = function() return clock.mono end,
				narrative = ns.NarrativeClock.NewSession() }
			local made = observe(ns, ctx, GOLDSHIRE)
			expect.equal(#made, 0, "no return on the first visit after the upgrade")
			expect.equal(ctx.lastLocation.diag.why, "new")
			expect.equal(char.story.places["Elwynn Forest / Goldshire"].lastPlay, 0, "counting starts now")
			expect.equal(char.fields.homeland.value, "Goldshire", "the Homeland is untouched")
			play(ns, char, ctx, clock, 300)
			observe(ns, ctx, STONEFIELD)
			play(ns, char, ctx, clock, ns.NarrativeClock.DayLength(char))
			expect.equal(observe(ns, ctx, GOLDSHIRE)[1].record.meta.visit, "return", "then returns work normally")
		end)

		t:it("a moment waiting from before the upgrade keeps waiting", function()
			local ns, char, ctx, clock = setup()
			local record = ns.GameEvents.Record(char, "quest", { questId = 1, title = "Q", zone = "Z", level = 10 },
				clock.now)
			local reaction = assert(ns.Reactions.Consider(char, record, clock.now, 0))
			reaction.createdPlay = nil -- as saved by v0.6
			reaction.createdAt = clock.now - 30 * 86400
			play(ns, char, ctx, clock, 60)
			expect.equal(#ns.Reactions.List(char, clock.now, ns.NarrativeClock.Read(char, ctx)), 1)
			expect.equal(reaction.createdPlay, 60, "its wait is counted from now")
		end)

		t:it("a clock behind a place's reading (an older backup restored) means no absence, not an error", function()
			local ns, char = setup()
			char.story.clock.played = 100
			local entry = ns.Places.CleanEntry({ zone = "Elwynn Forest", subzone = "Goldshire", kind = "town",
				lastPlay = 50000, first = 1, last = 1 })
			local ok, why, info = ns.Places.ReturnCheck(char, entry, "town", 100)
			expect.falsy(ok)
			expect.equal(why, "away")
			expect.equal(info.away, 0)
		end)
	end)

	t:describe("narrative clock in the client (L2)", function()
		t:it("runs while playing, survives /reload and logout, and ignores time offline", function()
			local mock, env, ns = Boot.Start()
			mock.Slash("set name Kyssarra")
			local key = ns.ctx.characterKey
			mock.Play(1800)
			local played = env.DawnwardChroniclesDB.characters[key].story.clock.played
			expect.truthy(played >= 1740 and played <= 1800, "about half an hour of play: " .. played)
			mock.Fire("PLAYER_LOGOUT")
			local saved = ns.Util.DeepCopy(env.DawnwardChroniclesDB)
			-- Next session, a week later, on a restarted computer.
			local mock2, env2 = Boot.Start({ savedVariables = { DawnwardChroniclesDB = saved } })
			expect.equal(env2.DawnwardChroniclesDB.characters[key].story.clock.played, saved.characters[key].story.clock
				.played, "kept across the reload")
			mock2.Play(600)
			local after = env2.DawnwardChroniclesDB.characters[key].story.clock.played
			expect.truthy(after - played >= 540 and after - played <= 600, "only the new play is added")
			mock2.afk = true
			mock2.Fire("PLAYER_FLAGS_CHANGED", "player")
			mock2.Play(1200)
			expect.equal(env2.DawnwardChroniclesDB.characters[key].story.clock.played, after, "AFK: paused")
		end)

		t:it("the pace is a story setting, refused when unknown", function()
			local mock, env, ns = Boot.Start()
			mock.Slash("set name Kyssarra")
			local char = env.DawnwardChroniclesDB.characters[ns.ctx.characterKey]
			expect.truthy(mock.Slash("story set pace brisk"):find("brisk", 1, true))
			expect.equal(char.story.prefs.pace, "brisk")
			expect.equal(ns.NarrativeClock.DayLength(char), 3600)
			mock.Slash("story set pace hourly")
			expect.equal(char.story.prefs.pace, "brisk", "an unknown pace changes nothing")
			expect.truthy(mock.Slash("story settings"):find("a narrative day is 1 hour of play", 1, true))
		end)
	end)
end
