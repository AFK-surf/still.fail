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
