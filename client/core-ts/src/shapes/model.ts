// Models by what they are rather than how a provider spells them (the station reads them alike).

/// What a model's id says, worked out once per id: lists sort and name their models on every change they make (a
/// station's card, its profiles' series), each comparison reading both ids again, much of what the core did on a phone
/// (2026-10-19). Kept for as many ids as a workspace has, then started over.
function remembered<T>(of: (id: string) => T): (id: string) => T {
  const kept = new Map<string, T>();
  return (id) => {
    let v = kept.get(id);
    if (v === undefined && !kept.has(id)) {
      if (kept.size >= 2048) kept.clear();
      v = of(id);
      kept.set(id, v);
    }
    return v as T;
  };
}

const isDigits = (s: string) => s.length > 0 && /^[0-9]+$/.test(s);
const isAlpha = (s: string) => s.length > 0 && /^[A-Za-z]+$/.test(s);

/// What a model is, however it is spelled: lower case, without its provider's prefix, region, version stamp or date.
export function key(id: string): string {
  const lower = id.trim().toLowerCase();
  const at = lower.indexOf("[");
  const [base, context] = at >= 0 ? [lower.slice(0, at), lower.slice(at)] : [lower, ""];
  let m = base.split("/").pop() ?? base;
  m = m.split("@")[0]!;
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
  if (n > 1 && digits(parts[n - 1]!, 8)) m = parts.slice(0, n - 1).join("-");
  else if (n > 3 && digits(parts[n - 3]!, 4) && digits(parts[n - 2]!, 2) && digits(parts[n - 1]!, 2)) m = parts.slice(0, n - 3).join("-");
  if (m.startsWith("fusion-") && m.includes("-sidekick-")) {
    const split = splitDevinFusion(m);
    if (split !== null) m = split.model;
  }
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

const AGY_LEVELS = ["none", "minimal", "low", "medium", "high", "xhigh", "max"];
const DEVIN_LEVELS = ["low", "medium", "high", "xhigh", "max"];

/// An Antigravity ACP tiered `modelId` (`gemini-4-carbon-high`, `claude-opus-5-5-medium`, `gpt-oss-120b-medium`) split
/// into its base model and thinking level; null when `id` carries no trailing level.
export function splitAgyTier(id: string): { model: string; effort: string } | null {
  const trimmed = id.trim();
  const effort = AGY_LEVELS.find((l) => trimmed.endsWith(`-${l}`) && trimmed.length > l.length + 1);
  return effort === undefined ? null : { model: trimmed.slice(0, -effort.length - 1), effort };
}

/// A Devin Fusion model (`fusion-<lead>-sidekick-<side>` or legacy `fusion-<lead>-<effort>-sidekick-<side>`) split
/// into its normalized `model` (`fusion-<lead>-sidekick-<side>`), `lead`, `side` and optional legacy `leadEffort`.
export function splitDevinFusion(id: string): { model: string; lead: string; side: string; leadEffort: string | null } | null {
  const trimmed = id.trim();
  if (!trimmed.startsWith("fusion-")) return null;
  const mark = "-sidekick-";
  const at = trimmed.indexOf(mark, 7);
  if (at <= 7 || at + mark.length >= trimmed.length) return null;
  const rawLead = trimmed.slice(7, at);
  const side = trimmed.slice(at + mark.length);
  const leadEffort = DEVIN_LEVELS.find((l) => rawLead.endsWith(`-${l}`) && rawLead.length > l.length + 1) ?? null;
  const lead = leadEffort === null ? rawLead : rawLead.slice(0, -leadEffort.length - 1);
  return { model: `fusion-${lead}-sidekick-${side}`, lead, side, leadEffort };
}

/// A Devin Fusion lead id normalized by stripping any trailing thinking level (`gpt-6-sol-max` -> `gpt-6-sol`).
export function devinFusionLead(lead: string): string {
  const trimmed = lead.trim();
  const eff = DEVIN_LEVELS.find((l) => trimmed.endsWith(`-${l}`) && trimmed.length > l.length + 1);
  return eff === undefined ? trimmed : trimmed.slice(0, -eff.length - 1);
}

export const DEVIN_FUSION_LEADS: readonly string[] = [
  "claude-opus-5-5",
  "claude-opus-5-6",
  "claude-sonnet-5-5",
  "claude-sonnet-5-6",
  "gemini-4-carbon",
  "gemini-4.1-carbon",
  "gpt-6-sol",
  "gpt-6-luna",
  "gpt-6.1-terra",
];

export const DEVIN_FUSION_SIDES: readonly string[] = [
  "swe-2-medium",
  "swe-2-high",
  "swe-2-flash-xhigh",
  "claude-sonnet-5-5-medium",
  "claude-haiku-5-5-medium",
  "gpt-6-luna-high",
  "gpt-6.1-terra-high",
  "gpt-5-6-sol-high",
  "gpt-5-6-luna-high",
  "glm-5-2",
];

/// Sidekick models Devin offers for `lead` (null when `lead` is not a Fusion lead model).
export function devinFusionSidesFor(lead: string): readonly string[] | null {
  const k = key(lead);
  if (!DEVIN_FUSION_LEADS.includes(k)) return null;
  if (k === "gpt-6-luna") return DEVIN_FUSION_SIDES.filter((s) => s !== "gpt-6-luna-high");
  if (k === "gpt-6.1-terra") return DEVIN_FUSION_SIDES.filter((s) => s !== "gpt-6.1-terra-high");
  return DEVIN_FUSION_SIDES;
}

const SIDE_EFFORTS: Record<string, string> = {
  low: "低",
  medium: "中",
  high: "高",
  xhigh: "超高",
  max: "最高",
};

/// A Devin sidekick (`swe-2-medium`, `swe-2-flash-xhigh`, `glm-5-2`) formatted for a sidekick picker: `SWE-2 · 中`.
export function sidekickName(side: string): string {
  const k = key(side);
  const eff = Object.keys(SIDE_EFFORTS).find((l) => k.endsWith(`-${l}`) && k.length > l.length + 1);
  const core = eff === undefined ? k : k.slice(0, -eff.length - 1);
  const coreName = namedOf(core) ?? side;
  return eff === undefined ? coreName : `${coreName} · ${SIDE_EFFORTS[eff]!}`;
}

/// A model as people call it: Opus 5.5, GPT-6 Astra, o4 Mini; one whose family is not known here reads as spelled.
export const name = remembered(nameOf);
function nameOf(id: string): string {
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
export const family = remembered(familyOf);
function familyOf(id: string): string | null {
  const k = key(id);
  const rawBase = k.split("[")[0]!;
  if (namedOf(rawBase) === null) return null;
  const split = splitDevinFusion(rawBase);
  const base = split !== null ? split.lead : rawBase;
  const words = base.split("-").filter((w) => w !== "");
  const first = words[0];
  if (first === undefined) return null;
  if (first === "claude" || CLAUDE.includes(first)) {
    const w = words.find((w) => CLAUDE.includes(w));
    return w === undefined ? null : word(w);
  }
  if (first === "gpt") {
    const f = words.slice(2).find((w) => ["sol", "astra", "luna"].includes(w.split(":")[0]!));
    if (f !== undefined) return word(f.split(":")[0]!);
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

const orderKey = remembered(orderKeyOf);
function orderKeyOf(id: string): Readonly<{ rank: number; family: string; version: readonly number[]; key: string }> {
  const f = family(id);
  const rank = f === null ? CLAUDE.length + 1 : (() => {
    const i = CLAUDE.indexOf(f.toLowerCase());
    return i >= 0 ? i : CLAUDE.length;
  })();
  const k = key(id);
  const base = k.split("[")[0]!;
  const split = splitDevinFusion(base);
  const versionBase = split !== null ? split.lead : base;
  const version = versionBase.split(/[^0-9]/).filter((n) => n !== "").map((n) => Number(n)).filter((n) => n <= 0xffffffff);
  return { rank, family: f ?? "", version, key: split !== null ? `${split.lead}~${split.side}` : k };
}

function namedOf(base: string): string | null {
  if (base.startsWith("fusion-")) {
    const split = splitDevinFusion(base);
    if (split !== null) {
      const leadName = namedOf(split.lead) ?? split.lead;
      const sideEff = Object.keys(SIDE_EFFORTS).find((l) => split.side.endsWith(`-${l}`) && split.side.length > l.length + 1);
      const sideCore = sideEff === undefined ? split.side : split.side.slice(0, -sideEff.length - 1);
      const sideName = namedOf(sideCore) ?? sideCore;
      const sideDisplay = sideEff === undefined ? sideName : `${sideName} (${SIDE_EFFORTS[sideEff]!})`;
      return `${leadName} + ${sideDisplay}`;
    }
  }
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
  const parts = joined(words);
  const dashed = ["gpt", "glm", "swe"].includes(first) ? word(first) : null;
  if (dashed !== null && parts[1] !== undefined) {
    const second = parts[1] in BRANDS ? BRANDS[parts[1]]! : parts[1];
    return [`${dashed}-${second}`, ...parts.slice(2).map(word)].join(" ");
  }
  const o = oSeries(first);
  const known = ["gpt", "glm", "codex", "deepseek", "qwen", "qwq", "gemini", "gemma", "kimi", "moonshot", "minimax", "grok", "mistral", "devstral", "codestral", "llama", "doubao", "hunyuan", "ernie", "nemotron", "muse", "adaptive"];
  const fam = first.replace(/[0-9.]+$/, "");
  if (!o && !known.includes(fam)) return null;
  return parts.map((w, i) => (i === 0 && o ? w : word(w))).join(" ");
}

/// A version spelled in parts joined again (gpt-5-6 is GPT-5.6, kimi-k2-6 Kimi K2.6): a part of one or two digits after
/// one that ends in a digit, not a longer one (deepseek-r1-0528 is a date).
function joined(words: string[]): string[] {
  const out: string[] = [];
  for (const w of words) {
    const last = out[out.length - 1];
    if (last !== undefined && /[0-9]$/.test(last) && /^[0-9]{1,2}$/.test(w)) out[out.length - 1] = `${last}.${w}`;
    else out.push(w);
  }
  return out;
}

const BRANDS: Record<string, string> = {
  deepseek: "DeepSeek", minimax: "MiniMax", qwq: "QwQ", glm: "GLM", gpt: "GPT", swe: "SWE", oss: "OSS", moonshot: "Moonshot", devstral: "Devstral",
  codestral: "Codestral", llama: "Llama", ernie: "ERNIE", vl: "VL", r1: "R1", it: "IT",
};

function word(w: string): string {
  if (w in BRANDS) return BRANDS[w]!;
  if (/^[0-9]+(?:\.[0-9]+)?[bmk]$/.test(w)) return w.toUpperCase();
  const chars = [...w];
  if (chars.length === 0) return "";
  return chars[0]!.toUpperCase() + chars.slice(1).join("");
}
