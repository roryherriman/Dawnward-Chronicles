-- L1/L2: the first-time setup wizard and the developer setup commands (v0.6).
-- Mocked client: proves the rules and wiring, not the in-game look.
local Boot = require("support.boot")
local Loader = require("support.loader")

local CHAR = "Testchar-TestRealm"

local function click(button)
	button:GetScript("OnClick")(button)
end

return function(t, expect)
	local function start(opts)
		opts = opts or {}
		opts.wizard = true
		local mock, env, ns = Boot.Start(opts)
		return mock, env, ns
	end

	local function wizard(ns)
		return ns.SetupWizard.Frame()
	end

	local function input(ns, key)
		for _, i in ipairs(wizard(ns).inputs) do
			if i.fieldKey == key then return i end
		end
	end

	local function cycle(ns, key)
		for _, b in ipairs(wizard(ns).cycles) do
			if b.spec.key == key then return b end
		end
	end

	local function goTo(ns, page)
		ns.SetupWizard.Go(page)
	end

	local function db(env)
		return env.DawnwardChroniclesDB
	end

	t:describe("setup wizard: when it opens", function()
		t:it("opens instead of the journal the first time a new character uses Dawnward, and writes nothing", function()
			local mock, env, ns = start()
			mock.Slash("")
			expect.truthy(ns.SetupWizard.IsShown())
			expect.falsy(ns.MainWindow.IsShown(), "the wizard comes first")
			expect.equal(wizard(ns).title:GetText(), "Welcome")
			expect.equal(wizard(ns).eyebrow:GetText(), "FIRST-TIME SETUP")
			expect.equal(wizard(ns):GetFrameStrata(), "HIGH")
			expect.falsy(db(env).characters[CHAR], "no character record before Finish")
		end)

		t:it("never opens by itself for an established character", function()
			local mock, _, ns = start()
			mock.Slash("set name Lirael")
			mock.Slash("")
			expect.falsy(ns.SetupWizard.IsShown())
			expect.truthy(ns.MainWindow.IsShown())
		end)

		t:it("counts recorded story data as established, not only profile fields", function()
			local ns = Loader.Core()
			local char = ns.Schema.NewCharacter(1)
			expect.falsy(ns.Onboarding.IsEstablished(char), "a blank record is still new")
			char.story.places["Elwynn Forest"] = ns.Places.CleanEntry({ zone = "Elwynn Forest", first = 1, last = 1 })
			expect.truthy(ns.Onboarding.IsEstablished(char))
			expect.falsy(ns.Onboarding.ShouldAutoLaunch(char))
			expect.truthy(ns.Onboarding.ShouldAutoLaunch(nil))
		end)

		t:it("does not open by itself in simulation mode or on read-only data", function()
			local mock, _, ns = start({ savedVariables = { DawnwardChroniclesDB = { schemaVersion = 999 } } })
			mock.Slash("")
			expect.falsy(ns.SetupWizard.IsShown())
			local mock2, _, ns2 = start()
			mock2.Slash("sim on")
			mock2.Slash("")
			expect.falsy(ns2.SetupWizard.IsShown())
		end)

		t:it("opens by itself at most once per session; closing keeps a draft without creating a record", function()
			local mock, env, ns = start()
			mock.Slash("")
			goTo(ns, 2)
			input(ns, "title"):SetText("Wanderer")
			goTo(ns, 3)
			click(wizard(ns).close)
			expect.falsy(ns.SetupWizard.IsShown())
			local draft = db(env).ui.wizardDrafts[CHAR]
			expect.equal(draft.page, 3)
			expect.equal(draft.values.title, "Wanderer")
			expect.falsy(db(env).characters[CHAR], "a draft is not a character record")
			mock.Slash("")
			expect.falsy(ns.SetupWizard.IsShown(), "not again this session")
			expect.truthy(ns.MainWindow.IsShown())
		end)

		t:it("resumes the draft in a new session, on the same page with the same values", function()
			local mock, env, ns = start()
			mock.Slash("")
			goTo(ns, 2)
			input(ns, "pronouns"):SetText("she/her")
			goTo(ns, 4)
			click(wizard(ns).later) -- Set up later: keeps the draft and opens the journal
			expect.truthy(ns.MainWindow.IsShown())
			local saved = ns.Util.DeepCopy(db(env))
			local mock2, _, ns2 = start({ savedVariables = { DawnwardChroniclesDB = saved } })
			mock2.Slash("")
			expect.truthy(ns2.SetupWizard.IsShown())
			expect.equal(wizard(ns2).title:GetText(), "Privacy")
			expect.equal(input(ns2, "pronouns"):GetText(), "she/her")
		end)
	end)

	t:describe("setup wizard: pages and Finish", function()
		t:it("keeps values between pages, with Back and Next", function()
			local mock, _, ns = start()
			mock.Slash("")
			expect.falsy(wizard(ns).back:IsEnabled(), "no Back on the first page")
			click(wizard(ns).next)
			expect.equal(wizard(ns).title:GetText(), "Character")
			expect.equal(input(ns, "name"):GetText(), "Testchar", "the in-game name is suggested")
			input(ns, "name"):SetText("Lirael Dawnward")
			click(wizard(ns).next)
			click(cycle(ns, "frequency"))
			expect.equal(cycle(ns, "frequency"):GetText(), "Rarely")
			click(wizard(ns).back)
			expect.equal(input(ns, "name"):GetText(), "Lirael Dawnward")
			click(wizard(ns).next)
			expect.equal(cycle(ns, "frequency"):GetText(), "Rarely")
		end)

		t:it("finishes: saves the choices, marks setup complete and opens the journal", function()
			local mock, env, ns = start()
			local trp3Before = ns.Util.DeepCopy(env.DawnwardChroniclesTRP3DB)
			mock.Slash("")
			goTo(ns, 2)
			input(ns, "name"):SetText("Lirael")
			input(ns, "homeland"):SetText("Goldshire")
			goTo(ns, 3)
			click(cycle(ns, "places")) -- on -> fewer
			goTo(ns, 5)
			click(wizard(ns).themeTiles[3]) -- Shadowbound
			expect.equal(ns.Style.Current().id, "shadowbound", "previewed at once")
			click(cycle(ns, "minimap")) -- hide
			goTo(ns, 6)
			expect.equal(wizard(ns).next:GetText(), "Finish")
			expect.truthy(wizard(ns).summary:GetText():find("Homeland: Goldshire", 1, true))
			click(wizard(ns).next)

			local char = db(env).characters[CHAR]
			expect.equal(char.fields.name.value, "Lirael")
			expect.equal(char.fields.name.visibility, "private")
			expect.equal(char.fields.homeland.value, "Goldshire")
			expect.falsy(char.fields.title, "empty answers write nothing")
			expect.equal(char.story.prefs.places, "fewer")
			expect.equal(char.theme, "shadowbound")
			expect.truthy(db(env).ui.minimap.hidden)
			expect.deepEqual(char.wizard, { done = true, version = ns.Onboarding.VERSION, doneAt = char.wizard.doneAt })
			expect.falsy(db(env).ui.wizardDrafts and db(env).ui.wizardDrafts[CHAR], "draft cleared")
			expect.deepEqual(env.DawnwardChroniclesTRP3DB, trp3Before, "nothing written to Total RP 3")
			expect.falsy(ns.SetupWizard.IsShown())
			expect.truthy(ns.MainWindow.IsShown())
			expect.equal(ns.MainWindow.CurrentSection(), "journal")
			-- Complete: the journal opens normally from now on, also after a reload.
			mock.Slash("")
			mock.Slash("")
			expect.falsy(ns.SetupWizard.IsShown())
			local clean = ns.Schema.NormalizeDatabase(db(env))
			expect.truthy(clean.characters[CHAR].wizard.done)
		end)

		t:it("never overwrites or clears an existing profile or story", function()
			local mock, env, ns = start()
			mock.Slash("set name Lirael")
			mock.Slash("set homeland Goldshire")
			mock.Slash("journal add An old entry")
			local before = ns.Util.DeepCopy(db(env).characters[CHAR])
			mock.Slash("setup")
			expect.truthy(ns.SetupWizard.IsShown(), "available on demand")
			goTo(ns, 2)
			expect.equal(input(ns, "homeland"):GetText(), "Goldshire", "existing values are pre-filled")
			input(ns, "homeland"):SetText("") -- an empty box never erases
			input(ns, "title"):SetText("Wanderer")
			goTo(ns, 6)
			click(wizard(ns).next)
			local char = db(env).characters[CHAR]
			expect.equal(char.fields.homeland.value, "Goldshire")
			expect.equal(char.fields.name.value, "Lirael")
			expect.equal(char.fields.title.value, "Wanderer")
			expect.deepEqual(char.journal, before.journal)
			expect.deepEqual(char.story.events, before.story.events)
		end)

		t:it("returns to the character's own theme when closed after a preview", function()
			local mock, env, ns = start()
			mock.Slash("set name Lirael")
			mock.Slash("theme lightbound")
			mock.Slash("setup")
			goTo(ns, 5)
			click(wizard(ns).themeTiles[3])
			expect.equal(ns.Style.Current().id, "shadowbound")
			click(wizard(ns).close)
			expect.equal(ns.Style.Current().id, "lightbound")
			expect.equal(db(env).characters[CHAR].theme, "lightbound", "a preview is not a choice")
		end)

		t:it("on read-only data opens as a preview that cannot save", function()
			local mock, env, ns = start({ savedVariables = { DawnwardChroniclesDB = { schemaVersion = 999 } } })
			mock.Slash("setup")
			expect.truthy(wizard(ns).eyebrow:GetText():find("READ-ONLY", 1, true))
			goTo(ns, 6)
			expect.falsy(wizard(ns).next:IsEnabled())
			click(wizard(ns).close)
			expect.equal(db(env).schemaVersion, 999)
			expect.falsy(db(env).ui)
		end)

		t:it("fits the smallest screen the game's UI scale allows", function()
			local _, _, ns = start()
			local L = ns.SetupWizard.LAYOUT
			expect.truthy(L.height <= 640 and L.width <= 1000)
			expect.truthy(L.bodyTop + 260 <= L.height - L.footer, "room for the tallest page")
		end)
	end)

	t:describe("developer setup commands", function()
		t:it("are unavailable outside development builds", function()
			local mock = start({ version = "0.6.0" })
			expect.truthy(mock.Slash("dev setup"):find("only available in development builds", 1, true))
			expect.truthy(mock.Slash("dev setup reset confirm"):find("only available", 1, true))
			expect.falsy(mock.Slash("help all"):find("dev setup", 1, true))
			local devMock = start()
			expect.truthy(devMock.Slash("help all"):find("dev setup", 1, true), "listed in development builds")
		end)

		t:it("dev setup opens a clearly marked preview, even after setup was completed", function()
			local mock, env, ns = start()
			mock.Slash("set name Lirael")
			db(env).characters[CHAR].wizard = { done = true, version = 1, doneAt = 5 }
			local reply = mock.Slash("dev setup")
			expect.truthy(reply:find("preview", 1, true))
			expect.truthy(ns.SetupWizard.IsShown())
			expect.truthy(wizard(ns).eyebrow:GetText():find("PREVIEW", 1, true))
			expect.falsy(wizard(ns).later:IsShown())
			goTo(ns, 6)
			expect.equal(wizard(ns).next:GetText(), "Save choices")
			expect.truthy(wizard(ns).discard:IsShown())
		end)

		t:it("Close preview discards everything; Save choices applies them without touching setup status", function()
			local mock, env, ns = start()
			mock.Slash("dev setup")
			goTo(ns, 2)
			input(ns, "name"):SetText("Preview Name")
			goTo(ns, 6)
			click(wizard(ns).discard)
			expect.falsy(db(env).characters[CHAR], "nothing saved")
			expect.falsy(db(env).ui and db(env).ui.wizardDrafts and db(env).ui.wizardDrafts[CHAR], "no draft")

			mock.Slash("dev setup")
			goTo(ns, 2)
			input(ns, "name"):SetText("Saved Name")
			goTo(ns, 6)
			click(wizard(ns).next)
			local char = db(env).characters[CHAR]
			expect.equal(char.fields.name.value, "Saved Name")
			expect.deepEqual(char.wizard, {}, "setup status unchanged")
		end)

		t:it("dev setup status reports completion, version, draft and whether the character is new", function()
			local mock, _, ns = start()
			local reply = mock.Slash("dev setup status")
			expect.truthy(reply:find("Setup: not complete.", 1, true))
			expect.truthy(reply:find("Current wizard version: 1.", 1, true))
			expect.truthy(reply:find("Draft: none.", 1, true))
			expect.truthy(reply:find("New character", 1, true))
			mock.Slash("")
			goTo(ns, 3)
			click(wizard(ns).close)
			reply = mock.Slash("dev setup status")
			expect.truthy(reply:find("Draft: saved, page 3 of 6 (Story).", 1, true))
			mock.Slash("setup")
			goTo(ns, 6)
			click(wizard(ns).next)
			reply = mock.Slash("dev setup status")
			expect.truthy(reply:find("Setup: complete (wizard version 1", 1, true))
			expect.truthy(reply:find("Draft: none.", 1, true))
		end)

		t:it("dev setup reset asks first, then forgets only the setup state", function()
			local mock, env, ns = start()
			mock.Slash("set name Lirael")
			mock.Slash("journal add Keep me")
			mock.Slash("memory add The day the grove burned")
			db(env).characters[CHAR].wizard = { done = true, version = 1, doneAt = 5 }
			ns.Actions.SaveSetupDraft(ns.ctx, { page = 2, values = { title = "x" } })
			local before = ns.Util.DeepCopy(db(env).characters[CHAR])
			local reply = mock.Slash("dev setup reset")
			expect.truthy(reply:find("dev setup reset confirm", 1, true))
			expect.truthy(db(env).characters[CHAR].wizard.done, "nothing changed without confirm")
			reply = mock.Slash("dev setup reset confirm")
			expect.truthy(reply:find("reset", 1, true))
			local char = db(env).characters[CHAR]
			expect.deepEqual(char.wizard, {})
			expect.falsy(db(env).ui.wizardDrafts[CHAR])
			before.wizard = {}
			expect.deepEqual(char, before, "profile, journal and story untouched")
		end)

		t:it("dev setup reset never creates a character record", function()
			local mock, env = start()
			mock.Slash("dev setup reset confirm")
			expect.falsy(db(env).characters[CHAR])
		end)
	end)

	t:describe("onboarding saved data", function()
		t:it("cleans completion state and drafts, and caps drafts", function()
			local ns = Loader.Core()
			local O = ns.Onboarding
			expect.deepEqual(O.Clean({ step = 3 }), {})
			expect.deepEqual(O.Clean({ done = true, version = 1, doneAt = 9, junk = 1 }), { done = true, version = 1,
				doneAt = 9 })
			expect.deepEqual(O.Clean({ done = "yes" }), {})
			local d = O.CleanDraft({ page = 99, values = { name = string.rep("n", 500), frequency = "loud",
				places = "fewer", theme = "paladin", minimap = false, card = false } })
			expect.equal(d.page, 1)
			expect.equal(#d.values.name, 100)
			expect.falsy(d.values.frequency)
			expect.equal(d.values.places, "fewer")
			expect.falsy(d.values.theme)
			expect.equal(d.values.minimap, false)
			local many = {}
			for i = 1, 80 do many["C" .. i .. "-Realm"] = { page = 2, values = {} } end
			local n = 0
			for _ in pairs(O.CleanDrafts(many)) do n = n + 1 end
			expect.equal(n, O.MAX_DRAFTS)
		end)

		t:it("keeps schema 5: v0.5 data loads unchanged apart from the new, empty setup state", function()
			local ns = Loader.Core()
			local raw = { schemaVersion = 5, characters = {}, importBackups = {},
				ui = { wizardDrafts = { [CHAR] = { page = 2, values = { name = "A" } } }, position = { left = 1, top = 2 } } }
			local db2, info = ns.Migrations.Load(raw)
			expect.equal(db2.schemaVersion, 5)
			expect.equal(info.status, "ok")
			expect.equal(db2.ui.wizardDrafts[CHAR].values.name, "A")
			expect.deepEqual(db2.ui.position, { left = 1, top = 2 })
		end)
	end)
end
