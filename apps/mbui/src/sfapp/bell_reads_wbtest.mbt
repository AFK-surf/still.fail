// What the rail's bell reads to say whether it has its dot (sfdesk's bell_lit), over the made-up core a client's
// messages go to (sffixture's round_trip_again): the same topics whatever any of them holds.

///|
test "大屏 the rail's bell: 待处理 come to list a chat and then none, the services left up long it reads held all along, never let go of and asked again" {
  new_run()
  let heard : Array[String] = []
  let base = fixture("home")
  let plain = (base.topic_read)("workspaceMarks", @sfbase.marks_asked()).value.unwrap()
  let marks = @signals.signal(plain)
  let src : Source = {
    ..round_trip_again(
      {
        ..base,
        topic_read: fn(name, params) {
          if name == "workspaceMarks" {
            return { value: Some(marks.get()), error: None, version: 1 }
          }
          (base.topic_read)(name, params)
        },
      },
      0.0,
      heard=fn(h) { heard.push(h) },
    ),
    reads_ahead: fn() { true },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_true(wire_subs(heard).contains("sub longJobs"), msg="the bell reads no longJobs: \{Repr(wire_subs(heard))}")
  let from = wire_subs(heard).length()
  // (a chat come to 待处理, as a message the person has not read lists it; then read, none)
  marks.set(@sffixture.fix_attention_marks())
  t.run_for(@ui.move_most_ms)
  marks.set(plain)
  t.run_for(@ui.move_most_ms)
  let subs = wire_subs(heard)
  let since = subs[from:].to_owned().filter(fn(s) { s.has_suffix(" longJobs") })
  assert_eq(since, [])
}
