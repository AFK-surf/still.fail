// A station's variables for what it starts for its agents, for the stories (docs/agent-env.md): the demo station's
// overview with `agentEnv` as the station says it (a secret's value masked), set or none yet; saving answers at once.
import type { DemoExtension } from "../src/demo/mount.tsx";
import type { EnvVar, StationView } from "../src/core/shapes.ts";

const SET: EnvVar[] = [
  { key: "HTTPS_PROXY", value: "http:…7890", secret: true },
  { key: "HTTP_PROXY", value: "http://127.0.0.1:7890", secret: false },
  { key: "NO_PROXY", value: "corp.example,10.0.0.0/8", secret: false },
];

/** The demo with its station's variables set (`set`) or none yet. */
export function agentEnvDemo(set: boolean): DemoExtension {
  const agentEnv = set ? SET : [];
  return {
    then: (topic, value) => (topic.topic === "stations" && Array.isArray(value)
      ? (value as StationView[]).map((s) => (s.overview ? { ...s, overview: { ...s.overview, agentEnv } } : s))
      : undefined),
    call: (name) => (name === "agentEnv.set" ? {} : undefined),
  };
}
