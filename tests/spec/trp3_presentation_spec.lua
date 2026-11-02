-- L2: TRP3 presentation styles and defining moments (fake 3.4.1; not in-game evidence).
local Loader = require("support.loader")
local Fake = require("fakes.trp3_341")

local function legacySpec(t, expect)
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
		local char = assert(store:EnsureCharacter(KEY, 1))
		return { ns = ns, fake = fake, deps = deps, char = char, Sync = ns.TRP3Sync }
	end

	-- Runs one quest through the story loop and returns the draft entry.
	local function storyEntry(w, title)
		local ns, char = w.ns, w.char
		char.story.pacing.playByCategory = {}
		local record = ns.GameEvents.Record(char, "quest", { questId = #char.story.events + 1, title = title,
			zone = "Ashenvale", level = 25 }, 10)
		local reaction = ns.Reactions.Consider(char, record, 10, 10)
		return ns.Decisions.Decide(char, reaction.id, { optionId = "nothing" }, 11).entry
	end

	local function publish(w, entry)
		assert(w.ns.Journal.Approve(w.char, entry.id, 12))
		assert(w.ns.Journal.SetImportant(w.char, entry.id, true, 12))
		assert(w.ns.Journal.SetVisibility(w.char, entry.id, "public", 12))
	end

	t:describe("TRP3 presentation (v0.4)", function()
		t:it("the default style gives exactly the v0.3 block", function()
			local ns = Loader.WithTRP3()
			local public = { facts = { { category = "origin", statement = "Born in {Mulgore}" },
				{ category = "belief", statement = "Trusts no one" } }, journal = {} }
			expect.equal(ns.TRP3AboutBlock.Compose(public),
				"{h3}Chronicle{/h3}\nOrigin: Born in (Mulgore)\nBelief: Trusts no one")
		end)

		t:it("only approved, important story entries in the projection become defining moments", function()
			local ns = Loader.WithTRP3()
			local journal = {
				{ kind = "story", status = "approved", important = true, visibility = "public", title = "Kept" },
				{ kind = "story", status = "draft", important = true, visibility = "public", title = "Draft" },
				{ kind = "story", status = "approved", important = false, visibility = "public", title = "Minor" },
				{ kind = "note", important = true, visibility = "public", title = "A note" },
			}
			expect.deepEqual(ns.TRP3AboutBlock.Moments({ journal = journal }), { "Kept" })
			expect.equal(ns.TRP3AboutBlock.Compose({ facts = {}, journal = journal }),
				"{h3}Chronicle{/h3}\nDefining moments:\n- Kept")
		end)

		t:it("every style uses only markup verified in TRP3 3.4.1's source", function()
			local ns = Loader.WithTRP3()
			local allowed = { "^h[123]$", "^/h[123]$", "^h[123]:[cr]$", "^p:[cr]$", "^/p$", "^col:%x%x%x%x%x%x$",
				"^/col$", "^icon:[%w_]+:%d+$" }
			for id, style in pairs(ns.TRP3Presentation.STYLES) do
				local text = ns.TRP3AboutBlock.Compose({ trp3Style = id, facts = { { category = "fear",
					statement = "x" } }, journal = { { kind = "story", status = "approved", important = true,
					visibility = "public", title = "{icon:evil:99} y" } } })
				for tag in text:gmatch("{([^}]*)}") do
					local ok = false
					for _, pattern in ipairs(allowed) do
						if tag:match(pattern) then ok = true end
					end
					expect.truthy(ok, id .. ": unverified tag {" .. tag .. "}")
				end
				expect.truthy(style.label)
				expect.falsy(text:find("evil", 1, true) and text:find("{icon:evil", 1, true), "player text is escaped")
			end
		end)

		t:it("a public defining moment syncs into the About section once, and drafts never do", function()
			local w = world()
			local entry = storyEntry(w, "The Ashenvale Ambush")
			w.Sync.SetOptIn(w.deps, "about", true)
			expect.equal(w.Sync.Check(w.deps, "about").state, "noop", "a private draft publishes nothing")
			publish(w, entry)
			local r = w.Sync.Run(w.deps)[1]
			expect.equal(r.state, "written", r.message)
			local text = w.fake.profile.player.about.T1.TX
			expect.truthy(text:find("Private about text", 1, true), "the player's own text is kept")
			expect.truthy(text:find("- The Ashenvale Ambush", 1, true), text)
			expect.equal(w.Sync.Run(w.deps)[1].state, "noop", "repeated sync is idempotent")
			-- Making it private again removes it on the next sync.
			w.ns.Journal.SetVisibility(w.char, entry.id, "private", 13)
			expect.equal(w.Sync.Run(w.deps)[1].state, "written")
			expect.equal(w.fake.profile.player.about.T1.TX, "Private about text")
		end)

		t:it("changing style rewrites only Dawnward's own section, and release restores the text", function()
			local w = world()
			publish(w, storyEntry(w, "Moment"))
			w.Sync.SetOptIn(w.deps, "about", true)
			w.Sync.Run(w.deps)
			w.char.story.prefs.trp3Style = "arcane"
			expect.equal(w.Sync.Run(w.deps)[1].state, "written")
			local text = w.fake.profile.player.about.T1.TX
			expect.truthy(text:find("{col:b89cff}", 1, true))
			expect.equal(text:sub(1, #"Private about text"), "Private about text")
			assert(w.Sync.Release(w.deps, "about"))
			expect.equal(w.fake.profile.player.about.T1.TX, "Private about text")
		end)

		t:it("an upgraded profile is not rewritten: v0.3 content with the default style is a no-op", function()
			local w = world()
			w.ns.Facts.Add(w.char, { category = "origin", statement = "Born at sea", visibility = "public" })
			w.Sync.SetOptIn(w.deps, "about", true)
			w.Sync.Run(w.deps)
			local version = w.fake.profile.player.about.v
			-- Schema v4 normalisation (as after an upgrade) and a new default story table.
			w.deps.store.real.characters[KEY] = w.ns.Schema.NormalizeCharacter(w.ns.Util.DeepCopy(w.char))
			expect.equal(w.Sync.Run(w.deps)[1].state, "noop")
			expect.equal(w.fake.profile.player.about.v, version)
		end)
	end)
end

-- These specs model characters an earlier version created (Loader.Legacy).
return function(t, expect)
	Loader.Legacy(function() legacySpec(t, expect) end)
end
