// What the reader of an event stream (sse.mbt) does to many bytes at once, and to many lines, for js: the engine's
// own (a typed array's `set`, `copyWithin`, `indexOf`; an array's `push` and `join`). JavaScript written out, which
// no compiler reads: the package's tests run it (`moon test --target js src/wire`).

///|
/// `chunk` put in `to` from `at` on, without its CRs: where it then ends. A newline is put after it where there is
/// room for one (it is of nothing kept: the next chunk is put over it): what stops `newline` at the end of what is
/// kept.
extern "js" fn put(to : FixedArray[Byte], at : Int, chunk : Bytes) -> Int =
  #|(to, at, chunk) => {
  #|  if (chunk.indexOf(13) < 0) {
  #|    to.set(chunk, at);
  #|    at += chunk.length;
  #|  } else {
  #|    for (let i = 0; i < chunk.length; i++) if (chunk[i] !== 13) to[at++] = chunk[i];
  #|  }
  #|  if (at < to.length) to[at] = 10;
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
/// Where the first newline of `held` is from `from` on and before `end`, -1 where none is. Asked of all of `held`,
/// no view of it made up to `end` (the reader in TypeScript makes one: under Hermes a `subarray` costs by the size of
/// what it is a view of, and one for each line of a long block was that size times its lines): what is past `end`
/// is not looked through, since `put`, which wrote last, left a newline at `end` (or `held` ends there).
extern "js" fn newline(held : FixedArray[Byte], from : Int, end : Int) -> Int =
  #|(held, from, end) => {
  #|  const at = held.indexOf(10, from);
  #|  return at < end ? at : -1;
  #|}

///|
/// An event's `data:` lines as they are read: the engine's own array, and its join, which makes their text once.
#external
priv type Lines

///|
extern "js" fn lines() -> Lines =
  #|() => []

///|
extern "js" fn line_kept(lines : Lines, line : String) -> Unit =
  #|(lines, line) => void lines.push(line)

///|
/// How many are kept.
extern "js" fn lines_kept(lines : Lines) -> Int =
  #|(lines) => lines.length

///|
/// Them as one text, a newline between two.
extern "js" fn lines_joined(lines : Lines) -> String =
  #|(lines) => lines.join("\n")

