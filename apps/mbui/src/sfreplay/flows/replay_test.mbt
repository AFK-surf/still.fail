// The app over kept conversations with its core (source.mbt).

///|
test "signed out, as a run's core said: the sign-in page" {
  let r = @core.Replay::parse((
    #|{"out":{"id":1,"subscribe":{"topic":"accounts"},"keyed":true}}
    #|{"in":{"id":1,"value":[]},"w":1000}
  ))
  r.attach()
  @ui.on_message("core", @core.receive)
  let t = @ui.Tester::new(@sfreplay.app)
  // posted to mbui's queue, taken by the next frame as it begins
  assert_eq(r.deliver(to=fn(json, bytes) { t.post("core", json, bytes?) }), 1)
  assert_true(t.find("登录") is None)
  t.draw()
  assert_true(t.find("登录") is Some(_))
  t.assert_idle()
  @core.Replay::detach()
}

///|
test "a legacy jobs recording is shared by the bar and the opened sheet" {
  let r = @core.Replay::parse((
    #|{"out":{"id":7,"subscribe":{"topic":"chatJobs","station":"w/s","session":"k"},"keyed":true}}
    #|{"in":{"id":7,"value":{"jobs":[{"id":"j1"}]}},"w":1}
    #|{"out":{"id":7,"unsubscribe":true}}
  ))
  r.attach()
  @sfreplay.use_recorded_jobs(r)
  let src = @sfreplay.source()
  let full : Map[String, Json] = { "station": "w/s", "session": "k" }
  let summary : Map[String, Json] = { "station": "w/s", "session": "k", "summary": true }
  (src.topic)("chatJobs", summary) |> ignore
  assert_eq(r.deliver(), 1)
  let shown = (src.topic)("chatJobs", full).value
  assert_eq(shown.unwrap().stringify(), "{\"jobs\":[{\"id\":\"j1\"}]}")
  (src.leave)("chatJobs", full)
  (src.leave)("chatJobs", summary)
  assert_eq(r.diverged().length(), 0)
  assert_eq(r.fuzzy().length(), 0)
  @core.Replay::detach()
}

///|
test "a newer jobs recording keeps the summary and sheet separate" {
  let r = @core.Replay::parse((
    #|{"out":{"id":7,"subscribe":{"topic":"chatJobs","station":"w/s","session":"k","summary":true,"compact":true},"keyed":true}}
    #|{"in":{"id":7,"value":{"jobs":[],"hasJobs":true}},"w":1}
    #|{"out":{"id":8,"subscribe":{"topic":"chatJobs","station":"w/s","session":"k","compact":true},"keyed":true}}
    #|{"in":{"id":8,"value":{"jobs":[{"id":"j1"}]}},"w":2}
  ))
  r.attach()
  @sfreplay.use_recorded_jobs(r)
  let src = @sfreplay.source()
  let full : Map[String, Json] = { "station": "w/s", "session": "k" }
  let summary : Map[String, Json] = { "station": "w/s", "session": "k", "summary": true }
  (src.topic)("chatJobs", summary) |> ignore
  assert_eq(r.deliver(), 1)
  (src.topic)("chatJobs", full) |> ignore
  assert_eq(r.deliver(), 1)
  assert_eq((src.topic)("chatJobs", summary).value.unwrap().stringify(), "{\"jobs\":[],\"hasJobs\":true}")
  assert_eq((src.topic)("chatJobs", full).value.unwrap().stringify(), "{\"jobs\":[{\"id\":\"j1\"}]}")
  assert_eq(r.diverged().length(), 0)
  assert_eq(r.fuzzy().length(), 0)
  @core.Replay::detach()
}
