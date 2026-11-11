// The language and the product the core said, forgotten as the next Tester starts: in a program with no app (sfapp's
// reset says them again; this package has none), the second test below once began in the first one's English.
// (The two run in this order in one program: the second is the one that fails when the first's are kept.)

///|
fn lang_reset_tester() -> @ui.Tester {
  @ui.Tester::new(fn(c) {
    @sf.begin(c) |> ignore
    @sf.link_row(c, "lang", @sf.t("web-main.history.reminder", args=[("name", @sf.product())])) |> ignore
  }, w=360.0, platform=2)
}

///|
test "lang reset: a test that sets English and another product" {
  let t = lang_reset_tester()
  @sf.set_language(Some("en"))
  @sf.set_product("monoid")
  t.draw()
  assert_eq(@sf.language(), "en")
  assert_eq(@sf.product(), "monoid")
}

///|
test "lang reset: the next test's Tester starts in the device's language and the build's product" {
  let t = lang_reset_tester()
  t.draw()
  assert_eq(@sf.language(), "zh")
  assert_eq(@sf.product(), "still.fail")
}
