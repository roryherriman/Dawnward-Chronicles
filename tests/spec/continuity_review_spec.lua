-- L1/L2: continuity review (#42): new checks, examine, correct (the
-- record's own edit form), explain (a stored note), preserve (the existing
-- answers) and undo. Nothing is ever rewritten for the player.
local Loader = require("support.loader")
local Boot = require("support.boot")

local CHAR = "Testchar-TestRealm"

local function click(button)
	button:GetScript("OnClick")(button)
end

return function(t, expect)
	local function setup()
		local ns = Loader.Core()
		local char = ns.Schema.NewCharacter(1)
		char.fields.name = { value = "Lirael", visibility = "public" }
		return ns, char
	end

	local function kinds(ns, char)
		local out = {}
		for _, f in ipairs(ns.Continuity.Findings(char)) do out[f.key:match("^[^:]+")] = f end
		return out
	end

	t:describe("continuity checks (#42)", function()
		t:it("a public stance that says the opposite of a public fact about the same subject", function()
			local ns, char = setup()
			local stance = assert(ns.Identity.Add(char, { subject = "The Argent Dawn", persona = "Stands with them",
				visibility = "public" }, 1))
			ns.Facts.Add(char, { category = "belief", statement = "Never trusted the Argent Dawn", subject = "The Argent Dawn",
				visibility = "public" }, nil, 2)
			local f = kinds(ns, char).publicfact
			expect.truthy(f, "flagged")
			expect.truthy(f.message:find("Stands with them", 1, true))
			-- Private on either side, or marked deliberate: nothing to flag.
			stance.visibility = "private"
			expect.falsy(kinds(ns, char).publicfact)
			stance.visibility, stance.deliberate = "public", true
			expect.falsy(kinds(ns, char).publicfact)
			-- Said the same way round: no finding.
			stance.deliberate = nil
			char.facts[1].statement = "Trusts the Argent Dawn"
			expect.falsy(kinds(ns, char).publicfact)
		end)

		t:it("a goal marked achieved with open steps, or before the game shows its objective", function()
			local ns, char = setup()
			local g = assert(ns.Goals.Add(char, { title = "Reach 20", objective = { kind = "level", target = 20 } }, 1))
			ns.Goals.AddMilestone(char, g.id, "Train with the master", 2)
			ns.GameEvents.Record(char, "levelup", { level = 15 }, 3)
			expect.falsy(kinds(ns, char).goalopen, "an active goal with open steps is fine")
			ns.Goals.SetState(char, g.id, "achieved", 4)
			local k = kinds(ns, char)
			expect.truthy(k.goalopen and k.goalopen.message:find("Train with the master", 1, true))
			expect.truthy(k.goalunmet and k.goalunmet.message:find("level 15/20", 1, true))
			ns.Goals.SetMilestone(char, g.id, 1, true, 5)
			expect.falsy(kinds(ns, char).goalopen, "every step done")
			expect.equal(g.state, "achieved", "the goal is never changed by a check")
		end)

		t:it("a memory dated before the event it remembers, only when both dates are known", function()
			local ns, char = setup()
			local e = assert(ns.GameEvents.Record(char, "quest", { questId = 7, title = "The Fallen", zone = "Duskwood" }, 500))
			local m = assert(ns.Memories.Add(char, { title = "Before it happened", links = { events = { e.key } } },
				"player", 100))
			expect.truthy(kinds(ns, char).memorydate)
			m.at = 0 -- unknown date (backstory): nothing is claimed
			expect.falsy(kinds(ns, char).memorydate)
			m.at = 600
			expect.falsy(kinds(ns, char).memorydate)
		end)

		t:it("stays cheap on full lists (the Review tab counts findings on every refresh)", function()
			local ns, char = setup()
			local keys = {}
			for i = 1, 300 do
				local e = ns.GameEvents.Record(char, "quest", { questId = i, title = "Q" .. i, zone = "Zone" .. i % 30 }, i)
				if e then keys[#keys + 1] = e.key end
			end
			for i = 1, 300 do
				local links = {}
				for j = 1, 20 do links[j] = keys[(i + j) % #keys + 1] end
				ns.Memories.Add(char, { title = "M" .. i, links = { events = links } }, "player", 1000 + i)
			end
			for i = 1, 60 do
				ns.Identity.Add(char, { subject = "S" .. i, persona = "P" .. i, conviction = "C" .. i,
					visibility = "public" }, 1)
				ns.Facts.Add(char, { category = "belief", statement = "Not S" .. i, subject = "S" .. i,
					visibility = "public" }, nil, 1)
			end
			local started = os.clock()
			for _ = 1, 10 do ns.Continuity.Findings(char) end
			local elapsed = os.clock() - started
			expect.truthy(elapsed < 2, string.format("10 full reviews took %.2fs", elapsed))
		end)

		t:it("a record replaced by one that no longer exists", function()
			local ns, char = setup()
			local a = assert(ns.Memories.Add(char, { title = "Old" }, "player", 1))
			local b = assert(ns.Memories.Add(char, { title = "New" }, "player", 2))
			assert(ns.Memories.Supersede(char, a.id, b.id, 3))
			expect.falsy(kinds(ns, char).replaced)
			assert(ns.Memories.Remove(char, b.id))
			expect.truthy(kinds(ns, char).replaced)
		end)
	end)

	t:describe("examine, explain, preserve and undo (#42)", function()
		t:it("examines both records side by side with dates and provenance, changing nothing", function()
			local ns, char = setup()
			ns.Memories.Add(char, { title = "The fire" }, "player", 100)
			local s = assert(ns.Memories.Add(char, { title = "The fire", text = "Suggested" }, "suggested", 200))
			assert(ns.Memories.Accept(char, s.id, 250))
			local before = ns.Util.DeepCopy(char)
			local finding = kinds(ns, char).duplicate
			local view = assert(ns.Continuity.Examine(char, finding.key))
			expect.equal(#view.sides, 2)
			expect.equal(view.sides[1].at, 100)
			expect.equal(view.sides[1].provenance, "Your words")
			expect.equal(view.sides[2].at, 200)
			expect.equal(view.sides[2].provenance, "Suggested by Dawnward")
			expect.equal(view.sides[2].updatedAt, 250)
			expect.truthy(view.sides[1].editable and view.sides[2].editable)
			expect.deepEqual(char, before, "examining is read-only")
			-- A stance's two sides; a personality value and a trait fact.
			ns.Identity.Add(char, { subject = "The Horde", persona = "Proud", conviction = "Wants to leave" }, 300)
			view = ns.Continuity.Examine(char, kinds(ns, char).persona.key)
			expect.equal(view.sides[1].text, "Proud")
			expect.equal(view.sides[2].text, "Wants to leave")
			expect.equal(view.sides[2].visibility, "private")
			char.personality.courage = { value = 2, visibility = "private", updatedAt = 400 }
			ns.Facts.Add(char, { category = "trait", statement = "Bold beyond reason" }, nil, 410)
			view = ns.Continuity.Examine(char, kinds(ns, char).axis.key)
			expect.equal(view.sides[1].list, "personality")
			expect.equal(view.sides[2].text, "Bold beyond reason")
			expect.equal(view.sides[2].at, 410)
			expect.falsy(view.sides[2].editable, "facts are edited in the Character section")
		end)

		t:it("explains with a stored note; an explanation needs words", function()
			local ns, char = setup()
			ns.Identity.Add(char, { subject = "The Horde", persona = "Proud", conviction = "Wants to leave" }, 1)
			local key = ns.Continuity.Findings(char)[1].key
			local _, err = ns.Continuity.Review(char, key, "explained", "  ", 2)
			expect.truthy(err:find("explanation", 1, true))
			local before = ns.Util.DeepCopy(char.story.identity)
			local review = assert(ns.Continuity.Review(char, key, "explained", "She says it to keep her family safe", 3))
			expect.equal(review.note, "She says it to keep her family safe")
			expect.truthy(review.message:find("Wants to leave", 1, true), "the finding's wording is kept")
			expect.deepEqual(char.story.identity, before, "explaining changes no record")
			expect.equal(#ns.Continuity.Findings(char), 0)
			local answered = ns.Continuity.Answered(char)
			expect.equal(answered[1].review.choice, "explained")
			-- Kept across a reload.
			local clean = ns.Schema.NormalizeCharacter(char)
			expect.equal(clean.story.reviews[1].note, "She says it to keep her family safe")
			expect.equal(clean.story.reviews[1].choice, "explained")
		end)

		t:it("undo takes an answer back and restores what a secret answer changed", function()
			local ns, char = setup()
			local stance = assert(ns.Identity.Add(char, { subject = "The Horde", persona = "Proud",
				conviction = "Wants to leave" }, 1))
			local key = ns.Continuity.Findings(char)[1].key
			assert(ns.Continuity.Review(char, key, "secret", nil, 2))
			expect.equal(stance.convictionVisibility, "secret")
			expect.equal(stance.deliberate, true)
			assert(ns.Continuity.Undo(char, key))
			expect.equal(stance.convictionVisibility, "private")
			expect.equal(stance.deliberate, nil)
			expect.equal(ns.Continuity.Findings(char)[1].key, key, "the finding is open again")
			expect.equal(#char.story.reviews, 0)
			-- A later change by the player is kept.
			assert(ns.Continuity.Review(char, key, "secret", nil, 3))
			assert(ns.Identity.SetConvictionVisibility(char, stance.id, "public", 4))
			-- (the player made the private side public after answering)
			assert(ns.Continuity.Undo(char, key))
			expect.equal(stance.convictionVisibility, "public", "the player's own later change is kept")
			-- Every other answer is undone the same way.
			for _, choice in ipairs({ "growth", "unreliable", "correction", "ignore" }) do
				assert(ns.Continuity.Review(char, key, choice, nil, 5))
				expect.equal(#ns.Continuity.Findings(char), 0, choice)
				assert(ns.Continuity.Undo(char, key))
				expect.equal(#ns.Continuity.Findings(char), 1, choice)
			end
			local _, err = ns.Continuity.Undo(char, key)
			expect.truthy(err:find("no answer", 1, true))
		end)

		t:it("cleans saved answers additively: message and undo kept, junk dropped", function()
			local ns, char = setup()
			char.story.reviews = {
				{ key = "persona:1:abc", choice = "secret", at = 5, message = "About x", undo = { identity = 1,
					convictionVisibility = "private", deliberate = false } },
				{ key = "persona:2:abc", choice = "growth", at = 6, undo = { identity = "x" } },
				{ key = "persona:3:abc", choice = "made up" },
			}
			local clean = ns.Schema.NormalizeCharacter(char).story.reviews
			expect.equal(#clean, 2)
			expect.deepEqual(clean[1].undo, { identity = 1, convictionVisibility = "private", deliberate = false })
			expect.equal(clean[1].message, "About x")
			expect.equal(clean[2].undo, nil)
		end)

		t:it("examine, explain, answered and undo work from chat", function()
			local mock, env = Boot.Start()
			mock.Slash("set name Zanjin")
			mock.Slash("stance add Orgrimmar; Loyal to the Warchief; Doubts the Warchief")
			local examined = mock.Slash("continuity examine 1")
			expect.truthy(examined:find("Stance, in public", 1, true), examined)
			expect.truthy(examined:find("Doubts the Warchief", 1, true))
			expect.truthy(mock.Slash("continuity explain 1"):find("explanation", 1, true), "an explanation needs words")
			expect.truthy(mock.Slash("continuity explain 1 Old loyalties die hard"):find("kept", 1, true))
			local story = env.DawnwardChroniclesDB.characters[CHAR].story
			expect.equal(story.reviews[1].note, "Old loyalties die hard")
			expect.truthy(mock.Slash("continuity answered"):find("Old loyalties die hard", 1, true))
			expect.truthy(mock.Slash("continuity undo 1"):find("taken back", 1, true))
			expect.equal(#story.reviews, 0)
			expect.truthy(mock.Slash("continuity"):find("Doubts the Warchief", 1, true))
		end)
	end)

	t:describe("Review tab: examine, correct, explain, undo (L2)", function()
		local function start()
			local mock, env, ns = Boot.Start()
			mock.Slash("set name Lirael")
			mock.Slash("")
			ns.MainWindow.Select("chronicle")
			local section = ns.ChronicleView.section
			for _, b in ipairs(section.tabButtons) do
				if b.tabId == "review" then click(b) end
			end
			return mock, env, ns, section
		end

		local function button(row, text)
			for _, b in ipairs(row.buttons) do
				if b:IsShown() and b:GetText() == text then return b end
			end
			error("no button " .. text)
		end

		t:it("examines a duplicate side by side, corrects one in its own form, and returns to the list", function()
			local _, env, ns, section = start()
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			ns.Memories.Add(char, { title = "The fire", text = "First" }, "player", 100)
			ns.Memories.Add(char, { title = "The fire", text = "Second" }, "player", 200)
			ns.MainWindow.Refresh()
			local row = section.rows[1]
			expect.truthy(row.examine:IsShown(), "a finding offers Examine")
			expect.equal(row.examine.variant, "default")
			expect.truthy(button(row, "Secret").tooltipText, "the answers keep their tooltips")
			click(row.examine)
			expect.equal(section.reviewMode, "examine")
			expect.equal(section.rows[1].chip.label:GetText(), "A · Memory")
			expect.equal(section.rows[1].text:GetText(), "First")
			expect.equal(section.rows[2].text:GetText(), "Second")
			expect.falsy(section.rows[1].examine:IsShown())
			expect.equal(section.count:GetText(), "Examining one finding")
			expect.equal(section.new:GetText(), "<  All findings")
			-- The finding itself, with its answers, and the Explain card.
			expect.truthy(button(section.rows[3], "Growth"))
			expect.truthy(button(section.rows[4], "Explain..."))
			-- Correct: the record's own edit form; the player rewrites it.
			click(button(section.rows[2], "Edit"))
			local form = section.form
			expect.truthy(form:IsOpen())
			expect.equal(form.spec.title, "Edit memory")
			for _, r in ipairs(form.rows) do
				if r.field and r.field.key == "title" then r.line:SetText("The fire, years later") end
			end
			click(form.save)
			expect.equal(char.story.memories[2].title, "The fire, years later")
			expect.equal(char.story.memories[1].title, "The fire", "the other record is untouched")
			ns.MainWindow.Refresh()
			expect.equal(section.reviewMode, "open", "nothing left to examine: back to the list")
			expect.truthy(section.empty:IsShown())
		end)

		t:it("explains through a form, lists the answer, and undoes it", function()
			local mock, env, ns, section = start()
			mock.Slash("stance add The Cenarion Circle; Loyal; Doubts its leaders")
			ns.MainWindow.Refresh()
			local story = env.DawnwardChroniclesDB.characters[CHAR].story
			expect.equal(section.new:GetText(), "Answered  0")
			expect.falsy(section.new:IsEnabled())
			click(section.rows[1].examine)
			click(button(section.rows[4], "Explain..."))
			local form = section.form
			expect.equal(form.spec.title, "Explain this finding")
			click(form.save)
			expect.truthy(form:IsOpen(), "an explanation needs words")
			for _, r in ipairs(form.rows) do
				if r.field and r.field.key == "note" then r.area.edit:SetText("A test of their faith") end
			end
			click(form.save)
			expect.equal(story.reviews[1].choice, "explained")
			expect.equal(story.reviews[1].note, "A test of their faith")
			expect.equal(story.identity[1].conviction, "Doubts its leaders", "canon is untouched")
			ns.MainWindow.Refresh()
			expect.equal(section.reviewMode, "open")
			-- Answered: the answer with its note, and Undo answer.
			expect.equal(section.new:GetText(), "Answered  1")
			click(section.new)
			expect.equal(section.reviewMode, "answered")
			local row = section.rows[1]
			expect.equal(row.chip.label:GetText(), "Explained")
			expect.equal(row.meta:GetText(), "Your note: A test of their faith")
			local undo = button(row, "Undo answer")
			expect.equal(undo.variant, "default")
			expect.truthy(undo.tooltipText:find("back", 1, true))
			click(undo)
			expect.equal(#story.reviews, 0)
			click(section.new)
			expect.equal(section.reviewMode, "open")
			expect.truthy(section.rows[1]:IsShown(), "the finding is open again")
		end)

		t:it("keeps the Examine button clear of the card's chip", function()
			local _, _, ns = Boot.Start()
			local CV = ns.ChronicleView
			local L = CV.LAYOUT
			local chip = CV.CardRects({}).chip
			local er = CV.EXAMINE_RECT
			local x = L.cardWidth - L.cardPad - er.w
			expect.truthy(chip.x + chip.w <= x, "no horizontal overlap")
			expect.truthy(er.y + er.h <= CV.CardRects({ meta = true }).meta.y, "above the meta line")
		end)
	end)
end
