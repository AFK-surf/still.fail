import { readFileSync, realpathSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

// Check the raw paths and the test work path after home has been replaced. The latter catches a partial scrub.
export function containsLocalInformation(text, { home = "", work = "", workspace = "", hostname = "", privateTerms = [] } = {}) {
  const paths = new Set();
  const variants = (p) => {
    if (!p) return [];
    const absolute = resolve(p);
    let real = absolute;
    try { real = realpathSync(absolute); } catch { /* A test directory need not exist yet. */ }
    return [...new Set([absolute, real])].filter((s) => s.length > 1);
  };
  const homes = variants(home);
  const works = variants(work);
  for (const path of homes) paths.add(path);
  for (const path of works) {
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
    if (value && typeof value === "object") return Object.entries(value).some(([k, v]) => visit(v, k));
    return false;
  };
  return text.split("\n").filter(Boolean).some((line) => visit(JSON.parse(line)));
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    const trace = readFileSync(process.argv[2], "utf8");
    if (containsLocalInformation(trace, {
      home: process.env.HOME,
      work: process.env.E2E_WORK,
      workspace: dirname(fileURLToPath(new URL("../../..", import.meta.url))),
      hostname: process.argv[3],
      privateTerms: process.env.E2E_PRIVATE_TERMS_FILE ? readFileSync(process.env.E2E_PRIVATE_TERMS_FILE, "utf8").split(/\r?\n/) : [],
    })) process.exitCode = 1;
  } catch {
    // A malformed trace must not pass the check.
    process.exitCode = 1;
  }
}
