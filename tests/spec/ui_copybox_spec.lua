-- L2: copy window layering and layout. The mock records what our code asks
-- the client to do; whether it *looks* right is still an L3 check.
local Loader = require("support.loader")
local Mock = require("support.wow_mock")

-- Strata from lowest to highest, as defined by the WoW client.
local STRATA_ORDER = {
	BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5,
	FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8,
}

local function loadCopyBox()
	local mock = Mock.new()
	local env = Loader.NewEnv(mock.env)
	local ns = Loader.Load({ "UI/CopyBox.lua" }, env, {})
	return ns.CopyBox, mock
end

local function overlaps(a, b)
	return a.bottom < b.top and b.bottom < a.top
end

return function(t, expect)
	t:describe("copy window layout maths", function()
		local CopyBox = loadCopyBox()
		local L = CopyBox.LAYOUT
		local r = CopyBox.ComputeLayout(L)

		t:it("stacks buttons, status line and text area without overlap", function()
			expect.falsy(overlaps(r.buttons, r.status), "status overlaps buttons")
			expect.falsy(overlaps(r.status, r.well), "status overlaps the text well")
			expect.truthy(r.scroll.bottom >= r.well.bottom and r.scroll.top <= r.well.top, "text sits inside the well")
		end)

		t:it("keeps every region inside the opaque background", function()
			for _, name in ipairs({ "status", "well", "scroll" }) do
				local rect = r[name]
				expect.truthy(rect.left >= r.background.left and rect.right <= r.background.right
					and rect.bottom >= r.background.bottom and rect.top <= r.background.top, name .. " escapes the background")
			end
			expect.truthy(r.buttons.bottom >= r.background.bottom)
		end)

		t:it("leaves room for the scroll bar and the title", function()
			expect.truthy(L.width - r.scroll.right >= L.pad + 20, "scroll bar needs ~20px beside the text")
			expect.truthy(L.height - r.well.top >= L.titleTop + 14, "text well must start below the title")
		end)

		t:it("gives the text a usable area", function()
			expect.truthy(r.editWidth >= 400, "text width " .. r.editWidth)
			expect.truthy(r.textHeight >= L.minTextHeight, "text height " .. r.textHeight)
		end)
	end)

	t:describe("copy window layering (L2)", function()
		t:it("opens above other addons' dialogs, including Total RP 3 popups", function()
			local CopyBox = loadCopyBox()
			CopyBox.ShowExport("Title", "!DWC1!B!00000000!{}")
			local frame = CopyBox.GetFrame()
			-- TRP3 3.4.1 uses DIALOG for its popups/tutorials and MEDIUM for its main window.
			expect.truthy(STRATA_ORDER[frame:GetFrameStrata()] > STRATA_ORDER.DIALOG,
				"strata is " .. tostring(frame:GetFrameStrata()))
			expect.truthy(STRATA_ORDER[frame:GetFrameStrata()] < STRATA_ORDER.TOOLTIP, "must stay below tooltips")
			expect.truthy(frame.__toplevel, "toplevel so clicks raise it")
		end)

		t:it("raises itself every time it opens", function()
			local CopyBox = loadCopyBox()
			CopyBox.ShowExport("A", "x")
			CopyBox.ShowImport(function() end, function() end, function() end)
			expect.equal(CopyBox.GetFrame().__raised, 2)
		end)

		t:it("uses fully opaque backgrounds and no translucent backdrop fill", function()
			local CopyBox = loadCopyBox()
			CopyBox.ShowExport("A", "x")
			local frame = CopyBox.GetFrame()
			expect.equal(frame.__backdrop.bgFile, nil, "stock dialog background is translucent")
			local solid = 0
			for _, tex in ipairs(frame.__textures) do
				if tex.__color then
					expect.equal(tex.__layer, "BACKGROUND")
					expect.equal(tex.__color[4], 1, "background alpha")
					solid = solid + 1
				end
			end
			expect.equal(solid, 2, "window background and text well")
		end)

		t:it("pads the text and sizes it to the visible area", function()
			local CopyBox = loadCopyBox()
			CopyBox.ShowExport("A", "x")
			local frame = CopyBox.GetFrame()
			local r = CopyBox.ComputeLayout(CopyBox.LAYOUT)
			local edit = frame.editBox
			expect.deepEqual(edit.__insets, { 6, 6, 6, 6 })
			expect.equal(edit:GetWidth(), r.editWidth)
			frame.scroll:GetScript("OnSizeChanged")(frame.scroll, 450, 200)
			expect.equal(edit:GetWidth(), 450, "text width follows the scroll area")
			expect.truthy(frame.status.__wordWrap)
		end)

		t:it("starts at the top and keeps the cursor visible", function()
			local CopyBox = loadCopyBox()
			CopyBox.ShowExport("A", "x")
			local frame = CopyBox.GetFrame()
			local scroll, edit = frame.scroll, frame.editBox
			expect.equal(scroll:GetVerticalScroll(), 0)
			scroll:SetHeight(200)
			local onCursor = edit:GetScript("OnCursorChanged")
			onCursor(edit, 0, -390, 2, 14) -- caret below the visible area
			expect.equal(scroll:GetVerticalScroll(), 204)
			onCursor(edit, 0, -50, 2, 14) -- caret above it
			expect.equal(scroll:GetVerticalScroll(), 50)
			onCursor(edit, 0, -60, 2, 14) -- already visible: no jump
			expect.equal(scroll:GetVerticalScroll(), 50)
		end)
	end)
end
