// Claude Code on macOS keeps its login in the keychain, under a name made from
// its config directory's path, and falls back to <config dir>/.credentials.json
// only when the keychain refuses. A profile's login has to live in its home:
// the home is renamed after a sign-in (the keychain item stays behind under the
// old path), quota reads the file, and a keychain item is out of reach of the
// station's other processes. So profile processes get a `security` first on
// their PATH that finds nothing and stores nothing (exit 44, "not found"), and
// Claude Code reads and writes the file, as it does on Linux. The machine's own
// login is not touched: machine profiles run on a token handed to them.
import { chmodSync, existsSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const STUB = "#!/bin/sh\n# ember: profile logins are kept in files, not the keychain (src/no-keychain.ts).\nexit 44\n";

/** The directory with the stand-in `security`, made (again) if missing. */
function stubDir(): string {
  const dir = join(tmpdir(), `ember-no-keychain-${process.getuid?.() ?? 0}`);
  const path = join(dir, "security");
  if (!existsSync(path)) {
    mkdirSync(dir, { recursive: true });
    writeFileSync(path, STUB);
    chmodSync(path, 0o755);
  }
  return dir;
}

/** `env` with Claude Code kept off the keychain (macOS only; elsewhere it uses the file anyway). */
export function fileCredentials<T extends Record<string, string | undefined>>(env: T): T {
  if (process.platform !== "darwin") return env;
  return { ...env, PATH: `${stubDir()}:${env.PATH ?? process.env.PATH ?? ""}` };
}
