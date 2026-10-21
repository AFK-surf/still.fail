// The step right after a profile is added (pages/Accounts.tsx PickModelsPage, mobile/Profiles.tsx PickModelsScreen): an
// API key's form that adds the demo's profile when submitted, then its models chosen there; still being read
// (`reading`: the station's first check not back), or listed with one enabled.
import type { DemoExtension } from "../src/demo/mount.tsx";
import type { ProfileFlowView } from "../src/core/shapes.ts";

/** What the form's button says: the story's step clicks it. */
export const ADD = "验证并添加";

export function pickModelsDemo(reading: boolean): DemoExtension {
  const view: ProfileFlowView = {
    step: "connect", station: "", title: "连接 Anthropic", hint: "", groups: [], method: "key", choices: [], showEndpoint: false, endpoint: "", protocols: [], regions: [],
    showKey: true, key: "sk-ant-…", keyLabel: "API key", canSubmit: true, pending: false, submitLabel: ADD, usesLine: "添加后可用于：Claude Code",
    tile: { id: "anthropic", name: "Anthropic", group: "labs", mark: "anthropic", kind: "api-provider", hasKey: true, hasPlan: true, runtime: "claude", endpointRequired: false, protocols: [], keyOptional: false, uses: ["claude"], usesText: "Claude Code" },
  };
  return {
    topic: (t) => (t.topic === "profileFlow" ? { ...view, station: String(t.station) } : undefined),
    // Submitting adds the demo's own profile (the stories show states, not what follows).
    call: (name) => (name === "profile.flow.submit" ? { id: "machine-claude" } : name.startsWith("profile.flow.") ? {} : undefined),
    then: (t, value) => {
      if (t.topic !== "overview" || !value || typeof value !== "object") return undefined;
      const o = value as { profiles: Record<string, unknown>[] };
      return {
        ...o, profiles: o.profiles.map((p) => {
          const check = p.check as { models?: string[] } | undefined;
          return reading
            ? { ...p, models: [], check: undefined, checkText: "未检查", checkTone: "neutral", modelsReading: true, available: [], modelsText: "尚未列出模型" }
            : { ...p, models: ["claude-opus-5-5"], available: check?.models ?? [], modelsReading: false };
        }),
      };
    },
  };
}
