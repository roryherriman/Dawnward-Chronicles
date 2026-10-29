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

		t:it("keeps every button inside its own record and nearer it than the next one", function()
			local _, _, ns = Boot.Start()
			local L = ns.ChronicleView.LAYOUT
			local r = ns.ChronicleView.RowRects()
			local cardHeight = L.rowHeight - L.rowGap
			for _, b in ipairs(r.buttons) do
				expect.truthy(b.x >= L.rowPad - 2 and b.x + b.w <= L.width - L.rowPad + 2, "inside the card's sides")
				expect.truthy(b.y >= 0 and b.y + b.h <= cardHeight, "inside the card's height")
				local toOwnText = b.y - (r.text.y + r.text.h)
				local toNextText = (L.rowHeight + r.text.y) - (b.y + b.h)
				expect.truthy(toOwnText < toNextText, "nearer its own record's text than the next record's")
			end
			expect.truthy(L.rowGap >= 4, "records are separated by a visible gap")
		end)

		t:it("lays out long button labels from the record's right edge without leaving it", function()
			local _, env, ns, section = start()
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			char.story.places[ns.Places.Key("Elwynn Forest", "Goldshire")] = ns.Places.CleanEntry({
				zone = "Elwynn Forest", subzone = "Goldshire", kind = "town", first = 1, last = 1 })
			for _, b in ipairs(section.tabButtons) do
				if b.tabId == "places" then click(b) end
			end
			local L = ns.ChronicleView.LAYOUT
			local row = section.rows[1]
			local left = L.width
			for _, b in ipairs(row.buttons) do
				if b:IsShown() then
					local x = b.__points[1][2]
					expect.equal(b:GetParent(), row, "the button belongs to the record")
					expect.truthy(x >= L.rowPad - 2, "starts inside the record: " .. b:GetText())
					expect.truthy(x + b:GetWidth() <= L.width - L.rowPad + 2, "ends inside the record")
					expect.truthy(x + b:GetWidth() <= left, "buttons never overlap")
					left = x
				end
			end
			expect.truthy(left >= L.metaWidth + L.rowPad, "buttons stay clear of the record's details")
		end)

		t:it("shows a place's status apart from the actions that change it", function()
			local mock, env, ns, section = start()
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			char.story.places[ns.Places.Key("Elwynn Forest", "Goldshire")] = ns.Places.CleanEntry({
				zone = "Elwynn Forest", subzone = "Goldshire", kind = "town", first = 1, last = 1 })
			for _, b in ipairs(section.tabButtons) do
				if b.tabId == "places" then click(b) end
			end
			local row = section.rows[1]
			expect.equal(row.status:GetText(), "")
			local function shown(text)
				for _, b in ipairs(row.buttons) do
					if b:IsShown() and b:GetText() == text then return b end
				end
			end
			click(shown("Mark meaningful"))
			expect.equal(row.status:GetText(), "MEANINGFUL")
			expect.truthy(shown("Unmark meaningful"), "the action says what it will do")
			click(shown("Set as homeland"))
			mock.AcceptPopup()
			expect.equal(row.status:GetText(), "HOMELAND  -  MEANINGFUL")
			expect.falsy(shown("Set as homeland"), "no action offered for what is already so")
			-- The status sits on line one, the actions on line two.
			local L = ns.ChronicleView.LAYOUT
			expect.truthy(6 + 14 <= L.lineTwo, "status ends above the buttons")
			expect.equal(row.text:GetWidth(), ns.ChronicleView.RowRects().text.w - L.statusWidth - 8,
				"the title makes room for the status")
		end)

		t:it("clears the status and restores the text width on other tabs", function()
			local _, env, ns, section = start()
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			local place = ns.Places.CleanEntry({ zone = "Elwynn Forest", subzone = "Goldshire", first = 1, last = 1 })
			place.meaningful = true
			char.story.places[ns.Places.Key("Elwynn Forest", "Goldshire")] = place
			ns.Memories.Add(char, { text = string.rep("A long memory that wraps. ", 12) }, "player", 1)
			for _, b in ipairs(section.tabButtons) do
				if b.tabId == "places" then click(b) end
			end
			expect.equal(section.rows[1].status:GetText(), "MEANINGFUL")
			for _, b in ipairs(section.tabButtons) do
				if b.tabId == "memories" then click(b) end
			end
			expect.equal(section.rows[1].status:GetText(), "")
			expect.equal(section.rows[1].text:GetWidth(), ns.ChronicleView.RowRects().text.w)
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

		t:it("puts each field's Edit and visibility controls inside that field's panel", function()
			local _, _, _, section = open()
			local checked = 0
			for i, spec in ipairs(section.specs) do
				local row = section.rows[i]
				if spec.kind == "field" or spec.kind == "item" then
					if row.edit:IsShown() then
						expect.equal(row.edit:GetParent(), row, "Edit belongs to its own entry")
						checked = checked + 1
					end
					if row.vis:IsShown() then
						expect.equal(row.vis:GetParent(), row, "visibility belongs to its own entry")
					end
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
			for i, spec in ipairs(section.specs) do
				local row = section.rows[i]
				if spec.kind == "field" or spec.kind == "item" then
					local p = row.__points[1]
					boxes[#boxes + 1] = { x = p[4] or 0, y = y(row), w = row:GetWidth(), h = row:GetHeight() }
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
