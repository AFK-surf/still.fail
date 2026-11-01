// What a box kept to a height scrolls (Ctx::capped) does with the hand, as the old frame's: the contract a node's
// scrolling column keeps. A column 200 tall at most at the top of a window 400 by 300 holding a button "上面的按钮" (it
// takes presses, counted), a field, rows taller than it can show, and a button "最后的按钮" last.

///|
/// The case, and how many times 上面的按钮 was pressed.
fn capped_case() -> (Tester, Ref[Int]) {
  let pressed = Ref(0)
  let t = Tester::new(fn(c) {
    c.capped("body", 200.0, fn() {
      let button = fn(label : String) {
        let id = c.id(label)
        c.focusable(id)
        if c.interact(id).clicked && label == "上面的按钮" {
          pressed.val += 1
        }
        let b = c.box(id~, w=Px(160.0), h=Px(40.0), bg=0xE0E0E0FFL, fn() { c.text(label) |> ignore })
        c.semantics(b, Button, id~, label~, actions=[Activate])
      }
      button("上面的按钮")
      c.editor("body/field", placeholder="字段") |> ignore
      for i in 0..<8 {
        c.box(w=Px(160.0), h=Px(40.0), fn() { c.text("第\{i}行") |> ignore }) |> ignore
      }
      button("最后的按钮")
    })
    |> ignore
  }, w=400.0, h=300.0, platform=0)
  t.draw()
  (t, pressed)
}

///|
/// How far it is scrolled.
fn capped_at() -> Double {
  match sideways.get(g().capped_id("body")) {
    Some(s) => s.x
    None => -1.0
  }
}

///|
/// The middle of what is read out as `role` labelled `label`, where it is in the column's sight (0 to 200 down), if it
/// is.
fn capped_point(t : Tester, role : Role, label : String) -> (Double, Double)? {
  match t.query(role, label~) {
    Some(s) => {
      let (x, y, w, h) = s.rect
      let (px, py) = (x + w / 2.0, y + h / 2.0)
      if py >= 0.0 && py < 200.0 { Some((px, py)) } else { None }
    }
    None => None
  }
}

///|
test "a box kept to a height: the wheel over a button in it that takes presses, in sight: what it holds scrolls; the button not pressed" {
  let (t, pressed) = capped_case()
  let at = capped_point(t, Button, "上面的按钮")
  match at {
    Some((x, y)) => t.wheel(x, y, 40.0)
    None => ()
  }
  assert_eq((at is Some(_), capped_at() > 0.0, pressed.val), (true, true, 0), msg="\{capped_at()}")
}

///|
test "a box kept to a height: the wheel over its field, in sight: what it holds scrolls" {
  let (t, _) = capped_case()
  let at = capped_point(t, TextField, "")
  match at {
    Some((x, y)) => t.wheel(x, y, 40.0)
    None => ()
  }
  assert_eq((at is Some(_), capped_at() > 0.0), (true, true), msg="\{capped_at()}")
}

///|
test "a box kept to a height: the wheel over its words, in sight: what it holds scrolls" {
  let (t, _) = capped_case()
  let at = match t.find("第1行") {
    Some((x, y)) if y >= 0.0 && y < 200.0 => Some((x + 4.0, y + 4.0))
    _ => None
  }
  match at {
    Some((x, y)) => t.wheel(x, y, 40.0)
    None => ()
  }
  assert_eq((at is Some(_), capped_at() > 0.0), (true, true), msg="\{capped_at()}")
}

///|
test "a box kept to a height: wheeled past its end, kept at its end" {
  let (t, _) = capped_case()
  for _ in 0..<20 {
    t.wheel(80.0, 100.0, 120.0)
  }
  let max = capped_at()
  t.wheel(80.0, 100.0, 120.0)
  assert_true(max > 0.0 && capped_at() == max, msg="\{max} \{capped_at()}")
}

///|
test "a box kept to a height: its last button out of sight, Tab to it: the focus on it, scrolled to show it" {
  let (t, _) = capped_case()
  let out_first = capped_point(t, Button, "最后的按钮") is None
  for _ in 0..<12 {
    if t.focused().map(fn(s) { s.label }) == Some("最后的按钮") {
      break
    }
    t.tab()
  }
  let focused = t.focused().map(fn(s) { s.label })
  let shown = match t.query(Button, label="最后的按钮") {
    Some(b) => b.rect.1 >= 0.0 && b.rect.1 + b.rect.3 <= 200.0 + 0.5
    None => false
  }
  assert_eq((out_first, focused, shown, capped_at() > 0.0), (true, Some("最后的按钮"), true, true), msg="\{capped_at()}")
}
