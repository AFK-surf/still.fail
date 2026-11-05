///|
/// Zoomed in to 1.5 in a Mac window (its corner 16, so 10.67 in the page's points), the chat bar's last key, 6 under
/// its top and in from its side, follows the window's corner: 4.67 round, 7 as drawn, a corner the theme lets what lies
/// in a corner have at that zoom, linked so as main's icon_button(linked=bar_keys_link()) is, the corner rule taking it
/// as following it, not as a box of its own 4.67 round, squarer than the theme's least.
test "wide: zoomed to 1.5 in a Mac window, the chat bar's last key follows the window's corner" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat", w=1280.0, h=800.0, window_corner=16.0, window_inset=true)
  for _ in 0..<3 {
    t.key(@ui.key_of_char('='), mods=@ui.mod_cmd)
    t.run_for(@ui.move_most_ms * 2.0)
  }
  assert_eq(@ui.window_zoom(), 1.5)
  assert_eq(t.corner_faults(), [])
}
