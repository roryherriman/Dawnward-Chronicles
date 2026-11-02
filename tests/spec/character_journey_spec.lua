-- L1/L2: the character journey from setup through sustained play (#13, #19,
-- #21, #27, #32): player-defined axis meanings and locks, rejected arc
-- suggestions, private arcs and goals never published, goal progress from
-- verified events, explicit publishing with a preview, and a backup round
-- trip of every record type with a restore preview, corrupted-data recovery
-- and undo. Mocked client: rules and wiring, not in-game evidence.
local Loader = require("support.loader")
local Boot = require("support.boot")

local CHAR = "Testchar-TestRealm"

local function turnIn(mock, id, title)
	mock.quest = { id = id, title = title, level = 20 }
	mock.Fire("QUEST_COMPLETE")
	mock.Fire("QUEST_TURNED_IN", id, 100, 10)
end

local function click(b) b:GetScript("OnClick")(b) end

return function(t, expect)
	local ns = Loader.WithTRP3()
	local Schema, AxisMeanings, Evolution, Arcs, Goals = ns.Schema, ns.AxisMeanings, ns.Evolution, ns.Arcs, ns.Goals

	local function fresh()
		return Schema.NewCharacter(1)
	end

	local function reload(char)
		return Schema.NormalizeCharacter(ns.Util.DeepCopy(char))
	end

	--- #21 ---------------------------------------------------------------------------------

	t:describe("player-defined axis meanings (#21, L1)", function()
		t:it("renames an axis in the player's words without touching its value, history or TRP3 traits", function()
			local c = fresh()
			ns.Personality.Set(c, "faith", 14, 1)
			c.personality.faith.visibility = "public"
			local plannedBefore = ns.TRP3TraitPlan and ns.TRP3TraitPlan.Desired(ns.Projection.GetPublic(c))
			assert(AxisMeanings.Set(c, "faith", { left = "Trusts no god", right = "Trusts the Ancestors",
				meaning = "Not the Light: the spirits of her clan." }, 2))
			local axis = Schema.PERSONALITY_AXIS_BY_ID.faith
			local left, right, meaning, custom = AxisMeanings.Labels(c, axis)
			expect.equal(left, "Trusts no god")
			expect.equal(right, "Trusts the Ancestors")
			expect.equal(meaning, "Not the Light: the spirits of her clan.")
			expect.truthy(custom)
			expect.equal(c.personality.faith.value, 14)
			expect.equal(axis.left, "Sceptical", "Dawnward's own labels are unchanged")
			if plannedBefore then
				expect.deepEqual(ns.TRP3TraitPlan.Desired(ns.Projection.GetPublic(c)), plannedBefore,
					"the Total RP 3 trait mapping is unchanged")
			end
			-- Private: never in the public projection or a share export.
			local share = ns.Transfer.Export(c, "share", {})
			expect.falsy(share:find("Ancestors", 1, true))
			expect.falsy(ns.Projection.GetPublic(c).axisMeanings)
		end)

		t:it("is reversible: clearing a word brings Dawnward's back; reset removes everything", function()
			local c = fresh()
			AxisMeanings.Set(c, "honour", { left = "Wolf", right = "Oathbound" }, 1)
			AxisMeanings.Set(c, "honour", { left = "" }, 2)
			local left, right = AxisMeanings.Labels(c, Schema.PERSONALITY_AXIS_BY_ID.honour)
			expect.equal(left, "Pragmatic")
			expect.equal(right, "Oathbound")
			AxisMeanings.Reset(c, "honour", 3)
			expect.falsy(AxisMeanings.Get(c, "honour"))
			AxisMeanings.Set(c, "honour", { left = "" }, 4)
			expect.falsy(c.axisMeanings.honour, "an empty entry is not kept")
		end)

		t:it("refuses unknown axes and over-long words, changing nothing", function()
			local c = fresh()
			expect.falsy(AxisMeanings.Set(c, "holiness", { left = "x" }, 1))
			expect.falsy(AxisMeanings.Set(c, "faith", { left = string.rep("x", 40) }, 1))
			expect.falsy(AxisMeanings.Get(c, "faith"))
		end)

		t:it("a locked axis is never proposed a change by story answers; unlocking changes no value", function()
			local c = fresh()
			ns.Personality.Set(c, "compassion", 15, 1)
			AxisMeanings.Set(c, "compassion", { locked = true }, 1)
			local change, why = Evolution.Propose(c, "compassion", -1, "a ruthless answer", 1, 2)
			expect.falsy(change)
			expect.truthy(why:find("locked", 1, true))
			expect.equal(#Evolution.Pending(c), 0)
			expect.truthy(Evolution.Propose(c, "courage", 1, "a bold answer", 1, 2), "other axes still move")
			-- The player can still set it by hand.
			ns.Personality.Set(c, "compassion", 3, 3)
			expect.equal(c.personality.compassion.value, 3)
			AxisMeanings.Set(c, "compassion", { locked = false }, 4)
			expect.equal(c.personality.compassion.value, 3)
			expect.truthy(Evolution.Propose(c, "compassion", 1, "a kind answer", 2, 5))
		end)

		t:it("is cleaned on load: unknown axes and junk dropped, nothing invented", function()
			local raw = fresh()
			raw.axisMeanings = { faith = { left = "|cffff0000Red|r doubt", locked = "yes", extra = 1 },
				nonsense = { left = "x" }, courage = "bad", discipline = {} }
			local c = reload(raw)
			expect.deepEqual(c.axisMeanings, { faith = { left = "Red doubt" } })
			-- Older saved data has none: an empty table, nothing else changes.
			raw.axisMeanings = nil
			expect.deepEqual(reload(raw).axisMeanings, {})
		end)
	end)

	t:describe("player-defined axis meanings in the window (#21, L2)", function()
		t:it("a click on an axis opens a form; saving shows the player's words and the lock", function()
			local mock, env, ns2 = Boot.Start()
			mock.Slash("personality set faith 12")
			mock.Slash("")
			ns2.MainWindow.Select("character")
			local section = ns2.CharacterView.section
			local faithIndex
			for i, axis in ipairs(ns2.Schema.PERSONALITY_AXES) do
				if axis.id == "faith" then faithIndex = i end
			end
			local a = section.personality.axes[faithIndex]
			a:GetScript("OnMouseUp")(a)
			local form = section.form
			expect.truthy(form.IsOpen())
			expect.falsy(section.header:IsShown(), "header actions wait while the form is open")
			local values = { left = "Doubts", right = "Trusts the Ancestors", meaning = "", locked = true }
			local ok = form.spec.onSave(values)
			expect.truthy(ok)
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			expect.deepEqual(char.axisMeanings.faith, { left = "Doubts", right = "Trusts the Ancestors", locked = true })
			expect.equal(char.personality.faith.value, 12)
			local rows = ns2.CharacterView.PersonalityRows(char)
			expect.equal(rows[faithIndex].left, "Doubts")
			expect.equal(rows[faithIndex].right, "Trusts the Ancestors")
			expect.truthy(rows[faithIndex].locked)
			-- And back to Dawnward's words (the form offers it once there is something to reset).
			form:Close()
			a:GetScript("OnMouseUp")(a)
			expect.truthy(section.form.spec.onDelete())
			expect.falsy(char.axisMeanings.faith)
		end)
	end)

	--- #19 / #27 ----------------------------------------------------------------------------

	t:describe("arcs: rejecting a suggestion (#19, L1)", function()
		local function withPattern()
			local c = fresh()
			for i = 1, Arcs.PATTERN do
				c.story.decisions[i] = { id = i, theme = "mercy", at = i, effects = {} }
			end
			c.story.nextId = Arcs.PATTERN + 1
			return c
		end

		t:it("a rejected arc suggestion is removed and its theme is not suggested again", function()
			local c = withPattern()
			local arc = Arcs.SuggestFromPattern(c, 5)
			expect.equal(arc.status, "proposed")
			expect.equal(arc.visibility, "private")
			assert(Arcs.Reject(c, arc.id, 6))
			expect.equal(#c.story.arcs, 0)
			expect.falsy(Arcs.SuggestFromPattern(c, 7), "not suggested again")
			-- The memory survives a reload and a backup.
			expect.falsy(Arcs.SuggestFromPattern(reload(c), 8))
			local plan = ns.Transfer.Decode(ns.Transfer.Export(c, "backup", {}))
			expect.falsy(Arcs.SuggestFromPattern(plan.character, 8))
		end)

		t:it("removing a waiting suggestion counts as rejecting it (the Chronicle's Remove button)", function()
			local c = withPattern()
			local arc = Arcs.SuggestFromPattern(c, 5)
			assert(Arcs.Remove(c, arc.id))
			expect.falsy(Arcs.SuggestFromPattern(c, 7))
		end)

		t:it("only a waiting suggestion can be rejected; the player's own arcs are concluded instead", function()
			local c = withPattern()
			local mine = Arcs.Add(c, { title = "Find my brother" }, "player", 1)
			local _, why = Arcs.Reject(c, mine.id, 2)
			expect.truthy(why:find("only a suggested arc", 1, true))
			local arc = Arcs.SuggestFromPattern(c, 5)
			Arcs.Accept(c, arc.id, 6)
			expect.falsy(Arcs.Reject(c, arc.id, 7))
			expect.equal(#c.story.arcs, 2)
		end)

		t:it("/dawnward arc reject works from chat", function()
			local mock, env = Boot.Start()
			mock.Slash("set name A")
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			for i = 1, Arcs.PATTERN do
				char.story.decisions[i] = { id = 100 + i, theme = "duty", at = i, effects = {} }
			end
			local arc = assert(Arcs.SuggestFromPattern(char, 5))
			expect.truthy(mock.Slash("arc reject " .. arc.id):find("will not be suggested again", 1, true))
			expect.equal(#char.story.arcs, 0)
		end)
	end)

	t:describe("arcs and goals stay private (#19, #27, L1)", function()
		t:it("no arc or goal, whatever its visibility, reaches the public projection, a share export or TRP3", function()
			local c = fresh()
			local secretArc = Arcs.Add(c, { title = "Avenge Hearthglen", visibility = "secret" }, "player", 1)
			local publicArc = Arcs.Add(c, { title = "Become a paladin", visibility = "public" }, "player", 1)
			Arcs.AddTurningPoint(c, publicArc.id, "Knelt at the chapel", nil, 2)
			Goals.Add(c, { title = "Earn my sister's forgiveness", visibility = "private" }, 1)
			Goals.Add(c, { title = "Exalted with Stormwind", visibility = "public" }, 1)
			expect.equal(secretArc.visibility, "secret")
			local public = ns.Projection.GetPublic(c)
			public.trp3Style = "neutral"
			local about = ns.TRP3AboutBlock.Compose(public)
			local share = ns.Transfer.Export(c, "share", {})
			for _, text in ipairs({ "Hearthglen", "paladin", "chapel", "forgiveness", "Exalted" }) do
				expect.falsy(share:find(text, 1, true), text .. " not in a share export")
				expect.falsy(about:find(text, 1, true), text .. " not in the Total RP 3 block")
			end
			expect.falsy(public.story)
			-- A personal backup (v0.10) holds every arc and goal.
			local full = ns.Transfer.Decode(ns.Transfer.Export(c, "backup", {})).character
			expect.equal(#full.story.arcs, 2)
			expect.equal(#full.story.goals, 2)
			-- A backup as older versions made it (no secrets) kept the private ones and left the secret arc out.
			local backup = ns.Transfer.Decode(ns.Transfer.Export(c, "backup", { includeSecrets = false })).character
			local titles = {}
			for _, a in ipairs(backup.story.arcs) do titles[a.title] = true end
			expect.truthy(titles["Become a paladin"])
			expect.falsy(titles["Avenge Hearthglen"])
			expect.equal(#backup.story.goals, 2)
		end)
	end)

	t:describe("goals from verified events (#27, L2)", function()
		t:it("a level objective follows verified level-ups and is never achieved automatically", function()
			local mock, env = Boot.Start()
			mock.Slash("goal add Reach level 12")
			mock.Slash("goal add Never fight again") -- contradictory goals may coexist
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			local goal = char.story.goals[1]
			mock.Slash("goal level " .. goal.id .. " 12")
			local p = Goals.Progress(char, goal)
			expect.equal(p.objective.current, nil, "no signal yet: nothing is assumed")
			mock.Fire("PLAYER_LEVEL_UP", 11)
			expect.equal(Goals.ObjectiveText(Goals.Progress(char, goal)), "level 11/12")
			mock.Fire("PLAYER_LEVEL_UP", 12)
			p = Goals.Progress(char, goal)
			expect.truthy(p.objective.met)
			expect.equal(goal.state, "active", "met is shown; only the player marks it achieved")
			expect.equal(#Goals.Active(char), 2)
			-- A subjective milestone is only ever ticked by the player.
			mock.Slash("goal milestone " .. char.story.goals[2].id .. " Put the sword away")
			expect.falsy(char.story.goals[2].milestones[1].done)
		end)
	end)

	--- #13 ----------------------------------------------------------------------------------

	t:describe("journal entries and the profile (#13, v0.10, L1)", function()
		t:it("a journal note never reaches the published profile; an approved defining moment does", function()
			local c = fresh()
			ns.Publication.Adopt(c, 1)
			local note = ns.Journal.AddNote(c, { title = "The bridge", text = "We held it." }, 2)
			ns.Journal.SetVisibility(c, note.id, "public", 3)
			local draft = ns.Journal.AddStoryDraft(c, { title = "The vow", text = "I swore it." }, 4)
			local public = ns.Projection.GetPublic(c)
			expect.equal(#public.journal, 0, "a note, even one an older version marked Public, and a draft")
			ns.Journal.Approve(c, draft.id, 5)
			ns.Journal.SetImportant(c, draft.id, true, 6)
			public = ns.Projection.GetPublic(c)
			expect.equal(#public.journal, 1)
			expect.equal(public.journal[1].title, "The vow")
		end)
	end)

	--- #32 ----------------------------------------------------------------------------------

	-- A character with every kind of record, built through play and commands.
	local function richCharacter()
		local mock, env, ns2 = Boot.Start()
		mock.Slash("set name Aelin")
		mock.Slash("set summary A |cff00ff00green|r line\nwith a break and \195\169")
		mock.Vis("vis summary public")
		mock.Slash("fact add origin Born in Lordaeron")
		mock.Vis("fact vis 1 public")
		mock.Slash("fact add fear Deep water")
		mock.Vis("fact vis 2 secret")
		mock.Slash("family add sister Ilsa")
		mock.Slash("history add as a child; Saw the Plague")
		mock.Slash("journal add The bridge")
		mock.Slash("personality set faith 12")
		turnIn(mock, 30, "Draft Quest")
		local waiting = env.DawnwardChroniclesDB.characters[CHAR].story.reactions[1]
		assert(waiting, "a story moment is waiting")
		mock.Slash("story " .. waiting.id .. " 1")
		mock.Fire("PLAYER_LEVEL_UP", 7)
		mock.Slash("memory add The night at the bridge")
		mock.Slash("arc add Find my brother")
		local char = env.DawnwardChroniclesDB.characters[CHAR]
		mock.Slash("arc turn " .. char.story.arcs[#char.story.arcs].id .. " A letter came")
		mock.Slash("goal add Reach level 20")
		mock.Slash("goal milestone " .. char.story.goals[1].id .. " Leave Elwynn")
		mock.Slash("stance add The Light; Faithful; Doubting")
		mock.Slash("person add npc Marshal Dughan; mentor")
		AxisMeanings.Set(char, "faith", { left = "Doubting", right = "Ancestral", locked = true }, 5)
		ns2.StoryImport.Import(ns2.ctx, "paste", "First line.\nSecond line.\nThird line.", nil, "sentence")
		ns2.StoryImport.Approve(char, ns2.StoryImport.Waiting(char)[1].key, nil, 6)
		ns2.StoryImport.Skip(char, ns2.StoryImport.Waiting(char)[1].key, 6)
		return mock, env, ns2, char
	end

	-- Everything except timestamps of the write and the full event records
	-- (a backup carries event keys, not events).
	local function comparable(ns2, char)
		local c = ns2.Schema.NormalizeCharacter(ns2.Util.DeepCopy(char))
		c.createdAt, c.updatedAt = nil, nil
		c.story.events = nil
		return c
	end

	t:describe("backup round trip of every record type (#32, L2)", function()
		t:it("a full backup restores every record, privacy state and v0.7 field exactly", function()
			local _, _, ns2, char = richCharacter()
			for _, list in ipairs({ "memories", "arcs", "goals", "identity", "people", "decisions", "changes" }) do
				expect.truthy(#char.story[list] > 0, list .. " present")
			end
			expect.equal(#char.facts, 3)
			expect.truthy(#char.interpretations > 0 and next(char.interpretationKeys) ~= nil)
			local text = ns2.Transfer.Export(char, "backup", { includeSecrets = true, includeBiography = true,
				characterKey = CHAR })
			-- Into a fresh installation of the same character.
			local mock2, env2, ns3 = Boot.Start()
			local ok = ns3.Commands.StageImport(ns3.ctx, text)
			expect.truthy(ok)
			mock2.Slash("import confirm")
			local restored = env2.DawnwardChroniclesDB.characters[CHAR]
			expect.deepEqual(comparable(ns3, restored), comparable(ns2, char))
			expect.equal(ns3.Sources.Current(restored).text, "First line.\nSecond line.\nThird line.")
			expect.deepEqual(restored.axisMeanings.faith, { left = "Doubting", right = "Ancestral", locked = true })
			-- Importing the same backup again duplicates nothing.
			ns3.Commands.StageImport(ns3.ctx, text)
			mock2.Slash("import confirm")
			expect.deepEqual(comparable(ns3, env2.DawnwardChroniclesDB.characters[CHAR]), comparable(ns2, char))
		end)

		t:it("an older backup without secrets restores the rest and keeps the current secrets", function()
			local mock, env, ns2, char = richCharacter()
			local text = ns2.Transfer.Export(char, "backup", { characterKey = CHAR, includeSecrets = false })
			expect.falsy(text:find("Deep water", 1, true))
			mock.Slash("fact add belief Added after the backup")
			ns2.Commands.StageImport(ns2.ctx, text)
			mock.Slash("import confirm")
			local now = env.DawnwardChroniclesDB.characters[CHAR]
			local statements = {}
			for _, f in ipairs(now.facts) do statements[f.statement] = f.visibility end
			expect.equal(statements["Deep water"], "secret", "the current secret is carried over")
			expect.falsy(statements["Added after the backup"], "a restore is a restore")
			expect.equal(statements["Born in Lordaeron"], "public", "privacy states kept")
			expect.deepEqual(now.axisMeanings.faith, char.axisMeanings.faith)
		end)

		t:it("shows a restore preview per record type, warns about another character, and can be undone", function()
			local mock, env, ns2, char = richCharacter()
			local text = ns2.Transfer.Export(char, "backup", { includeSecrets = true, characterKey = "Other-Realm" })
			mock.Slash("memory add Something new")
			local before = ns2.Util.DeepCopy(env.DawnwardChroniclesDB.characters[CHAR])
			mock.chat = {}
			local ok, message = ns2.Commands.StageImport(ns2.ctx, text)
			expect.truthy(ok)
			expect.truthy(message:find("made from Other-Realm, not " .. CHAR, 1, true))
			local printed = table.concat(mock.chat, "\n")
			expect.truthy(printed:find("What changes:", 1, true))
			local memories = #before.story.memories
			expect.truthy(printed:find("memories: " .. memories .. " now -> " .. (memories - 1) .. " after", 1, true),
				printed)
			expect.truthy(printed:find("arcs: 1 now -> 1 after (same count)", 1, true))
			-- The preview changed nothing.
			expect.deepEqual(env.DawnwardChroniclesDB.characters[CHAR], before)
			mock.Slash("import confirm")
			expect.equal(#env.DawnwardChroniclesDB.characters[CHAR].story.memories, memories - 1)
			mock.Slash("import undo")
			expect.deepEqual(env.DawnwardChroniclesDB.characters[CHAR], before, "undo brings back the exact profile")
		end)

		t:it("a backup of the same character has no owner warning; an older backup without owner has none", function()
			local plan = { owner = CHAR }
			expect.falsy(ns.Transfer.OwnerWarning(plan, CHAR))
			expect.falsy(ns.Transfer.OwnerWarning({}, CHAR))
			expect.truthy(ns.Transfer.OwnerWarning({ owner = "B-R" }, CHAR))
			-- Share exports never name the owner.
			local c = fresh()
			local share = ns.Transfer.Export(c, "share", { characterKey = CHAR })
			expect.falsy(share:find("Testchar", 1, true))
		end)

		t:it("a failed import leaves saved data untouched", function()
			local mock, env, ns2, char = richCharacter()
			local text = ns2.Transfer.Export(char, "backup", {})
			local before = ns2.Util.DeepCopy(env.DawnwardChroniclesDB)
			for _, bad in ipairs({ text:sub(1, #text - 20), text:gsub("Aelin", "Aelyn"), "!DWC1!B!zz!{",
				"!DWC1!S" .. text:sub(8), "" }) do
				local ok = ns2.Commands.StageImport(ns2.ctx, bad)
				expect.falsy(ok)
				mock.Slash("import confirm")
				expect.deepEqual(env.DawnwardChroniclesDB, before)
			end
		end)
	end)

	t:describe("recovery from corrupted saved data (#32, L1/L2)", function()
		t:it("a corrupted part of one character is repaired without losing the rest or other characters", function()
			local good = Schema.NewCharacter(1)
			ns.Character.SetField(good, "name", "Intact", 1)
			ns.Facts.Add(good, { category = "origin", statement = "Kept" }, nil, 1)
			local broken = Schema.NewCharacter(1)
			ns.Character.SetField(broken, "name", "Damaged", 1)
			ns.Facts.Add(broken, { category = "belief", statement = "Survives" }, nil, 1)
			broken.story = "corrupted"
			broken.facts[2] = "junk"
			broken.journal = 42
			broken.axisMeanings = { faith = 7 }
			broken.sources = { current = 9, versions = { { kind = "paste", text = 123 } } }
			local saved = { DawnwardChroniclesDB = { schemaVersion = Schema.VERSION, characters = {
				["Other-Realm"] = ns.Util.DeepCopy(good), [CHAR] = broken }, importBackups = {}, ui = {} } }
			local mock, env = Boot.Start({ savedVariables = saved })
			local out = mock.Slash("status")
			expect.falsy(out:find("read-only", 1, true), "still writable")
			local db = env.DawnwardChroniclesDB
			expect.equal(db.characters["Other-Realm"].fields.name.value, "Intact")
			expect.equal(db.characters["Other-Realm"].facts[1].statement, "Kept")
			local c = db.characters[CHAR]
			expect.equal(c.fields.name.value, "Damaged")
			expect.equal(#c.facts, 1)
			expect.equal(c.facts[1].statement, "Survives")
			expect.equal(type(c.story), "table")
			expect.deepEqual(c.journal, {})
			expect.deepEqual(c.axisMeanings, {})
			expect.equal(#c.sources.versions, 0)
			mock.Slash("fact add trait Still works")
			expect.equal(#db.characters[CHAR].facts, 2)
		end)

		t:it("fuzz: random damage to any part of a character never raises and never touches another character", function()
			local _, _, _, rich = richCharacter()
			local other = Schema.NormalizeCharacter(ns.Util.DeepCopy(rich))
			local junk = { "x", 0, -1, 1.5, true, false, {}, { 1, 2, 3 }, { a = { b = "c" } }, string.rep("z", 5000) }
			local keys = {}
			for k in pairs(rich) do keys[#keys + 1] = k end
			table.sort(keys)
			local seed = 12345
			local function rand(n)
				seed = (seed * 1103515245 + 12345) % 2147483648
				return seed % n + 1
			end
			for _ = 1, 300 do
				local victim = ns.Util.DeepCopy(rich)
				for _ = 1, rand(3) do
					local key = keys[rand(#keys)]
					local target = victim[key]
					if type(target) == "table" and rand(2) == 1 then
						local inner = {}
						for k in pairs(target) do inner[#inner + 1] = k end
						if #inner > 0 then
							table.sort(inner, function(a, b) return tostring(a) < tostring(b) end)
							target[inner[rand(#inner)]] = junk[rand(#junk)]
						end
					else
						victim[key] = junk[rand(#junk)]
					end
				end
				local db = { schemaVersion = Schema.VERSION, characters = { A = victim, B = ns.Util.DeepCopy(other) },
					importBackups = {}, ui = {} }
				local ok, result = pcall(Schema.NormalizeDatabase, db, {})
				expect.truthy(ok, tostring(result))
				expect.truthy(result.characters.B, "the other character is kept")
				expect.deepEqual(result.characters.B, Schema.NormalizeCharacter(other), "and unchanged")
			end
		end)
	end)

	t:describe("setup to sustained play (L2)", function()
		t:it("a new character imports a story during setup, finishes setup, then plays on", function()
			local mock, env, ns2 = Boot.Start({ wizard = true })
			mock.Slash("")
			ns2.SetupWizard.Go(2)
			click(ns2.SetupWizard.Frame().importStory)
			local w = ns2.ImportWizard.Frame()
			w.edit:SetText("Raised on a farm near Goldshire.\n\nShe wants to see the sea.")
			click(w.primary)
			click(w.approve)
			click(w.skip)
			ns2.ImportWizard.Close()
			ns2.SetupWizard.Go(#ns2.Onboarding.PAGES)
			ns2.SetupWizard.Finish()
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			expect.truthy(char.wizard.done)
			expect.equal(#char.facts, 1)
			expect.equal(char.facts[1].category, "origin")
			expect.equal(char.facts[1].visibility, "private")
			turnIn(mock, 31, "First Steps")
			expect.truthy(#char.story.events > 0, "tracking continues")
		end)
	end)
end
