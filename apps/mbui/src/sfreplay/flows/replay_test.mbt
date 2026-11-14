// The app over kept conversations with its core (source.mbt).

///|
fn signed_out_run() -> Unit raise {
  // The preceding run must release its readers while its own replay is still attached. Otherwise resetting the
  // client can make those readers subscribe into this recording before this Tester's first frame.
  @ui.run_let_go()
  @sfbase.reset()
  let r = @core.Replay::parse((
    #|{"out":{"id":1,"subscribe":{"topic":"accounts"},"keyed":true}}
    #|{"in":{"id":1,"value":[]},"w":1000}
  ))
  r.attach()
  @sfcore.listen(@sfapp.core_taking())
  let t = @ui.Tester::new(@sfreplay.app, tree=@sfreplay.app_tree)
  // posted to mbui's queue, taken by the next frame as it begins
  assert_eq(r.deliver(to=fn(json, bytes) { t.post("core", json, bytes?) }), 1)
  assert_true(t.find("登录") is None)
  t.draw()
  assert_true(t.find("登录") is Some(_))
  // (past the app's first splash's second, which the window's tree waits from its start whatever the core says: then
  // nothing left to wake for)
  t.run_for(@sfapp.splash_label_ms)
  assert_true(t.find("登录") is Some(_))
  t.assert_idle()
  @core.Replay::detach()
}

///|
test "signed out, as a run's core said: the sign-in page" {
  signed_out_run()
}

///|
test "a signed-out replay after a signed-in run starts with its own accounts" {
  let previous = @sfreplay.Flow::start(@sfreplay.trace("draft"))
  previous.see("端到端测试")
  signed_out_run()
}

///|
test "a legacy jobs recording is shared by the bar and the opened sheet" {
  @ui.run_let_go()
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
  @sfbase.held_build()
  src.topic("chatJobs", summary).get().snapshot() |> ignore
  @sfbase.held_end()
  assert_eq(r.deliver(), 1)
  @sfbase.held_build()
  let shown = src.topic("chatJobs", full).get().value
  assert_eq(shown.unwrap().stringify(), "{\"jobs\":[{\"id\":\"j1\"}]}")
  @sfbase.held_end()
  (src.leave)("chatJobs", full, @sfbase.TopicLeave::Legacy)
  (src.leave)("chatJobs", summary, @sfbase.TopicLeave::Legacy)
  assert_eq(r.diverged(), [])
  assert_eq(r.fuzzy().length(), 0)
  @core.Replay::detach()
}

///|
test "a newer jobs recording keeps the summary and sheet separate" {
  @ui.run_let_go()
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
  @sfbase.held_build()
  src.topic("chatJobs", summary).get().snapshot() |> ignore
  @sfbase.held_end()
  assert_eq(r.deliver(), 1)
  @sfbase.held_build()
  src.topic("chatJobs", full).get().snapshot() |> ignore
  @sfbase.held_end()
  assert_eq(r.deliver(), 1)
  @sfbase.held_build()
  assert_eq(src.topic("chatJobs", summary).get().value.unwrap().stringify(), "{\"jobs\":[],\"hasJobs\":true}")
  assert_eq(src.topic("chatJobs", full).get().value.unwrap().stringify(), "{\"jobs\":[{\"id\":\"j1\"}]}")
  assert_eq(r.diverged(), [])
  assert_eq(r.fuzzy().length(), 0)
  @sfbase.held_end()
  @core.Replay::detach()
}
