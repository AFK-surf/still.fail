// The screens a story is shown on in the gallery: the Mac app's window (its buttons where the app puts them,
// apps/desktop/src/main.ts trafficLightPosition) or full screen, and phones, each with its own safe area (status bar,
// notch, island or punch hole; home indicator or navigation buttons). The story's page takes a device's insets
// through --safe-top … (styles/global.css.ts) and the Mac's frame through data-desktop / data-fullscreen, as the
// desktop app's preload sets them; the gallery draws what the system draws over the page.

export interface Device {
  id: string;
  label: string;
  group: string;
  width: number;
  height: number;
  /** The screen's (or the window's) corner. */
  radius: number;
  /** The Mac app's window ("window", its three buttons) or full screen. */
  mac?: "window" | "full";
  /** A phone's safe area, in CSS px. */
  safe?: { top: number; bottom: number };
  /** What sits in the top of a phone's screen. */
  cutout?: { kind: "island" | "notch" | "hole"; width: number; height: number; top: number };
  /** What sits at its foot: a home indicator (iOS, Android's gestures) or Android's three buttons. */
  foot?: "indicator" | "buttons";
  os?: "ios" | "android";
}

export const DEVICES: Device[] = [
  { id: "mac", label: "Mac 窗口", group: "Mac", width: 1280, height: 800, radius: 16, mac: "window" },
  { id: "mac-full", label: "Mac 全屏", group: "Mac", width: 1280, height: 800, radius: 10, mac: "full" },
  {
    id: "iphone-16-pro", label: "iPhone 16 Pro", group: "iPhone", os: "ios", width: 402, height: 874, radius: 55,
    safe: { top: 62, bottom: 34 }, cutout: { kind: "island", width: 126, height: 37, top: 11 }, foot: "indicator",
  },
  {
    id: "iphone-13-mini", label: "iPhone 13 mini（刘海）", group: "iPhone", os: "ios", width: 375, height: 812, radius: 44,
    safe: { top: 50, bottom: 34 }, cutout: { kind: "notch", width: 154, height: 32, top: 0 }, foot: "indicator",
  },
  { id: "iphone-se", label: "iPhone SE（Home 键）", group: "iPhone", os: "ios", width: 375, height: 667, radius: 0, safe: { top: 20, bottom: 0 } },
  {
    id: "pixel-9", label: "Pixel 9（手势导航）", group: "Android", os: "android", width: 412, height: 915, radius: 40,
    safe: { top: 48, bottom: 24 }, cutout: { kind: "hole", width: 22, height: 22, top: 13 }, foot: "indicator",
  },
  {
    id: "galaxy-s24", label: "Galaxy S24（三键导航）", group: "Android", os: "android", width: 360, height: 780, radius: 36,
    safe: { top: 36, bottom: 48 }, cutout: { kind: "hole", width: 18, height: 18, top: 10 }, foot: "buttons",
  },
];

export const device = (id: string | null | undefined): Device | undefined => DEVICES.find((d) => d.id === id);

/** Puts the page on `d`: its safe area, or the Mac app's frame. */
export function wear(d: Device): void {
  const root = document.documentElement;
  if (d.mac) {
    root.dataset.desktop = "inset";
    root.toggleAttribute("data-fullscreen", d.mac === "full");
  }
  if (d.safe) {
    root.style.setProperty("--safe-top", `${d.safe.top}px`);
    root.style.setProperty("--safe-bottom", `${d.safe.bottom}px`);
  }
}
