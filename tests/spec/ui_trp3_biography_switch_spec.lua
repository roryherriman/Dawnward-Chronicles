-- L2 (v0.10.1): the Total RP 3 page's Biography section shows the biography
-- editor (UI/TRP3BiographyPanel.lua) and, behind a switch, the About page's
-- sync card (state, Approve, conflict choices, preview), so embedding the
-- editor never hides those controls.
local Boot = require("support.boot")
local Fake = require("fakes.trp3_341")

local function click(b) b:GetScript("OnClick")(b) end

return function(t, expect)
	t:describe("Total RP 3 page: Biography switch (L2)", function()
		t:it("opens on the editor; Sync shows the state and Approve; back again", function()
			local fake = Fake.new({})
			local extra = {}
			for k, v in pairs(fake.env) do
				if k ~= "C_AddOns" then extra[k] = v end
			end
			local mock, _, ns = Boot.Load({ extra = extra })
			mock.env.C_AddOns.IsAddOnLoaded = fake.env.C_AddOns.IsAddOnLoaded
			local meta = mock.env.C_AddOns.GetAddOnMetadata
			mock.env.C_AddOns.GetAddOnMetadata = function(name, field)
				return fake.env.C_AddOns.GetAddOnMetadata(name, field) or meta(name, field)
			end
			Boot.Login(mock)
			ns.SetupWizard.SkipAutoLaunchThisSession(ns.ctx.characterKey)
			mock.Slash("set summary Born in Stormwind.")
			ns.SettingsPanel.OpenPage("trp3")
			local page = ns.SettingsPanel.panel.trp3Page
			for _, b in ipairs(page.nav.buttons) do
				if b.segmentId == "about" then click(b) end
			end
			expect.truthy(page.biography, "the editor is embedded")
			expect.truthy(page.biography:IsVisible(), "Biography opens on the editor")
			expect.truthy(page.bioNav.buttons[1]:IsShown() and page.bioNav.buttons[2]:IsShown(), "the switch shows")
			click(page.bioNav.buttons[2])
			expect.falsy(page.biography:IsVisible())
			expect.truthy(page.featureView:IsVisible(), "the sync card")
			expect.truthy(page.approve:IsShown(), "Approve is there")
			click(page.bioNav.buttons[1])
			expect.truthy(page.biography:IsVisible())
			for _, b in ipairs(page.nav.buttons) do
				if b.segmentId == "traits" then click(b) end
			end
			expect.falsy(page.bioNav.buttons[1]:IsShown(), "only on Biography")
		end)
	end)
end
