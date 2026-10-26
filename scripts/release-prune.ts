// The releases bucket keeps, of the desktop and Android apps, the installer each feed names and any newer (a release
// whose files are put but whose feed is not yet, scripts/release-put.sh); of the betas also the newest 5 installers
// (zip, exe, apk) and 30 .blockmap/.sig. Older installers are deleted, and older beta blockmaps; a stable release's
// blockmaps all stay (a few hundred KB each). A desktop app updates from the version it runs by fetching that
// version's blockmap (when it has not kept it) and the new file's changed blocks: no old installer is needed, so a beta
// up to 30 releases behind still updates by difference. The beta desktop app's web archives (docs/desktop-web-updates.md):
// the one its feed names, any newer, and the newest 5. What a station's job staged (staged/<when>-<commit>/:
// scripts/release-put.sh --stage) and no put took back and deleted: after two days. The stations', Node and the feeds
// are never touched.
// CI runs it after `put` (.github/workflows/pipeline.yml).
//   node scripts/release-prune.ts [--dry-run]
// Needs CLOUDFLARE_API_TOKEN (and CLOUDFLARE_ACCOUNT_ID, else the token's first account).

const BUCKET = "stillfail-releases";
const FEEDS = [
  "desktop/stillfail-beta-mac.yml", "desktop/stillfail-beta.yml", "android/beta/latest.json",
  "desktop/stillfail-mac.yml", "desktop/stillfail.yml", "android/latest.json", "android/mbui/latest.json", "mac/mbui/latest.json",
  "mac/latest.json", "mac/beta/latest.json", "win/mbui/latest.json", "win/latest.json", "win/beta/latest.json",
];
/** An installer: its name before and after the version, and the version; then .blockmap or .sig when it is one. */
const INSTALLER = /^((?:desktop|android|mac|win)\/stillfail-(?:beta-|mbui-)?)(\d+(?:\.\d+\.\d+)?)(-[\w-]+\.(?:zip|exe)|\.apk)(\.blockmap|\.sig)?$/;
/** How many of a beta's newest installers, and of its blockmaps, stay. */
const BETA_INSTALLERS = 5;
const BETA_BLOCKMAPS = 30;
/** The beta desktop app's web app: its feed, its archives, and how many of the newest stay. */
const WEB_FEED = "desktop/web/stillfail-beta-web.json";
const WEB_ARCHIVE = /^desktop\/web\/stillfail-beta-web-0\.1\.(\d+)\.tar\.gz$/;
const WEB_ARCHIVES = 5;
/** What a station's job staged, by when (seconds since 1970), and how long it may stay there. */
const STAGED = /^staged\/(\d+)-/;
const STAGED_SECONDS = 2 * 24 * 3600;

const dryRun = process.argv.includes("--dry-run");
const token = process.env.CLOUDFLARE_API_TOKEN;
if (!token) throw new Error("CLOUDFLARE_API_TOKEN is not set");

async function api(path: string, init: RequestInit = {}): Promise<Response> {
  for (let attempt = 1; ; attempt++) {
    const response = await fetch(`https://api.cloudflare.com/client/v4${path}`, {
      ...init, headers: { Authorization: `Bearer ${token}` },
    });
    if (response.ok || response.status === 404 || attempt === 3) return response;
    await new Promise((r) => setTimeout(r, 5000));
  }
}
async function json(path: string): Promise<any> {
  const response = await api(path);
  if (!response.ok) throw new Error(`${path}: ${response.status} ${await response.text()}`);
  return response.json();
}

const account = process.env.CLOUDFLARE_ACCOUNT_ID || (await json("/accounts")).result[0].id;
const objects = `/accounts/${account}/r2/buckets/${BUCKET}/objects`;

const keys: string[] = [];
for (let cursor = ""; ;) {
  const page = await json(`${objects}?per_page=1000${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ""}`);
  keys.push(...page.result.map((o: { key: string }) => o.key));
  cursor = page.result_info?.cursor ?? "";
  if (!page.result_info?.is_truncated || !cursor) break;
}

const older = (a: string, b: string) => {
  const [x, y] = [a.split(".").map(Number), b.split(".").map(Number)];
  for (let i = 0; i < Math.max(x.length, y.length); i++) if ((x[i] ?? 0) !== (y[i] ?? 0)) return (x[i] ?? 0) < (y[i] ?? 0);
  return false;
};
/** An installer's group (its name without the version), version, and whether it is the installer's blockmap or .sig. */
const installer = (key: string) => {
  const m = key.match(INSTALLER);
  // (still.fail mbui's, android/stillfail-mbui-<n>.apk, kept as a beta's)
  return m ? { group: m[1]! + m[3]!, version: m[2]!, beta: m[1]!.endsWith("beta-") || m[1]!.endsWith("mbui-"), map: !!m[4] } : null;
};

// The version each feed names, by group. The desktop's feeds name the file without its directory.
const current = new Map<string, string>();
for (const feed of FEEDS) {
  const response = await api(`${objects}/${feed}`);
  if (response.status === 404) continue;
  if (!response.ok) throw new Error(`${feed}: ${response.status}`);
  for (const m of (await response.text()).matchAll(/[\w.\/-]+\.(?:zip|exe|apk)/g)) {
    const named = installer(m[0].includes("/") ? m[0] : `${feed.split("/")[0]}/${m[0]}`);
    if (named) current.set(named.group, named.version);
  }
}

// The versions of each kind of file (an installer, its blockmap, its .sig), newest first.
const kind = (key: string, file: { group: string }) => file.group + (key.match(/\.(blockmap|sig)$/)?.[0] ?? "");
const versions = new Map<string, string[]>();
for (const key of keys) {
  const file = installer(key);
  if (file) versions.set(kind(key, file), [...(versions.get(kind(key, file)) ?? []), file.version]);
}
for (const list of versions.values()) list.sort((a, b) => (older(a, b) ? 1 : older(b, a) ? -1 : 0));

// The web archives: the build the feed names (none: the feed is not out yet, and nothing goes).
const webFeed = await api(`${objects}/${WEB_FEED}`);
if (!webFeed.ok && webFeed.status !== 404) throw new Error(`${WEB_FEED}: ${webFeed.status}`);
const webNamed = webFeed.ok ? Number((await webFeed.json()).build) : null;
const webBuilds = keys.map((key) => Number(key.match(WEB_ARCHIVE)?.[1])).filter((n) => Number.isSafeInteger(n)).sort((a, b) => b - a);

const doomed = keys.filter((key) => {
  const staged = Number(key.match(STAGED)?.[1]);
  if (Number.isSafeInteger(staged)) return staged < Date.now() / 1000 - STAGED_SECONDS;
  const web = Number(key.match(WEB_ARCHIVE)?.[1]);
  if (Number.isSafeInteger(web)) return webNamed !== null && web < webNamed && webBuilds.indexOf(web) >= WEB_ARCHIVES;
  const file = installer(key);
  const named = file && current.get(file.group);
  if (!file || !named || !older(file.version, named)) return false;
  if (!file.beta) return !file.map;
  return versions.get(kind(key, file))!.indexOf(file.version) >= (file.map ? BETA_BLOCKMAPS : BETA_INSTALLERS);
});

console.log(`${keys.length} files, ${doomed.length} old installers, blockmaps and staged files to delete`);
if (dryRun) {
  for (const key of doomed) console.log(`  ${key}`);
  process.exit(0);
}
let failed = 0;
for (let i = 0; i < doomed.length; i += 8) {
  await Promise.all(doomed.slice(i, i + 8).map(async (key) => {
    const response = await api(`${objects}/${key}`, { method: "DELETE" });
    if (!response.ok && response.status !== 404) { failed++; console.error(`deleting ${key}: ${response.status}`); }
  }));
}
console.log(`deleted ${doomed.length - failed}`);
if (failed) process.exit(1);
