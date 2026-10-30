// The bookshelf over made-up books (library.mbt), for trying the shelf and
// the reader without a station: src/coredemo has it over the core.

///|
/// Where each book was left: chapter, offset.
let places : Map[String, (Int, Int)] = {}

///|
fn info(b : Book) -> @shelf.BookInfo {
  {
    id: b.id,
    title: b.title,
    author: b.author,
    chapters: b.chapters.length(),
    cover: None,
    place: places.get(b.id),
    read: None,
  }
}

///|
fn find(id : String) -> Book? {
  for b in library {
    if b.id == id {
      return Some(b)
    }
  }
  None
}

///|
let source : @shelf.Source = {
  books: fn() { Some(Ok(library.map(info))) },
  toc: fn(id) { find(id).map(fn(b) { b.chapters }) },
  chapter: fn(id, i) {
    match find(id) {
      Some(b) if i >= 0 && i < b.chapters.length() => Some(Ok(chapter_blocks(b, i)))
      _ => Some(Err("没有这一章"))
    }
  },
  save_place: fn(id, chapter, offset, _at) { places.set(id, (chapter, offset)) },
  now: fn() { @ui.wall_ms() },
}

///|
fn main {
  @ui.run("书架", fn(c) { @shelf.view(c, source) })
}
