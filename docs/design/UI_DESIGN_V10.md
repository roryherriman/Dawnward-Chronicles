# Dawnward Chronicles v0.10: interface fidelity and the profile without classification

Status: **implemented, automated tests only (L2).** Nothing here has been compared in game. The acceptance test is the owner's side-by-side comparison of in-game screenshots against the approved renderings in [mockups](mockups/README.md) ([TESTING.md](../TESTING.md) part Z, item Z15). No fidelity percentage is claimed.

v0.10 builds on [UI_DESIGN_V09.md](UI_DESIGN_V09.md). The detailed per-element tables (approved rendering, v0.9, now, remaining difference, cause, in-game check) are in four audits:

| Area | Audit |
|---|---|
| Window shell, rail, Journal, shared design system | [audit/v10-shell-journal.md](audit/v10-shell-journal.md) |
| Character profile and Character Showcase | [audit/v10-character.md](audit/v10-character.md) |
| Story Director, reaction card, Chronicle (all tabs, Places) | [audit/v10-story-chronicle.md](audit/v10-story-chronicle.md) |
| Settings, first-time setup, Total RP 3 page, story import, Total RP 3 output | [audit/v10-settings-setup-trp3.md](audit/v10-settings-setup-trp3.md) |

## 1. What changed for every screen

- **No privacy classification.** Public / Private / Secret chips, toggles, confirmations and the public preview are gone everywhere ([PRIVACY.md](../PRIVACY.md)). Where a rendering shows a privacy chip, that space is left out and the row re-flows.
- **Line icons.** The 1.15.9 client has Line regions (`CreateLine`, `SetStartPoint`, `SetEndPoint`, `SetThickness`; Blizzard's `SimpleLineAPIDocumentation.lua`). v0.9 listed "no vector icons" as a client limit; for line icons that was wrong. `Style.ICONS` draws the mockup's icons as strokes; without line regions every control keeps its v0.9 word or glyph.
- **Tracked eyebrows.** Letter-spaced capitals (0.16 em) with `Widgets.TrackedLabel`, one font string per letter, on every screen. v0.9 listed letter spacing as a limit; it is now done.
- **Fonts.** Alegreya Sans Italic and Medium and Cinzel Bold (OFL) join the bundled faces ([Media/Fonts/FONTS.txt](../../DawnwardChronicles/Media/Fonts/FONTS.txt)); a file that fails to load falls back to the nearest v0.9 face.
- **Colours.** Gold and edge tones are closer to the design; eyebrows use a readable tone (Shadowbound's was 2.1–2.5:1, now at least 4.5:1).

## 2. Remaining differences, by cause

**Verified Classic Era 1.15.9 limits**
- Square corners on buttons, inputs, cards and nav items: masks give circles and pills only, and fake corners need a known background colour that ghost buttons, chips and pooled cards cannot guarantee.
- Line strokes have square ends and plain joins (no round caps).
- One font and one style per font string: a bold label and regular text on one wrapped line are two strings (Story "Why now" uses an inline indent; the Total RP 3 preview cannot show bold runs).
- The Showcase model's lighting and camera are the client's.
- Total RP 3 About markup is limited to what TRP3 3.4.1 renders (headings, colour, icons, alignment).

**Deliberate choices (reversible)**
- Eyebrows are 13 px, not 12 (the project's 13 px minimum).
- The heading reads "Profile", not "Who she is" (no assumed pronoun).
- One click answers a Story moment (the rendering shows pick, then Save): behaviour, not look.
- Chronicle cards pack into the shorter column rather than rows; card text stops at 8 lines with Read.
- Settings and the Total RP 3 page are organised by purpose with a section rail, where the rendering shows one long page.
- Game-derived Race and Class tiles are 18 px taller to fit "from the game".

**Not done (candidates for later)**
- A highlighted word inside Journal story text.
- A narrower reading width in the Chronicle Read view.
- The import window's category picker is still a cycle button (eleven categories do not fit side by side).

## 3. Most likely in-game risks

1. Line icons render, at window scale 0.7 and 1.4.
2. Tracked eyebrows: letters evenly spaced, never overlapping.
3. The new font files load (italic rail title, Medium navigation, Bold dates).
4. Character pencil buttons, dashed "+ Add" tiles, game-derived Race and Class.
5. Chronicle scrolling list: wheel, thumb and refresh keep their place.
6. Total RP 3 page sections and the About preview against Total RP 3's own About page.
7. Story "Why now" inline indent (relies on a leading no-break space).
