// The web app's stories (web/stories/stories.tsx) at a desktop's sizes, light and dark: what the wide frame is held
// against (the reference the PC layout follows). Builds the stories as test/browser/stories.mjs does, serves the build
// and takes each story, its steps taken, at each size.
//   node apps/mbui/scripts/web-ref.mjs OUT [STORY,…] [WxH,…]
// (from the repository's root, its packages installed; PLAYWRIGHT_MODULE picks Playwright, e.g. apps/mbui's
// out/node/node_modules/playwright)
import { mkdir, mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { build, preview } from 'vite';

const playwright = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');

// The page as it will stay: loaded (its network quiet), its fonts in, and every animation it runs that ends (a CSS
// transition, an animation with a count) ended, by the animations' own `finished`: what the picture waits for, not a
// time. (A spinner's endless one is left running.)
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
const out = process.argv[2] || 'out/web-ref';
const ids = (process.argv[3] || 'app-chat,app-new-chat,app-todo,app-files,settings-appearance').split(',');
const sizes = (process.argv[4] || '1280x800,1440x900').split(',').map((s) => s.split('x').map(Number));
const configFile = fileURLToPath(new URL('../../../web/vite.stories.config.ts', import.meta.url));
const dist = await mkdtemp(join(tmpdir(), 'web-ref-'));
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
    for (const [width, height] of sizes) {
      for (const theme of ['light', 'dark']) {
        const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: 1, locale: 'zh-CN' });
        await page.goto(`${base}?story=${story.id}&theme=${theme}`);
        await settled(page);
        for (const step of story.steps ?? []) {
          try {
            const at = (selector) => page.locator(selector).filter({ visible: true }).first();
            if (step.click) await at(step.click).click({ timeout: 5000 });
            if (step.rightClick) await at(step.rightClick).click({ button: 'right', timeout: 5000 });
            if (step.hover) await at(step.hover).hover({ timeout: 5000 });
            if (step.text) await page.getByText(step.text, { exact: true }).filter({ visible: true }).first().click({ timeout: 5000 });
            if (step.key) await page.keyboard.press(step.key);
            if (step.move) await page.mouse.move(step.move[0], step.move[1]);
            await settled(page);
          } catch (e) {
            console.log(`${story.id}: step ${JSON.stringify(step)} not taken (${e.message.split('\n')[0]})`);
          }
        }
        await page.evaluate(() => window.endDemo?.());
        await settled(page);
        const name = `${out}/${story.id}-${width}x${height}-${theme}.png`;
        await page.screenshot({ path: name });
        console.log(`took ${name}`);
        await page.close();
      }
    }
  }
} finally {
  await browser.close();
  server.httpServer.close();
}
