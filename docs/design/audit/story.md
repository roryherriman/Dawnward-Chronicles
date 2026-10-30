# Audit: Story Director (v0.8 visual fidelity)

Scope: the Story section (`UI/StoryView.lua`) and the reaction card that announces a waiting moment (`UI/ReactionCard.lua`).
Compared with: [story-director.png](../mockups/story-director.png) and `mockups/source/Story.dc.html`.
Base: `origin/claude/upbeat-mendel-ds1ct4` at `d7409bf` (design system and shell pass).

**Nothing here has been checked in the game.** The L2 suite (WoW mock) proves wiring, sizes, colours and that nothing overlaps. Whether it looks right is the owner's in-game comparison (steps at the end).

Behaviour is unchanged: the Story Director's rules, one click answers (no pick-then-save), Later / Not now / Dismiss, approval of every personality change, Reverse with confirmation, inline validation of the own-words answer, keyboard (FocusChain) and the "no invented content" rules (every chip, reason and memory still comes from the record or the Director).

Priority: P1 is visible every time the screen opens, P2 is visible often, P3 is a detail.

## 1. Moment card

| Element | Approved rendering | Before (v0.7) | Now | Difference remaining | Why | Fixable? | Priority | How to validate in game |
|---|---|---|---|---|---|---|---|---|
| Card | `#151B26` card, 1 px dim gold edge `#4A3E26`, padding 20 / 22, blocks 12 apart, actions pinned to the bottom | Callout: warm `#1A1A17` fill, bright gold edge and a glow; every block at a fixed height | Card colour with the dim gold edge (ground mixed with the ornament line), padding 20 / 22, blocks 12 apart, action row pinned 20 above the bottom | Square corners | True API limit (no rounded rectangles without art) | No | P1 | The card reads as the mockup's quiet gold-edged panel, not a glowing callout |
| Layout flow | Blocks follow each other; heights follow content | Fixed slots (question 50, why 58, four 58 px answer rows, field 58); a longer question or a third why line overlapped the next block | Text is measured (client height, never less than an estimate from the fonts' advance widths) and `StoryView.MomentLayout` places each block under the previous one. A fuller moment uses a compact spacing (16 / 8 / 6); only the fullest (eight answers and three why lines) cut lines, with the full text on hover | The compact spacing is tighter than the mockup | Design choice: the mockup shows six one-or-two-line answers without hints; real library answers often take three lines in a 232 px column | — | P1 | Open a moment with a long question: nothing overlaps; tested for every combination (L2) |
| Event chips | Gold place chip with a pin icon, neutral tag chip, 24 high, round ends, 8 apart | 24 high chips (shared component), place, tie, event, level and when | Same chips, 8 apart, each capped at the card width (full text on hover); chips that do not fit the line are left out | No pin icon; "Returned after 3 days away" shows the record's own label | Line icons: true API limit (no vector art, no verified pin texture). The record holds no "days away" fact for most events, and the screen invents nothing | No | P2 | Gold place chip first, neutral event chip after it |
| Question | Alegreya Sans 22, line height 1.4, `#FBF3E0` | Alegreya Sans 19, body text colour, two lines at most (cut silently) | Alegreya Sans 22 with 6 px line spacing (28 px lines), title white, up to three lines; a longer question shows whole on hover | Text colour `#F4EEE2` vs `#FBF3E0` | Design choice: the shared title tone | Yes | P1 | Question size and colour next to the mockup |
| "Why now" well | `#11161F` well, `#232C3D` edge, padding 10 / 12, 14 px lines; bold gold-beige labels ("Why now:", "She remembers:"), muted text | Card-coloured well, one 13 px string with accent-coloured (not bold) labels; the echo appended to the Why now sentence | Darker well with the quiet edge, padding 10 / 12. Each line has its label in Alegreya Sans Bold 14 in the field-label tone and its text in the 14 px muted meta style, wrapping under itself; a long label (a long name) puts its text on the next line | Wrapped lines start under the text, not under the label (hanging indent) | True API limit: one font per font string, so a bold label and wrapping regular text cannot share one paragraph | No (only with a single font) | P2 | Bold "Why now:" label, muted reason |
| "remembers" line | "She remembers: “…”" | "Morrow remembers: “…”" in the same string | Own row, bold label, quoted titles of established memories only | Name instead of a pronoun | Design choice: Dawnward never assumes pronouns | — | — | A memory in the same zone appears; a proposed one does not |
| "Last time:" echo | (not in the mockup; added by the Director's echo) | Appended to the "Why now" sentence | Its own row, "Last time:" label, the player's own earlier answer as a sentence (`StoryView.WhyLines(view, memories, true)`; chat and the old call keep the appended form) | — | — | — | P2 | Die twice in one zone a few days apart: the second moment shows "Last time: … came back more careful." |
| Answer grid | Two columns, 8 apart; cards 52+ high, padding 8 / 14, `#1A2130` fill, `#33405A` edge, 16 px text | Two columns; 58 px fixed cards, default button fill, 15 px text cut at two lines | Two columns 8 apart, each row as high as its taller answer (52 minimum), padding 8 / 14, the design's fill and edge, answers in the 16 px reading style up to three lines | Answers can take three lines where the mockup shows two | Content: library answers are longer than the mockup's | — | P1 | Six answers: same rhythm as the mockup's grid |
| Number badge | 24 px key with 5 px corners, `#4A5874` edge, bold 13 | 24 px square outline, 13 px regular | 24 px round disc (two masked discs: a 1 px ring and the card-coloured fill; square where masks are unavailable), bold 13 | Round instead of the mockup's slightly rounded square | Design choice requested for this pass (`Style.Disc`) | — | P2 | Round numbered discs at the left of each answer |
| Hint line | (not in the mockup) | 13 px muted line, cut when long | 13 px muted line under the answer; the theme part is left out when the whole hint would not fit (the tooltip always has it). Only the fullest moments move hints into the tooltip | Not in the mockup at all | Design choice (v0.7): the player sees what an answer would propose before clicking | — | P3 | "More Compassionate" under the first quest answer |
| Answer hover | `.on`: `#2A2416` fill, gold edge, gold key with dark number, bright text | Lighter fill, gold edge | The mockup's chosen look on hover: dark gold fill (accent × 0.195 = `#2A2315`), gold edge, gold disc with dark number, title-white answer, field-label hint | No persistent "selected" state | Behaviour: a click answers at once (kept, as instructed) | — | P1 | Hover answer 2: it looks like the mockup's highlighted card |
| Own words | Label 14 / 500 `#D8C49A`; 64 px field, `#0F141D` well, placeholder "What does Kyssarra think or feel?" | Label, 58 px field | Label (bold 14, field-label tone), field 64 px when there is room (never below 36), the shared input well, focus ring and inline error next to the label; placeholder with the character's name | Label weight bold (700) instead of 500 | Medium weight not bundled | Yes (bundle Alegreya Sans Medium) | P3 | Click the field: gold ring; Save empty: inline error |
| Action row | 36 px buttons 8 apart: Save answer (primary, check icon), Later, Not now (ghost), Dismiss (danger) right-aligned | 30 px buttons with fixed widths | 36 px buttons sized to their labels (label + 16 each side), 8 apart, Dismiss at the card's right edge, pinned to the bottom | No check icon on Save answer | Line icons: true API limit | No | P2 | Bottom row lines up with the mockup |
| Empty state | (not in the mockup) | Title, body, summary | Cinzel title, a short gold rule, body in the reading style, summary in the meta style, centred | — | — | — | P3 | Answer every moment |

## 2. Header and side panels

| Element | Approved rendering | Before (v0.7) | Now | Difference remaining | Why | Fixable? | Priority | How to validate in game |
|---|---|---|---|---|---|---|---|---|
| Eyebrow | "STORY · MOMENT 1 OF 2" | Same | Same (unchanged) | No letter spacing | True API limit (shell audit) | No | P2 | Header |
| Pager | 36 px icon buttons ‹ › beside Close, 6 apart, disabled at 40 % | 36 px, "<" ">" in the small button font | 36 px, "<" ">" in the 20 px glyph style (as the close button), disabled by the shared 45 % | Text glyphs, not drawn chevrons | Line icons: true API limit | No | P2 | Arrows sit level with Close |
| Position label | (not in the mockup) | "1 of 2 · kept for later", 13 px | Same text in the 14 px meta style | Extra element | Design choice: says when a moment was kept for later | — | P3 | Left of the arrows |
| Also waiting | Card, eyebrow, an inner card: 15 px question, 13 px meta, padding 10 | Fixed 52 px button rows, 13 px text | Inner cards in the design's fill and edge (gold edge on hover), padding 10, question 15 px with 3 px line spacing up to two lines (whole on hover), 13 px meta; Reflect as a 24 px ghost button in the title row | Reflect is not in the mockup | Feature kept (#29) | — | P2 | Second moment appears as the mockup's inner card |
| Growth to approve | Inner card: "More **Compassionate**" 15 px, reason 13 px muted, Approve / Reject 30 px | 22 px buttons, label in the accent colour, reason two lines fixed | Inner card in the design's fill, label in Alegreya Sans Bold 15 bright gold, reason 13 px with 4 px line spacing (two lines, whole on hover), Approve (primary) and Reject (ghost) 30 px side by side | "More" is bold gold too (the mockup has it regular white) | One font and colour per font string; kept as one string | Yes (a second font string) | P3 | Approve and Reject are full-size buttons inside the card |
| Applied (Reverse) | (not in the mockup) | 28 px rows, 20 px Reverse | 34 px inner cards, 24 px Reverse; confirmation unchanged | — | — | — | P3 | Approve a change, then Reverse |
| Note | 13 px muted, 1.35 line height | 13 px, no extra spacing | 13 px with 4 px line spacing, measured | — | — | — | P3 | Under Growth to approve |
| Panel fit | Both panels fit beside the card | Fixed heights; could overflow with two moments, two changes and two applied | Heights measured; when the two panels would not fit, the second waiting row goes first (still counted, reachable with < >), then the second applied change, then the second pending one (both still in `/dawnward develop`) | — | — | — | P2 | Many moments and changes at once: nothing below the window |

## 3. Reaction card

| Element | Approved rendering | Before (v0.7) | Now | Difference remaining | Why | Fixable? | Priority | How to validate in game |
|---|---|---|---|---|---|---|---|---|
| Card | (no mockup; the moment in miniature) | 400 × 116, meta at the top right beside the eyebrow (could touch it), 22 px buttons | 400 wide, height follows the question (one to three lines); eyebrow, then the meta line (14 px) on its own line, the question in the reading style, compact 30 px buttons sized to their labels, a 28 px close button | No mockup to compare | — | — | P2 | Turn in a quest out of combat |

## Remaining differences that are true API limits

- Rounded corners on cards, answer cards and buttons; drop shadows.
- Line icons (pin on the place chip, check on Save answer, chevrons).
- Letter spacing on the eyebrow.
- A bold label and regular text wrapping in one paragraph (the "Why now" well uses a hanging indent instead).

## Proposals for shared components (not changed here)

- `Widgets.GLYPHS`: map "<" and ">" to the glyph style like "X", so every pager gets the larger glyph (done locally in StoryView).
- A shared "inner card" painter (the mockup's `#1A2130` / `#2C3648` card inside a panel); StoryView paints its side rows locally.
- A "measured text" helper (`StoryView.WrapLines` + client height) in `Widgets`, for other screens that lay out variable text.

## Manual in-game visual acceptance (compare with story-director.png)

1. `/reload`, open the journal, turn in a quest out of combat. The reaction card appears: eyebrow, "Quest completed · <zone>" on its own line, the question in large reading text, Answer / Later / Dismiss 30 px high. Nothing touches the close button.
2. Click Answer. The Story screen opens on that moment; the eyebrow reads "STORY · MOMENT 1 OF n".
3. Compare the moment card with the mockup: dim gold edge (not a glowing callout), chips at the top, the question at 22 px in title white, the darker "Why now" well with a bold beige "Why now:" label and muted text.
4. Check the answer grid: two columns 8 apart, round numbered discs, answers in 16 px reading type, a short hint under each. Hover an answer: dark gold fill, gold edge, gold disc with a dark number.
5. Check the "Or in your own words" label and field, and that Save answer / Later / Not now sit at the bottom left with Dismiss at the bottom right, all 36 px high.
6. Click in the field: gold focus ring, placeholder disappears. Click Save answer with nothing typed: the error appears beside the label and the moment stays.
7. Die twice in the same zone a few days apart (or use a test character): the second moment shows a separate "Last time:" line with your earlier answer.
8. Create two or three moments in different zones (`/dawnward story set frequency frequent`): Also waiting shows the next one as an inner card; hover it (gold edge) and click it to switch. Use < > in the header.
9. Answer a moment: Growth to approve shows "More …" in bold gold, the reason, and full-size Approve and Reject. Approve, then Reverse the applied change and confirm.
10. Resize the window to its smallest and largest scale: everything keeps its proportions and nothing leaves the card or the panels.
11. Switch theme in Settings and repeat steps 3–4: every colour follows the theme.
12. Answer every moment: the empty state shows the title, a short gold rule, the explanation and the summary, centred.
