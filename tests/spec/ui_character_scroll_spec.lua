-- L2 (v0.9, docs/design/UI_DESIGN_V09.md gap #6): on the Character profile
-- only the left column scrolls (mockup: character-profile.png); the right
-- column (Personality, Family) and the header stay put. Mocked client: the
-- scroll range is the scroll child's height less the frame's, as the client
-- computes it; whether it feels right is the in-game check.
local Loader = require("support.loader")
local Boot = require("support.boot")

local LONG = string.rep("Raised above the Lion's Pride Inn by a widowed innkeeper who kept the lamps lit. ", 12)

local function click(button)
	button:GetScript("OnClick")(button)
end

-- A character on the v0.10 model (as setup makes it), so no one-time
-- publish callout takes room above the columns.
local function openCharacter()
	local mock, env, ns = Boot.Start()
	ns.Actions.WithCharacter(ns.ctx, function(c) return ns.Publication.Adopt(c, 1) end)
	mock.Slash("")
	ns.MainWindow.Select("character")
	return mock, env, ns, ns.CharacterView.section
end

local function wheel(frame, delta)
	frame:GetScript("OnMouseWheel")(frame, delta)
end

-- Top (positive, downwards) of a region placed with SetPoint(point, rel, relPoint, x, y).
local function top(region)
	local p = region.__points[1]
	return -((type(p[2]) == "number" and p[3]) or p[5] or 0)
end

local function legacySpec(t, expect)
	t:describe("character profile: only the left column scrolls (L2)", function()
		t:it("puts the fields in the left scroll frame and the right column beside it", function()
			local mock, _, ns, section = openCharacter()
			mock.Slash("family add sister Mira")
			local CV = ns.CharacterView
			local L = CV.LAYOUT
			local cols = CV.Columns(ns.MainWindow.ContentWidth())
			local viewH = ns.MainWindow.ContentHeight() - L.scrollTop
			expect.equal(section.scroll:GetWidth(), cols.left, "the scroll frame is the left column")
			expect.equal(section.scroll:GetHeight(), viewH)
			expect.equal(section.scroll:GetScrollChild(), section.child)
			expect.equal(section.child:GetWidth(), cols.left)
			expect.equal(section.sideScroll.__points[1][2], cols.rightX, "the right column stands at rightX")
			expect.equal(section.sideScroll:GetWidth(), cols.right)
			expect.equal(section.sideScroll:GetParent(), section.frame, "not inside the left scroll frame")
			expect.equal(section.header:GetParent(), section.frame, "the header stays out of both")
			for i, spec in ipairs(section.specs) do
				local column = spec.group == "family" and section.side or section.child
				expect.equal(section.rows[i]:GetParent(), column, spec.kind)
			end
			expect.equal(section.personality:GetParent(), section.side)
			expect.equal(section.familyPanel:GetParent(), section.side)
			for _, a in ipairs(section.personality.axes) do expect.equal(a:GetParent(), section.side) end
			-- With long texts the left column scrolls; the right one stays put.
			mock.Slash("set summary " .. LONG)
			mock.Slash("set background " .. LONG)
			expect.truthy(section.scroll:GetVerticalScrollRange() > 0, "the left column scrolls")
			wheel(section.scroll, -1)
			expect.truthy(section.scroll:GetVerticalScroll() > 0)
			expect.equal(section.sideScroll:GetVerticalScroll(), 0, "scrolling the left leaves the right alone")
		end)

		t:it("covers every left-column entry with its scroll range, and follows edits", function()
			local mock, _, _, section = openCharacter()
			local viewH = section.scroll:GetHeight()
			local function check(what)
				local bottom = 0
				for i, spec in ipairs(section.specs) do
					if spec.group ~= "family" then
						local row = section.rows[i]
						bottom = math.max(bottom, top(row) + row:GetHeight())
					end
				end
				expect.equal(section.child:GetHeight(), math.max(bottom, 1), what .. ": the child ends at the last entry")
				expect.equal(section.scroll:GetVerticalScrollRange(), math.max(0, bottom - viewH),
					what .. ": the range reaches it")
			end
			check("empty")
			local before = section.child:GetHeight()
			mock.Slash("set summary " .. LONG)
			check("long summary")
			expect.truthy(section.child:GetHeight() > before, "a long summary makes the column taller")
			mock.Slash("set eyes grey")
			mock.Slash("set residence " .. string.rep("A long lane in Goldshire ", 4))
			check("Details group")
			-- At the end, then shorter: the view stops at the new end.
			for _ = 1, 100 do wheel(section.scroll, -1) end
			expect.equal(section.scroll:GetVerticalScroll(), section.scroll:GetVerticalScrollRange())
			mock.Slash("clear summary")
			check("summary cleared")
			expect.truthy(section.scroll:GetVerticalScroll() <= section.scroll:GetVerticalScrollRange(),
				"never past the end")
		end)

		t:it("scrolls on the wheel by a step, clamped to the range", function()
			local mock, _, ns, section = openCharacter()
			mock.Slash("set summary " .. LONG)
			mock.Slash("set motivation " .. LONG)
			local scroll = section.scroll
			expect.truthy(scroll:IsMouseWheelEnabled())
			local range = scroll:GetVerticalScrollRange()
			expect.truthy(range > ns.Widgets.WHEEL_STEP, "enough to scroll more than one step")
			wheel(scroll, -1)
			expect.equal(scroll:GetVerticalScroll(), ns.Widgets.WHEEL_STEP)
			wheel(scroll, 1)
			wheel(scroll, 1)
			expect.equal(scroll:GetVerticalScroll(), 0, "not above the top")
			for _ = 1, 100 do wheel(scroll, -1) end
			expect.equal(scroll:GetVerticalScroll(), range, "not past the end")
		end)

		t:it("keeps the wheel over the right column and the window from reaching the camera", function()
			local mock, _, ns, section = openCharacter()
			local side = section.sideScroll
			expect.truthy(side:IsMouseWheelEnabled(), "the right column takes the wheel")
			wheel(side, 1)
			expect.equal(side:GetVerticalScroll(), 0, "at the top the wheel is taken and nothing moves")
			local frame = ns.MainWindow.GetFrame()
			expect.truthy(frame:IsMouseWheelEnabled(), "the window takes the wheel everywhere else")
			wheel(frame, -1)
			-- v0.10: many family members never make the right column scroll: as
			-- many as fit, then "+N more" opens the whole list.
			for i = 1, 14 do mock.Slash("family add cousin Cousin" .. i) end
			expect.equal(side:GetVerticalScrollRange(), 0, "no secondary scroll bar")
			local panelBottom = top(section.familyPanel) + section.familyPanel:GetHeight()
			expect.equal(section.side:GetHeight(), panelBottom, "the whole family panel is in reach")
			expect.truthy(panelBottom <= side:GetHeight(), "and inside the column")
			expect.truthy(section.familyMore:IsShown())
			expect.equal(section.familyMore:GetText(), "+" .. section.familyHidden .. " more")
			expect.equal(section.familyShown + section.familyHidden, 14)
			expect.truthy(top(section.familyMore) + section.familyMore:GetHeight() <= panelBottom)
			for i, spec in ipairs(section.specs) do
				if spec.group == "family" and section.rows[i]:IsShown() then
					local row = section.rows[i]
					expect.truthy(top(row) + row:GetHeight() <= top(section.familyMore), "above +N more")
				end
			end
			local left = section.scroll:GetVerticalScroll()
			for _ = 1, 100 do wheel(side, -1) end
			expect.equal(side:GetVerticalScroll(), 0)
			expect.equal(section.scroll:GetVerticalScroll(), left, "the left column does not move")
		end)

		t:it("keeps the scroll place sane through profile, showcase and back", function()
			local mock, _, _, section = openCharacter()
			mock.Slash("set summary " .. LONG)
			mock.Slash("set background " .. LONG)
			wheel(section.scroll, -1)
			wheel(section.scroll, -1)
			local place = section.scroll:GetVerticalScroll()
			expect.truthy(place > 0)
			click(section.showcaseButton)
			expect.equal(section.mode, "showcase")
			expect.falsy(section.scroll:IsShown())
			expect.falsy(section.sideScroll:IsShown())
			expect.truthy(section.showcaseView:IsShown())
			expect.truthy(section.showcaseButton:IsShown(), "the way back stays in the header")
			click(section.showcaseButton)
			expect.equal(section.mode, "profile")
			expect.truthy(section.scroll:IsShown() and section.sideScroll:IsShown())
			expect.equal(section.scroll:GetVerticalScroll(), place, "back where the player was")
			-- Shorter while away: back at the new end, not past it.
			for _ = 1, 100 do wheel(section.scroll, -1) end
			click(section.showcaseButton)
			mock.Slash("clear background")
			click(section.showcaseButton)
			expect.equal(section.scroll:GetVerticalScroll(), section.scroll:GetVerticalScrollRange())
			expect.equal(section.previewButton, nil, "no public preview any more (v0.10)")
		end)

		t:it("an older character's publish callout pushes both columns down and gives them less room", function()
			local mock, _, ns = Boot.Start()
			mock.Slash("set name Lirael")
			mock.Slash("")
			ns.MainWindow.Select("character")
			local section = ns.CharacterView.section
			local L = ns.CharacterView.LAYOUT
			local full = ns.MainWindow.ContentHeight() - L.scrollTop
			expect.equal(ns.Publication.Status(ns.Actions.Character(ns.ctx)), "pending")
			expect.truthy(section.callout:IsShown())
			local drop = L.calloutHeight + L.calloutGap
			expect.equal(section.scroll:GetHeight(), full - drop)
			expect.equal(section.sideScroll:GetHeight(), full - drop)
			expect.equal(top(section.scroll), L.scrollTop + drop)
			expect.equal(top(section.sideScroll), L.scrollTop + drop)
			expect.equal(top(section.callout), L.scrollTop)
			mock.Slash("publish confirm")
			ns.MainWindow.Refresh()
			expect.falsy(section.callout:IsShown())
			expect.equal(section.scroll:GetHeight(), full, "the room comes back")
			expect.equal(top(section.scroll), L.scrollTop)
		end)

		t:it("keeps the same geometry in layout units at window scale 0.7 and 1.4", function()
			local mock, _, ns, section = openCharacter()
			mock.Slash("set summary " .. LONG)
			mock.Slash("family add sister Mira")
			local function snapshot()
				local s = { section.scroll:GetWidth(), section.scroll:GetHeight(), section.sideScroll:GetWidth(),
					section.sideScroll:GetHeight(), section.sideScroll.__points[1][2], section.child:GetHeight(),
					section.side:GetHeight(), section.scroll:GetVerticalScrollRange() }
				for i in ipairs(section.specs) do
					local row = section.rows[i]
					s[#s + 1] = top(row)
					s[#s + 1] = row:GetWidth()
					s[#s + 1] = row:GetHeight()
				end
				return s
			end
			local base = snapshot()
			local frame = ns.MainWindow.GetFrame()
			for _, scale in ipairs({ 0.7, 1.4 }) do
				frame:SetScale(scale)
				ns.MainWindow.Refresh()
				expect.deepEqual(snapshot(), base, "scale " .. scale)
			end
		end)
	end)

	t:describe("shared wheel and scroll helpers (L2)", function()
		t:it("scrolls through the template's bar, clamped, so its thumb follows", function()
			local mock, _, ns = Boot.Start()
			local scroll = mock.newFrame("ScrollFrame", nil, nil)
			local child = mock.newFrame("Frame", nil, scroll)
			scroll:SetSize(100, 200)
			child:SetSize(100, 500)
			scroll:SetScrollChild(child)
			local bar = mock.newFrame("Slider", nil, scroll)
			function bar:SetValue(v) self.value = v; scroll:SetVerticalScroll(v) end
			scroll.ScrollBar = bar
			expect.equal(ns.Widgets.ScrollTo(scroll, 1000), 300)
			expect.equal(bar.value, 300, "the bar moved too")
			expect.equal(ns.Widgets.ScrollTo(scroll, -5), 0)
			expect.equal(scroll:GetVerticalScroll(), 0)
			local plain = mock.newFrame("Frame", nil, nil)
			ns.Widgets.SwallowWheel(plain)
			expect.truthy(plain:IsMouseWheelEnabled())
			plain:GetScript("OnMouseWheel")(plain, -1)
		end)
	end)
end

-- These specs model characters an earlier version created (Loader.Legacy).
return function(t, expect)
	Loader.Legacy(function() legacySpec(t, expect) end)
end
