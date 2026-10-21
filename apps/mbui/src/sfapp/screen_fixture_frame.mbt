// The fixture screen's frame (screen_fixture.mbt): ScreenViewerTest's picture of a browser's tab (a page with a bar
// and lines, 1280 × 720), the JPEG its test sends, kept here as hex.

///|
/// The frame's JPEG, decoded once.
fn screen_fix_jpeg() -> Bytes {
  let hex = screen_fix_jpeg_hex
  let n = hex.length() / 2
  let nibble = fn(ch : Int) {
    if ch >= 97 {
      ch - 87
    } else {
      ch - 48
    }
  }
  Bytes::makei(n, fn(i) {
    (nibble(hex.code_unit_at(2 * i).to_int()) * 16 + nibble(hex.code_unit_at(2 * i + 1).to_int())).to_byte()
  })
}

///|
let screen_fix_jpeg_hex : String = ""
