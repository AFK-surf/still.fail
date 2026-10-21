// Isolated Electron fixture, bundled by diagnostics.mjs. Never starts a station or registers app links.
import { app, BrowserWindow, crashReporter } from "electron";
import { desktopDiagnostics } from "../src/diagnostics";

app.setPath("userData", process.env.DIAGNOSTICS_TEST_DIR!);
if (!app.requestSingleInstanceLock()) app.quit();
else {
  const log = desktopDiagnostics();
  app.whenReady().then(async () => {
    if (crashReporter.getUploadToServer()) throw new Error("crashes must stay local");
    const mode = process.env.DIAGNOSTICS_TEST_MODE;
    if (mode === "main-crash") process.crash();
    if (mode === "abrupt") process.exit(9);
    if (mode === "exception") {
      // Suppress Electron's default modal only in this fixture; the monitor still observes the error.
      process.on("uncaughtException", () => app.exit(1));
      setImmediate(() => { throw new Error("diagnostics fixture failure"); });
      return;
    }
    const window = new BrowserWindow({ show: false });
    await window.loadURL("data:text/html,<title>Diagnostics test</title>");
    if (mode === "renderer-crash") {
      window.webContents.once("render-process-gone", () => app.quit());
      window.webContents.forcefullyCrashRenderer();
    } else {
      log.write("test-ready");
      app.quit();
    }
  });
}
