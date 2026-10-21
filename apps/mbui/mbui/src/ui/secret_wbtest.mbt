///|
test "a secret's field: its words drawn as dots, the app reading them whole, never copied out" {
  let mut got = ""
  let t = Tester::new(fn(c) {
    c.column(w=Fill(1.0), h=Fill(1.0), fn() {
      got = c.editor("key", placeholder="xoxb-…", secret=true).text
      c.spacer()
    })
    |> ignore
  })
  t.tap_text("xoxb-…")
  t.type_text("sk-made-up")
  t.frame()
  assert_eq(got, "sk-made-up")
  let dump = t.dump()
  // (drawn as ten dots, the caret after them)
  assert_true(dump.contains("caret=10"))
  assert_false(dump.contains("sk-made-up"))
  match fake.val {
    Some(f) => f.clipboard = "before"
    None => ()
  }
  t.key(key_select_all)
  t.key(key_copy)
  t.key(key_cut)
  t.frame()
  match fake.val {
    Some(f) => assert_eq(f.clipboard, "before")
    None => ()
  }
  assert_eq(got, "sk-made-up")
}
