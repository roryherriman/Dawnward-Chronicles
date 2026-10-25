# UI direction (from v0.2)

Status: **direction in use.** v0.2 implements the first part: the three-section window, the settings panel and three cosmetic themes. Emblems, theme suggestions, resizing and paged reading remain open (see the end of this document).

## Why
An earlier project showed that too many tabs, controls and features can hurt usability. Dawnward Chronicles should feel like a **character's journal you read and write in**, not a management dashboard.

## Principles

1. **Three sections only: Journal, Character and Story.** No further top-level tabs.
2. **A compact settings area holds everything technical:** Total RP 3 integration, backup/export/import, simulation mode, and other options. It is reached from a single small control, not a fourth section.
3. **Reading and writing come first.** Large, comfortable text areas take priority over counts, charts or status panels. Numbers appear only where they help the story, such as a level next to a journal entry.
4. **One layout for every character.** Characters differ in content and theme, never in structure.
5. **Per-character themes** use packaged textures, accent colours, borders and optional emblems.
6. **A small set of built-in themes**, including a neutral default.
7. **Players choose their theme and can override any part of it.** Class or race never decides a character's identity or look.
8. **Theme suggestions come later**, based on class, race and *approved* backstory. They are optional and never applied automatically.
9. **No runtime AI, no external services, and no generated textures.** Everything ships inside the addon.
10. **Restraint:** no unnecessary animation, decorative clutter, or controls without a demonstrated need.
11. **Readable at any resolution and UI scale.**
12. **Start small** and grow only when a real need appears.

## Structure

```
┌───────────────────────────────────────────────┐
│ [emblem] Character name               [⚙] [×] │  ← one settings control
│  Journal   Character   Story                  │  ← three sections, nothing more
├───────────────────────────────────────────────┤
│                                               │
│   Reading/writing area (most of the window)   │
│                                               │
├───────────────────────────────────────────────┤
│ short status or prompt line                   │
└───────────────────────────────────────────────┘
```

| Section | Holds | Arrives with |
|---|---|---|
| Journal | Recorded milestones and the player's own notes, newest first | v0.2 (journal milestone) |
| Character | Profile fields, family and history, each with its visibility shown | v0.2, replacing the slash-only editing |
| Story | Pending and past story decisions | v0.3 (decision popups) |
| Settings (compact) | Theme choice, Total RP 3 status and sync options, backup/export/import, simulation mode | v0.2, with each item added only when its feature exists |

Slash commands stay as a quick, keyboard-friendly route. The window never offers fewer safety steps than the commands, such as `confirm` for deletions.

## Themes

A theme is **data**, not code:

```lua
-- illustrative only
{
	id = "neutral",
	name = "Neutral",
	accent = { 0.80, 0.68, 0.36 },        -- headings, selected section, focus
	background = "Interface\\AddOns\\DawnwardChronicles\\Media\\Themes\\Neutral\\Background",
	border = "Interface\\AddOns\\DawnwardChronicles\\Media\\Themes\\Neutral\\Border",
	emblem = nil,                         -- optional packaged emblem
	text = { 0.92, 0.90, 0.85 },          -- body text colour on this background
}
```

- **Built-in set:** start with three or four. **Neutral** is the default and is always available. The others are general moods (for example, parchment, night or steel), not class or race themes. The final list is decided when the art is ready.
- **Per character:** the saved data stores a theme ID plus optional overrides (accent colour, emblem on or off). This is a schema change, so it comes with a migration and L1 tests.
- **Player control:** a new character always gets Neutral. Nothing is chosen from class or race.
- **Later: suggestions.** A rule-based, local hint may consider class, race and *approved, public or private* backstory facts, never secret ones. It is shown as a suggestion the player can ignore. This is not part of v0.2.
- **Assets:** only original art or art with a compatible licence, recorded in `THIRD_PARTY_NOTICES.md`. Textures are small and few, to keep the addon light.

## Readability and scale (testable rules)

The copy-window fix in v0.1 set the pattern:

- **Layering:** a layer above other addons' dialogs, the window comes to the front when opened, and it is fully opaque behind text.
- **One layout table:** every region is computed from a single table. Tests check that regions don't overlap and that every region stays inside the background.
- **Contrast:** each theme's text colour must reach at least a **4.5:1** contrast ratio against its background. This is an automated L1 check per theme.
- **Size:** a minimum and maximum window size, kept on screen, resizable within bounds, with the size remembered per account.
- **Scale:** the L3 checklist includes at least two UI scale settings and one small resolution.
- **Motion:** no looping animations. Any transition is short, and turning it off loses nothing.

## Non-goals
- No statistics dashboard, graphs or achievement-style counters.
- No per-class layouts, and no hidden "identity" inferred from class or race.
- No downloaded, AI-generated or procedurally generated art.
- No features in the window that exist only because there is room for them.

## Open questions (to settle when v0.2 is planned)
- Which three or four built-in themes, and who makes the art?
- Should the journal be one long page or paged like a book? Start with one page and decide after testing.
- Should the settings area be a panel inside the window or a small separate one? Keep whichever is simpler.
