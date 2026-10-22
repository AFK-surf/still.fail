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

///|
test "上次检查's time as Android's short date and time (a Tester's zone UTC's)" {
  assert_eq(short_date_time(1790000000000.0), "2026/9/21 14:13")
  assert_eq(short_date_time(951782400000.0), "2000/2/29 00:00")
  assert_eq(short_date_time(4102444799000.0), "2099/12/31 23:59")
  assert_eq(short_date_time(0.0), "1970/1/1 00:00")
}
