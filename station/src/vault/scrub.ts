// What a command run with a secret in its environment says, with the secret hidden (docs/vault.md, 三种用法): the value
// and the ways it is commonly written out (base64, base64url, URL-encoded, JSON-escaped) are each replaced with a mark,
// also when a chunk of output ends partway through one. Exact values, not shapes: unlike publish/redact.ts, nothing is
// guessed. A net for output only: a command that sends the value somewhere itself is not stopped here.

/// What a hidden value reads as.
export const HIDDEN = "[已隐藏]";

/// The forms of `value` hidden: the value as it is and as it is often written, the shortest worth hiding 4 bytes long.
export function formsOf(value: string): Buffer[] {
  const raw = Buffer.from(value, "utf8");
  const forms = [raw, Buffer.from(raw.toString("base64")), Buffer.from(raw.toString("base64url")), Buffer.from(encodeURIComponent(value)), Buffer.from(JSON.stringify(value).slice(1, -1))];
  // base64 of the value at each of the three offsets it can start at inside a longer text (`user:token` encoded whole):
  // the characters whose six bits are all the value's own.
  for (const lead of [0, 1, 2]) {
    const padded = Buffer.concat([Buffer.alloc(lead), raw]);
    const from = Math.ceil((lead * 4) / 3);
    const to = Math.floor(((lead + raw.length) * 4) / 3);
    if (to - from < 8) continue;
    for (const alphabet of ["base64", "base64url"] as const) forms.push(Buffer.from(padded.toString(alphabet).slice(from, to)));
  }
  const seen = new Set<string>();
  return forms.filter((f) => f.length >= 4 && !seen.has(f.toString("latin1")) && (seen.add(f.toString("latin1")), true));
}

/// A stream's scrubber: `push` each chunk, `end` at the end; each gives what may be shown so far. Holds back as much of
/// the end of what it has seen as could be the start of a form, until the next chunk says whether it is.
export class Scrubber {
  readonly #forms: Buffer[];
  readonly #mark: Buffer;
  readonly #keep: number;
  #held = Buffer.alloc(0);

  constructor(values: string[], mark = HIDDEN) {
    // The longest first: a form inside another is hidden with it.
    this.#forms = values.flatMap(formsOf).sort((a, b) => b.length - a.length);
    this.#mark = Buffer.from(mark);
    this.#keep = Math.max(0, ...this.#forms.map((f) => f.length - 1));
  }

  push(chunk: Buffer): Buffer {
    const all = Buffer.concat([this.#held, chunk]);
    const [out, rest] = this.#scan(all, false);
    this.#held = rest;
    return out;
  }

  end(): Buffer {
    const [out] = this.#scan(this.#held, true);
    this.#held = Buffer.alloc(0);
    return out;
  }

  /// What of `all` may go out, and what is held back (`last`: nothing is).
  #scan(all: Buffer, last: boolean): [Buffer, Buffer] {
    const parts: Buffer[] = [];
    let at = 0;
    let from = 0;
    // Positions from which a whole form could still fit are matched; past that, only when this is the last chunk.
    const limit = last ? all.length : Math.max(0, all.length - this.#keep);
    while (at < limit) {
      const hit = this.#forms.find((f) => all.length - at >= f.length && all.subarray(at, at + f.length).equals(f));
      if (hit === undefined) {
        at++;
        continue;
      }
      parts.push(all.subarray(from, at), this.#mark);
      at += hit.length;
      from = at;
    }
    parts.push(all.subarray(from, Math.max(from, limit)));
    return [Buffer.concat(parts), Buffer.from(all.subarray(Math.max(from, limit)))];
  }
}

/// `text` scrubbed whole.
export function scrub(text: string, values: string[]): string {
  const s = new Scrubber(values);
  return Buffer.concat([s.push(Buffer.from(text)), s.end()]).toString("utf8");
}
