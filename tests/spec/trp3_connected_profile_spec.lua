-- L2 (v0.9): the connected-profile screen (Settings > Total RP 3 >
-- Overview), the one-step connection, automatic updates after it, the
-- profile preview and the biography's own visibility, through the whole
-- addon under the WoW mock and the TRP3 3.4.1 fake (not in-game evidence).
local Loader = require("support.loader")
local Boot = require("support.boot")
local Fake = require("fakes.trp3_341")

local CHAR = "Testchar-TestRealm"

local function click(button)
	button:GetScript("OnClick")(button)
end

local function start(fakeOpts, savedVariables)
	local fake = Fake.new(fakeOpts or {})
	local extra = {}
	for k, v in pairs(fake.env) do
		if k ~= "C_AddOns" then extra[k] = v end
	end
	local mock, env, ns = Boot.Load({ extra = extra, savedVariables = savedVariables })
	mock.env.C_AddOns.IsAddOnLoaded = fake.env.C_AddOns.IsAddOnLoaded
	local meta = mock.env.C_AddOns.GetAddOnMetadata
	mock.env.C_AddOns.GetAddOnMetadata = function(name, field)
		return fake.env.C_AddOns.GetAddOnMetadata(name, field) or meta(name, field)
	end
	Boot.Login(mock)
	ns.SetupWizard.SkipAutoLaunchThisSession(ns.ctx.characterKey)
	function mock.AcceptPopup()
		local d = ns.Widgets.dialog
		assert(d and d:IsShown(), "no confirmation dialog is open")
		local text = d.text:GetText()
		d.accept:GetScript("OnClick")(d.accept)
		return text
	end
	return mock, env, ns, fake
end

local function open(ns)
	ns.SettingsPanel.OpenPage("trp3")
	local page = ns.SettingsPanel.panel.trp3Page
	click(page.nav.buttons[1])
	return page
end

-- A v0.9 character: profile model, a name, a story.
local function newCharacter(mock, ns)
	mock.Slash("set name Mirelle")
	local char = ns.ctx.store.real.characters[CHAR]
	ns.Publication.Adopt(char, 1)
	for key in pairs(char.fields) do char.fields[key].visibility = "public" end
	mock.Slash("set firstName Mirelle")
	mock.Slash("set pronouns she/her")
	ns.Actions.WithCharacter(ns.ctx, function(c)
		return ns.Sources.Capture(c, "paste", "# The fall of Lordaeron\nThe walls fell.\n\nShe hid.", nil, 5)
	end)
	return char
end

local function legacySpec(t, expect)
	t:describe("connected profile: Overview and one-step connection (L2)", function()
		t:it("shows the profile at a glance, and connects everything after one confirmation", function()
			-- A fresh Total RP 3 profile: the first name is the game's own (replaceable).
			local mock, env, ns, fake = start({ characteristics = { v = 3, FN = "Testchar", PS = {} } })
			newCharacter(mock, ns)
			mock.timers = {}
			local page = open(ns)
			expect.truthy(page.overview:IsShown())
			expect.equal(page.overviewRows[1].value:GetText(), "Main · this character only")
			expect.equal(page.overviewRows[2].value:GetText(), "Not connected")
			expect.equal(page.chip.label:GetText(), "Not connected")
			click(page.connectAll)
			local asked = mock.AcceptPopup()
			expect.truthy(asked:find("About page (your whole story)", 1, true))
			local entry = env.DawnwardChroniclesTRP3DB.optIn[CHAR]
			for _, id in ipairs(ns.TRP3Ledger.MAPPINGS) do
				expect.equal(ns.TRP3Ledger.Policy(entry, id), "dawnward", id)
			end
			expect.equal(#fake.events, 0, "nothing written until the debounced run")
			mock.RunTimers()
			local about = fake.profile.player.about.T1.TX
			expect.truthy(about:find("{h2}The fall of Lordaeron{/h2}\nThe walls fell.\n\nShe hid.", 1, true), about)
			expect.equal(fake.profile.player.characteristics.FN, "Mirelle")
			expect.equal(fake.profile.player.characteristics.MI[1].VA, "she/her")
			ns.MainWindow.Refresh()
			expect.truthy(page.overviewRows[2].value:GetText():find("20 of 20 items", 1, true))
			expect.falsy(page.overviewRows[3].value:GetText():find("Nothing written", 1, true), "a last update time")
		end)

		t:it("keeps TRP3 up to date by itself after a change, without asking again", function()
			local mock, _, ns, fake = start()
			newCharacter(mock, ns)
			assert(ns.TRP3Commands.ConnectAll(ns.ctx, {}))
			mock.RunTimers()
			mock.chat = {}
			ns.Actions.WithCharacter(ns.ctx, function(c)
				return ns.Sources.Capture(c, "paste", "# The fall of Lordaeron\nThe walls fell at dusk.", nil, 9)
			end)
			expect.equal(#mock.timers, 1, "one debounced run")
			mock.RunTimers()
			expect.truthy(fake.profile.player.about.T1.TX:find("The walls fell at dusk.", 1, true))
			expect.falsy(ns.Widgets.dialog and ns.Widgets.dialog:IsShown(), "no prompt")
			mock.Slash("set pronouns they/them")
			mock.RunTimers()
			expect.equal(fake.profile.player.characteristics.MI[1].VA, "they/them")
		end)

		t:it("changes the About layout, template and style from the Overview", function()
			local mock, _, ns, fake = start()
			newCharacter(mock, ns)
			assert(ns.TRP3Commands.ConnectAll(ns.ctx, {}))
			mock.RunTimers()
			local page = open(ns)
			local layout = page.overviewChoices[2]
			for _, b in ipairs(layout.buttons) do
				if b.segmentId == "frames" then click(b) end
			end
			expect.equal(ns.ctx.store.real.characters[CHAR].story.prefs.trp3Layout, "frames")
			mock.RunTimers()
			expect.equal(fake.profile.player.about.TE, 2)
			expect.truthy(fake.profile.player.about.T2[1].TX:find("The walls fell.", 1, true))
			expect.equal(fake.profile.player.about.T1.TX, "Private about text", "only Dawnward's content moved")
		end)

		t:it("fits every Overview label, status line and button inside the card", function()
			local _, _, ns = start()
			local page = open(ns)
			for _, seg in ipairs(page.overviewChoices) do
				for _, b in ipairs(seg.buttons) do
					expect.truthy(ns.Widgets.LabelFits(b:GetText(), b:GetWidth(), b:GetHeight(), "segment"),
						seg.key .. ": " .. b:GetText())
				end
			end
			expect.truthy(page.connectAll:GetWidth() + page.previewProfile:GetWidth() + 8 + 2 * 18
				<= page.card:GetWidth(), "the two buttons do not overlap")
			expect.truthy(ns.Style.TextWidth(page.overviewTitle:GetText(), "title") + 12 + page.switchModel:GetWidth()
				+ 2 * 18 <= page.card:GetWidth(), "the switch button sits beside the title")
			local lastRow = 88 + 8 * ns.TRP3Page.OVERVIEW_ROW + 10 + 3 * (ns.TRP3Page.SELECTOR_HEIGHT + 10)
			expect.truthy(lastRow <= page.card:GetHeight() - 14 - ns.Style.CONTROL.compact - 8,
				"choices stay above the buttons")
		end)

		t:it("previews everything it would publish without writing", function()
			local mock, _, ns, fake = start()
			newCharacter(mock, ns)
			mock.Slash("set faith A private faith")
			ns.Character.SetFieldVisibility(ns.ctx.store.real.characters[CHAR], "faith", "private", 9)
			local before = fake.snapshot()
			local page = open(ns)
			click(page.previewProfile)
			local text = ns.CopyBox.GetFrame().editBox:GetText()
			expect.truthy(text:find("ABOUT PAGE (template 1)", 1, true))
			expect.truthy(text:find("She hid.", 1, true))
			expect.truthy(text:find("First name: Mirelle", 1, true))
			expect.truthy(text:find("Pronouns: she/her", 1, true))
			expect.falsy(text:find("A private faith", 1, true), "never a Private value")
			expect.deepEqual(fake.snapshot(), before)
		end)
	end)

	t:describe("connected profile: older characters (L2)", function()
		t:it("offers the one-time confirmation, which publishes older details only after it, keeping the records",
			function()
			local mock, env, ns = start()
			mock.Slash("set name Lirael")
			mock.Slash("set faith The Light")
			mock.Vis("vis faith secret")
			local page = open(ns)
			expect.truthy(page.switchModel:IsShown())
			click(page.switchModel)
			local asked = mock.AcceptPopup()
			expect.truthy(asked:find("Profile details: 2 more to publish", 1, true), asked)
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			expect.truthy(ns.Publication.IsComplete(char))
			expect.equal(char.fields.faith.visibility, "secret", "the stored record is not changed")
			expect.equal(ns.Projection.GetPublic(char).fields.faith.value, "The Light")
			ns.MainWindow.Refresh()
			expect.falsy(page.switchModel:IsShown(), "only once")
		end)

		t:it("keeps an older character's story back until the one-time confirmation; the retired "
			.. "visibility command changes nothing", function()
			local mock, env, ns, fake = start()
			mock.Slash("set name Lirael")
			ns.Actions.WithCharacter(ns.ctx, function(c)
				return ns.Sources.Capture(c, "paste", "An older story.", nil, 5)
			end)
			expect.truthy(mock.Slash("biography status"):find("saved verbatim.", 1, true))
			mock.Slash("trp3 enable about confirm")
			mock.Slash("story set trp3About profile")
			mock.RunTimers()
			expect.falsy(fake.profile.player.about.T1.TX:find("An older story", 1, true), "kept back: never sent")
			expect.truthy(mock.Slash("biography public"):find(ns.Commands.RETIRED_VISIBILITY, 1, true))
			mock.RunTimers()
			expect.falsy(fake.profile.player.about.T1.TX:find("An older story", 1, true), "still kept back")
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			expect.equal(char.sources.visibility, "private", "nothing changed")
			mock.Slash("publish confirm")
			mock.RunTimers()
			expect.truthy(fake.profile.player.about.T1.TX:find("An older story.", 1, true))
			expect.equal(char.sources.visibility, "private", "the stored value is kept; it no longer decides")
		end)
	end)
end

-- These specs model characters an earlier version created (Loader.Legacy).
return function(t, expect)
	Loader.Legacy(function() legacySpec(t, expect) end)
end
