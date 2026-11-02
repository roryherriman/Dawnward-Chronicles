# Audit v0.10: Settings, first-time setup, Total RP 3 page, story import, and how the profile looks in Total RP 3

Scope: `UI/SettingsPanel.lua`, `UI/SetupWizard.lua`, `UI/TRP3Page.lua`, `UI/ImportWizard.lua`, the presentation parts of `Integrations/TRP3/Presentation.lua` and `Integrations/TRP3/Commands.lua` (`ProfilePreview`, new `AboutDisplay` and `PlainLines`). `AboutDoc.Plan`, `Sync.lua`, `Ledger.lua` and `Adapter.lua` are unchanged.
Compared with: [first-time-setup.png](../mockups/first-time-setup.png) (`source/SetupWizard.dc.html`), [proposed-trp3-sync.png](../mockups/proposed-trp3-sync.png) (`source/TRP3Sync.dc.html`), [design-system.png](../mockups/design-system.png). The General, Story, Data and Help pages and the import window have no rendering of their own; they follow the TRP3 mockup's settings frame and the setup's language.
Base: `origin/feat/v0.10-no-privacy` at `cc67ebf`.

**Nothing here has been checked in the game.** The L2 suite (WoW mock) proves wiring, sizes, positions and that text fits by the bundled fonts' advance widths; whether it looks right is the owner's in-game comparison (last column, and the steps at the end).

No sync behaviour changed: every action still calls the same guarded function (`TRP3Commands.Approve`, `SetFeature`, `ConnectAll`, `CreateProfile`, `SelectProfile`, `Import`, `Sync.Authorize`, `Sync.Resolve`, `Sync.Rollback`) behind the same confirmations. The Public / Private / Secret classification stays removed (no chip anywhere; `ui_no_privacy*_spec.lua` green).

## 1. Settings (General, Story, Data, Total RP 3, Help)

| Element | Approved rendering | Before (v0.9) | Now | Remaining difference | Cause | In-game check |
|---|---|---|---|---|---|---|
| Pages | Sub-tabs in a track (TRP3Sync.dc.html) | General, Story, Data, Total RP 3 | General, Story, Data, Total RP 3, **Help** (5 × 104, Done at the right) | Track has no 3 px inner padding | Shared `Widgets.Segmented` (another engineer's component) | Five tabs in one track, Done not gold |
| General | (design system rows) | Appearance; Interface and help with four buttons (minimap, guide, setup, reset) | Appearance (theme gallery, unchanged); **Interface**: Minimap button as a **Shown / Hidden** segmented choice, Window size → Reset window size | — | — | Click Hidden: the minimap button disappears, Hidden stays raised |
| Minimap control | Clear active state | One cycle button "Minimap button: shown" | Two segments, the state in use raised | — | — | — |
| Story | Clear active state | One "Story settings" panel of ten rows, incl. "TRP3 style" | Two panels: **Story moments** (Moments, Significance, Places, Story pace, Card, Class flavour) and **Your answers and records** (Changes, Drafts, Quests); every option visible, the one in use raised. Story pace keeps the gameplay-time wording ("Brisk (1 h)…", play time only) | — | — | Story → both panels; click an option: it rises, status confirms |
| TRP3 style | — | A Story row | Moved to Total RP 3 → Biography, beside the template it styles (same `Actions.SetStoryPref("trp3Style")`) | — | Deliberate: one place for how the About page looks | — |
| Data | — | Backup and sharing, Your story, Simulation mode | Backup and sharing, Your story ("Import a story…") | — | — | Each button opens the same window as before |
| Help | — | (inside General) | **Help and setup**: Guide, First-time setup (Run setup), Chat commands (List the commands); the version line | — | — | Help → three rows, each button works |
| Developer tools | Not on ordinary screens | Simulation mode on Data for everyone | **Testing** panel on Help (simulation toggle, Reset test data with its confirmation, Preview setup) shown only in development builds (`SetupCommands.DevEnabled`) or while simulation is on, so it can always be turned off | — | — | Release build: no Testing panel; `/dawnward sim on` → it appears |

## 2. First-time setup

| Element | Approved rendering | Before (v0.9) | Now | Remaining difference | Cause | In-game check |
|---|---|---|---|---|---|---|
| Stages | Welcome, Character, Story, Privacy, Appearance, Finish | Welcome, Character, Story, Appearance, Total RP 3 (when installed), Finish | Same (no Privacy stage; owner decision v0.9) | Privacy stage absent | Deliberate (classification removed) | Rail lists five or six stages |
| Character grid | Name · Title / Pronouns · Homeland / About them, 40 px inputs, 96 px area | 48 px portrait and identity row above the grid; 80 px area | The mockup's grid from the top; the game identity is the **Name's hint** ("Suggested from your character (Human · Paladin). Change it if you like.", the mockup's hint wording); About them 96 px; rows 98 apart so a two-line hint never meets the next label | No live portrait | Deliberate: the mockup has none | Type 101 characters in Title: red ring and red line, nothing overlaps |
| Note under the fields | Lock + "Everything starts Private" | Profile note + Import a story… | Same (no lock, no Private wording) | Privacy box text | Deliberate (classification removed) | — |
| Story / Appearance / Total RP 3 choices | (not rendered) | 30 px cycle buttons with a "›" | **Segmented choices**, every option shown with short labels (Rarely · Normal · Often · Never; On · Fewer · Off; Card · Chat line; Ask me first · Apply at once; Shown · Hidden; Connect · Not now; Keep mine · Use Dawnward's); the full wording on hover | — | — | Story stage: four rows of segments, the current one raised |
| Total RP 3 stage | — | Status, Create / Switch profile, Refresh connection, choices | Unchanged behaviour; choices segmented | — | — | Default profile: Create a profile…; after creating, Connect enabled |
| Review (Finish) | — | Two text panels | Same panels; labels in the field-label tone, values plain; **Backstory** line added ("saved word for word (n paragraphs)" / "none yet"); the Total RP 3 line says what Finish will actually do | Rows are text lines, not a grid | Space: two 254 px columns | Finish: Backstory line, Total RP 3 line |
| Resume / completion | Draft kept, nothing saved until Finish | Same | Unchanged (draft only of edited keys; completion only on Finish) | — | — | Close on Story, reopen: back on Story with choices kept |

## 3. Total RP 3 page

| Element | Approved rendering | Before (v0.9) | Now | Remaining difference | Cause | In-game check |
|---|---|---|---|---|---|---|
| Summary strip | TOTAL RP 3 · LINKED PROFILE · SYNC + Experimental | Same | Unchanged | Eyebrow 13 vs 11, no tracking | Readability minimum; verified no letter spacing | Hover a value: full text |
| Organisation | Card (Biography/Traits) + right column (conflict, backups) | Tabs Overview · Biography · Traits · Mappings, right column always | **Section rail** (188 wide, 44 px items like the shell navigation, gold bar on the open one, a state dot each): Connection · Character information · Biography · Personality · Appearance and At First Glance · Synchronization status · Conflicts and recovery; one section card beside it (568 × 464) | The mockup's always-visible right column is now the "Conflicts and recovery" section | Deliberate (brief: organise by purpose); a pending conflict marks the rail amber, the part's own section red, and the page opens on it | Seven rail items; click each |
| Connection | — | Overview tab | Active profile, connected character (n of 20 items), **last successful sync**; the connection note; Connect everything… / Create a profile… / Switch profile… / Switch back…, Preview profile, Refresh connection; Publish whole profile… for older characters | — | — | Default profile: Create a profile…; switched: Paused, Switch back… |
| Character information | — | Mappings tab (all 20 rows, paged) | The 14 field and additional-information mappings, Dawnward / TRP3 / Off, Import per field, staged until Authorize… (same confirmation), the unsupported note | Long details cut (full on hover) | Space | Stage Race → Dawnward, Authorize… lists "+ Race" |
| Biography | Proposed-change card | Feature card with a 4-line text preview | Header with state chip, explanation, status line (amber when blocked or in conflict), kept-text line, **Content / Template / Style** choices, and a **preview drawn as Total RP 3 shows it**: h1/h2/h3 headings in decreasing size, paragraphs, template 2 frames with their icon (left, right, alternating as TRP3) and tiled background, template 3's "icon  Title  icon" parts; scrolls (wheel) | Fonts are Dawnward's, not TRP3's SystemFont_Shadow faces; no "+ Background:" bold runs | One style per font string (verified limit); preview uses the bundled fonts for a consistent window | Biography → Frames + Silver Hand: framed sections, marble background, gold headings |
| Personality | Traits | Text lines "Brave 14 / 6 Cautious" | Trait bars: left word, bar leaning by value (V2/20), right word | No trait icons | Dawnward's traits use TRP3's default question-mark icon | Set an axis: one bar |
| Appearance and At First Glance | — | Rows on Mappings | Eye colour, Height, Build and At First Glance rows (same staging), and the At First Glance entries listed | — | — | — |
| Synchronization status | — | Overview lines | Biography (with the About page's read-only trace on hover), Personality, Character information (n of 14), Additional information, At First Glance, Last successful sync, **Last problem** (amber, from the write log), Conflicts; then **Never sent, or not supported** (counts only; unsupported list, accurate for the v0.9 profile model) | — | — | After a sync: date and time in Last successful sync |
| Conflicts and recovery | Amber callout + backups | Right column, 3 backups | Amber callout (Keep yours / Use Dawnward's, stacked so both labels fit) or a calm "No conflicts" panel, and "Also waiting: …"; **5 backups**, Roll back… and Exact restore… with the same confirmations (exact restore names what comes back) | — | — | Edit a synced trait in TRP3: page opens here, amber callout |
| Unsupported text | — | Said pronouns and names are never written (wrong since v0.9) | "Never written: Currently and RP status, icon and colours, walk-up, roleplay experience and music. Your one Name is never split…" | — | Correction | — |

## 4. How the profile looks in Total RP 3 (Phase 7)

| Element | Total RP 3 3.4.1 (verified in its source) | Before | Now | Remaining difference | Cause | In-game check |
|---|---|---|---|---|---|---|
| Markup | `{h1-3}`, `{/hN}`, `{p:c/r}`, `{col:hex}`, `{/col}`, `{icon:name:size}` (Utils.lua structureTags, convertTextTag) | Same tags | Same tags; L1 test rejects any other tag in Dawnward's own output (the player's biography is kept word for word, their own tags included) | — | — | No raw `{h2}` text on another client |
| Section icons | InterfaceIcons.lua: the only or oldest candidate of DirectorySection, HistorySection, MiscInfoSection, PhysicalSection, TraitSection, TargetNotes, ProfileDefault | Same names | Same names, now on `Presentation.ICONS` (with where each was verified); the preview only draws allowlisted icons | Icon presence in the 1.15.9 client is inferred from TRP3 shipping them as Classic fallbacks; the UI source holds no icon list | Verified limit of the evidence | Arcane style: every heading shows its icon, no question marks |
| Frame backgrounds | Tiled list, Core/UITools.lua | Neutral/Arcane 1, Silver Hand **2** (Bank-Background) | Neutral/Arcane 1 (Dialog), Silver Hand **3 (Marble)**; `Presentation.BACKGROUNDS` lists 1, 3, 4 with the Classic UI files that use them | Background 2 appears only in a later client's BankFrame.xml in the 1.15.9 source tree; not used | Verified (not in Classic sources) | Frames + Silver Hand: marble frames |
| Heading colours | `{col}` | Neutral white, Silver Hand #E6C35C, Arcane #B89CFF | Unchanged (Neutral byte-identical, so earlier profiles are not rewritten) | — | Deliberate | — |
| Paragraph spacing | toHTML drops the line break after a heading; a blank line shows as one empty line | One blank line between sections | Unchanged (verified correct) | — | — | — |
| Player's formatting | — | Restyled frames keep IC/BK (AboutDoc planFrames) | Unchanged; documented | — | — | Restyle a Dawnward frame in TRP3, change a fact: icon and background stay |
| Preview window ("Preview profile") | — | Raw markup | Laid out as TRP3 shows it: per frame "icon, background", template 3's titles, headings as "-- Title --", colour and icon codes removed | Plain text (a copy window) | Copy window is an edit box | Connection → Preview profile |

## 5. Story import window

| Element | Approved rendering | Before (v0.9) | Now | Remaining difference | Cause | In-game check |
|---|---|---|---|---|---|---|
| Steps | (setup's rail language) | Eyebrow "STORY IMPORT" only | Two round step badges beside the eyebrow (Paste your story · Review the pieces): gold current, check when behind, each clickable; eyebrow "STORY IMPORT · STEP n OF 2" | — | — | Save and review: step 1 shows a check |
| Title | Cinzel 26 (setup) | Cinzel 28 | Cinzel 26 (`stage`) | — | — | — |
| Privacy chip | None | None | None | — | — | — |
| Category | — | Cycle button "Category: … ›" | Unchanged | Still a cycle | Not done: eleven categories do not fit a segmented row | — |

## 6. Shared components built locally (for the shared-components engineer)

1. Section rail (`buildRail` in TRP3Page.lua): a vertical, multi-line segmented navigation with a state dot and a gold selection bar.
2. Segmented choice with `Update / SetEnabled / IsEnabled / GetText / Option` (`choiceRow` in SetupWizard.lua) — `Widgets.Segmented` has no enabled state or per-item widths.
3. Pooled preview renderer (`newRenderer` / `TRP3Page.Render`): headings, paragraphs and textured frames in a slim-bar scroll frame.
4. Step badges (ImportWizard `buildSteps`, SetupWizard rail): a shared `Widgets.StepBadge` would remove two copies.
5. Amber callout tone (`paintAmber`), still local.

## 7. Tests added or changed (L1/L2, mocked client)

- New `trp3_presentation_allowlist_spec.lua` (9): code lists equal the verified lists; every style's background verified; every template × style writes only verified icons, backgrounds and tags; the biography word for word in every template and style; Neutral unchanged; the preview model reads headings/paragraphs as toHTML, converts colour/icon codes, keeps TRP3's order (page, frames, three titled parts); the copy-window layout.
- `ui_trp3_page_spec.lua`: rail order, sizes and two-line names; titles beside the chip; card/rail fill the page; mapping rows, glance box, recovery columns, backup list + both restores + note fit; Biography stack (status, kept text, choices, preview) above the action rule; trait bars fit; every explanation in two lines; the preview mirrors order, headings, frames, Marble background and gold headings; Synchronization status lines, last sync, last problem in amber; all behaviour tests now drive sections (opt-in, guards, conflict, rollback, mappings, import, shared profile, privacy sweep over every section).
- `ui_settings_spec.lua`: five pages; Help rows; Testing panel only in dev builds or while simulation is on; story panels fit; minimap segments fit. `ui_minimap_spec.lua`: Shown/Hidden segments.
- `ui_setup_layout_spec.lua`, `ui_setup_wizard_spec.lua`, `trp3_setup_connection_spec.lua`, `first_login_spec.lua`: Name hint carries the identity; two-line hints never meet the next label; 96 px area; every choice a segmented control with every option fitting; review lines include the backstory with labels in tone.
- `story_import_spec.lua`: steps beside the eyebrow, before the close button, states and clicks.
- Mock: `SetTexture` records the file (conservative).

## 8. In-game checks (owner)

1. `/reload`, `/dawnward`, Settings: five tabs; General shows Appearance and Interface (Minimap Shown/Hidden, Reset window size). Resize the window to 0.7 and 1.4: nothing clips.
2. Story: two panels, every option visible. Data: Backup and sharing, Your story. Help: Guide, Run setup, List the commands; no Testing panel on a release build.
3. Settings → Total RP 3 with TRP3 3.4.1: the rail on the left; each section's dot (green connected, amber waiting, red conflict).
4. Biography: choose Frames + Silver Hand: framed sections, marble background, gold headings, icons left/right alternately; Arcane: violet headings with icons; Sections: "Physical Description / Personality Traits / History". Compare with TRP3's own About page on a second account after a sync (same headings, order, frames).
5. Personality: bars lean as TRP3's own bars do.
6. Synchronization status: after a sync, a date in Last successful sync; hover Biography for the trace.
7. Edit a Dawnward trait in TRP3: the page opens on Conflicts and recovery, amber callout; Keep yours / Use Dawnward's behave as before; Roll back… and Exact restore… ask first.
8. Setup (Settings → Help → Run setup): the Character grid as the mockup, the Name's hint names race and class; Story choices segmented; Finish lists the backstory.
9. Character → Import story: step badges beside the eyebrow; Save and review ticks step 1.
