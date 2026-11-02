-- L2: every record's actions belong visibly to that record (v0.6 entry
-- rows). Checks containment, spacing between records, status kept apart
-- from the actions that change it, and hover on the whole record.
local Boot = require("support.boot")

local CHAR = "Testchar-TestRealm"

local function click(button)
	button:GetScript("OnClick")(button)
end

local function y(frame)
	local p = frame.__points and frame.__points[1]
	return p and -(p[5] or 0) or 0
end

return function(t, expect)
	t:describe("entry rows: Chronicle records", function()
		local function start()
			local mock, env, ns = Boot.Start()
			mock.Slash("set name Lirael")
			mock.Slash("")
			ns.MainWindow.Select("chronicle")
			return mock, env, ns, ns.ChronicleView.section
		end

		local function tabTo(section, id)
			for _, b in ipairs(section.tabButtons) do
				if b.tabId == id then click(b) end
			end
		end

		local function goldshire(ns, char)
			char.story.places[ns.Places.Key("Elwynn Forest", "Goldshire")] = ns.Places.CleanEntry({
				zone = "Elwynn Forest", subzone = "Goldshire", kind = "town", first = 1, last = 1 })
		end

		t:it("keeps every button inside its own card, apart from the others and from the next card", function()
			local _, env, ns, section = start()
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			ns.Memories.Add(char, { title = "Suggested", text = "A suggestion" }, "suggested", 1)
			ns.Memories.Add(char, { title = "Mine", text = "My own" }, "player", 2)
			ns.MainWindow.Refresh()
			local L = ns.ChronicleView.LAYOUT
			expect.truthy(L.rowGap >= 4 and L.colGap >= 4, "cards are separated by a visible gap")
			for i = 1, 2 do
				local row = section.rows[i]
				local r = row.layout
				local spans = {}
				for _, b in ipairs(row.actions) do
					if b:IsShown() then
						expect.equal(b:GetParent(), row, "the button belongs to its card")
						local x, top = b.__points[1][2], -b.__points[1][3]
						expect.truthy(x >= L.cardPad and x + b:GetWidth() <= L.cardWidth - L.cardPad,
							"inside the card's sides: " .. b:GetText())
						expect.truthy(top >= r.divider.y and top + L.buttonHeight <= row:GetHeight(), "below the divider")
						spans[#spans + 1] = { x, x + b:GetWidth() }
					end
				end
				for a2 = 1, #spans do
					for b2 = a2 + 1, #spans do
						expect.truthy(spans[a2][2] <= spans[b2][1] or spans[b2][2] <= spans[a2][1], "buttons never overlap")
					end
				end
				expect.equal(row.vis, nil, "no visibility chip on a record card")
			end
		end)

		t:it("marks a suggestion as needing a decision, with Accept first and Remove on the right", function()
			local _, env, ns, section = start()
			ns.Memories.Add(env.DawnwardChroniclesDB.characters[CHAR], { text = "Suggested" }, "suggested", 1)
			ns.MainWindow.Refresh()
			local row = section.rows[1]
			expect.truthy(row.highlight, "a suggestion stands out")
			expect.equal(row.chip.label:GetText(), "Suggested · needs your call")
			expect.equal(row.actions[1]:GetText(), "Accept")
			expect.equal(row.actions[1].variant, "primary")
			local remove
			for _, b in ipairs(row.actions) do
				if b:IsShown() and b:GetText() == "Remove" then remove = b end
			end
			local L = ns.ChronicleView.LAYOUT
			expect.equal(remove.__points[1][2] + remove:GetWidth(), L.cardWidth - L.cardPad, "Remove sits at the right")
			expect.equal(remove.variant, "danger")
		end)

		t:it("shows a place's status apart from the actions that change it", function()
			local mock, env, ns, section = start()
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			goldshire(ns, char)
			tabTo(section, "places")
			local view = section.places
			local d = view.detail
			local function chipTexts()
				local out = {}
				for _, chip in ipairs(d.chips) do
					if chip:IsShown() then out[#out + 1] = chip.label:GetText() end
				end
				return out
			end
			expect.deepEqual(chipTexts(), { "No memories tied to it" })
			expect.falsy(view.rows[1].icon:IsShown())
			click(d.mark)
			expect.deepEqual(chipTexts(), { "Marked meaningful", "No memories tied to it" })
			expect.equal(d.mark:GetText(), "Unmark meaningful", "the action says what it will do")
			expect.truthy(view.rows[1].icon:IsShown(), "the list marks it too")
			click(d.homeland)
			mock.AcceptPopup()
			expect.deepEqual(chipTexts(), { "Homeland", "Marked meaningful", "No memories tied to it" })
			expect.falsy(d.homeland:IsEnabled(), "no action offered for what is already so")
			expect.truthy(d.note:GetText():find("Your Homeland field reads", 1, true), "the note names the field")
			expect.falsy(d.note:GetText():find("Private", 1, true) or d.note:GetText():find("visibility", 1, true))
			-- The status sits above the stats; the actions below the divider.
			local L = ns.ChroniclePlaces.LAYOUT
			local chipY = -d.chips[1].__points[1][3]
			expect.truthy(chipY + 20 <= L.height - L.detailPad - L.buttonHeight - 14, "status well above the actions")
			expect.equal(d.write:GetParent(), d)
		end)

		t:it("lists places with their zone, kind and visits, and selects one for the detail", function()
			local _, env, ns, section = start()
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			goldshire(ns, char)
			char.story.places["Duskwood / Darkshire"] = ns.Places.CleanEntry({ zone = "Duskwood", subzone = "Darkshire",
				first = 1700000000, last = 1700000000, visits = 3 })
			tabTo(section, "places")
			local view = section.places
			expect.equal(view.rows[1].name:GetText(), "Darkshire", "most recently visited first")
			expect.equal(view.rows[1].sub:GetText(), "Duskwood · not yet mapped", "never classified from its name")
			expect.equal(view.rows[1].visits:GetText(), "3 visits")
			expect.equal(view.rows[2].sub:GetText(), "Elwynn Forest · settlement")
			expect.equal(view.rows[2].visits:GetText(), "1 visit")
			expect.truthy(view.rows[1].selected)
			expect.equal(view.detail.sub:GetText(), "Duskwood · not yet mapped · first visited today")
			expect.equal(view.detail.stats[1].value:GetText(), "3")
			expect.equal(view.detail.stats[2].value:GetText(), "Today")
			view.rows[2]:GetScript("OnClick")(view.rows[2])
			expect.equal(view.detail.name:GetText(), "Goldshire")
			expect.truthy(view.rows[2].selected)
			expect.falsy(view.rows[1].selected)
			expect.equal(view.detail.stats[3].value:GetText(), "Counting from your next visit",
				"read-only: logged before the narrative clock")
			expect.falsy(view.prev:IsShown(), "no pager for one page")
		end)

		t:it("hides the places view on other tabs and shows the cards again", function()
			local _, env, ns, section = start()
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			goldshire(ns, char)
			ns.Memories.Add(char, { text = string.rep("A long memory that wraps. ", 12) }, "player", 1)
			tabTo(section, "places")
			expect.truthy(section.places.frame:IsShown())
			expect.falsy(section.rows[1]:IsShown())
			expect.falsy(section.new:IsShown())
			tabTo(section, "memories")
			expect.falsy(section.places.frame:IsShown())
			expect.truthy(section.rows[1]:IsShown())
			expect.truthy(section.new:IsShown())
			local L = ns.ChronicleView.LAYOUT
			expect.equal(section.rows[1].text:GetWidth(), L.cardWidth - 2 * L.cardPad)
		end)

		t:it("highlights the whole record while pointing at one of its buttons", function()
			local _, env, ns, section = start()
			ns.Memories.Add(env.DawnwardChroniclesDB.characters[CHAR], { text = "A memory" }, "player", 1)
			ns.MainWindow.Refresh()
			local row = section.rows[1]
			local edit
			for _, b in ipairs(row.buttons) do
				if b:IsShown() and b:GetText() == "Edit" then edit = b end
			end
			edit:GetScript("OnEnter")(edit)
			expect.truthy(row.hover, "the record lights up with its button")
			expect.falsy(section.rows[2].hover, "the neighbour does not")
			edit:GetScript("OnLeave")(edit)
			expect.falsy(row.hover)
		end)
	end)

	t:describe("entry rows: Character fields, family and history", function()
		local function open()
			local mock, env, ns = Boot.Start()
			mock.Slash("set name Aelin")
			mock.Slash("set title " .. string.rep("Keeper of very long titles ", 3))
			mock.Slash("family add mother Elsa " .. string.rep("Brightwater-of-the-long-name ", 3))
			mock.Slash("history add " .. string.rep("Left home on a long road that wraps. ", 5))
			mock.Slash("")
			ns.MainWindow.Select("character")
			return mock, env, ns, ns.CharacterView.section
		end

		t:it("puts each field's Edit inside that field's panel", function()
			local _, _, _, section = open()
			local checked = 0
			for i, spec in ipairs(section.specs) do
				local row = section.rows[i]
				if spec.kind == "field" or spec.kind == "item" then
					if row.edit:IsShown() then
						expect.equal(row.edit:GetParent(), row, "Edit belongs to its own entry")
						checked = checked + 1
					end
					expect.equal(row.vis, nil, "no visibility chip")
					expect.falsy(row.plain, "fields and items are boxed panels")
				end
			end
			expect.truthy(checked >= 4, "fields, family and history all checked")
		end)

		-- v0.7: fields are tiles in a grid and cards beside the family column,
		-- so panels are checked in two dimensions: no two overlap, and each
		-- pair is at least ENTRY.gap apart across or down.
		t:it("separates panels by a gap, even with long wrapped text", function()
			local _, _, ns, section = open()
			local boxes = {}
			-- The right column scrolls by itself: its entries are placed in its
			-- own scroll child, which stands at rightX.
			local rightX = ns.CharacterView.Columns(ns.MainWindow.ContentWidth()).rightX
			for i, spec in ipairs(section.specs) do
				local row = section.rows[i]
				if spec.kind == "field" or spec.kind == "item" then
					local p = row.__points[1]
					local x0 = row:GetParent() == section.side and rightX or 0
					boxes[#boxes + 1] = { x = x0 + (p[4] or 0), y = y(row), w = row:GetWidth(), h = row:GetHeight() }
				end
			end
			expect.truthy(#boxes >= 14, "fields, family and history checked")
			local gap = ns.Widgets.ENTRY.gap
			for a = 1, #boxes do
				for b = a + 1, #boxes do
					local A, B = boxes[a], boxes[b]
					local across = math.max(B.x - (A.x + A.w), A.x - (B.x + B.w))
					local down = math.max(B.y - (A.y + A.h), A.y - (B.y + B.h))
					expect.truthy(across >= gap or down >= gap, "a gap of at least ENTRY.gap between panels")
				end
			end
		end)

		t:it("highlights the field whose Edit button is pointed at", function()
			local _, _, _, section = open()
			local row
			for i, spec in ipairs(section.specs) do
				if spec.kind == "field" and spec.field.key == "name" then row = section.rows[i] end
			end
			row.edit:GetScript("OnEnter")(row.edit)
			expect.truthy(row.hover)
			row.edit:GetScript("OnLeave")(row.edit)
			expect.falsy(row.hover)
		end)
	end)
end
