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
		t:it("lists the stages in a rail with done, current and upcoming states (v0.9: no Privacy stage)", function()
			local mock, _, ns = start()
			mock.Slash("")
			local w = wizard(ns)
			expect.equal(#w.steps, 6)
			local titles = {}
			for i, step in ipairs(w.steps) do titles[i] = step.label:GetText() end
			expect.deepEqual(titles, { "Welcome", "Character", "Story", "Appearance", "Total RP 3", "Finish" })
			expect.falsy(w.steps[5]:IsShown(), "the Total RP 3 stage only when Total RP 3 is installed")
			expect.equal(w.steps[6].num:GetText(), "5", "the visible stages are numbered in order")
			ns.SetupWizard.Go(3)
			expect.equal(w.steps[1].state, "done")
			expect.equal(w.steps[2].state, "done")
			expect.equal(w.steps[3].state, "current")
			expect.equal(w.steps[4].state, "future")
			expect.truthy(w.steps[1].check:IsShown(), "a done stage shows the check mark")
			expect.falsy(w.steps[1].num:IsShown())
			expect.falsy(w.steps[4].check:IsShown())
			expect.truthy(w.steps[4].num:IsShown())
			expect.equal(w.stepLabel:GetText(), "STEP 3 OF 5")
			expect.equal(w.title:GetText(), "Story")
			expect.equal(w.subtitle:GetText(), ns.SetupWizard.SUBTITLES.story)
		end)

		t:it("a stage in the rail can be clicked, and the draft follows", function()
			local mock, env, ns = start()
			mock.Slash("")
			local w = wizard(ns)
			click(w.steps[4])
			expect.equal(w.page, 4)
			expect.equal(w.title:GetText(), "Appearance")
			expect.equal(env.DawnwardChroniclesDB.ui.wizardDrafts[CHAR].page, 4)
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

		t:it("the Total RP 3 stage appears only when Total RP 3 is installed, and writes nothing", function()
			local mock, env, ns = start()
			local trp3Before = ns.Util.DeepCopy(env.DawnwardChroniclesTRP3DB)
			mock.Slash("")
			local w = wizard(ns)
			ns.SetupWizard.Go(5)
			expect.equal(w.page, 6, "skipped: Total RP 3 is not installed")
			ns.SetupWizard.Close()
			ns.ctx.trp3Status = function() return { installed = true, loaded = false } end
			ns.SetupWizard.Open({})
			expect.truthy(w.steps[5]:IsShown())
			ns.SetupWizard.Go(5)
			expect.equal(w.title:GetText(), "Total RP 3")
			expect.equal(w.stepLabel:GetText(), "STEP 5 OF 6")
			expect.equal(w.trp3Chip.label:GetText(), "Installed, not loaded")
			expect.falsy(w.trp3Cycles.trp3:IsEnabled(), "nothing to connect to")
			expect.truthy(w.trp3Note:GetText():find("Nothing is sent before Finish", 1, true))
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
			expect.truthy(w.finishNote:GetText():find("sent to Total RP 3", 1, true))
			expect.falsy(w.choices:GetText():find("Total RP 3:", 1, true), "no Total RP 3 line without the stage")
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

	t:describe("setup wizard v0.8: hierarchy and spacing (SetupWizard.dc.html)", function()
		local function topOf(widget)
			for _, p in ipairs(widget.__points or {}) do
				if p[1] == "TOPLEFT" then return p[#p] end
			end
		end

		t:it("the rail: round 26 px badges, 44 px steps, and a mode eyebrow that never reaches the steps", function()
			local mock, _, ns = start()
			mock.Slash("")
			local w = wizard(ns)
			local L = ns.SetupWizard.LAYOUT
			for _, step in ipairs(w.steps) do
				expect.equal(step:GetHeight(), 44)
				expect.equal(step.badge:GetWidth(), L.badge)
			end
			-- Each mode's eyebrow fits two lines of the rail (Cinzel 13, 16 px lines).
			local eyebrowWidth = L.rail - 48
			for _, text in ipairs({ "FIRST-TIME SETUP", "PREVIEW · TEST MODE", "SIMULATION · PREVIEW ONLY",
				"READ-ONLY · NOTHING SAVED" }) do
				expect.truthy(ns.Style.TextWidth(text, "eyebrow") <= 2 * eyebrowWidth, text)
			end
			expect.truthy(L.top + 26 + 2 * 16 <= L.stepsTop, "two eyebrow lines end above the first step")
			-- Badge states: current gold, done gold-tinted with the check, future edged.
			ns.SetupWizard.Go(3)
			local theme = ns.Style.Current()
			expect.equal(w.steps[3].badgeBg.__color[1], theme.accent[1])
			expect.truthy(w.steps[1].check:IsShown())
			expect.equal(w.steps[5].badgeRing.__color[1], ns.Style.Tones(theme).edgeStrong[1])
		end)

		t:it("the header: Cinzel stage title, a one-line subtitle, a 36 px close", function()
			local mock, _, ns = start()
			mock.Slash("")
			local w = wizard(ns)
			expect.equal(w.close:GetWidth(), 36)
			for _, subtitle in pairs(ns.SetupWizard.SUBTITLES) do
				expect.truthy(ns.Style.TextWidth(subtitle, "body") <= w.subtitle:GetWidth(), subtitle)
			end
			local L = ns.SetupWizard.LAYOUT
			expect.truthy(L.top + 60 + 18 <= L.bodyTop, "subtitle above the body")
		end)

		t:it("Character: fields, hints and errors never overlap, and the stage fits above the footer", function()
			local mock, _, ns = start()
			mock.Slash("")
			ns.SetupWizard.Go(2)
			local L = ns.SetupWizard.LAYOUT
			local name, pronouns = input(ns, "name"), input(ns, "pronouns")
			expect.equal(name:GetHeight(), ns.Style.CONTROL.input)
			-- Row 1: the label 22 above the input, the hint (or error) below; row 2's label after that.
			local hintBottom = -topOf(name) + name:GetHeight() + 4 + 17
			expect.truthy(hintBottom <= -topOf(pronouns) - 22, "row 1's hint ends above row 2's label")
			local summary = input(ns, "summary").anchorRegion
			local errorBottom = -topOf(summary) + summary:GetHeight() + 3 + 17
			local note = wizard(ns).profileNote
			expect.truthy(errorBottom <= -topOf(note), "the long field's error line ends above the note")
			expect.truthy(-topOf(note) + note:GetHeight() <= L.height - L.bodyTop - L.footer - 8, "fits the body")
			-- Hints are one line in their column.
			expect.truthy(ns.Style.TextWidth(name.hint:GetText(), "small") <= name:GetWidth())
		end)

		t:it("footer and cycle labels fit their buttons", function()
			local mock, _, ns = start()
			mock.Slash("")
			local w = wizard(ns)
			local fits = ns.Widgets.LabelFits
			for _, page in ipairs(ns.Onboarding.PAGES) do
				expect.truthy(fits("Next: " .. page.title, w.next:GetWidth(), w.next:GetHeight()))
			end
			expect.truthy(fits("Save choices", w.next:GetWidth(), w.next:GetHeight()))
			expect.truthy(fits(w.discard:GetText(), w.discard:GetWidth(), w.discard:GetHeight()))
			expect.truthy(fits(w.later:GetText(), w.later:GetWidth(), w.later:GetHeight()))
			for _, b in ipairs(w.cycles) do
				for _, v in ipairs(b.spec.values) do
					-- Room is kept on the right for the chevron.
					expect.truthy(fits(v[2], b:GetWidth() - 24, b:GetHeight(), "choice"), v[2])
				end
				expect.truthy(b.chevron:GetText() ~= "")
			end
			expect.truthy(fits(w.importStory:GetText(), w.importStory:GetWidth(), w.importStory:GetHeight()))
		end)
	end)
end
