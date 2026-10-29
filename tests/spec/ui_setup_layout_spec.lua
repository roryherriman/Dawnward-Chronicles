-- L2: the v0.7 layout of the first-time setup wizard (step rail, portrait,
-- grouped panels, privacy chips, Total RP 3 status, footer buttons, inline
-- validation, fit-to-screen). Mocked client: proves structure and wiring,
-- not the in-game look.
local Boot = require("support.boot")

local CHAR = "Testchar-TestRealm"

local function click(button)
	button:GetScript("OnClick")(button)
end

return function(t, expect)
	local function start(opts)
		opts = opts or {}
		opts.wizard = true
		return Boot.Start(opts)
	end

	local function wizard(ns)
		return ns.SetupWizard.Frame()
	end

	local function input(ns, key)
		for _, i in ipairs(wizard(ns).inputs) do
			if i.fieldKey == key then return i end
		end
	end

	t:describe("setup wizard v0.7: step rail and header", function()
		t:it("lists the six stages in a rail with done, current and upcoming states", function()
			local mock, _, ns = start()
			mock.Slash("")
			local w = wizard(ns)
			expect.equal(#w.steps, 6)
			local titles = {}
			for i, step in ipairs(w.steps) do titles[i] = step.label:GetText() end
			expect.deepEqual(titles, { "Welcome", "Character", "Story", "Privacy", "Appearance", "Finish" })
			ns.SetupWizard.Go(3)
			expect.equal(w.steps[1].state, "done")
			expect.equal(w.steps[2].state, "done")
			expect.equal(w.steps[3].state, "current")
			expect.equal(w.steps[4].state, "future")
			expect.truthy(w.steps[1].check:IsShown(), "a done stage shows the check mark")
			expect.falsy(w.steps[1].num:IsShown())
			expect.falsy(w.steps[4].check:IsShown())
			expect.truthy(w.steps[4].num:IsShown())
			expect.equal(w.stepLabel:GetText(), "STEP 3 OF 6")
			expect.equal(w.title:GetText(), "Story")
			expect.equal(w.subtitle:GetText(), ns.SetupWizard.SUBTITLES.story)
		end)

		t:it("a stage in the rail can be clicked, and the draft follows", function()
			local mock, env, ns = start()
			mock.Slash("")
			local w = wizard(ns)
			click(w.steps[5])
			expect.equal(w.page, 5)
			expect.equal(w.title:GetText(), "Appearance")
			expect.equal(env.DawnwardChroniclesDB.ui.wizardDrafts[CHAR].page, 5)
			click(w.steps[1])
			expect.equal(w.page, 1)
		end)

		t:it("footer: Set up later, Back and Next naming the next stage; Finish on the last", function()
			local mock, _, ns = start()
			mock.Slash("")
			local w = wizard(ns)
			expect.equal(w.next:GetText(), "Next: Character")
			expect.equal(w.back:GetText(), "Back")
			expect.equal(w.later:GetText(), "Set up later")
			expect.equal(w.next.variant, "primary")
			click(w.next)
			expect.equal(w.next:GetText(), "Next: Story")
			ns.SetupWizard.Go(6)
			expect.equal(w.next:GetText(), "Finish")
			expect.truthy(w.railNote:GetText():find("kept if you close", 1, true))
		end)

		t:it("the rail note says nothing is kept in the developer preview", function()
			local mock, _, ns = start()
			mock.Slash("dev setup")
			expect.truthy(wizard(ns).railNote:GetText():find("Preview", 1, true))
		end)
	end)

	t:describe("setup wizard v0.7: stages", function()
		t:it("the Character stage shows the player's own portrait and game identity", function()
			local mock, _, ns = start()
			mock.Slash("")
			ns.SetupWizard.Go(2)
			local w = wizard(ns)
			expect.equal(w.portrait.portrait.__portrait, "player", "the client's own portrait")
			expect.truthy(w.identity:GetText():find("Testchar", 1, true))
			expect.truthy(input(ns, "name").hint:IsShown())
			expect.truthy(input(ns, "pronouns").hint:IsShown())
		end)

		t:it("validates inline: an over-long field is marked and Next stays on the stage", function()
			local mock, env, ns = start()
			mock.Slash("")
			ns.SetupWizard.Go(2)
			local w = wizard(ns)
			local name = input(ns, "name")
			name:SetText(string.rep("n", 101))
			click(w.next)
			expect.equal(w.page, 2, "stays on Character")
			expect.truthy(name.invalid)
			expect.equal(name.errorLabel:GetText(), "! Name can be at most 100 characters.")
			expect.falsy(name.hint:IsShown(), "the hint gives way to the error")
			-- Enter on a one-line field goes through the same check.
			w.chain.onSubmit()
			expect.equal(w.page, 2)
			-- Fixing the text clears the error; Next then works.
			name:SetText("Lirael")
			name:GetScript("OnTextChanged")(name, true)
			expect.falsy(name.invalid)
			expect.truthy(name.hint:IsShown())
			click(w.next)
			expect.equal(w.page, 3)
			expect.falsy(env.DawnwardChroniclesDB.characters[CHAR], "nothing saved before Finish")
		end)

		t:it("Finish with an over-long field returns to Character instead of saving", function()
			local mock, env, ns = start()
			mock.Slash("")
			ns.SetupWizard.Go(2)
			input(ns, "title"):SetText(string.rep("t", 101))
			ns.SetupWizard.Go(6)
			click(wizard(ns).next)
			expect.equal(wizard(ns).page, 2)
			expect.truthy(input(ns, "title").invalid)
			expect.truthy(ns.SetupWizard.IsShown())
			expect.falsy(env.DawnwardChroniclesDB.characters[CHAR])
		end)

		t:it("Privacy explains Public, Private and Secret with chips, and shows Total RP 3 status only", function()
			local mock, env, ns = start()
			local trp3Before = ns.Util.DeepCopy(env.DawnwardChroniclesTRP3DB)
			mock.Slash("")
			ns.SetupWizard.Go(4)
			local w = wizard(ns)
			local tones = {}
			for i, chip in ipairs(w.privacyChips) do tones[i] = chip.tone .. "=" .. chip.label:GetText() end
			expect.deepEqual(tones, { "public=Public", "private=Private", "secret=Secret" })
			expect.equal(w.trp3Chip.label:GetText(), "Total RP 3: Not installed")
			expect.truthy(w.trp3Note:GetText():find("never publishes anything to Total RP 3", 1, true))
			ns.ctx.trp3Status = function() return { installed = true, loaded = true, version = "2.5" } end
			ns.SetupWizard.Refresh()
			expect.equal(w.trp3Chip.label:GetText(), "Total RP 3: Installed")
			ns.ctx.trp3Status = function() return { installed = true, loaded = false } end
			ns.SetupWizard.Refresh()
			expect.equal(w.trp3Chip.label:GetText(), "Total RP 3: Installed, not loaded")
			expect.deepEqual(env.DawnwardChroniclesTRP3DB, trp3Before, "status only, nothing written")
		end)

		t:it("Finish reviews the character and the choices in two panels", function()
			local mock, _, ns = start()
			mock.Slash("")
			ns.SetupWizard.Go(2)
			input(ns, "homeland"):SetText("Goldshire")
			ns.SetupWizard.Go(6)
			local w = wizard(ns)
			expect.truthy(w.summary:GetText():find("Homeland: Goldshire", 1, true))
			expect.falsy(w.summary:GetText():find("Theme:", 1, true))
			expect.truthy(w.choices:GetText():find("Theme: ", 1, true))
			expect.truthy(w.choices:GetText():find("Minimap button: shown", 1, true))
			expect.truthy(w.finishNote:GetText():find("nothing is sent to Total RP 3", 1, true))
		end)
	end)

	t:describe("setup wizard v0.7: size", function()
		t:it("uses the main window's design language and scales down to fit a small screen", function()
			local mock, env, ns = start()
			local L = ns.SetupWizard.LAYOUT
			expect.equal(L.width, 820)
			expect.equal(L.height, 600)
			expect.truthy(L.rail + 2 * L.pad + L.bodyWidth == L.width)
			env.UIParent:SetSize(800, 480)
			mock.Slash("")
			local w = wizard(ns)
			expect.truthy(w.fitScale < 1, "scaled down")
			expect.truthy(L.height * w.fitScale <= 480)
			expect.truthy(L.width * w.fitScale <= 800)
			env.UIParent:SetSize(1920, 1080)
			ns.SetupWizard.Open({})
			expect.equal(w.fitScale, 1, "never scaled up")
		end)
	end)
end
