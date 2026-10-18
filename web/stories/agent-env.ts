// A station's variables for its agents, for the stories (docs/agent-env.md): the demo station's overview with `agentEnv`
// as the station says it (a secret's value masked), set or none yet; the core's draft of them (agentEnvForm) as written,
// read line by line, or with a line it cannot take and a name given twice; saving answers at once.
import type { DemoExtension } from "../src/demo/mount.tsx";
import type { AgentEnvDraft, AgentEnvLine, EnvVar, StationView } from "../src/core/shapes.ts";

const SET: EnvVar[] = [
  { key: "HTTPS_PROXY", value: "http:…7890", secret: true },
  { key: "HTTP_PROXY", value: "http://127.0.0.1:7890", secret: false },
  { key: "NO_PROXY", value: "corp.example,10.0.0.0/8", secret: false },
];

const pair = (name: string, value: string, problem: string | null = null): AgentEnvLine =>
  ({ parts: [{ kind: "name", text: name }, { kind: "other", text: "=" }, { kind: "value", text: value }], problem, error: false });
const line = (text: string, kind: "comment" | "other", problem: string | null = null): AgentEnvLine =>
  ({ parts: text ? [{ kind, text }] : [], problem, error: problem !== null && kind === "other" });

const draftOf = (lines: AgentEnvLine[], dirty: boolean): AgentEnvDraft => ({
  text: lines.map((l) => l.parts.map((p) => p.text).join("")).join("\n"),
  lines, errors: lines.filter((l) => l.error).length, dirty, pending: false,
});

const DRAFTS = {
  set: draftOf(SET.map((e) => pair(e.key, e.value)), false),
  empty: draftOf([line("", "other")], false),
  wrong: draftOf([
    line("# 公司代理", "comment"),
    pair("HTTPS_PROXY", "http://127.0.0.1:7890", "重复，以后面的为准"),
    line("http_proxy http://127.0.0.1:7890", "other", "不是「变量名=值」的格式"),
    pair("HTTPS_PROXY", "http://127.0.0.1:7891"),
    pair("NO_PROXY", "localhost,.internal"),
  ], true),
};

/** The demo with its station's variables set, none yet, or being edited with a line wrong. */
export function agentEnvDemo(state: "set" | "empty" | "wrong"): DemoExtension {
  const agentEnv = state === "empty" ? [] : SET;
  return {
    topic: (topic) => (topic.topic === "agentEnvForm" ? DRAFTS[state] : undefined),
    then: (topic, value) => (topic.topic === "stations" && Array.isArray(value)
      ? (value as StationView[]).map((s) => (s.overview ? { ...s, overview: { ...s.overview, agentEnv } } : s))
      : undefined),
    call: (name) => (name.startsWith("agentEnv.") ? {} : undefined),
  };
}
