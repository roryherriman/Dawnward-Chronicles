-- L2: the Chronicle section (narrative records in the window). Mocked client.
local Loader = require("support.loader")
local Boot = require("support.boot")

local CHAR = "Testchar-TestRealm"

local function click(button)
	button:GetScript("OnClick")(button)
end

local function legacySpec(t, expect)
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
		local _, _, PNS = Boot.Start()
		local PCV = PNS.ChronicleView
		-- Cards of every shape: short, long, with and without title, meta,
		-- progress, many chips and many buttons.
		local LONG = string.rep("She walked the whole Lantern Road with a single candle. ", 12)
		local function shapes()
			return {
				{ chip = { "Ordinary", "muted" }, date = "Today", text = "Short", chips = {}, vis = "private" },
				{ chip = { "Defining", "accent" }, date = "28 Oct", title = "The night the lanterns went out",
					text = LONG, chips = { { "Goldshire", "muted" }, { "Your words", "muted" },
						{ "Established", "muted" } }, vis = "private" },
				{ chip = { "Active", "accent" }, title = "Restore the grove", meta = string.rep("1/2 milestones · ", 12),
					text = "Why", progress = 0.5, chips = { { "Your words", "muted" } }, vis = "public" },
				{ chip = { "Stance", "accent" }, examine = true, text = LONG,
					chips = { { "Elwynn Forest and its many quiet places", "muted" }, { "Suggested by Dawnward", "muted" },
						{ "Established", "muted" }, { "Fourth chip", "muted" } }, vis = "secret" },
				{ text = "", chips = {} },
			}
		end
		local ACTIONS = {
			function() return { { "edit", "Edit" } } end,
			function(read)
				local left = { { "accept", "Accept" }, { "edit", "Edit" }, { "turn", "Turn" } }
				if read then left[#left + 1] = { "read", "Read" } end
				return left, { "remove", "Remove" }
			end,
			function(read)
				local left = { { "edit", "Edit" }, { "dispute", "Dispute" }, { "steps", "Steps" } }
				if read then left[#left + 1] = { "read", "Read" } end
				return left, { "remove", "Remove" }
			end,
			function()
				local left = {}
				for _, id in ipairs({ "growth", "unreliable", "secret", "correction", "ignore" }) do
					left[#left + 1] = { id, PNS.ChronicleView.REVIEW_LABELS[id] }
				end
				return left
			end,
			function() return {} end,
		}

		local function parts(r)
			local out = { r.chip }
			for _, k in ipairs({ "date", "examine", "title", "meta", "text", "progress", "chips", "divider" }) do
				if r[k] then out[#out + 1] = r[k] end
			end
			if r.buttons then
				for _, b in ipairs(r.buttons.items) do
					out[#out + 1] = { x = r.buttons.x + b.x, y = r.buttons.y + b.y, w = b.w, h = PCV.LAYOUT.buttonHeight }
				end
			end
			return out
		end

		t:it("sizes each card to its content and never lets its parts overlap", function()
			local L = PCV.LAYOUT
			for si, content in ipairs(shapes()) do
				for ai, actions in ipairs(ACTIONS) do
					local r = PCV.CardLayout(content, actions)
					local list = parts(r)
					for i = 1, #list do
						local p = list[i]
						expect.truthy(p.x >= 0 and p.x + p.w <= L.cardWidth, "inside the card width " .. si .. "/" .. ai)
						expect.truthy(p.y >= 0 and p.y + p.h <= r.height, "inside the card height " .. si .. "/" .. ai)
						for j = i + 1, #list do
							expect.falsy(overlaps(list[i], list[j]),
								string.format("parts %d and %d overlap (shape %d, actions %d)", i, j, si, ai))
						end
					end
					if r.date then expect.falsy(overlaps(r.chip, r.date), "the status chip leaves room for the date") end
					if r.examine then expect.falsy(overlaps(r.chip, r.examine), "and for Examine") end
					expect.truthy(r.height <= L.gridHeight, "a card always fits a page")
					if r.chips then
						for c = 1, #r.chips.items do
							for d = c + 1, #r.chips.items do
								expect.falsy(overlaps(
									{ x = r.chips.items[c].x, y = r.chips.items[c].y, w = r.chips.items[c].w, h = L.chipRow },
									{ x = r.chips.items[d].x, y = r.chips.items[d].y, w = r.chips.items[d].w, h = L.chipRow }),
									"chips never overlap")
							end
						end
					end
				end
			end
			-- Content-aware: a short card is much shorter than a long one.
			local short = PCV.CardLayout(shapes()[1], ACTIONS[1])
			local long = PCV.CardLayout(shapes()[2], ACTIONS[2])
			expect.truthy(short.height < 170, "a short memory is a short card: " .. short.height)
			expect.truthy(long.height > short.height + 100)
			expect.truthy(long.truncated, "the long text is cut")
			expect.equal(long.text.lines, L.maxTextLines)
			expect.falsy(short.truncated)
			-- The long text's card offers Read; the short one does not need it.
			local labels = {}
			for _, b in ipairs(long.buttons.items) do labels[#labels + 1] = b.label end
			expect.truthy(table.concat(labels, ","):find("Read", 1, true))
			-- Grid and toolbar fit the content area.
			expect.truthy(L.inset * 2 + L.width <= PNS.MainWindow.ContentWidth())
			expect.equal(L.height, PNS.MainWindow.ContentHeight())
			expect.equal(L.cols * L.cardWidth + (L.cols - 1) * L.colGap, L.width, "two columns fill the width")
			expect.truthy(L.tabHeight <= L.toolbarTop and L.toolbarTop + L.toolbarHeight <= L.gridTop,
				"tabs, then the toolbar, then the cards")
		end)

		t:it("pages cards by what fits: the shorter column first, never past the grid", function()
			local L = PCV.LAYOUT
			expect.equal(#PCV.Paginate({}), 1, "an empty list is one empty page")
			local pages = PCV.Paginate({ 150, 300, 150, 150, 150 })
			expect.equal(pages[1][1].col, 1)
			expect.equal(pages[1][2].col, 2)
			expect.equal(pages[1][3].col, 1, "the third card goes under the shorter first one")
			expect.equal(pages[1][3].y, 150 + L.rowGap)
			expect.equal(pages[1][4].col, 2, "the fourth: under the 300 card, now the shorter column")
			for _, page in ipairs(PCV.Paginate({ 480, 200, 200, 200, 120, 170, 300, 486, 600, 160, 160, 160, 160, 160 })) do
				expect.truthy(#page >= 1 and #page <= L.pool)
				for i, a in ipairs(page) do
					expect.truthy(a.y + a.h <= L.gridHeight, "inside the grid")
					for j = i + 1, #page do
						local b = page[j]
						expect.falsy(a.col == b.col and a.y < b.y + b.h + L.rowGap and b.y < a.y + a.h + L.rowGap,
							"cards in a column keep their gap")
					end
				end
			end
			local n, page = PCV.Pages(pages, 9)
			expect.equal(n, #pages)
			expect.equal(page, n, "a page past the end shows the last one")
		end)

		t:it("fits each tab's buttons inside a card, the five answers in one row", function()
			local L = PCV.LAYOUT
			local inner = L.cardWidth - 2 * L.cardPad
			for ai, actions in ipairs(ACTIONS) do
				local left, right = actions(true)
				local rows = PCV.ButtonRows(left, right, inner)
				for _, b in ipairs(rows.items) do
					expect.truthy(b.x >= 0 and b.x + b.w <= inner, "inside the card: " .. b.label)
					expect.truthy(PNS.Widgets.LabelFits(b.label, b.w, L.buttonHeight), "label fits: " .. b.label)
				end
				if ai == 4 then expect.equal(rows.rows, 1, "the answers sit in one row") end
				if ai == 2 then expect.equal(rows.rows, 1, "Accept, Edit, Turn, Read and Remove in one row") end
			end
			-- Toolbar labels fit the New button.
			for _, spec in ipairs(PCV.TABS) do
				if spec.new then
					expect.truthy(PNS.Widgets.LabelFits("+  " .. spec.new, L.newWidth, L.toolbarHeight), spec.new)
				end
			end
			expect.truthy(PNS.Widgets.LabelFits("<  All findings", L.newWidth, L.toolbarHeight))
			expect.truthy(PNS.Widgets.LabelFits("Answered  999", L.newWidth, L.toolbarHeight))
		end)

		t:it("fits the tabs in one row, even with three-digit counts", function()
			local L = PCV.LAYOUT
			local width = L.tabPad
			for _, spec in ipairs(PCV.TABS) do
				local w = PCV.TabWidth(spec, 999)
				expect.truthy(PNS.Widgets.LabelFits(spec.label .. "  999", w, L.tabHeight - 2 * L.tabPad, "segment"),
					spec.label)
				width = width + w + L.tabGap
			end
			expect.truthy(width - L.tabGap + L.tabPad <= L.width, "tabs fit one row")
		end)

		t:it("places each card's frames from its layout, two cards side by side", function()
			local _, env, ns, section = start()
			local CV = ns.ChronicleView
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			ns.Memories.Add(char, { title = "The grove", text = "It burned" }, "player", 1)
			ns.Memories.Add(char, { text = "A second" }, "player", 2)
			ns.MainWindow.Refresh()
			local row = section.rows[2]
			expect.equal(row.text:GetWidth(), row.layout.text.w)
			expect.equal(row.text:GetWidth(), CV.LAYOUT.cardWidth - 2 * CV.LAYOUT.cardPad)
			expect.equal(row.title:GetText(), "The grove")
			expect.equal(row:GetHeight(), row.layout.height, "the card is as tall as its content")
			local p1, p2 = section.rows[1].__points[1], section.rows[2].__points[1]
			expect.equal(p1[3], p2[3], "first two cards share a row")
			expect.truthy(p2[2] >= p1[2] + CV.LAYOUT.cardWidth, "side by side, apart")
			expect.falsy(section.rows[1].title:IsShown(), "no title: the text takes its place")
			expect.truthy(section.rows[1]:GetHeight() < row:GetHeight(), "no title: a shorter card")
		end)

		t:it("pages long lists", function()
			local _, env, ns, section = start()
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			for i = 1, 6 do ns.Memories.Add(char, { title = "Title " .. i, text = "Memory " .. i }, "player", i) end
			ns.MainWindow.Refresh()
			expect.equal(section.pageLabel:GetText(), "Page 1 of 2")
			expect.truthy(section.next:IsShown(), "the pager shows with more than one page")
			expect.equal(section.rows[1].text:GetText(), "Memory 6")
			expect.equal(section.count:GetText(), "Newest first · 6 memories")
			click(section.next)
			expect.equal(section.rows[1].text:GetText(), "Memory 2")
			expect.falsy(section.rows[3]:IsShown())
			expect.falsy(section.next:IsEnabled())
		end)

		t:it("fills a page with short cards and hides the pager for one page", function()
			local _, env, ns, section = start()
			local CV = ns.ChronicleView
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			for i = 1, 6 do ns.Memories.Add(char, { text = "Memory " .. i }, "player", i) end
			ns.MainWindow.Refresh()
			local shown, bottom = 0, 0
			for _, row in ipairs(section.rows) do
				if row:IsShown() then
					shown = shown + 1
					bottom = math.max(bottom, -row.__points[1][3] + row:GetHeight())
				end
			end
			expect.truthy(shown >= 4, "short cards: at least four on a page")
			expect.truthy(bottom <= CV.LAYOUT.height, "the cards end inside the content area")
			local long = string.rep("A long memory that wraps over many lines. ", 30)
			ns.Memories.Add(char, { title = "Long", text = long }, "player", 7)
			ns.MainWindow.Refresh()
			expect.equal(section.rows[1].text:GetText(), char.story.memories[7].text,
				"the card holds the whole text; the client cuts it")
			expect.truthy(section.rows[1].layout.truncated)
		end)

		t:it("names the tab in the heading and counts each tab's records", function()
			local mock, env, ns, section = start()
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			ns.Memories.Add(char, { text = "One" }, "player", 1)
			mock.Slash("stance add The Cenarion Circle; Loyal; Doubts its leaders")
			ns.MainWindow.Refresh()
			expect.equal(ns.MainWindow.HeadingFor(ns.MainWindow.Sections()[4], char, false), "Memories")
			local labels = {}
			-- The count is drawn in a quieter colour (inline colour code).
			for _, b in ipairs(section.tabButtons) do
				labels[b.tabId] = b:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
			end
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
		t:it("adds a memory from a form and shows its provenance and status, nothing to classify", function()
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
			expect.equal(row.vis, nil, "no visibility chip")
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

		t:it("accepts a suggestion", function()
			local _, env, ns, section = start()
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			ns.Memories.Add(char, { text = "Suggested" }, "suggested", 1)
			ns.MainWindow.Refresh()
			local row = section.rows[1]
			click(button(row, "Accept"))
			expect.equal(char.story.memories[1].status, "established")
			expect.equal(char.story.memories[1].visibility, "private", "the stored value is left alone")
		end)

		t:it("offers no visibility form field, chip or Inner button on any tab", function()
			local mock, _, _, section = start()
			mock.Slash("stance add The Circle; Loyal; Doubts its leaders")
			mock.Slash("goal add Find a ship")
			mock.Slash("arc add Belonging")
			for _, id in ipairs({ "memories", "arcs", "goals", "identity", "people" }) do
				tab(section, id)
				click(section.new)
				for _, r in ipairs(section.form.rows) do
					if r.field then
						expect.falsy(r.field.key == "visibility", id .. ": no Visibility field")
						expect.falsy(r.field.label:find("Private", 1, true) or r.field.label:find("Public", 1, true),
							id .. ": " .. r.field.label)
					end
				end
				click(section.form.cancel)
				for _, row in ipairs(section.rows) do
					if row:IsShown() then
						for _, b in ipairs(row.buttons) do
							if b:IsShown() then
								local text = b:GetText() or ""
								expect.falsy(text:find("Inner", 1, true) or text:find("Private", 1, true)
									or text:find("Public", 1, true) or text:find("Secret", 1, true), id .. ": " .. text)
							end
						end
					end
				end
			end
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

		t:it("shows a long record whole in its full view, with the same actions, and goes back", function()
			local mock, env, ns, section = start()
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			local long = string.rep("She walked the whole Lantern Road with a single candle. ", 10)
			ns.Memories.Add(char, { title = "The night the lanterns went out", text = long }, "player", 1)
			ns.Memories.Add(char, { title = "Short", text = "Short" }, "player", 2)
			ns.MainWindow.Refresh()
			local d = section.detail
			expect.falsy(d:IsShown())
			-- Newest first: the short one has no Read; the long one does.
			expect.falsy(pcall(button, section.rows[1], "Read"), "nothing to read further")
			local read = button(section.rows[2], "Read")
			expect.equal(read.variant, "ghost")
			expect.truthy(read.tooltipText, "Read explains itself")
			click(read)
			expect.truthy(d:IsShown())
			expect.equal(d.title:GetText(), "The night the lanterns went out")
			expect.equal(d.text:GetText(), char.story.memories[1].text, "the whole text")
			expect.truthy(d.body:GetHeight() > ns.ChronicleView.LAYOUT.maxTextLines * ns.ChronicleView.LAYOUT.textLine,
				"the text scrolls when it is longer than a card")
			expect.equal(d.back:GetText(), "<  Back to memories")
			expect.falsy(pcall(button, d, "Read"), "no Read inside the full view")
			-- The record's own actions work from the full view.
			click(button(d, "Dispute"))
			expect.equal(char.story.memories[1].status, "disputed")
			expect.truthy(d:IsShown(), "the full view stays on its record after an action")
			click(button(d, "Edit"))
			expect.truthy(section.form:IsOpen())
			expect.equal(section.form.spec.title, "Edit memory")
			click(section.form.cancel)
			click(d.back)
			expect.falsy(d:IsShown())
			-- Removing the record closes its full view.
			click(button(section.rows[2], "Read"))
			click(button(d, "Remove"))
			mock.AcceptPopup()
			expect.equal(#char.story.memories, 1)
			expect.falsy(d:IsShown())
			-- Changing tab closes it too.
			ns.Memories.Add(char, { title = "Again", text = long }, "player", 3)
			ns.MainWindow.Refresh()
			click(button(section.rows[1], "Read"))
			expect.truthy(d:IsShown())
			tab(section, "arcs")
			expect.falsy(d:IsShown())
		end)

		t:it("marks a suggestion in the design's amber and a dispute in red", function()
			local _, env, ns, section = start()
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			local m = ns.Memories.Add(char, { text = "Mine" }, "player", 1)
			ns.Memories.Dispute(char, m.id, 2)
			ns.Memories.Add(char, { text = "Suggested" }, "suggested", 3)
			ns.MainWindow.Refresh()
			expect.equal(section.rows[1].highlight, "waiting")
			expect.equal(section.rows[1].chip.tone, "waiting")
			expect.equal(section.rows[2].highlight, "danger")
			expect.equal(section.rows[2].chip.tone, "danger")
			expect.equal(button(section.rows[2], "Accept").variant, "primary")
		end)

		t:it("answers continuity findings from the Review tab without changing canon", function()
			local mock, env, _, section = start()
			mock.Slash("stance add The Cenarion Circle; Loyal; Doubts its leaders")
			tab(section, "review")
			expect.truthy(section.rows[1]:IsShown())
			local answer = button(section.rows[1], "Intended")
			expect.equal(answer.variant, "default", "a real button (filled, with an edge), not a quiet label")
			expect.truthy(answer.tooltipText:find("means it", 1, true))
			click(answer)
			local story = env.DawnwardChroniclesDB.characters[CHAR].story
			expect.equal(story.reviews[1].choice, "secret")
			expect.equal(story.identity[1].conviction, "Doubts its leaders")
			expect.falsy(section.rows[1]:IsShown())
		end)
	end)
end

-- These specs model characters an earlier version created (Loader.Legacy).
return function(t, expect)
	Loader.Legacy(function() legacySpec(t, expect) end)
end
