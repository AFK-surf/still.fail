// The releases bucket keeps, of the desktop, Android and Linux apps, the installer each feed names and any newer (a
// release whose files are put but whose feed is not yet, scripts/release-put.sh), and the installers (zip, exe, apk,
// tar.gz) its deltas are from: what the next release's deltas are made from (scripts/release-deltas.ts, up to 10 builds
// back, the betas' as the stable apps'; the owner, 2026-11-11). Not the newest N: Android's APK is put for every main
// commit before its feed, so installers that never were a feed would take the places. Of the betas also 30
// .blockmap/.sig. Other older installers are deleted, and older beta blockmaps; a stable release's blockmaps all stay
// (a few hundred KB each). A desktop app updates from the version it runs by fetching that version's blockmap (when it
// has not kept it) and the new file's changed blocks: no old installer is needed, so a beta up to 30 releases behind
// still updates by difference. A Windows installer's raw form (.raw.zst) stays as long as its installer. A delta
// (….from-<n>.delta) stays while its feed offers it (and when it is newer than what the feed names: being put); the
// station's archives kept under their own names (station/archive/<channel>/…) while their channel's feed names them,
// as its build or a base of its deltas (or are newer than it), and its deltas while it offers them. The web archives
// the beta Electron app took without a new app (made until 2026-10-26, when that app was moved to mbui's): the one its
// feed names, any newer, and the newest 5. What a station's job staged (staged/<when>-<commit>/: scripts/release-put.sh
// --stage) and no put took back and deleted: after two days. An Android release's native symbols (symbols/android/…:
// scripts/release.sh, read by scripts/crash-symbols.ts) once older than 30 days by the time the bucket says it was put
// (its listing's last_modified; the owner, 2026-11-11): one whose time cannot be read stays. The stations' own names,
// Node and the feeds are never touched.
// CI runs it after `put` (.github/workflows/pipeline.yml).
//   node scripts/release-prune.ts [--dry-run]
// Needs CLOUDFLARE_API_TOKEN (and CLOUDFLARE_ACCOUNT_ID, else the token's first account).

import { baseFile } from "./release-deltas.ts";

const BUCKET = "stillfail-releases";
export const FEEDS = [
  "desktop/stillfail-beta-mac.yml", "desktop/stillfail-beta.yml", "android/beta/latest.json",
  "desktop/stillfail-mac.yml", "desktop/stillfail.yml", "android/latest.json", "android/mbui/latest.json", "mac/mbui/latest.json",
  "mac/latest.json", "mac/beta/latest.json", "win/mbui/latest.json", "win/latest.json", "win/beta/latest.json",
  "linux/mbui/latest.json", "linux-arm64/mbui/latest.json", "station.json", "station-beta.json",
];
/** An installer: its name before and after the version, and the version; then what goes with it (.blockmap, .sig, its
 * raw form, a delta to it) when it is one. */
const INSTALLER = /^((?:desktop|android|mac|win|linux)\/stillfail-(?:beta-|mbui-)?)(\d+(?:\.\d+\.\d+)?)(-[\w-]+\.(?:zip|exe|tar\.gz)|\.apk)(\.blockmap|\.sig|\.raw\.zst|\.from-\d+\.delta)?$/;
/** How many of a beta's newest blockmaps and .sigs stay. */
const BETA_BLOCKMAPS = 30;
/** The beta Electron app's web app: its feed, its archives, and how many of the newest stay. */
const WEB_FEED = "desktop/web/stillfail-beta-web.json";
const WEB_ARCHIVE = /^desktop\/web\/stillfail-beta-web-0\.\d+\.(\d+)\.tar\.gz$/;
const WEB_ARCHIVES = 5;
/** What a station's job staged, by when (seconds since 1970), and how long it may stay there. */
const STAGED = /^staged\/(\d+)-/;
const STAGED_SECONDS = 2 * 24 * 3600;
/** An Android release's symbols, and how long they stay after they were put. */
const SYMBOLS = /^symbols\//;
const SYMBOLS_SECONDS = 30 * 24 * 3600;
/** The station's archives under their own names, and their deltas (scripts/release-deltas.ts). */
const STATION_ARCHIVE = /^station\/archive\/(stable|beta)\/(\d+)-([0-9a-f]{64})-([a-z0-9-]+?)(\.tar\.gz|\.zip|\.from-\d+-[0-9a-f]{16}\.delta)$/;

const older = (a: string, b: string) => {
  const [x, y] = [a.split(".").map(Number), b.split(".").map(Number)];
  for (let i = 0; i < Math.max(x.length, y.length); i++) if ((x[i] ?? 0) !== (y[i] ?? 0)) return (x[i] ?? 0) < (y[i] ?? 0);
  return false;
};
/** An installer's group (its name without the version), version, and what it is beside an installer. */
const installer = (key: string) => {
  const m = key.match(INSTALLER);
  // (still.fail mbui's, android/stillfail-mbui-<n>.apk, kept as a beta's)
  return m ? { group: m[1]! + m[3]!, version: m[2]!, beta: m[1]!.endsWith("beta-") || m[1]!.endsWith("mbui-"), extra: m[4] ?? "" } : null;
};


/** Of the apps' feeds: the version each names, by group (the desktop's feeds name the file without its directory),
 * every delta one offers, and the versions of the installers its deltas are from, by group. */
const appFeeds = (feeds: Record<string, string>) => {
  const current = new Map<string, string>();
  const offered = new Set<string>();
  const bases = new Map<string, Set<string>>();
  for (const feed of FEEDS) {
    const text = feeds[feed];
    if (text === undefined || feed.startsWith("station")) continue;
    // (a name ending there: not a delta's nor a raw form's, which name the installer at their start)
    for (const m of text.matchAll(/[\w.\/-]+?\.(?:zip|exe|apk|tar\.gz)(?=[^\w.\/-]|$)/g)) {
      const named = installer(m[0].includes("/") ? m[0] : `${feed.split("/")[0]}/${m[0]}`);
      if (named) current.set(named.group, named.version);
    }
    for (const m of text.matchAll(/[\w.\/-]+\.delta/g)) offered.add(m[0]);
    if (!feed.endsWith(".json")) continue;
    let f: any;
    try { f = JSON.parse(text); } catch { continue; }
    if (!Number.isSafeInteger(f?.versionCode) || typeof f.file !== "string" || !Array.isArray(f.deltas)) continue;
    for (const d of f.deltas) {
      const base = Number.isSafeInteger(d?.from) ? installer(baseFile(f.file, f.versionCode, d.from)) : null;
      if (base) bases.set(base.group, (bases.get(base.group) ?? new Set()).add(base.version));
    }
  }
  return { current, offered, bases };
};

/** The installers of `keys` newer than the version their feed names (a release being put, or never to be a feed). */
export function aheadOf(keys: string[], feeds: Record<string, string>): string[] {
  const { current } = appFeeds(feeds);
  return keys.filter((key) => {
    const file = installer(key);
    const named = file?.extra === "" && current.get(file.group);
    return !!named && older(named, file!.version);
  });
}

/**
 * Which of the bucket's `keys` go: `feeds` the feeds' text by name (a feed not there: absent), `webNamed` the build the
 * web archives' feed names, `now` seconds since 1970, `putAt` when each key was put by the bucket's word (seconds since
 * 1970; a key without one: not known).
 */
export function doomedOf(keys: string[], feeds: Record<string, string>, webNamed: number | null, now: number, putAt: ReadonlyMap<string, number> = new Map()): string[] {
  const { current, offered, bases } = appFeeds(feeds);
  // The station's feeds: by channel, the build each names, the archives (by sha256) it names as its own or as a base
  // of its deltas, and its deltas.
  const station = new Map<string, { build: number; named: Set<string>; deltas: Set<string> }>();
  for (const [feed, channel] of [["station.json", "stable"], ["station-beta.json", "beta"]] as const) {
    const text = feeds[feed];
    if (text === undefined) continue;
    try {
      const f = JSON.parse(text), words = JSON.parse(Buffer.from(f.release, "base64").toString("utf8"));
      const named = new Set<string>(Object.values(words.builds ?? {}).map((b: any) => String(b.sha256)));
      const deltas = new Set<string>();
      for (const list of Object.values(f.deltas ?? {})) for (const d of list as any[]) { named.add(String(d.base)); deltas.add(String(d.file)); }
      station.set(channel, { build: Number(words.build), named, deltas });
    } catch {
      // (a feed not read as one: nothing of its channel goes)
      station.set(channel, { build: Infinity, named: new Set(), deltas: new Set() });
    }
  }

  // The versions of each installer's blockmaps and of its .sigs, newest first.
  const kind = (file: { group: string; extra: string }) => file.group + file.extra;
  const versions = new Map<string, string[]>();
  for (const key of keys) {
    const file = installer(key);
    if (file && (file.extra === ".blockmap" || file.extra === ".sig")) versions.set(kind(file), [...(versions.get(kind(file)) ?? []), file.version]);
  }
  for (const list of versions.values()) list.sort((a, b) => (older(a, b) ? 1 : older(b, a) ? -1 : 0));
  const webBuilds = keys.map((key) => Number(key.match(WEB_ARCHIVE)?.[1])).filter((n) => Number.isSafeInteger(n)).sort((a, b) => b - a);

  return keys.filter((key) => {
    const staged = Number(key.match(STAGED)?.[1]);
    if (Number.isSafeInteger(staged)) return staged < now - STAGED_SECONDS;
    if (SYMBOLS.test(key)) {
      const put = putAt.get(key);
      return put !== undefined && Number.isFinite(put) && put < now - SYMBOLS_SECONDS;
    }
    const web = Number(key.match(WEB_ARCHIVE)?.[1]);
    if (Number.isSafeInteger(web)) return webNamed !== null && web < webNamed && webBuilds.indexOf(web) >= WEB_ARCHIVES;
    const archive = key.match(STATION_ARCHIVE);
    if (archive) {
      const feed = station.get(archive[1]!);
      if (!feed || Number(archive[2]) > feed.build) return false;
      return archive[5]!.endsWith(".delta") ? !feed.deltas.has(key) : !feed.named.has(archive[3]!);
    }
    const file = installer(key);
    const named = file && current.get(file.group);
    if (!file || !named || !older(file.version, named)) {
      // (a delta to the build its feed names that the feed does not offer: made by a run before this one's)
      return !!file && !!named && file.extra.endsWith(".delta") && file.version === named && !offered.has(key);
    }
    if (file.extra.endsWith(".delta")) return true;
    if (file.extra === ".blockmap" || file.extra === ".sig") {
      if (!file.beta) return false;
      return versions.get(kind(file))!.indexOf(file.version) >= BETA_BLOCKMAPS;
    }
    // (an installer, and its raw form with it: a base of its feed's deltas stays)
    return !bases.get(file.group)?.has(file.version);
  });
}

if (import.meta.main) {
  const dryRun = process.argv.includes("--dry-run");
  const token = process.env.CLOUDFLARE_API_TOKEN;
  if (!token) throw new Error("CLOUDFLARE_API_TOKEN is not set");

  const api = async (path: string, init: RequestInit = {}): Promise<Response> => {
    for (let attempt = 1; ; attempt++) {
      const response = await fetch(`https://api.cloudflare.com/client/v4${path}`, {
        ...init, headers: { Authorization: `Bearer ${token}` },
      });
      if (response.ok || response.status === 404 || attempt === 3) return response;
      await new Promise((r) => setTimeout(r, 5000));
    }
  };
  const json = async (path: string): Promise<any> => {
    const response = await api(path);
    if (!response.ok) throw new Error(`${path}: ${response.status} ${await response.text()}`);
    return response.json();
  };

  const account = process.env.CLOUDFLARE_ACCOUNT_ID || (await json("/accounts")).result[0].id;
  const objects = `/accounts/${account}/r2/buckets/${BUCKET}/objects`;

  // (each object's last_modified, an ISO 8601 time, when it was written: Cloudflare's R2 List Objects; one not read as a
  // time is left out of putAt, and what goes by it stays)
  const keys: string[] = [];
  const putAt = new Map<string, number>();
  for (let cursor = ""; ;) {
    const page = await json(`${objects}?per_page=1000${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ""}`);
    for (const o of page.result as { key: string; last_modified?: unknown }[]) {
      keys.push(o.key);
      const put = typeof o.last_modified === "string" ? Date.parse(o.last_modified) / 1000 : NaN;
      if (Number.isFinite(put)) putAt.set(o.key, put);
    }
    cursor = page.result_info?.cursor ?? "";
    if (!page.result_info?.is_truncated || !cursor) break;
  }

  const feeds: Record<string, string> = {};
  for (const feed of FEEDS) {
    const response = await api(`${objects}/${feed}`);
    if (response.status === 404) continue;
    if (!response.ok) throw new Error(`${feed}: ${response.status}`);
    feeds[feed] = await response.text();
  }
  // The web archives: the build the feed names (none: the feed is not out yet, and nothing goes).
  const webFeed = await api(`${objects}/${WEB_FEED}`);
  if (!webFeed.ok && webFeed.status !== 404) throw new Error(`${WEB_FEED}: ${webFeed.status}`);
  const webNamed = webFeed.ok ? Number((await webFeed.json()).build) : null;

  const doomed = doomedOf(keys, feeds, webNamed, Date.now() / 1000, putAt);
  // (said each, so that what goes can be read from CI's log)
  for (const key of aheadOf(keys, feeds)) console.log(`above its feed: ${key}`);
  console.log(`${keys.length} files, ${doomed.length} old installers, deltas, blockmaps, archives, staged files and symbols to delete`);
  for (const key of doomed) console.log(`  ${key}`);
  if (dryRun) process.exit(0);
  let failed = 0;
  for (let i = 0; i < doomed.length; i += 8) {
    await Promise.all(doomed.slice(i, i + 8).map(async (key) => {
      const response = await api(`${objects}/${key}`, { method: "DELETE" });
      if (!response.ok && response.status !== 404) { failed++; console.error(`deleting ${key}: ${response.status}`); }
    }));
  }
  console.log(`deleted ${doomed.length - failed}`);
  if (failed) process.exit(1);
}
