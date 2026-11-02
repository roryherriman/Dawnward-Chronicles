-- L1/L2: the guide and help (#51). Mocked client.
local Boot = require("support.boot")
local Loader = require("support.loader")

local CHAR = "Testchar-TestRealm"

return function(t, expect)
	local function click(button)
		button:GetScript("OnClick")(button)
	end

	t:describe("guide (#51)", function()
		t:it("is contextual help only: it never opens by itself, and closing it saves nothing (v0.6)", function()
			local mock, env, ns = Boot.Start()
			mock.Slash("set name Lirael")
			mock.Slash("")
			local guide = ns.GuidePanel.panel
			expect.falsy(guide:IsOpen(), "the setup wizard, not the guide, welcomes new characters")
			local before = ns.Util.DeepCopy(env.DawnwardChroniclesDB.characters[CHAR])
			mock.Slash("guide")
			expect.equal(guide.title:GetText(), "Welcome")
			click(guide.next)
			expect.equal(guide.title:GetText(), "Journal")
			expect.truthy(guide.topicButtons[2].selected, "the current topic is shown as selected")
			click(guide.close)
			expect.falsy(guide:IsOpen())
			expect.deepEqual(env.DawnwardChroniclesDB.characters[CHAR], before, "closing the guide writes nothing")
		end)

		t:it("opens from ?, Settings and chat", function()
			local mock, env, ns = Boot.Start()
			mock.Slash("set name Lirael")
			env.DawnwardChroniclesDB.characters[CHAR].guide = { done = true }
			mock.Slash("")
			local guide = ns.GuidePanel.panel
			expect.falsy(guide:IsOpen())
			click(ns.MainWindow.GetFrame().help)
			expect.truthy(guide:IsOpen())
			click(ns.MainWindow.GetFrame().help)
			expect.falsy(guide:IsOpen())
			mock.Slash("guide")
			expect.truthy(guide:IsOpen())
			click(guide.close)
			ns.MainWindow.ToggleSettings()
			click(ns.SettingsPanel.panel.guide)
			expect.truthy(guide:IsOpen())
		end)

		t:it("searches the guide and the command list", function()
			local mock, _, ns = Boot.Start()
			mock.Slash("")
			local guide = ns.GuidePanel.panel
			guide.search:SetText("goal level")
			click(guide.searchButton)
			expect.equal(guide.title:GetText(), "Search")
			expect.truthy(guide.body:GetText():find("goal level 12 20", 1, true))
			guide.search:SetText("zzzz")
			click(guide.searchButton)
			expect.truthy(guide.body:GetText():find("Nothing matches", 1, true))
		end)

		t:it("does not create a record when saved data is read-only", function()
			local mock, env, ns = Boot.Start({ savedVariables = { DawnwardChroniclesDB = { schemaVersion = 999 } } })
			mock.Slash("")
			if ns.GuidePanel.panel:IsOpen() then click(ns.GuidePanel.panel.close) end
			expect.equal(env.DawnwardChroniclesDB.schemaVersion, 999)
			expect.falsy(env.DawnwardChroniclesDB.characters)
		end)
	end)

	t:describe("help (#51)", function()
		local function run(cmd)
			local mock = Boot.Start()
			return mock.Slash(cmd)
		end

		t:it("is short by default and points to the guide and the full list", function()
			local reply = run("help")
			expect.truthy(reply:find("/dawnward guide", 1, true))
			expect.truthy(reply:find("help all", 1, true))
			expect.falsy(reply:find("family add", 1, true))
			expect.truthy(run("help all"):find("family add", 1, true))
			expect.truthy(run("help story"):find("cooldown", 1, true))
			expect.truthy(run("help profile published"):find("Total RP 3", 1, true))
			local all = run("help all")
			for _, word in ipairs({ "vis ", "public|private|secret", "[secrets]" }) do
				expect.falsy(all:find(word, 1, true), "retired from help: " .. word)
			end
		end)

		t:it("explains a missing record number with an example", function()
			local reply = run("goal milestone Find a ship")
			expect.truthy(reply:find("/dawnward goal milestone 12 Find a ship", 1, true))
			reply = run("arc turn Left home")
			expect.truthy(reply:find("/dawnward arc turn 7 Left home", 1, true))
		end)

		t:it("cleans saved guide state", function()
			local ns = Loader.Core()
			expect.deepEqual(ns.Guide.Clean({ done = "yes", page = 99 }), {})
			expect.deepEqual(ns.Guide.Clean({ done = true, page = 2 }), { done = true, page = 2 })
			expect.truthy(ns.Guide.ShouldAutoOpen(nil))
		end)
	end)
end
