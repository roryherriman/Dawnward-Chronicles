-- L2 (v0.10.3): the owner's level-6 character (tests/fixtures/kyssarra_level6.lua)
-- loads unchanged and stays unchanged across a reload and new events.
-- Additive only: the six old suggestions stay pending with their stored
-- words (never approved, never rewritten), approved, edited and disputed
-- memories are kept, nothing is recorded twice, and the Total RP 3 profile
-- and ledger (fake: tests/fakes/trp3_341.lua) do not change.
local Loader = require("support.loader")
local Fake = require("fakes.trp3_341")
local Kyssarra = require("fixtures.kyssarra_level6")
local Boot = require("support.boot")

return function(t, expect)
	local KEY = Kyssarra.KEY

	local function world()
		local ns = Loader.WithTRP3()
		local fake = Fake.new({})
		local store = ns.Store.new(ns.Schema.NewDatabase(), ns.Schema.NewDatabase())
		local clock = Kyssarra.T0 + 5000
		local deps = {
			env = fake.env, ledger = ns.TRP3Ledger.New(), store = store, characterKey = KEY,
			now = function() clock = clock + 1; return clock end,
			inCombat = function() return false end,
		}
		local w = { ns = ns, fake = fake, deps = deps, store = store }
		function w.now() return clock end
		function w.later(s) clock = clock + s end
		return w
	end

	local function load(ns, raw)
		return ns.Schema.NormalizeCharacter(ns.Util.DeepCopy(raw))
	end

	local function byId(list)
		local out = {}
		for _, r in ipairs(list) do out[r.id] = r end
		return out
	end

	-- Everything but what new play may add.
	local function snapshotOld(ns, char)
		local s = ns.Util.DeepCopy(char)
		return { memories = s.story.memories, decisions = s.story.decisions, changes = s.story.changes,
			arcs = s.story.arcs, goals = s.story.goals, people = s.story.people, identity = s.story.identity,
			journal = s.journal, glance = s.glance, trp3status = s.trp3status, fields = s.fields,
			personality = s.personality }
	end

	t:describe("migration: Kyssarra Dawnward at level 6 (v0.10.3)", function()
		t:it("loads unchanged: six suggestions still pending in their stored words, every other record kept", function()
			local w = world()
			local ns = w.ns
			local raw = Kyssarra.Character(ns)
			local loaded = load(ns, raw)
			expect.deepEqual(load(ns, loaded), loaded, "loading is stable")
			local m = byId(loaded.story.memories)
			for _, s in ipairs(Kyssarra.SUGGESTED) do
				expect.equal(m[s.id].status, "proposed", "not auto-approved: " .. s.title)
				expect.equal(m[s.id].provenance, "suggested")
				expect.equal(m[s.id].text, s.text, "stored text is not rewritten")
				expect.equal(m[s.id].kind, nil, "an old suggestion is not reclassified")
				expect.equal(m[s.id].visibility, "private")
			end
			expect.equal(m[42].text, "Kyssarra Dawnward relished the freedom their strength brings.")
			expect.equal(m[50].status, "established")
			expect.equal(m[50].visibility, "public", "an approved public memory stays public")
			expect.equal(m[52].provenance, "player")
			expect.equal(m[52].text, "I did not run. I want to remember that.", "her edit is kept")
			expect.equal(m[53].status, "disputed", "a rejected suggestion stays rejected")
			expect.equal(#loaded.story.memories, 10, "nothing added, nothing removed")
			expect.equal(#loaded.story.events, #raw.story.events)
			expect.equal(#loaded.story.decisions, 6)
			expect.equal(loaded.story.changes[2].status, "pending")
			expect.equal(#loaded.journal, #raw.journal)
			local drafts = 0
			for _, e in ipairs(loaded.journal) do
				if e.kind == "story" and e.status == "draft" then drafts = drafts + 1 end
			end
			expect.equal(drafts, 5, "story drafts stay drafts")
			expect.deepEqual(loaded.glance, raw.glance)
			expect.deepEqual(loaded.trp3status, raw.trp3status)
			expect.equal(loaded.story.arcs[1].turningPoints[1].note, raw.story.arcs[1].turningPoints[1].note)
			expect.equal(loaded.story.goals[1].title, "Earn a place in the Order")
			expect.equal(loaded.story.people[1].name, "Brother Sammuel")
			expect.equal(loaded.story.identity[1].conviction, "Unsure of the nobility")
			expect.equal(loaded.profileSuggestions, nil)
		end)

		t:it("shows no duplicate: events the old suggestions tell are not recorded again", function()
			local w = world()
			local ns = w.ns
			local loaded = load(ns, Kyssarra.Character(ns))
			local keys = {}
			for _, e in ipairs(ns.Memories.Recorded(loaded)) do keys[#keys + 1] = e.key end
			expect.deepEqual(keys, {}, "every notable event here already has its suggestion, linked")
			expect.equal(ns.Memories.Basis(loaded, byId(loaded.story.memories)[42]),
				"Recorded: Kyssarra Dawnward reached level 5 in Elwynn Forest.", "the suggestion shows its support")
			expect.equal(#ns.Memories.Suggestions(loaded), 6)
		end)

		t:it("stays unchanged across a reload and new events; new text uses her pronouns", function()
			local w = world()
			local ns = w.ns
			local loaded = load(ns, Kyssarra.Character(ns))
			local before = snapshotOld(ns, loaded)
			-- Playing on: a routine level, a new zone, level 10 and its question.
			assert(ns.GameEvents.Record(loaded, "levelup", { level = 7, zone = "Westfall" }, w.now()))
			ns.Actions.ObserveLocation({ store = { real = { characters = { [KEY] = loaded } }, realReadOnly = false },
				characterKey = KEY, now = w.now }, { zone = "Westfall", level = 8 })
			expect.equal(#loaded.story.memories, 10, "routine play adds no memory and no suggestion")
			w.later(100)
			loaded.story.pacing.playByCategory, loaded.story.pacing.lastByCategory = {}, {}
			local ten = assert(ns.GameEvents.Record(loaded, "levelup", { level = 10, zone = "Westfall" }, w.now()))
			expect.equal(ns.Memories.Recorded(loaded)[1], ten, "recorded at once, no approval")
			expect.equal(ns.Memories.RecordedText(loaded, ten), "Kyssarra Dawnward reached level 10 in Westfall.")
			local reaction = assert(ns.Reactions.Consider(loaded, ten, w.now(), w.now()))
			local view = ns.Reactions.Present(loaded, reaction)
			expect.equal(view.question, "Kyssarra Dawnward has grown stronger (level 10). What does that strength mean "
				.. "to her?")
			local result = assert(ns.Decisions.Decide(loaded, reaction.id, { optionId = "protect" }, w.now()))
			expect.equal(result.memory.text, "Kyssarra Dawnward felt her new strength as a responsibility to others.")
			expect.equal(result.memory.status, "established")
			expect.equal(result.reflection.text, "Others may come to rely on her.")
			expect.equal(result.reflection.status, "proposed")
			-- Reload: the same, and nothing old changed.
			local reloaded = load(ns, loaded)
			expect.deepEqual(load(ns, reloaded), reloaded)
			local after = snapshotOld(ns, reloaded)
			for i = 1, #before.memories do
				expect.deepEqual(after.memories[i], before.memories[i], "memory #" .. before.memories[i].id)
			end
			for _, k in ipairs({ "arcs", "goals", "people", "identity", "glance", "trp3status", "fields",
				"personality" }) do
				expect.deepEqual(after[k], before[k], k)
			end
			for i = 1, #before.decisions do expect.deepEqual(after.decisions[i], before.decisions[i]) end
			for i = 1, #before.changes do expect.deepEqual(after.changes[i], before.changes[i]) end
			for i = 1, #before.journal do expect.deepEqual(after.journal[i], before.journal[i]) end
			expect.equal(#ns.Memories.Suggestions(reloaded), 7, "the six old ones, and one new reflection")
		end)

		t:it("leaves the Total RP 3 profile and ledger as they were", function()
			local w = world()
			local ns = w.ns
			local loaded = load(ns, Kyssarra.Character(ns))
			w.store.real.characters[KEY] = loaded
			assert(ns.TRP3Sync.SetOptIn(w.deps, "glance", true))
			assert(ns.TRP3Sync.SetPolicy(w.deps, "currently", "dawnward"))
			ns.TRP3Sync.Run(w.deps)
			local published = ns.Util.DeepCopy(w.fake.snapshot())
			local ledger = ns.TRP3Ledger.Normalize(ns.Util.DeepCopy(w.deps.ledger))
			local setters = #w.fake.setterLog
			-- New play: a level 10 answer (an established answer and a reflection).
			loaded.story.pacing.playByCategory, loaded.story.pacing.lastByCategory = {}, {}
			local ten = assert(ns.GameEvents.Record(loaded, "levelup", { level = 10, zone = "Westfall" }, w.now()))
			local reaction = assert(ns.Reactions.Consider(loaded, ten, w.now(), w.now()))
			assert(ns.Decisions.Decide(loaded, reaction.id, { optionId = "protect" }, w.now()))
			ns.TRP3Sync.Run(w.deps)
			expect.deepEqual(w.fake.snapshot(), published, "nothing published")
			expect.equal(#w.fake.setterLog, setters, "no TRP3 setter called")
			local now = ns.TRP3Ledger.Normalize(ns.Util.DeepCopy(w.deps.ledger))
			expect.deepEqual(now.profiles, ledger.profiles, "ownership and backups unchanged")
		end)

		t:it("Memories screen: All, Established and Suggestions; the six stay pending; Later and Dismiss", function()
			local mock, env, ns = Boot.Start()
			mock.Slash("")
			local CHAR = ns.ctx.characterKey
			local loaded = load(ns, Kyssarra.Character(ns))
			env.DawnwardChroniclesDB.characters[CHAR] = loaded
			ns.MainWindow.Select("chronicle")
			local section = ns.ChronicleView.section
			ns.MainWindow.Refresh()
			local function click(b) b:GetScript("OnClick")(b) end
			local function filter(id)
				for _, b in ipairs(section.filter.buttons) do
					if b.segmentId == id then click(b) end
				end
			end
			expect.truthy(section.filter.buttons[1]:IsShown(), "the filter shows on Memories")
			expect.equal(#section.items, 10)
			filter("suggested")
			expect.equal(#section.items, 6)
			for _, item in ipairs(section.items) do expect.equal(item.status, "proposed") end
			filter("established")
			expect.equal(#section.items, 3)
			filter("suggested")
			local row = section.rows[1]
			local first = row.record
			local later
			for _, b in ipairs(row.actions) do
				if b:IsShown() and b:GetText() == "Later" then later = b end
			end
			click(later)
			expect.equal(first.laterAt ~= nil, true)
			expect.equal(section.items[6], first, "put off: last")
			expect.equal(section.contents[6].chip[1], "Suggested · later")
			local dismiss
			for _, b in ipairs(section.rows[1].actions) do
				if b:IsShown() and b:GetText() == "Dismiss" then dismiss = b end
			end
			local gone = section.rows[1].record
			click(dismiss)
			mock.AcceptPopup()
			expect.equal(ns.Memories.Find(loaded, gone.id), nil)
			expect.equal(#section.items, 5)
			-- A level 10 now: recorded on All, with nothing to click.
			assert(ns.GameEvents.Record(loaded, "levelup", { level = 10, zone = "Westfall" }, Kyssarra.T0 + 9000))
			filter("all")
			local recorded = section.items[1]
			expect.truthy(recorded.recorded)
			expect.equal(section.contents[1].chip[1], "Recorded")
			expect.equal(section.contents[1].text, "Kyssarra Dawnward reached level 10 in Westfall.")
			local left = ns.ChronicleView.Actions("memories", recorded, {})
			expect.deepEqual(left, {}, "nothing to accept, edit or remove")
			-- Switching tabs hides the filter.
			for _, b in ipairs(section.tabButtons) do
				if b.tabId == "arcs" then click(b) end
			end
			expect.falsy(section.filter.buttons[1]:IsShown())
		end)

		t:it("the filter sits between the search and the count, at any window scale", function()
			local mock, env, ns = Boot.Start()
			mock.Slash("")
			local CHAR = ns.ctx.characterKey
			env.DawnwardChroniclesDB.characters[CHAR] = load(ns, Kyssarra.Character(ns))
			for i = 1, 290 do
				ns.Memories.Add(env.DawnwardChroniclesDB.characters[CHAR], { title = "M" .. i }, "player", i)
			end
			ns.MainWindow.Select("chronicle")
			local section = ns.ChronicleView.section
			local L = ns.ChronicleView.LAYOUT
			local function snapshot()
				ns.MainWindow.Refresh()
				local buttons = section.filter.buttons
				local x = buttons[1].__points[1][2]
				local right = x
				for i, b in ipairs(buttons) do
					right = right + b:GetWidth() + (i > 1 and 2 or 0)
					expect.truthy(ns.Widgets.LabelFits(b:GetText(), b:GetWidth(), b:GetHeight()), b:GetText())
				end
				local countText = section.count:GetText()
				local countLeft = L.width - ns.Style.TextWidth(countText, "meta")
				return { x = x, right = right, countLeft = countLeft, search = section.search:GetWidth(), text = countText }
			end
			local base = snapshot()
			expect.equal(base.text, "Newest first · 300 memories")
			expect.truthy(base.x >= L.newWidth + 10 + base.search, "after the search")
			expect.truthy(base.right + 8 <= base.countLeft, "before the count")
			local frame = ns.MainWindow.GetFrame()
			for _, scale in ipairs({ 0.7, 1.4 }) do
				frame:SetScale(scale)
				expect.deepEqual(snapshot(), base, "scale " .. scale)
			end
		end)
	end)
end
