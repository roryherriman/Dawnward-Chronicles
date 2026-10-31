-- A long, multi-section biography used by the About tests (v0.9). It is a
-- stand-in written for the tests, not any player's canon: the owner's real
-- backstory (Kyssarra Dawnward) is not in the repository. When a copy of it
-- is placed at private/fixtures/kyssarra_backstory.txt (git-ignored), the
-- same tests also run against it (tests/spec/trp3_about_doc_spec.lua).
--
-- It deliberately has: text before the first heading, Markdown and TRP3
-- heading lines, several paragraphs per section, a blank line inside a
-- section, a line with literal braces, accented letters and a long section.
local paragraphs = {
	"Mirelle Ashvale was born in the last quiet years before the plague, in a stone house above the river "
		.. "fields of Darrowshire. Her mother kept bees; her father mended carts and said little.",
	"She remembers the smell of smoke on the wind long before she understood what it meant.",
	"# The fall of Lordaeron",
	"When the grain carts came back from Andorhal, the sickness came with them. Within a season the village "
		.. "chapel had become a hospital, then a barracks, then nothing at all.",
	"Mirelle carried water for the wounded until there were no wounded left to carry it to. She was fourteen.",
	"",
	"The night the walls fell she hid in the root cellar with her younger brother, counting heartbeats instead "
		.. "of footsteps, until the silence outside was worse than any sound.",
	"## Family",
	"Her brother Tomas survived with her. Of the rest, she found only her mother's hive tools, "
		.. "still wrapped in oilcloth {as if someone meant to come back for them}.",
	"{h2}Beliefs and motivations{/h2}",
	"She does not believe the Light abandoned Lordaeron. She believes people did, and that a person can choose "
		.. "not to. Every oath she has taken since is a version of that choice.",
	"Café owners in Stormwind still remember the quiet girl who paid for her bread in Lordaeron silver.",
	"# Defining experiences",
}
-- A long section: a dozen paragraphs of the same register.
for i = 1, 12 do
	paragraphs[#paragraphs + 1] = string.format("Year %d after the fall: she walked another road east, helped "
		.. "another family bury what they could not carry, and wrote their names in the small book she keeps for "
		.. "that purpose. Entry %d of the book reads only: they were here, and someone remembers.", i, i)
end
return table.concat(paragraphs, "\n")
