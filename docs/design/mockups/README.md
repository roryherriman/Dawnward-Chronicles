# Dawnward Chronicles: design mockups (concepts)

These are **design concepts, not in-game screenshots.** They are the visual source of truth and acceptance reference for the next UI phase. The in-game Lua interface does not look like this yet. See [UI_DESIGN_V07.md](../UI_DESIGN_V07.md) for the audit, the Classic Era limitations and the staged plan.

**Sample data only.** The character, journal entries, memories, places, family and dialogue below are invented for the mockups. That covers "Kyssarra Dawnwhisper", "The night the lanterns went out", Maybell, Tobin, the missing courier and similar. They are not game lore and never appear in the addon. The real addon shows the player's own data.

## Approved (owner approval, 2026-10-29)

| # | Screen | Image |
|---|---|---|
| 1 | Journal / dashboard (primary) | [journal-dashboard.png](journal-dashboard.png) |
| 2 | Character | [character-profile.png](character-profile.png) |
| 3 | Story Director | [story-director.png](story-director.png) |
| 4 | Chronicle: Memories | [chronicle-memories.png](chronicle-memories.png) |
| 5 | Chronicle: Places | [chronicle-places.png](chronicle-places.png) |
| 6 | First-time setup (step 2 of 6) | [first-time-setup.png](first-time-setup.png) |
| 7 | Design system | [design-system.png](design-system.png) |

![Journal / dashboard](journal-dashboard.png)

| | |
|---|---|
| ![Character](character-profile.png) | ![Story Director](story-director.png) |
| ![Chronicle: Memories](chronicle-memories.png) | ![Chronicle: Places](chronicle-places.png) |
| ![First-time setup](first-time-setup.png) | ![Design system](design-system.png) |

## Proposed, awaiting approval

These were added after approval, at the owner's request, to cover the Total RP 3 workflow and the Character Showcase. They are **not approved yet**.

| Screen | Image |
|---|---|
| Settings: Total RP 3 sync (status, linked profile, proposed change, never-shared list, conflict, backups) | [proposed-trp3-sync.png](proposed-trp3-sync.png) |
| Character Showcase (live 3D model with portrait fallback) | [proposed-character-showcase.png](proposed-character-showcase.png) |

## Provenance

- **Source:** the original artboards from the 2026-10-29 design session (a Claude design canvas). They are kept verbatim in [`source/`](source/) as `.dc.html` files, with `canvas.json` for the layout.
- **Rendering:** each image is a 2× render (2200 × 1440, design system 2200 × 2000) of those exact files. The renderer is `tools/design/render_mockups.js` (Playwright/Chromium), using the Google Fonts the artboards load: Cinzel and Alegreya Sans.
- **Live-copy check:** the seven approved sources were confirmed byte-identical to the published canvas before rendering.
- **Packaging:** these are documentation assets only. `tools/package.py` packages only the addon folder, so nothing here reaches the game.

To re-render, run from the repository root with Playwright available:

```
node tools/design/render_mockups.js "$PWD/docs/design/mockups/source" "$PWD/docs/design/mockups" 2 \
  Main.dc.html:journal-dashboard:1100:720 Character.dc.html:character-profile:1100:720 \
  Story.dc.html:story-director:1100:720 ChronicleMemories.dc.html:chronicle-memories:1100:720 \
  ChroniclePlaces.dc.html:chronicle-places:1100:720 SetupWizard.dc.html:first-time-setup:1100:720 \
  DesignSystem.dc.html:design-system:1100:1000 TRP3Sync.dc.html:proposed-trp3-sync:1100:720 \
  CharacterShowcase.dc.html:proposed-character-showcase:1100:720
```
