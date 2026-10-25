# Character evolution model

## Goals
- Development is **cumulative and gradual**: one decision never transforms a personality.
- **Temporary feelings stay temporary** unless the player makes them lasting.
- The player sees **words, not numbers**, and can adjust things simply.

## Three moving parts

### 1. Mood (emotional state, temporary)
- **One** current mood from a small set: proud, determined, hopeful, content, weary, unsettled, grieving, angry, shaken.
- It has an **intensity** (low / medium / high) and **fades** with time played and real time (for example one step per hour of play, or per day).
- **Set by** decision effects and some experiences: a death can suggest "shaken", but only if the player picks that reaction.
- **Used for:**
  - weighting prompts;
  - Currently suggestions ("Still shaken after Stratholme");
  - journal colour.
- **Never** turns into a trait by itself.

### 2. Tendencies (long-term leanings)
A small, extensible set of **bipolar axes**. Each has two respectable poles (neither is "good" or "bad"):

| Axis | − pole | + pole |
|---|---|---|
| confidence | doubtful | assured |
| compassion | detached | compassionate |
| caution | bold | cautious |
| ambition | content | driven |
| duty | free-spirited | dutiful |
| curiosity | traditional | curious |

- **Loyalty** is deliberately **not** a global axis. Loyalties belong to specific relationships and factions, so they are canon facts ("Loyal to the Argent Dawn").
- **Internal value:** −100 … +100, starting at 0, or at the player-confirmed starting leanings from the wizard or TRP3 traits.
- **Nudges:** each decision effect moves a value by `delta × (1 − |value| / 100)`, with a delta of 1–3, so change slows near the extremes. A **daily cap** per axis prevents grinding.
- **Words, not numbers:**

  | Range | Shown as |
  |---|---|
  | \|v\| < 15 | (not shown) |
  | 15–39 | leans … |
  | 40–69 | … |
  | ≥ 70 | strongly … |

  Numbers are internal and appear only in a debug view.

### 3. Insights (proposals to change canon)
- When a tendency **crosses a threshold** and the pattern is consistent (for example several decisions in the same direction), Dawnward creates an **insight**, an interpretation: "{name} has grown more cautious since Stratholme. Make 'cautious' part of their character?"
- Approving creates a **trait fact** in canon, with provenance listing the decisions behind it.
- Rejecting keeps the tendency but stops asking about it for a while.
- **Beliefs, motivations, fears and relationships** develop the same way: decisions can *propose* them; only the player makes them canon.

## Review and adjustment (no dashboard)
The Character section gains one **Development** area:
- **Now:** the mood, in one line.
- **Leanings:** the visible tendencies in words.
- **Recent decisions:** the last 5, with **Undo last**.

**Adjust** on a leaning offers four simple choices: *that's not them* (reset toward neutral), *more so*, *less so* and *lock* (no further drift). Each adjustment is recorded as a player decision, so history stays honest.

## How the six layers map

| Layer | Stored in | Example |
|---|---|---|
| Objective experience | journal `event` entries, `sources` | "Defeated Baron Rivendare in Stratholme" |
| Player decision | `decisions` + journal reaction | "Chose humility" |
| Emotional state | `evolution.mood` | "determined (medium)" |
| Long-term development | `evolution.tendencies` | "leans dutiful" |
| Canon | `facts` | "Vowed to protect Hearthglen" (trait, belief, vow) |
| Public narrative | projection by publication policy | Currently: "Determined, after Stratholme" |

## Biography evolution: what is realistic without AI
A **composer** builds a structured biography draft from canon and decisions:

| Section | Built from |
|---|---|
| Origins and early life | `origin` and `place` facts; the player's own origin text if provided |
| Important relationships | `relationship` facts and family entries |
| Defining experiences | decisions and events the player marked as **defining**, plus high-significance moments |
| Recent developments | the last few *public* decisions, using each option's journal phrasing |
| Who they are now | approved traits, visible leanings, current motivations and beliefs |

- **Quality:** each sentence comes from an authored fragment for that fact category or option, joined with simple connective rules (ordering, grouping, avoiding repeated sentence openings). The result reads as a **coherent but somewhat formulaic** history, which is good enough as a draft, not literary prose.
- **The player's edits win.** An edited section is kept. Later recompositions only **propose** additions, such as a new "Recent developments" paragraph, as a diff to accept.
- **The original biography** (Path A) is kept verbatim. The composer never rewrites it; it can quote or link it as the "Origins" section if the player chooses.
