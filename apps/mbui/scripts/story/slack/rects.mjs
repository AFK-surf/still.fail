// Where the film's desktop Slack lays out its parts (desk/desk.html at 1272 × 813), to frame them: `node rects.mjs`.
import { createRequire } from 'node:module';
import { join, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const here = dirname(fileURLToPath(import.meta.url));
const require = createRequire(join(process.env.PW_FROM || here, 'x.js'));
const { chromium } = require('playwright-core');
const b = await chromium.launch({ channel: 'chrome' });
const p = await b.newPage({ viewport: { width: 1272, height: 813 } });
await p.goto(pathToFileURL(join(here, 'desk/desk.html')).href, { waitUntil: 'load', timeout: 120000 });
await p.evaluate(() => document.fonts.ready);
const m = { typing: -1.5, ana: 1.6, eyes: 2.3, found: 3.8, point: 4.1, open: 4.9, deploy: 10.3, fixed: 12.85, reply: 13.06, thanks: 14.26 };
const r = async (t, png) => {
  await p.evaluate(([t, m]) => window.at(t, m), [t, m]);
  console.log(t, JSON.stringify(await p.evaluate(() => {
    const r = (e) => { if (!e) return null; const b = e.getBoundingClientRect(); return [b.x, b.y, b.width, b.height].map(Math.round); };
    const ed = [...document.querySelectorAll('.ql-editor')];
    return { main: r(ed.find((e) => !e.closest('.p-threads_flexpane'))), thread: r(document.querySelector('.p-threads_flexpane')),
      bar: r([...document.querySelectorAll('[data-qa="reply_bar"]')].find((e) => !e.closest('.p-threads_flexpane'))), threadEditor: r(ed.find((e) => e.closest('.p-threads_flexpane'))) };
  })));
  await p.screenshot({ path: join(here, png) });
};
await r(0.5, 'desk/s1.png');
await r(4.6, 'desk/s2.png');
await r(5.5, 'desk/s3.png');
await r(13.8, 'desk/s4.png');
await b.close();
