///|
/// A page of a button by its words, an icon's button by its label, words, and a box that only holds the page: what a
/// screen reader is told of it, and a double tap on the button.
fn a11y_view(sent : Ref[Int], send_id : Ref[Int]) -> (@ui.Ctx) -> Unit {
  fn(c) {
    c.column(fn() {
      let send = c.id("send")
      send_id.val = send
      c.box(id=send, w=Px(80.0), h=Px(40.0), fn() { c.text("Send", wrap=false) |> ignore }) |> ignore
      if c.clicked(send) {
        sent.val += 1
      }
      let back = c.id("back")
      c.box(id=back, w=Px(40.0), h=Px(40.0), label="Back", fn() {  }) |> ignore
      c.text("Hello there", wrap=false) |> ignore
    })
    |> ignore
  }
}

///|
/// The fields of the line whose role and label are these, if there is one.
fn a11y_line(said : String, role : String, label : String) -> Array[String]? {
  for line in said.split("\n") {
    let f = line.split("\u{1F}").map(fn(v) { v.to_string() }).to_array()
    if f.length() == 16 && f[3] == role && f[9] == label {
      return Some(f)
    }
  }
  None
}

///|
test "a screen reader on: told the widgets, a pressed box a button by its words or label; nothing while off" {
  let sent : Ref[Int] = Ref::new(0)
  let send_id : Ref[Int] = Ref::new(0)
  let t = @ui.Tester::new(a11y_view(sent, send_id))
  assert_eq(t.a11y_said(), "")
  t.set_a11y(true)
  t.draw()
  let said = t.a11y_said()
  let send = a11y_line(said, "Button", "Send").unwrap()
  // its widget's id, activated; laid out where it is, 80 by 40
  assert_eq(send[2], send_id.val.to_string())
  assert_eq(send[15], "a")
  assert_eq(send[7], "80")
  assert_eq(send[8], "40")
  assert_true(a11y_line(said, "Button", "Back") is Some(_))
  assert_true(a11y_line(said, "Text", "Hello there") is Some(_))
  // the button's words are its name, not words of their own
  assert_true(a11y_line(said, "Text", "Send") is None)
  // the same page again: told the same
  t.draw()
  assert_eq(t.a11y_said(), said)
}

///|
test "a screen reader's double tap: the button activated the next frame, as a tap" {
  let sent : Ref[Int] = Ref::new(0)
  let send_id : Ref[Int] = Ref::new(0)
  let t = @ui.Tester::new(a11y_view(sent, send_id))
  t.set_a11y(true)
  t.draw()
  t.post(@hostapi.a11y_channel, "{\"id\":\{send_id.val},\"action\":\"activate\"}")
  t.draw()
  assert_eq(sent.val, 1)
}

///|
test "a node's number is kept from frame to frame, and words of the same parent told apart" {
  let sent : Ref[Int] = Ref::new(0)
  let send_id : Ref[Int] = Ref::new(0)
  let t = @ui.Tester::new(a11y_view(sent, send_id))
  t.set_a11y(true)
  t.draw()
  let first = a11y_line(t.a11y_said(), "Text", "Hello there").unwrap()[0]
  t.set_dark(true)
  t.draw()
  assert_eq(a11y_line(t.a11y_said(), "Text", "Hello there").unwrap()[0], first)
}

///|
test "a screen reader writing in a field: told it takes words, they take the place of what it held, as typed" {
  let field = @ui.Field::new(text="draft")
  let t = @ui.Tester::new(fn(c) {
    c.column(fn() { c.editor("note", placeholder="Note", field~) |> ignore }) |> ignore
  })
  t.set_a11y(true)
  t.draw()
  let line = a11y_line(t.a11y_said(), "TextField", "Note").unwrap()
  assert_eq(line[10], "draft")
  assert_eq(line[15], "t")
  t.post(
    @hostapi.a11y_channel,
    "{\"id\":\{line[2]},\"action\":\"set_text\",\"text\":\"from the reader\"}",
  )
  t.draw()
  assert_eq(field.text(), "from the reader")
  assert_eq(a11y_line(t.a11y_said(), "TextField", "Note").unwrap()[10], "from the reader")
}
