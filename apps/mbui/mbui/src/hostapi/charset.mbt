// Text in a legacy encoding decoded by the system's own tables (a reader's novel in GB18030, as still.fail's Android
// app reads one: TextModel.kt decodeText, Charset.forName): Android's java.nio Charset, Apple's CFString encodings,
// Windows' code pages, the browser's TextDecoder. A character the encoding has no mapping for becomes U+FFFD; None
// where the host does not know the encoding.

///|
/// `data` decoded as `charset` (a name as IANA has it: "GB18030", "Big5", "Shift_JIS", "windows-1252"…); None where the
/// host does not know it.
pub fn decode_charset(data : Bytes, charset : String) -> String? {
  if cs_known(charset) == 0 {
    None
  } else {
    Some(cs_decode(data, charset))
  }
}

///|
/// A file's bytes as text, and the encoding that made it (still.fail's Android app's TextModel.kt decodeText): a byte
/// order mark settles it; else strict UTF-8 (a character cut in half at the end of a `truncated` front, or of a
/// half-copied file, dropped); else GB18030, as the system's tables decode it (decode_charset); UTF-8 with replacement
/// characters where the host knows no GB18030. The encoding as "UTF-8", "UTF-8 BOM", "UTF-16LE", "UTF-16BE",
/// "GB18030" or "UTF-8 (lossy)".
pub fn decode_text(b : Bytes, truncated? : Bool = false) -> (String, String) {
  let n = b.length()
  if n == 0 {
    return ("", "UTF-8")
  }
  let at = fn(i : Int) -> Int { b[i].to_int() }
  if n >= 3 && at(0) == 0xEF && at(1) == 0xBB && at(2) == 0xBF {
    let v = b.clamped_view(start=3, end=@codec.utf8_end(b, 3, n, truncated))
    return (@utf8.decode(v) catch { _ => @utf8.decode_lossy(v) }, "UTF-8 BOM")
  }
  if n >= 2 && at(0) == 0xFF && at(1) == 0xFE {
    return (@codec.utf16_text(b, 2, true), "UTF-16LE")
  }
  if n >= 2 && at(0) == 0xFE && at(1) == 0xFF {
    return (@codec.utf16_text(b, 2, false), "UTF-16BE")
  }
  let whole = b.clamped_view(start=0, end=@codec.utf8_end(b, 0, n, truncated))
  let strict : String? = Some(@utf8.decode(whole)) catch { _ => None }
  if strict is Some(s) {
    return (s, "UTF-8")
  }
  if !truncated {
    let cut = b.clamped_view(start=0, end=@codec.utf8_end(b, 0, n, true))
    let cut_strict : String? = Some(@utf8.decode(cut)) catch { _ => None }
    if cut_strict is Some(s) {
      return (s, "UTF-8")
    }
  }
  // not UTF-8: GB18030 (a superset of GBK, the usual answer for older Chinese text), as the system's tables decode it;
  // a character the end cuts in half dropped
  match decode_charset(b, "GB18030") {
    Some(s) => {
      let mut text = s
      if truncated {
        while text.has_suffix("\u{FFFD}") {
          text = text.view(end_offset=text.length() - 1).to_owned()
        }
      }
      (text, "GB18030")
    }
    None => (@utf8.decode_lossy(whole), "UTF-8 (lossy)")
  }
}
