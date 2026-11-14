// The base as JavaScript calls it (libs/base/js/base.js, which build.sh builds of this package and what it reaches):
// for a core in TypeScript that takes a part of the base written once here, as it is (client/core-ts/src/sse.ts).
// What crosses is what both sides hold the same way, so nothing is converted on the way: bytes are a Uint8Array
// (`Bytes`), a text a string (`String`), a list a JavaScript array (`FixedArray`, never `Array`, which is an object
// of MoonBit's own there); a value of the base's own (`@wire.Sse`) is given back as it was got, never looked into.

///|
/// A reader of an event stream (`@wire.Sse`).
pub fn sse_new() -> @wire.Sse {
  @wire.Sse::new()
}

///|
/// The events `chunk` ends, in order, each `[name, data]` or, where it has an id, `[name, data, id]`. The chunk is
/// not kept: its caller may write it again.
pub fn sse_feed(sse : @wire.Sse, chunk : Bytes) -> FixedArray[FixedArray[String]] {
  let events = sse.feed(chunk)
  FixedArray::makei(events.length(), i => {
    let event = events[i]
    match event.id {
      Some(id) => [event.name, event.data, id]
      None => [event.name, event.data]
    }
  })
}
