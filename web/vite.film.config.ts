// The promo film's panes (web/film): the site's demo app with the film's story in place of its own, built as one page
// (film/record.mjs builds it and films it). Never built into anything shipped.
import { fileURLToPath } from "node:url";
import { mergeConfig, type Plugin } from "vite";
import demo from "./vite.demo.config.ts";

const here = (path: string) => fileURLToPath(new URL(path, import.meta.url));
/** The demo's story (src/demo/story.ts), as mount.tsx imports it: the film's. */
const story: Plugin = {
  name: "film-story",
  enforce: "pre",
  resolveId: (source, importer) => (source === "./story.ts" && importer?.endsWith("/demo/mount.tsx") ? here("film/story.ts") : null),
};
export default mergeConfig({ ...demo, plugins: [story, ...(demo.plugins ?? [])], build: {} }, {
  root: here("film"),
  build: { outDir: here("../dist/film"), emptyOutDir: true, target: "es2022", cssCodeSplit: false, rollupOptions: { input: { index: here("film/index.html") }, output: { codeSplitting: false } } },
});
