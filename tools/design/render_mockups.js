// Renders design-canvas artboards (.dc.html) to PNG for docs/design/mockups.
// Usage: node render_mockups.js <srcDir> <outDir> <scale> File.dc.html:name:width:height ...
// The artboards' runtime script (support.js) is stubbed: the markup renders as plain HTML.
const { chromium } = require('playwright');
const path = require('path');
const [, , srcDir, outDir, scale, ...pairs] = process.argv;
(async () => {
  const browser = await chromium.launch();
  for (const pair of pairs) {
    const [file, name, w, h] = pair.split(':');
    const page = await browser.newPage({ viewport: { width: +w, height: +h }, deviceScaleFactor: +scale });
    await page.route('**/support.js', r => r.fulfill({ status: 200, contentType: 'text/javascript', body: '' }));
    await page.goto('file://' + path.join(srcDir, file), { waitUntil: 'networkidle' });
    await page.evaluate(() => document.fonts.ready);
    const fams = await page.evaluate(() => [...document.fonts].filter(f => f.status === 'loaded').map(f => f.family + ' ' + f.weight + ' ' + f.style));
    await page.screenshot({ path: path.join(outDir, name + '.png'), clip: { x: 0, y: 0, width: +w, height: +h } });
    console.log(name, 'fonts:', [...new Set(fams)].join(', '));
    await page.close();
  }
  await browser.close();
})();
