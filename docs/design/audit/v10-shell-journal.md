# Audit v0.10: window shell, rail, Journal and the shared design system

Scope: `UI/Style.lua`, `UI/Widgets.lua` (shared components), `UI/MainWindow.lua` (window, rail, header, grip), `UI/JournalView.lua` (dashboard, cards, editor), the fonts in `Media/Fonts/`.
Compared with: [journal-dashboard.png](../mockups/journal-dashboard.png) and `mockups/source/Main.dc.html`, [design-system.png](../mockups/design-system.png) and `DesignSystem.dc.html`, the rail in [character-profile.png](../mockups/character-profile.png). Earlier audits: [shell-and-components.md](shell-and-components.md), [journal.md](journal.md).

**Nothing here has been seen in the game.** L2 tests (WoW mock) prove sizes, positions, fits, colours and wiring. During this work the mock's frame tree was also drawn to PNG at 2x (an approximate renderer using the bundled fonts, not kept in the repository) and compared side by side with the 2x mockup; that is how most of the gaps below were found. It is not a screenshot: line anti-aliasing, font hinting and the portrait differ in game.

Causes: **limit** = verified Classic Era 1.15.9 limit; **deliberate** = kept on purpose (behaviour, data or readability rule); **not done** = possible, not done in this pass.

## What changed in v0.10, in one view

- **Line icons are possible after all.** The 1.15.9 client has Line regions (`Frame:CreateLine`, `SimpleLineAPIDocumentation.lua`: `SetStartPoint`, `SetEndPoint`, `SetThickness`, colour via `SetColorTexture`). `Style.ICONS` holds the mockup's SVG icons as strokes in a 24 px box (circles and arcs as short polylines) and `Style.LineIcon(parent, name, size)` draws them. v0.9 listed "no vector icons" as a limit; for line icons it is not one. Where `CreateLine` is missing every caller keeps its v0.9 text or glyph.
- **Tracked capitals.** `Widgets.TrackedLabel` sets each letter in its own font string, spaced by the bundled font's advance widths plus 0.16 em (0.18 em for the wordmark, 0.14 em for date months). Letter spacing is still not a font string feature (limit), but the look is reproduced.
- **The design's weights.** Alegreya Sans Italic and Medium (unmodified, google/fonts) and a Cinzel Bold instance (fontTools, wght 700), OFL; sources and hashes in `Media/Fonts/FONTS.txt`. Each falls back to its v0.9 file if it fails to load.

## 1. Shared components (benefit every screen)

| Element | Approved rendering | Before (v0.9) | Now | Remaining difference | Cause | In-game check |
|---|---|---|---|---|---|---|
| Icons | Stroke icons (book, person, sparkle, chronicle, ×, +, magnifier, pencil, bin, check, ?, gear, house, star) | Words, glyphs, desaturated game icons | `Style.LineIcon` with those 15 icons; `Button:SetIcon(name)` (icon 16 / 14 + gap 8, centred with the label, coloured with it, `iconRole` to override), `Chip:SetIcon(name)` (13 + 6), `IconButton("X")` draws the line ×, `SearchBox` draws the magnifier | Stroke joins are butt-ended quads (no round caps); circles are 12–16 segments | limit (Line regions have no caps or joins) | Look at the nav icons and the × at 100 % and 70 % scale: no gaps at corners, no jagged diagonals |
| Eyebrows | Cinzel 12 caps, 0.16 em tracking, `#C9A55E` | Plain Cinzel 13 caps, no tracking | Tracked (`Widgets.TrackedLabel`) in panel titles, callouts, the header eyebrow, wordmark, date months; tightens its tracking rather than overrun a box | 13 instead of 12 | deliberate (13 px minimum) | `ACTIVE GOALS` letters evenly spaced, none overlapping |
| Eyebrow colour | `#C9A55E` | Theme ornament (Shadowbound `#8E3A40` read at 2.1–2.5:1) | Tone `eyebrowText`: the ornament, lightened only until 4.5:1 on the lightest surface (unchanged in Classic Dawnward) | Shadowbound eyebrows are a lighter crimson than its ornament | deliberate (readability) | Shadowbound: eyebrows readable |
| Bright gold | `#F0D08E` | `#E4C997` (mixed toward white: greyed) | `#F2CE8A` (`Style.Brighten`: scaled to keep the hue, then 15 % white) | within 4 units per channel | — | Dates and gold chips read gold, not beige |
| Edges and fills | `#3E4C66`, `#4A5874`, `#2A3346`, `#33405A`, dot `#6E7891`, callout `#1A1A17` | Greyed (`#414A5A`, `#525A69`, `#2A3342`, `#394253`, `#6F706F`, `#181A1D`) | `#3E4C65`, `#475775`, `#273347`, `#364258`, `#6C7990`, `#1C1914` (`Style.Scale` keeps the blue) | ≤ 4 units | — | Secondary button edge and the featured card edge look blue-grey |
| Chips | 24 high, medium 13, gold `#2A2213` fill + `#6B5631` edge, amber `#2E2410` + `#6A5122`, icons | Regular 13, gold fill = surface + 10 % gold (`#292A2D`, grey) | Medium 13 (`chip` style), gold `#2B2415`, amber `#2E2514` / `#6A562F`, optional icon | — | — | "Defining" chip: warm dark gold fill with a star |
| Segmented | Track with 1 px edge, 3 px padding; items sized to their words (12 px padding), 2 apart | Equal items; each screen drew its own track | `Widgets.Segmented(..., { fit = true, framed = true })`: `seg.frame` is the track; `Widgets.SegmentWidths`. Default (no options) unchanged for other screens | Square ends | limit/not done (see corners) | Journal filter: All narrower than Defining, inside an outlined track |
| Search box | Magnifier at 12, text at 36, placeholder 15 | No icon, placeholder 13 | Icon, inset 36, placeholder in the input size (`placeholder` style 15) | — | — | Click: the gold ring; the icon stays grey |
| Cards | Featured: `#1A2230` fill, `#4A5A78` edge | Journal-only painter | `Card:SetFeatured(on)`; hovered featured card gets the gold edge | Square corners | not done (see corners) | Defining entry lifted |
| Progress bar | 6 high, round ends | Square ends | Track and fill are pills where masks work; the fill is never narrower than its ends | — | — | Goal bars have round ends |
| Date block | Cinzel 24 / 700 day, 12 tracked month | SemiBold day, untracked 13 month | Cinzel Bold day; tracked month centred in the block | Month 13 instead of 12 | deliberate (minimum) | Dates line up, month evenly spaced |
| Panels | Side panels padding 14 / 16 | 14 everywhere | `Widgets.Panel(parent, title, { padX })`, title fits the panel (`panel.titleReserve` keeps room for a control) | — | — | — |
| Tooltips on regions | — | `Widgets.Tooltip` hooked any target | Font strings, textures and lines keep the text but are never hooked (they have no mouse scripts; the client would raise an error); `Widgets.CanHaveTooltip` | — | — | — |
| Text width estimates | — | `·`, `×`, `…`, `—` counted as 0.6 em | Real advances per file (`Style.ADVANCE_EXTRA`); estimates follow the file actually loaded | — | — | — |
| Corner radius (buttons 6, cards 10, nav 8) | Rounded | Square | Square | Square corners on buttons, inputs, cards, nav items | not done: masks give circles only (limit); a rounded rectangle would need corner discs over a known background colour, and ghost buttons, chips on varied surfaces and pooled cards do not know it reliably; a wrong guess shows dark corners, worse than square | — |
| Keyboard focus ring on buttons | 2 px gold | none | none | — | limit (buttons take no keyboard focus; inputs keep their 2 px ring) | — |

## 2. Window shell and rail

| Element | Approved rendering | Before (v0.9) | Now | Remaining difference | Cause | In-game check |
|---|---|---|---|---|---|---|
| Frame, proportions | 1100 × 720, 1 px gold line, rail 272, content 772 at 28 padding | Same | Same | Outer corners square (radius 6) | limit | — |
| Top-left ornament | Double L, `#B8954F` | Double L (2 px) | Unchanged | Stroke 2 vs 1.5 | deliberate (1 px lines vanish at 70 % scale) | — |
| Bottom-right corner | The same ornament turned 180° | Chat size-grabber art, gold | The grip **is** the ornament (two gold Ls, 18 px, 6 in), brighter on hover and while dragging; scaling resize, saved scale and Settings → Reset window size unchanged | — | — | Drag the bottom-right ornament: the window scales; Reset window size restores 100 % |
| Wordmark | 18 px four-point star, DAWNWARD Cinzel 13 tracked 0.18 em | Rotated square, untracked | Line star + tracked DAWNWARD (`TrackedLabel`) | — | — | Star crisp, text evenly spaced |
| Portrait | 116 ring, 4 px gap, 104 well, level pill on the ring | Same (masked discs) | Unchanged | The game's 3D head instead of the mockup's silhouette | deliberate (real character) | — |
| Name | Cinzel 21, two lines | Same | Same | — | — | — |
| Title | Alegreya Sans 15 *italic*, `#D8C49A` | Regular 15 | Italic (bundled Alegreya Sans Italic); label tone `#E1C795` | Tone 9 units warmer than `#D8C49A` | not done (derived tone shared with field labels) | Title in italics |
| Race · class · pronouns | 14 muted, class coloured | Same | Same | — | — | — |
| Homeland chip | House icon + name | Name only | House line icon + name (medium 13); no privacy chip | — | — | — |
| Navigation | Line icons 20 at 14, label 17 / 500 at 46, selected `#1F2838` + `#6B5631` + `#F3DCA6` | Desaturated game icons, Regular 17 | Line icons (book, person, sparkle, chronicle) in the label's colour; Medium 17; selected as before | Selected text `#F2CE8A` vs `#F3DCA6` (accent bright); corners square | deliberate (one bright gold) / see corners | Selected item: gold icon and text |
| Story badge | 22 gold disc, bold 13 | Same | Same | — | — | — |
| Total RP 3 line | Dot + "Total RP 3 · sync off" 13 muted | "Total RP 3 · profile "…"" (no sync state) | "Total RP 3 · sync on / sync off" from the ledger (`TRP3Commands.AnyManaged`, read only, failures read as off); gold dot when on; profile in the tooltip; "not installed (optional)" / "installed, not loaded" / "status unavailable" otherwise | — | — | With Total RP 3 loaded and sync off: grey dot and "sync off"; turn sync on: gold dot |
| Guide / Settings | Ghost compact, ? and gear icons | Text only | Icons + text | — | — | — |
| Close | 36 square, 18 px line × | × glyph | Line × (scaled with the button) | — | — | — |
| Header eyebrow | Cinzel 12 tracked | Untracked 13 | Tracked 13 | 13 vs 12 | deliberate (minimum) | — |
| Status line | (none; content runs to the bottom edge) | 20 px status line, content ends 36 above the bottom | Unchanged | 36 px of the content height kept for messages | deliberate (every screen reports results there) | — |

## 3. Journal

| Element | Approved rendering | Before (v0.9) | Now | Remaining difference | Cause | In-game check |
|---|---|---|---|---|---|---|
| Header, subline | Eyebrow, title 28, subline 15 | Same | Eyebrow tracked | — | — | — |
| New entry | + icon, "New entry", 36 high, ~120 wide | "+ New entry" text, 124 | Line + icon, "New entry", width from the label (≈120) | — | — | — |
| Search | Magnifier, 230 × 36 | No icon | Shared search box with icon | — | — | — |
| Filter | Fitted items on a framed track | Equal 62 px items, local track | Shared segmented control, fitted and framed (244 wide; the design's is 249) | — | — | All / Defining / Story / Events snug in the track |
| "A moment awaits" | 44 disc with sparkle, eyebrow 11 tracked, question 17, Answer / Later | Disc with a jewel, untracked eyebrow 13 | Disc with the line sparkle, tracked eyebrow 13, padding 18 | Eyebrow 13 vs 11; question 16 vs 17 | deliberate (minimum; one reading size) | — |
| Entry card | Date block, title, chip, meta, body 16/1.5, footer | Same structure; footer: "Defining" button (80) + Edit + Delete (text) | Footer: square star toggle (gold when defining) + Edit (pencil) + Delete (bin), all icons | The mockup has no Defining toggle (only the chip) | deliberate (behaviour: any entry can be marked) | Star toggles the Defining chip |
| Defining chip | Gold chip with a filled star | Text only | Line star (outline) + text | Outline star, not filled | limit (lines only; no star texture verified) | — |
| Event card | Title + meta, no footer | Footer row holding only "Defining" | No footer: the star sits at the end of the meta line, centred on it; the card is 46 px shorter | — | — | A level-up card is title + meta + star |
| Meta line of notes | "Goldshire, Elwynn Forest · Level 24 · Your words" | "Your words" | "Your words" | No place or level on notes | deliberate (notes record none; nothing is guessed) | — |
| Draft actions | Approve (check) + Reject | Approve + Edit + Delete + Defining | Approve (check icon) + Edit + Delete + star | No separate Reject | deliberate (v0.7: Delete rejects) | — |
| Highlighted word in story text | "**Compassionate**" in gold | Plain | Plain | not done | the text is stored plain; colouring needs markup or the development's trait name | — |
| Scroll bar | Slim 6 px, always drawn | Slim, shown only when scrolling is possible | Same | Hidden when everything fits | deliberate | — |
| Right column | Panels padding 14 / 16, "All" link 14 regular | Padding 14, link bold 14 | Padding 16 sides; link in regular 14 (meta), underlined; title keeps room for it | — | — | — |
| Goal bars | 6 high, round | 6 high, square | Round ends | — | — | — |
| Empty journal | (not drawn) | Centred text card | Gold book icon above the text | — | — | New character: icon + explanation |
| Entry editor | (design-system form: 36 inputs, labels `#D8C49A`, 36 buttons) | 22 px inputs and buttons, muted 13 labels | 36 px title input, 36 px Save (primary) and Cancel (ghost), labels meta 14 in the label tone; each error line has its own room (L2-checked) | — | — | New entry: tall fields; Save with an empty text shows the red line above the buttons, not over them |

## 4. Fonts audit

Bundled (all OFL, `Media/Fonts/`): Cinzel SemiBold, **Cinzel Bold** (new), Alegreya Sans Regular, Bold, **Italic**, **Medium** (new). Game templates used by any screen are all mapped to a bundled style (`GameFontNormalHuge` → screen 28, `GameFontNormalLarge` → title 18, `GameFontHighlightLarge` → name 18, `GameFontNormalSmall` → eyebrow 13, `GameFontNormal` → label bold 14, `GameFontHighlight` → body 15, `GameFontHighlightSmall` → small 13, `GameFontDisableSmall` → 13, `ChatFontNormal` → input 15); no Dawnward style is under 13 (tested over `Style.FONTS`).

| Style | File, size | Used in the shell and Journal for |
|---|---|---|
| screen | Cinzel SemiBold 28 | Window title |
| railName | Cinzel SemiBold 21 | Rail name (2 lines) |
| title | Cinzel SemiBold 18 | Card titles, editor heading |
| eyebrow | Cinzel SemiBold 13, tracked | Header eyebrow, wordmark, panel titles, callout eyebrow, date months |
| day | **Cinzel Bold** 24 | Card dates |
| reading | Alegreya Sans 16, +4 leading | Card text, callout question, empty states |
| body | Alegreya Sans 15 | Goal titles, place names, subline |
| meta | Alegreya Sans 14 | Card meta, identity line, editor labels, "All" link |
| small | Alegreya Sans 13 | Captions, place details, Total RP 3 line, status line |
| italic | **Alegreya Sans Italic** 15 | Rail title |
| nav | **Alegreya Sans Medium** 17 | Navigation |
| chip | **Alegreya Sans Medium** 13 | Every chip |
| placeholder | Alegreya Sans 15 | Search placeholders |
| button / buttonSmall | Alegreya Sans Bold 15 / 14 | Buttons 34 px and taller / compact |
| badge | Alegreya Sans Bold 13 | Level pill, Story count |

Other screens still label some eyebrows with plain `Widgets.Label(..., "eyebrow")` (Character group headings and tile keys, Settings, TRP3 page, setup wizard): those are untracked and sit beside tracked panel titles. They can switch to `Widgets.TrackedLabel(parent, "eyebrow", "eyebrow")` (same calls for text, colour and justification).

## 5. Tests

New: `tests/spec/ui_fidelity_v10_shell_spec.lua` (12 L2 tests: wordmark position and fit, nav icons and selection colours, italic title, homeland icon and fit, Guide/Settings/close icons with fitting labels, Total RP 3 sync line and dot from the ledger, the grip ornament and hover, tracked header eyebrow inside the title column, toolbar without overlap, footerless event cards with the star centred on the meta line, editor heights and error-line room, callout and empty-state icons, side panel padding and title room). `tests/spec/ui_components_spec.lua`: 8 tests for the v0.10 components (tooltip guard on regions, every line icon inside its box and recoloured, button icon centring and widths, tracked labels, fitted framed segmented control and the unchanged default, chip icon, gold chip tones, featured card, round progress ends, search icon, tone values). `ui_shell_spec.lua`: font weights and fallbacks, the Total RP 3 line. `ui_journal_dashboard_spec.lua`: fitted filter items, icons on actions, sparkle disc. The mock gained `CreateLine` (records start, end, thickness).

## 6. In-game checks (in order)

1. `/reload`, `/dawnward`, Settings → General → Reset window size; put journal-dashboard.png beside it.
2. **Line icons render at all** (nav, ×, Guide ?, Settings gear, magnifier, + on New entry, pencil and bin on cards, sparkle in the callout, house on the homeland chip). If any shows nothing, report it: the fallback (text) only applies when `CreateLine` is missing, not when a line draws empty.
3. Icons at window scale 0.7 and 1.4 (drag the bottom-right ornament): strokes stay visible, no broken corners.
4. Tracked eyebrows: DAWNWARD, JOURNAL, ACTIVE GOALS, A MOMENT AWAITS · 1 OF 2, NOV under dates. Letters evenly spaced, none touching or overlapping. If letters overlap, the advance widths do not match the client's rendering: report the scale and the word.
5. Fonts: the rail title is italic; navigation and chip labels look a little heavier than body text; dates heavier than titles. If any of these looks like the regular face, a file failed to load (they then fall back silently).
6. Bottom-right ornament: gold double L; hover brightens it; drag resizes; Reset window size still works.
7. Total RP 3 line with Total RP 3 loaded: "sync off" and a grey dot; after turning sync on in the Total RP 3 page, "sync on" and a gold dot.
8. Journal: filter items snug to their words; the star toggle gold on a defining entry; a level-up card without a footer, star at the end of its meta line; New entry opens the editor with tall fields and buttons; Save empty: red line between the text and the buttons.
9. Themes Lightbound and Shadowbound: eyebrows readable, icons follow the text colours.
