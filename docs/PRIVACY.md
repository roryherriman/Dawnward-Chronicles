# Privacy model

A character's history is the player's creative work. Some of it is meant for other players to see, and much of it is not. Dawnward keeps a hard line between **private character history** and **public profile information**.

## Visibility levels

Every fact Dawnward stores (a family member, a backstory paragraph, a journal entry, a trait reason) has one visibility level:

| Level | Inside Dawnward | Shareable export | TRP3 | Default for |
|---|---|---|---|---|
| `public` | ✅ | ✅ | ✅ (when sync is enabled) | Original model: nothing (making something public is an explicit choice). Profile model (v0.9): profile details, see below. |
| `private` | ✅ | ❌, unless "include private" is ticked for a personal backup | ❌ | Original model: everything. Profile model: the journal, story answers, private convictions |
| `secret` | ✅ | ❌, unless "include secrets" is ticked separately, with a warning | ❌ **never** | Facts the player marks as secret |

## Publication model (v0.9)

Two models exist side by side, per character (`char.publication`, `Core/Publication.lua`, `Privacy.DefaultFor`):

| | Original model | Profile model |
|---|---|---|
| Who has it | Characters created before v0.9 | Characters set up with the v0.9 wizard, and older characters after the one-time switch |
| Profile fields, family, history, facts, personality values, a stance's public persona, the biography | Start **Private** | Start **Public**: they describe the character to others, ready for Total RP 3 |
| Journal entries, story answers and records, private convictions, memories | Start Private | Start Private (unchanged) |
| Secret | Never published | Never published |

- **No routine classification.** The v0.9 setup wizard has no privacy step. A new character's details are its public profile; any single item can still be made Private or Secret with its chip.
- **Older characters are never published silently.** They keep the original model until the player runs the one-time switch (`/dawnward publish`, or the Total RP 3 page). It first previews, per category, how many items are Private, Secret and already Public. Only the **Private** items of the categories the player ticks become Public; **Secret items never change**; the journal and story records are not part of it. Ticking nothing switches the model for new items only.
- **The biography** (the verbatim story kept as a biography source) now has its own visibility. It starts Public under the profile model and Private otherwise; only while it is Public does its current text reach the public projection (share exports and, when connected, Total RP 3). Earlier versions and where it came from never do.
- **Unknown values are safe.** A damaged or unknown publication value loads as the original model; an unknown biography visibility loads as Private. An older build that does not know these keys drops them, which also falls back to Private.

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

The **only** way character data leaves the core is `Projection.GetPublic(characterKey)`. It returns a newly built, deep-copied table that contains `public` facts only (each with its statement, category and subject; provenance is reduced to its origin, without source links or excerpts) and, since v0.9, the biography's current text when the biography itself is Public. The TRP3 integration and the shareable export both work from this projection and never see the core database.

Tests check that:

- `private` and `secret` values never appear in any projection, share export or TRP3 write;
- changing the projection cannot change the core data;
- marking a fact as `secret` removes it from the very next projection.

## What Dawnward never does

- It never sends character data over the network. Only TRP3 (or MSP) transmits a profile, and only what TRP3 already holds.
- It never reads other players' private data. Reading other players' TRP3 profiles is out of scope.
- It never stores account names, BattleTags, real names or email addresses.

## Development data

Real character data used during development, such as Kyssarra Dawnward's detailed backstory, lives in `private/`, which git ignores.

You can also list private terms (NPC names, family names) one per line in `private/hygiene-denylist.txt`. `tools/check.py` then fails if any file that could be committed contains one of them.
