-- L1/L2 (v0.9): the full-profile About page. The player's whole biography
-- (word for word, every paragraph, in order) and the Public sections of the
-- character, in Total RP 3's templates 1, 2 and 3, kept up to date
-- automatically, never duplicated and never written over the player's own
-- text. Against the TRP3 3.4.1 fake (mocked; not in-game evidence).
local Loader = require("support.loader")
local Fake = require("fakes.trp3_341")

local LONG = require("fixtures.long_biography")

-- The owner's real backstory, when a private copy exists (git-ignored).
local function privateBackstory()
	local f = io.open("private/fixtures/kyssarra_backstory.txt", "rb")
	if not f then return nil end
	local text = f:read("*a")
	f:close()
	return text ~= "" and text or nil
end

-- Every line of the biography that is not one of the player's headings.
local function bodyLines(text)
	local out = {}
	for line in (text:gsub("\r\n", "\n") .. "\n"):gmatch("([^\n]*)\n") do
		local heading = line:match("^%s*#+%s*%S") or line:match("^%s*{h%d[:%a]*}.-{/h%d}%s*$")
		if not heading and line:match("%S") then out[#out + 1] = line end
	end
	return out
end

-- Asserts every body line appears in text exactly once and in order.
local function expectWhole(expect, text, biography)
	local at = 1
	for _, line in ipairs(bodyLines(biography)) do
		local s, e = text:find(line, at, true)
		expect.truthy(s, "missing or out of order: " .. line:sub(1, 60))
		if s then
			expect.falsy(text:find(line, e + 1, true), "duplicated: " .. line:sub(1, 60))
			at = e + 1
		end
	end
end

return function(t, expect)
	local KEY = "Testchar-TestRealm"

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
				ns.Publication.Adopt(char, 1) -- a character set up with the wizard: its whole profile publishes
				w.adopted = true
			end
			return char
		end
		function w.bio(text)
			assert(ns.Sources.Capture(w.char(), "paste", text, nil, deps.now()))
		end
		function w.field(key, value)
			assert(ns.Character.SetField(w.char(), key, value, 1))
		end
		function w.pref(key, value) w.char().story.prefs[key] = value end
		function w.connect(opts)
			assert(w.Sync.Authorize(deps, { about = "dawnward" }, opts))
		end
		function w.run() return w.Sync.RunFeature(deps, "about") end
		function w.about() return fake.profile.player.about end
		function w.record() return deps.ledger.profiles[fake.profileId].about end
		return w
	end

	t:describe("About document: the biography (L1)", function()
		t:it("splits only at the player's own headings and keeps every line, in order", function()
			local AboutDoc = Loader.WithTRP3().TRP3AboutDoc
			local sections = AboutDoc.SplitBiography(LONG)
			local titles = {}
			for i, s in ipairs(sections) do titles[i] = s.title or "(before the first heading)" end
			expect.deepEqual(titles, { "(before the first heading)", "The fall of Lordaeron", "Family",
				"Beliefs and motivations", "Defining experiences" })
			local joined = {}
			for _, s in ipairs(sections) do joined[#joined + 1] = s.body end
			expectWhole(expect, table.concat(joined, "\n"), LONG)
			expect.truthy(sections[2].body:find("carry it to. She was fourteen.\n\nThe night", 1, true),
				"a blank line inside a section is kept")
		end)

		t:it("builds sections from Public data only, in a fixed order", function()
			local ns = Loader.WithTRP3()
			local char = ns.Schema.NewCharacter(1)
			ns.Publication.Adopt(char, 1)
			ns.Character.SetField(char, "summary", "A quiet paladin who keeps a book of names.", 1)
			ns.Character.SetField(char, "appearance", "Grey eyes, a burn scar on one hand.", 1)
			ns.Character.SetField(char, "motivation", "No village forgotten.", 1)
			ns.Character.SetFieldVisibility(char, "motivation", "private", 1)
			ns.Character.AddItem(char, "family", { relation = "brother", name = "Tomas", status = "living" }, 1)
			ns.Facts.Add(char, { category = "belief", statement = "The Light never left" })
			ns.Facts.Add(char, { category = "origin", statement = "Born above the river fields" })
			ns.Sources.Capture(char, "paste", "One paragraph of story.", nil, 2)
			local doc = ns.TRP3AboutDoc.Build(ns.Projection.GetPublic(char))
			local ids = {}
			for i, s in ipairs(doc) do ids[i] = s.id .. ":" .. s.title end
			expect.deepEqual(ids, { "overview:Character overview", "appearance:Appearance", "bio:Background",
				"family:Family", "beliefs:Beliefs and motivations", "notes:Chronicle notes" })
			local all = {}
			for _, s in ipairs(doc) do all[#all + 1] = s.body end
			all = table.concat(all, "\n")
			expect.falsy(all:find("No village forgotten", 1, true), "a Private field never appears")
			expect.truthy(all:find("Brother: Tomas (living)", 1, true))
			expect.truthy(all:find("Origin: Born above the river fields", 1, true))
		end)

		t:it("styles headings with TRP3's own tags and escapes a player's heading", function()
			local P = Loader.WithTRP3().TRP3Presentation
			expect.equal(P.SectionHeading(P.Get("neutral"), "Family", 2, "family"), "{h2}Family{/h2}")
			expect.equal(P.SectionHeading(P.Get("silverhand"), "Family", 2, "family"),
				"{h2}{col:e6c35c}Family{/col}{/h2}")
			expect.equal(P.SectionHeading(P.Get("arcane"), "Family", 3, "family"),
				"{h3}{icon:inv_misc_grouplooking:18} {col:b89cff}Family{/col}{/h3}")
			expect.equal(P.SectionHeading(P.Get("neutral"), "{col:ff0000}Red", 2), "{h2}(col:ff0000)Red{/h2}")
		end)
	end)

	t:describe("About page: template 1 (L2)", function()
		t:it("adds the whole biography after the player's own text, once, and keeps it up to date", function()
			local w = world()
			w.bio(LONG)
			w.field("summary", "A quiet paladin.")
			w.connect()
			local r = w.run()
			expect.equal(r.state, "written", r.message)
			local tx = w.about().T1.TX
			expect.equal(tx:sub(1, #"Private about text\n\n"), "Private about text\n\n", "the player's text stays first")
			expect.truthy(tx:find("{h2}Character overview{/h2}\nA quiet paladin.", 1, true))
			expect.truthy(tx:find("{h2}The fall of Lordaeron{/h2}\nWhen the grain carts", 1, true))
			expectWhole(expect, tx, LONG)
			expect.equal(w.run().state, "noop", "no change, no write, no version bump")
			-- The biography changes in Dawnward: the same block is replaced in place.
			w.bio(LONG .. "\nShe still keeps bees.")
			expect.equal(w.run().state, "written")
			tx = w.about().T1.TX
			expectWhole(expect, tx, LONG .. "\nShe still keeps bees.")
			local _, count = tx:gsub("Private about text", "")
			expect.equal(count, 1)
		end)

		t:it("an older character's hidden biography waits for the one-time confirmation", function()
			local w = world()
			w.bio("A secret past.")
			w.ns.Sources.SetVisibility(w.char(), "secret", 5)
			w.char().publication = { mode = "profile" } -- a v0.9 character with a hidden item
			w.field("summary", "Public summary.")
			w.connect()
			w.run()
			expect.falsy(w.about().T1.TX:find("A secret past", 1, true))
			expect.truthy(w.about().T1.TX:find("Public summary.", 1, true))
		end)

		t:it("pauses instead of overwriting when the player edits Dawnward's part", function()
			local w = world()
			w.bio("First paragraph.")
			w.connect()
			w.run()
			w.about().T1.TX = w.about().T1.TX:gsub("First paragraph%.", "First paragraph, edited by hand.")
			w.bio("First paragraph, revised in Dawnward.")
			local r = w.run()
			expect.equal(r.state, "conflict")
			expect.truthy(w.about().T1.TX:find("edited by hand", 1, true), "the player's edit wins")
		end)

		t:it("never duplicates: Dawnward's text already there without a record is a conflict", function()
			local w = world()
			w.bio("Only this.")
			w.connect()
			w.run()
			local text = w.about().T1.TX
			w.deps.ledger.profiles[w.fake.profileId].about = nil -- the ledger was lost
			local r = w.run()
			expect.equal(r.state, "conflict", r.message)
			expect.equal(w.about().T1.TX, text, "not appended a second time")
		end)

		t:it("refuses, with the reason, a section larger than it writes, and never shortens it", function()
			local w = world()
			w.bio(string.rep("A long line of story that goes on. ", 400)) -- about 14 KB
			w.field("summary", string.rep("Summary words. ", 120))
			for i = 1, 40 do
				w.ns.Facts.Add(w.char(), { category = "event", statement = string.rep("Fact " .. i .. " ", 30) })
			end
			w.ns.TRP3AboutDoc.MAX_BYTES = 8000
			w.connect()
			local check = w.Sync.Check(w.deps, "about")
			w.ns.TRP3AboutDoc.MAX_BYTES = 30000
			expect.equal(check.state, "blocked")
			expect.truthy(check.reasons[1]:find("never shortens", 1, true), check.reasons[1])
		end)
	end)

	t:describe("About page: template 2 frames (L2)", function()
		t:it("adds a frame per section after the player's frames, with icons and a background", function()
			local own = { TX = "My own frame", IC = "INV_Misc_Rose_01", BK = 5 }
			local w = world({ about = { v = 2, TE = 2, T2 = { own } } })
			w.bio(LONG)
			w.pref("trp3Style", "arcane")
			w.connect()
			expect.equal(w.run().state, "written")
			local frames = w.about().T2
			expect.deepEqual(frames[1], { TX = "My own frame", IC = "INV_Misc_Rose_01", BK = 5 })
			expect.equal(#frames, 1 + 5, "one frame per biography section")
			expect.equal(frames[2].IC, "inv_misc_book_12")
			expect.equal(frames[2].BK, 1)
			expect.truthy(frames[3].TX:find("{h2}{icon:inv_misc_book_12:18} {col:b89cff}The fall of Lordaeron", 1,
				true))
			local all = {}
			for i = 2, #frames do all[#all + 1] = frames[i].TX end
			expectWhole(expect, table.concat(all, "\n"), LONG)
		end)

		t:it("keeps a restyled frame's icon and background, and removes frames no longer needed", function()
			local w = world({ about = { v = 2, TE = 2, T2 = {} } })
			w.bio("# One\nFirst.\n# Two\nSecond.")
			w.connect()
			w.run()
			w.about().T2[1].IC = "INV_Sword_04"
			w.about().T2[1].BK = 9
			w.bio("# One\nFirst, revised.")
			expect.equal(w.run().state, "written")
			expect.equal(#w.about().T2, 1)
			expect.equal(w.about().T2[1].IC, "INV_Sword_04", "the player's styling is kept")
			expect.equal(w.about().T2[1].BK, 9)
			expect.truthy(w.about().T2[1].TX:find("First, revised.", 1, true))
		end)
	end)

	t:describe("About page: template 3 (L2)", function()
		t:it("puts appearance in PH, beliefs and personality in PS, the rest in the history", function()
			local w = world({ about = { v = 2, TE = 3, T3 = { PH = {}, PS = { TX = "My own personality notes." }, HI = {} } } })
			w.bio(LONG)
			w.field("appearance", "Grey eyes.")
			w.field("motivation", "No village forgotten.")
			w.connect()
			expect.equal(w.run().state, "written")
			local t3 = w.about().T3
			expect.equal(t3.PH.TX, "Grey eyes.", "TRP3 titles this part itself")
			expect.truthy(t3.PS.TX:find("^My own personality notes%.\n\n{h3}Beliefs and motivations{/h3}"))
			expectWhole(expect, t3.HI.TX, LONG)
		end)
	end)

	t:describe("About page: layout, takeover and upgrade (L2)", function()
		t:it("switches template when the player picks one in Dawnward, moving only Dawnward's content", function()
			local w = world()
			w.bio("# Story\nA tale.")
			w.connect()
			w.run()
			w.pref("trp3Layout", "frames")
			expect.equal(w.run().state, "written")
			expect.equal(w.about().TE, 2)
			expect.equal(w.about().T1.TX, "Private about text", "the old template keeps only the player's text")
			expect.truthy(w.about().T2[1].TX:find("A tale.", 1, true))
		end)

		t:it("a template changed in Total RP 3 pauses sync", function()
			local w = world()
			w.bio("A tale.")
			w.connect()
			w.run()
			w.about().TE = 3
			expect.equal(w.run().state, "conflict")
		end)

		t:it("Replace takes over the About text once, keeping the player's text in a backup", function()
			local w = world()
			w.bio("The whole story.")
			w.connect({ adopt = true })
			expect.equal(w.run().state, "written")
			expect.truthy(w.about().T1.TX:find("^{h2}Background{/h2}\nThe whole story%."))
			expect.falsy(w.about().T1.TX:find("Private about text", 1, true))
			local backup = w.deps.ledger.backups[#w.deps.ledger.backups]
			expect.equal(w.ns.TRP3Ledger.BackupData(backup).T1.TX, "Private about text")
			expect.equal(w.record().mode, "adopt")
			-- Later edits in TRP3 are conflicts, never overwritten.
			w.about().T1.TX = w.about().T1.TX .. "\nAdded in TRP3."
			w.bio("The whole story, revised.")
			expect.equal(w.run().state, "conflict")
		end)

		t:it("upgrades a v0.8 summary block in place to the full profile, without duplicating", function()
			local w = world()
			local char = w.char()
			char.publication = {} -- an older character: the summary block
			w.ns.Facts.Add(char, { category = "origin", statement = "Born in Stormwind", visibility = "public" })
			w.connect()
			expect.equal(w.run().state, "written")
			expect.equal(w.about().T1.TX, "Private about text\n\n{h3}Chronicle{/h3}\nOrigin: Born in Stormwind")
			expect.truthy(w.record().block, "the v0.8 record shape for the summary")
			w.pref("trp3About", "profile")
			expect.equal(w.run().state, "written")
			local tx = w.about().T1.TX
			expect.falsy(tx:find("{h3}Chronicle{/h3}", 1, true), "the old block was replaced, not kept")
			expect.truthy(tx:find("{h2}Chronicle notes{/h2}\nOrigin: Born in Stormwind", 1, true))
			local _, count = tx:gsub("Private about text", "")
			expect.equal(count, 1)
		end)

		t:it("rolls back to the player's own text, rebuilding Dawnward's part from what is Public now", function()
			local w = world()
			w.bio("A tale.")
			w.connect()
			w.run()
			w.bio("A tale, retold.") -- a second write: its backup holds Dawnward's first text
			w.run()
			w.char().publication = {} -- back on an older model: the story is no longer published
			local preview = w.Sync.RollbackPreview(w.deps)
			expect.truthy(preview.ownPossible, preview.ownReason)
			expect.truthy(table.concat(preview.items, "\n"):find("A tale.", 1, true), "names what is no longer Public")
			local ok, msg = w.Sync.Rollback(w.deps, nil, "own")
			expect.truthy(ok, msg)
			expect.equal(w.about().T1.TX, "Private about text")
		end)

		t:it("keeps the v0.9 About record across a reload", function()
			local w = world({ about = { v = 2, TE = 2, T2 = {} } })
			w.bio("# One\nFirst.")
			w.connect()
			w.run()
			local clean = w.ns.TRP3Ledger.Normalize(w.ns.Util.DeepCopy(w.deps.ledger))
			expect.deepEqual(clean.profiles[w.fake.profileId].about.frames, w.record().frames)
			expect.equal(w.run().state, "noop")
		end)
	end)

	t:describe("About page: the owner's backstory (private fixture, when present)", function()
		t:it("publishes Kyssarra Dawnward's complete backstory word for word in templates 1, 2 and 3", function()
			local text = privateBackstory()
			if not text then
				-- Not in the repository: copy it to private/fixtures/kyssarra_backstory.txt to run this.
				return
			end
			for _, about in ipairs({ { v = 2, TE = 1, T1 = {} }, { v = 2, TE = 2, T2 = {} },
				{ v = 2, TE = 3, T3 = { PH = {}, PS = {}, HI = {} } } }) do
				local w = world({ about = about })
				w.bio(text)
				w.connect()
				expect.equal(w.run().state, "written")
				local a = w.about()
				local all = a.T1 and a.T1.TX or a.T3 and a.T3.HI.TX or ""
				for _, frame in ipairs(a.T2 or {}) do all = all .. "\n" .. frame.TX end
				expectWhole(expect, all, text)
			end
		end)
	end)
end
