import { app, crashReporter } from "electron";
import { mkdirSync } from "node:fs";
import { join } from "node:path";
import { DiagnosticLog } from "./diagnostic-log.mts";

/** Installed by the primary instance, before ready and before any child processes are created. */
export function desktopDiagnostics(): DiagnosticLog {
  const log = new DiagnosticLog(join(app.getPath("userData"), "diagnostics"));
  log.start({ version: app.getVersion(), electron: process.versions.electron, platform: process.platform, arch: process.arch });
  let fatal = false;
  // Observe without swallowing Node's fatal exceptions or changing its rejection policy.
  process.on("uncaughtExceptionMonitor", (error, origin) => {
    fatal = true;
    log.write("main-exception", { origin, error });
  });
  process.on("exit", (code) => log.write("process-exit", { code }));
  app.on("before-quit", () => log.write("before-quit"));
  app.on("will-quit", () => log.write("will-quit"));
  app.on("quit", (_event, code) => {
    if (fatal) log.write("quit-after-exception", { code });
    else log.finish(code);
  });
  app.on("child-process-gone", (_event, details) => {
    log.write("child-process-gone", { type: details.type, reason: details.reason, exitCode: details.exitCode, serviceName: details.serviceName });
  });
  app.on("browser-window-created", (_event, window) => {
    const id = window.id;
    log.write("window-created", { window: id });
    window.on("close", () => log.write("window-close-requested", { window: id }));
    window.on("closed", () => log.write("window-closed", { window: id }));
    window.on("unresponsive", () => log.write("window-unresponsive", { window: id }));
    window.on("responsive", () => log.write("window-responsive", { window: id }));
    window.on("query-session-end", () => log.write("system-session-ending", { window: id }));
    window.webContents.on("render-process-gone", (_event, details) => {
      log.write("renderer-gone", { window: id, reason: details.reason, exitCode: details.exitCode });
    });
  });
  try {
    const dumps = join(app.getPath("userData"), "diagnostics", "crashes");
    mkdirSync(dumps, { recursive: true });
    app.setPath("crashDumps", dumps);
    crashReporter.start({ uploadToServer: false });
    log.write("crash-reporter-started", { uploadToServer: false });
  } catch (error) {
    log.write("crash-reporter-failed", { error });
  }
  return log;
}
