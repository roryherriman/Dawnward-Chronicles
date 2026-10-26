# First-time setup wizard

## Shape
- **Not a tab and not a separate window.** The wizard is an overlay inside the existing journal window, like the settings panel, using the same layout table, theme and opaque background.
- **It never interrupts play.** It appears only when the player opens the journal for a character with no foundation, wizard not dismissed. Nothing pops up at login.
- **Card one** ("Begin your chronicle") offers three equal choices and **Not now**:
  1. **I already have a story**, listed first and marked "recommended" only when a compatible TRP3 profile is detected;
  2. **Help me develop my character**;
  3. **Discover my story as I play**.
- **Controls** on every step: a progress line ("Step 2 of 5"), **Back**, **Continue**, **Skip this step** and **Finish now**. Escape closes the wizard and saves progress.
- **Progress is saved per character** (`wizard = { path, step, answers, updatedAt, dismissed }`) after every step.
- **Coming back:** the Character section has a single **Revisit setup** link; choosing another path never deletes earlier answers or canon.
- **Simulation mode** runs the wizard against simulation data, so the whole flow can be rehearsed safely.

## Path A: I already have a story

| Step | Content | Notes |
|---|---|---|
| A1 Source | **Link TRP3 profile**: shows the active profile name with Confirm, or switch to **Paste or write a biography** | Refuses the TRP3 default profile (its ID changes every login). Confirmed once per character (approved decision 10). |
| A2 Identity | Shows the imported identity fields (name, title, race, class, pronouns, age, residence, birthplace…), each with a visibility choice | Values are copied into Dawnward and never written back. TRP3 fields come from public getters and `GetCharacteristics()`. **S** |
| A3 Biography | The stored biography shown sentence by sentence (TRP3 text tags hidden for display; the stored text stays verbatim). Click a sentence and choose **Make this a fact** with a category. | The About text is read through the 3.4.1-only adapter (approved). On other versions this step becomes paste-only. |
| A4 Review | Suggestions from structured fields (for example "Lives in Stormwind", or a trait "leans lawful" from TRP3 personality sliders), with Approve, Edit, Reject or Skip | Suggestions only; nothing becomes canon automatically |
| A5 Publication | Which categories may be public (see the publication policy), and whether Dawnward may manage TRP3's Currently text and titles | Defaults: everything **private**, nothing managed |
| Finish | A summary of the canon so far, plus what happens next | — |

## Path B: Help me develop my character

The steps are short and conversational. Each has 1–3 questions, each question offers optional quick choices *and* a free text box, and every question can be skipped. **Skip the rest** jumps straight to the draft.

| Step | Example questions (illustrative) | Produces |
|---|---|---|
| B1 Name and identity | "What do people call you?", "Pronouns, if you'd like prompts to use them" | Identity fields |
| B2 Origins | "Where did you grow up?" "What was home like?" | `origin` and `place` facts |
| B3 People | "Who mattered most growing up?" (relation + name + how things stand now) | Family entries and `relationship` facts |
| B4 A defining moment | "What's one moment you still think about?" | An `event` fact and a history entry |
| B5 Temperament | Small situations, for example "A plan goes wrong mid-fight. You…": rethink carefully / push on harder / look to your companions / laugh it off | **Starting leanings** for 2–3 tendencies, shown back as words for confirmation |
| B6 Beliefs and values | "What would you never do?" "What do you owe others?" (duty, loyalty, faith, freedom…) | `belief` facts |
| B7 Fears and weaknesses | "What do you avoid thinking about?" | `fear` facts (default **secret**) |
| B8 Motivations | "What are you working toward right now?" | `motivation` facts, plus an optional goal |
| B9 Draft | **An editable biography draft assembled only from the answers**, with sections for the parts answered | The draft is shown with an **Edit** button; the edited text becomes the player's own |
| B10 Publication | As in A5 | — |

**No invented facts.** The draft composer may only use the player's answers plus fixed connecting phrases from `Content/Narrative`. An L1 test checks that every non-template word in the draft comes from an answer.

## Path C: Discover my story as I play

| Step | Content |
|---|---|
| C1 | "Your story will take shape through play." Optional name and pronouns, used in prompts. |
| C2 | Story-moment frequency (Off / Rare / **Normal** / Frequent) and publication defaults (everything private) |
| Finish | Back to the journal. The first story moment appears after a meaningful event, at a safe time. |

## Tone guidelines for questions
- Write in second person, warmly, in-world where possible ("Tell me about home…"). Never form-like ("Enter place of birth").
- Never assume class, race or gender. Quick choices are always optional, and "something else" is always possible.
- Fears and secrets default to **secret**; everything else defaults to **private**.
