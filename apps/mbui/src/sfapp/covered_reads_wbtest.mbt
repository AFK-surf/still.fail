// A page of the stack made as nodes reads the core while it shows (sfbase's Source::shown_by, shown_made): covered by
// another, what it read is let go and nothing of it is worked out again; shown again, read again from that moment, as it
// was until the core answers.

///|
/// Home on a phone over `client` (made after the run begun anew: new_run) for the long jobs of ws1 (what Home's
/// node reads of the core), the rest the fixture's.
fn covered_home(client : @core.Client) -> @ui.Tester {
  let base = fixture_app("home")
  let src : Source = {
    ..base,
    topic_read: fn(name, p) {
      if name != "longJobs" { return (base.topic_read)(name, p) }
      let sub = client.follow_topic(name, params=p)
      { value: sub.value, error: sub.error, version: sub.version }
    },
    waits: fn(name, p) {
      if name == "longJobs" { client.follow_topic(name, params=p).waiting } else { (base.waits)(name, p) }
    },
    leave: fn(name, p, reason) {
      if reason is @sfbase.TopicLeave::Owned(stop) { stop(); return }
      if name == "longJobs" { client.leave_topic(name, params=p) } else { (base.leave)(name, p, @sfbase.TopicLeave::Legacy) }
    },
    release: fn(name, p) {
      if name == "longJobs" { client.release_topic(name, params=p) } else { (base.release)(name, p) }
    },
  }
  @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
}

///|
let covered_jobs_params : Map[String, Json] = { "scope": Json::string("ws1") }

///|
test "Home covered by a chat lets go of what it read, and reads it again as it shows" {
  new_run()
  let client = @core.Client::new(fn(_) {  })
  let t = covered_home(client)
  t.frame()
  t.run_for(first_page_ms)
  guard client.peek_topic("longJobs", params=covered_jobs_params) is Some(first) else { fail("home did not read its jobs") }
  client.receive_json({ "id": Json::number(first.id.to_double()), "value": { "groups": [] } })
  t.frame()
  let covered_at = t.time()
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  t.frame()
  // (still read while the chat slides over it; let go as it covers it, at the end of its slide)
  t.frame_at(covered_at + @ui.move_ms(390.0) - 1.0)
  let held_sliding = client.peek_topic("longJobs", params=covered_jobs_params) is Some(_)
  t.frame_at(covered_at + @ui.move_ms(390.0))
  t.frame()
  let held_covered = client.peek_topic("longJobs", params=covered_jobs_params) is Some(_)
  let back_at = t.time()
  nav_home()
  // (read again at the moment it is gone back to, before any frame of the slide)
  let held_back = client.peek_topic("longJobs", params=covered_jobs_params) is Some(_)
  t.frame_at(back_at + @ui.move_ms(390.0))
  t.frame()
  assert_eq((held_sliding, held_covered, held_back), (true, false, true))
  @ui.run_let_go()
}


///|
test "Home covered works nothing out as the core speaks; shown again, drawn from what it last read until the core answers" {
  new_run()
  let client = @core.Client::new(fn(_) {  })
  let t = covered_home(client)
  t.frame()
  t.run_for(first_page_ms)
  guard client.peek_topic("longJobs", params=covered_jobs_params) is Some(first) else { fail("home did not read its jobs") }
  client.receive_json({ "id": Json::number(first.id.to_double()), "value": { "groups": [] } })
  t.frame()
  let covered_at = t.time()
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  t.frame()
  t.frame_at(covered_at + @ui.move_ms(390.0))
  t.frame()
  // (what it read said again while it is covered: nothing of the tree bound anew for it)
  let tree = @ui.view_tree().unwrap()
  let before = tree.work()
  client.receive_json({ "id": Json::number(first.id.to_double()), "value": { "groups": [{ "id": "g1" }] } })
  t.frame()
  let after = tree.work()
  nav_home()
  // (the frames of its way back drawn as a host draws them: its rows held still, rows_steady judging each)
  t.run_for(@ui.move_ms(390.0))
  t.frame()
  if bar_rest() > t.time() {
    t.frame_at(bar_rest())
  }
  // (what comes in by itself as it is shown again come in: what is drawn by the clock still)
  t.run_for(@ui.move_most_ms)
  // (shown again, the core not answered yet: as it last read it)
  let again_words = t.drawn_text()
  // (the core answers as it said before: drawn as it already was, nothing between)
  guard client.peek_topic("longJobs", params=covered_jobs_params) is Some(second) else { fail("home did not read again") }
  client.receive_json({ "id": Json::number(second.id.to_double()), "value": { "groups": [] } })
  t.frame()
  let home_words = t.drawn_text()
  @ui.run_let_go()
  assert_eq((after.bound - before.bound, after.computes - before.computes), (0, 0))
  let lines = fn(s : String) -> Array[String] { s.split("\n").map(fn(l) { l.to_string() }).collect() }
  let (a, b) = (lines(again_words), lines(home_words))
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  let apart = Array::makei(n, fn(i) { i }).iter().find_first(fn(i) { a[i] != b[i] })
  assert_true(a == b, msg="\{a.length()} lines, \{b.length()} answered; apart at \{apart.map(fn(i) { (i, a[i], b[i]) })}")
}

///|
test "a page covered and shown again, the core saying what it reads is the same (asked with the version kept): the very value it read all along, nothing worked out again" {
  new_run()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  client.keep(fn(name, _) { if name == "longJobs" { 4 } else { 0 } })
  let src = signal_client_source(client)
  let shown = @signals.signal(true)
  // (what a page works out of what it reads: worked out again only for another value, never the same one said again)
  let seen : Array[Json?] = []
  let _t = @ui.Tester::new(fn(_c) {  }, tree=fn(root) {
    let gated = src.shown_by(root, fn() { shown.get() })
    let value = @signals.computed(fn(_) { gated.topic("longJobs", covered_jobs_params).get().value }, same=fn(a, b) {
      physical_equal(a, b)
    })
    @signals.effect(fn() { seen.push(value.get()) }) |> ignore
  })
  guard client.peek_topic("longJobs", params=covered_jobs_params) is Some(first) else { fail("not read") }
  client.receive_json({ "id": Json::number(first.id.to_double()), "value": { "groups": [{ "id": "g1" }] } })
  guard seen[seen.length() - 1] is Some(held) else { fail("no value: \{seen}") }
  let worked = seen.length()
  // (covered: let go of, the value kept by the core's client, its version said)
  shown.set(false)
  assert_true(sent[sent.length() - 1].contains("\"keep\":true"), msg=sent[sent.length() - 1])
  client.receive_json({ "id": Json::number(first.id.to_double()), "v": "k:1" })
  // (shown again: asked with that version; till the core answers, as it was)
  shown.set(true)
  assert_true(sent[sent.length() - 1].contains("\"have\":\"k:1\""), msg=sent[sent.length() - 1])
  guard client.peek_topic("longJobs", params=covered_jobs_params) is Some(second) else { fail("not read again") }
  // (the core: the same)
  client.receive_json({ "id": Json::number(second.id.to_double()), "same": true })
  assert_eq(seen.length(), worked, msg="worked out again: \{seen.length() - worked} times")
  assert_true(seen.iter().all(fn(v) { v is None || v.map_or(false, fn(v) { physical_equal(v, held) }) }), msg="\{seen}")
  @ui.run_let_go()
}

///|
test "a page covered lets go of what it read keeping it whatever the topic, and asks it again with its version: the same, nothing anew; changed, as the core says" {
  new_run()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  // (the client keeps nothing of its own accord: what is kept is the covered page's asking)
  client.keep(fn(_, _) { 0 })
  let src : Source = {
    ..signal_client_source(client),
    keep_left: fn(name, params) { client.keep_left(name, params~, most=@sfbase.covered_kept) },
  }
  let shown = @signals.signal(true)
  let seen : Array[Json?] = []
  let _t = @ui.Tester::new(fn(_c) {  }, tree=fn(root) {
    let gated = src.shown_by(root, fn() { shown.get() })
    let value = @signals.computed(fn(_) { gated.topic("longJobs", covered_jobs_params).get().value }, same=fn(a, b) {
      physical_equal(a, b)
    })
    @signals.effect(fn() { seen.push(value.get()) }) |> ignore
  })
  guard client.peek_topic("longJobs", params=covered_jobs_params) is Some(first) else { fail("not read") }
  client.receive_json({ "id": Json::number(first.id.to_double()), "value": { "groups": [{ "id": "g1" }] } })
  guard seen[seen.length() - 1] is Some(held) else { fail("no value: \{seen}") }
  let worked = seen.length()
  // (covered: let go of keeping it, though the client keeps nothing of longJobs itself)
  shown.set(false)
  assert_true(sent[sent.length() - 1].contains("\"keep\":true"), msg=sent[sent.length() - 1])
  client.receive_json({ "id": Json::number(first.id.to_double()), "v": "k:1" })
  // (shown again: asked with its version; the core: the same)
  shown.set(true)
  assert_true(sent[sent.length() - 1].contains("\"have\":\"k:1\""), msg=sent[sent.length() - 1])
  guard client.peek_topic("longJobs", params=covered_jobs_params) is Some(second) else { fail("not read again") }
  client.receive_json({ "id": Json::number(second.id.to_double()), "same": true })
  assert_eq(seen.length(), worked, msg="worked out again: \{seen.length() - worked} times")
  assert_true(seen.iter().all(fn(v) { v is None || v.map_or(false, fn(v) { physical_equal(v, held) }) }), msg="\{seen}")
  // (covered and shown again once more, the core saying it changed meanwhile: its new value, worked out once)
  shown.set(false)
  client.receive_json({ "id": Json::number(second.id.to_double()), "v": "k:1" })
  shown.set(true)
  guard client.peek_topic("longJobs", params=covered_jobs_params) is Some(third) else { fail("not read a third time") }
  client.receive_json({ "id": Json::number(third.id.to_double()), "value": { "groups": [] } })
  assert_eq(seen.length(), worked + 1, msg="\{seen}")
  assert_eq(seen[seen.length() - 1].map(fn(v) { v.stringify() }), Some("{\"groups\":[]}"))
  @ui.run_let_go()
}
