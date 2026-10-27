// Server-sent events: a text/event-stream split into (event name, data) as chunks arrive (station.rs `SseParser`), with
// its id where the event has one; a block with an id and no data is an id alone (name and data "").
//
// What has come and is not a whole block yet is kept as bytes, and only what came since is looked through for the
// blank line that ends one (a big event comes in many chunks: looking through all it holds at each was quadratic, and
// pushing it a byte at a time into an array, then slicing what was left after each block, made a phone's core spend
// most of its time here with agents at work).

export class SseParser {
  #buffer = new Uint8Array(4096);
  /// What has come and is not read yet: from `#start` to `#end`; up to `#looked` looked through for a blank line.
  #start = 0;
  #end = 0;
  #looked = 0;
  readonly #decoder = new TextDecoder();

  feed(chunk: Uint8Array): [string, string, string?][] {
    this.#append(chunk);
    const events: [string, string, string?][] = [];
    for (;;) {
      const end = this.#blank();
      if (end < 0) break;
      // A block ends at a newline, so it never splits a UTF-8 sequence.
      const block = this.#decoder.decode(this.#buffer.subarray(this.#start, end));
      this.#start = end + 2;
      this.#looked = this.#start;
      let name = "message";
      let id: string | null = null;
      const data: string[] = [];
      for (const line of block.split("\n")) {
        if (line.startsWith("event:")) name = line.slice(6).trim();
        else if (line.startsWith("id:")) id = line.slice(3).trim();
        else if (line.startsWith("data:")) {
          const rest = line.slice(5);
          data.push(rest.startsWith(" ") ? rest.slice(1) : rest);
        }
      }
      if (data.length > 0) events.push(id === null ? [name, data.join("\n")] : [name, data.join("\n"), id]);
      // An id alone: where the station's log is, no event (events.ts, a stream read afresh).
      else if (id !== null) events.push(["", "", id]);
    }
    if (this.#start === this.#end) this.#start = this.#end = this.#looked = 0;
    return events;
  }

  /// `chunk` after what is kept, without its CRs (CR only ever comes as CRLF here: data is JSON, which escapes it).
  #append(chunk: Uint8Array): void {
    const kept = this.#end - this.#start;
    if (this.#end + chunk.length > this.#buffer.length) {
      // (what is kept moved to the front, into room for the chunk)
      const to = kept + chunk.length > this.#buffer.length ? new Uint8Array(Math.max(this.#buffer.length * 2, kept + chunk.length)) : this.#buffer;
      if (to === this.#buffer) to.copyWithin(0, this.#start, this.#end);
      else to.set(this.#buffer.subarray(this.#start, this.#end));
      this.#looked -= this.#start;
      this.#start = 0;
      this.#end = kept;
      this.#buffer = to;
    }
    if (chunk.indexOf(13) < 0) {
      this.#buffer.set(chunk, this.#end);
      this.#end += chunk.length;
      return;
    }
    for (const b of chunk) if (b !== 13) this.#buffer[this.#end++] = b;
  }

  /// Where the first blank line (two newlines) of what is kept starts, -1 none yet; what was looked through, not again.
  #blank(): number {
    let i = this.#buffer.subarray(0, this.#end).indexOf(10, Math.max(this.#looked, this.#start));
    while (i >= 0 && i + 1 < this.#end) {
      if (this.#buffer[i + 1] === 10) return i;
      i = this.#buffer.subarray(0, this.#end).indexOf(10, i + 1);
    }
    // (a newline at the very end may begin one with the next chunk)
    this.#looked = i >= 0 ? i : this.#end;
    return -1;
  }
}
