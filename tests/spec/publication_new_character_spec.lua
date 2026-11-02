-- L2 (v0.10): a character first created by this version is on the
-- whole-profile model however it is created (setup, a command, an automatic
-- event), so it never waits for the one-time confirmation meant for data an
-- earlier version kept back.
local Boot = require("support.boot")

local CHAR = "Testchar-TestRealm"

return function(t, expect)
	t:describe("publication: characters new to v0.10 (L2)", function()
		t:it("a character created by a command publishes its whole profile, with no publish callout", function()
			local mock, env, ns = Boot.Start()
			mock.Slash("set name Lirael")
			mock.Slash("set faith The Light")
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			expect.truthy(ns.Publication.IsComplete(char))
			expect.equal(ns.Publication.Status(char), "profile")
			expect.equal(ns.Projection.GetPublic(char).fields.faith.value, "The Light")
			ns.MainWindow.Show(true)
			ns.MainWindow.Select("character")
			local section = ns.CharacterView.section
			expect.truthy(section.callout ~= nil, "the page has the callout frame")
			expect.falsy(section.callout:IsShown(), "no 'earlier version' callout")
		end)

		t:it("a character first seen through an automatic event is on the same model", function()
			local mock, env, ns = Boot.Start()
			mock.Fire("PLAYER_LEVEL_UP", 7)
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			expect.truthy(char, "the level-up created the character")
			expect.truthy(ns.Publication.IsComplete(char))
		end)
	end)
end
