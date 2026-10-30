-- L2: the resizable main window (v0.7 fix): a gold grip in the bottom-right
-- corner scales the window, within limits, inside the screen, remembered.
local Boot = require("support.boot")

local function click(button)
	button:GetScript("OnClick")(button)
end

return function(t, expect)
	local function open(opts, w, h)
		local mock, env, ns = Boot.Start(opts)
		env.UIParent.__width, env.UIParent.__height = w or 1920, h or 1080
		mock.Slash("")
		return mock, env, ns, ns.MainWindow.GetFrame()
	end

	t:describe("window size rules (pure)", function()
		t:it("keeps the chosen scale between the limits and inside the screen", function()
			local _, _, ns = Boot.Load()
			local W = ns.MainWindow
			expect.equal(W.EffectiveScale(nil, 1920, 1080), 1, "the design's own size by default")
			expect.equal(W.EffectiveScale(5, 3840, 2160), W.MAX_SCALE)
			expect.equal(W.EffectiveScale(0.1, 1920, 1080), W.MIN_SCALE, "never unreadably small")
			local fit = W.FitLimit(1024, 640)
			expect.truthy(fit < 1)
			expect.equal(W.EffectiveScale(1.3, 1024, 640), fit, "never larger than the screen")
			expect.truthy(1100 * fit <= 1024 - W.FIT_MARGIN + 1e-9 and 720 * fit <= 640 - W.FIT_MARGIN + 1e-9)
		end)

		t:it("follows the cursor from the fixed top-left corner, and never past the screen edge", function()
			local _, _, ns = Boot.Load()
			local W = ns.MainWindow
			-- Window at (100, 900) on a 1920 x 1080 screen; drag to 1200 wide.
			expect.truthy(math.abs(W.DragScale(100, 900, 100 + 1210, 900 - 500, 1920, 1080) - 1.1) < 1e-9)
			-- Dragging far past the right edge stops at the edge.
			local s = W.DragScale(1000, 900, 5000, 0, 1920, 1080)
			expect.truthy(1000 + 1100 * s <= 1920 + 1e-9, "inside the right edge")
			expect.truthy(900 - 720 * s >= -1e-9, "inside the bottom edge")
			expect.equal(W.DragScale(100, 900, 120, 880, 1920, 1080), W.MIN_SCALE, "a tiny drag stops at the minimum")
		end)
	end)

	t:describe("the resize grip", function()
		t:it("is a gold grip in the bottom-right corner", function()
			local _, _, _, frame = open()
			local grip = frame.resizeHandle
			expect.truthy(grip ~= nil)
			local p = grip.__points[1]
			expect.equal(p[1], "BOTTOMRIGHT")
			expect.truthy(grip:GetNormalTexture().__texture:find("SizeGrabber", 1, true))
		end)

		t:it("scales the window while held, works only while held, and remembers the size", function()
			local mock, env, ns, frame = open()
			local grip = frame.resizeHandle
			frame.__left, frame.__top = 100, 900
			grip:GetScript("OnMouseDown")(grip)
			expect.truthy(grip:GetScript("OnUpdate") ~= nil)
			mock.cursorX, mock.cursorY = 100 + 1210, 900 - 500
			grip:GetScript("OnUpdate")(grip)
			expect.truthy(math.abs(frame:GetScale() - 1.1) < 1e-9)
			local point = frame.__points[#frame.__points]
			expect.equal(point[1], "TOPLEFT")
			expect.truthy(math.abs(point[4] * 1.1 - 100) < 1e-6 and math.abs(point[5] * 1.1 - 900) < 1e-6,
				"the top-left corner stays put")
			grip:GetScript("OnMouseUp")(grip)
			expect.equal(grip:GetScript("OnUpdate"), nil, "no work once released")
			expect.truthy(math.abs(env.DawnwardChroniclesDB.ui.windowScale - 1.1) < 1e-9)
			-- After /reload or logout: the same size.
			local saved = ns.Util.DeepCopy(env.DawnwardChroniclesDB)
			local _, _, _, frame2 = open({ savedVariables = { DawnwardChroniclesDB = saved } })
			expect.truthy(math.abs(frame2:GetScale() - 1.1) < 1e-9)
		end)

		t:it("does nothing while the cursor has not moved", function()
			local mock, _, _, frame = open()
			local grip = frame.resizeHandle
			frame.__left, frame.__top = 100, 900
			grip:GetScript("OnMouseDown")(grip)
			mock.cursorX, mock.cursorY = 1310, 400
			grip:GetScript("OnUpdate")(grip)
			local points = #frame.__points
			grip:GetScript("OnUpdate")(grip)
			grip:GetScript("OnUpdate")(grip)
			expect.equal(#frame.__points, points, "no re-anchoring for an unmoved cursor")
			grip:GetScript("OnMouseUp")(grip)
		end)

		t:it("fits a smaller screen even when a larger size was chosen", function()
			local mock, env, ns = open()
			ns.Actions.SaveWindowScale(ns.ctx, 1.4)
			mock.Slash("")
			env.UIParent.__width, env.UIParent.__height = 1024, 640
			mock.Slash("")
			local frame = ns.MainWindow.GetFrame()
			expect.equal(frame:GetScale(), ns.MainWindow.FitLimit(1024, 640))
		end)

		t:it("Settings → General → Reset window size returns to the design size", function()
			local mock, env, ns, frame = open()
			ns.Actions.SaveWindowScale(ns.ctx, 1.3)
			mock.Slash("")
			mock.Slash("")
			expect.truthy(math.abs(frame:GetScale() - 1.3) < 1e-9)
			click(frame.gear)
			click(ns.SettingsPanel.panel.resetSize)
			expect.equal(env.DawnwardChroniclesDB.ui.windowScale, nil)
			expect.equal(frame:GetScale(), 1)
		end)

		t:it("cleans a damaged saved size", function()
			local _, _, ns = Boot.Load()
			expect.equal(ns.Schema.NormalizeUi({ windowScale = 0 / 0 }).windowScale, nil)
			expect.equal(ns.Schema.NormalizeUi({ windowScale = "big" }).windowScale, nil)
			expect.equal(ns.Schema.NormalizeUi({ windowScale = 1.2 }).windowScale, 1.2)
		end)
	end)
end
