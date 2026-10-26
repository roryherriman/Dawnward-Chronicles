# Story prompt and decision engine

The goal is contextual, personal prompts without AI, using a curated library of templates, explicit conditions, weighting and the character's own history. The selection is deterministic, so it can be tested.

## 1. Moments (the queue)
An **experience** (an observed event) may become a **moment**, something worth asking about.

- **Significance rules** (data in `Content/Prompts/rules.lua`) decide whether an experience is worth asking about. Examples: level ∈ {10, 20, …}; first entry to an instance; `ENCOUNTER_END` with success; standing reaches Honored; first death in a zone; a player-pinned quest.
- **Coalescing:** several experiences close together become one moment. For example, five quest turn-ins in Westfall become "your work in Westfall".
- **Rate limits:**
  - **Frequency setting:** Off / Rare (at most 1 per ~2 hours of play) / **Normal** (~1 per 45 minutes) / Frequent (~1 per 20 minutes).
  - **Per-category cooldowns.**
  - **Never more than one waiting prompt notice at a time.**
- **Queue:** at most 20 moments. Each **expires** (for example after 7 days, or when the context is stale). Older, low-significance moments drop first.
- **Player controls:** on every prompt, **Decide**, **Later** (postpone, which keeps it in the Story section), **Dismiss** and **Fewer like this** (mutes the category). Frequency and muted categories live in the existing settings panel.

## 2. Prompt templates (data, not code)
```lua
-- Content/Prompts/victory.lua (illustrative)
{
	id = "victory.boss.meaning",
	triggers = { "encounter_success" },
	conditions = {                       -- all optional; any unmet condition skips the template
		levelAtLeast = 20,
		notRecentlyUsed = 3,             -- not among the last 3 prompts shown
		mood = { notIn = { "grieving" } },
	},
	weight = 10,
	question = {
		"What does this victory mean to {name}?",
		"{name} stands over {enemy}. What stays with {them}?",           -- variants
	},
	options = {
		{ id = "pride", text = "Pride: {they} feel{s} closer to who {they} hope{s} to become.",
		  tags = { "pride" }, effects = { mood = "proud", tend = { confidence = 2 } },
		  journal = "{name} took pride in defeating {enemy}." },
		{ id = "humility", text = "Humility: {they} remember{s} those who suffered, and recommit{s} to protecting others.",
		  tags = { "duty", "compassion" }, effects = { mood = "determined", tend = { compassion = 2, duty = 1 } },
		  journal = "After {enemy}, {name} thought of those who could not be saved." },
		{ id = "unease", text = "Unease: the victory shows how much darkness remains.",
		  tags = { "doubt" }, effects = { mood = "unsettled", tend = { caution = 2 } },
		  journal = "{name} found little comfort in the victory over {enemy}." },
		{ id = "none", text = "No lasting change: just another battle on a long road.",
		  tags = {}, effects = {}, journal = "{name} defeated {enemy}." , neutral = true },
	},
	callbacks = {                         -- optional extra option, only if history supports it
		{ when = { decisionTag = "duty", within = 5 },
		  text = "{name} remembers the vow made after {lastDutyMoment}." },
	},
}
```

- **Tokens:** `{name}`, `{enemy}`, `{zone}`, `{level}`, `{faction}`, and pronoun tokens such as `{they}`/`{them}`/`{s}`.
  - Tokens are filled from **observed data** and **canon** only.
  - Pronouns come from the character's own pronouns field; without one, templates use the name, so they never guess gender.
- **Rules every template must follow:**
  - **at least one neutral or "no lasting change" option**;
  - **no option that implies a class or race personality**;
  - effects are **small** (tendency nudges of 1–3 on a ±100 scale).

## 3. Selection: where the variety comes from
For a moment, Dawnward:

1. **Filters** the templates whose trigger and conditions match the moment and the character.
2. **Scores** each remaining template:

   `weight × novelty × relevance × variety`

   | Factor | What it does |
   |---|---|
   | **Novelty** | Strongly lowers templates and phrasings used recently; never repeats the last N |
   | **Relevance** | Boosts templates that reference the character's **canon** (an approved relationship, belief or fear), **current mood**, or **recent decisions** |
   | **Variety** | Small penalty for asking the same *kind* of question as the last prompt (meaning, emotion, relationship, future) |

3. **Picks** with a **seeded weighted choice** (seed = moment ID + character key), so the same state always gives the same prompt. That makes it testable and avoids "reroll" exploits.
4. **Assembles the options:**
   - the template's options;
   - **conditional options**, shown only when canon supports them (for example "Think of {sibling}");
   - **callbacks** to earlier decisions;
   - always the neutral option.

   It shows 3–4 options and keeps both "aligned" and "contrary" reactions, so it never railroads a character toward existing tendencies.

**What this achieves:** prompts differ by event, place, enemy, mood, canon and history. With about 60 templates × 2–3 phrasings × conditional options, a character sees a wide variety early on.

**Honest limit:** over a long time, phrasings will repeat. More content packs, rather than AI, address that.

## 4. Decisions
A decision records `{ momentId, templateId, optionId, at, context (zone, level, enemy…), effects }`.

**When the player decides:**
1. **Journal:** an entry appears with **two parts**, the *event* (automatic, factual) and the *reaction* (the chosen option's phrasing, attributed to the decision). Experience and interpretation stay visibly separate.
2. **Mood:** set or blended.
3. **Tendencies:** nudged (see `evolution-model.md`).
4. **Canon effects:** if an option is explicitly labelled with one (for example "Make this a vow"), it records a fact with provenance `decision:<id>`. Any other implication only becomes an **interpretation** for review.
5. **Publication:** if the resulting category is set to **auto** *and* the prompt displayed the public badge on that option, the development may be published (see `trp3-sync.md`).

**Afterwards:**
- **Review:** the Story section lists pending moments and the decision history (newest first, paged like the journal).
- **Undo** reverses the last decision's effects. Earlier decisions can be *annotated*, not rewritten.

## 5. What it will not do
- Make decisions for the player, or change personality without a decision or approval.
- Treat every character the same: options and weights depend on that character's canon, mood and history.
- Generate free prose. All text comes from authored fragments plus observed data.
