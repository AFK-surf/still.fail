// A picture picked as a station's mark too large to put up as it is (station_mark.mbt picture_mark_small).

///|
test "a picture too large as it is: its middle square at 96, a JPEG small enough to go with the workspace" {
  // 400 by 300, the left 50 red, the rest grey: its middle 300 square all grey
  let w = 400
  let h = 300
  let px = FixedArray::make(w * h * 4, b'\x80')
  for y in 0..<h {
    for x in 0..<w {
      px[(y * w + x) * 4 + 3] = b'\xFF'
      if x < 50 {
        px[(y * w + x) * 4] = b'\xFF'
        px[(y * w + x) * 4 + 1] = b'\x00'
        px[(y * w + x) * 4 + 2] = b'\x00'
      }
    }
  }
  match picture_mark_small(w, h, px) {
    Some(url) => {
      assert_true(url.has_prefix("data:image/jpeg;base64,/9j/"))
      assert_true(url.length() <= 46000)
    }
    None => fail("not made")
  }
  // what is put up as it is: a small PNG, as it is
  assert_eq(picture_mark(b"\x89PNG\r\n\x1a\nxyz"), Some("data:image/png;base64,iVBORw0KGgp4eXo="))
  // and a GIF, which may move
  assert_eq(picture_mark(b"GIF89axyz"), Some("data:image/gif;base64,R0lGODlheHl6"))
}
