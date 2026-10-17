// The workspace lock for the stories (docs/workspace-lock.md): the demo workspace's `lock` topic as the core puts it
// together (client/core-ts/src/views/lock.ts) with security mode on, and with no station in the workspace.
import type { DemoExtension } from "../src/demo/mount.tsx";
import type { LockStation, LockView } from "../src/core/shapes.ts";

export type LockStory = "on" | "noStations";

const STATIONS: LockStation[] = [
  { id: "s_studio", name: "Studio", version: "0.1.3217", online: true, protected: true },
  { id: "s_mini", name: "mini1", version: "0.1.2980", online: false, protected: false },
];

function view(story: LockStory): LockView {
  const stations = story === "noStations" ? [] : STATIONS;
  return {
    available: true, locked: true, notice: false, role: "owner", manages: true, owner: true, canSign: true, signs: true,
    me: { device: "d_demo", code: "482 913", kind: "app", confirmed: true, waiting: false },
    signers: 1,
    members: [{
      sub: "demo-you", email: "you@acme.dev", name: "你", role: "owner", you: true,
      devices: [{ id: "d_demo", kind: "app", label: "MacBook Pro", signs: true, older: false, mine: true, renewSoon: false, recent: false }],
    }],
    stations, protected: stations.filter((s) => s.protected).length, requests: [], renew: [], attention: 0,
  };
}

/** The demo with security mode on, as `story` has it. */
export function lockDemo(story: LockStory): DemoExtension {
  return { topic: (t) => (t.topic === "lock" ? view(story) : undefined) };
}
