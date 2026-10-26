-- Authored reaction templates: the questions Dawnward may ask after an
-- event, and the answers it offers. Data only.
--
-- Universal by design. These rules are enforced by
-- tests/spec/core_reactions_spec.lua:
--   * no template, option or phrase names a class, race, faction, city,
--     deity or the Light, or assumes the character is good, heroic,
--     religious, honourable or merciful;
--   * every template offers answers pulling in different moral and
--     emotional directions, plus a neutral "nothing worth remembering";
--   * effects are small (-1 or +1 on at most two axes) and only ever
--     proposals the player approves;
--   * text refers to the character by name ({name}) and "they", never by a
--     guessed gender.
--   * each answer may carry a `theme`: a neutral word for what the answer is
--     about, used to notice patterns across the player's own answers.
--
-- Questions have variants with the tokens they need ({title}, {zone},
-- {level}); a variant is used only when every token it needs is verified,
-- so an uncertain event gets a neutral, reusable question instead.
--
-- FLAVOR adds one optional extra answer for some classes. It never removes
-- or changes the universal answers, carries no personality effect, and can
-- be switched off. Class never decides what a character is like.
local _, ns = ...

local ReactionLibrary = {}
ns.ReactionLibrary = ReactionLibrary

-- The neutral answer every template ends with.
ReactionLibrary.NEUTRAL = {
	id = "nothing", text = "Nothing worth remembering.",
	phrase = "felt it was nothing worth remembering", effects = {},
}

ReactionLibrary.TEMPLATES = {
	{
		id = "quest.meaning", category = "quest", minSignificance = 1,
		questions = {
			{ text = "{name} has finished \"{title}\" in {zone}. How did it sit with them?", needs = { "title", "zone" } },
			{ text = "{name} has finished \"{title}\". How did it sit with them?", needs = { "title" } },
			{ text = "{name} has seen another task through in {zone}. How did it sit with them?", needs = { "zone" } },
			{ text = "{name} has seen another task through. How did it sit with them?", needs = {} },
		},
		options = {
			{ id = "resolve", theme = "protecting others", text = "It strengthened their resolve to help those who need it.",
				phrase = "felt their resolve to help others grow", effects = { compassion = 1 },
				meaning = "It may shape how they answer the next call for help." },
			{ id = "doubt", theme = "doubt", text = "It made them question whether their efforts really matter.",
				phrase = "wondered whether their efforts really matter", effects = { faith = -1 },
				meaning = "The doubt may linger." },
			{ id = "ambition", theme = "ambition", text = "They saw it as one more step toward their own ambitions.",
				phrase = "saw it as one more step toward their own ambitions", effects = { honour = -1 },
				meaning = "Their own goals come first." },
			{ id = "craft", theme = "craftsmanship", text = "They took quiet pride in a job done properly.",
				phrase = "took quiet pride in a job done properly", effects = { discipline = 1 },
				meaning = "Doing things properly matters to them." },
		},
	},
	{
		id = "quest.company", category = "quest", minSignificance = 1,
		questions = {
			{ text = "Who was on {name}'s mind after \"{title}\"?", needs = { "title" } },
			{ text = "Who was on {name}'s mind after their work in {zone}?", needs = { "zone" } },
			{ text = "Who was on {name}'s mind after their latest task?", needs = {} },
		},
		options = {
			{ id = "alone", theme = "solitude", text = "No one. They prefer to work alone.",
				phrase = "was glad to have done it alone", effects = { sociability = -1 },
				meaning = "They keep their own counsel." },
			{ id = "company", theme = "companionship", text = "They wished they had shared the road with someone.",
				phrase = "wished they had shared the road with someone", effects = { sociability = 1 },
				meaning = "They may look for company on the road ahead." },
			{ id = "lost", theme = "loss", text = "Someone they have lost.",
				phrase = "thought of someone they have lost", effects = {},
				meaning = "An old loss still travels with them." },
			{ id = "owed", theme = "debts", text = "Only whoever owes them for it.",
				phrase = "thought mostly of what they were owed", effects = { compassion = -1 },
				meaning = "They keep count of debts." },
		},
	},
	{
		id = "quest.challenge", category = "quest", minSignificance = 2,
		-- Only for a verified challenge: the quest was well above the character's level.
		when = function(record)
			local q, l = record.meta and record.meta.questLevel, record.level
			return q ~= nil and l ~= nil and q >= l + 2
		end,
		questions = {
			{ text = "\"{title}\" asked a lot of {name}. What did they take from it?", needs = { "title" } },
			{ text = "That task in {zone} asked a lot of {name}. What did they take from it?", needs = { "zone" } },
			{ text = "That task asked a lot of {name}. What did they take from it?", needs = {} },
		},
		options = {
			{ id = "bold", theme = "daring", text = "That they can face more than they thought.",
				phrase = "learned they can face more than they thought", effects = { courage = 1 },
				meaning = "They may take bigger risks." },
			{ id = "careful", theme = "caution", text = "That they should be more careful next time.",
				phrase = "resolved to be more careful next time", effects = { courage = -1 },
				meaning = "Caution may serve them well." },
			{ id = "prepared", theme = "preparation", text = "That preparation won the day, not luck.",
				phrase = "credited preparation, not luck", effects = { discipline = 1 },
				meaning = "They trust in preparation." },
			{ id = "chance", theme = "fortune", text = "That chance carried them more than skill.",
				phrase = "suspected that chance carried them", effects = { discipline = -1 },
				meaning = "They know how thin the line can be." },
		},
	},
	{
		id = "levelup.strength", category = "levelup", minSignificance = 2,
		questions = {
			{ text = "{name} has grown stronger (level {level}). What does that strength mean to them?",
				needs = { "level" } },
			{ text = "{name} has grown stronger. What does that strength mean to them?", needs = {} },
		},
		options = {
			{ id = "protect", theme = "responsibility", text = "A responsibility to those weaker than them.",
				phrase = "felt their new strength as a responsibility to others", effects = { honour = 1 },
				meaning = "Others may come to rely on them." },
			{ id = "freedom", theme = "freedom", text = "Freedom: fewer people can tell them what to do.",
				phrase = "relished the freedom their strength brings", effects = { discipline = -1 },
				meaning = "They answer to fewer people now." },
			{ id = "proof", theme = "ambition", text = "Proof that they are meant for more.",
				phrase = "took it as proof they are meant for more", effects = { courage = 1 },
				meaning = "Their ambitions may grow with them." },
			{ id = "burden", theme = "burden", text = "A weight they never asked for.",
				phrase = "felt it as a weight they never asked for", effects = {},
				meaning = "Strength has a cost they feel." },
		},
	},
	{
		id = "death.return", category = "death", minSignificance = 2,
		questions = {
			{ text = "{name} fell in {zone} and came back. How did it change them?", needs = { "zone" } },
			{ text = "{name} fell and came back. How did it change them?", needs = {} },
		},
		options = {
			{ id = "careful", theme = "caution", text = "They will be more careful from now on.",
				phrase = "came back more careful", effects = { courage = -1 },
				meaning = "Caution may keep them alive." },
			{ id = "defiant", theme = "defiance", text = "It only made them more determined.",
				phrase = "came back more determined", effects = { courage = 1 },
				meaning = "Defeat feeds their determination." },
			{ id = "shaken", theme = "doubt", text = "It shook what they believe in.",
				phrase = "found their beliefs shaken", effects = { faith = -1 },
				meaning = "What they believe may be changing." },
			{ id = "convinced", theme = "conviction", text = "It strengthened their convictions.",
				phrase = "came back surer of their convictions", effects = { faith = 1 },
				meaning = "Their convictions run deeper now." },
		},
	},
}

-- Optional class-flavoured extra answers (UnitClass file tokens). One per
-- class, for quests only, with no personality effect. Every Classic Era
-- class is listed so no class is singled out.
ReactionLibrary.FLAVOR = {
	quest = {
		WARRIOR = { id = "flavor.warrior", text = "They measured it as a test of their own strength.",
			phrase = "measured it as a test of their own strength" },
		PALADIN = { id = "flavor.paladin", text = "They weighed it against whatever code they live by.",
			phrase = "weighed it against the code they live by" },
		HUNTER = { id = "flavor.hunter", text = "They thought about the land and the creatures in it.",
			phrase = "thought about the land and the creatures in it" },
		ROGUE = { id = "flavor.rogue", text = "They counted what they gained, and who paid for it.",
			phrase = "counted what they gained, and who paid for it" },
		PRIEST = { id = "flavor.priest", text = "They looked for meaning in it, whatever they believe.",
			phrase = "looked for meaning in it" },
		SHAMAN = { id = "flavor.shaman", text = "They wondered what balance it upset or restored.",
			phrase = "wondered what balance it upset or restored" },
		MAGE = { id = "flavor.mage", text = "What they learned interested them more than the reward.",
			phrase = "cared more for what they learned than the reward" },
		WARLOCK = { id = "flavor.warlock", text = "They wondered what power could be drawn from it.",
			phrase = "wondered what power could be drawn from it" },
		DRUID = { id = "flavor.druid", text = "They thought about what it meant for the wild places.",
			phrase = "thought about what it meant for the wild places" },
	},
}

ReactionLibrary.BY_ID = {}
for _, template in ipairs(ReactionLibrary.TEMPLATES) do
	ReactionLibrary.BY_ID[template.id] = template
end

--- Templates for an event record that a reaction of this significance may
-- use, in library order. A template with a `when` condition applies only
-- when the record's verified data satisfies it.
function ReactionLibrary.For(category, significance, record)
	local out = {}
	for _, template in ipairs(ReactionLibrary.TEMPLATES) do
		if template.category == category and (significance or 1) >= template.minSignificance
			and (not template.when or (record ~= nil and template.when(record))) then
			out[#out + 1] = template
		end
	end
	return out
end

function ReactionLibrary.Flavor(category, classToken)
	local byClass = ReactionLibrary.FLAVOR[category]
	local option = byClass and classToken and byClass[classToken]
	if not option then
		return nil
	end
	return { id = option.id, text = option.text, phrase = option.phrase, effects = {}, flavor = true }
end
