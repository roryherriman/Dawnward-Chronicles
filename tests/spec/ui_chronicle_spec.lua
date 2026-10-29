-- L2: the Chronicle section (narrative records in the window). Mocked client.
local Boot = require("support.boot")

local CHAR = "Testchar-TestRealm"

local function click(button)
	button:GetScript("OnClick")(button)
end

return function(t, expect)
	local function start()
		local mock, env, ns = Boot.Start()
		mock.Slash("set name Lirael")
		mock.Slash("")
		ns.MainWindow.Select("chronicle")
		return mock, env, ns, ns.ChronicleView.section
	end

	local function tab(section, id)
		for _, b in ipairs(section.tabButtons) do
			if b.tabId == id then click(b) end
		end
	end

	local function form(section, values)
		local f = section.form
		expect.truthy(f:IsOpen(), "a form is open")
		for _, row in ipairs(f.rows) do
			local field = row.field
			if field and values[field.key] ~= nil then
				local v = values[field.key]
				if field.kind == "area" then row.area.edit:SetText(v)
				elseif field.kind == "cycle" then row.value = v
				else row.line:SetText(tostring(v)) end
			end
		end
		click(f.save)
	end

	-- The row's visible button labelled text.
	local function button(row, text)
		for _, b in ipairs(row.buttons) do
			if b:IsShown() and b:GetText() == text then return b end
		end
		error("no button " .. text)
	end

	local function overlaps(a, b)
		return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
	end

	-- The visible chips of a card, in order.
	local function chips(row)
		local out = {}
		for _, chip in ipairs(row.chips) do
			if chip:IsShown() then out[#out + 1] = chip.label:GetText() end
		end
		return out
	end

	t:describe("Chronicle layout (#46, v0.7 cards)", function()
		t:it("never lets a card's parts overlap, and fits the grid in the content area", function()
			local _, _, ns = Boot.Start()
			local CV = ns.ChronicleView
			local L = CV.LAYOUT
			for _, opts in ipairs({ {}, { title = true }, { title = true, meta = true },
				{ title = true, meta = true, progress = true }, { meta = true, progress = true } }) do
				local r = CV.CardRects(opts)
				local parts = { r.chip, r.text, r.chips, r.divider, r.buttons }
				for _, k in ipairs({ "title", "meta", "progress" }) do
					if r[k] then parts[#parts + 1] = r[k] end
				end
				for i = 1, #parts do
					expect.truthy(parts[i].x >= 0 and parts[i].x + parts[i].w <= L.cardWidth, "inside the card width")
					expect.truthy(parts[i].y >= 0 and parts[i].y + parts[i].h <= L.cardHeight, "inside the card height")
					for j = i + 1, #parts do
						expect.falsy(overlaps(parts[i], parts[j]), string.format("parts %d and %d overlap", i, j))
					end
				end
				expect.falsy(overlaps(r.chip, r.date), "the status chip leaves room for the date")
				expect.truthy(r.text.h >= 50, "at least three lines of text")
			end
			expect.truthy(L.inset * 2 + L.width <= ns.MainWindow.ContentWidth())
			expect.equal(L.cols * L.cardWidth + (L.cols - 1) * L.colGap, L.width, "two columns fill the width")
			local width = 0
			for _, spec in ipairs(CV.TABS) do width = width + spec.width + L.tabGap end
			expect.truthy(width + 2 * L.tabPad <= L.width, "tabs fit one row")
			local lastX, lastY = CV.CardOrigin(CV.ROWS)
			expect.truthy(lastX + L.cardWidth <= L.inset + L.width)
			expect.truthy(lastY + L.cardHeight <= ns.MainWindow.ContentHeight(), "cards end inside the content area")
			expect.truthy(L.toolbarTop + L.toolbarHeight <= L.gridTop, "toolbar above the cards")
		end)

		t:it("fits each tab's buttons inside a card without overlapping", function()
			local _, _, ns = Boot.Start()
			local CV = ns.ChronicleView
			local W = CV.BUTTON_WIDTHS
			local inner = CV.LAYOUT.cardWidth - 2 * CV.LAYOUT.cardPad
			local gap = CV.LAYOUT.buttonGap
			local rows = {
				{ W.Accept, W.Edit, 84, W.Remove },             -- a suggested stance-like record
				{ W.Edit, W.Dispute, W.Steps, W.Remove },
				{ W.Accept, W.Edit, W.Turn, W.Remove },
				{ W.growth, W.unreliable, W.secret, W.correction, W.ignore },
			}
			for _, widths in ipairs(rows) do
				local total = 0
				for _, w in ipairs(widths) do total = total + w end
				expect.truthy(total + gap * (#widths - 1) <= inner, "the row of buttons fits")
			end
		end)

		t:it("places each card's frames from the same rectangles, in a two-column grid", function()
			local _, env, ns, section = start()
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			ns.Memories.Add(char, { title = "The grove", text = "It burned" }, "player", 1)
			ns.Memories.Add(char, { text = "A second" }, "player", 2)
			ns.MainWindow.Refresh()
			local r = ns.ChronicleView.CardRects({ title = true })
			local row = section.rows[2]
			expect.equal(row.text:GetWidth(), r.text.w)
			expect.equal(row.title:GetText(), "The grove")
			local p1, p2 = section.rows[1].__points[1], section.rows[2].__points[1]
			expect.equal(p1[3], p2[3], "first two cards share a row")
			expect.truthy(p2[2] >= p1[2] + ns.ChronicleView.LAYOUT.cardWidth, "side by side, apart")
			expect.falsy(section.rows[1].title:IsShown(), "no title: the text takes its place")
		end)

		t:it("pages long lists", function()
			local _, env, ns, section = start()
			expect.equal(select(1, ns.ChronicleView.Pages(0, 1)), 1)
			expect.equal(select(2, ns.ChronicleView.Pages(13, 9)), 4)
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			for i = 1, 6 do ns.Memories.Add(char, { text = "Memory " .. i }, "player", i) end
			ns.MainWindow.Refresh()
			expect.equal(section.pageLabel:GetText(), "Page 1 of 2")
			expect.equal(section.rows[1].text:GetText(), "Memory 6")
			expect.equal(section.count:GetText(), "Newest first · 6 memories")
			click(section.next)
			expect.equal(section.rows[1].text:GetText(), "Memory 2")
			expect.falsy(section.rows[3]:IsShown())
			expect.falsy(section.next:IsEnabled())
		end)

		t:it("names the tab in the heading and counts each tab's records", function()
			local mock, env, ns, section = start()
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			ns.Memories.Add(char, { text = "One" }, "player", 1)
			mock.Slash("stance add The Cenarion Circle; Loyal; Doubts its leaders")
			ns.MainWindow.Refresh()
			expect.equal(ns.MainWindow.HeadingFor(ns.MainWindow.Sections()[4], char, false), "Memories")
			local labels = {}
			for _, b in ipairs(section.tabButtons) do labels[b.tabId] = b:GetText() end
			expect.equal(labels.memories, "Memories  1")
			expect.equal(labels.identity, "Stances  1")
			expect.equal(labels.arcs, "Arcs")
			expect.equal(labels.review, "Review  1")
			tab(section, "goals")
			local def
			for _, d in ipairs(ns.MainWindow.Sections()) do if d.id == "chronicle" then def = d end end
			expect.equal(def.heading, "Goals")
			expect.equal(ns.MainWindow.GetFrame().title:GetText(), "Goals", "the window heading follows at once")
		end)

		t:it("filters a tab with the search box and says when nothing matches", function()
			local _, env, ns, section = start()
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			ns.Memories.Add(char, { title = "Lanterns", text = "The night the lanterns went out" }, "player", 1)
			ns.Memories.Add(char, { title = "Knife", text = "Tobin's knife" }, "player", 2)
			ns.MainWindow.Refresh()
			section.search:SetText("LANTERN")
			section.search:GetScript("OnTextChanged")(section.search, true)
			expect.equal(section.rows[1].title:GetText(), "Lanterns")
			expect.falsy(section.rows[2]:IsShown())
			expect.equal(section.count:GetText(), "1 of 2 memories")
			section.search:SetText("grove")
			section.search:GetScript("OnTextChanged")(section.search, true)
			expect.truthy(section.empty:IsShown())
			expect.truthy(section.empty:GetText():find("Nothing matches", 1, true))
			tab(section, "arcs")
			expect.equal(section.query, "", "a new tab starts unfiltered")
			-- Private feelings are never searched.
			tab(section, "people")
			ns.People.Add(char, { name = "Maybell", kind = "npc", feelings = "secretly jealous" }, 3)
			section.search:SetText("jealous")
			section.search:GetScript("OnTextChanged")(section.search, true)
			expect.falsy(section.rows[1]:IsShown())
		end)

		t:it("explains each empty tab", function()
			local _, _, ns, section = start()
			for _, id in ipairs({ "memories", "arcs", "goals", "identity", "people", "review" }) do
				tab(section, id)
				expect.truthy(section.empty:IsShown(), id .. " is empty")
				expect.equal(section.empty:GetText(), ns.ChronicleView.EMPTY[id][2])
				expect.falsy(section.rows[1]:IsShown())
			end
			tab(section, "places")
			expect.truthy(section.places.empty:IsShown())
			expect.truthy(section.places.emptyText:GetText():find("No places logged yet", 1, true))
			expect.falsy(section.places.detail:IsShown())
		end)
	end)

	t:describe("Chronicle section (L2)", function()
		t:it("adds a memory from a form and shows its provenance, status and visibility", function()
			local _, env, _, section = start()
			expect.truthy(section.empty:IsShown())
			click(section.new)
			form(section, { title = "The grove", text = "The day the grove burned" })
			expect.falsy(section.form:IsOpen())
			local m = env.DawnwardChroniclesDB.characters[CHAR].story.memories[1]
			expect.equal(m.text, "The day the grove burned")
			local row = section.rows[1]
			expect.truthy(row:IsShown())
			expect.equal(row.title:GetText(), "The grove")
			expect.equal(row.text:GetText(), "The day the grove burned")
			expect.equal(row.chip.label:GetText(), "Ordinary")
			expect.deepEqual(chips(row), { "Your words", "Established" })
			expect.truthy(row.vis:IsShown())
			expect.equal(row.vis:GetText(), "Private")
		end)

		t:it("keeps a form open with the reason when saving is refused", function()
			local _, env, _, section = start()
			click(section.new)
			form(section, {})
			expect.truthy(section.form:IsOpen())
			local title = section.form.rows[1].line
			expect.truthy(title.invalid, "the title field is highlighted")
			expect.truthy(title.errorLabel:GetText():find("needs a title or some text", 1, true))
			expect.equal(#env.DawnwardChroniclesDB.characters[CHAR].story.memories, 0)
		end)

		t:it("accepts a suggestion; public is refused until then", function()
			local _, env, ns, section = start()
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			ns.Memories.Add(char, { text = "Suggested" }, "suggested", 1)
			ns.MainWindow.Refresh()
			local row = section.rows[1]
			click(button(row, "Private")) -- private -> public: refused for a proposal
			expect.equal(char.story.memories[1].visibility, "private")
			click(button(row, "Accept"))
			expect.equal(char.story.memories[1].status, "established")
			click(button(section.rows[1], "Private"))
			expect.equal(char.story.memories[1].visibility, "public")
		end)

		t:it("creates and edits arcs, goals, stances and people without slash commands", function()
			local _, env, ns, section = start()
			local story = function() return env.DawnwardChroniclesDB.characters[CHAR].story end
			tab(section, "arcs")
			click(section.new)
			form(section, { title = "Finding where I belong", kind = "conflict" })
			click(button(section.rows[1], "Edit"))
			form(section, { title = "Where I belong", state = "concluded" })
			expect.equal(story().arcs[1].title, "Where I belong")
			expect.equal(story().arcs[1].state, "concluded")
			click(button(section.rows[1], "Turn"))
			form(section, { note = "Left the grove" })
			expect.equal(story().arcs[1].turningPoints[1].note, "Left the grove")

			tab(section, "goals")
			click(section.new)
			form(section, { title = "Restore the grove", target = 20 })
			expect.equal(story().goals[1].objective.target, 20)
			click(button(section.rows[1], "Steps"))
			form(section, { new = "Find a seed" })
			click(button(section.rows[1], "Steps"))
			form(section, { [1] = true })
			expect.truthy(story().goals[1].milestones[1].done)
			-- A reputation objective needs a faction the game has shown; then it replaces the level.
			click(button(section.rows[1], "Edit"))
			form(section, { target = "", faction = "Darnassus", standing = 6 })
			expect.truthy(section.form:IsOpen(), "Darnassus not seen yet")
			click(section.form.cancel)
			expect.equal(story().goals[1].objective.target, 20, "a refused save changes nothing")
			ns.Observed.CompareStandings(env.DawnwardChroniclesDB.characters[CHAR],
				{ { id = 69, name = "Darnassus", standing = 5 } })
			click(button(section.rows[1], "Edit"))
			form(section, { target = "", faction = "Darnassus", standing = 6 })
			expect.equal(story().goals[1].objective.kind, "reputation")
			expect.truthy(section.rows[1].meta:GetText():find("Friendly/Honored with Darnassus", 1, true))
			click(button(section.rows[1], "Edit"))
			form(section, { target = 0, faction = "", state = "achieved" })
			expect.falsy(story().goals[1].objective)
			expect.equal(story().goals[1].state, "achieved")

			tab(section, "identity")
			click(section.new)
			form(section, { subject = "Darnassus", persona = "Devoted", conviction = "Feels abandoned" })
			expect.truthy(section.rows[1].text:GetText():find("Feels abandoned", 1, true))
			click(button(section.rows[1], "Edit"))
			form(section, { conviction = "", persona = "" })
			expect.truthy(section.form:IsOpen(), "one side must remain")
			click(section.form.cancel)

			tab(section, "people")
			click(section.new)
			form(section, { name = "Keeper Remulos", relation = "Mentor" })
			expect.equal(section.rows[1].title:GetText(), "Keeper Remulos")
			expect.equal(section.rows[1].text:GetText(), "Mentor")
			click(section.new)
			form(section, { name = "Aria", kind = "player" })
			expect.truthy(section.form:IsOpen(), "a player needs a realm")
			form(section, { realm = "Silverhand" })
			expect.equal(story().people[2].realm, "Silverhand")
		end)

		t:it("marks a logged place and links it as the homeland after confirmation", function()
			local mock, env, ns, section = start()
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			char.story.places[ns.Places.Key("Elwynn Forest", "Goldshire")] = ns.Places.CleanEntry({
				zone = "Elwynn Forest", subzone = "Goldshire", kind = "town", first = 1, last = 1 })
			tab(section, "places")
			local view = section.places
			local d = view.detail
			expect.equal(view.rows[1].name:GetText(), "Goldshire")
			expect.equal(d.name:GetText(), "Goldshire", "the first place is selected")
			click(d.mark)
			expect.truthy(ns.Places.FindByName(char, "Goldshire").meaningful)
			click(d.homeland)
			expect.falsy(char.fields.homeland, "nothing changes before confirming")
			mock.AcceptPopup()
			expect.equal(char.fields.homeland.value, "Goldshire")
			expect.equal(char.fields.homeland.visibility, "private")
			expect.truthy(ns.Places.Homeland(char))
			click(d.write)
			form(section, { text = "Where I first felt at home" })
			local memory = char.story.memories[1]
			expect.equal(memory.zone, "Elwynn Forest")
			expect.deepEqual(memory.links.events, { "place:Elwynn Forest / Goldshire" })
			expect.truthy(ns.Places.Linked(char.story, ns.Places.FindByName(char, "Goldshire")),
				"a return to Goldshire now recalls it")
			expect.truthy(view.tiedRows[1]:IsShown(), "the detail lists the tied memory")
			expect.truthy(view.tiedRows[1].text:GetText():find("Goldshire", 1, true))
			-- Changing the Homeland field elsewhere unlinks the place.
			mock.Slash("set homeland Lordaeron")
			expect.falsy(ns.Places.Homeland(char))
			ns.MainWindow.Refresh()
			expect.falsy(d.chips[1].label:GetText() == "Homeland")
			expect.truthy(d.homeland:IsEnabled(), "it can be made the homeland again")
		end)

		t:it("answers continuity findings from the Review tab without changing canon", function()
			local mock, env, _, section = start()
			mock.Slash("stance add The Cenarion Circle; Loyal; Doubts its leaders")
			tab(section, "review")
			expect.truthy(section.rows[1]:IsShown())
			click(button(section.rows[1], "secret"))
			local story = env.DawnwardChroniclesDB.characters[CHAR].story
			expect.equal(story.reviews[1].choice, "secret")
			expect.equal(story.identity[1].conviction, "Doubts its leaders")
			expect.falsy(section.rows[1]:IsShown())
		end)
	end)
end
