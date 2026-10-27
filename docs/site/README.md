# Project website (not published)

Location: `docs/site/`.

A static, dependency-free project page: `index.html`, `style.css` and `assets/`, which holds copies of the proposed brand assets from `assets/branding/`. It is **not deployed**. GitHub Pages is not configured for this repository, and publishing it would make the page public, which needs the maintainer's approval.

**Preview:** open `index.html` in a browser, or run `python -m http.server -d docs/site 8000` and visit http://localhost:8000.

- Fonts come from Google Fonts (Cinzel, EB Garamond; SIL OFL). Without a connection the page falls back to Georgia.
- There are no screenshots: real in-game captures will be added once the interface is verified.
- Keep the feature status labels in step with the README.

**To publish later (owner only):** Settings → Pages → deploy from a branch, choosing the folder; or use a small Pages workflow that uploads `docs/site/`. Check every link after deploying.
