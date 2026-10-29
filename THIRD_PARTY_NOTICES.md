# Third-party notices

The MIT licence in [`LICENSE`](LICENSE) covers only the original code and documentation in this repository.

## Bundled third-party code

**No third-party code.** Dawnward Chronicles ships no third-party libraries. If one is added, it will be listed here with its licence, and its licence file will be shipped next to it.

## Bundled fonts (from v0.7-dev)

These fonts ship in `DawnwardChronicles/Media/Fonts/`, with their licence files beside them (`OFL-Cinzel.txt`, `OFL-AlegreyaSans.txt`; summary in `FONTS.txt`). The MIT licence does not apply to them.

| Font | Files | Licence | Notes |
|---|---|---|---|
| [Cinzel](https://github.com/NDISCOVER/Cinzel) | `Cinzel-SemiBold.ttf` | SIL Open Font License 1.1 | A static weight-600 instance made from the variable font with fontTools. The name is unchanged because Cinzel declares no Reserved Font Name. Used for display text: titles, names and eyebrows |
| [Alegreya Sans](https://github.com/huertatipografica/Alegreya-Sans) | `AlegreyaSans-Regular.ttf`, `AlegreyaSans-Bold.ttf` | SIL Open Font License 1.1 | Unmodified. Used for reading text and labels |

On clients whose language the fonts do not cover, or when a file fails to load, the addon uses the game's own fonts instead.

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
