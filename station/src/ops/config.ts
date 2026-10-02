// config.json as it is now: read again when the file changed (by its size and time), so a page's edit applies to the
// next thing that reads it. A file that is not there or does not parse is `{}` (the defaults), as the Rust starts.
import { readFileSync, statSync } from "node:fs";
import { join } from "node:path";

export class ConfigFile {
  readonly path: string;
  private seen = "";
  private value: any = {};

  constructor(data: string) {
    this.path = process.env.STILLFAIL_CONFIG || process.env.EMBER_CONFIG || join(data, "config.json");
  }

  raw(): any {
    let now = "none";
    try {
      const st = statSync(this.path);
      now = `${st.size}:${st.mtimeMs}`;
    } catch {}
    if (now !== this.seen) {
      this.seen = now;
      try {
        this.value = now === "none" ? {} : JSON.parse(readFileSync(this.path, "utf8"));
      } catch {
        this.value = {};
      }
    }
    return this.value;
  }
}
