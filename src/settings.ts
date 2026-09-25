// The configuration as a live, editable document. config.json stays the source
// of truth: edits are validated by parseConfig, written atomically (mode 600,
// it holds secrets), and then announced to whoever applies them.
import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { parseConfig, type Config, type RawConfig } from "./config.ts";

export class Settings {
  readonly path: string;
  readonly dataDir: string;
  #raw: RawConfig;
  #config: Config;
  readonly #listeners = new Set<(config: Config) => void>();

  constructor(path: string, dataDir: string) {
    this.path = path;
    this.dataDir = dataDir;
    this.#raw = existsSync(path) ? JSON.parse(readFileSync(path, "utf8")) as RawConfig : {};
    this.#config = parseConfig(this.#raw, dataDir);
  }

  static load(env: NodeJS.ProcessEnv = process.env): Settings {
    const dataDir = resolve(env.EMBER_DATA ?? join(homedir(), ".ember"));
    return new Settings(env.EMBER_CONFIG ?? join(dataDir, "config.json"), dataDir);
  }

  get config(): Config {
    return this.#config;
  }

  /** The config as stored, for editing. Callers must not mutate it; use update(). */
  get raw(): Readonly<RawConfig> {
    return this.#raw;
  }

  /** Tells listeners that derived state changed although the config did not (e.g. a profile check finished). */
  touch(): void {
    for (const listener of this.#listeners) listener(this.#config);
  }

  onChange(listener: (config: Config) => void): () => void {
    this.#listeners.add(listener);
    return () => this.#listeners.delete(listener);
  }

  /** Applies an edit. Throws (and changes nothing) if the result does not validate. */
  update(edit: (raw: RawConfig) => RawConfig): Config {
    const next = edit(structuredClone(this.#raw));
    const config = parseConfig(next, this.dataDir);
    this.#raw = next;
    this.#config = config;
    this.#write();
    for (const listener of this.#listeners) listener(config);
    return config;
  }

  #write(): void {
    mkdirSync(dirname(this.path), { recursive: true });
    const tmp = `${this.path}.tmp-${process.pid}`;
    writeFileSync(tmp, `${JSON.stringify(this.#raw, null, 2)}\n`, { mode: 0o600 });
    renameSync(tmp, this.path);
  }
}
