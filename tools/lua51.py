"""Run a Lua script on real PUC Lua 5.1, embedded through lupa.

Used on machines without a native `lua5.1` (typically Windows without a C
toolchain). Behaves like `lua5.1 script.lua args...`: sets the global `arg`,
mirrors `print` to stdout, and maps `os.exit(code)` to this process's exit code.

Usage: python tools/lua51.py tests/run.lua tests/spec/x_spec.lua ...
"""

import sys

EXIT_SENTINEL = "__dawnward_os_exit__"


def main(argv):
    if len(argv) < 2:
        print("usage: lua51.py SCRIPT [ARGS...]", file=sys.stderr)
        return 2

    try:
        from lupa import lua51
    except ImportError:
        print("lupa is not installed (pip install 'lupa>=2.0')", file=sys.stderr)
        return 2

    script, args = argv[1], argv[2:]
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()

    arg_table = lua.table_from({i: a for i, a in enumerate([script] + args)})
    g.arg = arg_table

    exit_state = {"code": 0}

    def lua_print(*values):
        print("\t".join("nil" if v is None else str(v) for v in values), flush=True)

    def lua_exit(code=0):
        if code is True or code is None:
            code = 0
        elif code is False:
            code = 1
        exit_state["code"] = int(code)
        raise SystemExit(EXIT_SENTINEL)

    g.print = lua_print
    g.os.exit = lua_exit

    try:
        g.dofile(script)
    except SystemExit as e:
        if str(e) != EXIT_SENTINEL:
            raise
    except Exception as e:  # LuaError and friends
        message = str(e)
        if EXIT_SENTINEL in message:
            return exit_state["code"]
        print(f"lua error: {message}", file=sys.stderr)
        return 1
    return exit_state["code"]


if __name__ == "__main__":
    sys.exit(main(sys.argv))
