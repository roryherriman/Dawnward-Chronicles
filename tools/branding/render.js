// Renders brand PNGs for tools/branding/build.py. Usage: node render.js <jobs.json>
// Each job: { svg | html, out, width, height }. SVGs render on a transparent background.
const fs = require("fs");
const path = require("path");
const { pathToFileURL } = require("url");
const { chromium } = require("playwright");

(async () => {
	const jobs = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
	const browser = await chromium.launch();
	const page = await browser.newPage({ deviceScaleFactor: 1 });
	for (const job of jobs) {
		await page.setViewportSize({ width: job.width, height: job.height });
		if (job.svg) {
			const markup = fs.readFileSync(job.svg, "utf8")
				.replace("<svg ", `<svg style="display:block;width:${job.width}px;height:${job.height}px" `);
			await page.setContent(`<html><body style="margin:0;background:transparent">${markup}</body></html>`);
		} else {
			await page.goto(pathToFileURL(job.html).href);
			await page.waitForLoadState("networkidle");
		}
		fs.mkdirSync(path.dirname(job.out), { recursive: true });
		await page.screenshot({ path: job.out, omitBackground: !!job.svg,
			clip: { x: 0, y: 0, width: job.width, height: job.height } });
		console.log("rendered", path.relative(process.cwd(), job.out));
	}
	await browser.close();
})();
