// A field in a list's row with the keyboard coming up: kept in view, the list at its end or not.

///|
/// How long a step of the keyboard takes here: a display's frame.
let keyboard_step_ms : Double = 16.0

///|
test "a focused field in a list's row stays in view as the keyboard comes up, what covers the view's ends cleared" {
  let t = Tester::new(
    fn(c) {
      c.box(w=Fill(1.0), h=Fill(1.0), fn() {
        c.list(
          "rows",
          20,
          60.0,
          fn(i) {
            c.box(w=Fill(1.0), h=Px(60.0), fn() {
              if i == 16 {
                c.editor("field", placeholder="写在这里", font_size=14.0, line=20.0, max_lines=1) |> ignore
              } else {
                c.text("第 \{i} 行") |> ignore
              }
            })
            |> ignore
          },
          stick_end=true,
          clear_top=50.0,
          clear_foot=80.0,
        )
        |> ignore
      })
      |> ignore
    },
    w=360.0,
    h=600.0,
    platform=2,
  )
  t.draw()
  t.tap_text("写在这里")
  t.draw()
  // (a step at a time, as a host says it, the app laid out above it)
  for i in 1..=10 {
    t.set_ime_inset(i.to_double() * 40.0)
    t.resize_next(360.0, 600.0 - i.to_double() * 40.0)
    t.run_for(keyboard_step_ms)
  }
  guard t.focused() is Some({ rect: (_, y, _, h), .. }) else { fail("the field let go of the focus") }
  assert_true(y >= 50.0 && y + h <= 200.0 - 80.0, msg="field at \{y}..\{y + h} in a view of 200")
  // the keyboard down: at its end again, as it was
  for i in 1..=10 {
    t.set_ime_inset(400.0 - i.to_double() * 40.0)
    t.resize_next(360.0, 200.0 + i.to_double() * 40.0)
    t.run_for(keyboard_step_ms)
  }
  assert_true(t.find("第 19 行") is Some(_))
}
