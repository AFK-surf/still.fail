// The web app's stories (web/stories/stories.tsx) as numbers, for mbui's app to be held against them by src/sflayout:
// each story taken to its state at a desktop's size (as web-ref.mjs takes it), then every element on the page with
// where it is and how it looks (its box, what of it shows, its corner, ground, words' size, opacity), named by its
// class (the stories' build keeps vanilla-extract's debug names: `shell_dock`), its aria-label and its own words; and
// the made-up core's topics as the page has them then (window.demoTape), the same data for mbui's.
//   node apps/mbui/scripts/web-layout.mjs OUT STORY[,…] [WxH] [TOPICS.json]
// writes OUT/STORY.web.json and OUT/STORY.web.png. STORY@X,Y: the pointer moved to X,Y after its steps (a step more,
// mbui's taken too: `app-sidebar-folded@640,400`, the folded sidebar not shown a while by the pointer its click left). TOPICS.json: topics besides those the page asked for (mbui's app
// asks some the page does not: src/sflayout says which), a JSON array of the core's topic keys.
// (from the repository's root, its packages installed; PLAYWRIGHT_MODULE picks Playwright, as web-ref.mjs)
import { mkdir, mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { build, preview } from 'vite';

const playwright = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');

// The page as it will stay: its network quiet, its fonts in, every animation that ends ended (web-ref.mjs's).
async function settled(page) {
  await page.waitForLoadState('networkidle');
  await page.evaluate(async () => {
    await document.fonts.ready;
    for (;;) {
      const ending = document.getAnimations().filter((a) => a.playState === 'running' && a.effect?.getComputedTiming().endTime !== Infinity);
      if (ending.length === 0) break;
      await Promise.all(ending.map((a) => a.finished.catch(() => {})));
    }
  });
}

// Every element shown, in document order (a parent before what it holds): see the file's head.
function elements() {
  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = 1;
  const g = canvas.getContext('2d', { willReadFrequently: true });
  const rgba = new Map();
  // a CSS colour as RGBA, 0 to 255 each (whatever way it is written: rgb(), color-mix's oklch…), as a canvas paints it
  const colour = (c) => {
    if (!c || c === 'transparent' || c === 'rgba(0, 0, 0, 0)') return [0, 0, 0, 0];
    if (rgba.has(c)) return rgba.get(c);
    g.clearRect(0, 0, 1, 1);
    g.fillStyle = '#000';
    g.fillStyle = c;
    g.fillRect(0, 0, 1, 1);
    const d = [...g.getImageData(0, 0, 1, 1).data];
    rgba.set(c, d);
    return d;
  };
  const px = (v) => parseFloat(v) || 0;
  const out = [];
  const index = new Map();
  const vw = innerWidth, vh = innerHeight;
  // what a range of words covers, its lines' boxes together (null when nothing)
  const covers = (range, box) => {
    for (const q of range.getClientRects()) {
      if (q.width === 0 && q.height === 0) continue;
      box[0] = Math.min(box[0], q.left); box[1] = Math.min(box[1], q.top); box[2] = Math.max(box[2], q.right); box[3] = Math.max(box[3], q.bottom);
    }
  };
  // a paragraph: a block whose children are all inline (words, code, a link…): its words one text, as mbui draws them
  // in one rich text, what is in it not again
  const inline = (n) => n.nodeType === Node.TEXT_NODE || (n.nodeType === Node.ELEMENT_NODE && !(n instanceof SVGElement) && getComputedStyle(n).display.startsWith('inline') && [...n.childNodes].every(inline));
  const presses = (el) => /^(button|a|input|textarea|select|summary)$/i.test(el.tagName) || el.getAttribute('role') === 'button' || el.hasAttribute('tabindex');
  const walk = (el, parent, depth, cut, alpha, inPara) => {
    const cs = getComputedStyle(el);
    if (cs.display === 'none') return;
    const r = el.getBoundingClientRect();
    const a = alpha * px(cs.opacity === '' ? '1' : cs.opacity);
    // what of it shows: inside every box above it that clips, and the window
    const l = Math.max(r.left, cut[0]), t = Math.max(r.top, cut[1]);
    const rr = Math.min(r.right, cut[2]), b = Math.min(r.bottom, cut[3]);
    const svg = el instanceof SVGElement;
    const names = typeof el.className === 'string' ? el.className.split(/\s+/).filter((c) => /__/.test(c)).map((c) => c.replace(/__.*/, '')) : [];
    const para = !inPara && !cs.display.startsWith('inline') && el.children.length > 0 && [...el.childNodes].every(inline) && el.textContent.trim() !== '';
    // its own words: the text right in it (not its children's; a paragraph's, all of it), and where they are drawn
    let words = '';
    const wb = [Infinity, Infinity, -Infinity, -Infinity];
    if (para) {
      words = el.textContent;
      const range = document.createRange();
      range.selectNodeContents(el);
      covers(range, wb);
    } else if (!inPara) {
      for (const n of el.childNodes) {
        if (n.nodeType !== Node.TEXT_NODE || !n.textContent.trim()) continue;
        words += n.textContent;
        const range = document.createRange();
        range.selectNodeContents(n);
        covers(range, wb);
      }
    }
    const [wl, wt, wr, wbm] = wb;
    words = words.replace(/\s+/g, ' ').trim();
    const shown = cs.visibility !== 'hidden' && rr > l && b > t;
    const me = out.length;
    index.set(el, me);
    out.push({
      index: me,
      parent,
      depth,
      tag: el.tagName.toLowerCase(),
      names,
      label: el.getAttribute('aria-label') || '',
      role: el.getAttribute('role') || '',
      text: words,
      x: r.left, y: r.top, w: r.width, h: r.height,
      cut: shown ? [l, t, rr - l, b - t] : [l, t, 0, 0],
      words: words && wr > wl ? [wl, wt, wr - wl, wbm - wt] : null,
      hit: presses(el),
      radius: cs.borderTopLeftRadius.endsWith('%') ? px(cs.borderTopLeftRadius) / 100 * r.width : px(cs.borderTopLeftRadius),
      bg: colour(cs.backgroundColor),
      border_w: px(cs.borderTopWidth),
      border_c: colour(cs.borderTopColor),
      font_size: px(cs.fontSize),
      weight: px(cs.fontWeight),
      color: colour(cs.color),
      opacity: a,
    });
    // its ::before and ::after where they paint (a place's lit ground, a block's line): placed absolutely, by their
    // insets in its padding box (one placed otherwise is left out)
    for (const which of ['::before', '::after']) {
      const ps = getComputedStyle(el, which);
      if (ps.content === 'none' || ps.content === 'normal' || ps.display === 'none' || ps.position !== 'absolute') continue;
      const bg = colour(ps.backgroundColor), bw = px(ps.borderTopWidth);
      if (bg[3] === 0 && bw === 0) continue;
      const side = (v) => (v === 'auto' ? null : px(v));
      const L = r.left + px(cs.borderLeftWidth), T = r.top + px(cs.borderTopWidth);
      const W = r.width - px(cs.borderLeftWidth) - px(cs.borderRightWidth), H = r.height - px(cs.borderTopWidth) - px(cs.borderBottomWidth);
      const [li, ri, ti, bi] = [side(ps.left), side(ps.right), side(ps.top), side(ps.bottom)];
      const w = ps.width !== 'auto' && !ps.width.endsWith('%') ? px(ps.width) : li !== null && ri !== null ? W - li - ri : null;
      const h = ps.height !== 'auto' && !ps.height.endsWith('%') ? px(ps.height) : ti !== null && bi !== null ? H - ti - bi : null;
      if (w === null || h === null) continue;
      const x = li !== null ? L + li : L + W - (ri ?? 0) - w, y = ti !== null ? T + ti : T + H - (bi ?? 0) - h;
      const pl = Math.max(x, cut[0]), pt = Math.max(y, cut[1]), pr = Math.min(x + w, cut[2]), pb = Math.min(y + h, cut[3]);
      const pa = a * px(ps.opacity === '' ? '1' : ps.opacity);
      out.push({
        index: out.length, parent: me, depth: depth + 1, tag: which, names: names.map((n) => n + which), label: '', role: '', text: '',
        x, y, w, h, cut: shown && pr > pl && pb > pt ? [pl, pt, pr - pl, pb - pt] : [pl, pt, 0, 0], words: null, hit: false,
        radius: ps.borderTopLeftRadius.endsWith('%') ? px(ps.borderTopLeftRadius) / 100 * w : px(ps.borderTopLeftRadius),
        bg, border_w: bw, border_c: colour(ps.borderTopColor), font_size: 0, weight: 0, color: [0, 0, 0, 0], opacity: pa,
      });
    }
    // (an icon's drawing is one thing: its paths not listed)
    if (svg) return;
    const clips = cs.overflowX !== 'visible' || cs.overflowY !== 'visible';
    const inner = clips ? [Math.max(cut[0], r.left), Math.max(cut[1], r.top), Math.min(cut[2], r.right), Math.min(cut[3], r.bottom)] : cut;
    for (const c of el.children) walk(c, me, depth + 1, inner, a, inPara || para);
  };
  walk(document.body, -1, 0, [0, 0, vw, vh], 1, false);
  return out;
}

/** How long the page's clock runs after a step: longer than its timers (Rail.tsx PEEK_LEAVE: 400) and the motion they
 *  set off (brand.tsx moveSidebar: 380) together. */
const PAGE_TIMERS = 1500;
/** The moment the page's clock starts at, each run the same. */
const CLOCK_AT = Date.UTC(2026, 9, 20, 2, 0);
const out = process.argv[2] || 'out/layout';
const specs = (process.argv[3] || 'app-chat,app-sidebar-folded@640,400,app-sidebar-peek').split(/,(?![0-9])/);
const away = new Map(specs.map((s) => { const [id, at] = s.split('@'); return [id, at ? at.split(',').map(Number) : null]; }));
const ids = [...away.keys()];
const [width, height] = (process.argv[4] || '1280x800').split('x').map(Number);
const extra = process.argv[5] ? JSON.parse(await readFile(process.argv[5], 'utf8')) : [];
const configFile = fileURLToPath(new URL('../../../web/vite.stories.config.ts', import.meta.url));
const dist = await mkdtemp(join(tmpdir(), 'web-layout-'));
await build({ configFile, build: { outDir: dist, emptyOutDir: true, minify: false, reportCompressedSize: false }, logLevel: 'error' });
const server = await preview({ configFile, build: { outDir: dist }, preview: { host: '127.0.0.1', port: 0, strictPort: false }, logLevel: 'error' });
const base = `http://127.0.0.1:${server.httpServer.address().port}/`;
await mkdir(out, { recursive: true });
const browser = await playwright.chromium.launch(process.env.PLAYWRIGHT_CHANNEL ? { channel: process.env.PLAYWRIGHT_CHANNEL } : {});
try {
  const index = await browser.newPage();
  await index.goto(base);
  await index.waitForFunction(() => Array.isArray(window.stories));
  const stories = (await index.evaluate(() => window.stories)).filter((s) => ids.includes(s.id));
  await index.close();
  for (const story of stories) {
    const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: 1, locale: 'zh-CN' });
    // the page's clock the run's (Playwright's clock), stopped: its timers and frames (requestAnimationFrame, what moves
    // by script) run only as the run moves it on, PAGE_TIMERS after it opens and after each step, the same each run
    // however fast the machine is; then the animations it runs by CSS ended
    await page.clock.install({ time: CLOCK_AT });
    await page.clock.pauseAt(CLOCK_AT + 1000);
    await page.goto(`${base}?story=${story.id}&theme=light`);
    await page.clock.runFor(PAGE_TIMERS);
    await settled(page);
    const taken = [];
    for (const step of [...(story.steps ?? []), ...(away.get(story.id) ? [{ move: away.get(story.id) }] : [])]) {
      try {
        const at = (selector) => page.locator(selector).filter({ visible: true }).first();
        // where what it acts on is, as it acts (for mbui's app, where it has no such label or words)
        const on = step.text ? page.getByText(step.text, { exact: true }).filter({ visible: true }).first() : step.click || step.rightClick || step.hover ? at(step.click || step.rightClick || step.hover) : null;
        const box = on ? await on.boundingBox({ timeout: 5000 }) : null;
        if (step.click) await at(step.click).click({ timeout: 5000 });
        if (step.rightClick) await at(step.rightClick).click({ button: 'right', timeout: 5000 });
        if (step.hover) await at(step.hover).hover({ timeout: 5000 });
        if (step.text) await page.getByText(step.text, { exact: true }).filter({ visible: true }).first().click({ timeout: 5000 });
        if (step.key) await page.keyboard.press(step.key);
        if (step.move) await page.mouse.move(step.move[0], step.move[1]);
        // what the page does on its clock after a step (the folded sidebar shown a while folds again 400 ms after the
        // pointer has left it: Rail.tsx PEEK_LEAVE, and moves as it folds), then its CSS animations ended
        await page.clock.runFor(PAGE_TIMERS);
        await settled(page);
        taken.push(box ? { ...step, at: [box.x + box.width / 2, box.y + box.height / 2] } : step);
      } catch (e) {
        console.log(`${story.id}: step ${JSON.stringify(step)} not taken (${e.message.split('\n')[0]})`);
      }
    }
    await page.evaluate(() => window.endDemo?.());
    await page.clock.runFor(PAGE_TIMERS);
    await settled(page);
    // what runs on without end (a spinner, an activity's ring turning) held at its start: one picture, one set of boxes
    await page.evaluate(() => {
      for (const a of document.getAnimations()) if (a.effect?.getComputedTiming().endTime === Infinity) { a.pause(); a.currentTime = 0; }
    });
    await page.screenshot({ path: `${out}/${story.id}.web.png` });
    const tape = await page.evaluate((extra) => window.demoTape(extra), extra);
    const els = await page.evaluate(elements);
    // what is behind everything: the root's ground, else the body's, else the window's white
    const ground = await page.evaluate(() => {
      const c = [document.documentElement, document.body].map((e) => getComputedStyle(e).backgroundColor).find((c) => c && c !== 'rgba(0, 0, 0, 0)' && c !== 'transparent') || 'rgb(255, 255, 255)';
      const [r, g, b, a = 1] = c.match(/[\d.]+/g).map(Number);
      return [r, g, b, Math.round(a * 255)];
    });
    await writeFile(`${out}/${story.id}.web.json`, JSON.stringify({ story: story.id, title: story.title, width, height, ground, steps: taken, tape, elements: els }));
    console.log(`took ${out}/${story.id}.web.json: ${els.length} elements, ${tape.length} topics`);
    await page.close();
  }
} finally {
  await browser.close();
  server.httpServer.close();
}
