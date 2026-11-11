///|
/// A book of four parts, each a character.
fn keep_book() -> Book {
  {
    title: "Book",
    id: 9,
    text: "abcd",
    chunks: ["a", "b", "c", "d"],
    starts: [0, 1, 2, 3],
    parts: [],
    length: 4,
    chapters: [],
    heads: Map([]),
    encoding: "UTF-8",
    truncated: false,
    markdown: false,
  }
}

///|
/// A reading of `key` of a file whose kept places are put in `told` (where, of how long).
fn keep_reading(key : String, told : Array[(Double, Double)]) -> Reading {
  let r = reading_for(key)
  r.file = Some({ ..blob_file(b"abcd", "book.txt", 4.0, save=fn() {  }), keep_place: fn(at, of) { told.push((at, of)) } })
  r.book.set(Some(keep_book()))
  r
}

///|
test "a reader left where it last held still tells nothing again" {
  let told : Array[(Double, Double)] = []
  let r = keep_reading("keep-still", told)
  r.chunk = 2
  reader_keep(r, keep_book())
  assert_eq(told, [(2.0, 4.0)])
  // left where it was kept: nothing more said
  reader_let_go("keep-still")
  assert_eq(told, [(2.0, 4.0)])
}

///|
test "a reader left after it moved tells where once" {
  let told : Array[(Double, Double)] = []
  let r = keep_reading("keep-moved", told)
  r.chunk = 1
  reader_keep(r, keep_book())
  // moved on, and left before it held still there
  r.chunk = 3
  reader_let_go("keep-moved")
  assert_eq(told, [(1.0, 4.0), (3.0, 4.0)])
}
