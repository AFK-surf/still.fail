// A letter opened in the chat's letters (the presenters' panel a share of the window tall), touch first: the first
// letter's name, the agent that sent it, pressed in a room of its own as the rule of a press's room has it
// (Tester::room_faults), not cut short by the back button over it; each pressed where it is drawn doing its own.

///|
/// The letters' fixture with a letter open (sffix's chat-letters-open) in `win`, in Chinese: the room faults of the
/// first letter's agent name, and what pressing the back button's middle, then (opened again) the name's, did.
fn letters_room_said(win : (String, Double, Double, Int, String)) -> String {
  let name = "「BFT 备份尺寸分析」的 agent"
  let t = screen_in("chat-letters-open", win, "zh")
  let faults = t.room_faults().filter(fn(f) { f.contains(name) })
  let at = fn(s : String) { t.words().filter(fn(x) { x.0 == s }).map(fn(x) { (x.1 + x.3 / 2.0, x.2 + x.4 / 2.0) }).last() }
  let shown = fn() { at(name) is Some(_) }
  let opened = t.opened().length()
  match at(name) {
    Some((x, y)) => {
      t.tap(x, y)
      t.run_for(@ui.move_most_ms)
    }
    None => ()
  }
  let by_name = (t.opened().length() - opened, shown(), dui.letters_open != "", @sf.presenting())
  // (the back button: 36 round, 4 before the title, on its middle's line: letters_head)
  let t = screen_in("chat-letters-open", win, "zh")
  let title = t.words().filter(fn(x) { x.0 == "BFT 备份尺寸分析" }).last()
  let opened = t.opened().length()
  match title {
    Some(x) => {
      t.tap(x.1 - 4.0 - 18.0, x.2 + x.4 / 2.0)
      t.run_for(@ui.move_most_ms)
    }
    None => ()
  }
  let by_back = (t.opened().length() - opened, t.words().any(fn(x) { x.0 == name }), dui.letters_open != "", @sf.presenting())
  "\{win.0}: faults \{faults} name pressed: opened \{by_name.0} still shown \{by_name.1} letter open \{by_name.2} presenting \{by_name.3}; back pressed: opened \{by_back.0} still shown \{by_back.1} letter open \{by_back.2} presenting \{by_back.3}"
}

///|
test "a letter opened, touch and a tablet: its agent's name pressed in all of its room, not cut by the back button over it" {
  let out = []
  for name in ["touch", "tablet"] {
    match corner_windows.iter().find_first(fn(w) { w.0 == name }) {
      Some(win) => out.push(letters_room_said(win))
      None => out.push("\{name}: none")
    }
  }
  // (its name opening the chat it is from, the panel gone; back to the list, the panel still there)
  assert_eq(out, [
    "touch: faults [] name pressed: opened 0 still shown false letter open true presenting false; back pressed: opened 0 still shown false letter open false presenting true",
    "tablet: faults [] name pressed: opened 0 still shown false letter open true presenting false; back pressed: opened 0 still shown false letter open false presenting true",
  ])
}
