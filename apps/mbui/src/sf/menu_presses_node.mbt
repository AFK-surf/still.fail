// What is pressed and has a menu (a message's file: its card, its picture, its video), as a node of the window's tree:
// how it answers the hand, the library's (file_menu's and menu_asked's): pressed, pressed; right clicked, its menu
// where the pointer is; held by a finger, its menu there, felt, the press the menu's (lifting it opens nothing). A
// mouse's button held is a press as long as any.

///|
/// `v` pressed (`press`) and asking for its menu (`menu`: where in the window, and whether a finger's hold asked it,
/// as what a finger holds is lifted while its menu is up: lift_node) as the hand does.
pub fn menu_presses_node(v : @view.View, press : () -> Unit, menu : (Double, Double, Bool) -> Unit) -> Unit {
  v.on_menu(fn(m) { menu(m.wx, m.wy, false) }) |> ignore
  presses_held_node(v, press, @ui.long_press_ms, fn(d) {
    if @ui.pointing() is Finger {
      menu_held_node()
      menu(d.wx, d.wy, true)
    }
  })
}
