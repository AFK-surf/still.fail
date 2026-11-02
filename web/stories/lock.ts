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
  code: { state: "code", devices: 1, untilText: "14:05 前有效" },
  wrong: { state: "wrong", devices: 1, left: 2, untilText: "14:05 前有效" },
  none: { state: "none", devices: 0 },
  failed: { state: "failed", devices: 0, error: "配对超时" },
};

type Device = LockView["members"][number]["groups"][number]["devices"][number];

/** The person's devices as the core lists them, by app (this one's first, then the one used most lately; in each this
 *  one first, then the most lately used): which machine each is, when it was last used, one not used in a month and
 *  one approved before it said its name. */
const GROUPS: { appText: string; devices: Omit<Device, "mine" | "removable">[] }[] = [
  { appText: "still.fail 桌面版", devices: [
    { id: "d_demo", kind: "app", label: "still.fail 桌面版 · MacBook Pro", signs: true, older: false, renewSoon: false, recent: false, lastSeen: 1_760_000_000, nameText: "MacBook Pro", fullText: "MacBook Pro · still.fail 桌面版", metaText: "此设备 · 受信任" },
    { id: "d_studio", kind: "app", label: "still.fail 桌面版 · Mac Studio", signs: true, older: false, renewSoon: false, recent: false, lastSeen: 1_759_950_000, nameText: "Mac Studio", fullText: "Mac Studio · still.fail 桌面版", metaText: "一天内使用过 · 受信任" },
  ] },
  { appText: "still.fail Android", devices: [
    { id: "d_pixel", kind: "app", label: "still.fail Android · Pixel 9", signs: true, older: false, renewSoon: false, recent: true, lastSeen: 1_759_990_000, nameText: "Pixel 9", fullText: "Pixel 9 · still.fail Android", metaText: "一天内使用过 · 受信任 · 新增" },
    { id: "d_old", kind: "app", label: "still.fail Android · Pixel 7", signs: true, older: false, renewSoon: false, recent: false, nameText: "Pixel 7", fullText: "Pixel 7 · still.fail Android", metaText: "超过一个月未使用 · 受信任" },
  ] },
  { appText: "still.fail 网页版", devices: [
    { id: "d_chrome", kind: "web", label: "still.fail 网页版 · Chrome · macOS", signs: false, older: false, daysLeft: 4, renewSoon: true, recent: false, lastSeen: 1_759_800_000, nameText: "Chrome · macOS", fullText: "Chrome · macOS · still.fail 网页版", metaText: "2 天前使用过 · 剩余 4 天" },
    { id: "d_safari", kind: "web", label: "still.fail 网页版 · Safari · iOS", signs: false, older: false, daysLeft: 21, renewSoon: false, recent: false, lastSeen: 1_759_000_000, nameText: "Safari · iOS", fullText: "Safari · iOS · still.fail 网页版", metaText: "11 天前使用过 · 剩余 21 天" },
  ] },
  { appText: "其他", devices: [
    { id: "d_unnamed", kind: "app", label: "", signs: true, older: false, renewSoon: false, recent: false, nameText: "客户端", fullText: "客户端", metaText: "超过一个月未使用 · 受信任" },
  ] },
];

function view(story: LockStory): LockView {
  const stations = story === "noStations" ? [] : STATIONS;
  const waits = story !== "on" && story !== "noStations" && story !== "prompt";
  return {
    available: true, locked: true, notice: false, role: "owner", manages: true, owner: true, canSign: true, signs: !waits,
    me: {
      device: "d_demo", code: "4BU-L2G", kind: "app", confirmed: !waits, waiting: waits,
      ...(PAIR[story] ? { pair: PAIR[story] } : {}),
    },
    signers: waits ? 1 : GROUPS.flatMap((g) => g.devices).filter((d) => d.signs).length,
    members: [{
      sub: "demo-you", email: "you@acme.dev", name: "你", role: "owner", you: true, nameText: "你", roleText: "Owner",
      groups: GROUPS.map((g) => ({ ...g, devices: g.devices.map((d) => ({ ...d, mine: d.id === "d_demo", removable: !waits && d.id !== "d_demo" })) })),
    }],
    stations, protected: stations.filter((s) => s.protected).length, renew: [], attention: 0,
  };
}

/** A member's new phone, met face to face, asking into two workspaces, one of them not the one open. */
function prompts(story: LockStory): LockPromptsView {
  if (story !== "prompt") return { pairing: [] };
  return {
    pairing: [{
      device: "d_phone", email: "li@acme.dev", name: "李二", kind: "app", label: "still.fail 安卓版 · Pixel 8", code: "482913", deviceText: "still.fail 安卓版 · Pixel 8",
      created_at: 1_760_000_000, until: 1_760_000_300_000, untilText: "14:05 前有效", workspaces: [{ id: "w_acme", name: "Acme" }, { id: "w_daily", name: "日常", emoji: "☀️" }],
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
