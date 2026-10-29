# Dawnward Chronicles v0.7: UI design specification

Status: **in development on `claude/upbeat-mendel-ds1ct4`**. Stage A (window shell, character rail, Character Showcase, fonts, colour tokens) is built and passes automated tests (L2). Nothing in v0.7 has been verified in game yet.
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

Two further images are **proposals awaiting approval**, not approved designs:
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

## 4. Audit: current UI against each mockup

Honest gap list after stage A. "Shell" means the window frame, rail and header, which are shared by every screen.

| Screen | Matches now | Still different |
|---|---|---|
| Shell (all screens) | Left character rail with portrait, name, title, race · class · pronouns, level; rail navigation with icons, selection marker and a waiting-moments badge on Story; Guide and Settings at the bottom of the rail; eyebrow and title header; colour tokens; fonts; TRP3 status line | Icons are game textures, not line icons. The close button and scroll bars keep the existing styles |
| Journal | Header ("<Name>'s Journal") | Entries are still v0.6 rows. Missing: date block per entry, card layout, "today" summary strip |
| Character | Live model (Character Showcase) beside the profile; profile fields with visibility | Fields are a list, not grouped tiles. Missing: privacy badges styled as chips, the identity header block inside the section |
| Story Director | Header and waiting badge | Choices are still a vertical list, not the two-column choice grid with tone labels |
| Chronicle: Memories | Section tabs and entry panels (v0.6) | Not cards with a date column and type chip yet |
| Chronicle: Places | Status and action buttons per place | Not the master-detail layout (list left, selected place right) |
| First-time setup | Works (v0.6 wizard) | Visual style is v0.6: no step rail, no portrait on the Character page |
| Design system | Tokens, fonts, buttons, inputs | Chips and tiles are not components yet |

## 5. Stages

Each stage keeps every existing feature reachable, changes no SavedVariables format and must pass `python tools/check.py` before the next starts.

| Stage | Scope | Status |
|---|---|---|
| A | Window shell and character rail, Character Showcase, fonts, colour tokens, story pace setting | **Built**, L2 |
| B | Section internals: Journal cards with date block, Character tiles and chips, Story choice grid, Chronicle memory cards, Places master-detail | Next |
| C | Total RP 3 sync page in Settings, per the proposed mockup, **after the proposal is approved** | Waiting for approval |
| D | Setup wizard restyled to the approved mockup (step rail, portrait) | Planned |
| E | In-game verification (parts Q and R of [TESTING.md](../TESTING.md)), screenshots, fixes | Needs the owner's game |

## 6. Stage A in detail

- **Window** (`UI/MainWindow.lua`): 1100 × 720, rail 272 px wide, content from 96 px below the top to 36 px above the bottom, padding 28. `MainWindow.ComputeLayout` gives every rectangle, so the layout is unit-tested.
- **Rail identity**:
  - Read live from the game through `Showcase.GameIdentity()`: level, race and class. Never stored.
  - Name, title and pronouns come from the player's own profile fields.
  - Until a profile name is set, the game's character name is shown.
- **Navigation**: Journal, Character, Story and Chronicle buttons with icon, label and badge. The Story badge counts moments waiting for an answer.
- **Character Showcase** (`UI/Showcase.lua`):
  - The live 3D model in the gear the player is wearing.
  - Turn it with the ‹ › buttons or by dragging.
  - Falls back to the portrait when `SetUnit` fails.
  - Nothing renders while the journal is closed: the model is cleared on hide, and events are registered only while shown.
  - Steps aside while a field is being edited.
  - API evidence (from the 1.15.9 UI source):
    - Blizzard's own Classic QuestFrame and TabardFrame use `PlayerModel:SetUnit("player")`.
    - `CharacterModelBase` provides `SetRotation` and `ClearModel`.
- **Fonts** (`UI/Style.lua`, `Media/Fonts`): nine font objects, each replacing one game template.
- **Story pace** (Settings → Story): see [ARCHITECTURE.md](../ARCHITECTURE.md#gameplay-time-the-narrative-clock).

## 7. Total RP 3: requirements and what exists

Total RP 3 stays optional. Dawnward works fully without it.

| Requirement | Exists today (commands, v0.4–v0.6) | UI in v0.7 |
|---|---|---|
| TRP3 status and linked profile | `/dawnward trp3`, `trp3 diagnose`; Settings → Total RP 3 shows status | Rail status line (stage A); full page in stage C |
| Sync status | `trp3` status lines per feature (off, waiting, blocked, conflict, up to date, has changes) | Stage C |
| Preview of the public profile and of proposed changes | `trp3 preview`, `trp3 paste` | Stage C: side-by-side preview and change list |
| Explicit approval before publishing | `trp3 enable about|traits confirm`; nothing is written without opt-in | Stage C: an Approve button per change set |
| Conflict warnings | Conflict state; `trp3 resolve about|traits keep|reclaim` | Stage C |
| Backup and rollback | `trp3 backups`, `trp3 rollback [#] confirm`; a backup is taken before every write | Stage C |
| Unsupported mappings | Only About and Characteristics are synced; Dawnward never writes profile fields such as name or title | Stage C lists them as "not synced" |
| Only approved Public data, never Private or Secret | Enforced in `Integrations/TRP3` by visibility checks before any write | Unchanged |
| Never silently overwrite authored TRP3 content | Dawnward writes only its own section and checks ownership; conflicts stop the write | Unchanged |
| Opt-in, per character and per profile | Opt-in is stored per character and bound to the TRP3 profile | Unchanged |

The proposed page ([proposed-trp3-sync.png](mockups/proposed-trp3-sync.png)) only puts these existing, tested protections on one screen. It adds no new kind of write. It will not be built until the proposal is approved.

## 8. Acceptance for each stage

- The screen is compared with its mockup side by side on an in-game screenshot.
- Every difference is listed: fixed, or explained with a limit from section 3.
- All existing commands and features still work, and the automated suite passes.
- No Private or Secret data appears anywhere it did not appear before.
