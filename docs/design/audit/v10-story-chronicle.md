# Audit: Story Director and Chronicle (v0.10 fidelity pass)

Scope: `UI/StoryView.lua`, `UI/ReactionCard.lua`, `UI/ChronicleView.lua`, `UI/ChroniclePlaces.lua`.
Compared with: [story-director.png](../mockups/story-director.png), [chronicle-memories.png](../mockups/chronicle-memories.png), [chronicle-places.png](../mockups/chronicle-places.png) and their sources in `mockups/source/` (`Story.dc.html`, `ChronicleMemories.dc.html`, `ChroniclePlaces.dc.html`).
Base: `origin/feat/v0.10-no-privacy` at `cc67ebf`. Earlier audits: [story.md](story.md), [chronicle.md](chronicle.md) (v0.8); every row there that is not listed here is unchanged.

**Nothing here has been checked in the game.** The L2 suite (WoW mock) proves wiring, sizes and that nothing overlaps; text is measured from the bundled fonts' advance widths. For this pass each screen was also drawn from the mock's frame tree (resolved anchors, theme colours, the bundled fonts) next to the mockups, as a working aid; those drawings are approximations, not screenshots, and are not shipped. The last column is the owner's in-game check.

Behaviour is unchanged: the Story Director's rules (Core/Director.lua and the rest of Core) are untouched, one click still answers a moment, every personality change still waits for approval, and every Chronicle action, form, Review answer, Examine / Explain / Undo answer and the homeland link work as before. No privacy chip was added anywhere.

Cause column: **limit** = verified Classic Era client limit; **deliberate** = a choice, with the reason; **not done** = possible, left for later.

## 1. Story Director (story-director.png)

| Element | Approved rendering | Before (v0.9) | Now | Remaining difference | Cause | In-game check |
|---|---|---|---|---|---|---|
| "Why now" well | One paragraph per line: bold "Why now:" then the muted reason running on and wrapping back to the well's left edge; same for "She remembers:" | Bold label in its own column and the reason in a hanging indent beside it (wrapped lines started under the reason, not the label) | The reason runs on after the label and wraps back to the left edge, as the mockup. One font string per style: the reason's string starts with a run of no-break spaces as wide as the label (`StoryView.InlineIndent`; the bundled font's no-break space has the regular space's advance, 165/1000 em, read from the font file), the bold label sits over that room. Lines are estimated with that indent | The reason may start up to one space (about 2 px) closer to or farther from the label than the mockup's 4 px | limit: one font per string; the space run is the nearest match | Look at "Why now: …" with a reason that wraps: the second line starts at the well's left edge, the first a little after the colon |
| Same, without the bundled fonts | — | (hanging indent) | Label and reason stack (reason on the next line) when the bundled font is not in use (non-Latin client) or the label takes most of the line | — | deliberate: the space width of the game font is unknown | Only on a non-Latin client |
| "remembers" / "Last time" rows | As "Why now" | As the old well | Same inline flow | Name instead of "She" | deliberate (no assumed pronouns, as v0.8) | Die twice in a zone: "Last time:" row inline |
| Moment card, chips, question, answer grid, own words, actions | (see story.md) | v0.8 layout | Unchanged | As listed in story.md (no pin / check icons, round number discs, hints under answers) | limit (icons) / deliberate (discs, hints) | As story.md steps 3–6 |
| Pager, Also waiting, Growth to approve | (see story.md) | v0.8 | Unchanged | — | — | — |
| Empty state | — | Title, gold rule, body, summary | Unchanged | — | — | Answer every moment |

## 2. Reaction card (no mockup; the moment card in miniature)

| Element | Approved rendering | Before (v0.9) | Now | Remaining difference | Cause | In-game check |
|---|---|---|---|---|---|---|
| Where / what | Story card: gold place chip, neutral event chip | One muted text line "Quest completed · Elwynn Forest" | The Story section's first two chips: gold place chip ("Goldshire, Elwynn Forest") and the neutral event chip, 24 high, capped before the close button | No pin icon | limit (icons) | Turn in a quest: two chips under the eyebrow |
| Question | Story question: Alegreya Sans 22, title white | Reading 16 | Alegreya Sans 18 with 5 px line spacing (one step down from the Story's 22 for a 420 wide card), up to three lines | 18 rather than 22 | deliberate: the card is a notice, 420 wide | Question larger than before, never cut before three lines |
| Why now | Story well's first line | (none) | The Director's own reason as on the Story screen: bold "Why now:" with the reason running on (same no-break-space room), up to two lines | No well background | deliberate: the card is already the dark frame | The reason matches the Story screen's first line |
| Size | — | 400 wide | 420 wide; height from the question and the reason (`ReactionCard.Height(lines, whyLines)`) | — | — | Long quest title: card grows, nothing overlaps the buttons |
| Buttons | Story action row | Answer / Later / Dismiss, 30 px | Unchanged | — | — | — |

## 3. Chronicle: Memories and the other card tabs (chronicle-memories.png)

| Element | Approved rendering | Before (v0.9) | Now | Remaining difference | Cause | In-game check |
|---|---|---|---|---|---|---|
| List | One scrolling grid of cards with a slim scroll bar at the right | Pages ("< Page 1 of 2 >"), as many cards as fitted; a page often ended with a large empty area | One scrolling list (`UIPanelScrollFrameTemplate`, its bar restyled by `Widgets.SlimScrollBar` into the design's 6 px bar in a 12 px gutter). Cards keep the shortest-column placement (`ChronicleView.Masonry`). Only cards that intersect the view have a frame: 8 are made at once and the pool grows only when one view needs more; scrolling refills cards from the pool (`RenderWindow`, as the Journal list). The wheel moves 60 per notch (`Widgets.WHEEL_STEP`); a refresh keeps the place, a new tab or search starts at the top | Masonry rather than the mockup's row-aligned grid | deliberate (owner: less empty space; the mockup's rows leave a gap under a short card) | Wheel over the cards scrolls; the thumb drags; the wheel never zooms the camera |
| Card width | Two columns, 12 apart, beside the scroll bar | 380 (no room for a bar) | 374: two columns, 12 apart, then the 6 + 6 bar gutter (772 in all) | — | — | — |
| Text lines on a card | As many as needed | Up to 6, then "..." and Read | Up to 8 (the list scrolls now), then "..." and Read; the "Shortened" hover remains for a client cut the estimate missed | Very long texts still end on the card | deliberate: keeps cards scannable; Read shows the rest | A long memory shows 8 lines and Read |
| Toolbar | New, search, "Newest first · 12 memories" at the right | Same, plus the pager on long lists | New, search, the count at the right always (no pager) | No search / plus icons | limit (icons) | — |
| Tab counts | Count after the label in 12 px `#8D96A8` | Count in the label's string (same size, colour code) | The count is its own font string in the small type (13), after the measured label, in the quieter tone (gold-beige on the selected tab) | 13 rather than 12 | deliberate: the design system's smallest style | Tabs read "Memories 12" with a smaller number |
| Review count | Amber round badge | Amber number in the label | A round amber badge (`Style.Pill`, 20 high; square fill and edge where masks are missing) with the number in the bold badge type | — | — | Review tab with a finding: amber disc with the count |
| Tab widths | Each tab hugs its words | Minimum widths per tab (74–112), uneven gaps | Label + gap + count + 12 each side, nothing more | — | — | Even spacing along the track |
| Review finding card | (Memories card) | Chip, then the guidance line, then the finding's message | Chip and Examine, the finding's message (reading type), then the guidance question in the quiet meta type, then the five answers as filled buttons. Five answers still fit one row (a third, tighter gap step: 4 px) | — | — | A finding reads message first |
| Read (full view) | — | Full view over the list | Unchanged; it hides the list while open; a finding's question shows in the meta slot | Text runs the full panel width | not done (a narrower reading measure) | Read a long memory; Back returns to the same place in the list |
| Privacy chips | Public / Private / Secret chips in the mockup | Removed in v0.10 | Still removed; the chips row reflows | — | deliberate (owner decision) | No such chip anywhere |

## 4. Chronicle: Places (chronicle-places.png)

| Element | Approved rendering | Before (v0.9) | Now | Remaining difference | Cause | In-game check |
|---|---|---|---|---|---|---|
| Stat tile value | About 20 px ("14", "Today", "After 2 days away") | Reading 16 | Alegreya Sans 20 with 4 px spacing (`statValueSize`); tiles still grow together with the longest value | — | — | Values clearly larger than the tile labels |
| Tied memory row | Title 16, then " · Defining" smaller and muted | One string, status by colour code at the same size | Name in the reading type, then "· Defining" as its own small (13) muted font string right after the name; a long name is cut so the status always shows; hover still shows the whole memory | — | — | Status sits right after the title, smaller |
| List, detail heading, chips, note, actions | (see chronicle.md) | v0.8 | Unchanged (list stays paged: the mockup's list has no scroll bar) | Icons are game textures; no pencil on Write a memory here | limit (icons) | As chronicle.md step 12 |

## 5. What is a true limit and what is not

Verified limits (1.15.9): no vector icons (pin, check, search, plus, pencil), one font and size per font string (hence the separate count strings and the no-break-space room for inline labels), no letter spacing, masks give circles and pills only (the badge and discs are pills; cards keep square corners).

Not limits, left as choices or for later: masonry instead of row-aligned cards; an 8-line cap on card text; a narrower reading measure in the full view; hints under Story answers (v0.7 choice).

## 6. Shared-component proposals (not changed here: Widgets / Style belong to the shared pass)

1. `Widgets.Segmented` with a per-item count string and an optional badge (what `ChronicleView` now adds to each tab locally).
2. `Style.InlineIndent` / a "label + running text" helper in Style (now `StoryView.InlineIndent`), for any screen that wants a bold lead-in on wrapping text.
3. A "larger reading size" font object (18 and 20) in `Style.FONTS`, instead of per-string `SetFont` (Story question 22, reaction card 18, Places tile values 20).
4. A virtual-grid helper shared by the Journal list and the Chronicle grid (both keep a pool, a measured height per item and redraw on `OnVerticalScroll`).
5. A search icon for `Widgets.SearchBox` from a client texture, if one in 1.15.9 matches the line style.

## 7. In-game checks (compare with the mockups)

1. `/reload`, `/dawnward`, Story with a waiting moment: the "Why now:" row reads as one paragraph; a wrapped second line starts at the well's left edge; the reason starts a few px after the colon (not overlapping it, not far from it). Same for "… remembers:" and "Last time:".
2. Turn in a quest out of combat: the reaction card shows the eyebrow, a gold place chip and the event chip, the larger question, the Why now line, and Answer / Later / Dismiss. Nothing touches the close button. Escape still hides it.
3. Chronicle → Memories with a dozen or more memories: the cards scroll with the wheel and by dragging the slim bar's thumb; no empty band at the bottom; the count reads "Newest first · N memories" at the right. Scroll down, Edit a card and save: the list keeps its place. Switch tab and back: it starts at the top.
4. Tabs: names with smaller, quieter counts; Review's count in a round amber badge; even spacing along the track. Switch theme (Lightbound, Shadowbound): counts and the badge stay readable.
5. Review: a finding shows its message, then the question, then five filled answer buttons in one row; Examine, Explain, Answered and Undo answer behave as before.
6. Places: tile values large; tied memories show "· Defining" smaller and muted right after the title.
7. Resize the window to 0.7 and 1.4: the list, bar and badge scale with the window; nothing clips or overlaps.
