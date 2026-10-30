# Audit: Journal dashboard (v0.8 visual fidelity)

Scope: the Journal section (`UI/JournalView.lua`): subline, toolbar, "A moment awaits" callout, entry cards, scrolling, right column (Active goals, Recent places), empty states and the entry editor's entry points.
Compared with: [journal-dashboard.png](../mockups/journal-dashboard.png) and `mockups/source/Main.dc.html` (the main column, 772 wide at 1100 x 720). The shell (rail, header, chrome) and the shared components are covered in [shell-and-components.md](shell-and-components.md).
Base: `origin/claude/upbeat-mendel-ds1ct4` at `d7409bf`.

**Nothing here has been checked in the game.** The automated suite (L2, against the WoW mock) proves wiring, sizes, order and the absence of overlaps in UI units. Whether it looks right is the owner's in-game comparison (steps at the end).

Priority: P1 is visible at a glance, P2 is visible when looking at a card, P3 is a detail.

## 1. Header and toolbar

| Element | Approved rendering | Before (v0.7) | Now | Difference remaining | Why | Fixable? | Priority | How to validate in game |
|---|---|---|---|---|---|---|---|---|
| Subline | 15 muted, 2 px under the title: "37 entries · 4 defining moments · last entry today" | Same text at the top of the content area (16 px lower than the design, taking a list row's room) | Same real counts, 15 muted, directly under the title box (window y 80, 16 above the content area); the toolbar moves up accordingly | None in position; text is the real data | — | — | P1 | The subline sits right under "THE ROAD SO FAR", no gap of a line |
| New entry | Primary 36 high, "+" icon and "New entry", bold 15 | Primary 28 high, 112 wide, "+ New entry" | Primary 36 high (`CONTROL.standard`), 124 wide, "+ New entry" in bold 15 | "+" is a character, not a drawn icon | True API limit (no vector icons) | No | P2 | Same height as the search box; label not clipped |
| Search | 36 high, 230 wide, magnifier icon, placeholder 15 | 26 high, 230 wide | 36 high (`CONTROL.input`), 230 wide, dark well with the 2 px focus ring | No magnifier; placeholder 13 (shared `SearchBox`) | No verified magnifier texture in the 1.15.9 files; placeholder size is the shared widget's | Partly (placeholder size: shared) | P2 | Click into it: gold ring; type: list filters as you type |
| Filter | Segmented on a panel track with 1 px edge and 3 px padding; items 30 high (bold 14); selected raised `#2A3346` with `#4A5874` edge | 264 wide, items 24 high, track flush with the items | Items 30 high, 62 wide each, 2 apart, on a framed track (panel fill, 1 px edge, 4 px in: 3 padding + edge), 262 x 38, at the right edge | Equal-width items (design sizes each to its word) | Design choice: equal items keep the click targets and keyboardless layout simple | Yes | P3 | All / Defining / Story / Events sit in an outlined track; the selected one is raised |

## 2. "A moment awaits"

| Element | Approved rendering | Before (v0.7) | Now | Difference remaining | Why | Fixable? | Priority | How to validate in game |
|---|---|---|---|---|---|---|---|---|
| Frame | Gold edge, warm dark fill, padding 14 / 18, gap 16 below the toolbar and above the list | Callout at 64, list 12 below | Callout at 72 (16 below the 38 px toolbar), padding 14 / 18, list 16 below | Square corners | Radius limit (shared) | No | P2 | Gold-edged band under the toolbar |
| Icon | 44 px disc, `#2A2213` fill, gold edge, gold four-point star | 36 px game icon (a note) | 44 px masked disc with a gold edge, dark gold fill and a bright gold jewel (a square turned 45°, as the rail's wordmark), vertically centred | Jewel instead of a four-point star; square disc where masks are unavailable | True API limit (no vector art; no verified star texture) | No | P2 | A round gold-edged disc with a gold diamond |
| Eyebrow | Cinzel 11 caps, "A MOMENT AWAITS · 1 OF 2" | Cinzel eyebrow (13) at the panel's corner | Cinzel 13 caps aligned with the question (x 78) | 13 instead of 11, no letter spacing | Readability minimum (13) and no tracking in WoW | No | P3 | Eyebrow aligned with the question text |
| Question | 17 / 1.35, title white, wraps | 15 body text | `reading` 16 with 4 px leading, title white, 484 wide so it never runs under the buttons; the callout grows with the question (min 76) | 16 vs 17 | Design choice: one reading size across the screen | Yes | P2 | Two-line question reads like the mockup |
| Answer / Later | Primary and ghost, 36 high, bold 15, right, vertically centred | 26 high, top-aligned | 36 high (`CONTROL.standard`), 92 and 76 wide, 8 apart, 18 from the right edge, centred | — | — | — | P1 | Answer opens the Story section on that moment; Later postpones it |

## 3. Entry cards

| Element | Approved rendering | Before (v0.7) | Now | Difference remaining | Why | Fixable? | Priority | How to validate in game |
|---|---|---|---|---|---|---|---|---|
| Card | Surface, 1 px edge, radius 10, padding 14 / 18 (featured 16 / 18), 12 apart | Padding 14 all round, 10 apart, 464 wide | Padding 14 / 18 (16 / 18 featured), 12 apart, 488 wide (list 502 minus the 14 px gutter) | Square corners | Radius limit (8 corner discs per card would be cheap per card but costly across a pooled list; kept square for consistency with every other panel) | Partly | P2 | Cards read as separate story entries with air between them |
| Featured card | Lighter fill `#1A2230`, edge `#4A5A78`, gold day | Only on hover | Defining moments are featured (cardHover fill, selectedEdge); every card also lifts on hover; a hovered featured card gets the gold edge | The mockup features the first card; Dawnward features defining moments (real data, never position) | Design choice | — | P2 | Mark an entry Defining: its card lifts and its day turns gold |
| Date block | 52 wide; day Cinzel 24 (gold on the featured card, `#D9D2C2` otherwise); month Cinzel 12 tracked, muted | 56 wide, day always gold | 52 wide at x 18, day Cinzel 24 bright gold when featured, ghost text otherwise; month Cinzel 13 muted; hover shows the full date and origin | Month not tracked; Cinzel SemiBold vs Bold | No tracking; Bold not bundled (shared) | No / Yes | P3 | Dates line up in a column left of the titles |
| Title | Cinzel 18 / 600, title white `#F5EEDD`, chip at the right of the first line | Cinzel 18, body colour | Cinzel 18 in title white (`title` role), wraps in the width left by the chips; chips centred on the first line | — | — | — | P1 | "THE NIGHT THE LANTERNS WENT OUT" style titles |
| Status chips | Gold "Defining" (star icon), amber "Waiting for your approval", neutral "Recorded event" | All gold except neutral tags | Tones from the design: `accent` Defining, `waiting` amber for approval, `muted` Story / Recorded / Simulated event; at most 200 wide (cut text shows in full on hover) | No star icon | Line icons: true API limit | No | P2 | A draft shows an amber chip |
| Meta line | 14 muted, 6 below the title | 13 muted, 4 below | `meta` 14 muted, 6 below | — | — | — | P2 | "Goldshire, Elwynn Forest · Level 24 · Your words" |
| Story text | 16 / 1.5, `#E4DCCB`, full text | 15 body colour | `reading` 16 with 4 px leading in the reading tone, full text, 6 below the meta | Emphasis inside the text ("**Compassionate**" in gold) not reproduced | Not done: the text is the player's or the Story Director's plain text; colouring words needs markup in stored text | Yes (colour the development's trait name) | P3 | Paragraphs read comfortably, no cramped wrapping |
| Footer | Private chip left (24, lock icon); Edit (secondary sm, 30) and Delete (danger sm, 30) right, 8 apart; margin 4 + gap 6 | Visibility 20 high, buttons 20 high, 6 apart | Visibility chip 72 x 24 on the left; Delete 68, Edit 54, Approve 78, Defining 80 — all 30 high (`CONTROL.compact`), bold 14, 8 apart from the right edge; 10 below the text. A draft's four actions plus the chip fit the 384 px text column (tested) | No icons on Edit / Delete / Private | Line icons: true API limit | No | P1 | Edit and Delete sit at the bottom right inside the card, never touching the chip |
| Approve / Reject | Draft card: Approve (primary) and Reject (ghost) | Approve + Delete | Approve (primary) + Edit + Delete; "Defining" toggle kept on every card | No separate Reject | Design choice from v0.7: no reject action exists for journal drafts; Delete does it | — | P3 | — |
| Event card | Title + meta only | Footer with visibility and Defining | Footer kept (visibility and Defining must stay changeable on automatic entries) | Footer present | Behaviour preserved | — | P3 | — |

## 4. Scrolling

| Element | Approved rendering | Before (v0.7) | Now | Difference remaining | Why | Fixable? | Priority | How to validate in game |
|---|---|---|---|---|---|---|---|---|
| List | One continuous scrolling list, slim 6 px bar (track `#161D29`, thumb `#3E4C66`) in the 14 px right padding | Pages of 10 inside a scroll frame, "< Newer / Page n of m / Older >" under the list, the template's 16 px scroll bar with arrows | One continuous list: every matching entry is measured once (heights cached by content) and only the cards that intersect the visible area exist, drawn from a pool (at most a screenful + 1; tested with 60 entries). Scrolling (wheel or thumb) lays out only the cards coming into view. The template's bar is restyled: 6 px track in the gutter, proportional thumb, arrows invisible. Hidden when everything fits | Square thumb ends | Radius limit | No | P1 | Scroll a long journal with the wheel: smooth, no pager, the thumb's size matches the list |
| Scroll position | — | Reset by paging | Kept across refreshes (a level-up while reading does not move the list); a filter, a search or a new entry go back to the top | — | — | — | P2 | Scroll down, gain a level: you stay where you were |
| Measuring | — | — | A hidden measuring card lays out new content once; if a card's real height differs when shown (fonts not ready yet), the list corrects itself (restacks, at most three passes) | The first frame after a font change may restack once | Design choice: exact heights without creating a frame per entry | — | P3 | No overlapping or gapped cards after /reload |
| Cost | — | 10 cards per page laid out per refresh | Per refresh: the visible cards (as before) plus one cheap content string per matching entry; per scroll step: only newly visible cards. No OnUpdate; nothing runs while hidden | Content strings are built for every matching entry on each refresh (the search already reads every entry) | Design choice | Yes (key by entry id + updatedAt) | P3 | With hundreds of entries, typing in search stays responsive |

## 5. Right column

| Element | Approved rendering | Before (v0.7) | Now | Difference remaining | Why | Fixable? | Priority | How to validate in game |
|---|---|---|---|---|---|---|---|---|
| Width and gap | 250 wide, 20 from the list | 270 wide, 16 from the list | 250 wide, 20 from the list | — | — | — | P2 | Right column lines up with the callout's right edge |
| Panels | Cards, padding 14 / 16, eyebrow, 12 apart; Recent places hugs its content | Places panel stretched to the bottom | Surface panels, padding 14, eyebrow, 12 apart; Recent places hugs its rows (never past the content area) | Padding 14 sides vs 16 | Shared `Panel` padding | Yes (shared) | P3 | Panels end where their content ends |
| Active goals "All" | Gold text link, 14, top right | Ghost button 40 x 18 (edged since v0.8) | Text link: gold, brighter on hover, thin underline, no box; opens Chronicle > Goals | Bold 14 instead of regular 14 | Built on the shared button for its click and tooltip | Yes | P3 | "All" reads as a link |
| Goal rows | Title 15, bar 6 high (round), caption 13 muted, 6 apart, 12 between goals | Bar 4 high | Title 15, bar 6 high (`CONTROL.progress`), caption 13 muted, 6 apart, 12 between goals | Square bar ends | Radius limit | No | P2 | Bars are as thick as the mockup's |
| Place rows | Name 15; chips 20 high (gold); detail 13 muted; dividers with 10 above and below | Chips 24 high, 9 px spacing | Name 15; Homeland / Meaningful chips 20 high (`chipSmall`, text 13: readability minimum); detail 13 muted; dividers 10 / 10 | Chip text 13 vs 12 | Readability minimum | No | P3 | Goldshire shows two small gold chips |

## 6. Empty states

| Element | Approved rendering | Before (v0.7) | Now | Difference remaining | Why | Fixable? | Priority | How to validate in game |
|---|---|---|---|---|---|---|---|---|
| No entries / no match | (not drawn) | Centred muted text floating in the list area | A card at the top of the list with the explanation in the reading size, centred (same texts as before) | — | Design choice consistent with the cards | — | P2 | New character: a card says how to start; search "dragons": a card says no entries match |
| No goals / places | (not drawn) | Muted 13 text | Unchanged texts, 6 below the eyebrow | — | — | — | P3 | — |

## 7. Files changed

- `DawnwardChronicles/UI/JournalView.lua`: layout from Main.dc.html (exposed as `JournalView.LAYOUT`), subline position, toolbar heights and framed filter track, callout disc / eyebrow / question / buttons, card anatomy (featured cards, reading and meta styles, chip tones, footer sizes), virtual scrolling list with a pooled card set and a height cache (`JournalView.Stack`, `JournalView.Window`, `JournalView.ClampOffset`, `section:ScrollTo`), slim scroll bar, right column sizes, "All" text link, empty-state card. The pager (`older`, `newer`, `pageLabel`, `PAGE_SIZE`, `ClampPage`) is gone.
- `tests/spec/ui_journal_dashboard_spec.lua`: paging tests replaced by scrolling ones (newest first, oldest reachable, pool bounded, cards stacked without overlap, scroll position kept or reset); the layout test now checks the 250 px column and the framed track; new tests for design sizes.
- `tests/spec/ui_journal_window_spec.lua`: "ten per page" replaced by "one scrolling list that reaches the oldest, in order".
- `docs/design/audit/journal.md` (this file).

## 8. Proposals for shared components (not changed here)

1. `Widgets.Card`: a `:SetFeatured(on)` state (the design's featured card) instead of the Journal's local painter.
2. `Widgets.Segmented`: an option for the design's padded, edged track (the Journal draws its own `framedTrack`), and per-item widths.
3. `Widgets.SearchBox`: placeholder in the input size (15) and an optional icon slot.
4. A shared slim scroll bar (`Widgets.StyleScrollBar(scroll, gutter)`) and a virtual list helper (`Stack` / `Window` / pool) for Chronicle and Story lists.
5. `Widgets.Link(parent, text)` for text links such as "All".
6. `MainWindow`: a header subline slot under the title (the Journal anchors its subline 16 above the content area to sit there).
7. `UI_DESIGN_V07.md` section 4 still says the Journal is "Paged (10 per page)"; it now scrolls.

## 9. Tests

`python tools/check.py`: 893 passed, 0 failed (882 before); luacheck clean. New or reworked L2 tests:
- scrolls one long list from a small pool of reused cards (60 entries; pool bounded by the visible area; cards stacked a gap apart, no overlap; oldest reachable)
- keeps the scroll position on refresh; filter, search and new entry go back to the top
- a short journal has no scroll range and no pager
- measures an entry once (height cache)
- defining moments are featured cards with a gold day; drafts wait in amber
- splits the content area like the design (list + gutter + gap + 250 column = 772)
- subline under the window title and above the toolbar without overlapping
- design-system control heights in toolbar, callout and cards, with every label fitting
- reading / meta / Cinzel styles on cards and callout
- a draft's footer: visibility and four actions fit the text column without overlap; title and chips share the first line
- callout layout: question never runs under Answer and Later; list starts 16 below
- empty list as an explanatory card
- pure list maths (stack, window, clamp)

The layout is in UI units inside the fixed 772 x 588 content area, so it is identical at the window's smallest and largest scale (the window's own scale tests cover fitting the screen).

## 10. Manual in-game acceptance (compare with journal-dashboard.png)

1. `/reload`, open the journal (`/dawnward`) at the default size (Settings → General → Reset window size). Put journal-dashboard.png beside it.
2. Header: the subline ("N entries · N defining moments · last entry …") sits right under the title, with no blank line between them.
3. Toolbar: "+ New entry" (gold), the search box and the filter are all the same height; the filter sits in an outlined dark track with a little padding; "All" is raised.
4. Trigger a moment (complete a quest with the Story Director on, or `/dawnward story` in a development build). The callout: a round gold-edged disc with a gold diamond, "A MOMENT AWAITS · 1 OF N" aligned with the question, the question in large white text, Answer and Later vertically centred at the right. Answer opens the moment in Story; Later removes it from the Journal.
5. Cards: the date column (big day, small month) on the left, the title in white Cinzel with its chip on the right of the first line, the meta line, the full text in comfortable 16 px lines, then a footer: the visibility chip at the left, Edit and Delete (and Approve / Defining) at the right, inside the card. 12 px between cards.
6. Mark an entry Defining: its card gets the lighter fill and stronger edge, its day turns gold, a gold "Defining" chip appears. A Story Director draft shows an amber "Waiting for your approval" chip.
7. Write 30 or more entries (`/dawnward journal add …`), then scroll with the mouse wheel and by dragging the thin thumb: one continuous list, no pager, no overlapping or gapped cards, the oldest entry at the end. Report any overlap: the height correction should have prevented it.
8. While scrolled down, gain a level or receive a moment: the list does not jump. Change the filter or type in search: it goes back to the top.
9. Right column: Active goals with "All" as a gold link (hover brightens), 6 px gold bars and captions; Recent places with small gold Homeland / Meaningful chips and dividers. The places panel ends after its last row.
10. New character (or search "dragons"): an explanatory card at the top of the list instead of floating text.
11. Hover a long chip or the date: the full text shows. Hover a card: it lifts.
12. Switch themes (Settings → General): cards, track, scroll bar, callout disc and chips follow the theme; nothing becomes unreadable.
13. Drag the window to its smallest size: everything scales together; text stays readable.
