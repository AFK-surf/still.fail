// The shelf and the reader, over wherever books come from: a Source answers
// what the views ask each frame (None while it is still being read).

///|
pub(all) struct BookInfo {
  id : String
  title : String
  author : String
  chapters : Int
  /// an image source for its cover (Ctx::image), if it has one
  cover : String?
  /// where it was left: chapter and offset
  place : (Int, Int)?
  /// how much is read, 0 to 1
  read : Double?
}

///|
pub(all) struct Source {
  /// the books, or why they can't be read
  books : () -> Result[Array[BookInfo], String]?
  /// chapter titles
  toc : (String) -> Array[String]?
  /// a chapter's text
  chapter : (String, Int) -> Result[Array[@ui.Block], String]?
  /// the reader moved: book, chapter, offset
  save_place : (String, Int, Int) -> Unit
}
