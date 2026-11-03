-- L1/L2 (v0.10.3): the shared pronoun formatter (Core/Pronouns.lua) and every
-- generator that names the character: Story Director questions, answers
-- and echoes, journal drafts, memories, development reasons, arcs,
-- continuity findings and profile suggestions. Failing first: before
-- v0.10.3 a "She/Her" character read "the freedom their strength brings".
local Loader = require("support.loader")

return function(t, expect)
	local function char(ns, name, pronouns)
		local c = ns.Schema.NewCharacter(1)
		if name then c.fields.name = { value = name, visibility = "public" } end
		if pronouns then c.fields.pronouns = { value = pronouns, visibility = "public" } end
		return c
	end

	t:describe("reading the Pronouns field", function()
		t:it("knows she, he, they and it in the ways players write them", function()
			local P = Loader.Core().Pronouns
			for value, subject in pairs({ ["She/Her"] = "she", ["she/her/hers"] = "she", ["SHE / HER"] = "she",
				["he/him"] = "he", ["He/Him/His"] = "he", ["they/them"] = "they", ["They/Them/Theirs"] = "they",
				["it/its"] = "it", ["she/they"] = "she", ["she/her (Kyss)"] = "she", ["  he  "] = "he" }) do
				local set = P.Parse(value)
				expect.truthy(set, value)
				expect.equal(set.they, subject, value)
			end
		end)

		t:it("reads a complete custom set of five, and nothing less", function()
			local P = Loader.Core().Pronouns
			local xe = P.Parse("xe/xem/xyr/xyrs/xemself")
			expect.deepEqual(xe, { they = "xe", them = "xem", their = "xyr", theirs = "xyrs", themselves = "xemself" })
			for _, unsafe in ipairs({ "xe/xem", "xe/xem/xyr", "any", "any/all", "her/she", "she/xe", "", "   ",
				"ask me", "xe/xem/xyr/xyrs/xem", "she/her/xyr/xyrs/xemself" }) do
				expect.equal(P.Parse(unsafe), nil, "unsupported: " .. unsafe)
			end
			expect.equal(P.Parse(nil), nil)
			expect.equal(P.Parse(42), nil)
		end)

		t:it("never guesses from race, class or name", function()
			local ns = Loader.Core()
			local c = char(ns, "Kyssarra Dawnward")
			c.fields.race = { value = "Human", visibility = "public" }
			local forms = ns.Pronouns.For(c)
			expect.falsy(forms.known)
			expect.equal(forms.their, "Kyssarra's", "the name stands in, never a guessed pronoun")
		end)
	end)

	t:describe("rendering", function()
		t:it("Kyssarra Dawnward continued her training", function()
			local ns = Loader.Core()
			local c = char(ns, "Kyssarra Dawnward", "She/Her")
			expect.equal(ns.Pronouns.Text(c, "Kyssarra Dawnward continued {their} training."),
				"Kyssarra Dawnward continued her training.")
			expect.equal(ns.Pronouns.Text(char(ns, "Aldric", "he/him"), "Aldric continued {their} training."),
				"Aldric continued his training.")
			expect.equal(ns.Pronouns.Text(char(ns, "Lirael", "they/them"), "Lirael continued {their} training."),
				"Lirael continued their training.")
		end)

		t:it("keeps the possessive determiner, the possessive pronoun, the object and the reflexive apart", function()
			local ns = Loader.Core()
			local text = "The choice was {theirs}: {their} blade, {their} vow. It changed {them}; {they} kept it to "
				.. "{themselves}."
			expect.equal(ns.Pronouns.Text(char(ns, "K", "she/her"), text),
				"The choice was hers: her blade, her vow. It changed her; she kept it to herself.")
			expect.equal(ns.Pronouns.Text(char(ns, "A", "he/him"), text),
				"The choice was his: his blade, his vow. It changed him; he kept it to himself.")
			expect.equal(ns.Pronouns.Text(char(ns, "L", "they/them"), text),
				"The choice was theirs: their blade, their vow. It changed them; they kept it to themselves.")
			expect.equal(ns.Pronouns.Text(char(ns, "X", "xe/xem/xyr/xyrs/xemself"), text),
				"The choice was xyrs: xyr blade, xyr vow. It changed xem; xe kept it to xemself.")
		end)

		t:it("capitalises at the start of a sentence and for a capitalised token only", function()
			local ns = Loader.Core()
			local she = char(ns, "K", "she/her")
			expect.equal(ns.Pronouns.Text(she, "{they} {are} ready. {their} blade is sharp! {they} wait{s}.\n{them}"),
				"She is ready. Her blade is sharp! She waits.\nHer")
			expect.equal(ns.Pronouns.Text(she, "Curious: {they} want{s} to see it."), "Curious: she wants to see it.",
				"after a colon the sentence goes on")
			expect.equal(ns.Pronouns.Text(she, "Still, {They} said so."), "Still, She said so.")
		end)

		t:it("makes the verbs agree: they are, she is; they have, he has", function()
			local ns = Loader.Core()
			local text = "{They} {are} here and {have} time; {they} {were} owed, {do} not rest and keep{s} watch."
			expect.equal(ns.Pronouns.Text(char(ns, "L", "they/them"), text),
				"They are here and have time; they were owed, do not rest and keep watch.")
			expect.equal(ns.Pronouns.Text(char(ns, "K", "she/her"), text),
				"She is here and has time; she was owed, does not rest and keeps watch.")
			expect.equal(ns.Pronouns.Text(char(ns, "A", "He/Him"), text),
				"He is here and has time; he was owed, does not rest and keeps watch.")
			expect.equal(ns.Pronouns.Text(char(ns, "X", "xe/xem/xyr/xyrs/xemself"), "{They} {are} here."),
				"Xe is here.", "a custom set takes singular verbs")
		end)

		t:it("without readable pronouns, uses the name (or your character), never they for she", function()
			local ns = Loader.Core()
			local named = char(ns, "Kyssarra Dawnward")
			expect.equal(ns.Pronouns.Text(named, "Kyssarra Dawnward continued {their} training. {They} {are} ready."),
				"Kyssarra Dawnward continued Kyssarra's training. Kyssarra is ready.")
			local odd = char(ns, "Kyssarra Dawnward", "any/all")
			expect.equal(ns.Pronouns.Text(odd, "It mattered to {them}."), "It mattered to Kyssarra.")
			local nobody = char(ns, nil, nil)
			expect.equal(ns.Pronouns.Text(nobody, "{They} keep{s} {their} word. It is {theirs}."),
				"Your character keeps your character's word. It is your character's.")
			expect.equal(ns.Pronouns.Name(nobody), "Your character")
		end)

		t:it("leaves other tokens and the player's own braces alone", function()
			local ns = Loader.Core()
			local she = char(ns, "K", "she/her")
			expect.equal(ns.Pronouns.Text(she, "{name} reached {zone}; {their} {unknown}."),
				"{name} reached {zone}; her {unknown}.")
			local braces = char(ns, "Ky{they}ss%a", nil)
			expect.equal(ns.Pronouns.Text(braces, "{their} sword"), "Kytheyssa's sword",
				"a name never becomes a token or a format")
		end)

		t:it("keeps secret pronouns out of public text, if asked", function()
			local ns = Loader.Core()
			local c = char(ns, "Kyssarra", "she/her")
			c.fields.pronouns.visibility = "secret"
			expect.equal(ns.Pronouns.For(c, { public = true, neutral = true }).their, "their")
			expect.equal(ns.Pronouns.For(c).their, "her", "private text may use them")
		end)
	end)

	t:describe("every generator uses the profile's pronouns", function()
		local function levelFive(ns, c)
			local record = assert(ns.GameEvents.Record(c, "levelup", { level = 5, zone = "Elwynn Forest" }, 100))
			return assert(ns.Reactions.Consider(c, record, 100, 100))
		end

		t:it("Story Director question, answers, draft, memory and development reason (she/her)", function()
			local ns = Loader.WithTRP3()
			local c = char(ns, "Kyssarra Dawnward", "She/Her")
			local reaction = levelFive(ns, c)
			local view = ns.Reactions.Present(c, reaction)
			expect.equal(view.question, "Kyssarra Dawnward has grown stronger (level 5). What does that strength mean "
				.. "to her?")
			local freedom = ns.Reactions.FindOption(view, "freedom")
			expect.equal(freedom.text, "Freedom: fewer people can tell her what to do.")
			expect.equal(freedom.phrase, "relished the freedom her strength brings")
			expect.equal(freedom.meaning, "She answers to fewer people now.")
			expect.equal(ns.ReactionLibrary.BY_ID["levelup.strength"].options[2].phrase,
				"relished the freedom {their} strength brings", "the library keeps its tokens")
			local result = assert(ns.Decisions.Decide(c, reaction.id, { optionId = "freedom" }, 101))
			expect.equal(result.decision.phrase, "relished the freedom her strength brings")
			expect.truthy(result.entry.text:find("Kyssarra Dawnward relished the freedom her strength brings.", 1, true),
				result.entry.text)
			expect.equal(result.memory.text, "Kyssarra Dawnward relished the freedom her strength brings.")
			expect.equal(result.changes[1].reason, "Kyssarra Dawnward relished the freedom her strength brings")
			for _, text in ipairs({ view.question, result.entry.text, result.memory.text, result.changes[1].reason }) do
				expect.falsy(text:find("%f[%a]their%f[%A]") or text:find("%f[%a]them%f[%A]"), text)
			end
		end)

		t:it("he/him and they/them read the same answers in their own words", function()
			local ns = Loader.WithTRP3()
			local he = char(ns, "Aldric", "he/him")
			local view = ns.Reactions.Present(he, levelFive(ns, he))
			expect.equal(ns.Reactions.FindOption(view, "proof").text, "Proof that he is meant for more.")
			local they = char(ns, "Lirael", "they/them")
			view = ns.Reactions.Present(they, levelFive(ns, they))
			expect.equal(ns.Reactions.FindOption(view, "proof").text, "Proof that they are meant for more.")
			expect.equal(ns.Reactions.FindOption(view, "freedom").meaning, "They answer to fewer people now.")
		end)

		t:it("echoes an older answer stored with a literal 'their' in her pronouns, without rewriting it", function()
			local ns = Loader.Core()
			local c = char(ns, "Kyssarra Dawnward", "She/Her")
			local old = assert(ns.GameEvents.Record(c, "quest", { questId = 7, title = "Kobold Camp Cleanup",
				zone = "Elwynn Forest", level = 2 }, 10))
			c.story.decisions[1] = { id = 5, category = "quest", eventKeys = { old.key }, templateId = "quest.meaning",
				optionId = "resolve", phrase = "felt their resolve to help others grow", at = 11, effects = {} }
			local now = assert(ns.GameEvents.Record(c, "quest", { questId = 8, title = "Investigate Echo Ridge",
				zone = "Elwynn Forest", level = 3 }, 9000))
			local echo = ns.Director.Echo(c, now, ns.ReactionLibrary.BY_ID["quest.meaning"])
			expect.equal(echo, "Kyssarra Dawnward felt her resolve to help others grow")
			expect.equal(c.story.decisions[1].phrase, "felt their resolve to help others grow", "stored text unchanged")
		end)

		t:it("context answers, arcs and continuity findings use her pronouns", function()
			local ns = Loader.WithTRP3()
			local c = char(ns, "Kyssarra Dawnward", "she/her")
			assert(ns.Goals.Add(c, { title = "Earn a place in the Order" }, 1))
			local record = assert(ns.GameEvents.Record(c, "quest", { questId = 9, title = "Q", zone = "Elwynn Forest",
				level = 3 }, 10))
			local reaction = assert(ns.Reactions.Consider(c, record, 10, 10))
			local texts = {}
			for _, o in ipairs(ns.Reactions.Present(c, reaction).options) do texts[o.text] = true end
			expect.truthy(texts["It mattered to her goal: Earn a place in the Order."])
			assert(ns.Identity.Add(c, { subject = "Stormwind", persona = "Loyal", conviction = "Wary" }, 2))
			local found
			for _, f in ipairs(ns.Continuity.Findings(c)) do
				if f.kind == "persona" then found = f.message end
			end
			expect.equal(found, "About Stormwind, she says \"Loyal\" in public but believes \"Wary\".")
			for i = 1, ns.Arcs.PATTERN do
				c.story.decisions[#c.story.decisions + 1] = { id = 100 + i, theme = "duty", at = i, effects = {},
					eventKeys = {} }
			end
			local arc = assert(ns.Arcs.SuggestFromPattern(c, 50))
			expect.equal(arc.summary, "Several of your answers share this theme. Is it part of who she is becoming?")
		end)

		t:it("profile suggestions read custom and known sets through the same formatter", function()
			local ns = Loader.WithTRP3()
			local PS = ns.ProfileSuggestions
			local voice = PS.Voice(char(ns, nil, "xe/xem/xyr/xyrs/xemself"))
			expect.equal(PS.Render("{S} {has} grown; it shows in {p} manner and suits {o}.", voice),
				"Xe has grown; it shows in xyr manner and suits xem.")
			voice = PS.Voice(char(ns, nil, "She/Her"))
			expect.equal(PS.Render("{S} {has} grown.", voice), "She has grown.")
			voice = PS.Voice(char(ns, nil, nil))
			expect.equal(PS.Render("{S} {has} grown, in {p} way.", voice), "They have grown, in their way.",
				"public text without a name or pronouns stays neutral")
		end)
	end)
end
