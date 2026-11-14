// A model as people call it, and who made it (client/core-ts format.ts `makerOf`): the accounts'
// pages and published snapshots name models so, and draw their makers' marks.
import { modelKey } from "../read/usage.ts";

const CLAUDE = ["fable", "opus", "sonnet", "haiku"];
const BRANDS: Record<string, string> = {
  deepseek: "DeepSeek", minimax: "MiniMax", qwq: "QwQ", glm: "GLM", gpt: "GPT", swe: "SWE", oss: "OSS", moonshot: "Moonshot", devstral: "Devstral",
  codestral: "Codestral", llama: "Llama", ernie: "ERNIE", vl: "VL", r1: "R1", it: "IT",
};

const word = (w: string) => BRANDS[w] ?? (/^[0-9]+(\.[0-9]+)?[bmk]$/.test(w) ? w.toUpperCase() : w === "" ? "" : w[0]!.toUpperCase() + w.slice(1));
const digitsOnly = (w: string) => /^[0-9]+$/.test(w);

function joined(words: string[]): string[] {
  const out: string[] = [];
  for (const w of words) {
    const last = out[out.length - 1];
    if (last !== undefined && /[0-9]$/.test(last) && /^[0-9]{1,2}$/.test(w)) out[out.length - 1] = `${last}.${w}`;
    else out.push(w);
  }
  return out;
}

const EFFORT_SHORT: Record<string, string> = {
  low: "低",
  medium: "中",
  high: "高",
  xhigh: "超高",
  max: "最高",
};
const DEVIN_LEVELS = ["none", "minimal", "low", "medium", "high", "xhigh", "max"];

function namedModel(base: string): string | undefined {
  if (base.startsWith("fusion-")) {
    const splitAt = base.indexOf("-sidekick-");
    if (splitAt > "fusion-".length) {
      const leadRaw = base.slice("fusion-".length, splitAt);
      const sideRaw = base.slice(splitAt + "-sidekick-".length);
      if (sideRaw !== "") {
        const leadEffort = DEVIN_LEVELS.find((l) => leadRaw.endsWith(`-${l}`) && leadRaw.length > l.length + 1);
        const leadBase = leadEffort !== undefined ? leadRaw.slice(0, -leadEffort.length - 1) : leadRaw;
        const sideEffort = DEVIN_LEVELS.find((l) => sideRaw.endsWith(`-${l}`) && sideRaw.length > l.length + 1);
        const sideBase = sideEffort !== undefined ? sideRaw.slice(0, -sideEffort.length - 1) : sideRaw;
        const lead = namedModel(leadBase) ?? leadBase;
        const side = namedModel(sideBase) ?? sideBase;
        const sideLvl = sideEffort !== undefined ? (EFFORT_SHORT[sideEffort] ?? word(sideEffort)) : undefined;
        return sideLvl !== undefined ? `${lead} + ${side} (${sideLvl})` : `${lead} + ${side}`;
      }
    }
  }
  const words = base.split("-").filter((w) => w !== "");
  const first = words[0];
  if (first === undefined) return undefined;
  if (first === "claude" || CLAUDE.includes(first)) {
    const family = words.find((w) => CLAUDE.includes(w));
    if (family === undefined) return undefined;
    const version = words.filter(digitsOnly);
    const rest = words.filter((w) => w !== "claude" && w !== family && !digitsOnly(w)).map(word);
    return [word(family), ...(version.length > 0 ? [version.join(".")] : []), ...rest].join(" ");
  }
  const parts = joined(words);
  const dashed = ["gpt", "glm", "swe"].includes(first) ? word(first) : undefined;
  if (dashed !== undefined && parts[1] !== undefined) {
    const second = BRANDS[parts[1]] ?? parts[1];
    return [`${dashed}-${second}`, ...parts.slice(2).map(word)].join(" ");
  }
  const oSeries = first.length > 1 && first.startsWith("o") && digitsOnly(first.slice(1));
  const known = ["gpt", "glm", "codex", "deepseek", "qwen", "qwq", "gemini", "gemma", "kimi", "moonshot", "minimax", "grok", "mistral", "devstral", "codestral", "llama", "doubao", "hunyuan", "ernie", "nemotron", "muse", "adaptive"];
  const family = first.replace(/[0-9.]+$/, "");
  if (!oSeries && !known.includes(family)) return undefined;
  return parts.map((w, i) => (i === 0 && oSeries ? w : word(w))).join(" ");
}

/// A model as people call it: Opus 5.5, GPT-6 Astra, o4 Mini, DeepSeek V4 Pro; one of a family not known here reads as
/// it is spelled.
export function modelName(id: string): string {
  const k = modelKey(id);
  const at = k.indexOf("[");
  const [base, context] = at >= 0 ? [k.slice(0, at), k.slice(at + 1).replace(/\]+$/, "").toUpperCase()] : [k, ""];
  const named = namedModel(base);
  if (named === undefined) return id.trim();
  return context === "" ? named : `${named} ${context}`;
}

/// Who made a model, as its mark is known by (client/core-ts format.ts `makerOf`): none for one the marks do not know.
export function makerOf(model: string): string | null {
  const lower = model.toLowerCase();
  const sidekick = lower.indexOf("-sidekick-");
  const m = lower.startsWith("fusion-") && sidekick > 0 ? lower.slice("fusion-".length, sidekick) : lower;
  const has = (words: string[]) => words.some((w) => m.includes(w));
  if (has(["claude", "opus", "sonnet", "haiku", "fable"])) return "anthropic";
  if (has(["gpt", "codex", "openai"]) || (m.startsWith("o") && /^[0-9]/.test(m.slice(1)))) return "openai";
  if (has(["deepseek"])) return "deepseek";
  if (has(["qwen", "qwq"])) return "qwen";
  if (has(["glm", "zhipu"])) return "zhipu";
  if (has(["gemini", "gemma"])) return "gemini";
  if (has(["kimi", "moonshot"])) return "kimi";
  if (has(["minimax", "abab"])) return "minimax";
  if (has(["grok"])) return "xai";
  if (has(["swe-"]) || m === "adaptive") return "devin";
  return null;
}
