// The files' page for the stories (docs/drive.md "The files' page"): the demo's Studio and a second station of the
// workspace, MBA (its disk nearly full), each with its folders; the person's favourites; copies between them under way,
// done and failed (the `driveTransfers` topic as the core puts it together: client/core-ts/src/views/transfers.ts); and
// what a copy asked answers.
import type { DemoExtension } from "../src/demo/mount.tsx";
import type { DriveEntry, DriveFolder, DriveKind, DriveTransferShown, StationView } from "../src/core/shapes.ts";

const MBA = "demo/mba";
const NOW = Date.now();

type Made = [name: string, kind: DriveKind, size: number, minutes: number];
const FOLDERS: Record<string, Made[]> = {
  "/Users/mei": [["照片", "folder", 0, 60], ["项目", "folder", 0, 300], ["Downloads", "folder", 0, 40], ["Documents", "folder", 0, 900], ["login-375.png", "image", 240_000, 9_000]],
  "/Users/mei/照片": [["2026", "folder", 0, 60], ["旅行", "folder", 0, 9_000], ["首页截图.png", "image", 640_000, 12_000], ["IMG_0412.heic", "image", 2_100_000, 14_000]],
  "/Users/mei/项目": [["cue", "folder", 0, 30], ["演示录屏.mp4", "video", 48_234_496, 2_000]],
};

function folder(path: string): DriveFolder {
  const entries = (FOLDERS[path] ?? []).map(([name, kind, size, minutes]): DriveEntry => {
    const d = new Date(NOW - minutes * 60_000);
    return {
      name, dir: kind === "folder", size, mtime: d.getTime(), type: "", kind,
      sizeText: kind === "folder" ? "" : size >= 1_048_576 ? `${(size / 1_048_576).toFixed(1)} MB` : `${Math.round(size / 1024)} KB`,
      timeText: `${d.getMonth() + 1}/${d.getDate()}`,
    };
  });
  const folders = entries.filter((e) => e.dir).length;
  return { path: "", entries, folders, files: entries.length - folders, countText: `${folders} 个文件夹 · ${entries.length - folders} 个文件` };
}

const transfer = (over: Partial<DriveTransferShown>): DriveTransferShown => ({
  id: "t1", station: MBA, stationName: "MBA", fromStation: "demo/local", fromStationName: "Studio", fromRoot: "/Users/lin", fromPath: "Downloads",
  names: ["发版录屏 1014.mp4"], toRoot: "/Users/mei", toPath: "项目", toText: "MBA › 项目", title: "发版录屏 1014.mp4", move: false, state: "copying",
  active: true, progress: 0.38, total: 50_541_773, copied: 19_205_873, count: 1, files: 1, current: "发版录屏 1014.mp4", statusText: "18.3 MB / 48.2 MB",
  createdAt: NOW - 60_000, ...over,
});

/** The transfers the stories show: one copying, one waiting its turn, one failed (its station away), one done. */
export const TRANSFERS: DriveTransferShown[] = [
  transfer({}),
  transfer({ id: "t2", names: ["设计稿"], title: "设计稿", state: "queued", progress: 0, copied: 0, total: 0, statusText: "排队中", createdAt: NOW - 30_000, toText: "MBA › Documents", toPath: "Documents" }),
  transfer({ id: "t3", station: "demo/local", stationName: "Studio", fromStation: MBA, fromStationName: "MBA", names: ["备份.tar"], title: "备份.tar", state: "failed", active: false, progress: 0.4, statusText: "失败：station is not reachable", error: "station is not reachable", toText: "Studio › Downloads", createdAt: NOW - 600_000 }),
  transfer({ id: "t4", names: ["login-375.png", "export-1013.csv"], title: "login-375.png 等 2 项", state: "done", active: false, progress: 1, total: 544_768, copied: 544_768, files: 2, count: 2, statusText: "已完成 · 532 KB", toText: "MBA › 照片", toPath: "照片", createdAt: NOW - 1_200_000, endedAt: NOW - 1_180_000 }),
];

/** Studio and MBA; `transfers`: copies under way and ended. */
export function filesDemo(transfers: DriveTransferShown[] = []): DemoExtension {
  return {
    topic: (t) => {
      if (t.topic === "driveTransfers") return { supported: true, loaded: true, transfers };
      if (t.topic === "drive" && t.station === MBA) {
        const root = String(t.root);
        return folder(t.path ? `${root}/${t.path}` : root);
      }
      return undefined;
    },
    then: (t, value) => {
      if (t.topic !== "stations" || !Array.isArray(value)) return undefined;
      const studio = value[0] as StationView;
      const mba: StationView = {
        ...studio, station: MBA, id: "mba", name: "MBA", summary: "Apple M3 · 在线",
      };
      if (studio.overview) mba.overview = {
          ...studio.overview,
          disk: { freeBytes: 21_474_836_480, totalBytes: 245_107_195_904 },
          drive: { anywhere: true, home: "/Users/mei", roots: [{ path: "/Users/mei/照片", name: "照片", state: "ok" }], watch: true, transfers: true },
      };
      const withTransfers = studio.overview?.drive ? { ...studio, overview: { ...studio.overview, drive: { ...studio.overview.drive, transfers: true } } } : studio;
      return [withTransfers, mba];
    },
    call: (name, params) => {
      if (name === "drive.transfer") return { transfer: transfers[0] ?? null };
      if (name !== "drive.folders" || params.path) return undefined;
      // Each station's places, as its row opens: its home, the home's own folders, its disks.
      const home = params.station === MBA ? "/Users/mei" : "/Users/lin";
      const place = (name: string, path: string, disk = false) => ({ name, path, unreadable: false, ...(disk ? { disk: true } : {}) });
      const places = params.station === MBA
        ? [place("主目录", home), place("文稿", `${home}/Documents`), place("下载", `${home}/Downloads`)]
        : [place("主目录", home), place("桌面", `${home}/Desktop`), place("文稿", `${home}/Documents`), place("下载", `${home}/Downloads`), place("T7", "/Volumes/T7", true)];
      return { path: home, parent: "/Users", home, entries: [], unreadable: false, crumbs: [{ name: "主目录", path: home }], places };
    },
  };
}
