// The workspace lock for the stories (docs/workspace-lock.md): the demo workspace's `lock` topic as the core puts it
// together (client/core-ts/src/views/lock.ts) with security mode on, with no station in the workspace, on a device
// waiting to be approved (not asked yet, reaching its trusted devices, the code one shows to type, typed wrong, none
// answered, its key not kept), and with a new device showing this one's code (`lockPrompts`, views/pair.ts).
import type { DemoExtension } from "../src/demo/mount.tsx";
import type { LockPair, LockPromptsView, LockStation, LockView } from "../src/core/shapes.ts";

export type LockStory = "on" | "noStations" | "waiting" | "finding" | "code" | "wrong" | "none" | "failed" | "prompt";

const STATIONS: LockStation[] = [
  { id: "s_studio", name: "Studio", version: "0.1.3217", online: true, protected: true },
  { id: "s_mini", name: "mini1", version: "0.1.2980", online: false, protected: false },
];

const PAIR: Partial<Record<LockStory, LockPair>> = {
  finding: { state: "finding", devices: 0 },
  code: { state: "code", devices: 1 },
  wrong: { state: "wrong", devices: 1, left: 2 },
  none: { state: "none", devices: 0 },
};

function view(story: LockStory): LockView {
  const stations = story === "noStations" ? [] : STATIONS;
  const waits = story !== "on" && story !== "noStations" && story !== "prompt";
  return {
    available: true, locked: true, notice: false, role: "owner", manages: true, owner: true, canSign: true, signs: !waits,
    me: {
      device: "d_demo", code: "4BU-L2G", kind: "app", confirmed: !waits, waiting: waits, asked: false,
      ...(story === "failed" ? { failed: "无法在系统钥匙串中保存此设备的密钥：secure.set is not supported on this host" } : {}),
      ...(PAIR[story] ? { pair: PAIR[story] } : {}),
    },
    signers: 1,
    members: [{
      sub: "demo-you", email: "you@acme.dev", name: "你", role: "owner", you: true,
      devices: [{ id: "d_demo", kind: "app", label: "MacBook Pro", signs: true, older: false, mine: true, renewSoon: false, recent: false }],
    }],
    stations, protected: stations.filter((s) => s.protected).length, requests: [], renew: [], attention: 0,
  };
}

/** A member's new phone, met face to face, asking into two workspaces, one of them not the one open. */
function prompts(story: LockStory): LockPromptsView {
  if (story !== "prompt") return { pairing: [] };
  return {
    pairing: [{
      device: "d_phone", email: "li@acme.dev", name: "李二", kind: "app", label: "still.fail 安卓版 · Pixel 8", code: "K7F-2QX",
      created_at: 1_760_000_000, workspaces: [{ id: "w_acme", name: "Acme" }, { id: "w_daily", name: "日常", emoji: "☀️" }],
    }],
  };
}

/** The demo with security mode on, as `story` has it. */
export function lockDemo(story: LockStory): DemoExtension {
  return {
    topic: (t) => (t.topic === "lock" ? view(story) : t.topic === "lockPrompts" ? prompts(story) : undefined),
    // What changes something answers at once, the page as it was (the stories show states, not what follows).
    call: (name) => (name.startsWith("lock") ? {} : undefined),
  };
}
