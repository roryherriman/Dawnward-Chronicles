"""Build the release zips: one per game client, from the same source revision.

Usage:
  python tools/package.py                    # both packages
  python tools/package.py --target classic   # Classic Era only
  python tools/package.py --target forever   # WoW Forever only
  python tools/package.py --allow-dirty      # development builds from an uncommitted tree

Output (dist/ is git-ignored), each with a .sha256 file and a .manifest.json:
  dist/DawnwardChronicles-ClassicEra-<toc version>.zip
  dist/DawnwardChronicles-Forever-v1.0.0-Beta.zip

Both packages contain the same source files (tracked by git under
DawnwardChronicles/, so local or private files can never end up in a
release; tests, tools and docs never are). Only the TOC differs: each
package declares its client's interface number, its version and
`## X-Dawnward-Target`, which the addon reports (/dawnward status) and
checks against the client it is running on (Platform/Detect.lua).

Every zip is verified after it is written: one root folder, every TOC entry
present with the exact letter case, every Lua file compiles on Lua 5.1, no
test, tool, private or debug-only files, no local paths, and the interface
number is the one its target expects.
"""

import argparse
import hashlib
import io
import json
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ADDON = "DawnwardChronicles"

# Per-client packaging. Evidence for each interface number:
#   classic: WoW Classic Era 1.15.9 (70576), interface 11509 (verified in game, docs/COMPATIBILITY.md).
#   forever: WoW Forever 1.60.1 (70755): Blizzard UI source (Gethe/wow-ui-source, branch
#            "forever", commit 17ed2c3) and Total RP 3 3.5.4's TOC ("## Interface: 120105, 16001").
#            Static evidence only: confirm in game with /dump select(4, GetBuildInfo()).
TARGETS = {
    "classic": {
        "interface": 11509,
        "version": None,  # the TOC's own version (continues 0.10.x)
        "display": None,
        "zip": "DawnwardChronicles-ClassicEra-{version}.zip",
    },
    "forever": {
        "interface": 16001,
        "version": "1.0.0-beta",
        "display": "1.0.0 Beta",
        "title": "Dawnward Chronicles",
        "zip": "DawnwardChronicles-Forever-v1.0.0-Beta.zip",
    },
}

FORBIDDEN_PARTS = ("private/", "tests/", "tools/", "docs/", ".git", "__pycache__", ".tooling")
LOCAL_PATH = re.compile(r"[A-Za-z]:\\Users\\|/home/[a-z]|/Users/[A-Za-z]|roryh(?!erriman)", re.I)


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True, check=True).stdout


def tracked_files():
    out = subprocess.run(["git", "ls-files", "-z", "--", ADDON], cwd=ROOT, capture_output=True,
                         check=True).stdout.decode("utf-8").split("\0")
    return sorted(p for p in out if p)


def set_field(toc, field, value):
    """Replace a '## Field:' line, or add it after the last header line."""
    line = f"## {field}: {value}"
    pattern = re.compile(rf"^## {re.escape(field)}:.*$", re.M)
    if pattern.search(toc):
        return pattern.sub(lambda _: line, toc, count=1)
    headers = list(re.finditer(r"^##.*$", toc, re.M))
    at = headers[-1].end() if headers else 0
    return toc[:at] + "\n" + line + toc[at:]


def field(toc, name):
    m = re.search(rf"^## {re.escape(name)}:\s*(.+?)\s*$", toc, re.M)
    return m.group(1) if m else None


def build_toc(source_toc, target, spec):
    toc = source_toc
    toc = set_field(toc, "Interface", str(spec["interface"]))
    if spec.get("version"):
        toc = set_field(toc, "Version", spec["version"])
    if spec.get("title"):
        toc = set_field(toc, "Title", spec["title"])
    if spec.get("display"):
        toc = set_field(toc, "X-Display-Version", spec["display"])
    toc = set_field(toc, "X-Dawnward-Target", target)
    return toc


def find_lua51():
    native = shutil.which("lua5.1")
    if native:
        return [native]
    venv = ROOT / ".tooling" / "venv" / ("Scripts/python.exe" if sys.platform == "win32" else "bin/python")
    if venv.is_file():
        return [str(venv), str(ROOT / "tools" / "lua51.py")]
    return None


def check_lua_syntax(files):
    """Compile every Lua file on Lua 5.1 (files: {name: bytes}). Returns a list of errors."""
    lua = find_lua51()
    if not lua:
        return ["no Lua 5.1 runtime: Lua syntax was not checked"]
    errors = []
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        names = []
        for i, (name, data) in enumerate(sorted(files.items())):
            p = tmp / f"f{i}.lua"
            p.write_bytes(data)
            names.append((name, p))
        script = tmp / "syntax.lua"
        script.write_text(
            "for i = 1, #arg, 2 do local f, e = loadfile(arg[i + 1]) "
            "if not f then print('SYNTAX ' .. arg[i] .. ': ' .. tostring(e)) end end",
            encoding="utf-8")
        args = []
        for name, p in names:
            args += [name, str(p)]
        out = subprocess.run(lua + [str(script)] + args, capture_output=True, text=True)
        errors += [line for line in out.stdout.splitlines() if line.startswith("SYNTAX")]
        if out.returncode != 0:
            errors.append("Lua syntax check failed to run: " + out.stderr.strip())
    return errors


def verify(zip_path, target, spec):
    """Re-reads a written zip and checks it. Returns a list of problems."""
    problems = []
    with zipfile.ZipFile(zip_path) as zf:
        names = zf.namelist()
        roots = {n.split("/", 1)[0] for n in names}
        if roots != {ADDON}:
            problems.append(f"expected one root folder {ADDON}, found {sorted(roots)}")
        for n in names:
            low = n.lower()
            if any(part in low for part in FORBIDDEN_PARTS) or "\\" in n:
                problems.append("forbidden path in package: " + n)
        toc_name = f"{ADDON}/{ADDON}.toc"
        if toc_name not in names:
            return problems + ["missing " + toc_name]
        toc = zf.read(toc_name).decode("utf-8")
        if field(toc, "Interface") != str(spec["interface"]):
            problems.append(f"TOC interface {field(toc, 'Interface')} is not {spec['interface']} ({target})")
        if field(toc, "X-Dawnward-Target") != target:
            problems.append("TOC X-Dawnward-Target is not " + target)
        if spec.get("version") and field(toc, "Version") != spec["version"]:
            problems.append("TOC version is not " + spec["version"])
        other = [t for t in TARGETS if t != target]
        for o in other:
            if str(TARGETS[o]["interface"]) in (field(toc, "Interface") or ""):
                problems.append(f"{target} package declares the {o} interface")
        version = field(toc, "Version") or ""
        if target == "forever" and "-dev" in version:
            problems.append("the Forever package must not be a -dev build")
        listed = []
        for line in toc.splitlines():
            line = line.strip()
            if line and not line.startswith("#"):
                listed.append(f"{ADDON}/" + line.replace("\\", "/"))
        exact = set(names)
        for entry in listed:
            if entry not in exact:
                folded = {n.lower(): n for n in names}
                hint = folded.get(entry.lower())
                problems.append(f"TOC lists {entry}, " + (f"but the package has {hint} (letter case)" if hint
                                                           else "which is not in the package"))
        lua = {n: zf.read(n) for n in names if n.endswith(".lua")}
        for n in lua:
            if n not in exact or n not in listed:
                problems.append("Lua file not listed in the TOC: " + n)
        problems += check_lua_syntax(lua)
        for n in names:
            if n.endswith((".lua", ".toc", ".xml", ".txt", ".md")):
                text = zf.read(n).decode("utf-8", "replace")
                if LOCAL_PATH.search(text):
                    problems.append("local path or personal name in " + n)
    return problems


def build(target, files, source_toc, commit, dirty):
    spec = TARGETS[target]
    toc = build_toc(source_toc, target, spec)
    version = field(toc, "Version")
    out_dir = ROOT / "dist"
    out_dir.mkdir(exist_ok=True)
    out = out_dir / spec["zip"].format(version=version)
    toc_rel = f"{ADDON}/{ADDON}.toc"
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        for rel in files:
            info = zipfile.ZipInfo(rel, date_time=(2026, 1, 1, 0, 0, 0))  # reproducible
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            data = toc.encode("utf-8") if rel == toc_rel else (ROOT / rel).read_bytes()
            zf.writestr(info, data)
    out.write_bytes(buf.getvalue())
    problems = verify(out, target, spec)
    digest = hashlib.sha256(out.read_bytes()).hexdigest()
    manifest = {
        "target": target, "file": out.name, "version": version,
        "displayVersion": field(toc, "X-Display-Version") or version,
        "interface": spec["interface"], "commit": commit, "dirty": dirty,
        "sha256": digest, "files": len(files),
    }
    (out_dir / (out.name + ".sha256")).write_text(f"{digest}  {out.name}\n", encoding="utf-8")
    (out_dir / (out.name + ".manifest.json")).write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return out, digest, problems, manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--target", choices=["classic", "forever", "all"], default="all")
    parser.add_argument("--allow-dirty", action="store_true",
                        help="package an uncommitted tree (development only; the manifest says so)")
    args = parser.parse_args()

    source_toc = (ROOT / ADDON / f"{ADDON}.toc").read_text(encoding="utf-8")
    if not field(source_toc, "Version"):
        print("No ## Version in the TOC", file=sys.stderr)
        return 1
    untracked = git("ls-files", "--others", "--exclude-standard", "--", ADDON).split()
    if untracked:
        print("Refusing to package: untracked files in the addon folder:", *untracked, sep="\n  ", file=sys.stderr)
        return 1
    dirty = bool(git("status", "--porcelain", "--", ADDON).strip())
    if dirty and not args.allow_dirty:
        print("Refusing to package: uncommitted changes in the addon folder (commit first, or --allow-dirty).",
              file=sys.stderr)
        return 1
    commit = git("rev-parse", "HEAD").strip()
    files = tracked_files()

    failed = False
    for target in (["classic", "forever"] if args.target == "all" else [args.target]):
        out, digest, problems, manifest = build(target, files, source_toc, commit, dirty)
        print(f"{out.relative_to(ROOT)}: {manifest['files']} files, version {manifest['version']}, "
              f"interface {manifest['interface']}, commit {commit[:12]}{' (dirty)' if dirty else ''}")
        print(f"  sha256 {digest}")
        if "-dev" in manifest["version"]:
            print("  NOTE: a -dev build: developer commands are enabled.")
        for p in problems:
            print("  PROBLEM " + p, file=sys.stderr)
        failed = failed or bool(problems)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
