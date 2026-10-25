"""Run every local check: repository hygiene, luacheck (L0), Lua 5.1 tests (L1/L2).

Usage: python tools/check.py

Prefers native `lua5.1` and `luacheck` on PATH (as in CI); otherwise falls
back to .tooling/ (lupa venv and luacheck.exe). A missing tool is a failure,
never a silent skip.
"""

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOOLING = ROOT / ".tooling"

# Paths that must never be tracked or staged (case-insensitive, matched per path segment or suffix).
FORBIDDEN_PATH_PATTERNS = [
    (re.compile(r"(^|/)totalrp3[^/]*(/|$)", re.I), "Total RP 3 addon files"),
    (re.compile(r"(^|/)raiderio[^/]*(/|$)", re.I), "third-party addon files"),
    (re.compile(r"\.zip$", re.I), "zip archive (third-party addons or build output)"),
    (re.compile(r"(^|/)(wtf|savedvariables)(/|$)", re.I), "WoW client SavedVariables/WTF data"),
    (re.compile(r"(^|/)(private|review|\.tooling)(/|$)", re.I), "local-only directory"),
    (re.compile(r"(^|/)\.env(\.|$)", re.I), "environment/secrets file"),
    (re.compile(r"\.(pem|key|token)$", re.I), "key or token file"),
]

# File contents that indicate copied third-party source or leaked secrets.
FORBIDDEN_CONTENT_PATTERNS = [
    # Built from parts so this file does not match its own pattern.
    (re.compile("Copyright The " + "Total RP 3 Authors"), "Total RP 3 source header"),
    (re.compile(r"\b(ghp|gho|ghu|ghs)_[A-Za-z0-9]{30,}"), "GitHub token"),
    (re.compile(r"github_pat_[A-Za-z0-9_]{30,}"), "GitHub fine-grained token"),
    (re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"), "private key"),
    (re.compile(r"\bsk-[A-Za-z0-9]{20,}"), "API key"),
]

EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
ALLOWED_EMAIL_SUFFIXES = ("@users.noreply.github.com", "@anthropic.com", "@example.com")

# Optional, never committed: one term per line (e.g. private NPC or family names).
PRIVATE_DENYLIST = ROOT / "private" / "hygiene-denylist.txt"

TEXT_SUFFIXES = {".lua", ".toc", ".xml", ".md", ".txt", ".yml", ".yaml", ".json", ".py", ".ps1", ".sh", ""}


def git_files():
    """Tracked files plus untracked files that are not ignored (i.e. would be committed by `git add -A`)."""
    out = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=ROOT, capture_output=True, check=True,
    ).stdout.decode("utf-8")
    return sorted({p for p in out.split("\0") if p and (ROOT / p).is_file()})


def check_hygiene():
    problems = []
    denylist = []
    if PRIVATE_DENYLIST.is_file():
        denylist = [ln.strip() for ln in PRIVATE_DENYLIST.read_text(encoding="utf-8").splitlines()
                    if ln.strip() and not ln.startswith("#")]

    files = git_files()
    for rel in files:
        for pattern, why in FORBIDDEN_PATH_PATTERNS:
            if pattern.search(rel):
                problems.append(f"{rel}: {why}")

        path = ROOT / rel
        if path.suffix.lower() not in TEXT_SUFFIXES and not rel.startswith("."):
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        for pattern, why in FORBIDDEN_CONTENT_PATTERNS:
            if pattern.search(text):
                problems.append(f"{rel}: contains {why}")
        for email in set(EMAIL.findall(text)):
            if not email.lower().endswith(ALLOWED_EMAIL_SUFFIXES):
                problems.append(f"{rel}: contains a personal-looking email address")
        lowered = text.lower()
        for term in denylist:
            if term.lower() in lowered:
                problems.append(f"{rel}: contains a term from private/hygiene-denylist.txt")

    for p in problems:
        print(f"  FAIL {p}")
    note = f" (+{len(denylist)} private denylist terms)" if denylist else ""
    print(f"  scanned {len(files)} files{note}")
    return not problems


def find_luacheck():
    native = shutil.which("luacheck")
    if native:
        return [native]
    local = TOOLING / "bin" / ("luacheck.exe" if os.name == "nt" else "luacheck")
    if local.is_file():
        return [str(local)]
    return None


def find_lua51():
    native = shutil.which("lua5.1")
    if native:
        return [native]
    venv_python = TOOLING / "venv" / ("Scripts/python.exe" if os.name == "nt" else "bin/python")
    if venv_python.is_file():
        return [str(venv_python), str(ROOT / "tools" / "lua51.py")]
    return None


def run(cmd):
    return subprocess.run(cmd, cwd=ROOT).returncode == 0


def main():
    # Keep our headings in order with the subprocesses' output.
    sys.stdout.reconfigure(line_buffering=True)
    results = []

    print("== Hygiene")
    results.append(("hygiene", check_hygiene()))

    print("\n== L0 luacheck")
    luacheck = find_luacheck()
    if not luacheck:
        print("  FAIL luacheck not found (install it, or place luacheck.exe in .tooling/bin/)")
        results.append(("luacheck", False))
    else:
        results.append(("luacheck", run(luacheck + ["."])))

    print("\n== L1/L2 tests (Lua 5.1)")
    lua = find_lua51()
    specs = sorted(str(p.relative_to(ROOT)).replace("\\", "/") for p in (ROOT / "tests").rglob("*_spec.lua"))
    if not lua:
        print("  FAIL no Lua 5.1 runtime (install lua5.1, or create .tooling/venv with lupa)")
        results.append(("tests", False))
    elif not specs:
        print("  FAIL no *_spec.lua files found")
        results.append(("tests", False))
    else:
        results.append(("tests", run(lua + ["tests/run.lua"] + specs)))

    print("\n== Summary")
    for name, ok in results:
        print(f"  {'ok  ' if ok else 'FAIL'} {name}")
    return 0 if all(ok for _, ok in results) else 1


if __name__ == "__main__":
    sys.exit(main())
