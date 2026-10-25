## Summary

<!-- What does this change do, and why? -->

## Test level reached

<!-- Tick everything that actually ran. See docs/TESTING.md. -->
- [ ] L0 static: `python tools/check.py` passes
- [ ] L1 unit tests added or updated
- [ ] L2 mocked integration tests added or updated
- [ ] L3 checked in game on Classic Era (build: `____`, Total RP 3: `____`)
- [ ] L4 checked in game on WoW Forever (build: `____`, Total RP 3: `____`)

## Safety checklist

- [ ] No third-party addon source, SavedVariables, secrets or private character data are included
- [ ] No personality change can happen without player approval
- [ ] No journal entry can be created without an observed game event (or simulation mode)
- [ ] Only `public` facts can reach Total RP 3 or a shareable export
- [ ] No Total RP 3 write outside Dawnward-owned content, and no writes to files on disk
- [ ] `CHANGELOG.md` updated under **Unreleased** (if user-visible)
