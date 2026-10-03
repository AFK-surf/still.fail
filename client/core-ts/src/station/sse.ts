// Server-sent events: a text/event-stream split into (event name, data) as chunks arrive (station.rs `SseParser`).

export class SseParser {
  #buffer: number[] = [];

  feed(chunk: Uint8Array): [string, string][] {
    // CR only ever comes as CRLF here (data is JSON, which escapes it).
    for (const b of chunk) if (b !== 13) this.#buffer.push(b);
    const events: [string, string][] = [];
    for (;;) {
      let end = -1;
      for (let i = 0; i + 1 < this.#buffer.length; i++) {
        if (this.#buffer[i] === 10 && this.#buffer[i + 1] === 10) {
          end = i;
          break;
        }
      }
      if (end < 0) break;
      // A block ends at a newline, so it never splits a UTF-8 sequence.
      const block = new TextDecoder().decode(new Uint8Array(this.#buffer.slice(0, end)));
      this.#buffer = this.#buffer.slice(end + 2);
      let name = "message";
      const data: string[] = [];
      for (const line of block.split("\n")) {
        if (line.startsWith("event:")) name = line.slice(6).trim();
        else if (line.startsWith("data:")) {
          const rest = line.slice(5);
          data.push(rest.startsWith(" ") ? rest.slice(1) : rest);
        }
      }
      if (data.length > 0) events.push([name, data.join("\n")]);
    }
    return events;
  }
}
