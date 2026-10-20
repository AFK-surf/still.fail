// The stories (web/stories, `pnpm stories`): the parts of the app in each of their states on made-up data, for people
// to look at and the tests to measure (test/browser/stories.mjs). The site's demo's build, rooted at web/stories, never
// built into anything shipped. Its class names are the readable ones even when built (the tests build it, and know a
// panel's edge or the switcher by their names: test/browser/measure.mjs).
import { vanillaExtractPlugin } from "@vanilla-extract/vite-plugin";
import { fileURLToPath } from "node:url";
import { mergeConfig, type PluginOption } from "vite";
import demo from "./vite.demo.config.ts";

const here = (path: string) => fileURLToPath(new URL(path, import.meta.url));
const named = (p: PluginOption): boolean => !!p && typeof p === "object" && "name" in p && p.name.includes("vanilla-extract");
const plugins = (demo.plugins ?? []).flat(Infinity as 1).filter((p) => !named(p));
export default mergeConfig({ ...demo, plugins: [...plugins, vanillaExtractPlugin({ identifiers: "debug" })] }, { root: here("stories"), server: { port: 5199 } });
