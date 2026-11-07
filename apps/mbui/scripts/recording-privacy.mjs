import { lstatSync, readFileSync, readlinkSync, realpathSync } from "node:fs";
import { basename, dirname, isAbsolute, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

export function recordingRealPath(path = "") {
  if (!path) return "";
  // Keep dot segments until after realpath: a symlink followed by .. is resolved by the filesystem, not lexically.
  let current = isAbsolute(path) ? path : `${process.cwd()}/${path}`;
  const missing = [];
  while (true) {
    try { return join(realpathSync(current), ...missing.reverse()); } catch { /* A station may not exist yet. */ }
    const parent = dirname(current);
    if (parent === current) return "";
    missing.push(basename(current));
    current = parent;
  }
}

// Keep each spelling reached by following a known symlink, including intermediate spellings such as /var and
// /private/var on macOS. Do not guess unrelated aliases: fail if the known links expand without a finite bound.
export function recordingPathAliases(path = "") {
  if (!path) return [];
  const original = isAbsolute(path) ? path : `${process.cwd()}/${path}`;
  const components = [];
  for (const part of original.split("/")) {
    if (!part || part === ".") continue;
    if (part === "..") {
      if (components.length) {
        let previous;
        try { previous = lstatSync(`/${components.join("/")}`); } catch { throw new Error("cannot validate path containing dot segments"); }
        if (previous.isSymbolicLink()) throw new Error("ambiguous path containing dot segments");
        components.pop();
      }
    } else {
      components.push(part);
    }
  }
  const normalized = resolve(path);
  const real = recordingRealPath(original);
  // A link followed by .. can make lexical normalization name a different file. Refuse that configuration.
  if (original !== normalized && real !== recordingRealPath(normalized)) throw new Error("ambiguous path containing dot segments");
  const pending = [original, normalized];
  const seen = new Set();
  while (pending.length) {
    const candidate = pending.shift();
    if (seen.has(candidate)) continue;
    if (seen.size >= 128) throw new Error("too many symlink path aliases");
    seen.add(candidate);
    const parts = candidate.split("/").filter(Boolean);
    for (let i = 0; i < parts.length; i++) {
      const prefix = join("/", ...parts.slice(0, i + 1));
      let target;
      try {
        if (!lstatSync(prefix).isSymbolicLink()) continue;
        target = readlinkSync(prefix);
      } catch { continue; }
      pending.push(resolve(dirname(prefix), target, ...parts.slice(i + 1)));
    }
  }
  if (real) seen.add(real);
  return [...seen];
}

// Find the spelling of the work directory used by a station under a symlink, if any. The station itself may not
// exist yet, so inspect its parents too. Both spellings must be scrubbed to the same path in a recording.
export function stationWorkAlias(work = "", station = "") {
  if (!work || !station) return "";
  const actualWork = recordingRealPath(work);
  if (!actualWork) return "";
  let path = resolve(station);
  while (true) {
    try { if (realpathSync(path) === actualWork) return path; } catch { /* An uncreated station has existing parents. */ }
    const parent = dirname(path);
    if (parent === path) return "";
    path = parent;
  }
}

// These must be the paths of the run that produced the log, not guessed values for another run.
export function validateRecordingContext(work = "", station = "") {
  for (const path of [work, station]) {
    if (!path || !isAbsolute(path) || resolve(path) === "/" || recordingRealPath(path) === "/") {
      throw new Error("invalid recording path context");
    }
    recordingPathAliases(path);
  }
}

// Check the raw paths and the test work path after home has been replaced. The latter catches a partial scrub.
export function containsLocalInformation(text, { home = "", work = "", station = "", workAlias = "", workReal = "", stationReal = "", workPaths = [], stationPaths = [], workspace = "", hostname = "", privateTerms = [] } = {}) {
  const paths = new Set();
  const variants = (p) => {
    if (!p) return [];
    return recordingPathAliases(p).filter((s) => s.length > 1);
  };
  const homes = variants(home);
  const works = [work, workReal, workAlias, stationWorkAlias(work, station), ...workPaths].flatMap(variants);
  const stations = [station, stationReal, ...stationPaths].flatMap(variants);
  for (const path of homes) paths.add(path);
  for (const path of [...works, ...stations]) {
    paths.add(path);
    for (const h of homes) {
      if (path.startsWith(h + "/")) paths.add("/test-home" + path.slice(h.length));
    }
  }
  // The checkout and work directories may have other siblings in a private session directory.
  // Only treat that parent as private when it is actually below home, not home itself or /tmp.
  for (const path of variants(workspace)) {
    for (const h of homes) {
      if (path.startsWith(h + "/")) {
        paths.add(path);
        paths.add("/test-home" + path.slice(h.length));
      }
    }
  }
  if (hostname) paths.add(hostname);
  const needles = [...paths];
  // Station names and other local identifiers can be supplied privately, without putting them in this repository.
  const terms = privateTerms.map((term) => term.trim().toLowerCase()).filter(Boolean);
  const contains = (s) => needles.some((needle) => s.includes(needle)) || terms.some((term) => s.toLowerCase().includes(term));
  const visit = (value, key = "") => {
    if (typeof value === "string") {
      if (contains(value)) return true;
      if (key === "b" && value.length % 2 === 0 && /^[0-9a-f]+$/i.test(value)) {
        const bytes = Buffer.from(value, "hex");
        return needles.some((needle) => bytes.includes(Buffer.from(needle))) || contains(bytes.toString("utf8"));
      }
      return false;
    }
    if (Array.isArray(value)) return value.some((v) => visit(v));
    // Map keys can contain paths too. Reject them rather than changing a key and risking a collision in replay.
    if (value && typeof value === "object") {
      if (key === "host" && Object.hasOwn(value, "localStation") && value.localStation !== null) return true;
      return Object.entries(value).some(([k, v]) => contains(k) || visit(v, k));
    }
    return false;
  };
  return text.split("\n").filter(Boolean).some((line) => visit(JSON.parse(line)));
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    if (process.argv[2] === "--check-context") {
      validateRecordingContext(process.env.E2E_WORK, process.env.E2E_STATION);
    } else if (process.argv[2] === "--work-alias") {
      process.stdout.write(stationWorkAlias(process.env.E2E_WORK, process.env.E2E_STATION));
    } else if (process.argv[2] === "--work-real") {
      process.stdout.write(recordingRealPath(process.env.E2E_WORK));
    } else if (process.argv[2] === "--station-real") {
      process.stdout.write(recordingRealPath(process.env.E2E_STATION));
    } else if (process.argv[2] === "--work-paths") {
      process.stdout.write(JSON.stringify(recordingPathAliases(process.env.E2E_WORK)));
    } else if (process.argv[2] === "--station-paths") {
      process.stdout.write(JSON.stringify(recordingPathAliases(process.env.E2E_STATION)));
    } else {
      const aliasList = (name) => {
        const list = JSON.parse(process.env[name] || "[]");
        if (!Array.isArray(list) || list.some((item) => typeof item !== "string" || !item)) throw new Error("invalid path aliases");
        return list;
      };
      const trace = readFileSync(process.argv[2], "utf8");
      if (containsLocalInformation(trace, {
        home: process.env.HOME,
        work: process.env.E2E_WORK,
        station: process.env.E2E_STATION,
        workAlias: process.env.E2E_WORK_ALIAS,
        workReal: process.env.E2E_WORK_REAL,
        stationReal: process.env.E2E_STATION_REAL,
        workPaths: aliasList("E2E_WORK_PATHS"),
        stationPaths: aliasList("E2E_STATION_PATHS"),
        workspace: dirname(fileURLToPath(new URL("../../..", import.meta.url))),
        hostname: process.argv[3],
        privateTerms: process.env.E2E_PRIVATE_TERMS_FILE ? readFileSync(process.env.E2E_PRIVATE_TERMS_FILE, "utf8").split(/\r?\n/) : [],
      })) process.exitCode = 1;
    }
  } catch {
    // A malformed trace must not pass the check.
    process.exitCode = 1;
  }
}
