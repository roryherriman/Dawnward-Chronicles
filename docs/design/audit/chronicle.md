# Audit: Chronicle (v0.8 visual fidelity)

Scope: the Chronicle section, every tab: Memories, Arcs, Goals, Stances, People (cards), Places (list and detail), Review (findings, examine, explain, answered, undo). Files: `UI/ChronicleView.lua`, `UI/ChroniclePlaces.lua`.
Compared with: [chronicle-memories.png](../mockups/chronicle-memories.png) (`mockups/source/ChronicleMemories.dc.html`) and [chronicle-places.png](../mockups/chronicle-places.png) (`mockups/source/ChroniclePlaces.dc.html`). Arcs, Goals, Stances, People and Review have no mockup of their own; they use the Memories card.
Base: `origin/claude/upbeat-mendel-ds1ct4` at `d7409bf` (the design-system and shell pass, see [shell-and-components.md](shell-and-components.md)).

**Nothing here has been checked in the game.** The automated suite (L2, against the WoW mock) proves wiring, sizes and that nothing overlaps; text heights are estimated from the bundled fonts' real advance widths. Whether it looks right is the owner's in-game comparison (steps at the end).

Priority: P1 is visible every time the screen opens, P2 on some records, P3 a detail.

## 1. Owner requirements

| Requirement | What was done |
|---|---|
| Less empty space, denser cards | Cards are as tall as their content (a short memory is about 160 px instead of a fixed 240). Each card goes to the shorter column, so a short card never waits under a tall neighbour's row. A page holds as many cards as fit (up to 8), not a fixed 4. The empty-state and pager no longer take room they do not need (the pager hides on a single page; the count then sits at the right edge, as in the mockup). |
| No rigid fixed-height cards | `ChronicleView.CardLayout` computes each part from the content: title line, meta (up to 2 lines), text (up to 6 lines of the 16 px reading style), progress, chips (wrapping), divider, buttons (wrapping when needed). Paged rather than a scroll frame (the brief allows either); pages are computed by `ChronicleView.Paginate`. |
| Full text in an accessible view | A card that cannot show everything (text over 6 lines, a cut title, a long meta) offers **Read**: the full view of the record (whole title, meta, the text in a scrolling area, chips, and the same actions, including Edit, visibility and Remove), with "< Back to memories". Works for every tab and for examined Review records. Titles still show whole on hover. On Places, the tied memories and list rows show the whole memory or place on hover. |
| Badges and buttons attached to their record | Chips, the visibility chip and every action are children of their card and laid out from the card's own layout; the layout tests check nothing leaves its card or overlaps. Chips that do not fit wrap to a new row (v0.7 silently dropped them). |
| Contradiction answers look like real buttons | Growth / Unreliable / Secret / Correct it / Ignore stay default-variant (filled, edged) compact 30 px buttons, each with its tooltip; Examine is now a compact 30 px default button too (was 22). They are measured so all five fit one row. |
| Keep Places list-and-detail and the Review flows | Kept; Places detail now flows from its content. Examine, Explain, Answered, Undo answer behave as before (tests unchanged apart from geometry), and Continuity's rules still run once per refresh (tested again with the full view open). |

## 2. Memories (and the other card tabs)

| Element | Approved rendering | Before (v0.7) | Now | Difference remaining | Why | Fixable? | Priority | How to validate in game |
|---|---|---|---|---|---|---|---|---|
| Sub-tabs | Track (panel, edge, 3 px pad), items 34 high, 15/500, count 12 in `#8D96A8`, selected raised `#2A3346` / `#4A5874`; Review count in an amber badge | Items 28 high, fixed widths, count in the label colour | Items 34 high on a 40 px padded track, each sized to its label and count; count in a quieter tone (label gold when selected), Review's count in the "needs you" amber | Count the same size as the label (no 12 px inline); no amber pill around Review's count | True API limit: one font per button label (colour codes work inline, size changes do not) | Partly (a separate badge frame per tab) | P2 | Tabs read "Memories 12" with a quieter number; Review's number amber |
| Toolbar | Primary "+ New memory" 36 high, search 240 × 36 with icon, "Newest first · 12 memories" 14 muted at the right | New 30 high, search 30, count 13; pager always shown | New 148 × 36, search 240 × 36 (design input), count `meta` 14; pager (30 px ghost buttons) only with more than one page, and then left of it | No search icon; no plus glyph drawn (a "+" character) | No vector icons (shell audit) | No | P2 | Toolbar height matches the mockup |
| Card grid | Two columns, gap 12, cards sized to content, scrolls | 2 × 2 fixed 379 × 240, gaps 14 / 12, paged by 4 | Two 380 columns, gap 12; heights from content; shortest-column placement; paged by what fits (up to 8) | Paged, not scrolled; masonry rather than CSS-grid rows (less empty space than the mockup's own row alignment) | Design choice (owner: density; paging keeps pooled frames and tests simple) | Yes (scroll frame with pooled cards) | P1 | Short memories stack closer than before; no tall empty cards |
| Card box | `#151B26`, 1 px `#2A3345`, radius 10, pad 14 / 16, gap 8 | Pad 14 all round, fixed rows | Pad 14 top/bottom, 16 sides, 8 between parts, card colour and edge from the shared tokens | Square corners | Radius limit (shell audit) | No | P2 | — |
| Suggested card | Amber edge `#6A5122` on a warm fill `#18170F`, amber chip | Gold edge, gold left bar, gold chip | Amber edge (the chip formula, ≈ `#6A5122`) on the warm callout fill, amber "Suggested · needs your call" chip, no bar; a disputed record gets a dark red edge and red chip | — | — | — | P1 | The suggestion card glows amber, not gold |
| Status chip and date | Chip 24 (tag / goldtag / amber); date 13 muted at the right | Chip 20, date 13 | Shared `Widgets.Chip` 24, capped to the room left by the date (full text on hover if cut); date 13 muted | No star glyph in "Defining" | No vector icons | No | P3 | — |
| Title | Cinzel 17 / 600, `#F5EEDD`, one line | Cinzel 18 in the body colour | Cinzel 18 in the title tone, one line, cut with full title on hover; a cut title also offers Read | 18 vs 17 | Design choice: the shared title style (one size for all entry titles) | Yes | P3 | Title white, not parchment |
| Text | 15 / 1.5, `#E4DCCB`, as many lines as needed | 15, no leading, clipped silently at the card's fixed height | `reading` 16 + 4 px leading in the reading tone; up to 6 lines, then "..." and Read | 16 vs 15; long texts end at 6 lines on the card | Design choice: the shared reading style; a cap keeps cards dense, Read shows the rest | Yes (cap is `LAYOUT.maxTextLines`) | P1 | Body text has more air between lines |
| Chips row | Tag chips, then the visibility chip (with icon), wrapping | 20 high; a chip that did not fit was hidden | 24 high, measured widths, wrap to a second row; visibility chip last, sized to its label | No pin / lock / eye icons | No vector icons; the word is always shown | No | P2 | A memory with a zone shows all its chips |
| Divider and actions | Divider, then 30 px buttons: Accept primary, Edit secondary, Dispute ghost, Remove danger at the right | 26 px buttons with fixed widths | Compact 30 px buttons sized to their labels (12 px padding, tighter or a second row only if needed); same variants; Remove at the right edge | — | — | — | P1 | Buttons as in the mockup row |
| Read (full view) | (not in the mockup: the page scrolls) | None ("full text in Edit") | Ghost "Read" on cards that cut something; full view over the toolbar and cards: Back, date, chip, wrapped title, meta, scrolling text, chips, actions | Stock scroll bar | Shell audit: scroll bars keep the stock style | Yes (custom bar) | P1 | Open a long memory with Read |
| Goal progress | 6 px bar | 4 px | `Style.CONTROL.progress` 6 | Square ends | Radius limit | No | P3 | Goal card |
| Stance "Inner" button | — | "Inner: pri" | "Inner: Private" (the level spelled out) with a tooltip saying what changes | — | — | — | P3 | Hover the button |
| Empty state | — | Panel 110 high, body text | Same panel, reading style | — | — | — | P3 | Empty Arcs tab |

## 3. Review

| Element | Approved rendering | Before (v0.7) | Now | Difference remaining | Why | Fixable? | Priority | How to validate in game |
|---|---|---|---|---|---|---|---|---|
| Finding card | (Memories card style) | Fixed card, Examine 80 × 22 over the chip row | Content-sized card; the top row grows to the compact Examine (80 × 30, default variant, tooltip); no date (findings have none) | — | — | — | P1 | A finding card |
| Answers | Real buttons | Default variant, fixed widths | Default variant, measured, all five in one row (tighter padding if needed), each with its explanation tooltip | — | — | — | P1 | Five filled buttons in one row |
| Examine | Side by side | A and B side by side, then the finding and Explain | Same order; A and B start the two columns; a long side offers Read (Edit and Steps work from the full view) | — | — | — | P2 | Examine a duplicate |
| Answered / Undo | — | Cards with Undo answer | Same, content-sized | — | — | — | P3 | Answered list |

## 4. Places

| Element | Approved rendering | Before (v0.7) | Now | Difference remaining | Why | Fixable? | Priority | How to validate in game |
|---|---|---|---|---|---|---|---|---|
| Position | List panel 300 wide and detail panel 14 below the tabs | Top 50 | Top 54 (under the 40 px track + 14) | — | — | — | P3 | — |
| List rows | 56 apart: icon, name ~17, zone · kind 14 muted, visits 14 at the right; selected raised with a gold edge | Name 15, sub 13, visits 13; hover fill only | Name `nav` 17, sub and visits `meta` 14; hover: card-hover fill and edge; selected: raised fill, gold edge; hover tooltip with the full name, line, visits and markers | Line icons (house, star) are game textures; no wrapping second line (cut, full on hover) | No vector icons; design choice: fixed rows keep paging simple | No / Yes | P2 | Hover a long place name |
| Detail heading | Cinzel ~26 title, 15 muted line | Name in body colour | Cinzel 28 in the title tone (full name on hover), muted line | — | — | — | P2 | — |
| Meaning chips | Gold chips, then neutral "2 memories tied to it"; wrap | Fixed row, no wrap | Measured and wrapping | Chips 24 high (the mockup's are ~30 with icons) | Shared chip height | Yes (shared) | P3 | Homeland + meaningful + count |
| Note | 15 muted, "Private" in the visibility colour | 13, fixed 30 px box | `meta` 14, up to 3 lines, height from the text | "Private" not coloured | Design choice: plain text keeps the sentence searchable by tests and screen readers | Yes | P3 | — |
| Stat tiles | Eyebrow (wraps: "Next return moment"), value ~20, equal heights | Fixed 62 high; eyebrow on one line (clipped); value 15 | Eyebrow wraps; value `reading` 16; all three tiles as tall as the tallest content (70 min) | Value 16 vs ~20 | Shared reading style | Yes | P2 | A long "Next return moment" is not cut |
| Tied memories | Rows ~38 high: title 16 + " · Defining" muted | 28 high, small text, 3 max | 36 high, title in body, " · status" muted (colour code); as many as fit (up to 4) with "and N more in Memories"; hover shows the whole memory | — | — | — | P2 | Hover a tied memory |
| Actions | 36 px: primary "Write a memory here", secondary "Unmark meaningful", ghost "Set as homeland" (cut off in the mockup itself) | 30 px, fixed widths | 36 px, widths measured so all three fit with as much padding as the panel allows; Set as homeland disabled with a tooltip when already so | No pencil icon | No vector icons | No | P1 | All three buttons visible and uncut |

## 5. What is a true limit and what is not

True API limits (no workaround without art): line icons in chips and buttons, rounded corners, inline font-size changes in one label, letter spacing. Not limits but choices: paging instead of scrolling (a scroll frame with pooled cards is possible), the 6-line text cap on cards (tunable), masonry instead of row alignment (denser than the mockup), Cinzel 18 titles (shared style), note text without the coloured "Private".

## 6. Files changed

- `DawnwardChronicles/UI/ChronicleView.lua`: content-aware layout (`WrapLines`, `ButtonWidth`, `ButtonRows`, `ChipWidth`, `VisibilityWidth`, `ChipRows`, `CardLayout`, `Paginate`, `Pages`, `TabWidth`, `TabLabel`, `Actions`, `ItemLayout`, `ItemKey`), measured tabs with quiet counts, 36 px toolbar, pager only when needed, card pool of 8 positioned per page, amber / red "needs your call" painting, Read and the full view. Removed: `CardRects`, `CardOrigin`, `BUTTON_WIDTHS` (replaced by the measured layout).
- `DawnwardChronicles/UI/ChroniclePlaces.lua`: `DetailLayout` (flowing detail), `ActionWidths`, `MemoryParts`, `STATS`, `ACTIONS`; list rows and tiles restyled; tooltips on list rows and tied memories.
- Tests: `tests/spec/ui_chronicle_spec.lua` (layout tests rewritten for content-aware cards; new: pagination, tabs with 3-digit counts, button rows, short-card density, full view, amber / red highlight), `ui_chronicle_cards_spec.lua` (new: place detail layout, hover full text), `ui_entry_rows_spec.lua` (geometry read from each card's own layout), `continuity_review_spec.lua` (Examine rect from the new layout; new: full view of an examined record, rules once per refresh).

## 7. Shared-component proposals (not changed here)

1. `Widgets.Card` tone: a `highlight` of `"waiting"` (amber edge on the callout fill, no bar) and `"danger"`, as `ChronicleView` paints locally (`paintCard`). The Journal and Story suggestion cards could use the same.
2. `Widgets.ChipRow(parent, max)` and `Widgets.ButtonRow(parent, max)`: measured, wrapping rows (the `ChipRows` / `ButtonRows` maths here), so every screen attaches chips and actions the same way.
3. `Widgets.TextWidth`-based `Widgets.WrapLines(text, width, style)` in Style or Widgets (now `ChronicleView.WrapLines`, already used by Places).
4. A segmented item count badge (the mockup's small count and Review's amber pill) as part of `Widgets.Segmented`.
5. A themed scroll bar for `UIPanelScrollFrameTemplate` areas (the full view and forms).

## 8. Manual in-game acceptance (compare with chronicle-memories.png and chronicle-places.png)

1. `/reload`, `/dawnward`, Chronicle. Reset the window size (Settings → General) and place it next to chronicle-memories.png.
2. Tabs: a dark padded track; Memories selected raised with a light edge; each tab as wide as its words; counts in a quieter colour; Review's count amber when findings are open.
3. Toolbar: "+ New memory" gold, 36 px tall, the search box the same height; at the right "Newest first · N memories". With more than one page, "<  Page 1 of 2  >" sits at the right and the count moves left of it.
4. Write a short memory and a long one (several paragraphs). The short card is clearly shorter than the long one; no card has a large empty area. The long card shows six lines ending in "..." and a Read button.
5. Click Read: the whole record fills the area under the tabs; the text scrolls with the mouse wheel; Private / Edit / Remove work from there; "< Back to memories" returns. Switch tab while it is open: it closes.
6. Accept a Dawnward suggestion (a memory from Story): its card has an amber edge and warm fill, an amber "Suggested · needs your call" chip, Accept gold, Edit filled, Remove outlined red at the right.
7. Hover a card's title that is cut: the full title shows. Hover a card's Edit: the whole card highlights.
8. A memory with a zone: zone, "Your words", "Established" and the visibility chip all show (wrapping if needed), none overlapping.
9. Goals: a goal with milestones shows a 6 px gold bar; Steps opens the milestones.
10. Stances: "Inner: Private" button; hover explains it; click cycles the private side.
11. Review: with a contradiction (e.g. `/dawnward stance add The Cenarion Circle; Loyal; Doubts its leaders`), the finding card shows Examine (filled, 30 px) at the top right and the five answers as filled buttons in one row, each with its tooltip. Examine: A and B side by side; Read on a long side; Edit opens that record's form; Explain... and Answered / Undo answer as before.
12. Places (compare with chronicle-places.png): list on the left with 17 px names and 14 px zone lines; selected row raised with a gold edge; hover a row for the full name. Detail: large white name, muted line, "WHAT IT MEANS TO YOUR CHARACTER", chips wrapping, the note, three equal stat tiles ("NEXT RETURN MOMENT" wraps instead of being cut), tied memories with a muted status (hover shows the whole memory), and the three actions all fully visible on one row.
13. Resize the window to its smallest and largest scale: proportions stay (the window scales as a whole); text stays readable; nothing overlaps.
14. Switch theme (Lightbound, Shadowbound): cards, amber suggestion edge, tab counts and Places tiles follow the theme.
