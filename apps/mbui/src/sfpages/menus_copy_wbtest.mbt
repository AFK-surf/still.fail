// A picture copy belongs to the menu choice, even after the menu is gone. A later choice owns the clipboard instead.

///|
fn pending_copy(t : @ui.Tester, src : String) -> Int {
  let pending = t.pending().filter(fn(p) { p.0 == 1 && t.image_src(p.1) == src })
  assert_eq(pending.length(), 1, msg="one decode requested for \{src}")
  pending[0].1
}

///|
test "a later picture copy wins even when the first decode finishes last" {
  menus_reset()
  let t = @ui.Tester::new(fn(_) {  }, finish=false)
  let red = FixedArray::make(4, b'\xff')
  red[1] = b'\x00'
  red[2] = b'\x00'
  let blue = FixedArray::make(4, b'\xff')
  blue[0] = b'\x00'
  blue[1] = b'\x00'
  t.add_pixels("copy-first", 1, 1, red)
  t.add_pixels("copy-second", 1, 1, blue)
  t.draw()
  copy_menu_image("copy-first")
  let first = pending_copy(t, "copy-first")
  copy_menu_image("copy-second")
  let second = pending_copy(t, "copy-second")
  t.finish(1, second)
  assert_eq(t.clipboard_png(), Some(@pixels.png(1, 1, blue)))
  t.finish(1, first)
  assert_eq(t.clipboard_png(), Some(@pixels.png(1, 1, blue)), msg="the older decode must not overwrite the later choice")
}

///|
test "a failed picture decode does not copy and a later choice can succeed" {
  menus_reset()
  let t = @ui.Tester::new(fn(_) {  }, finish=false)
  let rgba = FixedArray::make(4, b'\xff')
  t.add_pixels("copy-fails", 1, 1, rgba)
  t.add_pixels("copy-retry", 1, 1, rgba)
  t.draw()
  copy_menu_image("copy-fails")
  t.finish(1, pending_copy(t, "copy-fails"), ok=false)
  assert_true(t.clipboard_png() is None)
  copy_menu_image("copy-retry")
  t.finish(1, pending_copy(t, "copy-retry"))
  assert_eq(t.clipboard_png(), Some(@pixels.png(1, 1, rgba)))
}
