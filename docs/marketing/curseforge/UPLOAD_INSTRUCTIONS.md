# Updating the CurseForge project by hand (owner only)

The project already exists and is **unlisted** (owner-confirmed): https://www.curseforge.com/wow/addons/dawnward-chronicles/preview. These steps change only its description and images. They **do not** upload addon files, change visibility, or publish anything. Nothing here was done automatically: no CurseForge API, token or login was used.

## 1. Before you start
- [ ] Decide whether to approve the new identity (#49, `docs/BRANDING_GUIDE.md`). If not, skip steps 3–4 and keep the current images.
- [ ] Re-read [`FINAL_DESCRIPTION.md`](FINAL_DESCRIPTION.md) against the README's feature table.

## 2. Description
1. Sign in at curseforge.com yourself, open the project, then **Edit Project** (or the description editor in the author console).
2. Switch the editor to **Markdown**, if offered.
3. Paste the block from `FINAL_DESCRIPTION.md` (between the code fences), without the fences.
4. Keep the Alpha and WoW Forever warning.
5. Preview, then save. Saving the description does **not** change visibility. Check that the project still shows as unlisted afterwards.

## 3. Avatar (only if #49 is approved)
1. Upload `assets/branding/png/dawnward-icon-400.png` as the project avatar.
2. Check how it looks at small sizes on the preview page.

## 4. Header image (only if #49 is approved)
1. Upload `assets/branding/png/curseforge-banner-1920x480.png` to the project's images.
2. Copy its URL into the first line of the description, replacing `BANNER_URL_AFTER_UPLOAD`.

## 5. Do not
- Do not upload an addon file (that is release gate #24, and `PUBLICATION_CHECKLIST.md`).
- Do not change visibility or project status.
- Do not add screenshots that aren't real in-game captures.

## 6. After saving
Update `docs/handoffs/CURSEFORGE_STATUS.md`: date, what changed, and visibility as it appears in the console.
