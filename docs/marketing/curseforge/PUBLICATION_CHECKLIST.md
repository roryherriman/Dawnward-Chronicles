# CurseForge publication checklist (WoW Forever)

None of these steps has been done. Each needs the owner's explicit approval, and nothing is to be created before the blockers are cleared.

## Blockers
- [ ] **WoW Forever compatibility verified in game** (release gate [#24](https://github.com/roryherriman/Dawnward-Chronicles/issues/24), not run). Until then any upload must be labelled Alpha and "Forever untested".
- [ ] **Forever TOC.** The addon's TOC declares `## Interface: 11509` (Classic Era). A Forever build needs a TOC with the Forever interface number (16001 according to other Forever addons; confirm with `/dump select(4, GetBuildInfo())` on a Forever client). Either add a second TOC (for example `DawnwardChronicles_Forever.toc` or the client-specific suffix the Forever client loads), or set the interface for a Forever-only package. Verify which TOC filename the Forever client reads.
- [ ] **Privacy of drafts.** CurseForge documents no private draft state. A project becomes available once both the project and a file are approved. Assume anything created can become public.

## Before creating the project
- [ ] Confirm in the author console that the **WoW Forever** flavour / game version (1.60.1 at the time of writing) is offered for new World of Warcraft projects. Do **not** substitute Retail or Classic Era.
- [ ] Re-read `LISTING.md` against the current repository: every feature status, and no planned feature described as available.
- [ ] Original project icon (at least 400 × 400) and optional banner; no Blizzard or TRP3 artwork.
- [ ] Real in-game screenshots from a disposable character on a Forever client.
- [ ] Privacy review: no character data, names of real players, account names or SavedVariables in screenshots or text.

## Packaging
- [ ] `python tools/check.py` passes on the commit being packaged.
- [ ] `python tools/package.py` builds `dist/DawnwardChronicles-<version>.zip` containing only the `DawnwardChronicles/` folder.
- [ ] The zip contains the Forever TOC and installs on a Forever client without Lua errors.
- [ ] The version in the TOC matches the file name and the changelog.
- [ ] Total RP 3 is marked as an **optional** dependency only.

## Creating and uploading (owner only)
- [ ] Create the project under World of Warcraft with the Forever flavour (expect moderation; it can take up to a few workdays).
- [ ] Upload the first file as **Alpha**, tagged with the Forever game version, using the changelog template.
- [ ] Record the project URL, ID and date in `docs/handoffs/CURSEFORGE_STATUS.md`.
