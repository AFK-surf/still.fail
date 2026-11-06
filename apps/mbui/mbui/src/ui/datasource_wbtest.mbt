// What a run keeps of what it shows, is typed and is told, by where its data comes from (datasource.mbt): of a real
// account's, nothing (its tape empty, no TEXTREC, no line on the log with the words in it), the run itself the same;
// of made-up data, all of it, the run seen again from the tape alone. One made-up sentinel both ways.

///|
let sentinel : String = "QZXSENTINEL"

///|
/// A run that is told the sentinel (a core's message) and typed it, kept on a tape, MBUI_TEXT_RECORD on: its tape, the
/// log's lines, what it was told.
fn sentinel_run(source : DataSource) -> (String, Array[String], Array[String], Bool) {
  let shown : Array[String] = []
  on_message("test.core", fn(j, _) { shown.push(j) })
  let t = Tester::new(shown_view(shown), w=300.0, h=100.0, env=[("MBUI_TEXT_RECORD", "1")])
  set_data_source(source)
  t.start_tape()
  t.run_for(lot_gap_ms)
  t.post("test.core", "{\"said\":\"\{sentinel}\"}")
  t.draw()
  t.type_text(sentinel)
  t.run_for(lot_gap_ms)
  (t.tape(), t.fake.logs.copy(), shown, text_recording())
}

///|
test "a real account's run keeps nothing of what it is told or typed: no tape, no text, no line with its words" {
  let (tape, logs, shown, text) = sentinel_run(RealAccount)
  assert_eq(tape, "")
  assert_false(text)
  assert_eq(logs.filter(l => l.contains(sentinel)), [])
  assert_eq(logs.filter(l => l.has_prefix("TEXTREC ") || l.has_prefix("INPUT ") || l.has_prefix("MSG ")), [])
  // (the run itself the same: what it was told shown)
  assert_eq(shown, ["{\"said\":\"\{sentinel}\"}"])
}

///|
test "a made-up run keeps what it is told and typed, and is seen again from its tape alone" {
  let (tape, _, shown1, text) = sentinel_run(MadeUp)
  assert_true(text)
  let lines = tape.split("\n").map(l => l.to_owned()).to_array()
  assert_eq(lines.filter(l => l.has_prefix("MSG ") && l.contains(sentinel)).length(), 1)
  assert_eq(lines.filter(l => l.has_prefix("INPUT ") && l.contains(sentinel)).length(), 1)
  let shown2 : Array[String] = []
  on_message("test.core", fn(j, _) { shown2.push(j) })
  let t2 = Tester::new(shown_view(shown2), w=300.0, h=100.0)
  let frames = t2.replay_frames(tape)
  assert_true(frames.length() > 0)
  for f in frames {
    assert_eq(f.2, f.1)
  }
  assert_eq(shown2, shown1)
}
