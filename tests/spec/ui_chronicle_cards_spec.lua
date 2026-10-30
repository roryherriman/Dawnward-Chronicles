-- L1/L2: what the v0.7 Chronicle cards and the Places detail show, from the
-- character's real records only (pure helpers, plus a goal's progress bar).
local Boot = require("support.boot")

local CHAR = "Testchar-TestRealm"
local NOW = 1700000000 -- 14 Nov 2023 (mock clock)

local function click(button)
	button:GetScript("OnClick")(button)
end

return function(t, expect)
	local function start()
		local mock, env, ns = Boot.Start()
		mock.Slash("set name Lirael")
		mock.Slash("")
		ns.MainWindow.Select("chronicle")
		return mock, env.DawnwardChroniclesDB.characters[CHAR], ns, ns.ChronicleView.section
	end

	local function texts(list)
		local out = {}
		for i, c in ipairs(list) do out[i] = c[1] end
		return out
	end

	t:describe("Chronicle card content", function()
		t:it("shows a memory's importance, date, provenance and canon status", function()
			local _, char, ns = start()
			local CV = ns.ChronicleView
			local m = ns.Memories.Add(char, { title = "Lanterns", text = "The night", importance = 3,
				zone = "Elwynn Forest" }, "player", NOW - 86400 * 3)
			local c = CV.CardContent("memories", m, char, NOW)
			expect.deepEqual(c.chip, { "Defining", "accent" })
			expect.equal(c.date, "11 Nov")
			expect.equal(c.title, "Lanterns")
			expect.deepEqual(texts(c.chips), { "Elwynn Forest", "Your words", "Established" })
			expect.falsy(c.highlight)
			expect.equal(CV.CardContent("memories", ns.Memories.Add(char, { text = "x" }, "player", NOW), char, NOW).date,
				"Today")
			expect.equal(CV.ShortDate(1600000000, NOW), "13 Sep 2020", "another year shows it")
			expect.falsy(CV.ShortDate(0, NOW), "an unknown date shows nothing")
		end)

		t:it("puts a suggestion's decision first and leaves its status chips out", function()
			local _, char, ns = start()
			local m = ns.Memories.Add(char, { text = "Suggested" }, "suggested", NOW)
			local c = ns.ChronicleView.CardContent("memories", m, char, NOW)
			expect.equal(c.chip[1], "Suggested · needs your call")
			expect.truthy(c.highlight)
			expect.deepEqual(c.chips, {})
		end)

		t:it("shows a goal's progress only from real milestones or its verified objective", function()
			local _, char, ns, section = start()
			local CV = ns.ChronicleView
			local g = ns.Goals.Add(char, { title = "Restore the grove" }, NOW)
			local c = CV.CardContent("goals", g, char, NOW)
			expect.falsy(c.progress, "nothing to measure: no bar")
			expect.equal(c.meta, "no milestones yet")
			ns.Goals.AddMilestone(char, g.id, "Find a seed", NOW)
			ns.Goals.AddMilestone(char, g.id, "Plant it", NOW)
			ns.Goals.SetMilestone(char, g.id, 1, true, NOW)
			c = CV.CardContent("goals", g, char, NOW)
			expect.equal(c.progress, 0.5)
			expect.equal(c.meta, "1/2 milestones")
			for _, b in ipairs(section.tabButtons) do
				if b.tabId == "goals" then click(b) end
			end
			local row = section.rows[1]
			expect.truthy(row.progress:IsShown())
			expect.equal(row.progress.value, 0.5)
			expect.equal(row.chip.label:GetText(), "Active")
		end)

		t:it("describes arcs, stances, people and findings in their own words", function()
			local mock, char, ns = start()
			local CV = ns.ChronicleView
			local a = ns.Arcs.Add(char, { title = "Where I belong", kind = "conflict" }, "player", NOW)
			local c = CV.CardContent("arcs", a, char, NOW)
			expect.equal(c.meta, "Conflict arc · no turning points yet")
			expect.deepEqual(c.chip, { "Active", "accent" })
			local s = ns.Identity.Add(char, { subject = "Darnassus", persona = "Devoted", conviction = "Abandoned" }, NOW)
			c = CV.CardContent("identity", s, char, NOW)
			expect.equal(c.title, "Darnassus")
			expect.equal(c.text, "In public: Devoted\nPrivately (Private): Abandoned")
			local p = ns.People.Add(char, { name = "Aria", kind = "player", realm = "Silverhand",
				feelings = "Never trusted her" }, NOW)
			c = CV.CardContent("people", p, char, NOW)
			expect.equal(c.title, "Aria-Silverhand")
			for _, v in pairs({ c.title, c.meta or "", c.text or "" }) do
				expect.falsy(v:find("trusted", 1, true), "private feelings stay off the card")
			end
			mock.Slash("stance add The Cenarion Circle; Loyal; Doubts its leaders")
			local finding = ns.Continuity.Findings(char)[1]
			c = CV.CardContent("review", finding, char, NOW)
			expect.equal(c.text, finding.message)
			expect.truthy(c.chip)
		end)
	end)

	t:describe("Places detail helpers", function()
		t:it("finds the memories tied to a place, including suggestions, but not superseded ones", function()
			local _, char, ns = start()
			local P = ns.ChroniclePlaces
			local entry = ns.Places.CleanEntry({ zone = "Elwynn Forest", subzone = "Goldshire", first = 1, last = 1 })
			local key = "place:Elwynn Forest / Goldshire"
			ns.Memories.Add(char, { title = "Home", links = { events = { key } } }, "player", 1)
			ns.Memories.Add(char, { title = "Elsewhere", zone = "Elwynn Forest" }, "player", 2)
			local s = ns.Memories.Add(char, { title = "Later", links = { events = { key } } }, "suggested", 3)
			local tied = P.TiedMemories(char.story, entry)
			expect.equal(#tied, 2)
			expect.equal(tied[1].title, "Later", "newest first")
			expect.equal(P.MemoryLine(tied[1]), "Later  ·  Suggested")
			expect.equal(P.MemoryLine(tied[2]), "Home  ·  Ordinary")
			s.status = "superseded"
			expect.equal(#P.TiedMemories(char.story, entry), 1)
			-- A whole zone counts memories that name it (as Places.Linked does).
			local zone = ns.Places.CleanEntry({ zone = "Elwynn Forest", first = 1, last = 1 })
			local zoneTied = P.TiedMemories(char.story, zone)
			expect.equal(#zoneTied, 1)
			expect.equal(zoneTied[1].title, "Elsewhere")
		end)

		t:it("puts the return rules in plain words, read-only", function()
			local _, _, ns = start()
			local P = ns.ChroniclePlaces
			expect.equal(P.ReturnText(true), "Your next visit can count")
			expect.equal(P.ReturnText(false, "away", { wait = 7500 }), "After 2 h 5 min more play away")
			expect.equal(P.ReturnText(false, "weekly", { wait = 600 }), "After 10 min more play")
			expect.equal(P.ReturnText(false, "new", {}), "Counting from your next visit")
			expect.equal(P.ReturnText(false, "ordinary", {}), "Only once it is tied to your story")
		end)

		t:it("pages a long list of places and keeps the selection on the page", function()
			local _, char, ns, section = start()
			for i = 1, 10 do
				local name = string.format("Place %02d", i)
				char.story.places["Zone / " .. name] = ns.Places.CleanEntry({ zone = "Zone", subzone = name,
					first = i, last = i })
			end
			for _, b in ipairs(section.tabButtons) do
				if b.tabId == "places" then click(b) end
			end
			local view = section.places
			expect.truthy(view.next:IsShown())
			expect.equal(view.pageLabel:GetText(), "Page 1 of 2")
			expect.equal(view.detail.name:GetText(), "Place 10")
			click(view.next)
			expect.equal(view.rows[1].name:GetText(), "Place 02")
			expect.equal(view.detail.name:GetText(), "Place 02", "the first place on the new page")
			expect.falsy(view.rows[3]:IsShown())
		end)
	end)
	t:describe("Chronicle card titles", function()
		t:it("shows a long goal title whole on hover", function()
			local _, char, ns, section = start()
			local long = "Find the missing courier somewhere between Goldshire and the Stonefield farm before the rains"
			assert(ns.Goals.Add(char, { title = long }, NOW))
			for _, b in ipairs(section.tabButtons) do
				if b.tabId == "goals" then click(b) end
			end
			local row = section.rows[1]
			expect.truthy(row.titleHover:IsShown())
			expect.equal(row.titleHover.tooltipTitle, long)
		end)
	end)
end
