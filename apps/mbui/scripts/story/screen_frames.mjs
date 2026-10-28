// A story's station screen made (story_fixture.mbt's `screen`): each of its moments (`screen.moments`: when, and what
// the page shows then) drawn by Chrome from its page (`screen.page`, e.g. checkout.html, given the moment as ?s=), a JPEG
// each, put in the story's pictures and its frames. The story out has them; run where Playwright is (Studio:
// PW_FROM=<a checkout with it>).
//   node screen_frames.mjs iduo-screen-en.json iduo-screen-en.built.json
import { readFileSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const [inName, outName] = process.argv.slice(2);
const story = JSON.parse(readFileSync(join(here, inName), 'utf8'));
const screen = story.screen;
const require = createRequire(join(process.env.PW_FROM || join(here, '../..'), 'x.js'));
const { chromium } = require('playwright-core');
const browser = await chromium.launch({ channel: 'chrome' });
// (the page laid out at its own size, drawn at the frames': screen.width x screen.height)
const [lw, lh] = screen.layout || [screen.width, screen.height];
const page = await browser.newPage({ viewport: { width: lw, height: lh }, deviceScaleFactor: screen.width / lw });
const url = pathToFileURL(join(here, screen.page)).href;
story.pictures = story.pictures || {};
screen.frames = [];
for (const [i, m] of screen.moments.entries()) {
  await page.goto(`${url}?s=${encodeURIComponent(JSON.stringify(m.s))}`);
  const name = `screen-${i}.jpg`;
  const jpg = await page.screenshot({ type: 'jpeg', quality: screen.quality || 70 });
  story.pictures[name] = jpg.toString('base64');
  screen.frames.push({ at: m.at, picture: name });
}
await browser.close();
delete screen.moments;
delete screen.layout;
delete screen.page;
writeFileSync(join(here, outName), JSON.stringify(story));
const bytes = Object.values(story.pictures).reduce((n, b) => n + b.length, 0);
console.log('screen frames:', screen.frames.length, 'pictures in base64:', bytes, 'bytes');
