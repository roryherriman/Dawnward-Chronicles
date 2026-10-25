# Third-party notices

The MIT licence in [`LICENSE`](LICENSE) covers only the original code and documentation in this repository.

## Bundled third-party code

**None.** Dawnward Chronicles currently ships no third-party libraries. If one is added, it will be listed here with its licence, and its licence file will be shipped next to it.

## Software we interoperate with, but do not include

| Project | Licence | Relationship |
|---|---|---|
| [Total RP 3](https://github.com/Total-RP/Total-RP-3) | Apache-2.0 | An optional, separately installed addon. Dawnward reads its public in-game API and, where enabled, calls its public setters. None of Total RP 3's source code, assets or data is copied into this repository or its releases. Field names and behaviour are described in `docs/TRP3_INTEGRATION.md` only to explain how the two addons work together. |

## Development tools (not distributed)

These are used only on a developer's machine or in CI. They are not part of any release.

| Tool | Licence | Use |
|---|---|---|
| [Lua 5.1](https://www.lua.org/) | MIT | Runs the tests on the same language version as World of Warcraft |
| [lupa](https://github.com/scoder/lupa) | MIT | Provides a Lua 5.1 runtime for the tests on Windows machines without a C toolchain |
| [luacheck](https://github.com/lunarmodules/luacheck) | MIT | Static analysis |

## Trademarks

World of Warcraft and Warcraft are trademarks or registered trademarks of Blizzard Entertainment, Inc. Dawnward Chronicles is a fan-made project. It is not affiliated with or endorsed by Blizzard Entertainment, the Total RP 3 authors, or the operators of any game server.
