-- L2 (v0.10.1): the in-game error "UI/Widgets.lua:266: attempt to call a nil
-- value" (Style.Apply on a main-window refresh, Style.Repaint from
-- Showcase.UpdateControls, portrait <-> live). The Showcase's rotate buttons
-- carry the client's own Texture objects as b.icon; the shared button painter
-- called the line-icon method SetColor on them, which a Texture does not
-- have. The mock's textures, like the client's, have no SetColor.
local Boot = require("support.boot")

local function click(b) b:GetScript("OnClick")(b) end

return function(t, expect)
	t:describe("Showcase with native texture icons (L2, regression)", function()
		local function open()
			local mock, env, ns = Boot.Start()
			mock.Slash("")
			ns.MainWindow.Select("character")
			click(ns.CharacterView.section.showcaseButton)
			return mock, env, ns, ns.CharacterView.section.showcase
		end

		t:it("a client Texture has no SetColor, as in game", function()
			local _, _, _, showcase = open()
			expect.equal(showcase.left.icon.SetColor, nil)
			expect.truthy(showcase.left.icon.SetVertexColor)
		end)

		t:it("repaints the Showcase on every theme without an error, arrows keeping their own colours", function()
			local _, _, ns, showcase = open()
			for _, id in ipairs({ "classic", "lightbound", "shadowbound" }) do
				local theme = ns.Themes.Get and ns.Themes.Get(id) or nil
				if theme then ns.Style.Apply(theme) end
				ns.MainWindow.Refresh()
				expect.deepEqual(showcase.left.icon.__vertex, { 1, 1, 1, 1 }, "untinted art (" .. id .. ")")
			end
		end)

		t:it("switches portrait <-> live, disables and re-enables the arrows, presses, turns and zooms", function()
			local _, _, ns, showcase = open()
			showcase:SetPreferPortrait(true)
			expect.falsy(showcase.left:IsEnabled(), "no turning the portrait")
			expect.truthy(showcase.left.icon:GetAlpha() < 1, "dimmed by its owner")
			ns.Style.Repaint(showcase.left)
			showcase:SetPreferPortrait(false)
			expect.truthy(showcase.left:IsEnabled())
			showcase.left:GetScript("OnMouseDown")(showcase.left)
			showcase.left:GetScript("OnMouseUp")(showcase.left)
			local before = showcase.model:GetRotation()
			click(showcase.right)
			expect.truthy(showcase.model:GetRotation() ~= before, "turned")
			click(showcase.zoomIn)
			expect.truthy(showcase.zoom > 0, "zoomed")
			ns.MainWindow.Refresh()
		end)

		t:it("tints a single-colour native icon with SetVertexColor and dims it when disabled", function()
			local _, env, ns = open()
			local b = ns.Widgets.Button(env.CreateFrame("Frame"), "", 30, 30)
			b.icon = b:CreateTexture(nil, "ARTWORK")
			ns.Style.Repaint(b)
			expect.equal(#b.icon.__vertex, 4)
			b:SetEnabled(false)
			expect.truthy(b.icon.__vertex[4] < 1, "a disabled control's icon is dimmed")
		end)
	end)
end
