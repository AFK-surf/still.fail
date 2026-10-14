// The releases bucket keeps, of the desktop and Android apps, only the installers that can still be downloaded: the one
// each feed names and any newer (a release whose files are put but whose feed is not yet, scripts/release-put.sh).
// Older installers (zip, exe, apk) are deleted; their .blockmap and .sig stay (a few hundred KB each), since a desktop
// app updates from the version it runs by fetching that version's blockmap (when it has not kept it) and the new
// file's changed blocks: no old installer is needed. The stations', Node and the feeds are never touched.
// CI runs it after `put` (.github/workflows/pipeline.yml).
//   node scripts/release-prune.ts [--dry-run]
// Needs CLOUDFLARE_API_TOKEN (and CLOUDFLARE_ACCOUNT_ID, else the token's first account).

const BUCKET = "stillfail-releases";
const FEEDS = [
  "desktop/stillfail-beta-mac.yml", "desktop/stillfail-beta.yml", "android/beta/latest.json",
  "desktop/stillfail-mac.yml", "desktop/stillfail.yml", "android/latest.json",
];
/** An installer: its name before and after the version, and the version. */
const INSTALLER = /^((?:desktop|android)\/stillfail-(?:beta-)?)(\d+(?:\.\d+\.\d+)?)(-[\w-]+\.(?:zip|exe)|\.apk)$/;

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
/** An installer's group (its name without the version) and version. */
const installer = (key: string) => {
  const m = key.match(INSTALLER);
  return m ? { group: m[1]! + m[3]!, version: m[2]! } : null;
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

const doomed = keys.filter((key) => {
  const file = installer(key);
  const named = file && current.get(file.group);
  return !!named && older(file!.version, named);
});

console.log(`${keys.length} files, ${doomed.length} installers older than their feed's to delete`);
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
