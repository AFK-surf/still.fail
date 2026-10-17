// The workspace lock for the stories (docs/workspace-lock.md): the demo workspace's `lock` topic as the core puts it
// together (client/core-ts/src/views/lock.ts) with security mode on, with no station in the workspace, and on a device
// waiting to be approved (its request pending, or turned down).
import type { DemoExtension } from "../src/demo/mount.tsx";
import type { LockStation, LockView } from "../src/core/shapes.ts";

export type LockStory = "on" | "noStations" | "waiting" | "denied";

const STATIONS: LockStation[] = [
  { id: "s_studio", name: "Studio", version: "0.1.3217", online: true, protected: true },
  { id: "s_mini", name: "mini1", version: "0.1.2980", online: false, protected: false },
];

function view(story: LockStory): LockView {
  const stations = story === "noStations" ? [] : STATIONS;
  const waits = story === "waiting" || story === "denied";
  return {
    available: true, locked: true, notice: false, role: "owner", manages: true, owner: true, canSign: true, signs: !waits,
    me: { device: "d_demo", code: "4BU-L2G", kind: "app", confirmed: !waits, waiting: waits, asked: story !== "denied" },
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
  return {
    topic: (t) => (t.topic === "lock" ? view(story) : undefined),
    // What changes something answers at once, the page as it was (the stories show states, not what follows).
    call: (name) => (name.startsWith("lock.") ? {} : undefined),
  };
}
