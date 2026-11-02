-- L1/L2: story import (#23, #16). The pasted or Total RP 3 text is kept
-- verbatim; pieces are only suggestions until the player approves them.
-- Mocked client: proves the rules and wiring, not the in-game look.
local Loader = require("support.loader")
local Boot = require("support.boot")
local Fake = require("fakes.trp3_341")

local CHAR = "Testchar-TestRealm"

-- A long multi-paragraph biography with the awkward parts a real paste has:
-- CRLF and LF line breaks, blank lines, UTF-8, a WoW colour code, an escaped
-- pipe, braces, quotes and trailing spaces.
local BIO = "Aelin was born in Lordaeron, the youngest of three.\r\n"
	.. "She grew up near the |cffff0000Thandol Span|r, where her father kept the toll.\r\n\r\n"
	.. "She believes the Light answers deeds, not prayers. She fears deep water.\n"
	.. "\n\"Never again,\" she said || and meant it {not a tag}.\n"
	.. "Caf\195\169 au lait \226\128\148 her one indulgence\226\128\166  \n"

return function(t, expect)
	local ns = Loader.Core()
	local Schema, StoryImport, Sources, Facts = ns.Schema, ns.StoryImport, ns.Sources, ns.Facts

	local function fresh()
		return Schema.NewCharacter(1)
	end

	local function reload(char)
		return Schema.NormalizeCharacter(ns.Util.DeepCopy(char))
	end

	t:describe("story import: verbatim source (L1)", function()
		t:it("stores a long multi-paragraph story byte for byte and keeps it through a reload", function()
			local c = fresh()
			local version, status = StoryImport.Capture(c, "paste", BIO, nil, 10)
			expect.equal(status, "stored")
			expect.equal(version.text, BIO)
			local again = reload(reload(c))
			expect.equal(Sources.Current(again).text, BIO, "identical after normalising twice (reload, relog)")
			expect.equal(Sources.Current(again).hash, Schema.SourceHash(BIO))
		end)

		t:it("refuses empty or over-long text and changes nothing", function()
			local c = fresh()
			expect.falsy(StoryImport.Capture(c, "paste", "", nil, 1))
			expect.falsy(StoryImport.Capture(c, "paste", "   \n  ", nil, 1))
			local huge = string.rep("a", Schema.FOUNDATION.bioBytes + 1)
			local v, why = StoryImport.Capture(c, "paste", huge, nil, 1)
			expect.falsy(v)
			expect.truthy(why:find("never shortened", 1, true))
			expect.equal(#c.sources.versions, 0)
			expect.falsy(StoryImport.Capture(c, "written", "x", nil, 1), "only paste and trp3 come from the wizard")
		end)

		t:it("keeps a story exactly at the size limit", function()
			local c = fresh()
			local text = string.rep("Word. ", math.floor(Schema.FOUNDATION.bioBytes / 6))
			text = text .. string.rep("x", Schema.FOUNDATION.bioBytes - #text)
			expect.equal(#text, Schema.FOUNDATION.bioBytes)
			local v = StoryImport.Capture(c, "paste", text, nil, 1)
			expect.equal(v.text, text)
		end)
	end)

	t:describe("story import: splitting (L1)", function()
		t:it("splits into sentences with their place in the story, quoting the player's words", function()
			local pieces = StoryImport.Pieces(BIO, "paste", "sentence")
			expect.equal(pieces[1].text, "Aelin was born in Lordaeron, the youngest of three.")
			expect.equal(pieces[1].ref, "p1 s1")
			expect.equal(pieces[3].ref, "p3 s1")
			expect.equal(pieces[4].text, "She fears deep water.")
			expect.equal(pieces[4].ref, "p3 s2")
			for _, piece in ipairs(pieces) do
				expect.truthy(#piece.text <= StoryImport.PIECE_BYTES)
			end
			expect.equal(StoryImport.RefText("p3 s2"), "Paragraph 3, sentence 2")
			expect.equal(StoryImport.RefText("p2 part 1/3"), "Paragraph 2 (part 1 of 3)")
		end)

		t:it("by paragraph keeps each paragraph whole, and cuts over-long ones at word boundaries", function()
			local long = string.rep("the long road north ", 40) -- 800 bytes, no full stop
			local pieces = StoryImport.Pieces("Short one.\n\n" .. long, "paste", "paragraph")
			expect.equal(pieces[1].text, "Short one.")
			expect.equal(pieces[1].ref, "p1")
			expect.equal(#pieces, 4, "800 bytes in parts of at most 300")
			local joined = {}
			for i = 2, #pieces do
				expect.truthy(#pieces[i].text <= StoryImport.PIECE_BYTES)
				expect.truthy(pieces[i].ref:find("part " .. (i - 1) .. "/3", 1, true))
				expect.falsy(pieces[i].text:find("^%s"), "no part starts with a space")
				joined[#joined + 1] = pieces[i].text
			end
			expect.equal(table.concat(joined, " "), ns.Util.Trim(long), "nothing lost or reworded")
		end)

		t:it("never cuts inside a UTF-8 character, even with no spaces", function()
			local text = string.rep("\195\169", 400) -- 800 bytes of é
			for _, part in ipairs(StoryImport.SplitLong(text)) do
				expect.truthy(#part <= StoryImport.PIECE_BYTES)
				expect.truthy(#part % 2 == 0, "whole characters only")
			end
		end)

		t:it("strips Total RP 3 tags for trp3 sources only", function()
			local pieces = StoryImport.Pieces("{h1:c}Title{/h1}{p}Born in {link*https://x*Stormwind}.{/p}", "trp3")
			expect.equal(pieces[1].text, "Title")
			expect.equal(pieces[2].text, "Born in Stormwind.")
			expect.equal(StoryImport.Pieces("{p}Kept{/p}", "paste")[1].text, "{p}Kept{/p}")
		end)

		t:it("handles empty, malformed and markup-only input without errors", function()
			expect.equal(#StoryImport.Pieces("", "paste"), 0)
			expect.equal(#StoryImport.Pieces(nil, "paste"), 0)
			expect.equal(#StoryImport.Pieces("{icon:x:20}{img:y}", "trp3"), 0)
			expect.equal(#StoryImport.Pieces("{{{ unclosed", "trp3"), 1)
			expect.equal(StoryImport.Pieces("a |cffff0000bold|r word. C", "paste")[1].text, "a |cffff0000bold|r word.")
		end)

		t:it("guesses a category from a few words only, and says other when unsure", function()
			expect.equal(StoryImport.GuessCategory("She fears deep water."), "fear")
			expect.equal(StoryImport.GuessCategory("Born in Lordaeron."), "origin")
			expect.equal(StoryImport.GuessCategory("Her brother left."), "relationship")
			expect.equal(StoryImport.GuessCategory("The sky was grey."), "other")
		end)
	end)

	t:describe("story import: review and canon (L1)", function()
		local function imported()
			local c = fresh()
			local v = StoryImport.Capture(c, "paste", BIO, nil, 5)
			local r = StoryImport.Propose(c, v, "sentence", 5)
			return c, v, r
		end

		t:it("proposes private suggestions linked to the source; nothing becomes canon", function()
			local c, v, r = imported()
			expect.equal(r.proposed, r.total)
			expect.equal(#c.facts, 0, "no canon without approval")
			local waiting = StoryImport.Waiting(c)
			expect.equal(#waiting, r.proposed)
			for _, item in ipairs(waiting) do
				expect.equal(item.visibility, "private")
				expect.equal(item.origin, "paste")
				expect.equal(item.sourceId, v.id)
				expect.equal(item.sourceVersion, v.hash)
			end
			expect.equal(Sources.Current(c).text, BIO, "the source is not changed by splitting")
		end)

		t:it("approves into a private fact with full provenance, using the player's edits", function()
			local c, v = imported()
			local item = StoryImport.Waiting(c)[2]
			local fact = StoryImport.Approve(c, item.key, { statement = "Grew up by the Thandol Span.",
				category = "origin" }, 9)
			expect.equal(fact.statement, "Grew up by the Thandol Span.")
			expect.equal(fact.category, "origin")
			expect.equal(fact.visibility, "private", "private unless the player chooses")
			expect.equal(fact.provenance.origin, "paste")
			expect.equal(fact.provenance.sourceId, v.id)
			expect.equal(fact.provenance.ref, "p2 s1")
			expect.equal(fact.provenance.excerpt, "She grew up near the Thandol Span, where her father kept the toll.",
				"the quote, with the colour code removed (the source keeps it)")
			expect.equal(fact.provenance.interpreted, true)
			expect.equal(StoryImport.Counts(c).approved, 1)
			-- And it is a normal fact that survives a reload.
			expect.equal(reload(c).facts[1].provenance.ref, "p2 s1")
		end)

		t:it("refuses an empty edit or an unknown category and changes nothing", function()
			local c = imported()
			local key = StoryImport.Waiting(c)[1].key
			expect.falsy(StoryImport.Approve(c, key, { statement = "   " }, 1))
			expect.falsy(StoryImport.Approve(c, key, { category = "nonsense" }, 1))
			expect.falsy(StoryImport.Approve(c, key, { visibility = "everyone" }, 1))
			local _, why = StoryImport.Approve(c, key, { statement = string.rep("x", 301) }, 1)
			expect.truthy(why:find("at most 300", 1, true), "an over-long edit is refused, never cut")
			expect.equal(#c.facts, 0)
			expect.truthy(ns.Interpretations.Find(c, key))
			expect.falsy(StoryImport.Approve(c, "paste:other:missing", {}, 1))
		end)

		t:it("skipped pieces are never suggested again, and importing again adds no duplicates", function()
			local c, v = imported()
			local items = StoryImport.Waiting(c)
			StoryImport.Skip(c, items[1].key, 2)
			StoryImport.Approve(c, items[2].key, nil, 2)
			local again = StoryImport.Propose(c, v, "sentence", 3)
			expect.equal(again.proposed, 0, "nothing new")
			expect.equal(again.known, again.total)
			expect.equal(#StoryImport.Waiting(c), #items - 2)
			expect.equal(StoryImport.Counts(c).skipped, 1)
			-- An edited story: only the new sentence is suggested.
			local edited = BIO .. "\nLater she joined the Argent Dawn."
			local v2 = StoryImport.Capture(c, "paste", edited, nil, 4)
			local r = StoryImport.Propose(c, v2, "sentence", 4)
			expect.equal(r.proposed, 1)
			local newest = StoryImport.Waiting(c)[#StoryImport.Waiting(c)]
			expect.equal(newest.statement, "Later she joined the Argent Dawn.")
			expect.equal(newest.sourceId, v2.id)
			expect.equal(#Sources.Versions(c), 2, "both versions kept verbatim")
			expect.equal(Sources.Get(c, v.id).text, BIO)
		end)

		t:it("does not suggest what is already a fact the player wrote", function()
			local c = fresh()
			Facts.Add(c, { category = "fear", statement = "She fears deep water" }, nil, 1)
			local v = StoryImport.Capture(c, "paste", "She fears deep water. She hums.", nil, 1)
			local r = StoryImport.Propose(c, v, "sentence", 1)
			expect.equal(r.proposed, 1)
			expect.equal(r.known, 1)
		end)

		t:it("an interrupted review resumes after a reload: waiting pieces and the source are kept", function()
			local c = imported()
			local before = #StoryImport.Waiting(c)
			StoryImport.Approve(c, StoryImport.Waiting(c)[1].key, nil, 3)
			local after = reload(c)
			expect.equal(#StoryImport.Waiting(after), before - 1)
			expect.equal(Sources.Current(after).text, BIO)
			expect.equal(#after.facts, 1)
		end)

		t:it("a full suggestion list loses nothing: the rest is suggested after reviewing", function()
			local c = fresh()
			local lines = {}
			for i = 1, Schema.FOUNDATION.pending + 5 do lines[i] = "Line number " .. i .. "." end
			local v = StoryImport.Capture(c, "paste", table.concat(lines, "\n"), nil, 1)
			local r = StoryImport.Propose(c, v, "sentence", 1)
			expect.equal(r.proposed, Schema.FOUNDATION.pending)
			expect.equal(r.full, 5)
			for _ = 1, 5 do StoryImport.Skip(c, StoryImport.Waiting(c)[1].key, 2) end
			local r2 = StoryImport.Propose(c, v, "sentence", 3)
			expect.equal(r2.proposed, 5)
			expect.equal(r2.full, 0)
		end)
	end)

	t:describe("story import: privacy (L1)", function()
		t:it("waiting and private pieces never reach the public projection or a share export", function()
			local c = fresh()
			local v = StoryImport.Capture(c, "paste", "Secret past. Private thought. Public fact.", nil, 1)
			StoryImport.Propose(c, v, "sentence", 1)
			local w = StoryImport.Waiting(c)
			StoryImport.Approve(c, w[1].key, { visibility = "secret" }, 2)
			StoryImport.Approve(c, StoryImport.Waiting(c)[1].key, nil, 2)
			local share = ns.Transfer.Export(c, "share", {})
			local public = ns.Projection.GetPublic(c)
			expect.equal(#public.facts, 0)
			for _, word in ipairs({ "Secret past", "Private thought", "Public fact" }) do
				expect.falsy(share:find(word, 1, true), word .. " stays out of a share export")
			end
			-- Only an explicit Public approval publishes, and then only the statement.
			StoryImport.Approve(c, StoryImport.Waiting(c)[1].key, { visibility = "public", statement = "Known in town" }, 3)
			share = ns.Transfer.Export(c, "share", {})
			expect.truthy(share:find("Known in town", 1, true))
			expect.falsy(share:find("Public fact", 1, true), "the source quote is not published with it")
			expect.falsy(share:find("Secret past", 1, true))
			-- A personal backup holds everything, the stored story included.
			local backup = ns.Transfer.Decode(ns.Transfer.Export(c, "backup", {}))
			expect.equal(#backup.character.facts, 3)
			expect.equal(#backup.character.sources.versions, 1)
			-- An older backup (no secrets, no biography) left the secret fact and the source out.
			local old = ns.Transfer.Decode(ns.Transfer.Export(c, "backup", { includeSecrets = false,
				includeBiography = false }))
			for _, f in ipairs(old.character.facts) do
				expect.falsy(f.statement:find("Secret past", 1, true))
			end
			expect.equal(#old.character.sources.versions, 0)
		end)

		t:it("v0.10: an approved piece is part of the profile; a waiting one never is", function()
			local c = fresh()
			ns.Publication.Adopt(c, 1)
			local v = StoryImport.Capture(c, "paste", "Raised by the sea. Fears the dark.", nil, 1)
			StoryImport.Propose(c, v, "sentence", 1)
			StoryImport.Approve(c, StoryImport.Waiting(c)[1].key, { statement = "Raised by the sea" }, 2)
			local public = ns.Projection.GetPublic(c)
			expect.equal(#public.facts, 1)
			expect.equal(public.facts[1].statement, "Raised by the sea")
			local plan = ns.Transfer.Decode(ns.Transfer.Export(c, "share", {}))
			expect.equal(#plan.character.facts, 1, "the waiting piece is not a fact")
			expect.equal(#plan.character.interpretations, 0, "suggestions are never shared")
		end)
	end)

	t:describe("story import: Total RP 3 About text (L1, read-only)", function()
		t:it("reads every template's text and leaves the copy unchanged", function()
			local t1 = { v = 2, TE = 1, T1 = { TX = "One.\n\nTwo." } }
			expect.equal(StoryImport.AboutText(t1), "One.\n\nTwo.")
			local t2 = { v = 2, TE = 2, T1 = {}, T2 = { { TX = "Frame one." }, { TX = "" }, { TX = "Frame two." } } }
			expect.equal(StoryImport.AboutText(t2), "Frame one.\n\nFrame two.")
			local t3 = { v = 2, TE = 3, T1 = {}, T3 = { PH = { TX = "Tall." }, PS = { TX = "Kind." }, HI = { TX = "Born." } } }
			expect.equal(StoryImport.AboutText(t3), "Tall.\n\nKind.\n\nBorn.")
			local before = ns.Util.DeepCopy(t3)
			StoryImport.AboutText(t3)
			expect.deepEqual(t3, before)
			expect.falsy(StoryImport.AboutText({ v = 1, TE = 1, T1 = { TX = "  " } }))
			expect.falsy(StoryImport.AboutText(nil))
		end)

		t:it("imports nothing when Dawnward's own section cannot be separated from the player's text", function()
			local core = require("support.loader").Core()
			local real = core.TRP3AboutDoc
			core.TRP3AboutDoc = { Strip = function() return nil, "the section was edited" end }
			local text, reason = core.StoryImport.AboutText({ v = 1, TE = 1, T1 = { TX = "Mine. Dawnward's." } }, {})
			core.TRP3AboutDoc = real
			expect.equal(text, nil, "never the whole text, Dawnward's block included")
			expect.truthy(reason:find("could not be separated", 1, true))
		end)
	end)

	t:describe("story import: the window (L2)", function()
		local function start(opts)
			local mock, env, ns2 = Boot.Start(opts)
			mock.Slash("set name Aelin")
			mock.Slash("")
			return mock, env, ns2
		end

		local function click(b) b:GetScript("OnClick")(b) end

		t:it("opens from Settings > Data, saves the paste verbatim and reviews one piece at a time", function()
			local _, env, ns2 = start()
			ns2.SettingsPanel.OpenPage("data")
			click(ns2.SettingsPanel.panel.importStory)
			local w = ns2.ImportWizard.Frame()
			expect.truthy(ns2.ImportWizard.IsShown())
			expect.equal(w.title:GetText(), "Your story")
			w.edit:SetText(BIO)
			click(w.primary) -- Save and review
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			expect.equal(ns2.Sources.Current(char).text, BIO, "saved exactly as pasted")
			expect.equal(#char.facts, 0, "nothing is canon yet")
			expect.equal(w.title:GetText(), "Review")
			expect.truthy(w.progress:GetText():find("Piece 1 of", 1, true))
			expect.equal(w.excerpt:GetText(), "Aelin was born in Lordaeron, the youngest of three.")
			expect.truthy(w.category:GetText():find("Origin (suggested)", 1, true))
			-- Edit, then approve: a fact, with nothing to classify.
			expect.equal(w.vis, nil, "no visibility chip")
			w.statement:SetText("Born in Lordaeron, youngest of three.")
			click(w.approve)
			expect.equal(#char.facts, 1)
			expect.equal(char.facts[1].statement, "Born in Lordaeron, youngest of three.")
			-- Skip the next; Later moves on without deciding.
			local skipped = w.excerpt:GetText()
			click(w.skip)
			expect.falsy(w.excerpt:GetText() == skipped)
			local waiting = #ns2.StoryImport.Waiting(char)
			click(w.later)
			expect.equal(#ns2.StoryImport.Waiting(char), waiting)
			expect.equal(#char.facts, 1)
		end)

		t:it("approving adds the piece at once, with no visibility question", function()
			local _, env, ns2 = start()
			ns2.ImportWizard.Open({})
			local w = ns2.ImportWizard.Frame()
			w.edit:SetText("She keeps a lantern lit.")
			click(w.primary)
			expect.equal(w.bioVis, nil, "no visibility chip for the saved story")
			click(w.approve)
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			expect.equal(#char.facts, 1)
			expect.falsy(ns2.Widgets.dialog and ns2.Widgets.dialog:IsShown(), "nothing to confirm")
			expect.falsy(w.status:GetText():find("Public", 1, true) or w.status:GetText():find("Private", 1, true))
		end)

		t:it("refuses an over-long paste with its size and saves nothing", function()
			local _, env, ns2 = start()
			ns2.ImportWizard.Open({})
			local w = ns2.ImportWizard.Frame()
			w.edit:SetText(string.rep("a", ns2.Schema.FOUNDATION.bioBytes + 10))
			ns2.ImportWizard.UpdateCount() -- the client fires OnTextChanged; the mock does not
			expect.truthy(w.count:GetText():find("too long by 10 bytes", 1, true))
			expect.falsy(ns2.ImportWizard.Save())
			expect.truthy(w.status:GetText():find("Nothing was cut or stored", 1, true))
			expect.equal(#env.DawnwardChroniclesDB.characters[CHAR].sources.versions, 0)
		end)

		t:it("opens from the setup wizard's Character stage and the Character section", function()
			local mock, _, ns2 = Boot.Start({ wizard = true })
			mock.Slash("")
			ns2.SetupWizard.Go(2)
			local setup = ns2.SetupWizard.Frame()
			click(setup.importStory)
			expect.truthy(ns2.ImportWizard.IsShown())
			ns2.ImportWizard.Close()
			expect.truthy(ns2.SetupWizard.IsShown(), "setup stays open behind it")
			ns2.SetupWizard.Close()
			mock.Slash("")
			ns2.MainWindow.Select("character")
			click(ns2.CharacterView.section.importButton)
			expect.truthy(ns2.ImportWizard.IsShown())
		end)

		t:it("/dawnward biography opens the window and reports what is stored", function()
			local mock, _, ns2 = start()
			mock.Slash("biography")
			expect.truthy(ns2.ImportWizard.IsShown())
			expect.truthy(mock.Slash("biography status"):find("No story stored yet", 1, true))
			local w = ns2.ImportWizard.Frame()
			w.edit:SetText("One. Two.")
			click(w.primary)
			expect.truthy(mock.Slash("biography status"):find("2 waiting, 0 approved, 0 skipped", 1, true))
		end)

		t:it("saves nothing on read-only data", function()
			local mock, env, ns2 = Boot.Start({ savedVariables = { DawnwardChroniclesDB = { schemaVersion = 999 } } })
			mock.Slash("")
			ns2.ImportWizard.Open({})
			local w = ns2.ImportWizard.Frame()
			expect.truthy(w.status:GetText():find("read-only", 1, true))
			w.edit:SetText("Some story.")
			expect.falsy(ns2.ImportWizard.Save())
			expect.equal(env.DawnwardChroniclesDB.schemaVersion, 999)
			expect.falsy(env.DawnwardChroniclesDB.characters)
		end)

		t:it("reads the player's own Total RP 3 About text read-only, without Dawnward's block", function()
			local fake = Fake.new({ about = { v = 4, TE = 1, BK = 1, T1 = { TX = "Raised by the Silver Hand.\n\n"
				.. "Dawnward block" } } })
			local extra = {}
			for k, v in pairs(fake.env) do
				if k ~= "C_AddOns" then extra[k] = v end
			end
			local mock, env, ns2 = Boot.Load({ extra = extra, savedVariables = { DawnwardChroniclesTRP3DB = nil } })
			mock.env.C_AddOns.IsAddOnLoaded = fake.env.C_AddOns.IsAddOnLoaded
			local meta = mock.env.C_AddOns.GetAddOnMetadata
			mock.env.C_AddOns.GetAddOnMetadata = function(name, field)
				return fake.env.C_AddOns.GetAddOnMetadata(name, field) or meta(name, field)
			end
			Boot.Login(mock)
			ns2.SetupWizard.SkipAutoLaunchThisSession(CHAR)
			-- Pretend Dawnward wrote the block (the ledger's exact record of it).
			env.DawnwardChroniclesTRP3DB.profiles[fake.profileId] = { conflicts = {},
				about = { template = 1, block = "\n\nDawnward block" } }
			local before = fake.snapshot()
			ns2.ImportWizard.Open({})
			local w = ns2.ImportWizard.Frame()
			click(w.readTRP3)
			expect.equal(w.edit:GetText(), "Raised by the Silver Hand.")
			expect.deepEqual(fake.snapshot(), before, "Total RP 3 is not changed")
			expect.equal(#fake.events, 0)
			click(w.primary)
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			local source = ns2.Sources.Current(char)
			expect.equal(source.kind, "trp3")
			expect.equal(source.text, "Raised by the Silver Hand.")
			expect.equal(ns2.StoryImport.Waiting(char)[1].origin, "trp3-biography")
			expect.deepEqual(fake.snapshot(), before)
		end)
	end)

	t:describe("story import: the window's v0.8 layout (L2)", function()
		local function start()
			local mock, env, ns2 = Boot.Start()
			mock.Slash("set name Aelin")
			mock.Slash("")
			ns2.ImportWizard.Open({ from = "settings" })
			return mock, env, ns2, ns2.ImportWizard.Frame()
		end
		local function click(b) b:GetScript("OnClick")(b) end
		local function topOf(widget)
			for _, p in ipairs(widget.__points or {}) do
				if p[1] == "TOPLEFT" then return p[#p] end
			end
		end

		t:it("the split choice shows both options, the one in use selected, and a click picks one", function()
			local _, _, ns2, w = start()
			expect.equal(#w.mode.buttons, 2)
			expect.equal(w.mode.selected, ns2.StoryImport.DEFAULT_MODE)
			for _, b in ipairs(w.mode.buttons) do
				expect.truthy(ns2.Widgets.LabelFits(b:GetText(), b:GetWidth(), b:GetHeight(), "segment"), b:GetText())
				if b.segmentId ~= w.modeValue then
					click(b)
					expect.equal(w.modeValue, b.segmentId)
					expect.equal(w.mode.selected, b.segmentId)
				end
			end
		end)

		t:it("both pages fit between the header and the footer, with 36 px controls", function()
			local _, _, ns2, w = start()
			local L = ns2.ImportWizard.LAYOUT
			local body = L.height - L.bodyTop - L.footer
			expect.truthy(-topOf(w.textNote) + w.textNote:GetHeight() <= body, "text page")
			expect.truthy(-topOf(w.reviewNote) + w.reviewNote:GetHeight() <= body, "review page")
			-- The statement's error line ends above the category row.
			local errorBottom = -topOf(w.statement) + w.statement:GetHeight() + 3 + 17
			expect.truthy(errorBottom <= -topOf(w.category), "error line above Category")
			for _, b in ipairs({ w.readTRP3, w.loadSaved, w.approve, w.skip, w.later, w.previous, w.primary,
				w.secondary }) do
				expect.equal(b:GetHeight(), ns2.Style.CONTROL.standard)
			end
			for _, text in ipairs({ "Save and review", "Done", "Review waiting (99)", "Back to text", "Close",
				"Read from Total RP 3", "Load saved story", "Previous" }) do
				local b = (text == "Save and review" or text == "Done") and w.primary or w.secondary
				if text == "Read from Total RP 3" then b = w.readTRP3 end
				if text == "Load saved story" then b = w.loadSaved end
				if text == "Previous" then b = w.previous end
				expect.truthy(ns2.Widgets.LabelFits(text, b:GetWidth(), b:GetHeight()), text)
			end
			expect.equal(w.close:GetWidth(), 36)
		end)

		t:it("v0.10: the two steps sit beside the eyebrow as in the setup rail, and each is a click away", function()
			local _, _, ns2, w = start()
			local I = ns2.ImportWizard
			local L, S = I.LAYOUT, I.STEP
			expect.truthy(ns2.Style.TextWidth("STORY IMPORT · STEP 2 OF 2", "eyebrow") + 16 <= S.x,
				"the eyebrow ends before the steps")
			expect.truthy(L.pad + S.x + 2 * S.width + S.gap <= L.width - L.pad - ns2.Style.CONTROL.icon - 12,
				"the steps end before the close button")
			for i, step in ipairs(w.steps) do
				expect.truthy(ns2.Style.TextWidth(I.STEPS[i].label, "meta") <= step.label:GetWidth(), I.STEPS[i].label)
				expect.equal(step.ring:GetWidth(), S.badge)
			end
			I.Show("text")
			expect.equal(w.steps[1].state, "current")
			expect.equal(w.steps[2].state, "future")
			expect.equal(w.eyebrow:GetText(), "STORY IMPORT · STEP 1 OF 2")
			click(w.steps[2])
			expect.equal(w.page, "review")
			expect.equal(w.steps[1].state, "done")
			expect.truthy(w.steps[1].check:IsShown())
			expect.equal(w.steps[2].state, "current")
			expect.equal(w.eyebrow:GetText(), "STORY IMPORT · STEP 2 OF 2")
			click(w.steps[1])
			expect.equal(w.page, "text")
		end)
	end)
end
