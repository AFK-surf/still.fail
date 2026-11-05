///|
test "copying a decoded message picture completes at the menu choice without drawing another frame" {
  copy_message_picture(true)
}

///|
test "copying a message picture still decoding completes at the host reply without drawing another frame" {
  copy_message_picture(false)
}

///|
fn copy_message_picture(decoded : Bool) -> Unit raise {
  let t = wide_tester([], mode="chat")
  let mut at : (Double, Double)? = None
  for _ in 0..<12 {
    match t.drawn_images().iter().find_first(fn(i) {
      i[0] > 400.0 && i[2] > 100.0 && i[1] > 80.0 && i[1] + i[3] / 2.0 < 700.0
    }) {
      Some(i) => {
        at = Some((i[0] + i[2] / 2.0, i[1] + dmin(i[3], 200.0) / 2.0))
        break
      }
      None => t.wheel(900.0, 400.0, -200.0)
    }
  }
  let (x, y) = at.unwrap()
  t.right_click(x, y)
  t.run_for(@kit.presence_in_ms)
  let src = @sfpages.offered_image()
  assert_true(src != "")
  t.add_pixels(src, 2, 2, FixedArray::make(16, b'\xff'))
  if decoded {
    @ui.current().image_pixels(src, @sfpages.image_copy_px) |> ignore
    t.finish_all()
  }
  let (x, y) = t.find("复制图片").unwrap()
  t.record_host()
  t.touch_at(0, x, y, t.time())
  t.touch_at(2, x, y, t.time())
  if !decoded {
    assert_eq(t.clipboard_png(), None)
    t.finish_all()
  }
  assert_true(t.clipboard_png().map(@pixels.is_png).unwrap_or(false),
    msg="the completed menu action cannot wait for a page to be drawn")
  assert_eq(t.host_frames().length(), 0)
}
