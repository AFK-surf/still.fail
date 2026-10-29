///|
#borrow(path)
extern "C" fn read_file(path : Bytes) -> Bytes = "stillfail_pinyin_read_file"

///|
#borrow(path, data)
extern "C" fn write_file(path : Bytes, data : Bytes) -> Int = "stillfail_pinyin_write_file"

///|
/// The words in the file at `path` (words.txt, where the host put it), or None when it cannot be read.
pub fn Dict::load(path : String) -> Dict? {
  match read_text(path) {
    Some(t) => Some(Dict::parse(t))
    None => None
  }
}

///|
/// The text of the file at `path`, or None when it cannot be read (or is empty).
pub fn read_text(path : String) -> String? {
  let b = read_file(@utf8.encode(path + "\u{0}"))
  if b.length() == 0 {
    return None
  }
  Some(@utf8.decode_lossy(b))
}

///|
/// `text` kept in the file at `path` (whole or not at all); false when it could not be.
pub fn write_text(path : String, text : String) -> Bool {
  write_file(@utf8.encode(path + "\u{0}"), @utf8.encode(text)) == 1
}
