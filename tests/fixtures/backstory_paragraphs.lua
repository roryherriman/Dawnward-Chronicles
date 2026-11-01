-- A stand-in backstory for the biography regression tests (tests/spec/
-- trp3_biography_regression_spec.lua). It is written for the tests and is
-- nobody's canon. It copies only the shape of the owner's real backstory,
-- which is not in the repository: a title line with an em dash, then plain
-- paragraphs separated by blank lines, with no headings, several one-line
-- paragraphs, apostrophes and about 3 KB of text. When the owner's copy is
-- at private/fixtures/kyssarra_backstory.txt (git-ignored), the same tests
-- also run against it.
local paragraphs = {
	"Tamsin Greyhollow \226\128\148 The Long Road Home",
	"Tamsin Greyhollow was born in a mill town on the edge of Hillsbrad, the daughter of a carter and a "
		.. "midwife. The Greyhollows were not wealthy or well known. People knew them for turning up when "
		.. "they were needed, and for leaving before anyone thought to thank them.",
	"Her father drove grain to the towns along the coast road. Her mother delivered half the children of "
		.. "the valley and taught Tamsin that patience was a kind of strength.",
	"From an early age Tamsin learned letters from the town's old scribe. She was quick with numbers and "
		.. "expected to keep the mill's accounts one day. She believed that careful records could keep "
		.. "almost any trouble from growing.",
	"That belief did not survive the dry year.",
	"When the river fell and the mill wheel stopped, the town argued over every sack of grain. Her father "
		.. "set out for the coast to buy more, though the roads were no longer safe.",
	"He told her to keep the ledger honest while he was gone.",
	"She did, but the ledger could not feed anyone.",
	"To Tamsin, the hungry winter that followed was not only bad luck. It was a sum she believed she should "
		.. "have worked out sooner. She had spent years learning to count what the town had, yet when it "
		.. "mattered most, the numbers had only told her what was already lost.",
	"Her father came home in the spring, thinner and quieter, and the family moved south to Southshore, "
		.. "where her mother found work at the chapel.",
	"The new town offered work, but not rest. Tamsin carried the old ledger with her, its last page still "
		.. "blank, and the question of whether she had counted the right things.",
	"Over time, her idea of what keeping accounts meant began to change.",
	"She still believed in records. She still believed in fairness. But she had come to doubt that a list "
		.. "on its own ever kept anyone fed.",
	"Her town had not starved because no one counted. Tamsin decided that she would be the one who carried "
		.. "the grain, not just the one who wrote it down.",
	"She chose to take up the road her father had travelled, with a cart, a ledger and a map she had yet "
		.. "to fill in.",
	"Now, at the start of her travels, Tamsin is an untested trader with a careful mind. She wants to be "
		.. "generous but worries about getting it wrong. She trusts numbers but privately wonders whether they "
		.. "can ever be enough. She wants to make her family proud without being sure what that would take.",
	"She has not yet become the person she means to be.",
	"The rest of the ledger is still blank.",
}

return table.concat(paragraphs, "\n\n") .. "\n"
