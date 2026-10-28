// A still of film 5's desktop Slack (desk/desk.html, build.mjs) at time t: `node deskshot.mjs t out.png [marks JSON]`.
import { createRequire } from 'node:module';
import { join, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const here = dirname(fileURLToPath(import.meta.url));
const require = createRequire(join(process.env.PW_FROM || here, 'x.js'));
const { chromium } = require('playwright-core');
const [t, out, marks = '{}'] = process.argv.slice(2);
const b = await chromium.launch({ channel: 'chrome' });
const [w, h] = (process.env.DESK_SIZE || '1272x813').split('x').map(Number);
const p = await b.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: 2 });
p.on('pageerror', (e) => console.log('page:', e.message));
await p.goto(pathToFileURL(join(here, 'desk/desk.html')).href, { waitUntil: 'load', timeout: 120000 });
await p.evaluate(() => document.fonts.ready);
await p.evaluate(([t, m]) => window.at(t, m), [Number(t), JSON.parse(marks)]);
await new Promise((r) => setTimeout(r, 500));
if (process.env.DEBUG_DM) console.log(await p.evaluate(() => document.querySelector('[data-qa-channel-sidebar-channel-type="im"]')?.outerHTML.slice(0, 1500)));
await p.screenshot({ path: out });
await b.close();
