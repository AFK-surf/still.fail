///|
/// The words in the file at `path` (words.txt, where the host put it), or None when it cannot be read.
pub fn Dict::load(path : String) -> Dict? {
  match read_text(path) {
    Some(t) => Some(Dict::parse(t))
    None => None
  }
}

///|
/// The text of the file at `path`, or None when it cannot be read (or is empty): moonrun's, as a test on Wasm runs
/// (mbui/runfs).
pub fn read_text(path : String) -> String? {
  match @runfs.read(path) {
    Some(b) if b.length() > 0 => Some(@utf8.decode_lossy(b[:]))
    _ => None
  }
}

///|
/// `text` kept in the file at `path` (whole or not at all); false when it could not be.
pub fn write_text(path : String, text : String) -> Bool {
  @runfs.write(path, @utf8.encode(text))
}
