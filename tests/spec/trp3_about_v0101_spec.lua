-- L1/L2 (v0.10.1): the About page as the character's public narrative.
-- The overview, the whole biography (word for word, the player's own
-- chapter headings), and only the optional sections the player wrote; no
-- facts, family lists, beliefs, stances or chronicle notes; no sentence
-- twice; body text in a readable colour instead of Total RP 3's paragraph
-- gold (RegisterAbout.lua setupHTMLFonts sets only h1-h3 to white); only
-- verified icons and backgrounds; a clean, conflict-free upgrade of what
-- v0.10.0 wrote. Against the TRP3 3.4.1 fake (mocked; not in-game evidence).
local Loader = require("support.loader")
local Fake = require("fakes.trp3_341")

local V010 = require("fixtures.about_v010")
local STAND_IN = require("fixtures.backstory_paragraphs")

local BIO = "# The fall\nShe was fourteen when the walls fell. She carried the ledger.\n\nShe hid in the mill.\n"
	.. "# After\nA new oath in Southshore."

-- The text a reader sees (Dawnward's colour tags removed).
local function visible(text)
	return (text:gsub("{col:%x%x%x%x%x%x}", ""):gsub("{/col}", ""))
end

local function count(haystack, needle)
	local n, at = 0, 1
	while true do
		local s, e = haystack:find(needle, at, true)
		if not s then return n end
		n, at = n + 1, e + 1
	end
end

-- The character v0.10.0's fixture was rendered from (fixtures/about_v010.lua).
local function fixtureCharacter(ns, char)
	ns.Character.SetField(char, "summary", "A quiet paladin who keeps a book of names. She was fourteen when the "
		.. "walls fell.", 1)
	ns.Character.SetField(char, "appearance", "Grey eyes, a burn scar on one hand.", 1)
	ns.Character.SetField(char, "motivation", "No village forgotten.", 1)
	ns.Character.AddItem(char, "family", { relation = "brother", name = "Tomas", status = "living" }, 1)
	ns.Facts.Add(char, { category = "belief", statement = "The Light never left" })
	ns.Facts.Add(char, { category = "origin", statement = "Born above the river fields" })
	ns.Facts.Add(char, { category = "relationship", statement = "Sworn to Captain Rhea" })
	ns.Sources.Capture(char, "paste", BIO, nil, 2)
end

-- Words that must never reach the About page (Dawnward's own records).
local RECORDS = { "Tomas", "Brother:", "Origin:", "Relationship:", "Born above the river fields",
	"Sworn to Captain Rhea", "The Light never left", "Chronicle notes", "Beliefs and motivations", "Family",
	"Where they stand", "Loyal to the crown", "Defining experiences" }

return function(t, expect)
	local KEY = "Testchar-TestRealm"

	local function profileChar(ns)
		local char = ns.Schema.NewCharacter(1)
		ns.Publication.Adopt(char, 1)
		return char
	end

	local function publicOf(ns, char, prefs)
		local public = ns.Projection.GetPublic(char)
		for k, v in pairs(prefs or {}) do public[k] = v end
		return public
	end

	local function world(fakeOpts)
		local ns = Loader.WithTRP3()
		local fake = Fake.new(fakeOpts or {})
		local store = ns.Store.new(ns.Schema.NewDatabase(), ns.Schema.NewDatabase())
		local clock = 1000
		local deps = {
			env = fake.env, ledger = ns.TRP3Ledger.New(), store = store, characterKey = KEY,
			now = function() clock = clock + 1; return clock end,
			inCombat = function() return false end,
		}
		local w = { ns = ns, fake = fake, deps = deps, Sync = ns.TRP3Sync }
		function w.char()
			local char = assert(store:EnsureCharacter(KEY, 1))
			if not w.adopted then
				ns.Publication.Adopt(char, 1)
				w.adopted = true
			end
			return char
		end
		function w.connect() assert(w.Sync.Authorize(deps, { about = "dawnward" })) end
		function w.run() return w.Sync.RunFeature(deps, "about") end
		function w.about() return fake.profile.player.about end
		function w.record() return deps.ledger.profiles[fake.profileId].about end
		function w.prefs() return w.char().story.prefs end
		return w
	end

	t:describe("About v0.10.1: deduplication (L1, pure)", function()
		local Doc = Loader.WithTRP3().TRP3AboutDoc

		t:it("compares sentences without case, spacing, punctuation or TRP3 tags", function()
			expect.equal(Doc.Normalize("  She   WAS fourteen,\twhen {col:ff0000}the{/col} walls fell!  "),
				"she was fourteen when the walls fell")
			expect.equal(Doc.Normalize("{h2}Don\226\128\153t \226\128\148 ever{/h2}"), "don t ever")
			expect.equal(Doc.Normalize("{quietly}"), "quietly", "braces that are not TRP3 tags keep their word")
			local s = Doc.Sentences("One. Two! \"Three?\" Four\nFive.\n\nSix")
			expect.equal(table.concat(s), "One. Two! \"Three?\" Four\nFive.\n\nSix", "nothing lost")
			expect.equal(#s, 6)
		end)

		t:it("drops only sentences already said, keeps the rest as written and keeps paragraph breaks", function()
			local c = Doc.NewCoverage()
			Doc.Cover(c, "She was fourteen when the walls fell. She hid in the mill.")
			local text, dropped = Doc.Dedupe("A quiet paladin.  she was FOURTEEN when the walls fell!\n\nShe hid. "
				.. "Born in the mill town.", c)
			expect.equal(text, "A quiet paladin.\n\nShe hid. Born in the mill town.")
			expect.equal(dropped, 1, "a short sentence inside a longer one is not a repeat")
			expect.equal(select(1, Doc.Dedupe("She hid in the mill.", c)), "", "nothing left: nothing shown")
			expect.deepEqual({ Doc.Dedupe("Untouched.", c) }, { "Untouched.", 0 })
		end)

		t:it("treats a long sentence found inside the biography as already said", function()
			local c = Doc.NewCoverage()
			Doc.Cover(c, "When the grain carts stopped, she left Hillsbrad quietly.")
			expect.equal(select(1, Doc.Dedupe("When the grain carts stopped, she left.", c)), "")
			expect.equal(select(1, Doc.Dedupe("She left.", c)), "She left.", "too short to judge: kept")
		end)
	end)

	t:describe("About v0.10.1: what the page says (L1)", function()
		t:it("publishes the narrative, never Dawnward's records, and never a sentence twice", function()
			local ns = Loader.WithTRP3()
			local char = profileChar(ns)
			fixtureCharacter(ns, char)
			local stance = ns.Identity.Add(char, { subject = "the crown", persona = "Loyal to the crown" }, 1)
			stance.status = "established"
			ns.Character.AddItem(char, "history", { when = "Year 20", text = "Took the oath" }, 1)
			ns.Personality.Set(char, "courage", 18, 1)
			for template = 1, 3 do
				local r = ns.TRP3AboutDoc.Render(ns.TRP3AboutDoc.Build(publicOf(ns, char)), template)
				local all = visible(table.concat({ r.T1 or "", r.PH or "", r.PS or "", r.HI or "" }, "\n"))
				for _, f in ipairs(r.frames or {}) do all = all .. "\n" .. visible(f.TX) end
				for _, word in ipairs(RECORDS) do
					expect.falsy(all:find(word, 1, true), "T" .. template .. ": not on the About page: " .. word)
				end
				expect.falsy(all:find("Took the oath", 1, true), "history entries stay in Dawnward")
				expect.equal(count(all, "She was fourteen when the walls fell."), 1,
					"T" .. template .. ": the overview's repeat of the biography is left out")
				expect.truthy(all:find("A quiet paladin who keeps a book of names.", 1, true), "the rest of the overview")
				expect.truthy(all:find("Grey eyes, a burn scar on one hand.", 1, true))
				expect.falsy(all:find("No village forgotten", 1, true), "motivation is off by default")
			end
		end)

		t:it("never repeats a sentence anywhere on the page, whatever repeats it", function()
			local ns = Loader.WithTRP3()
			local char = profileChar(ns)
			fixtureCharacter(ns, char)
			ns.Character.SetField(char, "appearance", "Grey eyes. She hid in the mill.", 1)
			ns.Character.SetField(char, "motivation", "A quiet paladin who keeps a book of names. No village forgotten.", 1)
			local entry = ns.Journal.AddStoryDraft(char, { title = "The oath", text = "A new oath in Southshore. "
				.. "She swore it at dawn." }, 1)
			ns.Journal.Approve(char, entry.id, 1)
			ns.Journal.SetImportant(char, entry.id, true, 1)
			local doc = ns.TRP3AboutDoc.Build(publicOf(ns, char, { trp3Sections = { on = { motivation = true,
				developments = true } } }))
			local text = visible(ns.TRP3AboutDoc.Render(doc, 1).T1)
			local seen = {}
			for line in (text .. "\n"):gmatch("([^\n]*)\n") do
				if not line:find("^{h%d") then
					for _, sentence in ipairs(ns.TRP3AboutDoc.Sentences(line)) do
						local n = ns.TRP3AboutDoc.Normalize(sentence)
						if n ~= "" then
							expect.falsy(seen[n], "said twice: " .. sentence)
							seen[n] = true
						end
					end
				end
			end
			expect.truthy(text:find("{h2}Motivation{/h2}\nNo village forgotten.", 1, true), text)
			expect.truthy(text:find("{h2}New developments{/h2}\n{h3}The oath{/h3}\nShe swore it at dawn.", 1, true), text)
			expect.truthy(text:find("{h2}Appearance{/h2}\nGrey eyes.", 1, true), text)
		end)

		t:it("leaves out an overview that only repeats the biography's opening, and never shows an empty section", function()
			local ns = Loader.WithTRP3()
			local char = profileChar(ns)
			ns.Sources.Capture(char, "paste", "Born in a mill town. Raised by a midwife.\n\nLater years.", nil, 1)
			ns.Character.SetField(char, "summary", "born in a mill town -- raised by a midwife", 1)
			local doc = ns.TRP3AboutDoc.Build(publicOf(ns, char))
			expect.equal(#doc, 1)
			expect.equal(doc[1].id, "biography")
			local tx = ns.TRP3AboutDoc.Render(doc, 1).T1
			for heading, after in tx:gmatch("({h2}.-{/h2})\n([^\n]*)") do
				expect.truthy(after:match("%S"), heading .. " has text under it")
			end
		end)

		t:it("only writes words the player wrote", function()
			local ns = Loader.WithTRP3()
			local char = profileChar(ns)
			fixtureCharacter(ns, char)
			local sources = { char.fields.summary.value, char.fields.appearance.value, BIO }
			local tx = visible(ns.TRP3AboutDoc.Render(ns.TRP3AboutDoc.Build(publicOf(ns, char)), 1).T1)
			for line in (tx .. "\n"):gmatch("([^\n]*)\n") do
				local heading = line:match("^{h%d}(.-){/h%d}$")
				if heading then
					local known = heading == "Character overview" or heading == "Biography" or heading == "Appearance"
						or BIO:find("# " .. heading, 1, true)
					expect.truthy(known, "a heading is a section title or the player's own: " .. heading)
				elseif line:match("%S") then
					local found = false
					for _, src in ipairs(sources) do found = found or src:find(line, 1, true) ~= nil end
					expect.truthy(found, "invented text: " .. line)
				end
			end
		end)

		t:it("follows the player's order, titles and choices, and the overview alone in summary mode", function()
			local ns = Loader.WithTRP3()
			local char = profileChar(ns)
			fixtureCharacter(ns, char)
			local prefs = { trp3Sections = { order = { "appearance", "biography" }, titles = { biography = "Her {story}" },
				on = { overview = false } } }
			local doc = ns.TRP3AboutDoc.Build(publicOf(ns, char, prefs))
			local ids = {}
			for i, s in ipairs(doc) do ids[i] = s.id end
			expect.deepEqual(ids, { "appearance", "biography" })
			local tx = ns.TRP3AboutDoc.Render(doc, 1).T1
			expect.truthy(tx:find("{h2}Her (story){/h2}", 1, true), "a title is escaped, never markup")
			doc = ns.TRP3AboutDoc.Build(publicOf(ns, char, { trp3About = "summary" }))
			expect.equal(#doc, 1)
			expect.equal(doc[1].id, "overview")
			-- A clean round trip through the saved data drops what is not valid.
			local clean = ns.StorySchema.CleanAboutSections({ order = { "biography", "nope", "biography" },
				on = { motivation = true, bogus = true }, titles = { overview = string.rep("x", 200) },
				icons = { overview = "Not a token!", biography = "INV_Misc_Book_09" }, backgrounds = { overview = 99 } })
			expect.deepEqual(clean.order, { "biography" })
			expect.deepEqual(clean.on, { motivation = true })
			expect.equal(#clean.titles.overview, ns.StorySchema.TRP3_SECTION_TITLE_MAX)
			expect.deepEqual(clean.icons, { biography = "inv_misc_book_09" })
			expect.deepEqual(clean.backgrounds, {})
			expect.equal(ns.StorySchema.CleanAboutSections({ on = { nope = true } }), nil, "nothing valid: defaults")
		end)

		t:it("puts only a personality description in PS, never anything generated from axes or traits", function()
			local ns = Loader.WithTRP3()
			local char = profileChar(ns)
			fixtureCharacter(ns, char)
			ns.Personality.Set(char, "courage", 20, 1)
			ns.Facts.Add(char, { category = "trait", statement = "Stubborn" })
			local r = ns.TRP3AboutDoc.Render(ns.TRP3AboutDoc.Build(publicOf(ns, char)), 3)
			expect.equal(r.PS, "", "Dawnward has no personality description: PS gets nothing")
			expect.equal(visible(r.PH), "Grey eyes, a burn scar on one hand.", "PH: the appearance only")
			expect.falsy(visible(r.HI):find("Grey eyes", 1, true), "never the appearance twice")
			-- A personality description (a field a later version may add) goes to PS alone.
			local public = publicOf(ns, char)
			public.fields.personality = { value = "Patient, then suddenly not.", visibility = "public" }
			r = ns.TRP3AboutDoc.Render(ns.TRP3AboutDoc.Build(public), 3)
			expect.equal(visible(r.PS), "Patient, then suddenly not.")
		end)
	end)

	t:describe("About v0.10.1: how it looks in Total RP 3 (L1)", function()
		t:it("colours every body line in each style, so no paragraph shows in TRP3's gold", function()
			local ns = Loader.WithTRP3()
			local P = ns.TRP3Presentation
			local char = profileChar(ns)
			fixtureCharacter(ns, char)
			for styleId, style in pairs(P.STYLES) do
				for template = 1, 3 do
					local r = ns.TRP3AboutDoc.Render(ns.TRP3AboutDoc.Build(publicOf(ns, char, { trp3Style = styleId })),
						template)
					local texts = { r.T1, r.PH, r.PS, r.HI }
					for _, f in ipairs(r.frames or {}) do texts[#texts + 1] = f.TX end
					for _, text in pairs(texts) do
						for _, item in ipairs(P.DisplayItems(text)) do
							if item.kind == "p" then
								for line in (item.text .. "\n"):gmatch("([^\n]*)\n") do
									expect.equal(line:sub(1, 10), "|cff" .. style.body, styleId .. " T" .. template
										.. ": a body line in the style's colour: " .. line)
									expect.equal(line:sub(-2), "|r")
								end
							else
								expect.truthy(item.kind == "h2" or item.kind == "h3", item.kind)
							end
						end
					end
				end
				expect.falsy(style.body:find("^ff[cd]"), styleId .. ": the body colour is not a gold")
			end
		end)

		t:it("keeps the body colour after the player's own colour tag ends", function()
			local P = Loader.WithTRP3().TRP3Presentation
			expect.equal(P.Body(P.Get("neutral"), "A {col:ff0000}red{/col} word.\n  \nNext."),
				"{col:e8e0d0}A {col:ff0000}red{/col}{col:e8e0d0} word.{/col}\n  \n{col:e8e0d0}Next.{/col}")
		end)

		t:it("uses only verified icons and backgrounds, whatever the saved choice says", function()
			local ns = Loader.WithTRP3()
			local P = ns.TRP3Presentation
			local char = profileChar(ns)
			fixtureCharacter(ns, char)
			local prefs = { trp3Style = "silverhand", trp3Sections = { icons = { overview = "ability_rogue_unknown",
				biography = "inv_scroll_02" }, backgrounds = { overview = 2, biography = 4 } } }
			local frames = ns.TRP3AboutDoc.Render(ns.TRP3AboutDoc.Build(publicOf(ns, char, prefs)), 2).frames
			expect.equal(frames[1].IC, "inv_misc_book_09", "an unverified icon falls back to the section's own")
			expect.equal(frames[1].BK, 3, "an unverified background falls back to the style's (Marble)")
			expect.equal(frames[2].IC, "inv_scroll_02")
			expect.equal(frames[2].BK, 4)
			for _, f in ipairs(frames) do
				expect.truthy(P.ICONS[f.IC], f.IC)
				expect.truthy(P.BACKGROUNDS[f.BK], tostring(f.BK))
			end
			for _, c in ipairs(P.ICON_CHOICES) do expect.truthy(P.ICONS[c.id], c.id) end
			for _, c in ipairs(P.BACKGROUND_CHOICES) do expect.truthy(P.BACKGROUNDS[c.id], tostring(c.id)) end
		end)

		t:it("keeps a long biography in one frame, or splits it only at the player's own headings", function()
			local ns = Loader.WithTRP3()
			local Doc = ns.TRP3AboutDoc
			local char = profileChar(ns)
			local chapters = {}
			for i = 1, 4 do
				chapters[i] = "# Chapter " .. i .. "\n" .. string.rep("Line " .. i .. " of the long road home. ", 60)
			end
			ns.Sources.Capture(char, "paste", table.concat(chapters, "\n"), nil, 1)
			local doc = Doc.Build(publicOf(ns, char))
			expect.equal(#Doc.Render(doc, 2).frames, 1, "under the limit: one frame")
			local saved = Doc.MAX_BYTES
			Doc.MAX_BYTES = 6000
			local frames = Doc.Render(doc, 2).frames
			Doc.MAX_BYTES = saved
			expect.truthy(#frames >= 2, "split")
			for i, f in ipairs(frames) do
				expect.truthy(#f.TX <= 6000, "frame " .. i .. " fits")
				if i > 1 then expect.truthy(f.TX:find("^{h3}Chapter %d{/h3}"), "a part starts at a chapter heading") end
			end
			local all = {}
			for _, f in ipairs(frames) do all[#all + 1] = visible(f.TX) end
			all = table.concat(all, "\n")
			for i = 1, 4 do
				expect.equal(count(all, "Line " .. i .. " of the long road home."), 60, "no line lost or repeated")
			end
		end)
	end)

	t:describe("About v0.10.1: sync (L2)", function()
		t:it("writes once, then never again while nothing changes, in every template and style", function()
			for _, styleId in ipairs({ "neutral", "silverhand", "arcane" }) do
				for _, about in ipairs({ { v = 2, TE = 1, T1 = { TX = "Mine." } },
					{ v = 2, TE = 2, T2 = { { TX = "Mine", IC = "INV_Misc_Rose_01", BK = 5 } } },
					{ v = 2, TE = 3, T3 = { PH = { TX = "Tall." }, PS = { TX = "Kind." }, HI = {} } } }) do
					local w = world({ about = about })
					fixtureCharacter(w.ns, w.char())
					w.prefs().trp3Style = styleId
					w.connect()
					expect.equal(w.run().state, "written")
					local v = w.about().v
					expect.equal(w.run().state, "noop", styleId .. " T" .. about.TE)
					expect.equal(w.about().v, v, "no version bump")
					-- The player's own content is untouched.
					if about.TE == 1 then expect.equal(w.about().T1.TX:sub(1, 7), "Mine.\n\n") end
					if about.TE == 2 then
						expect.deepEqual(w.about().T2[1], { TX = "Mine", IC = "INV_Misc_Rose_01", BK = 5 })
					end
					if about.TE == 3 then expect.equal(w.about().T3.PS.TX, "Kind.") end
				end
			end
		end)

		t:it("applies a chosen frame icon to Dawnward's frames, never to one the player restyled", function()
			local w = world({ about = { v = 2, TE = 2, T2 = {} } })
			fixtureCharacter(w.ns, w.char())
			w.connect()
			w.run()
			local frames = w.about().T2
			expect.equal(#frames, 3, "overview, biography, appearance")
			frames[3].IC, frames[3].BK = "INV_Sword_04", 9
			w.prefs().trp3Sections = { icons = { overview = "inv_scroll_02", appearance = "inv_misc_note_06" } }
			expect.equal(w.run().state, "written")
			expect.equal(w.about().T2[1].IC, "inv_scroll_02", "Dawnward's own frame takes the new icon")
			expect.equal(w.about().T2[3].IC, "INV_Sword_04", "the player's restyling is kept")
			expect.equal(w.about().T2[3].BK, 9)
			-- Moving a section keeps each frame's styling with its section.
			w.prefs().trp3Sections.order = { "appearance", "overview", "biography" }
			expect.equal(w.run().state, "written")
			expect.equal(w.about().T2[1].IC, "INV_Sword_04")
			expect.truthy(w.about().T2[1].TX:find("Appearance", 1, true))
			-- The record survives a reload, and the next run is a no-op.
			w.deps.ledger = w.ns.TRP3Ledger.Normalize(w.ns.Util.DeepCopy(w.deps.ledger))
			expect.equal(#w.record().frameIds, 3)
			expect.equal(w.run().state, "noop")
		end)

		t:it("upgrades the About page v0.10.0 wrote (template 1) in place, in one write", function()
			local w = world({ about = { v = 5, TE = 1, T1 = { TX = "Private about text\n\n" .. V010.T1 } } })
			fixtureCharacter(w.ns, w.char())
			w.connect()
			w.ns.TRP3Ledger.Profile(w.deps.ledger, w.fake.profileId).about = { template = 1, mode = "append",
				slots = { T1 = "\n\n" .. V010.T1 }, frames = {} }
			local r = w.run()
			expect.equal(r.state, "written", r.message)
			local tx = w.about().T1.TX
			expect.equal(tx:sub(1, #"Private about text\n\n{h2}Character overview"),
				"Private about text\n\n{h2}Character overview", "the player's text first, once")
			expect.equal(count(tx, "Private about text"), 1)
			for _, word in ipairs(RECORDS) do expect.falsy(tx:find(word, 1, true), "gone: " .. word) end
			expect.equal(count(visible(tx), "She was fourteen when the walls fell."), 1)
			expect.truthy(visible(tx):find("She hid in the mill.", 1, true))
			expect.equal(w.run().state, "noop", "then stable")
		end)

		t:it("upgrades v0.10.0's frames: reuses them by section, removes the ones no longer needed", function()
			local own = { TX = "My own frame", IC = "INV_Misc_Rose_01", BK = 5 }
			local frames = { own }
			local owned = {}
			for i, f in ipairs(V010.frames) do
				frames[#frames + 1] = { TX = f.TX, IC = f.IC, BK = f.BK }
				owned[i] = f.TX
			end
			local w = world({ about = { v = 5, TE = 2, T2 = frames } })
			fixtureCharacter(w.ns, w.char())
			w.connect()
			w.ns.TRP3Ledger.Profile(w.deps.ledger, w.fake.profileId).about = { template = 2, mode = "append",
				slots = {}, frames = owned }
			local r = w.run()
			expect.equal(r.state, "written", r.message)
			local T2 = w.about().T2
			expect.deepEqual(T2[1], own, "the player's frame is untouched")
			expect.equal(#T2, 1 + 3, "overview, biography, appearance; the rest removed")
			expect.equal(T2[2].IC, "inv_misc_book_09")
			expect.equal(T2[3].IC, "inv_misc_book_12", "the biography reused v0.10's first chapter frame")
			expect.equal(T2[4].IC, "spell_nature_strength", "the appearance kept its frame")
			for i = 2, 4 do
				for _, word in ipairs(RECORDS) do expect.falsy(T2[i].TX:find(word, 1, true), "gone: " .. word) end
			end
			expect.equal(w.run().state, "noop")
		end)

		t:it("pauses instead of dropping an obsolete v0.10.0 frame the player restyled", function()
			local frames, owned = {}, {}
			for i, f in ipairs(V010.frames) do
				frames[i] = { TX = f.TX, IC = f.IC, BK = f.BK }
				owned[i] = f.TX
			end
			frames[5].IC = "INV_Sword_04" -- the old Family frame, restyled by the player
			local w = world({ about = { v = 5, TE = 2, T2 = frames } })
			fixtureCharacter(w.ns, w.char())
			w.connect()
			w.ns.TRP3Ledger.Profile(w.deps.ledger, w.fake.profileId).about = { template = 2, mode = "append",
				slots = {}, frames = owned }
			local before = w.ns.Util.DeepCopy(w.about())
			local r = w.run()
			expect.equal(r.state, "conflict")
			expect.deepEqual(w.about(), before, "nothing written")
		end)

		t:it("upgrades v0.10.0's template 3: personality notes leave PS, the player's text stays", function()
			local w = world({ about = { v = 5, TE = 3, T3 = { PH = { TX = "Tall.\n\n" .. V010.PH },
				PS = { TX = "Kind.\n\n" .. V010.PS }, HI = { TX = V010.HI } } } })
			fixtureCharacter(w.ns, w.char())
			w.connect()
			w.ns.TRP3Ledger.Profile(w.deps.ledger, w.fake.profileId).about = { template = 3, mode = "append",
				slots = { PH = "\n\n" .. V010.PH, PS = "\n\n" .. V010.PS, HI = V010.HI }, frames = {} }
			local r = w.run()
			expect.equal(r.state, "written", r.message)
			local T3 = w.about().T3
			expect.equal(T3.PS.TX, "Kind.", "only the player's own personality text remains")
			expect.equal(visible(T3.PH.TX), "Tall.\n\nGrey eyes, a burn scar on one hand.")
			for _, word in ipairs(RECORDS) do expect.falsy(T3.HI.TX:find(word, 1, true), "gone: " .. word) end
			expect.equal(w.run().state, "noop")
		end)

		t:it("publishes the stand-in backstory whole, after the overview, with no sentence twice", function()
			local w = world()
			w.char()
			assert(w.ns.Sources.Capture(w.char(), "paste", STAND_IN, nil, 1))
			-- An overview that repeats the backstory's first lines word for word.
			local first = STAND_IN:match("\n\n(.-)\n\n")
			w.ns.Character.SetField(w.char(), "summary", first .. " A carter's daughter.", 1)
			w.connect()
			expect.equal(w.run().state, "written")
			local tx = visible(w.about().T1.TX)
			for block in (STAND_IN .. "\n\n"):gmatch("(.-)\n%s*\n") do
				block = block:match("^%s*(.-)%s*$")
				if block ~= "" then expect.equal(count(tx, block), 1, "once: " .. block:sub(1, 40)) end
			end
			expect.truthy(tx:find("{h2}Character overview{/h2}\nA carter's daughter.", 1, true), "only the new sentence")
		end)
	end)
end
