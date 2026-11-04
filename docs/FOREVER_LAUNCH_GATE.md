# WoW Forever launch gate (issue #24): automated and adversarial evidence

This is the acceptance matrix for issue #24 ("WoW Forever + bundled TRP3 exhaustive compatibility, fuzz, and launch readiness gate") as far as it can be met without the game. It records what was tested, against which client and Total RP 3 build, the result, the evidence, the limits, and what is still owed. It never claims a runtime pass: nothing here was run in a WoW Forever client.

## Targets and evidence labels

| Target | What was used | Status |
|---|---|---|
| WoW Forever client | Blizzard UI source, `Gethe/wow-ui-source` branch `forever`, commit 17ed2c3 "1.60.1 (70755)" (2026-11-03): project 18 (`WOW_PROJECT_CAMELOT`), a Mainline-based client. Interface 16001 is derived from the version string and corroborated by Total RP 3 3.5.4's TOC. | Static; Interface 16001 **not runtime-confirmed** (`/dump select(4, GetBuildInfo())` in game) |
| Total RP 3 on Forever | Upstream Total RP 3 **3.5.4** (tag 3.5.4, commit 2c921b0, 2026-11-02), whose TOC declares `## Interface: 120105, 16001` (Mainline and Forever only). The build installed on players' Forever clients is unknown. | Provisional (substitute: upstream 3.5.4) |
| Classic Era | Classic Era 1.15.9 (70576) source; Total RP 3 3.4.1 | Unchanged behaviour; all Classic tests green |

Labels used below:

- **L2 mocked**: automated, through the whole addon loaded from its TOC in the WoW mock (`tests/support/wow_mock.lua`; `client = "forever"` exposes only the APIs and events the forever branch documents, rejects anything else, and simulates secret values) with the Total RP 3 fakes (`tests/fakes/trp3_354.lua`, `tests/fakes/trp3_341.lua`). Mocked, not in-game.
- **Static**: source evidence (forever branch UI source, Total RP 3 source), with file and line.
- **Pending Live Forever Verification**: needs the WoW Forever client.
- **Pending two-client**: needs two WoW Forever clients (another player's view).

Every L2 result on the Forever track is also Pending Live Forever Verification, and every Total RP 3 3.5.4 result is provisional until the build Forever players run is known.

## Reproduction

From the repository root, with `lua5.1` on `PATH` (the suite refuses any other Lua):

```
python tools/check.py
```

runs hygiene, the TOC check, luacheck, every spec, the atlas tools and the packaging check (allow several minutes). A single spec:

```
lua5.1 tests/run.lua tests/spec/forever_trp3_e2e_spec.lua
lua5.1 tests/run.lua tests/spec/forever_adversarial_spec.lua
```

Several at once: `lua5.1 tests/run.lua tests/spec/a_spec.lua tests/spec/b_spec.lua`. Fuzz inputs come from `tests/support/fuzz.lua`, a seeded Park-Miller generator (exact in Lua 5.1 doubles, so the same seed gives the same input everywhere); a failing assertion names its seed. Private fixture tests (`private/`) are absent in a clean checkout; that is expected.

**Counts (this gate's run):** `python tools/check.py`: all stages ok, **1451 passed, 0 failed** (before this gate: 1414; +37). New: `forever_trp3_e2e_spec.lua` 15 tests, `forever_adversarial_spec.lua` 22 tests (each fuzz test loops over its seeds: 40 biographies, 60 corrupted databases, 7 malformed databases, every schema version, 20 corrupted ledgers, 30 malformed Total RP 3 profiles, 10 invalid icon identifiers, all 32 At First Glance slot patterns).

## Acceptance matrix

| #24 criterion | Test performed | Client / TRP3 | Result | Evidence | Limitation | Follow-up |
|---|---|---|---|---|---|---|
| Establish the real target (client, interface, TRP3 build) | Source audit; version profile `3.5.4` (`Integrations/TRP3/VersionProfiles.lua`) | Forever 1.60.1 / TRP3 3.5.4 | Partial | Static (see Targets) | Exact TRP3 build on Forever unknown; Interface not runtime-confirmed | Pending Live Forever Verification: `/dump select(4, GetBuildInfo())` and the TRP3 version in game |
| Static API audit (TOC, APIs, events, namespaces) | `forever_client_spec.lua`: every global the mock offers must be documented; unknown events raise; Classic-only globals removed | Forever mock | Pass | L2 mocked; Static (`docs/COMPATIBILITY.md`) | Mock built from generated docs, not the running engine | Pending Live Forever Verification |
| TRP3 public/internal API audit (About guards, characteristics, profile IDs, ownership, versions) | `trp3_354_spec.lua`; `forever_trp3_e2e_spec.lua` | TRP3 3.5.4 fake | Pass | L2 mocked; Static (`docs/TRP3_INTEGRATION.md`, "Total RP 3 3.5.x") | Fake, provisional substitute | Pending Live Forever Verification |
| Fail safely on absent, unexpected or malformed values | `forever_client_spec.lua` "degraded Forever clients"; adversarial "odd quest metadata", "secret values" | Forever mock | Pass (after fixes F1-F4) | L2 mocked | Secret behaviour simulated (`mock.Secret`, `issecretvalue`, `type`) | Pending Live Forever Verification |
| Existing hygiene, lint, tests, migrations | `python tools/check.py` | both | Pass | L2 mocked; counts above | — | Rerun after every change |
| First-login setup to a synced disposable profile | e2e "setup on TRP3's default profile creates a disposable profile…" | Forever / 3.5.4 | Pass | L2 mocked | — | Pending Live Forever Verification |
| Story import | e2e "imports a story…"; adversarial 40 seeded biographies, oversized input | Forever / 3.5.4 | Pass | L2 mocked | — | — |
| Fuzz biographies, markup (`\|c`, `\|T`, `\|H`, `\|r`, `{icon}`, `{col}`, `{h1}`), unicode, multiline, oversized | adversarial "40 seeded biographies…", "oversized input…" | Forever / 3.5.4 | Pass: imported, synced, read back, no churn | L2 mocked | Rendering of the markup in TRP3's About frame not checked (no client) | Pending Live Forever Verification (TRP3 render paths) |
| Truncated / corrupted / partial SavedVariables, partial migrations | adversarial "60 seeds of random deletion…", "not a table…", "any schema version…", "a corrupted Total RP 3 ledger…" (realistic database from `tests/fixtures/kyssarra_level6.lua` plus a second character) | Forever | Pass: no error; read-only data left exactly as saved; the other character identical to a control run; every approved memory not itself mutated kept | L2 mocked | Random mutations, not every possible corruption | — |
| Repeated /reload and relog | e2e "/reload and relog keep the connection…" (three cycles); `forever_client_spec.lua` "keeps everything through a /reload" | Forever / 3.5.4 | Pass: nothing rewritten, no update event | L2 mocked | — | Pending Live Forever Verification |
| Interrupted writes, failed write recovery | `trp3_354_spec.lua` "a write that does not read back is restored from the backup and switched off" | 3.5.4 fake | Pass | L2 mocked | — | — |
| Duplicate event bursts, repeated zone changes, event storms | adversarial "duplicate bursts and 1000 zone changes"; e2e "repeated syncs and event bursts write once" | Forever | Pass: one record each, bounded storage, no version churn | L2 mocked | Timing and memory of a real session not measured | Pending Live Forever Verification |
| Interrupted notification scheduling | adversarial "a story notice survives a lost timer, a reload mid-queue and a missing C_Timer, and shows once" | Forever | Pass | L2 mocked | — | — |
| Multiple characters and realms; wrong-character ownership; identity collisions | adversarial "same name on two realms…", "unreadable … name or realm" (F1), "two characters on one account…", Classic identity rules | Forever + Classic | Pass (after F1) | L2 mocked | Separate accounts are separate SavedVariables folders (by construction) | Pending Live Forever Verification |
| Missing TRP3; TRP3 disabled or loaded late; unknown build | e2e "missing or disabled…", "loaded late…", "an unknown 3.5.x build…" | Forever / 3.5.4, 3.5.3, 3.5.5, 3.6.0, placeholder | Pass: unknown builds read-only, explained | L2 mocked | — | — |
| Classic client with TRP3 3.5.4 | e2e "Classic Era client with 3.5.4 installed…" | Classic mock / 3.5.4 fake | Pass: 3.5.4's TOC declares no Classic interface, so the client normally refuses it ("loaded: false" = absent); a forced load gets the same audited, guarded path (Dawnward decides by TRP3's version, not the client) | L2 mocked; Static (3.5.4 TOC) | — | — |
| Profile switch mid-edit / mid-run; shared/default profile | e2e "a profile switch in the middle of a run stops every later write"; `trp3_354_spec.lua` (default profile, open editor) | Forever / 3.5.4 | Pass | L2 mocked | — | Pending Live Forever Verification |
| Concurrent manual About edits; version conflicts; no silent overwrites | e2e "a manual About edit in TRP3 is a conflict…", "a manual field edit pauses only that field…"; adversarial "30 seeds of malformed profile sections… every changed section was backed up first" | Forever / 3.5.4 | Pass | L2 mocked | — | — |
| Repeated sync and rollback loops; backups | e2e rollback (own text and exact), repeated runs; `trp3_354_spec.lua` "rollback … can itself be undone" | Forever / 3.5.4 | Pass | L2 mocked | Backup exhaustion covered by earlier ledger specs (`trp3_ledger_spec.lua`) | — |
| Privacy boundaries (unapproved, drafts, private, secret, simulation) | adversarial "unapproved, draft and private records of a real level-6 save never reach Total RP 3", "simulation mode never touches the real database or Total RP 3"; e2e journal note | Forever / 3.5.4 | Pass | L2 mocked | v0.10 publishes the whole profile, the biography included, by design (`docs/PRIVACY.md`) | — |
| Combat restrictions | e2e "in combat nothing is written…"; adversarial "combat toggling during runs: Total RP 3 is never written while in combat" (60 seeded toggles) | Forever / 3.5.4 | Pass | L2 mocked | Combat lockdown semantics of Forever not observed | Pending Live Forever Verification |
| Malformed TRP3 profile data; invalid traits and icon identifiers; At First Glance slot collisions | adversarial "30 seeds of malformed profile sections", "invalid custom traits and icon identifiers", "every pattern of occupied slots" | 3.5.4 fake | Pass: the player's traits and slots never touched; Dawnward writes plain icon names | L2 mocked | — | — |
| Profile icon on 3.5.4 | e2e "the Total RP 3 page" (F5) | Forever / 3.5.4, Classic / 3.4.1 | Pass | L2 mocked | — | Pending Live Forever Verification |
| TRP3 formatting on target render paths; plain-text fallback | Not testable without the client | — | Not done | — | — | Pending Live Forever Verification |
| Memory, performance, low-end configurations | `performance_spec.lua` (existing); event storm above | mock | Partial | L2 mocked | Real memory and frame time unmeasured | Pending Live Forever Verification |
| Two-client: other players see only approved public content, MSP, cache refresh | Fake's `remoteRefetch` / `miscExchange` checks in `trp3_354_spec.lua` | fake | Partial | L2 mocked | No second client | Pending two-client |
| Mandatory in-game smoke on a disposable character | — | — | Not done | — | Cannot be simulated | Pending Live Forever Verification |
| GO / NO-GO | — | — | Automated: no open BLOCKER/HIGH from this gate; target-client, multiplayer: unverified | — | — | Owner's decision after the in-game gate |

## Failures found by this gate, and fixes

| # | Severity | Reproducer | Root cause | Fix | Regression test |
|---|---|---|---|---|---|
| F1 | HIGH | Log in on Forever with `UnitName("player")` secret, nil, empty or failing (or no readable realm): the character key became `Unknown-<realm>`, so journal events, setup and the Total RP 3 opt-in were written under a key any other unidentified character shares (cross-character writes, and a sync of one character's profile into another's TRP3 profile). | `Platform/Bootstrap.lua` `characterKey()` fell back to "Unknown". | The key still reads "Unknown-…", but the session is locked: the store is rebuilt on detached, read-only copies (real and simulation), the TRP3 ledger likewise and sync paused, and the player is told to log in again. SavedVariables and Total RP 3 stay exactly as they were. | adversarial "unreadable (secret or missing) name or realm…" (six cases, incl. a pre-existing `Unknown-…` record and opt-in) |
| F2 | HIGH | Forever: `UnitIsAFK` is `SecretInChatMessagingLockdown` (Blizzard_APIDocumentationGenerated/UnitDocumentation.lua). `SafeTime.Reasons` and `PlayClock` tested its result directly; a boolean test of a secret can raise an error from a timer (no pcall) or at login. | Direct `if call(UnitIsAFK, "player")`. | `Compat.IsAway()`: a secret result is never tested and counts as away (cards and the narrative clock wait); a missing or failing function counts as not away, as before. Classic unchanged. | adversarial "a secret UnitIsAFK is never tested directly…" (the mock now counts secrets used without `issecretvalue`), "a plain UnitIsAFK still decides as before" |
| F3 | MEDIUM | Forever: secret `UnitRace`/`UnitClass`/`UnitName` values; opening the journal raised "attempt to convert a secret value to a string" in `Showcase.IdentityLine`, and `Character.GameValue` returned the secret. | `UI/Showcase.lua` `call()`, `Core/Character.lua` `GameValue`, `UI/SetupWizard.lua` (two `UnitName` reads, one unprotected) and `UI/MainWindow.lua` used client values without `Compat.Plain`. | Read through `Compat.Plain` (a secret reads as nothing). The mock's `type()` now reports a secret's hidden type, as the client does, so these paths are exercised. | adversarial "secret race, class and name values are not shown as the game's values" |
| F4 | LOW | `IsInInstance` results compared directly in `SafeTime.Reasons`. | Same pattern as F2. | `Compat.Plain` on both results. | covered by the F2 tests |
| F5 | LOW | Settings > Total RP 3 > Profile on 3.5.4: the profile icon row offered "Dawnward" and read as managed although the version profile keeps it read-only (`readOnlyRows.icon`). | `UI/TRP3Page.lua` did not read `readOnlyRows`. | `TRP3Page.ReadOnlyReason`; the row says "Read-only on this Total RP 3 version" with the reason in its tooltip, "Dawnward" is disabled and cannot be staged, and the icon editor's tooltip says so. 3.4.1 unchanged. | e2e "shows the profile icon row as read-only on 3.5.4…", "on 3.4.1 … managed as before" |
| F6 | LOW | `/dawnward trp3 help` said "Total RP 3 3.4.1 only". | Stale text after 3.5.4 was audited. | Now "audited Total RP 3 versions only: see trp3 diagnose". | — |

Checked and **not** defects (by design, recorded so they are not re-reported): the imported story publishes as the About biography word for word, the player's own TRP3 tags included (`docs/PRIVACY.md`, `docs/TRP3_INTEGRATION.md` "Biography"); other sections escape braces, so profile text never becomes TRP3 markup. Dawnward's one-field Name is never split into TRP3's first and last name (3.5.4's given-name default stays). A roleplay status the player already set in TRP3 is paused, not overwritten. The default rollback keeps Dawnward's part current; `rollback # exact` restores the section exactly. Raw `|` sequences in text are passed through: in game, edit boxes escape a typed or pasted `|` as `||`.

## Remaining risks

- Everything above is mocked. The Forever client, its secret-value rules and combat lockdown, and the TRP3 build players run are unverified; any of them can differ from the substitutes.
- An unidentified character (F1) stays read-only until the next login; the key is not re-resolved mid-session (a later `PLAYER_ENTERING_WORLD` retry was judged unsafe: event baselines and observers are already bound to the session).
- The mock cannot raise an error on a boolean test of a secret; such uses are caught only where a test counts unchecked secrets.
- Two-client behaviour (MSP, cache refresh, what other players see) is untested.
