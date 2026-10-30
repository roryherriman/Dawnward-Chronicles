# Dawnward Chronicles v0.8: visual fidelity refinement

Status: **implemented, automated tests only (L2).** Nothing in this document has been compared in game yet. The owner's side-by-side comparison of in-game screenshots against the approved renderings is the acceptance test ([TESTING.md](../TESTING.md) part V).

v0.8 refines the v0.7 interface towards the nine approved renderings in [mockups](mockups/README.md). It is not a redesign. Layout, behaviour and the rules of every screen are unchanged unless listed here. [UI_DESIGN_V07.md](UI_DESIGN_V07.md) still holds the tokens and stages; where the two differ, this document is newer.

No fidelity percentage is claimed. The owner estimated v0.7 at about 65% of the target; a measured figure needs the in-game comparison.

## Per-screen audits

Each audit has a difference table for every element: approved rendering, before (v0.7), now, the difference remaining, why it remains, whether it can be fixed, priority, and how to check it in game. Each also ends with numbered in-game acceptance steps.

| Screen | Mockup | Audit |
|---|---|---|
| Design system, window shell, character rail | design-system.png, journal-dashboard.png | [shell-and-components.md](audit/shell-and-components.md) |
| Journal | journal-dashboard.png | [journal.md](audit/journal.md) |
| Character and Character Showcase | character-profile.png, proposed-character-showcase.png | [character.md](audit/character.md) |
| Story Director (and the pop-up reaction card) | story-director.png | [story.md](audit/story.md) |
| Chronicle (all tabs; Places) | chronicle-memories.png, chronicle-places.png | [chronicle.md](audit/chronicle.md) |
| Settings, first-time setup, Total RP 3 page, story import | first-time-setup.png, proposed-trp3-sync.png | [settings-setup-trp3.md](audit/settings-setup-trp3.md) |

## What changed, in short

- **Design system:**
  - **Type scale:** screen title Cinzel 28, entry title 18. The eyebrow went from 11 to 13, so nothing is below the 13 px minimum.
  - **Text styles:** reading text is 16 with extra line spacing, meta 14. New named styles via `Style.FontFor`.
  - **Control heights from the mockup:** buttons 30 and 36, inputs 36, chips 24, navigation 44, progress bars 6.
  - **Secondary tones:** derived per theme and contrast-tested.
  - **Buttons:** they keep a visible edge instead of showing one only on hover.
  - **Round shapes:** chips, badges, number discs and the portrait ring are round, using the game's own mask textures (`CreateMaskTexture`, `Interface\CharacterFrame\TempPortraitAlphaMask`, as Blizzard's 1.15.9 frames use them), with a square fallback.
- **Rail:**
  - the mockup's geometry, with a ringed portrait and a level pill;
  - the class name in its class colour;
  - Homeland and privacy chips, from real data only;
  - a filled, gold-edged selected item, which now shows from the first open.
- **Journal:**
  - one scrolling list of story cards, built from a small pool of reused frames, with a slim scroll bar; this replaced paging;
  - the mockup's toolbar, the "A moment awaits" banner and the right column.
- **Character:**
  - fields as tiles on the window ground, with chips and Edit side by side;
  - personality knobs on a track;
  - family cards.
- **Character Showcase:**
  - the live model fills about 90% of its card;
  - the portrait fallback is a framed 132 px round portrait with a caption, no longer stretched.
- **Story Director:**
  - the moment card is measured and stacked, so long questions and reasons no longer overlap;
  - answers carry round number discs;
  - the side panels fit.
- **Chronicle:**
  - cards are sized to their content and placed into two columns;
  - a **Read** full view shows long records with their actions;
  - amber marks suggested records, red marks disputed ones;
  - the Review answers fit one row;
  - the Places detail is laid out from its content.
- **Settings, setup, TRP3 page, import:**
  - **Settings:** full-width grouped panels with a description per setting, and a segmented control per Story setting showing every option.
  - **Setup wizard:** a step rail with round badges and roomier fields.
  - **TRP3 page:** the mockup's amber states, one-line backups and a fixed ownership selector.
  - **Import window:** restyled the same way.

## Remaining differences, and why

**True limits of the 1.15.9 client** (no fix without shipping art, which the project avoids):
- No vector or line icons: lock, pencil, bin, star, magnifier, pin, eye and rotate arrows are words or glyphs.
- No rounded rectangles for buttons, cards and inputs. Masks make circles and pills, but not cut corners on panels with edges.
- No letter spacing. Tracked capitals in the mockup are plain capitals one size up.
- One font string cannot mix styles, so a bold label and regular text on the same wrapped line wrap together.

**Design choices made on purpose** (reversible, and listed in each audit):
- **Kept on purpose:** the hint line under Story answers, the paging in the Chronicle (with cards stacked per column), and the "Profile" heading (the mockup's "Who she is" assumes a pronoun).
- **Story answers:** one click answers a moment, as before (the mockup shows pick, then Save).
- **Wizard:** a 28 px title and 36 px inputs, slightly different from the mockup's 26 and 40.

**Not done yet** (candidates for a later pass):
- a scroll area for the left column only, on the Character page;
- a highlighted word inside Journal story text;
- the shared-component proposals collected in the audits:
  - a featured card state, and Card tones;
  - a padded Segmented track with per-item widths;
  - a shared slim scroll bar and scrolling list;
  - a text link component;
  - wrapping chip and button rows;
  - a shortened-text helper;
  - a portrait-in-ring component.
- optional extra OFL fonts: Alegreya Sans Italic and Medium, and Cinzel Bold.

## Most likely in-game risks

- **Masks:** if round shapes come out square or missing, masks behave differently on this client; the square fallback should still look tidy.
- **Text measurement:** text sizes are estimated from the bundled fonts' character widths. Real font rendering may differ by a few pixels, so look for clipped or touching text, especially at window scale 0.7.
- **Restyled scroll bars:** the Journal's slim bar, and the stock bar in the Chronicle full view.
- **Line heights:** the 28 px title and the 21 px rail name, which can take two lines.
