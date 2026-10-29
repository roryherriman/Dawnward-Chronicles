"""Build a release zip containing only the addon folder.

Usage: python tools/package.py
Output: dist/DawnwardChronicles-<version>.zip  (dist/ is git-ignored)

Only files tracked by git under DawnwardChronicles/ are packaged, so local
or private files can never end up in a release. Tests, tools and docs are
never included.
"""

import re
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ADDON = "DawnwardChronicles"


def main():
    toc = (ROOT / ADDON / f"{ADDON}.toc").read_text(encoding="utf-8")
    match = re.search(r"^## Version:\s*(\S+)", toc, re.M)
    if not match:
        print("No ## Version in the TOC", file=sys.stderr)
        return 1
    version = match.group(1)
    if "-dev" in version:
        # Developer commands (/dawnward dev ...) are enabled in -dev builds.
        print(f"NOTE: {version} is a development build: developer commands are enabled. "
              "Drop '-dev' from the TOC version for a release.", file=sys.stderr)

    tracked = subprocess.run(
        ["git", "ls-files", "-z", "--", ADDON], cwd=ROOT, capture_output=True, check=True,
    ).stdout.decode("utf-8").split("\0")
    tracked = sorted(p for p in tracked if p)
    untracked = subprocess.run(
        ["git", "ls-files", "--others", "--exclude-standard", "--", ADDON],
        cwd=ROOT, capture_output=True, text=True, check=True,
    ).stdout.split()
    if untracked:
        print("Refusing to package: untracked files in the addon folder:", *untracked, sep="\n  ", file=sys.stderr)
        return 1

    out_dir = ROOT / "dist"
    out_dir.mkdir(exist_ok=True)
    out = out_dir / f"{ADDON}-{version}.zip"
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
        for rel in tracked:
            zf.write(ROOT / rel, rel)
    print(f"{out.relative_to(ROOT)}: {len(tracked)} files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
