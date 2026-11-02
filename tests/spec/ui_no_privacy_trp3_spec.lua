-- L2 (v0.10): the Total RP 3 page and the setup wizard, with Total RP 3
-- installed (the 3.4.1 fake), show no Public / Private / Secret
-- classification either. Completes ui_no_privacy_spec.lua, which covers
-- every other screen.
local Boot = require("support.boot")
local Fake = require("fakes.trp3_341")

local WORDS = { "Public", "Private", "Secret", "Secrets" }

local function click(button)
	button:GetScript("OnClick")(button)
end

local function start()
	-- The player's own TRP3 text is shown on the page; keep it free of the swept words.
	local fake = Fake.new({ about = { v = 2, TE = 1, BK = 1, T1 = { TX = "My own about text" } } })
	local extra = {}
	for k, v in pairs(fake.env) do
		if k ~= "C_AddOns" then extra[k] = v end
	end
	local mock, env, ns = Boot.Load({ extra = extra })
	mock.env.C_AddOns.IsAddOnLoaded = fake.env.C_AddOns.IsAddOnLoaded
	local meta = mock.env.C_AddOns.GetAddOnMetadata
	mock.env.C_AddOns.GetAddOnMetadata = function(name, field)
		return fake.env.C_AddOns.GetAddOnMetadata(name, field) or meta(name, field)
	end
	Boot.Login(mock)
	ns.SetupWizard.SkipAutoLaunchThisSession(ns.ctx.characterKey)
	return mock, env, ns, fake
end

local function hits(mock)
	local found = {}
	for _, f in ipairs(mock.allFrames) do
		if f.__kind ~= "EditBox" and f.__kind ~= "Texture" and f:IsVisible() then
			for _, text in ipairs({ f.__text, f.tooltipTitle, f.tooltipText }) do
				if type(text) == "string" then
					for _, word in ipairs(WORDS) do
						if text:find("%f[%a]" .. word .. "%f[%A]") then found[#found + 1] = word .. " in: " .. text end
					end
				end
			end
		end
	end
	return found
end

return function(t, expect)
	t:describe("no Public / Private / Secret: Total RP 3 page and setup (v0.10, L2)", function()
		t:it("every Total RP 3 tab, connected and not, and its dialogs", function()
			local mock, _, ns = start()
			for _, line in ipairs({ "set name Aelin", "set race Elf", "set faith The Light", "fact add origin Born in "
				.. "Lordaeron", "personality set courage 14", "stance add Stormwind; Loyal; Doubts the king" }) do
				mock.Slash(line)
			end
			ns.SettingsPanel.OpenPage("trp3")
			local page = ns.SettingsPanel.panel.trp3Page
			local function sweep(where)
				for i = 1, #page.nav.buttons do
					click(page.nav.buttons[i])
					local found = hits(mock)
					expect.equal(#found, 0, where .. " tab " .. i .. ": " .. table.concat(found, " | "))
				end
			end
			sweep("not connected")
			click(page.connectAll)
			if ns.Widgets.dialog:IsShown() then
				local found = hits(mock)
				expect.equal(#found, 0, "connect dialog: " .. table.concat(found, " | "))
				click(ns.Widgets.dialog.accept)
			end
			mock.RunTimers()
			ns.MainWindow.Refresh()
			sweep("connected")
			for _, b in ipairs({ page.rollback, page.exact }) do
				if b and b:IsVisible() and b:IsEnabled() then
					click(b)
					local found = hits(mock)
					expect.equal(#found, 0, "rollback dialog: " .. table.concat(found, " | "))
					if ns.Widgets.dialog:IsShown() then click(ns.Widgets.dialog.cancel or ns.Widgets.dialog.accept) end
				end
			end
		end)

		t:it("every setup stage", function()
			local mock, _, ns = start()
			ns.SetupWizard.Open({})
			for i = 1, 6 do
				ns.SetupWizard.Go(i)
				local found = hits(mock)
				expect.equal(#found, 0, "setup stage " .. i .. ": " .. table.concat(found, " | "))
			end
		end)
	end)
end
