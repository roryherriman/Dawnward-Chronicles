# Privacy model

A character's history is the player's creative work. Some of it is meant for other players to see, and much of it is not. Dawnward keeps a hard line between **private character history** and **public profile information**.

## Visibility levels

Every fact Dawnward stores (a family member, a backstory paragraph, a journal entry, a trait reason) has one visibility level:

| Level | Inside Dawnward | Shareable export | TRP3 | Default for |
|---|---|---|---|---|
| `public` | ✅ | ✅ | ✅ (when sync is enabled) | Nothing. Making something public is always an explicit choice. |
| `private` | ✅ | ❌, unless "include private" is ticked for a personal backup | ❌ | Backstory, family, journal |
| `secret` | ✅ | ❌, unless "include secrets" is ticked separately, with a warning | ❌ **never** | Facts the player marks as secret |

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

## Total RP 3 sync (experimental, v0.3)
- TRP3 sync uses **only the public projection**: public facts and public personality values. Private and secret data, sources, suggestions and simulation data can never reach TRP3 (L2).
- It is off until you opt in for a character. Anything it writes, TRP3 then shares with other players as part of your profile.
- Backups of your TRP3 sections are stored in `DawnwardChroniclesTRP3DB` on your computer only.

## The public projection

The **only** way character data leaves the core is `Projection.GetPublic(characterKey)`. It returns a newly built, deep-copied table that contains `public` facts only. The TRP3 integration and the shareable export both work from this projection and never see the core database.

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
