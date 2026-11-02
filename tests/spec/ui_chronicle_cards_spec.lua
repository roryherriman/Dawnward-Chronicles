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
			expect.equal(c.text, "Persona: Devoted\nInner conviction: Abandoned")
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

		t:it("lays the place detail out from its content, nothing overlapping, the actions in one row", function()
			local _, _, ns = start()
			local P = ns.ChroniclePlaces
			local L = P.LAYOUT
			local width = 772 - L.listWidth - L.gap
			local function overlaps(a, b)
				return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
			end
			for _, info in ipairs({
				{ chips = { "2 memories tied to it" }, note = "Short", stats = { { "Visits", "3" }, { "Last here", "Today" },
					{ "Next return moment", "Your next visit can count" } }, tied = 0 },
				{ chips = { "Homeland", "Marked meaningful", "12 memories tied to it" },
					note = string.rep("Your Homeland field reads a very long place name and stays Private. ", 3),
					stats = { { "Visits", "1400" }, { "Last here", "28 Oct 2025" },
						{ "Next return moment", "After 12 h 50 min more play away" } }, tied = 12 },
			}) do
				local r = P.DetailLayout(info, width)
				local parts = { r.name, r.sub, r.means, r.note, r.tiedLabel, r.divider, r.buttons }
				for _, c in ipairs(r.chips) do parts[#parts + 1] = c end
				for _, s in ipairs(r.stats) do parts[#parts + 1] = s end
				for i = 1, r.shown do parts[#parts + 1] = r.tied[i] end
				if info.tied > r.shown then parts[#parts + 1] = r.more end
				for i = 1, #parts do
					local a = parts[i]
					expect.truthy(a.x >= 0 and a.x + a.w <= width and a.y >= 0 and a.y + a.h <= L.height, "inside")
					for j = i + 1, #parts do
						expect.falsy(overlaps(a, parts[j]), string.format("detail parts %d and %d overlap", i, j))
					end
				end
				expect.truthy(r.stats[1].h >= L.statMin)
				if info.tied > 0 then expect.truthy(r.shown >= 1, "at least one tied memory shows") end
			end
			local long = P.DetailLayout({ chips = { "x" }, note = "n", stats = { { "Next return moment",
				"After 12 h 50 min more play away" } }, tied = 0 }, width)
			expect.truthy(long.stats[1].h > L.statMin, "a long value makes the tiles taller instead of being cut")
			local inner = width - 2 * L.detailPad
			local widths = P.ActionWidths(inner)
			local total = L.buttonGap * 2
			for i, w in ipairs(widths) do
				total = total + w
				expect.truthy(ns.Widgets.LabelFits(P.ACTIONS[i], w, L.buttonHeight), P.ACTIONS[i])
			end
			expect.truthy(total <= inner, "the three actions fit the detail")
		end)

		t:it("shows a tied memory and a place whole on hover", function()
			local _, char, ns, section = start()
			char.story.places[ns.Places.Key("Elwynn Forest", "Goldshire")] = ns.Places.CleanEntry({
				zone = "Elwynn Forest", subzone = "Goldshire", kind = "town", first = 1, last = 1 })
			local text = string.rep("Goldshire felt smaller than she remembered. ", 6)
			ns.Memories.Add(char, { title = "Coming home smaller", text = text,
				links = { events = { "place:Elwynn Forest / Goldshire" } } }, "player", 2)
			for _, b in ipairs(section.tabButtons) do
				if b.tabId == "places" then click(b) end
			end
			local view = section.places
			local tied = view.tiedRows[1]
			expect.truthy(tied:IsShown())
			expect.equal(tied.tooltipTitle, "Coming home smaller")
			expect.equal(tied.tooltipText, char.story.memories[1].text, "the whole memory")
			expect.equal(tied.text:GetText(), "Coming home smaller")
			expect.equal(tied.status:GetText(), "· Ordinary", "the status in its own, smaller type")
			-- The stat tiles' values in the mockup's larger type, each tile holding its value.
			for _, tile in ipairs(view.detail.stats) do
				local _, size = tile.value:GetFont()
				expect.equal(size, ns.ChroniclePlaces.LAYOUT.statValueSize)
			end
			expect.truthy(tied.text:GetWidth() + 6 + ns.Style.TextWidth(tied.status:GetText(), "small") + 28
				<= view.detail.width - 2 * ns.ChroniclePlaces.LAYOUT.detailPad + 2, "name and status fit the row")
			expect.equal(view.rows[1].tooltipTitle, "Goldshire")
			expect.truthy(view.rows[1].tooltipText:find("Elwynn Forest", 1, true))
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
