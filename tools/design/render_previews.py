"""Render approximate previews of the v0.6 design (browser, not the game).

Reads theme colours from DawnwardChronicles/Core/Themes.lua and the window
and wizard sizes from the UI layout, then draws the journal window (Journal
tab) and the setup wizard (Character page) in Classic Dawnward, Lightbound
and Shadowbound with Chromium (Node `playwright`).

Usage: python tools/design/render_previews.py
Output: docs/design/previews/*.png  (labelled as approximations)

The font is a stand-in for the game's Friz Quadrata, and real game
rendering will differ: these images are for design review only, never
for a store page or as a screenshot.
"""

import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs" / "design" / "previews"


def themes():
    text = (ROOT / "DawnwardChronicles" / "Core" / "Themes.lua").read_text(encoding="utf-8")
    out = {}
    for block in re.findall(r'\{\s*id = "(\w+)",\s*name = "([^"]+)",(.*?)\n\t\}', text, re.S):
        tid, name, body = block
        colors = dict(re.findall(r'(\w+) = hex\("(#[0-9A-Fa-f]{6})"\)', body))
        if "background" in colors:
            out[tid] = {"name": name, **colors}
    return out


CSS = """
body{margin:0;background:#2a2f36;font-family:'Palatino Linotype',Georgia,serif;padding:24px}
.cap{color:#ddd;font:12px system-ui;margin:0 0 6px}
.win{position:relative;background:var(--background);outline:1px solid #050508;box-sizing:border-box}
.win:before{content:"";position:absolute;inset:3px;border:1px solid color-mix(in srgb,var(--ornament) 45%,transparent);pointer-events:none}
.c{position:absolute;width:10px;height:10px;border-color:var(--ornament);border-style:solid;border-width:0}
.tl{top:3px;left:3px;border-top-width:2px;border-left-width:2px}.tr{top:3px;right:3px;border-top-width:2px;border-right-width:2px}
.bl{bottom:3px;left:3px;border-bottom-width:2px;border-left-width:2px}.br{bottom:3px;right:3px;border-bottom-width:2px;border-right-width:2px}
.eyebrow{color:var(--ornament);font-size:10px;letter-spacing:.12em}
.title{color:var(--accent);font-size:17px}
.muted{color:var(--muted);font-size:11px}.text{color:var(--text);font-size:12px}
.btn{display:inline-flex;align-items:center;justify-content:center;height:20px;padding:0 8px;font-size:11px;
 background:var(--surface);border:1px solid var(--edge);color:var(--text);box-sizing:border-box}
.primary{background:var(--accent);border-color:var(--accent);color:var(--accentText)}
.ghost{background:transparent;border-color:transparent}.danger{background:transparent;border-color:transparent;color:var(--danger)}
.sel{background:var(--surfaceHover);border-color:var(--accent);color:var(--accent)}
.card{background:var(--surface);border:1px solid var(--edge);padding:8px 10px;margin-bottom:8px}
.icon{width:22px;height:22px;border:1px solid var(--edge);display:inline-flex;align-items:center;justify-content:center;color:var(--muted);font-size:12px;box-sizing:border-box}
.input{height:22px;background:var(--surface);border:1px solid var(--edge);color:var(--text);font-size:12px;padding:3px 6px;box-sizing:border-box}
"""


def window(t):
    tabs = "".join(
        f'<div style="width:112px;text-align:center;color:{"var(--accent)" if i == 0 else "var(--muted)"};'
        f'font-size:13px;padding-top:6px;height:28px;box-sizing:border-box;{"border-bottom:2px solid var(--accent)" if i == 0 else ""}">{n}</div>'
        for i, n in enumerate(["Journal", "Character", "Story", "Chronicle"]))
    cards = ""
    for meta, title, body, extra in [
        ("27 Oct 2026, 21:14  -  story", "Goldshire", "Reached Goldshire, Elwynn Forest, at level 5.<br><br>Lirael watched the people more than the place.", '<span class="btn sel">Defining</span>'),
        ("27 Oct 2026, 20:02  -  draft - approve to keep", "Kobold Candles", "Completed \"Kobold Candles\" in Elwynn Forest at level 4.", '<span class="btn primary">Approve</span>'),
        ("26 Oct 2026, 18:40  -  Level 3  -  Elwynn Forest  -  recorded automatically", "", "Reached level 3.", ""),
    ]:
        cards += (f'<div class="card"><div style="display:flex;justify-content:space-between;align-items:center">'
                  f'<span class="muted">{meta}</span><span style="display:flex;gap:4px">{extra}'
                  f'<span class="btn ghost">Edit</span><span class="btn danger">Delete</span>'
                  f'<span class="btn ghost" style="color:#C7C7C7">Private</span></span></div>'
                  + (f'<div class="title" style="font-size:13px;margin-top:6px">{title}</div>' if title else "")
                  + f'<div class="text" style="margin-top:4px">{body}</div></div>')
    return f"""
<div class="win" style="width:640px;height:540px">
 <i class="c tl"></i><i class="c tr"></i><i class="c bl"></i><i class="c br"></i>
 <div style="position:absolute;left:20px;top:14px;width:34px;height:34px;outline:1px solid var(--ornament);background:linear-gradient(135deg,#6b4a2b,#2f2016)"></div>
 <div class="eyebrow" style="position:absolute;left:66px;top:14px">DAWNWARD CHRONICLES</div>
 <div class="title" style="position:absolute;left:66px;top:28px">Lirael's Journal</div>
 <div style="position:absolute;right:20px;top:14px;display:flex;gap:6px"><span class="icon">?</span><span class="icon">&#9881;</span><span class="icon">X</span></div>
 <div style="position:absolute;left:20px;top:58px;display:flex;gap:4px">{tabs}</div>
 <div style="position:absolute;left:20px;right:20px;top:91px;border-top:1px solid var(--edge)"></div>
 <div style="position:absolute;left:20px;right:20px;top:92px;bottom:36px;background:var(--panel);padding:6px 8px;box-sizing:border-box;overflow:hidden">
  <div style="display:flex;justify-content:space-between;margin-bottom:10px"><span class="btn primary" style="width:100px">New entry</span>
   <span style="display:flex;gap:4px;align-items:center"><span class="btn ghost">&lt; Newer</span><span class="muted">Page 1 of 3</span><span class="btn ghost">Older &gt;</span></span></div>
  {cards}
 </div>
 <div style="position:absolute;left:20px;right:20px;bottom:36px;border-top:1px solid var(--edge)"></div>
 <div class="muted" style="position:absolute;left:20px;bottom:13px">Saved.</div>
</div>"""


def wizard(t):
    steps = "".join(
        f'<div style="width:85px"><div style="font-size:11px;color:{"var(--text)" if i < 1 else "var(--accent)" if i == 1 else "var(--muted)"}">{i + 1}&nbsp;&nbsp;{n}</div>'
        f'<div style="height:2px;width:79px;margin-top:6px;background:{"var(--accent)" if i <= 1 else "var(--edge)"}"></div></div>'
        for i, n in enumerate(["Welcome", "Character", "Story", "Privacy", "Appearance", "Finish"]))
    rows = "".join(
        f'<div style="display:flex;align-items:center;margin-top:14px"><div class="muted" style="width:150px;font-size:12px">{k}</div>'
        f'<div class="input" style="width:362px{";border-color:var(--accent)" if k == "Title" else ""}">{v}</div></div>'
        for k, v in [("Name", "Lirael"), ("Title", "Wanderer of the Vale"), ("Pronouns", "she/her"), ("Homeland", "Northshire Valley"), ("A line about them", "")])
    return f"""
<div class="win" style="width:560px;height:470px">
 <i class="c tl"></i><i class="c tr"></i><i class="c bl"></i><i class="c br"></i>
 <div class="eyebrow" style="position:absolute;left:24px;top:18px">FIRST-TIME SETUP</div>
 <div class="title" style="position:absolute;left:24px;top:33px">Character</div>
 <span class="icon" style="position:absolute;right:12px;top:12px">X</span>
 <div style="position:absolute;left:24px;top:68px;display:flex">{steps}</div>
 <div style="position:absolute;left:24px;right:24px;top:106px">
  <div class="muted" style="font-size:12px">Confirm who your character is. All of it is optional and private until you choose otherwise. Existing details are kept; an empty box never erases anything.</div>
  {rows}
 </div>
 <div style="position:absolute;left:24px;right:24px;bottom:52px;border-top:1px solid var(--edge)"></div>
 <div style="position:absolute;left:24px;right:24px;bottom:16px;display:flex;justify-content:space-between">
  <span style="display:flex;gap:8px"><span class="btn ghost" style="width:90px">&lt; Back</span><span class="btn ghost" style="width:120px">Set up later</span></span>
  <span class="btn primary" style="width:120px;height:22px">Next &gt;</span></div>
</div>"""


def page(tid, t, body, caption):
    vars_ = ";".join(f"--{k}:{v}" for k, v in t.items() if k != "name")
    return (f"<!doctype html><html><head><meta charset='utf-8'><style>{CSS}</style></head>"
            f"<body style='{vars_}'><p class='cap'>{caption} - {t['name']} - approximate browser preview, "
            f"not a game screenshot</p>{body}</body></html>")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    jobs = []
    tmp = Path(tempfile.mkdtemp())
    for tid in ("dawnward", "lightbound", "shadowbound"):
        t = themes()[tid]
        for kind, body, size in (("journal", window(t), (688, 600)), ("setup", wizard(t), (608, 530))):
            html = tmp / f"{kind}-{tid}.html"
            html.write_text(page(tid, t, body, "Journal window" if kind == "journal" else "Setup wizard"),
                            encoding="utf-8")
            jobs.append({"html": str(html), "out": str(OUT / f"v06-{kind}-{tid}.png"), "width": size[0],
                         "height": size[1]})
    spec = tmp / "jobs.json"
    spec.write_text(json.dumps(jobs))
    subprocess.run(["node", str(ROOT / "tools" / "design" / "render.js"), str(spec)], check=True, cwd=ROOT)
    return 0


if __name__ == "__main__":
    sys.exit(main())
