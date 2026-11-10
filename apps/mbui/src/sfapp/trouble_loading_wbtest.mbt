// A native core answers after the frame, not synchronously as the ordinary fixture does. Clearing a station's old
// trouble must not enqueue the same write on every frame before that answer and the updated prefs arrive.

///|
/// The declared time for which the fake core holds its answer, while the window continues drawing.
let trouble_core_delay_ms : Double = 3000.0

///|
fn trouble_loading_tester(calls : Array[Made], loaded : @signals.Signal[Bool], prefs : @signals.Signal[Json], generation? : Ref[Int] = Ref(0)) -> @ui.Tester {
  new_run()
  let base = fixture("home")
  let src : Source = {
    ..base,
    generation: fn(_, _) { (generation.val, true) },
    topic_read: fn(name, params) {
      if name == "chats" && !loaded.get() {
        return { value: None, error: None, version: 0 }
      }
      if name == "prefs" {
        let value = match (base.topic_read)(name, params).value {
          Some(Object(m)) => m.copy()
          _ => {}
        }
        value["trouble"] = prefs.get()
        return { value: Some(Json::object(value)), error: None, version: 1 }
      }
      (base.topic_read)(name, params)
    },
    call: fn(name, params, done) {
      if name == "prefs.set" && field(Some(params), "trouble") is Some(_) {
        calls.push({ name, params, bytes: None, done, heard: None })
      } else {
        (base.call)(name, params, done)
      }
    },
  }
  @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
}

///|
test "a workspace's chats still loading do not clear its remembered trouble" {
  let calls : Array[Made] = []
  let loaded = @signals.signal(false)
  let prefs : @signals.Signal[Json] = @signals.signal({ "ws1\nseen": "Maple 连不上了" })
  let t = trouble_loading_tester(calls, loaded, prefs)
  t.frame()
  t.frame()
  assert_eq(calls.length(), 0, msg="no chats value is not evidence that its stations recovered: \{calls.length()} writes")
  loaded.set(true)
  t.frame()
  assert_eq(calls.length(), 1, msg="clear once only after the chats value confirms recovery")
}

///|
test "clearing old trouble is one write until the core's changed prefs arrive" {
  let calls : Array[Made] = []
  let loaded = @signals.signal(true)
  let prefs : @signals.Signal[Json] = @signals.signal({ "ws1\nseen": "Maple 连不上了", "ws1\ngone": "Maple 连不上了" })
  let t = trouble_loading_tester(calls, loaded, prefs)
  t.frame()
  t.run_for(trouble_core_delay_ms)
  assert_eq(calls.length(), 1, msg="redraws must not fill the core's queue with duplicate writes: \{calls.length()} writes")
  assert_eq(field(field(Some(calls[0].params), "trouble"), "ws1\nseen"), Some(Json::null()))
  assert_eq(field(field(Some(calls[0].params), "trouble"), "ws1\ngone"), Some(Json::null()))
  (calls[0].done)(Ok(Json::null()))
  t.frame()
  t.frame()
  assert_eq(calls.length(), 1, msg="the call answer can precede the subscription's changed value")
  prefs.set({})
  t.frame()
  prefs.set({ "ws1\nseen": "Maple 连不上了" })
  t.frame()
  assert_eq(calls.length(), 2, msg="the same trouble in a later incident can be forgotten again")
}

///|
test "a failed trouble clear does not retry on every frame and a new core can clear it" {
  let calls : Array[Made] = []
  let loaded = @signals.signal(true)
  let prefs : @signals.Signal[Json] = @signals.signal({ "ws1\nseen": "Maple 连不上了" })
  let generation = Ref(0)
  let t = trouble_loading_tester(calls, loaded, prefs, generation~)
  t.frame()
  assert_eq(calls.length(), 1)
  (calls[0].done)(Err({ "code": "core_restarted" }))
  t.run_for(trouble_core_delay_ms)
  assert_eq(calls.length(), 1, msg="an error is not a reason to write again each frame")
  generation.val += 1
  t.frame()
  t.frame()
  assert_eq(calls.length(), 2, msg="an old core's pending clearing does not suppress the new core")
}
