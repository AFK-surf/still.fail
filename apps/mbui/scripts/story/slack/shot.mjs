// A still of film 5's Slack page (slack/<page>.html) at time t, at the outer screen's pixels: `node shot.mjs page t out.png`.
import { createRequire } from 'node:module';
import { join, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const here = dirname(fileURLToPath(import.meta.url));
const require = createRequire(join(process.env.PW_FROM || here, 'x.js'));
const { chromium } = require('playwright-core');
const [page, t, out] = process.argv.slice(2);
const b = await chromium.launch({ channel: 'chrome' });
const p = await b.newPage({ viewport: { width: 466, height: 678 }, deviceScaleFactor: 3 });
await p.goto(pathToFileURL(join(here, page + '.html')).href);
await p.evaluate(() => document.fonts.ready);
await p.evaluate((t) => window.at(t), Number(t));
await p.screenshot({ path: out });
await b.close();
