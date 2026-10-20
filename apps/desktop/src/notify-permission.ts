import { app } from "electron";
import { join } from "node:path";

export type SystemPermission = "granted" | "denied" | "default" | "unknown";

interface NotifyPermission {
  status(appId: string): string;
}

/** build/ (build.sh) when run from the source, the app's Resources when packaged, as main.ts has it. */
const resources = () => (app.isPackaged ? process.resourcesPath : join(__dirname, ".."));
let native: NotifyPermission | null | undefined;

/** Whether the system lets the app show notifications (apps/desktop/notify-permission): macOS's settings for this
 *  app's own bundle (appId unused there), Windows' for the AppUserModelID `appId`. "default": macOS has not asked yet.
 *  "unknown" on other platforms, and when the addon is missing or fails; it is loaded on the first call. */
export function systemPermission(appId: string): SystemPermission {
  if (process.platform !== "darwin" && process.platform !== "win32") return "unknown";
  if (native === undefined) {
    try { native = require(join(resources(), "notify-permission.node")) as NotifyPermission; }
    catch (error) { console.error("Notification permission: not known", error); native = null; }
  }
  try {
    const status = native?.status(appId);
    return status === "granted" || status === "denied" || status === "default" ? status : "unknown";
  } catch { return "unknown"; }
}
