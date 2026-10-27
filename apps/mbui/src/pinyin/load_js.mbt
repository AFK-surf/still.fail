///|
/// The words in the file at `path`: none in a browser (the keyboard is native's).
pub fn Dict::load(_path : String) -> Dict? {
  None
}

///|
/// No file in a browser.
pub fn read_text(_path : String) -> String? {
  None
}

///|
/// No file in a browser.
pub fn write_text(_path : String, _text : String) -> Bool {
  false
}
