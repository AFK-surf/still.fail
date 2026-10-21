// A station's software for the stories (Versions.tsx SoftwareList): the demo station's overview with `updates` as the
// station says them, every runtime it can install offered (`installable`), or a machine it cannot install some on (no
// npm on Windows), why said under each.
import type { DemoExtension } from "../src/demo/mount.tsx";
import type { SoftwareVersion, StationView } from "../src/core/shapes.ts";

const AT = Date.UTC(2026, 9, 22, 0, 42);
const line = (id: string, name: string, more: Partial<SoftwareVersion> = {}): SoftwareVersion =>
  ({ id, name, installed: false, newer: false, downgrade: false, updatable: true, state: "idle", checkedAt: AT, ...more });

const NO_NPM = (name: string) => `安装 ${name} 需要 npm：请先在本机安装 Node（含 npm）`;

const UPDATES: Record<"installable" | "noNpm", SoftwareVersion[]> = {
  installable: [
    line("station", "Station", { installed: true, version: "0.1.4389", latest: "0.1.4389", channel: "beta", auto: true }),
    line("claude", "Claude Code"),
    line("codex", "Codex"),
    line("dsh", "DeepSeek Harness"),
    line("grok", "Grok Build"),
    line("cursor", "Cursor"),
    line("devin", "Devin"),
  ],
  noNpm: [
    line("station", "Station", { installed: true, version: "0.1.4389", latest: "0.1.4389", channel: "beta", auto: true }),
    line("claude", "Claude Code", { installed: true, version: "2.1.284", latest: "2.1.284" }),
    line("codex", "Codex", { updatable: false, note: NO_NPM("Codex") }),
    line("dsh", "DeepSeek Harness", { updatable: false, note: NO_NPM("DeepSeek Harness") }),
    line("grok", "Grok Build", { updatable: false, note: NO_NPM("Grok Build") }),
    line("cursor", "Cursor", { updatable: false, note: NO_NPM("Cursor") }),
    line("devin", "Devin"),
  ],
};

/** The demo with its station's software: each runtime installable, or some not (why said under it). */
export function softwareDemo(state: "installable" | "noNpm"): DemoExtension {
  return {
    then: (topic, value) => (topic.topic === "stations" && Array.isArray(value)
      ? (value as StationView[]).map((s) => (s.overview ? { ...s, overview: { ...s.overview, updates: UPDATES[state] } } : s))
      : undefined),
  };
}
