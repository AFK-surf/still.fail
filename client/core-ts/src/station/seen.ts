// What the sync holds of each station beyond the records (its link, its host, its sessions at work, a topic's log or
// error, its screens, its logins) as its readers see it change: a station topic made from any of it reads what it
// uses here, and is made again as that changes (reactive.ts `Marks`), not by a list of the topics each change is
// for. A change with no key is of all of its kind on that station.
import { Marks } from "../reactive.ts";

export type Kind = "link" | "live" | "host" | "log" | "screens" | "terminals" | "logins" | "loginScreen";

export class Seen {
  readonly #kinds = new Map<Kind, Marks>();

  #of(kind: Kind): Marks {
    let marks = this.#kinds.get(kind);
    if (!marks) this.#kinds.set(kind, (marks = new Marks()));
    return marks;
  }

  /// What a station's `kind` is (`key`: one of it, a topic's log by its key, a session at work by its key).
  read(address: string, kind: Kind, key?: string): void {
    const marks = this.#of(kind);
    marks.read(address);
    if (key !== undefined) marks.read(`${address} ${key}`);
  }

  /// What every station's `kind` is.
  readAll(kind: Kind): void {
    this.#of(kind).read();
  }

  touch(address: string, kind: Kind, key?: string): void {
    this.#of(kind).touch(key === undefined ? address : `${address} ${key}`);
  }
}
