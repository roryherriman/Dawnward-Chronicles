# Story interpretation architecture (proposal)

Status: **design only.** Nothing in this document is implemented in v0.2. It describes how Dawnward will eventually turn a character's existing story into personalised story decisions, and checks that today's data model can grow into it.

> **Superseded in detail by [`planning/v0.3-proposal.md`](planning/v0.3-proposal.md).** The approved decisions there separate **Source**, **Interpretation** and **Canon** into three distinct layers, rather than the single fact list with a `status` field sketched below. The principles here still apply.

## The problem
Players come to Dawnward in three different ways, and all three must work equally well:

1. **Hand-written characters** with long, personal biographies, often in Total RP 3.
2. **Characters written with help from AI tools** outside the game.
3. **Characters with no history yet**, who want their story to emerge as they play.

Dawnward must respect each of these. It must not quietly rewrite what the player wrote, and it must not pretend to understand more than it does.

## Principles
- **The original is preserved.** A biography read from Total RP 3 is kept exactly as written, in private storage. Interpretations sit alongside it and never replace it.
- **Facts and interpretations are kept apart.** Every piece of character knowledge records *where it came from* and *whether the player approved it*.
- **Nothing becomes canon without approval.** Proposed facts wait in a review list. Story decisions use only approved facts.
- **No mandatory AI, external application or online service.** Everything works inside the game client. A player may *bring* text produced elsewhere, but Dawnward never calls out to anything.
- **No overclaiming.** Keyword matching cannot reliably understand an arbitrary biography. Dawnward only *suggests* from free text, and labels every suggestion as unverified.
- **Privacy carries through.** Every fact has a visibility (`public`, `private` or `secret`), just like everything else.

## Pipeline

```
 Sources                     Candidates               Review                 Canon               Story
 ──────────                  ──────────               ──────                 ─────               ─────
 TRP3 structured fields ──►  extracted facts  ──┐
 TRP3 biography text   ──►  player-marked      │                                                 decision
   (snapshot, verbatim)       passages         ├──►  player approves /  ──►  approved facts  ──►  pipeline
 Guided questions      ──►  answers           │     edits / rejects        (with provenance)    (v0.3+)
 Imported summary      ──►  proposed facts  ──┘
   (e.g. written with AI elsewhere)
 Journal + milestones  ──►  observed events (already factual)
```

### 1. Sources
| Source | How it is read | Reliability |
|---|---|---|
| **TRP3 structured fields**: name, title, race, class, age, residence, birthplace, misc fields, personality traits (`PS`: left/right labels and value), relationship status | Read-only, through TRP3's public API where it exists. Otherwise through a version-checked read adapter (see `TRP3_INTEGRATION.md`). | High: these are structured data the player entered on purpose. |
| **TRP3 biography** (`about`, templates 1–3) | Read-only snapshot, stored verbatim with the TRP3 version and the section's version number `v` | The text is exact; any *interpretation* of it is not. |
| **Guided questions**: a short questionnaire for characters with no history (origin, people who matter, what they want, what they fear) | Entered in Dawnward | High: the player answered directly. |
| **Imported summary**: text the player brings from outside, such as a summary drafted with an AI tool | Pasted in a simple, documented line-based format | Treated as *proposals*, never facts. |
| **Journal and milestones** | Already stored | Events are observed. Notes are the player's own words. |

### 2. Candidates
- **Structured fields** map one-to-one onto candidate facts. For example, the trait "Chaotic ↔ Lawful" at 15/20 becomes the candidate "leans lawful".
- **Biography text is never parsed into facts automatically.** Instead, the review screen shows the biography in paragraphs. The player can mark a passage and say what it is: a relationship, a motivation, an event, a place or a theme.
- **Optional hints** may highlight likely passages, such as words for family members ("mother", "brother") or capitalised names next to them. They are displayed as "possible", never stored as facts, and can be turned off.
- **Imported summaries** become candidates marked `proposed`.

### 3. Review
One list of candidates. Each can be approved, edited, rejected or postponed. Approving records who approved it and when. Rejected candidates are remembered, so the same suggestion isn't shown again.

### 4. Canon (the approved facts)
These are the facts the story pipeline may use. Each fact is small and typed:

```lua
-- illustrative only (schema v3+)
{
	id = 42,                          -- shared ID sequence with the other lists
	category = "relationship",        -- relationship | motivation | trait | origin | event | place | theme
	statement = "Estranged from her brother Tam",
	subject = "Tam",                  -- optional: who or what it concerns
	provenance = {
		source = "trp3-biography",    -- trp3-field | trp3-biography | questionnaire | import | journal | player
		ref = { profileVersion = 14, section = "about", passage = 3 },
		interpreted = true,           -- true when a person or tool summarised the source
	},
	status = "approved",              -- proposed | approved | rejected
	approvedAt = 1700000000,
	visibility = "private",
}
```

### 5. Story pipeline (from v0.3)
Story nodes carry conditions on fact categories and subjects, for example: "if there is an approved relationship whose status is estranged". Decisions reference fact IDs, so every story beat can explain *why* it appeared. A character with no facts still gets general story nodes, and the guided questions grow their canon over time.

## Fit with today's data model (schema v2)
v0.2 already provides what this design needs, so schema v3 can add it without reshaping existing data:

| Need | Already in v2 |
|---|---|
| Stable references to any item | One ID sequence (`nextId`) shared by family, history and journal. Facts would join it. |
| Visibility on every item | `visibility` on fields, family, history and journal entries |
| Factual versus written | Journal entries already distinguish `event` (observed) from `note` (written by the player) |
| Safe schema growth | Versioned saved data with copy-first migrations. Newer data is left read-only and never overwritten by an older version. |
| Isolation from TRP3 | The TRP3 adapter is read-only and only ever sees copies, never Dawnward's tables |
| Simulation | A separate saved variable, so the story pipeline can be tested on throwaway canon |

Planned for schema v3:

- `facts` (the list above);
- `sources` (verbatim biography snapshots with their TRP3 version and `v`, private);
- `rejected` (keys of dismissed suggestions, capped).

The migration would only add these.

## Explicit non-goals
- No free-form natural-language parser that claims to "understand" biographies.
- No AI model, network request or external helper at runtime.
- No automatic canon: every fact passes the player's review.
- No writes back to TRP3 from this pipeline. Sharing approved facts with TRP3 follows the separate, opt-in sync tiers.
