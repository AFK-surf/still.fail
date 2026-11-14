// What the reader of an event stream (sse.mbt) does to many bytes at once, for js: the engine's own (a typed
// array's `set`, `copyWithin`, `indexOf`), as the core's reader in TypeScript had them. JavaScript written out,
// which no compiler reads: the package's tests run it (`moon test --target js src/wire`).

///|
/// `chunk` put in `to` from `at` on, without its CRs: where it then ends.
extern "js" fn put(to : FixedArray[Byte], at : Int, chunk : Bytes) -> Int =
  #|(to, at, chunk) => {
  #|  if (chunk.indexOf(13) < 0) {
  #|    to.set(chunk, at);
  #|    return at + chunk.length;
  #|  }
  #|  for (let i = 0; i < chunk.length; i++) if (chunk[i] !== 13) to[at++] = chunk[i];
  #|  return at;
  #|}

///|
/// `from`'s bytes `start` to `end` at the front of `to`, which may be `from`.
extern "js" fn moved(to : FixedArray[Byte], from : FixedArray[Byte], start : Int, end : Int) -> Unit =
  #|(to, from, start, end) => {
  #|  if (to === from) to.copyWithin(0, start, end);
  #|  else to.set(from.subarray(start, end));
  #|}

///|
/// Where the first newline of `held` is from `from` on and before `end`, -1 where none is.
extern "js" fn newline(held : FixedArray[Byte], from : Int, end : Int) -> Int =
  #|(held, from, end) => held.subarray(0, end).indexOf(10, from)
