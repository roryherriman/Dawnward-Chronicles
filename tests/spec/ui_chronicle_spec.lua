-- L2: the Chronicle section (narrative records in the window). Mocked client.
local Boot = require("support.boot")

local CHAR = "Testchar-TestRealm"

local function click(button)
	button:GetScript("OnClick")(button)
end

return function(t, expect)
	local function start()
		local mock, env, ns = Boot.Start()
		mock.Slash("set name Lirael")
		mock.Slash("")
		ns.MainWindow.Select("chronicle")
		return mock, env, ns, ns.ChronicleView.section
	end

	local function tab(section, id)
		for _, b in ipairs(section.tabButtons) do
			if b.tabId == id then click(b) end
		end
	end

	t:describe("Chronicle section (L2)", function()
		t:it("adds a memory in the player's words and shows its provenance, status and visibility", function()
			local _, env, _, section = start()
			expect.truthy(section.empty:IsShown())
			section.input:SetText("The day the grove burned")
			click(section.add)
			local m = env.DawnwardChroniclesDB.characters[CHAR].story.memories[1]
			expect.equal(m.text, "The day the grove burned")
			expect.truthy(section.rows[1]:IsShown())
			expect.equal(section.rows[1].meta:GetText(), "player, established, private")
		end)

		t:it("accepts a suggestion; public is refused until then", function()
			local _, env, ns, section = start()
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			ns.Memories.Add(char, { text = "Suggested" }, "suggested", 1)
			ns.MainWindow.Refresh()
			local row = section.rows[1]
			expect.equal(row.buttons[1]:GetText(), "Accept")
			click(row.buttons[2]) -- private -> public: refused for a proposal
			expect.equal(char.story.memories[1].visibility, "private")
			click(row.buttons[1])
			expect.equal(char.story.memories[1].status, "established")
			click(section.rows[1].buttons[2])
			expect.equal(char.story.memories[1].visibility, "public")
		end)

		t:it("adds arcs and goals, and lists stances and people", function()
			local mock, env, _, section = start()
			tab(section, "arcs")
			section.input:SetText("Finding where I belong")
			click(section.add)
			tab(section, "goals")
			section.input:SetText("Restore the grove")
			click(section.add)
			mock.Slash("stance add Darnassus; Devoted; Feels abandoned")
			mock.Slash("person add npc Keeper Remulos; Mentor")
			tab(section, "identity")
			expect.truthy(section.rows[1].text:GetText():find("Feels abandoned", 1, true))
			expect.falsy(section.input:IsShown(), "stances are added from chat")
			tab(section, "people")
			expect.truthy(section.rows[1].text:GetText():find("Keeper Remulos", 1, true))
			local story = env.DawnwardChroniclesDB.characters[CHAR].story
			expect.equal(story.arcs[1].title, "Finding where I belong")
			expect.equal(story.goals[1].title, "Restore the grove")
		end)

		t:it("answers continuity findings from the Review tab without changing canon", function()
			local mock, env, _, section = start()
			mock.Slash("stance add The Cenarion Circle; Loyal; Doubts its leaders")
			tab(section, "review")
			expect.truthy(section.rows[1]:IsShown())
			click(section.rows[1].buttons[3]) -- secret
			local story = env.DawnwardChroniclesDB.characters[CHAR].story
			expect.equal(story.reviews[1].choice, "secret")
			expect.equal(story.identity[1].conviction, "Doubts its leaders")
			expect.falsy(section.rows[1]:IsShown())
		end)
	end)
end
