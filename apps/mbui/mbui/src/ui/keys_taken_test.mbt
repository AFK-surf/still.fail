// What a part over a field said it takes of the field's keys (Ctx::on_key): never a key catcher's, whose keys are all
// its own (catcher_key) as before anything else.

///|
test "a key catcher with the focus: a part that says it takes the catcher's keys takes none, the catcher has them" {
  let got : Array[@ui.KeyIn] = []
  let taken = Ref::new(0)
  let t = @ui.Tester::new(fn(c) {
    c.catch_keys("keys", true)
    let k = c.key_catcher("keys")
    if k.keys.length() > 0 {
      let keys = k.keys
      c.tell("caught", fn() { got.append(keys) })
    }
    // (as a menu over a field would, of the one with the focus)
    c.on_key(c.focused_id(), fn(_, _) {
      taken.val = taken.val + 1
      true
    })
    c.text(if k.focused { "typing" } else { "idle" }, wrap=false) |> ignore
  })
  t.draw()
  t.draw()
  assert_true(t.find("typing") is Some(_))
  t.key_told(@ui.key_code_enter, 0, t.time())
  t.key_told(@ui.key_tab, 0, t.time())
  t.draw()
  let downs : Array[String] = []
  for k in got {
    match k {
      Key(down=true, code~, ..) => downs.push(code)
      _ => ()
    }
  }
  assert_eq((taken.val, downs, t.find("typing") is Some(_)), (0, ["Enter", "Tab"], true))
}
