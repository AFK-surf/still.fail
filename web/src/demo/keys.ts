// The visitor's own model accounts in the demo: profiles added through the app's own 添加 Profile, kept in this
// browser only (localStorage) — the key goes nowhere but to its provider, from this browser (llm.ts). With one, the
// demo's agent (agent.ts) really answers.
import type { AccessKind, Maker, ModelOption, Profile } from "../core/shapes.ts";

export interface UserProfile {
  id: string;
  kind: Extract<AccessKind, "opencode-go">;
  key: string;
  /** Its enabled models; the first is its default. */
  models: string[];
  addedAt: number;
}

const STORE = "ember.demo.profiles";

export function userProfiles(): UserProfile[] {
  try {
    const saved = JSON.parse(localStorage.getItem(STORE) ?? "[]") as UserProfile[];
    return Array.isArray(saved) ? saved : [];
  } catch {
    return [];
  }
}

function save(list: UserProfile[]): void {
  localStorage.setItem(STORE, JSON.stringify(list));
}

/** OpenCode Go's models the demo offers, best first: the first is a new profile's default. */
export const OPENCODE_MODELS = ["kimi-k3", "deepseek-v4-pro", "glm-5.3", "qwen3.8-max", "minimax-m3"];

export function addUserProfile(kind: UserProfile["kind"], key: string): UserProfile {
  const list = userProfiles();
  const profile: UserProfile = { id: `opencode-go-${list.length + 1}`, kind, key, models: OPENCODE_MODELS, addedAt: Date.now() };
  save([...list, profile]);
  return profile;
}

export function updateUserProfile(id: string, change: Partial<Pick<UserProfile, "key" | "models">>): void {
  save(userProfiles().map((p) => (p.id === id ? { ...p, ...change, ...(change.key === "" ? { key: p.key } : {}) } : p)));
}

export function removeUserProfile(id: string): void {
  save(userProfiles().filter((p) => p.id !== id));
}

// ---- As the app shows them ----

/** A model's maker, for its mark (public/models/<id>.svg). */
export function makerOf(model: string): Maker | undefined {
  const makers: [string, Maker][] = [
    ["kimi", { id: "kimi", name: "Moonshot AI" }], ["deepseek", { id: "deepseek", name: "DeepSeek" }], ["glm", { id: "zhipu", name: "智谱" }],
    ["qwen", { id: "qwen", name: "Qwen" }], ["minimax", { id: "minimax", name: "MiniMax" }], ["grok", { id: "xai", name: "xAI" }], ["gpt", { id: "openai", name: "OpenAI" }],
  ];
  return makers.find(([prefix]) => model.startsWith(prefix))?.[1];
}

/** A model as people call it: kimi-k3 → Kimi K3, deepseek-v4-pro → DeepSeek V4 Pro. */
export function nameOf(model: string): string {
  const words: Record<string, string> = { kimi: "Kimi", deepseek: "DeepSeek", glm: "GLM", minimax: "MiniMax", qwen: "Qwen", pro: "Pro", max: "Max", flash: "Flash", plus: "Plus" };
  return model.split("-").map((w) => words[w] ?? (/^[a-z]\d/.test(w) ? w.toUpperCase() : w.replace(/^qwen/, "Qwen"))).join(" ");
}

export function presentProfile(p: UserProfile): Profile {
  const names = Object.fromEntries(OPENCODE_MODELS.map((m) => [m, nameOf(m)]));
  const makers = Object.fromEntries(OPENCODE_MODELS.flatMap((m) => (makerOf(m) ? [[m, makerOf(m)!]] : [])));
  return {
    id: p.id, name: "OpenCode Go", runtime: "claude", runtimes: ["claude", "codex"], access: { kind: p.kind, key: "" },
    home: `/Users/lin/.ember/homes/${p.id}`, homeExists: true, model: p.models[0]!, models: p.models, env: [], usedBy: [],
    loginCommand: "", backgroundOnMessage: true,
    check: { state: "ok", detail: "key 可用（存在你的浏览器里）", models: OPENCODE_MODELS, checkedAt: p.addedAt },
    checkText: "可用", checkTone: "green", makers, names,
    series: [{ name: "其他", models: OPENCODE_MODELS }], modelsText: `已启用 ${p.models.length} / ${OPENCODE_MODELS.length} 个模型`,
  };
}

/** The visitor's models, as a station offers them to a chat's model control. */
export function userModels(): ModelOption[] {
  return userProfiles().flatMap((p) => p.models.map((model) => ({
    model, name: nameOf(model), ids: [model], runtimes: ["claude" as const],
    ...(makerOf(model) ? { maker: makerOf(model)! } : {}),
    efforts: { claude: ["low", "medium", "high"] },
    accounts: { claude: [{ id: p.id, name: "OpenCode Go", current: false, kind: p.kind, runtime: "claude" as const }] },
  })));
}
