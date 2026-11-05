// The system's bottom bar leaves the list and its composer the same usable page height.

///|
test "the list and composer both keep above the system navigation bar" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  let end = fn() {
    t.words().iter().find_first(fn(w) { w.0.has_prefix("做完了：列表、跳到最新的按钮") && w.5 > 0.99 }).unwrap().2
  }
  let field = fn() { t.query(TextField, label="发消息").unwrap().rect.1 }
  let (row_was, field_was) = (end(), field())
  t.post(@hostapi.system_channel, "{\"bars\":{\"top\":0,\"bottom\":34,\"left\":0,\"right\":0}}")
  t.draw()
  assert_eq(field_was - field(), 34.0)
  assert_true((row_was - end() - 34.0).abs() < 0.5, msg="the last row moved \{row_was - end()}, its composer moved \{field_was - field()}")
}
