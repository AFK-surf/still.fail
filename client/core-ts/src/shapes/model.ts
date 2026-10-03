// Models by what they are rather than how a provider spells them (the station reads them alike).

const isDigits = (s: string) => s.length > 0 && /^[0-9]+$/.test(s);
const isAlpha = (s: string) => s.length > 0 && /^[A-Za-z]+$/.test(s);

/// What a model is, however it is spelled: lower case, without its provider's prefix, region, version stamp or date.
export function key(id: string): string {
  const lower = id.trim().toLowerCase();
  const at = lower.indexOf("[");
  const [base, context] = at >= 0 ? [lower.slice(0, at), lower.slice(at)] : [lower, ""];
  let m = base.split("/").pop() ?? base;
  m = m.split("@")[0];
  for (;;) {
    const dot = m.indexOf(".");
    if (dot < 0) break;
    const head = m.slice(0, dot);
    const rest = m.slice(dot + 1);
    if (!isAlpha(head) || rest === "") break;
    m = rest;
  }
  const v = m.lastIndexOf("-v");
  if (v >= 0 && stamp(m.slice(v + 2))) m = m.slice(0, v);
  const parts = m.split("-");
  const n = parts.length;
  const digits = (s: string, k: number) => s.length === k && isDigits(s);
  if (n > 1 && digits(parts[n - 1], 8)) m = parts.slice(0, n - 1).join("-");
  else if (n > 3 && digits(parts[n - 3], 4) && digits(parts[n - 2], 2) && digits(parts[n - 1], 2)) m = parts.slice(0, n - 3).join("-");
  return m + context;
}

function stamp(s: string): boolean {
  const colon = s.indexOf(":");
  if (colon < 0) return false;
  return isDigits(s.slice(0, colon)) && isDigits(s.slice(colon + 1));
}

/// Whether two spellings are one model.
export function same(a: string, b: string): boolean {
  return a === b || key(a) === key(b);
}

/// A model as people call it: Opus 5.5, GPT-6 Astra, o4 Mini; one whose family is not known here reads as spelled.
export function name(id: string): string {
  const k = key(id);
  const at = k.indexOf("[");
  const base = at >= 0 ? k.slice(0, at) : k;
  const context = at >= 0 ? k.slice(at + 1).replace(/\]+$/, "").toUpperCase() : "";
  const named = namedOf(base);
  if (named === null) return id.trim();
  return context === "" ? named : `${named} ${context}`;
}

const CLAUDE = ["fable", "opus", "sonnet", "haiku"];

function oSeries(first: string): boolean {
  return first.length > 1 && first.startsWith("o") && isDigits(first.slice(1));
}

/// The series a model is of (Opus, Sol, GPT, o 系列, DeepSeek…); null when its family is not known here.
export function family(id: string): string | null {
  const k = key(id);
  const base = k.split("[")[0];
  if (namedOf(base) === null) return null;
  const words = base.split("-").filter((w) => w !== "");
  const first = words[0];
  if (first === undefined) return null;
  if (first === "claude" || CLAUDE.includes(first)) {
    const w = words.find((w) => CLAUDE.includes(w));
    return w === undefined ? null : word(w);
  }
  if (first === "gpt") {
    const f = words.slice(2).find((w) => ["sol", "astra", "luna"].includes(w.split(":")[0]));
    if (f !== undefined) return word(f.split(":")[0]);
  }
  if (oSeries(first)) return "o 系列";
  return word(first.replace(/[0-9.]+$/, ""));
}

/// How models are listed: by series (Claude's biggest first, the rest by name), then newest first.
export function compareOrder(a: string, b: string): number {
  const ka = orderKey(a);
  const kb = orderKey(b);
  if (ka.rank !== kb.rank) return ka.rank - kb.rank;
  if (ka.family !== kb.family) return ka.family < kb.family ? -1 : 1;
  // Reverse(version): the bigger version first.
  for (let i = 0; i < Math.max(ka.version.length, kb.version.length); i++) {
    const x = ka.version[i];
    const y = kb.version[i];
    if (x === undefined) return 1;
    if (y === undefined) return -1;
    if (x !== y) return y - x;
  }
  return ka.key < kb.key ? -1 : ka.key > kb.key ? 1 : 0;
}

function orderKey(id: string): { rank: number; family: string; version: number[]; key: string } {
  const f = family(id);
  const rank = f === null ? CLAUDE.length + 1 : (() => {
    const i = CLAUDE.indexOf(f.toLowerCase());
    return i >= 0 ? i : CLAUDE.length;
  })();
  const k = key(id);
  const base = k.split("[")[0];
  const version = base.split(/[^0-9]/).filter((n) => n !== "").map((n) => Number(n)).filter((n) => n <= 0xffffffff);
  return { rank, family: f ?? "", version, key: k };
}

function namedOf(base: string): string | null {
  const words = base.split("-").filter((w) => w !== "");
  const first = words[0];
  if (first === undefined) return null;
  if (first === "claude" || CLAUDE.includes(first)) {
    const fam = words.find((w) => CLAUDE.includes(w));
    if (fam === undefined) return null;
    const version = words.filter((w) => isDigits(w));
    const rest = words.filter((w) => w !== "claude" && w !== fam && !isDigits(w)).map(word);
    const out = [word(fam)];
    if (version.length > 0) out.push(version.join("."));
    out.push(...rest);
    return out.join(" ");
  }
  const dashed = first === "gpt" ? "GPT" : first === "glm" ? "GLM" : null;
  if (dashed !== null && words[1] !== undefined) {
    return [`${dashed}-${words[1]}`, ...words.slice(2).map(word)].join(" ");
  }
  const o = oSeries(first);
  const known = ["gpt", "glm", "codex", "deepseek", "qwen", "qwq", "gemini", "gemma", "kimi", "moonshot", "minimax", "grok", "mistral", "devstral", "codestral", "llama", "doubao", "hunyuan", "ernie"];
  const fam = first.replace(/[0-9.]+$/, "");
  if (!o && !known.includes(fam)) return null;
  return words.map((w, i) => (i === 0 && o ? w : word(w))).join(" ");
}

const BRANDS: Record<string, string> = {
  deepseek: "DeepSeek", minimax: "MiniMax", qwq: "QwQ", glm: "GLM", gpt: "GPT", oss: "OSS", moonshot: "Moonshot", devstral: "Devstral",
  codestral: "Codestral", llama: "Llama", ernie: "ERNIE", vl: "VL", r1: "R1", it: "IT",
};

function word(w: string): string {
  if (w in BRANDS) return BRANDS[w];
  const chars = [...w];
  if (chars.length === 0) return "";
  return chars[0].toUpperCase() + chars.slice(1).join("");
}
