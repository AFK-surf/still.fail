// ZZ scratch: lines typed at moments near the end of the let-go's way; the field's steps per frame

///|
fn zz_typed_at(lead : Double, period : Double) -> Unit {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.set_frame_period(period)
  t.tap_text("发消息")
  t.type_text("第一条")
  t.enter()
  t.type_text("两行")
  tap_send(t)
  t.frame()
  let (at, ms) = @sfbase.flight_lets_go("ws1/st1:s-c1").unwrap()
  let end = at + ms
  // the frame before the one typed in: `lead` ms before the way's end (negative: after it)
  t.run_for(end - lead - period - t.time())
  let ys : Array[(Double, Double)] = [(t.time(), zz_field_top(t))]
  t.each_frame(Some(fn() { ys.push((t.time(), zz_field_top(t))) }))
  let typed_before = t.time()
  t.type_text("接着写")
  t.enter()
  let typed = t.time()
  t.run_for(900.0)
  t.each_frame(None)
  let rest = ys[ys.length() - 1].1
  let mut out = "ZZSWEEP period=\{period} lead=\{lead} end=\{end} typed=\{typed} (frame before \{typed_before}) rest=\{rest} steps:"
  let mut mx = 0.0
  for i = 1; i < ys.length(); i = i + 1 {
    let d = ys[i].1 - ys[i - 1].1
    if d.abs() > mx.abs() { mx = d }
    if i < 40 { out = out + " \{(ys[i].0 - typed).to_string()}:\{d}" }
  }
  println(out + " | max \{mx} D=\{ys[0].1 - rest}")
}

///|
test "zz sweep" {
  for period in [1000.0 / 60.0] {
    for lead in [150.0] {
      zz_typed_at(lead, period)
    }
  }
}

///|
fn zz_field_top(t : @ui.Tester) -> Double {
  match t.words_said().search_by(fn(w) { w.0.has_prefix("发消息") }) {
    Some(i) => t.words_said()[i].2
    None => -1.0
  }
}
