// config.json as a live, editable document (settings.rs): the file stays the source of truth. Edits are checked,
// written atomically (mode 600: it holds secrets) and told to whoever listens; fields this station does not know are
// kept as they are. Edited by something else (the installer, `stillfail channel`, a person): read again when the file
// changed (by its size and time) on the next read, and told then. A file that is not there is `{}` (the defaults).
import { mkdirSync, renameSync, statSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { setStationLang } from "./i18n.ts";
import { readJsonFile } from "./json-file.ts";

/// Checks a config before it is taken (config.rs `parse_config`'s refusals): throws what is wrong.
export type ConfigCheck = (raw: any, data: string) => void;

export class ConfigFile {
  readonly path: string;
  readonly data: string;
  /// What an edit must pass (the accounts module gives parse_config's checks).
  check: ConfigCheck = () => {};
  private seen = "";
  private value: any = {};
  private invalid: Error | null = null;
  private listeners = new Set<(raw: any) => void>();

  constructor(data: string) {
    this.data = data;
    this.path = process.env.STILLFAIL_CONFIG || join(data, "config.json");
    this.raw();
  }

  /// The config as stored now. Not to be changed in place: `update` does that.
  raw(): any {
    const now = this.stamp();
    if (now !== this.seen) {
      const first = this.seen === "";
      try {
        this.value = now === "none" ? {} : readJsonFile(this.path);
        this.seen = now;
        this.invalid = null;
      } catch (error) {
        this.seen = now;
        this.invalid = error instanceof Error ? error : new Error(String(error));
        // An initial read must not silently turn an unreadable config into defaults. Later, keep the last good value
        // for readers, but refuse edits until the file can be read again.
        if (first) throw this.invalid;
        return this.value;
      }
      setStationLang(this.value?.language);
      if (!first) this.tell();
    }
    return this.value;
  }

  /// Hears each config as it changes (by an edit here or in the file); gives the function that stops it.
  listen(listener: (raw: any) => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  /// Applies an edit to a copy; written and told only if the result checks out (else it throws, nothing changed).
  update(edit: (raw: any) => void): any {
    const next = structuredClone(this.raw());
    if (this.invalid !== null) throw this.invalid;
    edit(next);
    this.check(next, this.data);
    mkdirSync(dirname(this.path), { recursive: true });
    const tmp = `${this.path.replace(/\.json$/, "")}.json.tmp-${process.pid}`;
    writeFileSync(tmp, `${JSON.stringify(next, null, 2)}\n`, { mode: 0o600 });
    renameSync(tmp, this.path);
    this.value = next;
    this.seen = this.stamp();
    setStationLang(next?.language);
    this.tell();
    return next;
  }

  private stamp(): string {
    try {
      const st = statSync(this.path);
      return `${st.size}:${st.mtimeMs}:${st.ino}`;
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ENOENT") return "none";
      throw error;
    }
  }

  private tell() {
    for (const listener of this.listeners) {
      try {
        listener(this.value);
      } catch {}
    }
  }
}
