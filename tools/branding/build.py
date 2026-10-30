"""Build Dawnward Chronicles brand assets (issue #49): SVG sources and PNG exports.

Usage:
  python tools/branding/build.py --font-dir <dir with Cinzel-600.ttf and Cinzel-700.ttf> [--png]

Every shape is drawn here by hand-written geometry; no imagery is generated or
traced. The wordmark is Cinzel (SIL Open Font License 1.1, Google Fonts),
converted to vector outlines so the SVGs need no font. The font files are
not committed: download Cinzel from https://fonts.google.com/specimen/Cinzel.
With --png, Playwright's Chromium (Node `playwright` package) renders the
PNG exports and preview sheets through tools/branding/render.js.
"""

import argparse
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "branding"

PALETTE = {
    "night": "#14111C",      # Night Ink: dark backgrounds
    "ink": "#1A1714",        # Chronicle Ink: the addon's Neutral window
    "parchment": "#EDE6D6",  # Parchment: light backgrounds, text on dark
    "gold": "#DBBD75",       # Dawn Gold: the addon's Neutral accent
    "ember": "#E08A3C",      # Sunrise Ember: the sun's lower edge
    "violet": "#4B3B6B",     # Dusk Violet: secondary accent
}


# --- Wordmark outlines ------------------------------------------------------

def text_path(font_path, text, size, tracking=0.0):
    """SVG path data for text set in a TTF font, plus its advance width (px)."""
    from fontTools.pens.svgPathPen import SVGPathPen
    from fontTools.pens.transformPen import TransformPen
    from fontTools.ttLib import TTFont

    font = TTFont(font_path)
    glyphs = font.getGlyphSet()
    cmap = font.getBestCmap()
    scale = size / font["head"].unitsPerEm
    x, parts = 0.0, []
    for ch in text:
        name = cmap[ord(ch)]
        pen = SVGPathPen(glyphs)
        glyphs[name].draw(TransformPen(pen, (scale, 0, 0, -scale, x, 0)))
        parts.append(pen.getCommands())
        x += glyphs[name].width * scale + tracking * size
    return " ".join(p for p in parts if p), x - tracking * size


# --- The mark: dawn over an open book -----------------------------------------

def mark(bg, page, sun_top, sun_bottom, ray, uid, size=256, rounded=True):
    """The square mark as SVG markup (no outer <svg>), in a 256 x 256 box scaled to size."""
    s = size / 256
    cx, horizon = 128, 150
    rays = []
    for i, deg in enumerate((-60, -30, 0, 30, 60)):
        a = math.radians(deg - 90)
        r1, r2 = 62, 92 if deg == 0 else 84
        rays.append(f'<line x1="{cx + r1 * math.cos(a):.1f}" y1="{horizon + r1 * math.sin(a):.1f}" '
                    f'x2="{cx + r2 * math.cos(a):.1f}" y2="{horizon + r2 * math.sin(a):.1f}"/>')
    background = (f'<rect width="256" height="256" rx="{52 if rounded else 0}" fill="{bg}"/>' if bg else "")
    return f'''<g transform="scale({s:.4f})">
  <defs>
    <linearGradient id="sun{uid}" x1="0" y1="0" x2="0" y2="0.5">
      <stop offset="0" stop-color="{sun_top}"/><stop offset="1" stop-color="{sun_bottom}"/>
    </linearGradient>
    <clipPath id="sky{uid}"><rect x="0" y="0" width="256" height="{horizon}"/></clipPath>
  </defs>
  {background}
  <g stroke="{ray}" stroke-width="11" stroke-linecap="round">{"".join(rays)}</g>
  <circle cx="{cx}" cy="{horizon}" r="48" fill="url(#sun{uid})" clip-path="url(#sky{uid})"/>
  <path fill="{page}" d="M36 148 C66 140 104 142 122 156 L122 214 C104 200 66 198 36 206 Z"/>
  <path fill="{page}" d="M220 148 C190 140 152 142 134 156 L134 214 C152 200 190 198 220 206 Z"/>
</g>'''


def svg(width, height, body, title):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
            f'viewBox="0 0 {width} {height}" role="img" aria-label="{title}">\n<title>{title}</title>\n{body}\n</svg>\n')


VARIANTS = {
    # name: (background, page, sun top, sun bottom, rays, wordmark, subline)
    "dark": (PALETTE["night"], PALETTE["parchment"], PALETTE["gold"], PALETTE["ember"], PALETTE["gold"],
             PALETTE["parchment"], PALETTE["gold"]),
    "light": (PALETTE["parchment"], PALETTE["night"], PALETTE["gold"], PALETTE["ember"], PALETTE["ember"],
              PALETTE["night"], PALETTE["violet"]),
}


def lockup(fonts, variant, transparent=False):
    bg, page, top, bottom, ray, word, sub = VARIANTS[variant]
    big, big_w = text_path(fonts / "Cinzel-700.ttf", "DAWNWARD", 96, tracking=0.04)
    small, small_w = text_path(fonts / "Cinzel-600.ttf", "CHRONICLES", 44, tracking=0.32)
    width = 40 + 200 + 36 + max(big_w, small_w) + 48
    height = 280
    body = ""
    if not transparent:
        body += f'<rect width="{width:.0f}" height="{height}" rx="28" fill="{bg}"/>\n'
    body += f'<g transform="translate(40 40)">{mark(None, page, top, bottom, ray, "L" + variant, 200)}</g>\n'
    tx = 40 + 200 + 36
    body += f'<path fill="{word}" transform="translate({tx:.1f} 150)" d="{big}"/>\n'
    body += f'<path fill="{sub}" transform="translate({tx + (big_w - small_w) / 2:.1f} 214)" d="{small}"/>\n'
    return svg(round(width), height, body, "Dawnward Chronicles")


# --- Explored directions (see the brand guide) -----------------------------------

def concept_book():
    """B: Illuminated chronicle. A closed book whose cover bears a dawn medallion."""
    p = PALETTE
    return svg(256, 256, f'''<rect width="256" height="256" rx="52" fill="{p["violet"]}"/>
<rect x="64" y="40" width="128" height="176" rx="10" fill="{p["night"]}" stroke="{p["gold"]}" stroke-width="6"/>
<rect x="64" y="40" width="18" height="176" rx="6" fill="{p["gold"]}"/>
<circle cx="137" cy="118" r="34" fill="none" stroke="{p["gold"]}" stroke-width="6"/>
<path d="M111 126 A26 26 0 0 1 163 126 Z" fill="{p["ember"]}"/>
<line x1="105" y1="132" x2="169" y2="132" stroke="{p["gold"]}" stroke-width="6" stroke-linecap="round"/>
<path d="M150 216 L150 236 L160 228 L170 236 L170 216 Z" fill="{p["ember"]}"/>''', "Concept B: illuminated chronicle")


def concept_compass():
    """C: Compass and quill. An eight-point star whose north point is a quill nib."""
    p = PALETTE
    pts = []
    for i in range(16):
        a = math.radians(i * 22.5 - 90)
        r = 96 if i % 4 == 0 else (54 if i % 2 == 0 else 26)
        pts.append(f"{128 + r * math.cos(a):.1f},{128 + r * math.sin(a):.1f}")
    return svg(256, 256, f'''<rect width="256" height="256" rx="52" fill="{p["night"]}"/>
<circle cx="128" cy="128" r="100" fill="none" stroke="{p["violet"]}" stroke-width="6"/>
<polygon points="{" ".join(pts)}" fill="{p["gold"]}"/>
<path d="M128 22 C146 52 142 86 128 112 C114 86 110 52 128 22 Z" fill="{p["parchment"]}"/>
<line x1="128" y1="40" x2="128" y2="104" stroke="{p["night"]}" stroke-width="4"/>
<circle cx="128" cy="128" r="12" fill="{p["ember"]}"/>''', "Concept C: compass and quill")


def write(name, text):
    path = OUT / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return path


def build_svgs(fonts):
    written = []
    for variant, (bg, page, top, bottom, ray, _, _) in VARIANTS.items():
        written.append(write(f"svg/dawnward-mark-{variant}.svg",
                             svg(256, 256, mark(bg, page, top, bottom, ray, variant), "Dawnward Chronicles")))
        written.append(write(f"svg/dawnward-lockup-{variant}.svg", lockup(fonts, variant)))
        written.append(write(f"svg/dawnward-lockup-{variant}-transparent.svg", lockup(fonts, variant, True)))
    bg, page, top, bottom, ray, _, _ = VARIANTS["dark"]
    # Favicon: no rays below 32 px would blur; keep them, thicker, on a square.
    written.append(write("svg/favicon.svg", svg(256, 256, mark(bg, page, top, bottom, ray, "fav"), "Dawnward")))
    written.append(write("concepts/concept-a-rising-dawn.svg",
                         svg(256, 256, mark(bg, page, top, bottom, ray, "ca"), "Concept A: dawn over an open book")))
    written.append(write("concepts/concept-b-illuminated-chronicle.svg", concept_book()))
    written.append(write("concepts/concept-c-compass-quill.svg", concept_compass()))
    return written


PNG_EXPORTS = [
    # (source svg, output png, width, height)
    ("svg/dawnward-mark-dark.svg", "png/dawnward-icon-1024.png", 1024, 1024),
    ("svg/dawnward-mark-dark.svg", "png/dawnward-icon-512.png", 512, 512),
    ("svg/dawnward-mark-dark.svg", "png/dawnward-icon-400.png", 400, 400),
    ("svg/dawnward-mark-dark.svg", "png/dawnward-icon-256.png", 256, 256),
    ("svg/dawnward-mark-dark.svg", "png/dawnward-icon-128.png", 128, 128),
    ("svg/dawnward-mark-dark.svg", "png/dawnward-icon-64.png", 64, 64),
    ("svg/dawnward-mark-light.svg", "png/dawnward-icon-light-512.png", 512, 512),
    ("svg/favicon.svg", "png/favicon-32.png", 32, 32),
    ("svg/favicon.svg", "png/favicon-16.png", 16, 16),
    ("svg/favicon.svg", "png/apple-touch-icon-180.png", 180, 180),
]


def render_pngs():
    """Renders PNGs with Playwright's Chromium through Node (tools/branding/render.js)."""
    import json
    import subprocess
    import tempfile

    jobs = [{"svg": str(OUT / src), "out": str(OUT / dst), "width": w, "height": h} for src, dst, w, h in PNG_EXPORTS]
    for name in ("lockup-dark", "lockup-light"):
        source = OUT / f"svg/dawnward-{name}.svg"
        width = int(source.read_text(encoding="utf-8").split('width="', 1)[1].split('"', 1)[0])
        jobs.append({"svg": str(source), "out": str(OUT / f"png/dawnward-{name}.png"), "width": width, "height": 280})
    for html, out, w, h in (("social-preview.html", "png/social-preview-1280x640.png", 1280, 640),
                            ("preview-sheet.html", "previews/branding-preview.png", 1200, 1700),
                            ("curseforge-banner.html", "png/curseforge-banner-1920x480.png", 1920, 480),
                            ("curseforge-banner-850.html", "png/curseforge-banner-850x213.png", 850, 213)):
        source = OUT / "templates" / html
        if source.exists():
            jobs.append({"html": str(source), "out": str(OUT / out), "width": w, "height": h})
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        json.dump(jobs, f)
    subprocess.run(["node", str(Path(__file__).with_name("render.js")), f.name], check=True)


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--font-dir", required=True, type=Path)
    parser.add_argument("--png", action="store_true")
    args = parser.parse_args(argv)
    for path in build_svgs(args.font_dir):
        print("wrote", path.relative_to(ROOT))
    if args.png:
        render_pngs()
        print("rendered PNG exports")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
