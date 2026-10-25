# DRAFT: proposed Total RP 3 public API enhancement

> **Status: draft only. Not submitted.** Drafting was approved on 2026-10-25; submitting it, or contacting the Total RP 3 maintainers in any way, needs separate explicit approval. Before submission it should be re-checked against TRP3's latest `main` and contribution guidelines, and the wording adapted to their issue template.

---

**Proposed title:** Public API for other addons to manage a profile section and personality traits

### Summary
Hello, and thank you for Total RP 3 and its public `AddOn_TotalRP3` API.

We maintain a small open-source addon (Dawnward Chronicles, MIT) that helps players develop their character through play. It keeps a private journal and, with the player's consent, mirrors chosen developments into their TRP3 profile. Today we use only the public `CurrentUser` setters (for example `SetCurrentlyText` and `SetTitle`).

We'd like to keep a player's **About** text and **personality traits** in step as well, but there's no public way to do that. We don't want to write TRP3's internal tables, because that is unsupported, could break with any release, and could collide with TRP3's own editor. We'd like to ask whether a small supported API would be welcome, and we'd be glad to contribute a pull request in whatever shape you prefer.

### What we'd find useful (in order of preference)
1. **Addon-owned About sections:**
   - An addon registers a named section, and the player sees it as a separate block in their About page, clearly labelled with its source, and can hide or remove it.
   - TRP3 keeps full control of rendering, size limits, sanitising and exchange.
   - The player's own About text is never touched.
   - Sketch:
     - `AddOn_TotalRP3.ProfileSections.Register(owner, sectionID, { title = "…" })`
     - `AddOn_TotalRP3.ProfileSections.SetText(owner, sectionID, text)`, which returns ok or an error, and does nothing on the default profile, just as the existing setters do
     - `AddOn_TotalRP3.ProfileSections.Remove(owner, sectionID)`
2. **Personality traits:** `CurrentUser:GetPersonalityTraits()` (a copy) and `CurrentUser:SetPersonalityTraitValue(traitRef, value)`, limited to traits the player has *already* added, so addons can only adjust values and never add or remove traits.
3. **A supported read for About text:** for example `CurrentUser:GetAboutText()` or similar, to replace `GetInfo("about")`, which is marked for deprecation.
4. **Editor-in-progress signal:** `CurrentUser:IsEditingProfile()` or an event, so addons can wait instead of colliding with an open editor draft.

### Safety properties we'd follow and suggest
- Writes only to the player's active, non-default profile. The section stays out of other profiles.
- Text goes through TRP3's existing sanitising and size handling. TRP3 decides exchange behaviour (for example section versioning).
- Addons must not write while the editor is open (item 4).
- Everything is opt-in on our side; our addon never publishes private information.

### What we are *not* asking for
- No access to other players' profiles.
- No changes to TRP3's UI beyond showing the addon-owned section.
- No writes to TRP3 SavedVariables.

### Offer
We'd be happy to write the implementation and tests as a pull request, follow your code style, and keep the scope as small as you like, for example only item 3 and item 1 for template 1. If you'd rather this didn't exist, we completely understand, and will keep using the copy-and-paste approach.

---

*Internal notes, not part of the issue text:*
- Evidence: TRP3 3.4.1 and upstream `main` (3.5.3) expose setters only for the identity, title and status fields (`Core/Player.lua`). The About and trait sections are written only by TRP3's own editors. No existing issue discusses this (searched 2026-10-25).
- If accepted, Dawnward adds a capability-gated field writer per new API (see `trp3-sync.md` §4); nothing else in the sync design changes.
