// Server-sent events: a text/event-stream split into (event name, data) as chunks arrive, with
// its id where the event has one; a block with an id and no data is an id alone (name and data "").
//
// The reader is the base's in MoonBit (libs/base/src/wire/sse.mbt), written once there for a core in MoonBit and for
// this one, which takes it as it is built for JavaScript (libs/base/js/base.js, committed with its types:
// libs/base/build.sh; a change to how a stream is read is made there and built, never here). It reads as the one
// that was here read, to the byte: what has come and is no whole block yet kept as bytes, only what came since
// looked through for the blank line that ends one. Nothing is converted on the way: the chunk goes in as it is (and
// is not kept), the events come out as the arrays and strings they are.
import { sse_feed, sse_new } from "../../../libs/base/js/base.js";

export class SseParser {
  readonly #sse = sse_new();

  feed(chunk: Uint8Array): [string, string, string?][] {
    return sse_feed(this.#sse, chunk) as [string, string, string?][];
  }
}
