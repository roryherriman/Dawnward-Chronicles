# Audit: design system, window shell and character rail (v0.8 visual fidelity)

Scope: the shared tokens and components (`UI/Style.lua`, `UI/Widgets.lua`, the theme token values in `Core/Themes.lua`) and the window shell (`UI/MainWindow.lua`: chrome, rail, header, navigation, resize grip).
Compared with: [design-system.png](../mockups/design-system.png) and `mockups/source/DesignSystem.dc.html`, plus the rail and header in [journal-dashboard.png](../mockups/journal-dashboard.png) and `mockups/source/Main.dc.html`. The other mockups share the same rail.

**Nothing here has been checked in the game.** The automated suite (L2, against the WoW mock) proves wiring, sizes and colours. Whether it looks right is the owner's in-game comparison (steps at the end).

Priority: P1 is visible on every screen, P2 is visible on some screens, P3 is a detail.

## 1. Design system

| Element | Approved rendering | Before (v0.7) | Now | Difference remaining | Why | Fixable? | Priority | How to validate in game |
|---|---|---|---|---|---|---|---|---|
| Colour tokens | Ground `#0E1219`, Rail `#121825`, Surface `#151B26`, Raised `#1F2838`, Ornament line `#6B5631`, Gold `#D8B26A`, Text `#EFE7D6`, Muted `#A6A08F`, Danger `#E8837A` | Same values | Same values (tested against the hex) | None | — | — | — | Compare swatches with a screenshot colour picker |
| Secondary tones (title white, story text, field label, ghost text, nav text, bright gold, input well and edge, danger edge, progress track, callout fill) | `#F5EEDD`, `#E4DCCB`, `#D8C49A`, `#D9D2C2`, `#C9C2B2`, `#F0D08E`, `#0F141D` / `#33405A`, `#5E3236`, `#232C3D`, `#1A1A17` | Not modelled: titles were gold, inputs used the card colour, ghost/nav text was the plain text colour | `Style.Tones(theme)` derives each from the theme roles; Classic Dawnward lands within a few units of each hex; every theme gets them; all text tones tested at 4.5:1 or more | Small hue differences (derived, not hand-picked), e.g. secondary edge `#414A5A` vs `#3E4C66` | Design choice: derived so the six themes stay consistent | Yes (hand-tune per theme) | P3 | Picker on a title, an input and a ghost button |
| Visibility colours | Private `#B4C6EA`, Public `#93D9BB`, Secret `#EFA9A9`, each on a tinted fill with an edge | Grey, green and orange from v0.2 | The design's values; fills and edges are the colour mixed into the surface (Private on ground ≈ `#1F2738`, design `#1B2436`) | Fill hue slightly less blue | Design choice (one formula for every tone and theme) | Yes | P3 | A Private, a Public and a Secret chip side by side |
| "Needs you" amber | `#F2C46B` on `#2E2410`, edge `#6A5122` | Gold accent | `Themes.STATUS_COLORS.waiting`, chip tone `waiting` | Screens must use the tone (see section 4) | Not done in screens (not owned) | Yes | P2 | "Waiting for your approval" chip |
| Type: screen title | Cinzel 28 / 600, `#F5EEDD` | Cinzel 26, gold | Cinzel SemiBold 28, title white | None | — | — | P1 | Header title next to the mockup |
| Type: entry / section title | Cinzel 18 / 600 | Cinzel 19 | Cinzel 18 | None | — | — | P2 | Card titles |
| Type: eyebrow | Cinzel 12, caps, 0.16 em tracking | Cinzel 11, caps, no tracking | Cinzel 13, caps, no tracking | No letter spacing; one size up gives the same word width ("JOURNAL" 64 px vs 72 px tracked) and stays at the 13 px minimum | True API limit: no letter spacing in WoW; Cinzel has no thin or hair space, and a no-break space (0.25 em) is wider than the design's 0.16 em, so spaced capitals would look excessive | No | P2 | Eyebrows read as small gold capitals, not cramped |
| Type: story text | Alegreya Sans 16 / 1.5 | 15, no extra leading | New `reading` style: 16 with 4 px line spacing (`SetSpacing`) | Screens must opt in (section 4) | Not changed globally: body text in fixed-height cards would lose lines | Yes, per screen | P1 | A journal entry paragraph |
| Type: meta line | Alegreya Sans 14, muted | 13 | New `meta` style 14; small stays 13 (the minimum) | Screens must opt in | As above | Yes | P2 | "Goldshire · Level 24 · Your words" |
| Type: buttons | Alegreya Sans Bold 15 (compact 14) | Regular 15 / 13 | Bold 15 at 34 px and taller, bold 14 below; answer cards stay regular | Weight 700 vs the design's bold: same | — | — | P1 | Any button label |
| Type: chips | 13 / 500 | Regular 13 | Regular 13 | Medium weight (500) is not bundled | Design choice (one more font file for a hardly visible step) | Yes (bundle Alegreya Sans Medium, OFL) | P3 | Chip text |
| Type: minimum | Nothing below 13 | Eyebrow 11 | Every Dawnward style is 13 or more (tested) | — | — | — | P1 | — |
| Spacing scale | 4 · 8 · 12 · 16 · 20 · 28 | 4 · 8 · 12 · 16 · 24 | `Style.SPACE` = the design's steps | — | — | — | P3 | — |
| Control heights | Compact 30 · standard 36 · navigation 44 | Defaults 22 / 20 / 28 | `Style.CONTROL` (compact 30, standard 36, nav 44, input 36, chip 24, icon 36); the shell uses them. `Style.SIZE` keeps the v0.6 defaults because screens lay themselves out around them | Screens still pass their own (mostly 20–26 px) heights | Not done in screens (not owned); changing the defaults would overlap fixed layouts | Yes, per screen | P1 | Measure a toolbar button: 36 px at scale 1 |
| Corner radius | 6 controls, 10 panels, round chips | Square everywhere | Chips, visibility chips, the level badge, the navigation badge and the status dot are round (masked discs); buttons, inputs and panels stay square | Square corners on buttons, inputs, cards | True API limit for cheap shapes: no rounded rectangles or anti-aliased corners without art; round ends are possible only with the game's circle mask | Partly (corner discs per box would cost 8 textures per card) | P2 | Chip ends are round; card corners are square |
| Button: primary | Gold fill, `#F0D08E` edge, dark text | Gold fill, gold edge | Gold fill, bright gold edge, dark text, lighter on hover | Corners | Radius limit (above) | — | P1 | "+ New entry" |
| Button: secondary | `#1F2838` fill, `#3E4C66` edge, text | Card fill, dark edge | Raised fill, stronger edge; hover: lighter fill, gold edge | — | — | — | P1 | "Edit" |
| Button: ghost | No fill, `#2F3A4E` edge always, softer text | No fill and **no edge** until hovered | No fill, edge always, softer text; hover fill | — | — | — | P1 | "Later", "Guide" |
| Button: danger | No fill, `#5E3236` edge, `#F0A39B` text | No fill, no edge, danger text | No fill, dark red edge, light red text | — | — | — | P1 | "Delete" |
| Button: focused | 2 px bright gold outline | — | — | No keyboard focus ring on buttons | True API limit: WoW buttons take no keyboard focus; `FocusChain` covers inputs | No | P3 | — |
| Button: disabled | 45 % opacity | Muted text only | Fill and edge at 45 %, muted text (kept readable) | Text is muted rather than 45 % | Design choice: readability first | Yes | P3 | A disabled pager button |
| Segmented control | Panel track, items borderless, selected raised `#2A3346` with `#4A5874` edge | Joined default buttons, selected gold | Panel-coloured track under the items; items borderless until hovered; selected raised and edged in neutral, title-white text | No 3 px padding inside the track | Design choice: the track never takes more room than the caller gave | Yes | P2 | Journal filters |
| Chips | 24 high, 10 px padding, round, tinted fill + edge per tone (gold, amber, neutral, visibility) | 20 high, square, translucent tint of the accent | 24 high (20 with `Style.CONTROL.chipSmall`), 10 px padding, pill shape, opaque tinted fill and edge, tones `accent`, `waiting`, `muted`, `danger`, `public`, `private`, `secret`; `:SetMaxWidth(w)` cuts with the full text as a tooltip; contrast tested for every tone on every theme and surface | No icon (lock, eye) in visibility chips | True API limit for line icons (no vector art; no verified lock or eye texture in the 1.15.9 files); the word is always shown, so meaning never relies on colour | No | P2 | A Defining chip, a Private chip |
| Inputs | 36–38 high, `#0F141D` well, `#33405A` edge; focused 2 px gold; invalid 2 px danger, message in light red 14 | Card-coloured well, 1 px edge plus a 3 px bar on focus | Dark well, field edge; focused: 2 px gold ring and lighter well; invalid: 2 px danger ring; message `meta` 14 in light red; text inset 10 | Height 36 only where screens pass it (`EditLine(parent, max, Style.CONTROL.input)`) | Not done in screens (not owned) | Yes | P2 | Click a field: 2 px gold ring |
| Panels / cards | Surface `#151B26`, 1 px `#2A3345` edge, pad 14–18 | Panel colour (darker than cards) | Panels are surface-filled like the design's cards; hovered cards get the design's featured look (`#1A2230` fill, `#4A5874` edge); suggestions keep the gold edge and accent bar | Square corners | Radius limit | — | P2 | Side panels on the Journal |
| Callout | Gold edge, `#1A1A17` fill | Panel fill plus a gold glow | Warm dark fill (`calloutFill`) and gold edge | — | — | — | P2 | "A moment awaits" |
| Date block | Cinzel 24 / 700 bright gold day, Cinzel 12 tracked month | Cinzel 19 gold-ish day, small month | Cinzel 24 bright gold day, Cinzel 13 muted month, both centred | Weight 600 (SemiBold) vs 700 | Only SemiBold bundled | Yes (bundle Cinzel Bold, OFL) | P3 | Journal entry dates |
| Progress bar | 6 high, `#232C3D` track, gold fill, round ends | Edge-coloured track | Darker track tone | Height is the caller's (4); square ends | Not done in screens; radius limit | Partly | P3 | Goal bars |
| Tooltips | Not specified | Game tooltip, default title colour | Game tooltip; title in bright gold, body white and wrapped | Stock tooltip border | Design choice: Dawnward does not restyle the shared `GameTooltip` (other addons use it) | Yes, with a private tooltip frame | P3 | Hover the Guide button |
| Close button | 36 square ghost with edge, × icon 18 | "X" letter, no edge | 36 square, edge always, × (multiplication sign) in Alegreya Sans Bold 20 | Glyph rather than a drawn line icon | No vector art | No | P2 | Top-right close |

## 2. Window shell and character rail

| Element | Approved rendering | Before (v0.7) | Now | Difference remaining | Why | Fixable? | Priority | How to validate in game |
|---|---|---|---|---|---|---|---|---|
| Window frame | 1 px `#6B5631` line, rounded 6 | Dark outline, a gold inner line 3 px in, square corners | The 1 px gold frame line only, the content filling to it (`borderInset` 1) | Square outer corners | Radius limit | No | P1 | The window edge is one thin gold line |
| Corner ornaments | Double-L ornament (outer 11 px, inner 4 px) top-left and bottom-right, `#B8954F` | Single 10 px brackets in all four corners | Double-L ornament top-left (outer 12, inner 5, 2 px strokes, ornament gold); bottom-right is the resize grip | Bottom-right shows the grip art instead of the ornament | Design choice: the grip keeps its known look and behaviour; the ornament would overlap it | Yes (draw the grip as the ornament) | P3 | Top-left corner |
| Resize grip | (not in the design) | Chat size-grabber, gold | Unchanged (behaviour and art) | — | — | — | — | Drag the bottom-right corner |
| Rail | 272 wide, `#121825`, 1 px `#2C3648` line, padding 20 / 18 / 16 | Same width; inset 4 from the frame | Same, reaching the frame line | — | — | — | — | — |
| Wordmark | Four-point star (vector) + DAWNWARD, Cinzel 13, gold, tracked | DAWNWARD eyebrow (11, ornament colour), no mark | A small gold jewel (a square turned 45°) + DAWNWARD, Cinzel 13, gold | Jewel instead of a star; no tracking | True API limit (no vector art; no verified star texture; no tracking) | No | P3 | Top of the rail |
| Portrait | 116 circle: 2 px gold ring, 4 px gap, 104 portrait on `#1C2433` | Game portrait with the minimap tracking ring tinted gold (texture coordinates unverified) | Three masked discs (gold ring 116, gap 112 in the rail colour, well 104) under the game's round portrait; falls back to the v0.7 ring where masks are unavailable | Portrait art is the game's 3D-rendered head, not the mockup's silhouette | Design: the addon shows the real character | — | P1 | A clean, even gold ring with a dark gap |
| Level badge | Pill 22 high, ground fill, gold edge, bright gold bold 13, 8 px below the ring | Square 34 × 20, gold text 13 | Pill 40 × 22 (masked round ends), ground fill, gold edge, bold 13 bright gold, 14 px over and 8 px below the ring | — | — | — | P2 | The level sits on the ring's bottom edge |
| Name | Cinzel 21 / 600, centred, wraps to two lines | Cinzel 18 | Cinzel 21, centred, at most two lines; a longer name is cut and shown whole on hover | — | — | — | P1 | A two-word name wraps like the mockup |
| Title | Alegreya Sans 15 italic, `#D8C49A` | 15 regular, gold accent, could wrap | 15 regular in the field-label tone, one line, cut with the full text on hover | Not italic | Italic not bundled | Yes (bundle Alegreya Sans Italic, OFL) | P3 | Title under the name |
| Race · class · pronouns | 14 muted, class in its class colour | 13 muted, class uncoloured | `meta` 14 muted, class in the game's class colour (lightened only if under 4.5:1 on the rail) | — | — | — | P2 | Class name in its colour |
| Homeland and privacy chips | "Goldshire" (gold, house icon) and "Private" (lock icon) | Not shown | Homeland chip from the Homeland field (hidden when empty); privacy chip from the profile fields' own visibility: "Private", "N of M public" or "Public" with an explanatory tooltip (hidden when no field is set); never invented | No icons | Line icons: true API limit | No | P2 | Set a homeland; make one field Public |
| Navigation | 44 high, gap 4, full width, icon 20 at 14, label 17 / 500 `#C9C2B2`; selected: `#1F2838` fill, 1 px `#6B5631` edge, `#F3DCA6` text | 44 high, 8 px wider than the rail padding, label 15, selected: fill, gold edge, gold text and a 3 px accent bar | Rail-width items, icon 20 at 14, label 17 at 46 (Alegreya Sans Regular), nav text tone; selected: raised fill, gold edge, bright gold text and icon, no bar; hover: half fill. The first open now shows the selection (it showed none before a later refresh) | Icons are desaturated game icons, not line icons; weight 400 vs 500 | True API limit (no vector icons); Medium not bundled | No / Yes | P2 | Selected Journal item looks like the mockup's filled panel |
| Story badge | 22 round, gold, bold 13 dark text | Square 24 × 20, regular 13 | 22 disc (masked), gold, bold 13 dark text | — | — | — | P3 | Waiting count on Story |
| Total RP 3 status | 8 px grey dot + 13 muted line | Line only | Dot (gold when Total RP 3 is loaded, neutral otherwise) + line; the tooltip repeats the full line | — | — | — | P3 | Bottom of the rail |
| Guide / Settings | Ghost compact (30), equal halves, gap 8, icons | Ghost (edge only on hover), 30 | Ghost compact with the visible edge, bold 14 | No icons | Line icons: true API limit | No | P2 | Bottom of the rail |
| Header | Eyebrow 12 at 22, title Cinzel 28 `#F5EEDD`, close 36 at the right | Eyebrow 11, title 26 gold | Eyebrow Cinzel 13 at 22, title Cinzel 28 in title white (38 px line box), close 36 | Subtitle line under the title is the section's own | Owned by the screens | — | P1 | Header of every section |
| Content area | 772 wide at 28 padding, top 96 | Same | Same | — | — | — | — | — |

## 3. Files changed

- `DawnwardChronicles/UI/Style.lua`: design-system tokens (`SPACE`, `CONTROL`, `MIN_TEXT`), derived tones (`Mix`, `Tones`, `Tone`), the type scale with named styles (`FontFor`, `UsesBundledFont`, line spacing), text measurement (`ADVANCE`, `TextWidth`), round shapes (`NewMask`, `Disc`, `Pill`), the new frame chrome.
- `DawnwardChronicles/UI/Widgets.lua`: button variants and fonts, icon button, segmented track, card hover, visibility chip, input ring, chips (tones, pill, max width), panel and callout fills, date block, progress track, search box inset, tooltip title colour, dialog buttons.
- `DawnwardChronicles/UI/MainWindow.lua`: layout values from `Main.dc.html`, rail (jewel wordmark, portrait ring, level pill, identity block, chips, navigation, badge, status dot), header fonts, chrome corners, first-open selection fix.
- `DawnwardChronicles/Core/Themes.lua`: visibility colours from the design system, `STATUS_COLORS.waiting`. Theme ids and roles unchanged.
- Tests: `tests/spec/ui_shell_spec.lua`, `ui_components_spec.lua`, `ui_journal_window_spec.lua`, `core_themes_spec.lua`; one colour assertion in `ui_settings_spec.lua` (a default button is now filled with the raised colour, not the card colour).

## 4. Notes for the screen owners

- Heights: use `Style.CONTROL.compact` (30) for buttons inside cards and `Style.CONTROL.standard` (36) for toolbar and dialog buttons; `Style.CONTROL.input` (36) via `Widgets.EditLine(parent, maxBytes, height)` and `Widgets.SearchBox(parent, width, placeholder, onChange, height)`; `Style.CONTROL.progress` (6) for progress bars.
- Text: `Widgets.Label(parent, "reading", true, "reading")` for story text (16 with leading), `"meta"` for meta lines (14), `"day"` for big dates. `Widgets.SetTextRole(fs, tone)` colours a label with any theme role or tone (`heading`, `label`, `accentBright`, `navText`, ...).
- Chips: `Widgets.Chip(parent, text, tone, height)`; tone `waiting` for "Waiting for your approval"; `:SetMaxWidth(w)`; `:SetBase("panel")` when the chip sits on the rail or a panel-coloured area. `Widgets.CHIP_HEIGHT` is now 24.
- `Widgets.VisibilityButton` draws itself as the design's chip (tinted fill and edge, pill shape); screens no longer need their own painter for it.
- Panels are now surface-filled (the design's cards); a `Card` inside a `Panel` is separated by its edge only.
- Tests: `Widgets.LabelFits(text, width, height, variant)` and `Style.TextWidth(text, style)` estimate label widths from the bundled fonts' real advance widths.

## 5. Manual in-game acceptance (compare with journal-dashboard.png and design-system.png)

1. `/reload`, open the journal (`/dawnward`) at the default size (Settings → General → Reset window size). Compare with journal-dashboard.png side by side.
2. Window edge: one thin gold line; a double-L ornament in the top-left corner; the resize grip in the bottom-right still resizes.
3. Rail top: gold jewel and DAWNWARD, then the portrait inside a smooth gold ring with a dark gap (no jagged or square edges, no tracking-border art). If the ring is square or missing, report it: masks did not work and the fallback should have shown.
4. The level number sits in a small rounded pill across the ring's bottom edge.
5. Name in Cinzel, two lines for a long name; title one line in warm gold; race · class · pronouns with the class in its colour.
6. With a Homeland set, a gold "Homeland" chip; next to it "Private" (or "N of M public"). Hover the second chip: the tooltip explains it. Clear the Homeland: the chip disappears.
7. Navigation: Journal selected as a filled panel with a gold edge and bright gold text, the others in quiet text; hover shows a light fill. Story shows a round gold badge when moments wait.
8. Bottom of the rail: a dot and the Total RP 3 line; Guide and Settings as outlined buttons.
9. Header: small gold JOURNAL eyebrow, the title in large white Cinzel, a 36 px outlined close button with ×.
10. Buttons on any screen: primary gold with a bright edge; Edit-type buttons raised with an edge; Later-type buttons outlined; Delete outlined in dark red with light red text. Labels bold.
11. Chips anywhere: round-ended pills, readable text.
12. Click into any text field: a 2 px gold ring. Submit an empty required field: a 2 px red ring and a red message.
13. Switch theme (Settings → General → Lightbound, Shadowbound): every element above follows the theme, nothing unreadable.
14. Drag the window to its smallest size: text still readable, nothing overlaps in the rail.
