# Audit: Settings, first-time setup, Total RP 3 page and story import (v0.8 visual fidelity)

Scope: `UI/SettingsPanel.lua` (General, Story, Data pages), `UI/SetupWizard.lua`, `UI/TRP3Page.lua` (including the Mappings tab) and `UI/ImportWizard.lua`.
Compared with: [proposed-trp3-sync.png](../mockups/proposed-trp3-sync.png) (`mockups/source/TRP3Sync.dc.html`), [first-time-setup.png](../mockups/first-time-setup.png) (`mockups/source/SetupWizard.dc.html`) and [design-system.png](../mockups/design-system.png) for controls. There is no mockup for the General, Story and Data pages or the import window: they follow the TRP3 mockup's settings frame (sub-tabs, cards) and the design system.
Base: `origin/claude/upbeat-mendel-ds1ct4` at `d7409bf`.

**Nothing here has been checked in the game.** The L2 suite (WoW mock) proves wiring, sizes, colours and that text fits by the bundled fonts' advance widths. Whether it looks right is the owner's in-game comparison (steps at the end).

No behaviour changed: every action still calls the same function as before (`Actions.*`, `Commands.Execute`, the guarded `TRP3Commands` / `TRP3Sync` functions, `StoryImport.*`). No saved data changed.

Priority: P1 is visible at a glance, P2 is visible on inspection, P3 is a detail.

## 1. Settings (General, Story, Data)

| Element | Approved rendering | Before (v0.7) | Now | Difference remaining | Why | Fixable? | Priority | How to validate in game |
|---|---|---|---|---|---|---|---|---|
| Page switcher | Sub-tabs 34 high in a rail-coloured track with 3 px padding, selected raised (`TRP3Sync.dc.html`) | 420 × 22 segmented row at y 8 | 4 × 104 × 36 segmented (shared `Widgets.Segmented`), selected raised and edged, at the top of the content | No 3 px padding inside the track; no 1 px track border | Design choice of the shared segmented control (shell audit) | Yes (shared component) | P2 | Settings → the four tabs read as one control, the current one raised |
| Done | Not in the mockup (the close × only) | Primary 90 × 22 at the bottom right | Secondary 96 × 36 at the right of the switcher row; the bottom 40 px are now content | A button the mockup does not show | Design choice: keeps the existing way back to the journal (tested); secondary so the page's own primary (Approve and write) is the only gold button | — | P3 | Done at the top right, not gold |
| Page width and ground | Cards on the window ground, full content width (772) | Pages 580 wide on a panel-coloured fill | Full 772 width on the window ground; every group is a panel (the design's card) | — | — | — | P1 | Cards span the content width |
| Grouping | Card with an eyebrow heading per group | Loose headings (GameFontNormal) and notes (13 px) at fixed y; Data had Simulation between Backup and Your story | Panels with Cinzel eyebrow headings and a one-line description (meta 14, muted, at most two lines): Appearance; Interface and help; Story settings; Backup and sharing, Your story, Simulation mode (in that order) | — | — | — | P1 | Each page shows bordered groups with small gold capitals |
| Setting rows | (design system: label, description, control) | Buttons only, help in tooltips | Each setting is a row: name (bold 14, field-label tone) over a one-line description (meta 14, muted), control right-aligned in a fixed column, 1 px rules between rows; the full help on hover over the text | — | — | — | P1 | General → four rows, each with a button at the right |
| Story settings control | Clear active state | Cycle buttons "Moments: Normal  ›" 22 high, three per row; the options only in the tooltip | One segmented control per setting showing every option ("Rare · Normal · Frequent · Off"); the value in use raised and edged; one click sets that value directly (same `Actions.SetStoryPref` / `SetTracking`); options in a natural order (pace: Brisk, Standard, Slow) | Segments are equal width within a control | Shared segmented control has equal items | Yes (per-item widths in `Widgets.Segmented`) | P1 | Story → every row shows its options; click one, it becomes the raised one and the status line confirms |
| Theme gallery | Theme tiles (design system) | 36 high tiles, square 14 px swatches, selection = neutral raised fill | 40 high tiles, round swatches with an edge ring, the theme in use raised plus a 3 px gold bar | — | — | — | P2 | General → the current theme has a gold bar on its left |
| Buttons | Compact 30 in cards, standard 36 in toolbars | 22 px everywhere | Compact 30 in rows and panels, 36 for the switcher and Done; labels measured to fit (L2) | Square corners | True API limit (no rounded rectangles without art; shell audit) | No | P2 | — |
| Privacy and backup text | — | Hint in 13 px under the buttons | Description of the Backup panel (meta 14), always two lines or fewer | — | — | — | P3 | Data → Backup and sharing |
| Reset window size, guide, setup, minimap | — | Buttons in two lines | One row each with a description | — | — | — | P2 | General → Interface and help |

## 2. First-time setup wizard

| Element | Approved rendering | Before (v0.7) | Now | Difference remaining | Why | Fixable? | Priority | How to validate in game |
|---|---|---|---|---|---|---|---|---|
| Dialog | 820 × 600, 236 rail, 1 px gold frame, radius 8 | Same size, square | Same; fits small screens by scale | Square corners | True API limit | No | P2 | — |
| Wordmark | Star + DAWNWARD (Cinzel 13, gold, tracked) | "DAWNWARD" Cinzel 18 in title white | The shell's gold jewel + DAWNWARD Cinzel 13 gold | Jewel not star; no tracking | True API limit (no vector art; no letter spacing) | No | P3 | Top of the rail |
| Rail eyebrow | FIRST-TIME SETUP, 11 px | Same text; mode texts up to three lines ("PREVIEW  -  TEST MODE: NOTHING IS SAVED UNLESS YOU CHOOSE") | 13 px (minimum); mode texts shortened to two lines at most ("PREVIEW · TEST MODE", "SIMULATION · PREVIEW ONLY", "READ-ONLY · NOTHING SAVED"); the rail note still explains the mode in full | 13 vs 11 px | Readability rule: nothing below 13 | No (by rule) | P3 | /dawnward dev setup: the eyebrow is two lines and never touches the steps |
| Steps | 44 high, 26 px round badges; done = gold-tinted badge with check; current = gold badge, raised row with ornament edge; future = edged badge, muted text; label 16 | 40 high, 24 px square badges, label 15 | 44 high, 26 px round badges (`Style.Disc` ring + fill; square with an edge where masks are unavailable), the three states as designed, labels Alegreya 16, colours title white / ghost text / muted | Check is the game's check texture, not a line icon | True API limit (no vector icons) | No | P1 | The rail matches the mockup's six rows |
| Header | Eyebrow STEP n OF 6; title Cinzel 26; subtitle 15 `#BDB6A6`; 36 px close | Title Cinzel 18; subtitle wrapped; 30 px close | Title Cinzel 28 (the shell's screen title style), subtitle one line in the nav-text tone, 36 px close at the content edge | 28 vs 26 | Design choice: one screen-title size across Dawnward | Yes (a 26 style) | P2 | Title is large white Cinzel |
| Fields | Label bold 14, input 40 high, hint 13 below, 14/16 grid gaps; error 14 in light red with an icon | Inputs 28 high, rows 72 apart (hint and next label touched) | Inputs 36 (design-system input), rows 80 apart; hint 4 px under the input; error replaces the hint; L2 proves no overlap | 36 vs 40; error has "!" instead of an icon | Design system input height; no vector icon | Yes / No | P2 | Type 101 characters into Title: a red ring and a red line, nothing overlaps |
| Portrait and game identity | Not in the mockup | 56 px portrait | 48 px portrait and the identity line (kept: a feature) | Extra row compared to the mockup | Design choice: the live portrait is a v0.7 feature | — | P3 | Character stage |
| About them | Text area 96 high | 80 | 80 | 16 px shorter | Vertical space: the portrait row is kept | Yes (drop the portrait) | P3 | — |
| Privacy note | Private-coloured box (`#1B2436` / `#3A4D73`), lock icon, `#C9D6F0` text | Gold callout, 13 px text, 24 px Import button | Private chip colours from `Widgets.ChipColors`, text the Private colour lightened, Import a story… 30 px | No lock icon | True API limit (no verified lock texture) | No | P2 | Box is blue-grey, not gold |
| Story choices | (not in the mockup) | 26 px cycle buttons, "Click to change." | 30 px, a gold "›" at the right, tooltip lists every option with the current one marked | Still cycle buttons, not segmented | Design choice: the wizard's long labels ("Never (events are still recorded)") do not fit side by side | Yes, with shorter labels | P3 | Story stage: hover a choice |
| Footer | Set up later (quiet), Back (secondary), Next: Story (primary), 38 high | 30 high | 36 high (standard), Next 170 wide (every "Next: …" label measured) | 36 vs 38 | Design system standard height | — | P2 | — |
| Theme tiles | — | Square swatches | Round swatches, gold bar on the chosen theme | — | — | — | P3 | Appearance stage |

## 3. Total RP 3 page (Settings → Total RP 3)

| Element | Approved rendering | Before (v0.7) | Now | Difference remaining | Why | Fixable? | Priority | How to validate in game |
|---|---|---|---|---|---|---|---|---|
| Overall layout | Strip, then card (flex) + 258 column, 16 apart, full width | 10 px inset each side, 12 apart; 510 px tall page | Full content width (772), columns 16 apart, 538 px tall page | — | — | — | P1 | Card and right column fill the content area |
| Summary strip | Card, padding 12/16, eyebrow 11 + value 15, 1 px dividers, Experimental chip at the right | 54 high, values could wrap | 62 high, eyebrow Cinzel 13 + value 15 on one line; a longer value is cut and shown whole on hover; Experimental chip centred at the right | Eyebrow 13 vs 11, no tracking | Readability minimum; no letter spacing | No | P2 | Hover a long profile name: full text |
| Feature tabs (Biography, Traits, Mappings) | Not in the mockup (v0.8 addition) | 288 × 22 | 276 × 30 segmented, state chip on the same row | Extra row compared to the mockup | Needed for the v0.8 Mappings tab | — | P3 | — |
| Title and chip | Cinzel 18 title; amber "Needs your approval" chip | Cinzel 18; chip in gold accent | Cinzel 18; "Needs your approval" in the shared `waiting` (amber) tone | Chip sits on the tab row, not the title row | Space: the title row carries the full title width | Yes | P2 | Make a fact Public with biography sync on: amber chip |
| Explanation and status | Muted 14 | Muted 13, status small 13 up to two lines | Explanation meta 14 (two lines max); status one line, full text on hover | — | — | — | P2 | Hover the status line |
| Kept-text box | `#11161F` / `#232C3D`, 14 px | Ground fill, plain edge, 13 px | Input-well fill and track edge (shared tones), text 14 in the nav-text tone, two lines | — | — | — | P2 | — |
| Proposed-write box | `#132820` / `#2F5D4F`, text `#BFE9D5` | **Local tint**: Public at 10 % alpha with a 45 % edge, 13 px, 6 lines | Public chip fill and edge (`Widgets.ChipColors`), text the Public colour lightened, heading in Public green, 4 lines (more: "Copy text shows all") | Lines are plain text, not "**+ Background:**" bold runs | True API limit for mixed weights in one line cheaply (inline colour codes only) | Partly (colour the "+ label:" part) | P2 | Box is green, text light green |
| Never shared | Box with eyebrow, counts with inline Private / Public chips | 13 px, three-line unsupported text | 14 px counts (two lines) and a shorter "Title, race, class, age and homeland: only if you hand them over on Mappings; name, pronouns and the other fields never." (two lines); the long version is the box's tooltip | No inline chips inside the sentence | True API limit: font strings cannot hold frames inline | No | P2 | Hover the box: the full rules |
| Action row | 36 high: Approve and write (primary, check icon), Not now (ghost), Stop syncing (danger, right) above a 1 px rule | 26 high | 36 high, rule above; disabled/enabled exactly as before | No check icon | No vector icon | No | P1 | — |
| Conflict callout | Amber: `#6A5122` edge, `#18170F` fill, amber eyebrow, 14 px text, Keep yours (secondary) + Use Dawnward's (ghost) 30 high | Gold callout, 13 px, 24 px buttons | Amber edge and warm fill, amber title, 14 px story-tone text (5 lines, full on hover), 30 px buttons | Painted locally | Widgets.Callout has no tone yet (proposal below) | Yes | P1 | Edit a synced trait in Total RP 3: amber box |
| Backups | One line each: "About · before last write" left, "27 Oct" right; Roll back… secondary | Two-line rows (36 high) | One 30 px row each: name left (cut, full on hover), short date right in its own column; the full date in the tooltip; Roll back… and Exact restore… 30 high | — | — | — | P2 | Settings → Total RP 3 → the backup list |
| Mappings: selector | (not in the mockup) "Dawnward" needs ~74 px | 162 / 3 = 52 px items: "Dawnward" cut | 240 / 3 = 78 px items, 20 high (L2: every label fits) | — | — | — | P1 | Mappings tab: "Dawnward", "TRP3", "Off" fully readable |
| Mappings: rows | — | One 34 px line block; detail limited to 226 px | Two lines: name with selector and Import on the first, the detail across the full width on the second; rules between rows; name and full detail on hover | Long details are cut (full on hover) | Space | — | P2 | Hover a row |
| Mappings: shared-profile warning | — | 13 px, up to three lines | One line, amber when it warns, full text on hover | — | — | — | P2 | Shared profile: amber line |
| Rollback, authorize, import confirmations | Dawnward dialog | Unchanged | Unchanged (same texts, same guards) | — | — | — | — | — |

## 4. Story import window

| Element | Approved rendering | Before (v0.7) | Now | Difference remaining | Why | Fixable? | Priority | How to validate in game |
|---|---|---|---|---|---|---|---|---|
| Header | (follows the setup wizard) | Cinzel 18 title, 30 px close | Cinzel 28 title, subtitle in the nav-text tone (two lines max), 36 px close | — | — | — | P2 | /dawnward biography |
| Paste area | — | 280 high | 240 high (scrolls), count line meta 14 | 40 px shorter | Space for 36 px controls | — | P3 | — |
| Split choice | Clear active state | Cycle button "Split: by sentence  ›" | "Split" label + segmented "By sentence · By paragraph", the one in use selected | — | — | — | P2 | Click By paragraph: it is selected |
| Buttons and inputs | 36 standard | 26–30 buttons, 22 input | 36 everywhere; visibility chip 30 high (draws itself) | — | — | — | P2 | — |
| Notes | — | Gold callouts, 13 px | Plain panels, meta 14, two lines | — | — | — | P3 | — |
| Excerpt | — | Unbounded body text | Reading 16, three lines, the whole piece on hover; hidden with the controls when nothing waits | — | — | — | P2 | A long paragraph: hover the quote |
| Status | — | 13 px, unbounded | Meta 14, two lines, full message on hover | — | — | — | P3 | — |

## 5. Files changed

- `DawnwardChronicles/UI/SettingsPanel.lua`: layout constants (`SettingsPanel.LAYOUT`), panels and setting rows, segmented story controls (`Options`, `SegmentWidth`), Done in the switcher row, theme tile marks. `NextValue`, `ValueText`, `ButtonText` (now without the "›"), `ButtonHelp` kept as pure helpers.
- `DawnwardChronicles/UI/SetupWizard.lua`: layout values from the mockup, round step badges, header, fields, private note, cycle chevrons and tooltips, theme swatches, shorter mode eyebrows.
- `DawnwardChronicles/UI/TRP3Page.lua`: layout constants, strip, card, boxes in shared tones (local tint removed), amber callout, backup rows, Mappings rows and selector widths, hover text for every shortened line. Text changes: `MAPPINGS_EXPLAIN`, `UNSUPPORTED_TEXT` (+ `UNSUPPORTED_DETAIL`), `UnsupportedText()` order, `STATE_CHIP.ready` tone, `PREVIEW_LINES` 6 → 4.
- `DawnwardChronicles/UI/ImportWizard.lua`: header, 36 px controls, segmented split choice, note panels, hover text.
- Tests: `ui_settings_spec.lua`, `ui_story_spec.lua` (its story-settings test drove the old cycle buttons), `ui_trp3_page_spec.lua`, `ui_setup_layout_spec.lua`, `story_import_spec.lua`.

## 6. Shared-component proposals (implemented locally)

1. `Widgets.Callout(parent, title, tone)` with tone `waiting` (amber edge, warm fill, amber eyebrow), for "needs you" callouts. Local: `paintAmber` in `TRP3Page.lua`.
2. `Widgets.Panel` tone (`private`, `public`): a panel in a visibility chip's colours. Local: the setup wizard's privacy note and the TRP3 "add" box (both use `Widgets.ChipColors`).
3. `Widgets.SettingRow(parent, name, description, help, controlWidth)`: name, one-line description, control column, rule. Local: `settingRow` in `SettingsPanel.lua`.
4. `Widgets.Segmented` options: per-item widths and the design's 3 px track padding with a 1 px track edge.
5. A shortened-text helper: one line or N lines (`SetMaxLines`) plus a hover area with the full text. Local: `oneLine`, `paragraph`, `hoverOver` in `TRP3Page.lua` and similar code in the other files.
6. A round badge (edge disc + fill disc, square fallback) for numbered steps and swatches. Local: wizard steps, theme swatches.

## 7. Tests added (L2, mocked client)

- Settings: switcher and Done share the top row and fit; every panel fits its page without overlapping; one row per story setting with every option, each label fitting its segment, each description on one line; exactly one option selected and following the saved value; General and Data button labels fit and use design-system heights; the theme in use is marked.
- Story: the story settings test now drives the segmented controls (same actions, same saved values).
- Total RP 3: selector items fit "Dawnward" (≥ 74 px); right-column and action labels fit; strip columns hold the mockup's values; the Biography boxes stack above the action rule; explanation texts fit their lines; the preview box uses the Public chip colours and the plain boxes the input well. Existing geometry assertions updated (page height, column widths, one-line note, one-line backup rows) without weakening any behaviour check.
- Setup wizard: 44 px steps with 26 px badges and their three states; mode eyebrows fit two rail lines above the steps; subtitles fit one line; fields, hints and errors never overlap and the stage fits; footer, cycle and Import labels fit.
- Story import: both split options shown, selected and clickable; both pages fit between header and footer; error line above Category; 36 px controls; labels fit.
- The window scales as a whole (`SetScale` between 0.7 and 1.4), so fitting in UI units holds at the minimum and maximum window scale.

`python tools/check.py`: all checks ok, 898 tests passed, 0 failed (882 before), luacheck 0 warnings.

## 8. Manual in-game acceptance (compare with the named mockups)

1. `/reload`, `/dawnward`, Settings → Total RP 3 with Total RP 3 3.4.1 loaded. Put proposed-trp3-sync.png beside it.
2. Top row: four tabs in one track, "Total RP 3" raised; a Done button at the far right (not gold).
3. Strip: TOTAL RP 3 · LINKED PROFILE · SYNC eyebrows, values on one line, thin dividers, "Experimental" chip at the right. Hover a value: the full text.
4. Card: tabs and the state chip on the first row; "Biography: …" in Cinzel; two muted lines; the kept-text box dark; the proposed-write box green with light green text and a "Copy text" button; the "Never shared" box with two short paragraphs (hover for the rules); Approve and write (gold), Not now, Stop syncing (red outline) along the bottom above a thin rule.
5. With a pending change, the chip reads "Needs your approval" in amber.
6. Create a conflict (edit Dawnward's trait in Total RP 3): the right column shows an amber-edged callout with an amber title, Keep yours and Use Dawnward's side by side, both labels whole.
7. Backups: one line per backup, name left, "27 Oct" right; click one: it is raised; Roll back… and Exact restore… open the same confirmations as before (exact restore names what is no longer Public).
8. Mappings tab: seven rows, each with "Dawnward · TRP3 · Off" (or "Dawnward · Off") fully readable, the detail line under it; staging, Authorize… and its confirmation behave exactly as before (nothing written until Authorize).
9. Settings → General: Appearance card (six tiles, round swatches, gold bar on the current theme) and Interface and help (four rows with a button each). Switch theme: everything follows.
10. Settings → Story: ten rows, each showing all its options; the current one raised. Click another option: it becomes raised and the status line confirms the new value; reopen Settings: it is still selected.
11. Settings → Data: three cards in order Backup and sharing, Your story, Simulation mode; each button works as before (Reset test data still asks).
12. Settings → General → Run setup. Put first-time-setup.png beside it: round step badges (gold for the current stage, a gold-tinted check for done ones), 44 px rows; STEP 2 OF 6, a large Cinzel title, one subtitle line; two columns of 36 px inputs; the blue-grey "Everything starts Private" box with Import a story…; footer Set up later, Back, Next: Story.
13. Type over 100 characters into Title and press Next: a red ring and red line under the field, nothing overlapping the field below.
14. `/dawnward dev setup` and simulation mode: the rail eyebrow is at most two lines and never touches the first step.
15. Character → Import story: Cinzel title, a 36 px close, the "Split" choice with both options; save a long story and review: the quote shows three lines, hover shows the whole piece.
16. Resize the main window to its smallest and largest: nothing overlaps or clips in Settings (the window scales as a whole).
