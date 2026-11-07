import { log } from "../ops/log.ts";
import { BackgroundIndexBuilder } from "../store/background-index-builder.ts";
import { installSessionDirectories, sessionDirectoriesReady, sessionDirectoriesStep, sessionDirectory, sessionDirectoryArguments, SESSION_DIR_LIVE_MANY, type DirectorySession } from "../store/session-directory.ts";
import type { Store } from "../store/store.ts";

/// A memory check answers immediately while one shared worker prepares the directory lookup after handover.
export class SessionDirectoryBuilder extends BackgroundIndexBuilder {
  constructor(store: Store, previous: Promise<void>, workerFile?: URL) {
    super(store, previous, {
      scope: "memory", name: "session directory", previousName: "directories", kind: "directory",
      install: () => installSessionDirectories(store.db), ready: () => sessionDirectoriesReady(store.db),
      step: () => sessionDirectoriesStep(store.db),
    }, workerFile);
  }

  find(dir: string): DirectorySession | null {
    if (this.stopped) return null;
    try {
      const found = sessionDirectory(this.store.db, dir);
      if (found !== null) {
        if (!sessionDirectoriesReady(this.store.db)) this.buildIf(() => true);
        return found;
      }
    } catch (error) {
      log.warn("memory", "the session directory lookup could not be read", { error: (error as Error).message });
    }
    this.buildIf(() => true);
    return null;
  }

  /// The resource page attributes independent processes by directories mentioned in their arguments.
  findArguments(lines: readonly string[], home: string): Map<string, string> | null {
    if (this.stopped) return null;
    if (!lines.some((line) => line.includes("/"))) return new Map();
    try {
      const found = sessionDirectoryArguments(this.store.db, lines, home);
      if (!sessionDirectoriesReady(this.store.db) && this.store.db.prepare(SESSION_DIR_LIVE_MANY).get() !== undefined) this.buildIf(() => true);
      return found;
    } catch (error) {
      log.warn("resources", "the session directory lookup could not be read", { error: (error as Error).message });
      this.buildIf(() => true);
      return null;
    }
  }
}
