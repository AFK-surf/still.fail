// A station installed on this machine on its own (cloud/src/install.ts, install-windows.ts): a service of the user's
// that runs the machine's station at login, whether the app is open or not. The app manages it as it does the one it
// carries (the settings' 本机 Station page): starts, stops and restarts the service, and brings it up to date in place
// by running the installer without a token, as `stillfail update` does (turns handed over or drained, a station from
// before the rename moved). While one is installed the app runs none of its own: the service is this machine's.
import { execFile, execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

export interface Service {
  /** launchd (macOS), a systemd user service (Linux) or a scheduled task (Windows). */
  kind: "launchd" | "systemd" | "task";
  /** Its label, unit or task name. */
  name: string;
  /** Where it is defined (the plist, the unit file); none for a task. */
  definition?: string;
}

/** The names the installer gives it, now and before the rename (install.ts: label, old_label, unit, old_unit). */
const LABELS = ["fail.still.station", "org.3720.ember.station"];
const UNITS = ["stillfail-station.service", "ember-station.service"];
const TASK = "still.fail station";

let task: { at: number; there: boolean } | null = null;

/** The service installed here, if one is: read anew each time (a scheduled task's, at most once a minute). */
export function installedService(): Service | null {
  if (process.platform === "darwin") {
    for (const name of LABELS) {
      const definition = join(homedir(), "Library", "LaunchAgents", `${name}.plist`);
      if (existsSync(definition)) return { kind: "launchd", name, definition };
    }
    return null;
  }
  if (process.platform === "linux") {
    const dir = join(process.env.XDG_CONFIG_HOME || join(homedir(), ".config"), "systemd", "user");
    for (const name of UNITS) {
      const definition = join(dir, name);
      if (existsSync(definition)) return { kind: "systemd", name, definition };
    }
    return null;
  }
  if (process.platform === "win32") {
    if (!task || Date.now() - task.at > 60_000) {
      let there = false;
      try {
        execFileSync("schtasks", ["/Query", "/TN", TASK], { stdio: "ignore", windowsHide: true });
        there = true;
      } catch { /* none */ }
      task = { at: Date.now(), there };
    }
    return task.there ? { kind: "task", name: TASK } : null;
  }
  return null;
}

function run(file: string, args: string[], options: { env?: NodeJS.ProcessEnv; timeout?: number } = {}): Promise<string> {
  return new Promise((resolve, reject) => {
    execFile(file, args, { env: options.env ?? process.env, timeout: options.timeout ?? 30_000, maxBuffer: 4 << 20, windowsHide: true }, (error, stdout, stderr) => {
      if (!error) return resolve(stdout);
      // What it said last is why: an installer's whole output is long.
      const said = `${stdout}\n${stderr}`.trim().split("\n").slice(-6).join("\n");
      reject(new Error(said || error.message));
    });
  });
}

/** Starts, stops or restarts the service. A stopped one starts again at the next login (launchd, systemd) or sign-in. */
export async function controlService(service: Service, action: "start" | "stop" | "restart"): Promise<void> {
  if (service.kind === "launchd") {
    const domain = `gui/${process.getuid!()}`;
    const target = `${domain}/${service.name}`;
    if (action === "stop") return void (await run("launchctl", ["bootout", target]));
    // Not loaded (stopped here, or never since login): loaded, which starts it (RunAtLoad).
    try {
      await run("launchctl", action === "restart" ? ["kickstart", "-k", target] : ["kickstart", target]);
    } catch {
      await run("launchctl", ["bootstrap", domain, service.definition!]);
    }
    return;
  }
  if (service.kind === "systemd") return void (await run("systemctl", ["--user", action, service.name]));
  if (action !== "start") await run("schtasks", ["/End", "/TN", service.name]).catch(() => undefined);
  if (action !== "stop") await run("schtasks", ["/Run", "/TN", service.name]);
}

/**
 * The PATH the service runs with: the installer gives the service the caller's (where the agents are found), so an
 * update from the app, opened from Finder with launchd's short one, gives it the one it has. `fallback` when it says none.
 */
export function servicePath(service: Service, fallback: string): string {
  try {
    if (service.kind === "launchd") {
      return execFileSync("plutil", ["-extract", "EnvironmentVariables.PATH", "raw", "-o", "-", service.definition!], { encoding: "utf8" }).trim() || fallback;
    }
    if (service.kind === "systemd") {
      const line = readFileSync(service.definition!, "utf8").split("\n").find((l) => /^Environment="?PATH=/.test(l));
      const path = line?.replace(/^Environment="?PATH=/, "").replace(/"$/, "");
      return path || fallback;
    }
  } catch { /* the app's */ }
  return fallback;
}

/**
 * Brings the installed station up to date in place: the installer of `origin` run without a token, which updates a
 * station already in a workspace and leaves its data and service where they are. `env`: the PATH (servicePath) and
 * the channel the app is on. Up to 10 minutes (a drain waits for turns to end).
 */
export async function updateInstalled(service: Service, origin: string, env: NodeJS.ProcessEnv): Promise<void> {
  const { ELECTRON_RUN_AS_NODE: _, ...rest } = env;
  if (service.kind === "task") {
    await run("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", `& ([scriptblock]::Create((irm '${origin}/install.ps1')))`], { env: rest, timeout: 600_000 });
    return;
  }
  // Got first, then run: piped straight in, a download that fails would run an empty script, and that succeeds.
  await run("/bin/sh", ["-c", 'script=$(curl -fsSL "$0/install.sh") && printf "%s\n" "$script" | sh', origin], { env: rest, timeout: 600_000 });
}
