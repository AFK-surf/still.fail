// A Mac station's grants to still.fail Helper for the stories (docs/remote-screens.md "Grants"): the demo station's
// overview with `permissions` as the core puts them in words (client/core-ts/src/permissions.ts), in each state its page
// shows: every one given; some not (asked for from here); one asked for, its window up on the Mac, the screen drivable
// (opened to grant it there) or not (the person goes to the Mac); a read-only member's; and a station that says none
// (not a Mac), whose page has no such section.
import type { DemoExtension } from "../src/demo/mount.tsx";
import type { StationGrant, StationPermissions, StationView } from "../src/core/shapes.ts";

export type PermissionsStory = "granted" | "missing" | "asking" | "askingThere" | "readOnly" | "none";

const ROWS: [string, string, string][] = [
  ["capture", "屏幕录制", "远程查看此屏幕，agent 截屏"],
  ["control", "辅助功能", "远程控制此屏幕，agent 操作屏幕"],
  ["documents", "文稿", "在「文件」中访问文稿"],
  ["desktop", "桌面", "在「文件」中访问桌面"],
  ["downloads", "下载", "在「文件」中访问下载，接收拖入屏幕的文件"],
  ["removable", "外接磁盘", "在「文件」中访问外接磁盘"],
  ["network", "网络磁盘", "在「文件」中访问网络磁盘"],
];
const FEATURE: Record<string, string> = { control: "远程控制屏幕", desktop: "访问桌面", removable: "访问外接磁盘", network: "访问网络磁盘" };
const SCREEN = "/w/demo/s/local/screen/desktop";

/** The station's grants as its page has them in `story`; null for one that says none. */
export function permissionsOf(story: PermissionsStory): StationPermissions | null {
  if (story === "none") return null;
  // Missing: the Desktop and the disks; the screen not drivable (Accessibility missing too) where the person goes to the Mac.
  const missing = story === "granted" ? [] : story === "askingThere" ? ["control", "desktop", "removable", "network"] : ["desktop", "removable", "network"];
  const asking = story === "asking" ? "desktop" : story === "askingThere" ? "control" : null;
  const screen = !missing.includes("control");
  const grants: StationGrant[] = ROWS.map(([id, name, line]) => ({
    id, name, granted: !missing.includes(id), asking: id === asking,
    line: id === asking ? (screen ? "授权窗口已在该 Mac 上打开，可在远程屏幕中点击「允许」" : "授权窗口已在该 Mac 上打开，请在该 Mac 上点击「允许」") : line,
  }));
  return {
    grants,
    ...(missing.length ? { note: `当前不可用：${missing.map((g) => FEATURE[g]).join("、")}` } : {}),
    ...(screen ? { screen: SCREEN } : {}),
    canRequest: story !== "readOnly",
  };
}

/** The demo with its station's grants as `story` says (a grant asked for answers that its window is up), over `more`
 *  (the station's screens, for the one that opens the desktop once a grant is asked for). */
export function permissionsDemo(story: PermissionsStory, more: DemoExtension = {}): DemoExtension {
  const permissions = permissionsOf(story);
  return {
    topic: (topic) => more.topic?.(topic),
    then: (topic, value) => (topic.topic === "stations" && Array.isArray(value)
      ? (value as StationView[]).map((s) => (s.overview ? { ...s, overview: { ...s.overview, ...(permissions ? { permissions } : {}) } } : s))
      : more.then?.(topic, value)),
    call: (name, params) => (name === "permissions.request" ? { window: "up", screen: permissions?.screen != null } : more.call?.(name, params)),
    stream: (name, params, emit, signal) => more.stream?.(name, params, emit, signal),
  };
}
