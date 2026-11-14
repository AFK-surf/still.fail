// Everything a self-hosted still.fail cloud runs, into one directory (README.md): workerd (the `workerd` package's
// binary, pinned in package.json), the Workers bundled as wrangler bundles them, the config (config.ts), the static
// sites (`pnpm run build:cloud`'s dist/cloud-web, -admin, -preview: built first unless --sites-built) and `run`, which
// starts it with its directories and addresses.
//   node selfhost/build.ts [--out DIR] [--sites-built | --no-sites]       (default DIR: ../dist/selfhost)
// (--no-sites: the sites' directories empty, a cloud of the API alone: side/selfhost.test.ts's)
import { build } from "esbuild";
import { execFileSync } from "node:child_process";
import { chmodSync, cpSync, existsSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { join, resolve } from "node:path";
import { parseArgs } from "node:util";
import { SITES, workerdConfig } from "./config.ts";

const CLOUD = join(import.meta.dirname, "..");
const REPO = join(CLOUD, "..");
const { values } = parseArgs({ options: { out: { type: "string" }, "sites-built": { type: "boolean" }, "no-sites": { type: "boolean" } } });
const out = resolve(values.out ?? join(REPO, "dist", "selfhost"));

/** The Workers, by the file the config embeds. */
const WORKERS: Record<string, string> = {
  "api.js": "src/index.ts",
  "router.js": "selfhost/router.ts",
  "static.js": "selfhost/static.ts",
  "releases.js": "selfhost/releases.ts",
  "mail.js": "selfhost/mail.ts",
  "setup.js": "selfhost/setup.ts",
};

/** workerd's binary for this machine, as the `workerd` package installed it. */
function workerdBinary(): string {
  const arch = { x64: "64", arm64: "arm64" }[process.arch as string];
  if (!arch || !["linux", "darwin"].includes(process.platform)) throw new Error(`no workerd for ${process.platform}-${process.arch}`);
  const from = createRequire(createRequire(join(CLOUD, "package.json")).resolve("workerd/package.json"));
  return from.resolve(`@cloudflare/workerd-${process.platform}-${arch}/bin/workerd`);
}

if (!values["sites-built"] && !values["no-sites"]) execFileSync("pnpm", ["run", "build:cloud"], { cwd: REPO, stdio: "inherit" });
for (const site of Object.keys(SITES)) if (!values["no-sites"] && !existsSync(join(REPO, "dist", `cloud-${site}`, "index.html")) && site !== "preview") throw new Error(`no dist/cloud-${site}: pnpm run build:cloud`);

rmSync(out, { recursive: true, force: true });
mkdirSync(join(out, "workers"), { recursive: true });
mkdirSync(join(out, "bin"));
for (const [file, entry] of Object.entries(WORKERS)) {
  await build({
    entryPoints: [join(CLOUD, entry)],
    outfile: join(out, "workers", file),
    bundle: true,
    format: "esm",
    platform: "node",
    target: "es2024",
    // (as wrangler's nodejs_compat: Node's modules are the runtime's own)
    banner: { js: 'import { createRequire } from "node:module"; const require = createRequire("file:///worker.js");' },
    external: ["cloudflare:workers", "cloudflare:sockets", "node:*"],
    conditions: ["workerd", "worker", "browser"],
    logLevel: "warning",
  });
}
for (const site of Object.keys(SITES)) {
  if (values["no-sites"]) mkdirSync(join(out, "sites", site), { recursive: true });
  else cpSync(join(REPO, "dist", `cloud-${site}`), join(out, "sites", site), { recursive: true });
}
cpSync(workerdBinary(), join(out, "bin", "workerd"));
chmodSync(join(out, "bin", "workerd"), 0o755);
writeFileSync(join(out, "config.capnp"), workerdConfig());
cpSync(join(import.meta.dirname, "run"), join(out, "run"));
chmodSync(join(out, "run"), 0o755);
cpSync(join(import.meta.dirname, "cloud.env.example"), join(out, "cloud.env.example"));
console.log(`self-hosted cloud in ${out}`);
