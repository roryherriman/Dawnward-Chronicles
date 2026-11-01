-- L2 (v0.9): the complete-biography regression for Dawnward -> Total RP 3,
-- end to end, against the TRP3 3.4.1 fake (mocked; not in-game evidence).
-- One long backstory of plain paragraphs is imported, published to the About
-- page in templates 1, 2 and 3, edited, synced again, put in conflict,
-- rolled back and reloaded, checking at every step that no paragraph is lost,
-- shortened, rewritten, duplicated or moved to the wrong profile.
--
-- Two texts: a public stand-in with the same shape (tests/fixtures/
-- backstory_paragraphs.lua) always runs; the owner's real backstory runs too
-- when a private copy is at private/fixtures/kyssarra_backstory.txt
-- (git-ignored, never committed).
local Loader = require("support.loader")
local Fake = require("fakes.trp3_341")

local STAND_IN = require("fixtures.backstory_paragraphs")

local function privateBackstory()
	local f = io.open("private/fixtures/kyssarra_backstory.txt", "rb")
	if not f then return nil end
	local text = f:read("*a")
	f:close()
	return text ~= "" and text or nil
end

-- The text's paragraphs: blocks between blank lines, as written.
local function paragraphs(text)
	local out = {}
	for block in (text:gsub("\r\n", "\n") .. "\n\n"):gmatch("(.-)\n%s*\n") do
		block = block:match("^%s*(.-)%s*$")
		if block ~= "" then out[#out + 1] = block end
	end
	return out
end

local function count(haystack, needle)
	local n, at = 0, 1
	while true do
		local s, e = haystack:find(needle, at, true)
		if not s then return n end
		n, at = n + 1, e + 1
	end
end

-- Every paragraph once, in order, and each still followed by the next one
-- after exactly one blank line (no paragraph merged, split or reflowed).
local function expectParagraphs(expect, published, text, where)
	local list = paragraphs(text)
	local at = 1
	for i, p in ipairs(list) do
		local s, e = published:find(p, at, true)
		expect.truthy(s, where .. ": missing or out of order: " .. p:sub(1, 50))
		if not s then return end
		expect.equal(count(published, p), 1, where .. ": duplicated: " .. p:sub(1, 50))
		if list[i + 1] then
			expect.equal(published:sub(e + 1, e + 2), "\n\n", where .. ": paragraph break kept after: " .. p:sub(1, 50))
		end
		at = e + 1
	end
end

local TEMPLATES = {
	{ id = 1, about = { v = 2, TE = 1, BK = 1, T1 = { TX = "Private about text" } } },
	{ id = 2, about = { v = 2, TE = 2, BK = 1, T2 = { { TX = "My own frame", IC = "INV_Misc_Rose_01", BK = 5 } } } },
	{ id = 3, about = { v = 2, TE = 3, BK = 1, T3 = { PH = { TX = "My own looks." }, PS = { TX = "My own notes." },
		HI = {} } } },
}

-- Everything Dawnward published, whatever the template.
local function publishedText(about)
	if about.TE == 1 then return about.T1.TX end
	if about.TE == 3 then return about.T3.HI.TX or "" end
	local parts = {}
	for _, frame in ipairs(about.T2 or {}) do parts[#parts + 1] = frame.TX or "" end
	return table.concat(parts, "\n\n")
end

return function(t, expect)
	local KEY = "Testchar-TestRealm"

	local function world(template)
		local ns = Loader.WithTRP3()
		local fake = Fake.new({ about = template and ns.Util.DeepCopy(template.about) or nil })
		local store = ns.Store.new(ns.Schema.NewDatabase(), ns.Schema.NewDatabase())
		local clock = 1000
		local deps = {
			env = fake.env, ledger = ns.TRP3Ledger.New(), store = store, characterKey = KEY,
			now = function() clock = clock + 1; return clock end,
			inCombat = function() return false end,
		}
		local w = { ns = ns, fake = fake, deps = deps, Sync = ns.TRP3Sync, store = store }
		function w.char()
			local char = assert(store:EnsureCharacter(KEY, 1))
			ns.Publication.Adopt(char, 1)
			return char
		end
		function w.import(text)
			return ns.StoryImport.Capture(w.char(), "paste", text, nil, deps.now())
		end
		function w.connect() assert(w.Sync.Authorize(deps, { about = "dawnward" })) end
		function w.run() return w.Sync.RunFeature(deps, "about") end
		function w.about() return fake.profile.player.about end
		function w.record() return deps.ledger.profiles[fake.profileId].about end
		return w
	end

	local function scenarios(name, text)
		t:describe("Biography regression: " .. name .. " (L2)", function()
			t:it("imports the whole text into Dawnward byte for byte, every paragraph intact", function()
				local w = world()
				local version, state = w.import(text)
				expect.truthy(version, state)
				expect.equal(state, "stored")
				local current = w.ns.Sources.Current(w.char())
				expect.equal(current.text, text, "stored verbatim: nothing trimmed, reflowed or rewritten")
				expect.equal(#current.text, #text)
				expect.deepEqual(paragraphs(current.text), paragraphs(text))
				expect.equal(#w.ns.Sources.Paragraphs(current.text), #paragraphs(text), "no paragraph merged")
				-- Reviewing it as pieces suggests canon but never touches the source.
				local proposed = w.ns.StoryImport.Propose(w.char(), current, nil, w.deps.now())
				expect.truthy(proposed.total >= 1, "the text is offered for review in pieces")
				expect.equal(w.ns.Sources.Current(w.char()).text, text, "review leaves the stored text as written")
				local _, again = w.import(text)
				expect.equal(again, "unchanged", "importing the same text again stores nothing new")
			end)

			for _, template in ipairs(TEMPLATES) do
				local label = "template " .. template.id
				t:it(label .. ": publishes every paragraph once, keeps the player's own content and styling", function()
					local w = world(template)
					w.import(text)
					local before = w.fake.snapshot()
					w.connect()
					local r = w.run()
					expect.equal(r.state, "written", r.message)
					local about = w.about()
					expect.equal(about.TE, template.id, "the template is not changed")
					expectParagraphs(expect, publishedText(about), text, label)
					-- Every sentence survives (T2: across the frames).
					local published = publishedText(about)
					for _, p in ipairs(paragraphs(text)) do
						for _, sentence in ipairs(w.ns.Sources.Sentences(p)) do
							expect.truthy(published:find(sentence, 1, true), label .. ": sentence kept: " .. sentence:sub(1, 40))
						end
					end
					-- Unrelated TRP3 content is untouched.
					expect.deepEqual(w.fake.profile.player.characteristics, before.player.characteristics)
					expect.deepEqual(w.fake.profile.player.character, before.player.character)
					if template.id == 1 then
						expect.equal(about.T1.TX:sub(1, #"Private about text\n\n"), "Private about text\n\n")
						expect.truthy(about.T1.TX:find("{h2}", 1, true), "headings use TRP3's own tags")
					elseif template.id == 2 then
						expect.deepEqual(about.T2[1], { TX = "My own frame", IC = "INV_Misc_Rose_01", BK = 5 })
						expect.truthy(#about.T2 >= 2, "Dawnward's frames come after the player's")
						for i = 2, #about.T2 do
							local frame = about.T2[i]
							expect.truthy(type(frame.IC) == "string" and frame.IC ~= "", "frame " .. i .. " has an icon")
							expect.truthy(type(frame.BK) == "number", "frame " .. i .. " has a background")
							expect.truthy(#frame.TX <= w.ns.TRP3AboutDoc.MAX_BYTES, "frame " .. i .. " fits")
						end
					else
						expect.equal(about.T3.PH.TX, "My own looks.", "nothing to add to appearance")
						expect.truthy(about.T3.PS.TX:find("^My own notes%."), "the player's notes stay first")
						expect.truthy(about.T3.HI.TX:find(paragraphs(text)[1], 1, true), "the story is the history")
					end
				end)

				t:it(label .. ": an edit updates only Dawnward's part; a second sync duplicates nothing", function()
					local w = world(template)
					w.import(text)
					w.connect()
					w.run()
					local list = paragraphs(text)
					local edited = text:gsub("\n*$", "") .. "\n\nA new paragraph written after the first sync.\n"
					expect.equal(select(2, w.import(edited)), "stored")
					expect.equal(w.run().state, "written")
					local published = publishedText(w.about())
					expectParagraphs(expect, published, edited, label .. " after the edit")
					expect.equal(count(published, list[1]), 1, "the first paragraph is not repeated")
					expect.equal(w.run().state, "noop", "a second sync writes nothing")
					expect.equal(publishedText(w.about()), published)
					if template.id == 1 then
						expect.equal(count(w.about().T1.TX, "Private about text"), 1)
					end
				end)

				t:it(label .. ": a hand edit to Dawnward's part is a conflict, and the player's edit is kept", function()
					local w = world(template)
					w.import(text)
					w.connect()
					w.run()
					local first = paragraphs(text)[2]
					local about = w.about()
					if template.id == 1 then
						about.T1.TX = about.T1.TX:gsub(first:gsub("%p", "%%%0"), "Rewritten by hand in TRP3.", 1)
					elseif template.id == 2 then
						about.T2[#about.T2].TX = about.T2[#about.T2].TX .. "\nAdded by hand in TRP3."
					else
						about.T3.HI.TX = about.T3.HI.TX:gsub(first:gsub("%p", "%%%0"), "Rewritten by hand in TRP3.", 1)
					end
					local hand = publishedText(about)
					w.import(text .. "\nOne more line from Dawnward.")
					expect.equal(w.run().state, "conflict")
					expect.equal(publishedText(w.about()), hand, "nothing overwritten")
				end)
			end

			t:it("keeps text the player adds outside Dawnward's part when Dawnward updates (templates 1 and 3)", function()
				for _, template in ipairs({ TEMPLATES[1], TEMPLATES[3] }) do
					local w = world(template)
					w.import(text)
					w.connect()
					w.run()
					local about = w.about()
					local h = template.id == 1 and about.T1 or about.T3.HI
					h.TX = h.TX .. "\n\nA closing note the player typed in TRP3."
					local edited = text:gsub("\n*$", "") .. "\n\nAnother paragraph from Dawnward.\n"
					w.import(edited)
					expect.equal(w.run().state, "written", "template " .. template.id)
					h = template.id == 1 and w.about().T1 or w.about().T3.HI
					expectParagraphs(expect, h.TX, edited, "template " .. template.id)
					expect.equal(count(h.TX, "A closing note the player typed in TRP3."), 1, "the player's note is kept once")
				end
			end)

			t:it("backs up before writing and rolls back to the player's own About text", function()
				local w = world(TEMPLATES[1])
				w.import(text)
				w.connect()
				w.run()
				expect.truthy(#w.deps.ledger.backups >= 1, "a backup was taken before the first write")
				local backup = w.deps.ledger.backups[1]
				expect.equal(w.ns.TRP3Ledger.BackupData(backup).T1.TX, "Private about text")
				local preview = w.Sync.RollbackPreview(w.deps)
				expect.truthy(preview, "a preview before anything changes")
				expect.truthy(w.about().T1.TX:find(paragraphs(text)[2], 1, true), "previewing changes nothing")
				w.ns.Sources.SetVisibility(w.char(), "private", w.deps.now())
				local ok, msg = w.Sync.Rollback(w.deps, nil, "own")
				expect.truthy(ok, msg)
				expect.equal(w.about().T1.TX, "Private about text")
			end)

			t:it("survives a reload: the record persists and the next sync is a no-op", function()
				for _, template in ipairs(TEMPLATES) do
					local w = world(template)
					w.import(text)
					w.connect()
					w.run()
					local published = publishedText(w.about())
					-- /reload: SavedVariables are written and read back; Lua state is gone.
					local saved = w.ns.Serializer and w.ns.Serializer.Decode
						and w.ns.Serializer.Decode(w.ns.Serializer.Encode(w.deps.ledger)) or w.ns.Util.DeepCopy(w.deps.ledger)
					w.deps.ledger = w.ns.TRP3Ledger.Normalize(saved)
					w.fake.reload()
					expect.equal(w.ns.Sources.Current(w.char()).text, text, "the biography itself is unchanged")
					expect.equal(w.run().state, "noop", "template " .. template.id .. ": nothing rewritten after reload")
					expect.equal(publishedText(w.about()), published)
				end
			end)

			t:it("stays with its own character and TRP3 profile", function()
				local w = world(TEMPLATES[1])
				w.import(text)
				w.connect()
				w.run()
				expect.truthy(w.record(), "the record is kept under the connected profile")
				expect.equal(w.deps.ledger.optIn[KEY].profileId, w.fake.profileId)
				-- Another character on the same TRP3 profile cannot take the About page.
				local main = w.deps.characterKey
				w.deps.characterKey = "Alt-TestRealm"
				expect.falsy(w.Sync.SetOptIn(w.deps, "about", true))
				w.deps.characterKey = main
				-- Another TRP3 profile is never written to.
				w.fake.switchProfile("1700000099ZZZZZ", "Other", { about = { v = 1, TE = 1, T1 = { TX = "Other bio" } },
					characteristics = { v = 1, PS = {} }, character = { v = 1 } })
				w.import(text .. "\nA change after the switch.")
				local r = w.run()
				expect.equal(r.state, "blocked")
				expect.equal(w.about().T1.TX, "Other bio")
			end)
		end)
	end

	scenarios("stand-in backstory", STAND_IN)
	local private = privateBackstory()
	if private then
		scenarios("the owner's backstory (private fixture)", private)
	end
end
