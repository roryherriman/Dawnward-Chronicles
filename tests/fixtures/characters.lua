-- Simulation fixtures: varied characters across classes, races, factions
-- and personality archetypes. Tokens are the ones the client returns
-- (UnitClass / UnitRace file names, UnitFactionGroup). Personalities are
-- deliberately set against class stereotypes: the systems under test must
-- treat every one of these the same way.
local Fixtures = {}

Fixtures.CHARACTERS = {
	{ key = "Aldric-Test", name = "Aldric", class = "PALADIN", race = "Human", faction = "Alliance",
		archetype = "ruthless paladin", personality = { compassion = 3, honour = 4, faith = 6 } },
	{ key = "Grasha-Test", name = "Grasha", class = "WARLOCK", race = "Orc", faction = "Horde",
		archetype = "compassionate warlock", personality = { compassion = 18, faith = 9 } },
	{ key = "Lirael-Test", name = "Lirael", class = "DRUID", race = "NightElf", faction = "Alliance",
		archetype = "restless druid", personality = { discipline = 4, sociability = 15 } },
	{ key = "Morrow-Test", name = "Morrow", class = "ROGUE", race = "Scourge", faction = "Horde",
		archetype = "principled rogue", personality = { honour = 17, courage = 12 } },
	{ key = "Brannoc-Test", name = "Brannoc", class = "PRIEST", race = "Dwarf", faction = "Alliance",
		archetype = "sceptical priest", personality = { faith = 2 } },
	{ key = "Thunu-Test", name = "Thunu", class = "WARRIOR", race = "Tauren", faction = "Horde",
		archetype = "cowardly warrior", personality = { courage = 2 } },
	{ key = "Fizzwick-Test", name = "Fizzwick", class = "MAGE", race = "Gnome", faction = "Alliance",
		archetype = "impulsive mage", personality = { discipline = 1 } },
	{ key = "Zanjin-Test", name = "Zanjin", class = "SHAMAN", race = "Troll", faction = "Horde",
		archetype = "reserved shaman", personality = { sociability = 3 } },
	{ key = "Sylwen-Test", name = "Sylwen", class = "HUNTER", race = "NightElf", faction = "Alliance",
		archetype = "no personality set yet", personality = {} },
	{ key = "Vex-Test", name = nil, class = "MAGE", race = "Scourge", faction = "Horde",
		archetype = "unnamed character", personality = {} },
}

--- A fresh character for a fixture in namespace ns.
function Fixtures.Character(ns, fixture, now)
	local char = ns.Schema.NewCharacter(now or 1)
	if fixture.name then
		char.fields.name = { value = fixture.name, visibility = "public" }
	end
	for axis, value in pairs(fixture.personality or {}) do
		char.personality[axis] = { value = value, visibility = "private", updatedAt = 1 }
	end
	return char
end

--- Event context data for a fixture.
function Fixtures.Context(fixture, overrides)
	local data = { zone = fixture.faction == "Horde" and "The Barrens" or "Westfall", level = 20,
		class = fixture.class, race = fixture.race, faction = fixture.faction }
	for k, v in pairs(overrides or {}) do
		data[k] = v
	end
	return data
end

return Fixtures
