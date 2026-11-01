# Dawnward Chronicles v0.9: first login, the Total RP 3 profile, and fidelity

Status: **implemented, automated tests only (L2).** Nothing here has been compared in game. The acceptance test is the owner's side-by-side comparison of in-game screenshots against the approved renderings ([TESTING.md](../TESTING.md) parts V, W and X). No fidelity percentage is claimed.

v0.9 builds on [UI_DESIGN_V08.md](UI_DESIGN_V08.md) and its per-screen audits in [audit/](audit/), which stay the detailed reference. This document records what v0.9 changes on screen, where the build now deliberately differs from an approved rendering, and the gap assessment, screen by screen, in priority order.

## 1. Changes in v0.9

### First-time setup (first-time-setup.png, SetupWizard.dc.html)
| Element | Approved rendering | v0.8 build | v0.9 build |
|---|---|---|---|
| Stage heading | A question in Cinzel 26 ("Who is your character?") | The stage name in Cinzel 28 | A question per stage in Cinzel 26 (`DawnwardFontStage`); the rail keeps the short names. No pronouns are assumed ("What is their story?") |
| Inputs | 40 px (`.inp`) | 36 px | **40 px**; rows 84 apart so hints and errors still never touch (L2) |
| Stages | Welcome, Character, Story, **Privacy**, Appearance, Finish | the same | Welcome, Character, Story, Appearance, **Total RP 3** (only when installed), Finish. **Deliberate difference:** the owner's v0.9 decision removes routine privacy classification; the stage numbers follow the stages shown ("STEP 2 OF 5" without Total RP 3) |
| Character note | Lock icon: "Everything starts Private…" | the same | The profile note: what these details are for (the profile model). Same panel, no lock |
| Story stage | (not rendered) | preferences only | Backstory import first, then the story questions |
| Opening | (not rendered) | when Dawnward is first opened | by itself after the first login (Platform/SetupLaunch.lua) |

### Total RP 3 page (proposed-trp3-sync.png)
| Element | Approved rendering | v0.9 build |
|---|---|---|
| Feature switcher | Biography · Traits (plus the v0.8 Mappings) | **Overview** · Biography · Traits · Mappings (4 × 92 px) |
| Overview | **Not rendered** (new in v0.9) | Built from the existing language: the card title, label/value status lines (muted labels, body values), segmented choices for About page, template and style, a primary "Connect everything…", a secondary "Preview profile", a ghost "Use the profile model…" |
| Mappings | (v0.8, not rendered) | Paged: as many rows as fit the card, "‹ Page n of m ›" at the right of the Authorize row |

### Shared components
- **Slim scroll bar** (`Widgets.SlimScrollBar`): the Journal's 6 px track and proportional thumb are now shared, and used by the Character profile, its public preview and the Chronicle's full view. This closes the v0.8 "shared slim scroll bar" proposal and the "stock Blizzard scroll bars" note for those views. The copy window and text areas keep the stock bar (their text boxes need the arrows least, and the stock bar is proven there in game).

### Character profile (character-profile.png)
- A **Details** group (first and last name, title prefix, eye colour, height, build, residence, relationship status, allegiance) after Background, in the same tiles, three to a row. Not in the rendering (new fields for Total RP 3); it scrolls with the rest.

## 2. Gap assessment, by screen (largest first)

Status: **open** (worth doing), **limit** (the client cannot do it without shipped art), **choice** (kept on purpose). Each is to be confirmed with an in-game screenshot.

| # | Screen | Difference from the approved rendering | Status | Priority |
|---|---|---|---|---|
| 1 | All | Line icons (lock, pencil, bin, star, magnifier, pin, eye, rotate arrows) are words or glyphs | limit | — |
| 2 | All | Cards, buttons and inputs have square corners (masks give circles and pills only) | limit | — |
| 3 | All | Tracked capitals (letter spacing) are plain capitals one size up | limit | — |
| 4 | Setup | No Privacy stage; a Total RP 3 stage instead | choice (owner decision, v0.9) | — |
| 5 | Total RP 3 | The Overview tab has no approved rendering; it reuses existing components | open: render a mockup, then align | P1 |
| 6 | Character | Only one scroll area for both columns (the rendering scrolls the left column only) | closed: the left column scrolls on its own; the right column stays put and gets its own slim bar only when it is taller than the room (many family or history entries) | — |
| 7 | Story | One click answers a moment (the rendering shows pick, then Save) | choice (behaviour, not look) | — |
| 8 | Journal | A highlighted word inside story text | open | P3 |
| 9 | All | Card tones and a "featured" card state; a padded segmented track with per-item widths; a text link; wrapping chip rows; a portrait-in-ring component | open (component proposals from the v0.8 audits) | P2 |
| 10 | All | Alegreya Sans Italic and Medium, Cinzel Bold (OFL) not bundled; italics use the regular face | open (adds fonts and licences) | P3 |
| 11 | Showcase | The live model's lighting and camera depend on the client; the rendering's soft rim light cannot be matched exactly | limit | — |
| 12 | Copy window, text areas | Stock scroll bars | choice (see above) | P3 |

## 3. Most likely in-game risks (v0.9 additions)
- **Wizard heights:** the 40 px inputs leave about 4 px spare at the bottom of the Character stage (L2-checked); at window scale 0.7 check that the profile note is not clipped.
- **Slim bar:** relies on the template's `ScrollBar`, `ThumbTexture` and `OnScrollRangeChanged` as in the Journal; if a view shows no bar at all, it falls back to the stock one only where the template differs.
- **Mouse wheel:** the window now takes the wheel (`Widgets.SwallowWheel`), so it never zooms the camera over the journal; scroll frames on the Character page scroll a fixed 60 per notch (`Widgets.WheelScroll`). Check the Character columns and the Showcase model zoom.
- **Overview controls:** three segmented rows of 3–4 items; check that "Silver Hand" and "Sections" fit their items at your UI scale.

## 4. Screen-by-screen acceptance (end of v0.9)

This is the state handed to the owner for the in-game comparison ([TESTING.md](../TESTING.md) parts V, X and Y). "Matches" means the code implements what the rendering shows and the mocked tests (L2) check it; it has not been seen in game. No screen is claimed to be identical.

| Screen | Rendering | Matches (L2) | Still differs | Cause | Check in game |
|---|---|---|---|---|---|
| Window and rail | journal-dashboard.png, design-system.png | 1100×720 layout, ringed portrait with level pill, class colour, gold-edged selected item, Guide and Settings at the foot, gold resize grip (scale 0.7–1.4, saved, Reset Window Size) | Line icons are words or glyphs; square corners on cards and buttons | Verified limits (#1, #2): no vector icons or rounded rectangles without shipped art | Drag the grip to both limits; Reset; rail text at 0.7 |
| Journal | journal-dashboard.png | One scrolling list of cards, slim bar, toolbar, "A moment awaits" banner, right column | No highlighted word in story text (#8) | Open (P3): one font string cannot mix styles mid-line | Long entries, search, wheel scroll |
| Character profile | character-profile.png | Field tiles, chips beside Edit, **left column scrolls alone**, personality track, family cards | The right column gets its own bar when it is taller than the room; the rendering's right column never scrolls. "Profile" heading instead of "Who she is" | Content: unset axes and history make the column taller than the rendering's example. Heading: a choice (no assumed pronoun) | Wheel over each column; bar shows and hides; long summary; scale 0.7 and 1.4 |
| Character Showcase | proposed-character-showcase.png | Live model about 90% of its card, retries, a framed 132 px portrait fallback, toggle | The rendering's soft rim lighting | Verified limit (#11): the client sets model lighting and camera | Live model loads; toggle both ways; wheel zooms the model |
| Story Director | story-director.png | Measured moment card, numbered answers, custom answer, side panels | One click answers (rendering: pick, then Save) | Choice: Story Director behaviour is not changed for looks | Long questions; Escape; waiting moments |
| Chronicle (all tabs) | chronicle-memories.png, chronicle-places.png | Content-sized cards in two columns, Read full view, Review answers as buttons, amber and red markers, Places list and detail | Pages instead of one scrolling list | Choice (kept on purpose) | Long titles; Read; "Shortened" hover; Review buttons |
| Settings | (design-system.png controls) | Grouped full-width panels, a description per setting, segmented Story controls | Square corners | Limit #2 | Every page at 0.7; active states per theme |
| First-time setup | first-time-setup.png | Step rail with round badges, Cinzel 26 question headings, 40 px inputs | No Privacy stage; a Total RP 3 stage | Owner decision (v0.9, #4) | Every stage at 0.7; profile note not clipped |
| Total RP 3 | proposed-trp3-sync.png | Amber states, one-line backups, ownership selector, paged Mappings | Overview tab has no approved rendering (#5) | Open (P1): needs a rendering first; not redesigned here | Overview controls fit; preview; conflict and rollback prompts |
| Story import | (setup Story stage) | Restyled window, visibility chip, pieces review | — | — | Paste a 16 KB backstory (part Y) |

**Verified Classic Era limits** (checked in the 1.15.9 client source, not assumed): no vector icons; no rounded rectangles for panels with edges (masks give circles and pills only, `CreateMaskTexture` with `TempPortraitAlphaMask`); no letter spacing on font strings; one style per font string; the model's lighting and camera. Everything else listed as open or choice is fixable and was not blamed on the client.
