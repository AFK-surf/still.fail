// Which cloud and relays a build of the share host is for (src/share.ts): the page asks that cloud for the relays
// (web/vite.share.config.ts builds it in), and its headers let it talk to those (build-static.ts writes them).
// still.fail's own by default, as the API's wrangler.jsonc says: PUBLIC_ORIGIN, and the relays as src/relays.ts lists
// them (RELAY_URL or PUBLIC_ORIGIN, then RELAY_URLS). The web app has one build for both channels and so does this:
// the test channel's API is the same Worker, with the same relays. A dev cloud (cloud/test/dev.ts) says its own:
//   STILLFAIL_SHARE_CLOUD=http://127.0.0.1:8877 STILLFAIL_SHARE_RELAYS=http://127.0.0.1:3340 pnpm run build:cloud
import { readFileSync } from "node:fs";
import type { ShareHosts } from "./src/share.ts";

type Vars = { PUBLIC_ORIGIN: string; RELAY_URL?: string; RELAY_URLS?: string };

/** The API's vars, from its wrangler.jsonc (comment lines and trailing commas dropped, as deploy.py reads it). */
function apiVars(): Vars {
  const text = readFileSync(new URL("./wrangler.jsonc", import.meta.url), "utf8").replace(/^\s*\/\/.*$/gm, "").replace(/,(\s*[}\]])/g, "$1");
  return (JSON.parse(text) as { vars: Vars }).vars;
}

const list = (...parts: (string | undefined)[]) => [...new Set(parts.flatMap((p) => (p ?? "").split(",")).map((u) => u.trim()).filter(Boolean))];

export function shareHosts(env: Record<string, string | undefined> = process.env): ShareHosts {
  if (env.STILLFAIL_SHARE_CLOUD) return { cloud: env.STILLFAIL_SHARE_CLOUD, relays: list(env.STILLFAIL_SHARE_RELAYS) };
  const vars = apiVars();
  return { cloud: vars.PUBLIC_ORIGIN, relays: list(vars.RELAY_URL || vars.PUBLIC_ORIGIN, vars.RELAY_URLS) };
}
