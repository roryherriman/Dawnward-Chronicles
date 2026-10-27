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

	t:describe("Chronicle layout (#46)", function()
		t:it("never lets a row's text, status or buttons overlap, and fits the content area", function()
			local _, _, ns = Boot.Start()
			local CV = ns.ChronicleView
			local L = CV.LAYOUT
			local r = CV.RowRects()
			local parts = { r.text, r.meta }
			for _, b in ipairs(r.buttons) do parts[#parts + 1] = b end
			for i = 1, #parts do
				expect.truthy(parts[i].x >= 0 and parts[i].x + parts[i].w <= L.width, "inside the row width")
				expect.truthy(parts[i].y + parts[i].h <= L.rowHeight, "inside the row height")
				for j = i + 1, #parts do
					expect.falsy(overlaps(parts[i], parts[j]), string.format("parts %d and %d overlap", i, j))
				end
			end
			expect.truthy(L.inset * 2 + L.width <= ns.MainWindow.ContentWidth())
			expect.truthy(#CV.TABS * (L.tabWidth + L.tabGap) <= L.width + L.tabGap, "tabs fit one row")
			local contentHeight = ns.MainWindow.LAYOUT.height - ns.MainWindow.LAYOUT.contentTop
				- ns.MainWindow.LAYOUT.contentBottom
			expect.truthy(L.rowsTop + L.rows * L.rowHeight <= contentHeight - 34, "rows end above the paging bar")
		end)

		t:it("places each row's frames from the same rectangles", function()
			local _, _, ns, section = start()
			local r = ns.ChronicleView.RowRects()
			local row = section.rows[1]
			expect.equal(row.text:GetWidth(), r.text.w)
			expect.equal(row.meta:GetWidth(), r.meta.w)
			expect.equal(row.buttons[1]:GetWidth(), r.buttons[1].w)
		end)

		t:it("pages long lists", function()
			local _, env, ns, section = start()
			expect.equal(select(1, ns.ChronicleView.Pages(0, 1)), 1)
			expect.equal(select(2, ns.ChronicleView.Pages(13, 9)), 3)
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			for i = 1, 8 do ns.Memories.Add(char, { text = "Memory " .. i }, "player", i) end
			ns.MainWindow.Refresh()
			expect.equal(section.pageLabel:GetText(), "Page 1 of 2")
			expect.equal(section.rows[1].text:GetText(), "Memory 8")
			click(section.next)
			expect.equal(section.rows[1].text:GetText(), "Memory 2")
			expect.falsy(section.rows[3]:IsShown())
			expect.falsy(section.next:IsEnabled())
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
			expect.truthy(section.rows[1]:IsShown())
			expect.equal(section.rows[1].meta:GetText(), "player, established, private")
		end)

		t:it("keeps a form open with the reason when saving is refused", function()
			local _, env, _, section = start()
			click(section.new)
			form(section, {})
			expect.truthy(section.form:IsOpen())
			expect.truthy(section.form.message:GetText():find("needs", 1, true))
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
			local _, env, _, section = start()
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
			click(button(section.rows[1], "Edit"))
			form(section, { target = 0, state = "achieved" })
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
			expect.truthy(section.rows[1].text:GetText():find("Keeper Remulos", 1, true))
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
			local row = section.rows[1]
			expect.truthy(row.text:GetText():find("Goldshire", 1, true))
			click(button(row, "Mark"))
			expect.truthy(ns.Places.FindByName(char, "Goldshire").meaningful)
			click(button(section.rows[1], "Homeland"))
			expect.falsy(char.fields.homeland, "nothing changes before confirming")
			mock.AcceptPopup()
			expect.equal(char.fields.homeland.value, "Goldshire")
			expect.equal(char.fields.homeland.visibility, "private")
			expect.truthy(ns.Places.Homeland(char))
			click(button(section.rows[1], "Memory"))
			form(section, { text = "Where I first felt at home" })
			expect.equal(char.story.memories[1].zone, "Goldshire")
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
