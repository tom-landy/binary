// Render every SVG in a folder to a 1024px PNG next to it. Transparent SVGs stay transparent.
// Usage: node Design/icon/render.js /tmp/icons   (needs Playwright with Chromium)
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

(async () => {
  const dir = process.argv[2] || 'icons';
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1024, height: 1024 }, deviceScaleFactor: 1 });
  for (const file of fs.readdirSync(dir).filter(f => f.endsWith('.svg'))) {
    const svg = fs.readFileSync(path.join(dir, file), 'utf8');
    await page.setContent(`<html><body style="margin:0;background:transparent">${svg}</body></html>`);
    await page.locator('svg').screenshot({ path: path.join(dir, file.replace(/\.svg$/, '.png')), omitBackground: true });
  }
  await browser.close();
})();
