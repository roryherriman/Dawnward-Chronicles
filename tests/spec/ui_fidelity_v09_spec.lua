-- L1/L2 (v0.9): visual fidelity changes made against the approved mockups
-- (docs/design/mockups, docs/design/UI_DESIGN_V09.md). Mocked client: proves
-- sizes and wiring, not the in-game look.
local Boot = require("support.boot")

return function(t, expect)
	t:describe("v0.9 fidelity: the setup wizard (SetupWizard.dc.html)", function()
		t:it("asks a question as each stage's heading, keeping the short names in the rail", function()
			local mock, _, ns = Boot.Start({ wizard = true })
			mock.Slash("")
			local w = ns.SetupWizard.Frame()
			ns.SetupWizard.Go(2)
			expect.equal(w.title:GetText(), "Who is your character?", "the mockup's own heading")
			expect.equal(w.steps[2].label:GetText(), "Character")
			for id, headline in pairs(ns.SetupWizard.HEADLINES) do
				expect.falsy(headline:lower():find("%f[%a]she%f[%A]") or headline:lower():find("%f[%a]he%f[%A]")
					or headline:lower():find("%f[%a]her%f[%A]") or headline:lower():find("%f[%a]his%f[%A]"),
					id .. ": no assumed pronoun")
				expect.truthy(ns.Style.TextWidth(headline, "stage") <= ns.SetupWizard.LAYOUT.bodyWidth - 44,
					id .. " fits beside the close button")
			end
		end)

		t:it("uses the mockup's 40 px inputs and a 26 px Cinzel stage title", function()
			local ns = select(3, Boot.Start({ wizard = true }))
			expect.equal(ns.SetupWizard.LAYOUT.field, 40)
			expect.equal(ns.Style.FONT_BY_STYLE.stage.size, 26)
			expect.equal(ns.Style.FONT_BY_STYLE.stage.file, "display")
		end)
	end)

	t:describe("v0.9 fidelity: the shared slim scroll bar", function()
		t:it("sizes the thumb to the view, with a minimum, and fills the track when nothing scrolls", function()
			local ns = select(3, Boot.Start())
			local W = ns.Widgets
			expect.equal(W.SlimThumbHeight(300, 300), 300)
			expect.equal(W.SlimThumbHeight(300, 600), 150)
			expect.equal(W.SlimThumbHeight(300, 30000), W.SLIM_BAR.thumbMin)
			expect.equal(W.SlimThumbHeight(0, 100), 0)
		end)

		t:it("restyles a template bar, and leaves a scroll frame without one alone", function()
			local mock, _, ns = Boot.Start()
			local scroll = mock.newFrame("ScrollFrame", nil, nil)
			expect.equal(ns.Widgets.SlimScrollBar(scroll, 8), nil, "no template bar: nothing changes")
			local bar = mock.newFrame("Slider", nil, scroll)
			bar.ScrollUpButton = mock.newFrame("Button", nil, bar)
			bar.ScrollDownButton = mock.newFrame("Button", nil, bar)
			bar.ThumbTexture = bar:CreateTexture()
			scroll.ScrollBar = bar
			scroll.GetVerticalScrollRange = function() return 300 end
			scroll:SetSize(200, 300)
			local slim = ns.Widgets.SlimScrollBar(scroll, 8)
			expect.equal(slim, bar)
			expect.equal(bar:GetWidth(), ns.Widgets.SLIM_BAR.width)
			slim.UpdateThumb()
			expect.equal(bar.ThumbTexture:GetHeight(), 150, "a proportional thumb")
			expect.truthy(bar:IsShown())
			scroll.GetVerticalScrollRange = function() return 0 end
			slim.UpdateThumb()
			expect.falsy(bar:IsShown(), "hidden when nothing scrolls")
		end)
	end)
end
