# Contributing to Dawnward Chronicles

Thanks for your interest. This is a small project with strict rules about player safety and honest testing. Please read this guide before opening a pull request.

## Ground rules

1. **Never commit another addon's source code.** That includes Total RP 3, libraries copied out of other addons, and zipped `AddOns` folders. The hygiene check fails the build if it finds any.
2. **Never commit private data.** This covers SavedVariables, `WTF/` folders, character backstories you haven't chosen to publish, tokens and credentials. Keep personal test data in `private/`, which git ignores.
3. **Never write to another addon's files**, and never write to the client's files on disk.
4. **The player approves personality changes.** No code path may change traits without an approval record.
5. **Don't fabricate events.** Journal entries come only from observed game events, or from simulation mode, which keeps its data separate.
6. **State the test level in every claim.** Use L0–L4 from [`docs/TESTING.md`](docs/TESTING.md). Don't describe something as "works in game" unless it reached L3 or L4.

## Setup

You need **Python 3.9+** and git. Lua and luacheck don't have to be installed system-wide.

```bash
python -m venv .tooling/venv
```

```bash
.tooling/venv/Scripts/python -m pip install "lupa>=2.0"
```

On macOS or Linux, use `.tooling/venv/bin/python` instead.

For luacheck, either install it with LuaRocks (`luarocks install luacheck`) or put the official `luacheck.exe` from the [luacheck releases](https://github.com/lunarmodules/luacheck/releases) in `.tooling/bin/`.

If `lua5.1` (or `luajit`) and `luacheck` are already on your `PATH`, the tools use those instead.

## Running checks

```bash
python tools/check.py
```

This runs three steps:

1. **Hygiene:** looks for forbidden files among those git tracks.
2. **L0:** luacheck with the Lua 5.1 standard.
3. **L1 and L2:** the test suite on real Lua 5.1.

The tests refuse to run on any other Lua version.

## Workflow

See [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md). In short:

- Branch from `main` as `feat/<topic>`, `fix/<topic>` or `docs/<topic>`.
- Keep commits small, one logical change each, with an imperative subject line.
- Open a PR using the template. CI must pass.
- Add a `CHANGELOG.md` entry under **Unreleased** for any user-visible change.

## Code style

- Lua 5.1 only: no `goto`, no integer division, no `utf8` library.
- Indent with tabs. Prefer `local` everywhere. Add globals only through the addon namespace.
- `Core/` must not touch WoW globals. Client APIs go in `Platform/`, and Total RP 3 access goes in `Integrations/TRP3/`.
- Comments explain *why*, not *what*.

## Reporting bugs and compatibility results

Use the issue templates. Compatibility reports are very welcome, and the most useful ones include:

- the client and version (`/dump GetBuildInfo()`);
- the Total RP 3 version;
- the exact steps you took.

Remove character names you don't want made public before posting.
