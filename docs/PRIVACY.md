# Privacy model

A character's history is the player's creative work. Some of it is meant for other players to see, and much of it is not. Dawnward keeps a hard line between **private character history** and **public profile information**.

## Publication model (v0.10): your profile is your profile

**From v0.10 there is no per-item Public / Private / Secret classification in the normal experience.** A character's Dawnward profile is what Dawnward publishes to Total RP 3 once the player connects a named Total RP 3 profile. What is not meant for others is simply not part of the profile:

| Part of the profile (published when connected) | Never part of the profile |
|---|---|
| Profile details (names, titles, race, class, age, birthplace, residence, appearance, ...), the biography (the story kept word for word), family, history, facts, personality values and your own words for each axis, the public persona of an established stance, defining moments (approved story entries marked important) | Journal notes, unapproved story drafts and suggestions, story answers and decisions, memories, a stance's inner conviction, earlier biography versions and where text came from |

`char.publication` (`Core/Publication.lua`) records which model a character is on:

| Value | Who | What publishes |
|---|---|---|
| `{ mode = "profile", version = 2 }` | Characters set up with the wizard since v0.10; v0.9 characters with nothing hidden (moved over automatically when loaded); any character after the one-time confirmation | The whole profile; the old visibility of each record is ignored |
| `{ mode = "profile" }` (v0.9) with something hidden, or `{}` (before v0.9) | Older characters until the player confirms | Only what an earlier version marked Public |

- **Older content is never published silently.** A character an earlier version kept partly back stays as it was until the player confirms once (`/dawnward publish confirm`, or **Publish whole profile…** on the Total RP 3 page). The confirmation first lists, per category, how many items would be published.
- **Your own axis words** were never published before v0.10, so a character that has them counts as having something kept back and waits for the confirmation too.
- **Backups carry the model,** and restoring a backup never moves a character back to an earlier model.
- **Reversible and lossless.** The confirmation does not change any record: old visibility values stay stored, and `/dawnward publish undo` returns the character to the model it had.
- **Why this changed (v0.10).** In 0.9 a backstory imported during first-time setup was stored with the old Private default, because the wizard switched the character to the profile model only at Finish; the About page was then built from Public items only and stayed empty in game ("No description"). In v0.10 the profile publishes as a whole, so the order of setup steps no longer matters.

- **Nothing to classify on screen.** No Dawnward screen shows Public, Private or Secret any more: no chips, dropdowns, cycles or "Make Public" confirmations, and the Character page has no public preview (the Total RP 3 page keeps its own **Preview profile** of what Total RP 3 receives). The only publication control is the one-time **Publish whole profile…** callout, shown on the Character page only while a character waits for the confirmation.
- **Retired commands.** `vis`, `journal|fact|family|history|personality vis`, `memory|arc|goal|stance|person vis`, `stance private` and `biography public|private|secret` reply with one line ("Per-item visibility is no longer used…") and change nothing. Listings no longer show `[public]` / `[private]` tags.
- **Personal backups hold everything** (`/dawnward export backup`, Settings > Data): every record whatever its old visibility, the story, suggestions, key memory, axis meanings and the stored biography. Keep a backup to yourself. The words `secrets` and `biography` after `export backup` are still accepted and change nothing. Backups made by earlier versions (without secrets, or without the biography) still import: what they left out is kept from the current character.
- **Share exports** (`/dawnward export share`) hold the published profile (`Projection.GetPublic`): for a v0.10 character the whole profile; for one still waiting for the confirmation, what it marked Public.

## Visibility levels (legacy, before v0.10)

Older saved data still carries a visibility on each record. It is kept for compatibility and for characters that have not confirmed yet:

| Level | Meaning before v0.10 |
|---|---|
| `public` | Could reach share exports and Total RP 3 |
| `private` | Inside Dawnward only (personal backups could include it) |
| `secret` | Inside Dawnward only, never published |

## The journal (v0.2)
- Every journal entry has a visibility. Entries you write and automatic milestones both start **private**.
- Milestone entries record only what the game reports: level, zone, subzone and time. Nothing about other players is recorded.
- The cosmetic **theme** isn't personal information, so it is included in every export.
- **Milestone keys** (for example `levelup:23`, used to avoid duplicates) are included in personal backups only, never in share exports.

## Character foundations (v0.3)
- **Facts** and **suggestions** start **private**. Personality values start private too.
- **Biography sources** have no visibility of their own and are always private:
  - never in a share export;
  - never in a projection;
  - never sent to TRP3;
  - in a personal backup only when you ask (`/dawnward export backup biography`).
- **Suggestions and their key memory** are never in a share export or a projection. Personal backups include them, so a restore cannot re-suggest what you dismissed.
- Share exports were checked by planting marker text in every private part and scanning the export text (L1).

## The living chronicle (v0.4)

- **Story records** (events, reactions, decisions, personality changes, memories, arcs, goals, stances and people) are kept in the character's private `story` table. None of it is ever part of the public projection, a share export or Total RP 3. The exceptions are below.
- **Suggestions and drafts are private.** Anything Dawnward suggests starts *proposed* and private. A record must be *established* by you before it can be public. A story draft must be approved before it can be public.
- **What can leave Dawnward, and only if you make it public:**
  - an approved journal entry you mark as a defining moment (its title, in Total RP 3);
  - an established stance's public side;
  - its private conviction, only if you make that side public as well.
- **Secrets in backups.** A personal backup made without secrets leaves out:
  - secret records;
  - an identity's secret conviction;
  - secret feelings about a person;
  - your own words in an answer whose journal entry is secret, and the memory suggested from them.

  Restoring such a backup keeps the secrets you have now. Full event records are left out of backups (their keys are kept, so nothing is recorded twice).
- **Places.** The places log (where the character has been, and which places you marked as meaningful) is part of the private `story` table. It is never public, never in a share export and never sent to Total RP 3. Marking a place as meaningful creates nothing else.
- **Alts.** Story events are recorded only for characters that already use Dawnward, so installing it does not start recording every character on the account.

## Story import, axis meanings and publishing (v0.7.1)
- **Story import** (Character > Import story, Settings > Data, the setup wizard's Character stage, `/dawnward biography`):
  - the pasted text, or your own Total RP 3 About text, is stored **verbatim** as a private biography source (same rules as above: never public, never in a share export, in a backup only with the biography option);
  - reading Total RP 3 is read-only: Dawnward copies the active profile's About text (leaving out any block Dawnward wrote there) and never writes back;
  - every sentence or paragraph becomes a **private suggestion**. Nothing becomes canon until you choose Approve, and an approved fact is **Private** unless you choose Public, which first shows exactly what would become public and asks;
  - Skip removes a suggestion and remembers it, so importing the same or an edited story never suggests it again.
- **Public facts carry only their statement.** The public projection (share exports and Total RP 3) no longer includes a fact's source links or quoted excerpt, so a fact approved from your story never publishes the original sentence, even after you reworded it.
- **Axis meanings** (your own names for the personality axes, what they mean, and locks) are private: kept in personal backups, never in the public projection, a share export or Total RP 3. Total RP 3 traits keep Dawnward's own labels.
- **Arcs and goals** are never public, whatever their visibility chip says: they are not part of the public projection, share exports or the Total RP 3 block (tested). A rejected arc suggestion is remembered in the suggestion key memory, privately.
- **Publishing a journal entry** asks first and shows exactly the text that becomes shareable, and where it can appear.
- **Backup owner.** A personal backup now records the character it was made from (`Name-Realm`) so a restore can warn before one character's backup replaces another's. Share exports never include it.

## Total RP 3 sync (experimental, v0.3)
- TRP3 sync uses **only the public projection**: public facts and public personality values. Private and secret data, sources, suggestions and simulation data can never reach TRP3 (L2).
- It is off until you opt in for a character. Anything it writes, TRP3 then shares with other players as part of your profile.
- Backups of your TRP3 sections are stored in `DawnwardChroniclesTRP3DB` on your computer only.

## The public projection

The **only** way character data leaves the core is `Projection.GetPublic(char)`. It returns a newly built, deep-copied table. For a character on the v0.10 model it holds the profile described above; for an older character that has not confirmed, only items marked Public. Facts carry their statement, category and subject; provenance is reduced to its origin, without source links or excerpts. The TRP3 integration and the shareable export both work from this projection and never see the core database.

Tests check that:

- journal notes, drafts, story answers and inner convictions never appear in any projection or TRP3 write;
- an older character's kept-back items never appear before the one-time confirmation;
- changing the projection cannot change the core data;
- the confirmation can be undone exactly.

## What Dawnward never does

- It never sends character data over the network. Only TRP3 (or MSP) transmits a profile, and only what TRP3 already holds.
- It never reads other players' private data. Reading other players' TRP3 profiles is out of scope.
- It never stores account names, BattleTags, real names or email addresses.

## Development data

Real character data used during development, such as Kyssarra Dawnward's detailed backstory, lives in `private/`, which git ignores.

You can also list private terms (NPC names, family names) one per line in `private/hygiene-denylist.txt`. `tools/check.py` then fails if any file that could be committed contains one of them.
