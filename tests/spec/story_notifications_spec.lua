-- L2: delivery of Story Director moments (issue D, 0.10.2): when the small
-- reaction card appears, when a moment only waits in the Story section, and
-- why. Mocked client (tests/support/wow_mock.lua); not in-game evidence.
--
-- Root causes covered (failing first on 0.10.1):
--   * a moment was marked "notified" (and the notice cooldown started)
--     before the card was shown, so a card that failed to appear lost it;
--   * the card hid itself when combat started, but the moment stayed
--     "notified" and was never offered again;
--   * a second moment replaced a card still on screen (the first one was
--     never seen, yet counted as announced);
--   * a moment held back by the notice cooldown was only retried by chance
--     (the next zone change or fight), never when the cooldown ended;
--   * after a fight with several moments the oldest one was offered, and
--     nothing said that others were waiting.
local Boot = require("support.boot")

local CHAR = "Testchar-TestRealm"

local function click(button)
	button:GetScript("OnClick")(button)
end

return function(t, expect)
	local function start(opts)
		local mock, env, ns = Boot.Start(opts)
		mock.Slash("set name Tester")
		local story = env.DawnwardChroniclesDB.characters[CHAR].story
		story.prefs.card = true
		return mock, env, ns, story
	end

	-- A routine quest moment in its own zone (no folding; the category
	-- cooldown is cleared first so test moments can follow each other).
	-- Returns the reaction.
	local seq = 0
	local function moment(ns, story, significance)
		seq = seq + 1
		local char = ns.Actions.Character(ns.ctx)
		assert(char.story == story)
		story.pacing.playByCategory.quest = nil
		local record = assert(ns.GameEvents.Record(char, "quest",
			{ questId = 9000 + seq, title = "Task " .. seq, zone = "Zone " .. seq, level = 5 }, ns.ctx.now()))
		local reaction, outcome = ns.Reactions.Consider(char, record, ns.ctx.now())
		assert(reaction and outcome == "queued", tostring(outcome))
		if significance then reaction.significance = significance end
		ns.SafeTime.Schedule(ns.ctx)
		return reaction
	end

	local function card(ns)
		local frame = ns.ReactionCard.Frame()
		return frame and frame:IsShown() and frame or nil
	end

	local function notices(mock)
		local n = 0
		for _, line in ipairs(mock.chat) do
			if line:find("A moment for your story", 1, true) then n = n + 1 end
		end
		return n
	end

	t:describe("story notifications: display failures (issue D)", function()
		t:it("a card that fails to appear (error) keeps the moment eligible and retries at the next calm moment",
			function()
			local mock, _, ns, story = start()
			ns.SafeTime.ShowCard = function() error("card broke") end
			local r = moment(ns, story)
			mock.chat = {}
			mock.RunTimers()
			expect.equal(r.notifiedAt, nil, "not notified: nothing was shown")
			expect.equal(r.shownAt, nil)
			expect.equal(story.pacing.lastNoticeAt, 0, "the notice cooldown did not start")
			expect.equal(r.noticeTries, 1, "the attempt is recorded")
			expect.equal(notices(mock), 0, "no chat notice for a card nobody saw")
			ns.SafeTime.ShowCard = ns.ReactionCard.Show
			mock.Fire("PLAYER_REGEN_ENABLED")
			mock.RunTimers()
			expect.truthy(card(ns), "shown once the card works")
			expect.equal(card(ns).reactionId, r.id)
			expect.truthy(r.shownAt and r.notifiedAt)
			expect.equal(r.shownVia, "card")
			expect.equal(notices(mock), 1)
		end)

		t:it("a card that reports it was not shown keeps the moment eligible", function()
			local mock, _, ns, story = start()
			ns.SafeTime.ShowCard = function() return false end
			local r = moment(ns, story)
			mock.RunTimers()
			expect.equal(r.notifiedAt, nil)
			expect.equal(story.pacing.lastNoticeAt, 0)
			ns.SafeTime.ShowCard = ns.ReactionCard.Show
			mock.Fire("PLAYER_UPDATE_RESTING")
			mock.RunTimers()
			expect.equal(card(ns).reactionId, r.id)
		end)

		t:it("after repeated failures it falls back to the chat line (bounded, never lost)", function()
			local mock, _, ns, story = start()
			ns.SafeTime.ShowCard = function() return false end
			local r = moment(ns, story)
			mock.chat = {}
			for _ = 1, ns.SafeTime.MAX_TRIES + 2 do
				mock.Fire("PLAYER_REGEN_ENABLED")
				mock.RunTimers()
			end
			expect.equal(r.noticeTries, ns.SafeTime.MAX_TRIES)
			expect.equal(r.shownVia, "chat")
			expect.truthy(r.notifiedAt)
			expect.equal(notices(mock), 1, "one chat notice, not one per try")
		end)
	end)

	t:describe("story notifications: combat and other unsafe moments (issue D)", function()
		t:it("a card hidden by combat is offered again after the fight, at most twice", function()
			local mock, _, ns, story = start()
			local r = moment(ns, story)
			mock.RunTimers()
			expect.equal(card(ns).reactionId, r.id)
			for round = 1, ns.Reactions.MAX_INTERRUPTS do
				mock.inCombat = true
				mock.Fire("PLAYER_REGEN_DISABLED")
				expect.equal(card(ns), nil, "hidden in combat")
				expect.equal(r.closedHow, "combat")
				expect.equal(r.notifiedAt, nil, "eligible again (round " .. round .. ")")
				mock.inCombat = false
				mock.Fire("PLAYER_REGEN_ENABLED")
				mock.RunTimers()
				expect.truthy(card(ns), "offered again after the fight (round " .. round .. ")")
				expect.equal(card(ns).reactionId, r.id)
			end
			mock.inCombat = true
			mock.Fire("PLAYER_REGEN_DISABLED")
			mock.inCombat = false
			mock.Fire("PLAYER_REGEN_ENABLED")
			mock.RunTimers()
			expect.equal(card(ns), nil, "bounded: it now waits in the Story section")
			expect.truthy(r.notifiedAt)
			expect.equal(#story.reactions, 1, "still waiting")
		end)

		t:it("several moments during combat: one card afterwards (the newest), naming how many more wait", function()
			local mock, _, ns, story = start()
			mock.inCombat = true
			local a = moment(ns, story)
			mock.RunTimers()
			local b = moment(ns, story)
			mock.RunTimers()
			local c = moment(ns, story)
			mock.RunTimers()
			expect.equal(card(ns), nil, "never in combat")
			mock.chat = {}
			mock.inCombat = false
			mock.Fire("PLAYER_REGEN_ENABLED")
			mock.Fire("PLAYER_UPDATE_RESTING")
			mock.RunTimers()
			expect.equal(card(ns).reactionId, c.id, "the newest")
			expect.equal(notices(mock), 1, "one notice")
			expect.equal(a.notifiedAt, nil)
			expect.equal(b.notifiedAt, nil)
			expect.truthy(card(ns).more:IsShown())
			expect.equal(card(ns).more:GetText(), "2 more waiting in the Story section")
			-- Further calm moments do not flood: the cooldown holds the rest.
			mock.Fire("PLAYER_REGEN_ENABLED")
			mock.RunTimers()
			click(card(ns).close)
			mock.Fire("PLAYER_UPDATE_RESTING")
			mock.RunTimers()
			expect.equal(card(ns), nil)
			expect.equal(a.notifiedAt, nil, "waits for the cooldown")
			expect.equal(#story.reactions, 3, "nothing lost")
		end)

		t:it("never while dead, in a cinematic, loading, AFK or in a dungeon; each calm-again event retries",
			function()
			local cases = {
				{ set = function(m) m.dead = true end, clear = function(m) m.dead = false end, event = "PLAYER_UNGHOST",
					reason = "dead" },
				{ set = function(m) m.Fire("CINEMATIC_START") end, clear = function() end, event = "CINEMATIC_STOP",
					reason = "cinematic" },
				{ set = function(m) m.Fire("LOADING_SCREEN_ENABLED") end, clear = function() end,
					event = "LOADING_SCREEN_DISABLED", reason = "loading" },
				{ set = function(m) m.afk = true end, clear = function(m) m.afk = false end, event = "PLAYER_FLAGS_CHANGED",
					arg = "player", reason = "away" },
				-- Leaving a dungeon ends with a loading screen.
				{ set = function(m) m.instanceType = "party" end, clear = function(m) m.instanceType = nil end,
					event = "LOADING_SCREEN_DISABLED", reason = "instance" },
				{ set = function(m) m.inCombat = true end, clear = function(m) m.inCombat = false end,
					event = "PLAYER_REGEN_ENABLED", reason = "combat" },
			}
			for _, case in ipairs(cases) do
				local mock, _, ns, story = start()
				case.set(mock)
				local r = moment(ns, story)
				mock.RunTimers()
				expect.equal(card(ns), nil, case.reason)
				expect.equal(r.notifiedAt, nil, case.reason)
				local found = false
				for _, why in ipairs(ns.SafeTime.Reasons()) do
					if why == case.reason then found = true end
				end
				expect.truthy(found, case.reason)
				case.clear(mock)
				mock.Fire(case.event, case.arg)
				mock.RunTimers()
				expect.truthy(card(ns), "shown after " .. case.event)
				expect.equal(card(ns).reactionId, r.id)
			end
		end)
	end)

	t:describe("story notifications: pacing and dismissal (issue D)", function()
		t:it("a card on screen is never replaced by a newer moment; the next one follows when it closes", function()
			local mock, _, ns, story = start()
			local a = moment(ns, story)
			mock.RunTimers()
			expect.equal(card(ns).reactionId, a.id)
			local b = moment(ns, story, 3)
			mock.RunTimers()
			expect.equal(card(ns).reactionId, a.id, "not replaced")
			expect.equal(b.notifiedAt, nil)
			expect.equal(card(ns).more:GetText(), "1 more waiting in the Story section")
			click(card(ns).close)
			expect.equal(a.closedHow, "close")
			mock.RunTimers()
			expect.equal(card(ns).reactionId, b.id, "a major moment follows at once")
		end)

		t:it("a moment held back by the notice cooldown is retried when the cooldown ends (one timer, no polling)",
			function()
			local mock, _, ns, story = start()
			local a = moment(ns, story)
			mock.RunTimers()
			click(card(ns).close)
			local b = moment(ns, story)
			mock.RunTimers()
			expect.equal(card(ns), nil, "cooldown")
			expect.equal(b.notifiedAt, nil)
			expect.equal(#mock.timers, 1, "one retry timer")
			local wait = mock.timers[1].seconds
			local cooldown = ns.Reactions.COOLDOWN.normal
			expect.truthy(wait > cooldown - 30 and wait <= cooldown + 5, "at the end of the cooldown: " .. wait)
			-- More calm-moment events do not add timers.
			mock.Fire("PLAYER_REGEN_ENABLED")
			mock.RunTimers()
			expect.equal(#mock.timers, 1)
			mock.clock = mock.clock + cooldown
			mock.RunTimers()
			expect.equal(card(ns).reactionId, b.id)
			expect.truthy(a.shownAt < b.shownAt)
		end)

		t:it("a card closed by the player (Close, Escape, Later, Not now) is not offered again", function()
			for _, how in ipairs({ "close", "escape", "later" }) do
				local mock, _, ns, story = start()
				local r = moment(ns, story)
				mock.RunTimers()
				local frame = card(ns)
				if how == "close" then click(frame.close)
				elseif how == "escape" then frame:Hide() -- what UISpecialFrames does on Escape
				else click(frame.later) end
				expect.equal(r.closedHow, how)
				expect.truthy(r.closedAt and r.shownAt)
				mock.clock = mock.clock + 100000
				mock.Fire("PLAYER_REGEN_ENABLED")
				mock.RunTimers()
				expect.equal(card(ns), nil, how)
				expect.equal(#story.reactions, 1, "it stays waiting in the Story section")
			end
		end)

		t:it("respects frequency off and the card setting (chat line only)", function()
			local mock, _, ns, story = start()
			mock.Slash("story set card off")
			local r = moment(ns, story)
			mock.chat = {}
			mock.RunTimers()
			expect.equal(card(ns), nil)
			expect.equal(notices(mock), 1)
			expect.equal(r.shownVia, "chat")
			local mock2, _, ns2, story2 = start()
			local r2 = moment(ns2, story2)
			story2.prefs.frequency = "off"
			mock2.RunTimers()
			expect.equal(card(ns2), nil)
			expect.equal(r2.notifiedAt, nil)
		end)

		t:it("a card whose moment was answered elsewhere goes away", function()
			local mock, _, ns, story = start()
			local r = moment(ns, story)
			mock.RunTimers()
			expect.truthy(card(ns))
			mock.Slash("story " .. r.id .. " 1")
			expect.equal(#story.reactions, 0)
			expect.equal(card(ns), nil, "no card for a moment that is gone")
			local r2 = moment(ns, story, 3)
			mock.RunTimers()
			expect.equal(card(ns).reactionId, r2.id)
			mock.Slash("story " .. r2.id .. " notnow")
			expect.equal(card(ns), nil, "Not now in chat closes the card too")
			expect.equal(r2.closedHow, "notnow")
		end)

		t:it("stays above the open journal window", function()
			local mock, _, ns, story = start()
			ns.MainWindow.Show()
			moment(ns, story)
			mock.RunTimers()
			local frame = card(ns)
			expect.truthy(frame)
			expect.equal(frame:GetFrameStrata(), "HIGH")
			expect.equal(ns.MainWindow.GetFrame():GetFrameStrata(), "MEDIUM")
		end)
	end)

	t:describe("story notifications: reload and login (issue D)", function()
		t:it("a moment never shown is offered once after /reload; a shown one is not", function()
			local mock, env, ns, story = start()
			mock.instanceType = "party"
			local r = moment(ns, story)
			mock.RunTimers()
			expect.equal(r.notifiedAt, nil)
			mock.Fire("PLAYER_LOGOUT")
			local saved = ns.Util.DeepCopy(env.DawnwardChroniclesDB)
			local mock2, env2, ns2 = Boot.Start({ savedVariables = { DawnwardChroniclesDB = saved } })
			local story2 = env2.DawnwardChroniclesDB.characters[CHAR].story
			mock2.chat = {}
			mock2.RunTimers()
			expect.truthy(card(ns2), "offered after login")
			expect.equal(card(ns2).reactionId, r.id)
			expect.equal(notices(mock2), 1)
			expect.truthy(story2.reactions[1].shownAt)
			mock2.Fire("PLAYER_LOGOUT")
			local saved2 = ns2.Util.DeepCopy(env2.DawnwardChroniclesDB)
			local mock3, _, ns3 = Boot.Start({ savedVariables = { DawnwardChroniclesDB = saved2 } })
			mock3.clock = mock3.clock + 100000
			mock3.RunTimers()
			mock3.RunTimers()
			expect.equal(card(ns3), nil, "already shown: not again")
		end)

		t:it("after login the notice cooldown still applies, with one timer for its end", function()
			local mock, env, ns, story = start()
			moment(ns, story)
			mock.RunTimers()
			click(card(ns).close)
			moment(ns, story)
			mock.Fire("PLAYER_LOGOUT")
			local saved = ns.Util.DeepCopy(env.DawnwardChroniclesDB)
			local mock2, _, ns2 = Boot.Start({ savedVariables = { DawnwardChroniclesDB = saved } })
			mock2.clock = mock.clock
			mock2.RunTimers()
			expect.equal(card(ns2), nil, "cooldown")
			expect.equal(#mock2.timers, 1)
			mock2.clock = mock2.clock + ns2.Reactions.COOLDOWN.normal
			mock2.RunTimers()
			expect.truthy(card(ns2))
		end)

		t:it("saved notification state is normalised on load; older moments load unchanged", function()
			local ns = select(3, Boot.Load())
			local clean = ns.StorySchema.CleanReaction({ id = 3, category = "quest", eventKeys = { "quest:1" },
				templateId = "quest_general", createdAt = 10, shownAt = 20, shownVia = "card", closedAt = 30,
				closedHow = "escape", noticeTries = 2, triedAt = 15, interrupts = 1 })
			expect.equal(clean.shownAt, 20)
			expect.equal(clean.shownVia, "card")
			expect.equal(clean.closedAt, 30)
			expect.equal(clean.closedHow, "escape")
			expect.equal(clean.noticeTries, 2)
			expect.equal(clean.triedAt, 15)
			expect.equal(clean.interrupts, 1)
			local junk = ns.StorySchema.CleanReaction({ id = 4, category = "quest", eventKeys = { "quest:1" },
				templateId = "quest_general", shownAt = "soon", shownVia = "pigeon", closedHow = {}, noticeTries = -3,
				interrupts = 99 })
			expect.equal(junk.shownAt, nil)
			expect.equal(junk.shownVia, nil)
			expect.equal(junk.closedHow, nil)
			expect.equal(junk.noticeTries, nil)
			expect.equal(junk.interrupts, ns.Reactions.MAX_INTERRUPTS)
			local old = ns.StorySchema.CleanReaction({ id = 5, category = "quest", eventKeys = { "quest:1" },
				templateId = "quest_general", createdAt = 10, notifiedAt = 12 })
			expect.equal(old.notifiedAt, 12, "an announced 0.10.1 moment stays announced")
			expect.equal(old.shownAt, nil)
		end)
	end)

	t:describe("story notifications: badge and explanations (issue D)", function()
		t:it("the Story rail badge counts waiting moments and follows changes", function()
			local mock, _, ns, story = start()
			ns.MainWindow.Show()
			local tab = ns.MainWindow.GetFrame().tabs[3]
			expect.equal(tab.id, "story")
			expect.equal(tab.badge:GetText(), "")
			local a = moment(ns, story)
			ns.MainWindow.Refresh()
			expect.equal(tab.badge:GetText(), "1")
			moment(ns, story)
			ns.MainWindow.Refresh()
			expect.equal(tab.badge:GetText(), "2")
			expect.truthy(tab.tooltipText:find("2 moments are waiting", 1, true), tab.tooltipText)
			mock.Slash("story " .. a.id .. " dismiss")
			expect.equal(tab.badge:GetText(), "1", "updated by the command")
			expect.truthy(tab.tooltipText:find("1 moment is waiting", 1, true), tab.tooltipText)
		end)

		t:it("/dawnward story why explains each waiting moment in plain words", function()
			local mock, _, ns, story = start()
			local a = moment(ns, story)
			mock.RunTimers()
			click(card(ns).close)
			local b = moment(ns, story)
			mock.RunTimers()
			mock.inCombat = true
			local c = moment(ns, story)
			local text = mock.Slash("story why")
			expect.truthy(text:find("3 moments waiting", 1, true), text)
			expect.truthy(text:find("#" .. a.id .. ".-shown as a card"), text)
			expect.truthy(text:find("#" .. a.id .. ".-you closed it"), text)
			expect.truthy(text:find("not a safe moment now: in combat", 1, true), text)
			expect.truthy(text:find("#" .. c.id .. ".-next to be shown"), text)
			expect.truthy(text:find("#" .. b.id .. ".-after the newer moment"), text)
			expect.truthy(text:find("one card at a time", 1, true), text)
			mock.inCombat = false
			text = mock.Slash("story why")
			expect.truthy(text:find("#" .. c.id .. ".-pause between cards: until"), text)
			mock.Slash("story set card off")
			text = mock.Slash("story why")
			expect.truthy(text:find("card is switched off", 1, true), text)
			mock.Slash("story set frequency off")
			text = mock.Slash("story why")
			expect.truthy(text:find("Story prompts are off", 1, true), text)
			-- The developer status includes the same explanation.
			local status = table.concat(ns.StoryDiagnostics.StatusLines(ns.ctx), "\n")
			expect.truthy(status:find("Why no card", 1, true), status)
		end)
	end)
end
