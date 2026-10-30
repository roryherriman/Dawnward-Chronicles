# Dawnward Chronicles v0.7: UI design specification

Status: **implemented (stages A to D); refined by v0.8, see [UI_DESIGN_V08.md](UI_DESIGN_V08.md), which is newer where the two differ (type sizes, control heights, Journal scrolling).** Every screen is rebuilt to its approved mockup and passes the automated suite (L2). **Nothing in v0.7 has been verified in game yet**; see [TESTING.md](../TESTING.md) parts Q, R and S.
Baseline: v0.6.0-dev, schema 5, Classic Era 1.15.9 (interface 11509), Lua 5.1.
Supersedes the visual design in [UI_DESIGN_V06.md](UI_DESIGN_V06.md). The v0.6 component kit, keyboard rules, inline validation and themes are kept.

## 1. Source of truth

The seven approved mockups (approved 2026-10-29) are the visual source of truth and the acceptance criteria for v0.7. They are **design concepts, not screenshots**. The names, stories and places in them are sample data: the addon always shows the player's own character.

| Screen | Mockup |
|---|---|
| Journal (dashboard) | [journal-dashboard.png](mockups/journal-dashboard.png) |
| Character | [character-profile.png](mockups/character-profile.png) |
| Story Director | [story-director.png](mockups/story-director.png) |
| Chronicle: Memories | [chronicle-memories.png](mockups/chronicle-memories.png) |
| Chronicle: Places | [chronicle-places.png](mockups/chronicle-places.png) |
| First-time setup | [first-time-setup.png](mockups/first-time-setup.png) |
| Design system | [design-system.png](mockups/design-system.png) |

Two further designs were approved later (2026-10-29), and keep their original file names:
- [proposed-trp3-sync.png](mockups/proposed-trp3-sync.png): the Total RP 3 sync page.
- [proposed-character-showcase.png](mockups/proposed-character-showcase.png): the Character Showcase.

The gallery, provenance and re-render command are in [mockups/README.md](mockups/README.md).

A screen "matches" a mockup only when its layout, hierarchy, components and content placement match, not just its colours. Where Classic Era cannot reproduce something exactly, section 3 says so and names the closest alternative.

## 2. Design tokens (from the design-system mockup)

| Token | Hex | Theme role (`Core/Themes.lua`, theme `dawnward`) |
|---|---|---|
| Night | `#0E1219` | `background` |
| Panel | `#121825` | `panel` |
| Surface | `#151B26` | `surface` |
| Surface hover | `#1F2838` | `surfaceHover` |
| Edge | `#2C3648` | `edge` |
| Ornament | `#C9A55E` | `ornament` |
| Parchment text | `#EFE7D6` | `text` |
| Muted text | `#A6A08F` | `muted` |
| Gold accent | `#D8B26A` | `accent` |
| Text on gold | `#1A1408` | `accentText` |
| Danger | `#E8837A` | `danger` |
| Border | `#6B5631` | `border` |

Type:
- Display: Cinzel SemiBold (screen titles 26, section titles 19, names 18, eyebrows 11).
- Labels: Alegreya Sans Bold 14.
- Reading text: Alegreya Sans Regular 15, small 13.

Both fonts are OFL and bundled (see [THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md)). `Style.Font(template)` maps each game font template to its Dawnward font object.

The other themes (Lightbound, Shadowbound, Neutral, Silver Hand, Arcane) keep their own palettes and stay player-chosen. A saved theme is never changed.

## 3. Classic Era limits and the closest alternatives

| Mockup feature | Limit in the 1.15.9 client | What v0.7 does instead |
|---|---|---|
| Line icons (SVG) in the rail and on cards | No vector graphics; textures only | Game icon textures (`Interface\Icons\…`) at small size. Same position and meaning, different drawing style |
| Round portrait with a gold ring | No arbitrary masks. `SetPortraitTexture` already draws a round portrait | The game's round portrait with the minimap tracking-ring texture tinted gold. The texture coordinates need an in-game check (R4) |
| Soft shadows, gradients, rounded corners | No CSS. Gradients need `SetGradient` per texture; there are no rounded rectangles without art | Flat fills, 1 px edges and corner brackets from the v0.6 chrome. Square corners |
| Web fonts | Only fonts shipped in the addon folder; one file per weight | Cinzel and Alegreya Sans bundled as TTF. Non-Latin clients keep the game fonts |
| Fluid layout | Fixed-size frames, anchored | A fixed 1100 × 720 window that scales down to fit the screen by width and height (`Style.FitScale`) |
| Character art in the Showcase | The client can only render the player's real model | `PlayerModel` with `SetUnit("player")`; the portrait when that fails. Never invented art or gear |
| Hover tooltips with rich layout | `GameTooltip` lines only | Plain tooltip lines |

## 4. Audit: each screen against its mockup

What the implementation matches, and what still differs and why. "Classic" means a limit from section 3.

| Screen | Matches the mockup | Still different |
|---|---|---|
| Shell | Left character rail with portrait, name, title, race · class · pronouns, level; navigation with icons, selection marker and a waiting-moments badge on Story; Guide and Settings; eyebrow and title header; the Total RP 3 status line, which opens the Total RP 3 page; colour tokens and fonts | Icons are game textures (Classic). Scroll bars keep the stock style |
| Journal | "The road so far" with real counts; New entry, search, All / Defining / Story / Events filter; "A moment awaits" callout with Answer and Later; entry cards with date block, title, meta line, chips, visibility and actions inside the card; Active goals with progress bars; Recent places with chips; empty states | Paged (10 per page) rather than one long scroll. No line icons (Classic). Drafts have Delete rather than a separate Reject, because no reject action exists for journal drafts |
| Character | Identity, Background & biography and Summary panels of tiles, each with its visibility chip and Edit; Personality with real values and waiting changes linking to Story; Family & relationships; public profile preview (from the same public projection as exports and Total RP 3); Total RP 3 button | Personality visibility is in the tooltip; personality is still edited with `/dawnward personality`. Heading stays "Profile" (the mockup's "Who she is" assumes a pronoun) |
| Character Showcase | Live model in current gear, turning (buttons and drag), zoom (buttons and wheel, `SetPortraitZoom` 0–0.7 as Blizzard's own model frames use), portrait choice remembered per character, automatic portrait fallback, "In game" (level, race, class colour, guild, realm, read live) apart from "Your character" | The model's lighting and camera are the client's |
| Story Director | Event chips (place, tie, what happened, level and when); "Why now" from the Director's real reasons; memories it recalls; two-column choice grid with hints; own words with inline validation; Later, Not now, Dismiss; Also waiting; Growth to approve with reasons, Approve, Reject and Reverse | A choice answers on click (as before) rather than pick-then-save. Number keys are labels only. "Returned after N days away" shows the record's own label instead |
| Chronicle: Memories and other tabs | Tabs with counts on every tab (Memories, Arcs, Goals, Stances, People, Places, Review); New, search, counts and pager; 2×2 card grid with status chip, date, title, meta, text, chips, visibility, progress bars on goals, actions inside the card; empty states | Fixed-height cards: very long text is cut off inside the card (full text in Edit). Short date text at the top right, as in the mockup |
| Chronicle: Places | List and detail: list with Homeland and meaningful markers, zone · kind and visits; detail with what the place means, visits, last visit, next return moment (read-only, from gameplay time), tied memories and the actions | The Homeland icon is a game texture that needs an in-game check |
| First-time setup | Step rail with done / current / upcoming, step header, grouped panels, your portrait and live identity on Character, Privacy chips with what each means, optional Total RP 3 status (setup never publishes), Back / Next / Set up later / Finish | Square step badges (Classic). Clicking a step in the rail jumps to it (an addition) |
| Total RP 3 page | Status strip (installed, version, supported; linked profile; sync per feature; Experimental); proposed change with your own text kept; exactly what would be written, public only; never shared (counts only) and fields Dawnward never writes; Approve and write, Not now, Enable / Stop; conflict callout with Keep yours / Use Dawnward's; backups and Roll back | One feature at a time with a Biography / Traits switch. Releasing Dawnward's section is still command-only (`trp3 release`) |
| Design system | Tokens, fonts, buttons, chips, panels, callouts, date blocks, progress bars, search boxes, inputs (`UI/Widgets.lua`) | Square corners; no shadows (Classic) |

## 5. Stages

| Stage | Scope | Status |
|---|---|---|
| A | Window shell and character rail, Character Showcase, fonts, colour tokens, story pace setting | Built, L2 |
| B | Journal dashboard, Character profile, Story Director, Chronicle cards and Places list-and-detail | Built, L2 |
| C | Total RP 3 page (Settings → Total RP 3) | Built, L2 |
| D | Setup wizard restyled | Built, L2 |
| E | In-game verification ([TESTING.md](../TESTING.md) parts Q, R and S), in-game screenshots, fixes | **Needs the owner's game** |

## 6. Shared components

All screens use the same components from `UI/Widgets.lua`, so they stay consistent:

| Component | Use |
|---|---|
| `Button` | Variants: default, primary, ghost, danger, choice |
| `Segmented` | Filters and tabs |
| `Card` / `EntryRow` | One record per card, actions inside |
| `Chip` | Status pills; visibility tones use the fixed visibility colours |
| `Panel`, `Callout` | Grouped sections with an eyebrow title; the one thing waiting on the player |
| `DateBlock`, `ProgressBar`, `SearchBox` | Entry dates, goal progress, search |
| `VisibilityButton` | Public / Private / Secret |
| `EditLine`, `TextArea`, `FieldError`, `FocusChain` | Inputs, inline validation, Tab and Shift+Tab navigation |
| `Confirm` | Confirmation dialog |

## 7. Total RP 3: requirements and the page

Total RP 3 stays optional; Dawnward works fully without it.

**No new write behaviour.** The page (`UI/TRP3Page.lua`) calls the same guarded functions as the `/dawnward trp3` commands (`Integrations/TRP3/Commands.lua`, then `Sync`). Opening the page, previewing and "Not now" write nothing.

| Requirement | Where it is enforced | On the page |
|---|---|---|
| Status and linked profile | Adapter probe | Status strip |
| Sync status per feature | `Sync.Check` | Chip and reasons |
| Public preview and proposed changes | `Projection.GetPublic`, `AboutBlock`, `TraitPlan` | "Exactly what would be written" and the change list |
| Explicit approval | Opt-in per character and profile; Approve refuses without it | Enable (confirmed), Approve and write |
| Conflicts | Ownership check in `Sync.Check`; a conflict blocks writes | Callout with Keep yours / Use Dawnward's |
| Backup and rollback | Backup before every write; read-back undo | Backups list, Roll back (confirmed) |
| Unsupported mappings | Only About and traits are written | "Not written by Dawnward" list |
| Only Public data, never Private or Secret | `Projection.GetPublic` | Private and Secret appear only as counts |
| Editor, combat and version guards | `Sync` guards | Shown as Waiting or Blocked with the reason |

## 8. Acceptance for each stage

- The screen is compared with its mockup side by side on an in-game screenshot.
- Every difference is listed: fixed, or explained with a limit from section 3.
- All existing commands and features still work, and the automated suite passes.
- No Private or Secret data appears anywhere it did not appear before.
