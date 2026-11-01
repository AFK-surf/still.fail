// Signed in, its workspaces still read or failing to be (shell_is's Reading): the splash as the window's tree's nodes
// (reading_tree) drawn as the old view's (signed_in's splash) is, saying 正在读取你的 workspace and what the core waits
// on, or why reading failed at once; the workspaces come, the landing or the workspace in their place.

///|
/// The fixture's `mode` signed in, its workspaces as `ws` says (what the core's topic is: none read yet, failed, read)
/// and what the core waits on as `status` says, 390 by 844 to touch: the old view alone or the app's tree. The Tester,
/// the splash's second waited.
fn reading_case(
  node : Bool,
  ws : @signals.Signal[@sfbase.Topic],
  status : @signals.Signal[String],
  waited? : Bool = true,
) -> @ui.Tester {
  new_run()
  let base = fixture("landing")
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      match name {
        "workspaces" => ws.get()
        "status" => {
          let s = status.get()
          { value: Some({ "text": Json::string(s) }), error: None, version: s.length() + 1 }
        }
        _ => (base.topic)(name, params)
      }
    },
  }
  let t = if node {
    @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  } else {
    @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  }
  t.check_looks(false)
  if waited {
    t.run_for(splash_label_ms)
  }
  t
}

///|
/// What is drawn: rects, glyphs (where), shapes (the mark's).
fn reading_drawn(
  t : @ui.Tester,
) -> (Array[(Double, Double, Double, Double, Int64)], Array[(Double, Double)], Array[(Double, Double, Double, Double, Double, Int64)]) {
  (t.drawn_rects(), t.drawn_glyphs().map(fn(g) { (g.0, g.1) }), t.drawn_shapes())
}

///|
/// The workspaces' topic none read yet (`error`: failed so).
fn reading_topic(error? : String = "", version? : Int = 1) -> @sfbase.Topic {
  { value: None, error: if error == "" { None } else { Some({ "message": Json::string(error) }) }, version }
}

///|
test "signed in, its workspaces read: the splash as nodes drawn as the old one is, saying it reads them and what the core waits on; failed, why at once" {
  let cases = [("", ""), ("", "正在连接 still.fail cloud"), ("连接 still.fail cloud 失败", "")]
  let seen = []
  let same = cases.map(fn(k) {
    let (error, status) = k
    let draw = fn(node) {
      reading_drawn(
        reading_case(
          node,
          @signals.signal(reading_topic(error~), same=fn(a, b) { physical_equal(a, b) }),
          @signals.signal(status, same=fn(a, b) { a == b }),
        ),
      )
    }
    let (old, new) = (draw(false), draw(true))
    if old != new {
      seen.push("\{k}: old \{old.0} \{old.1.length()} \{old.2.length()} node \{new.0} \{new.1.length()} \{new.2.length()}")
    }
    old == new && old.2.length() > 0
  })
  assert_eq(same, Array::make(cases.length(), true), msg="\{seen}")
}

///|
test "signed in, its workspaces read as nodes: what the core waits on said as it changes; failed, said so; read, none in them: the landing in its place" {
  let ws = @signals.signal(reading_topic(), same=fn(a, b) { physical_equal(a, b) })
  let status = @signals.signal("", same=fn(a, b) { a == b })
  let t = reading_case(true, ws, status)
  // (said by the window's tree's own nodes, not an old view hosted in it)
  let by_tree = @ui.view_tree().unwrap().drawn().iter().any(fn(d) { d.words.has_prefix("正在读取你的 workspace") })
  let reading = t.find("正在读取你的 workspace") is Some(_) && by_tree
  status.set("正在连接 still.fail cloud")
  t.frame()
  let waits = t.find("正在连接 still.fail cloud") is Some(_)
  ws.set(reading_topic(error="连接 still.fail cloud 失败", version=2))
  t.frame()
  let failed = (t.find("连接 still.fail cloud 失败") is Some(_), t.find("正在读取你的 workspace") is None)
  // (read: none of them, every account answered: the landing)
  ws.set({ value: Some([{ "account": { "sub": "u1", "email": "lin@example.com", "name": "林" }, "workspaces": [], "invitations": [], "loaded": true }]), error: None, version: 3 })
  t.frame()
  let landing = (t.find("尚未加入任何 workspace") is Some(_), t.find("连接 still.fail cloud 失败") is None)
  assert_eq((reading, waits, failed, landing), (true, true, (true, true), (true, true)))
}

///|
/// Before the splash's second: no less than this of it left.
let reading_early_ms : Double = 300.0

///|
test "signed in, its workspaces read as nodes, before the splash's second: the ground alone; reading them failed then: why, at once, the frame not bare" {
  let ws = @signals.signal(reading_topic(), same=fn(a, b) { physical_equal(a, b) })
  let t = reading_case(true, ws, @signals.signal("", same=fn(a, b) { a == b }), waited=false)
  let early = (t.find("正在读取你的 workspace") is None, frame_bare.val, splash_waited.get())
  t.run_for(reading_early_ms)
  ws.set(reading_topic(error="连接 still.fail cloud 失败", version=2))
  t.frame()
  let failed = (t.find("连接 still.fail cloud 失败") is Some(_), frame_bare.val, splash_waited.get())
  assert_eq((early, failed), ((true, true, false), (true, false, false)))
}

///|
test "signed in, its workspaces read as nodes, then read with one in them: the workspace in view, its shell in the splash's place" {
  let ws = @signals.signal(reading_topic(), same=fn(a, b) { physical_equal(a, b) })
  let t = reading_case(true, ws, @signals.signal("", same=fn(a, b) { a == b }))
  let reading = t.find("正在读取你的 workspace") is Some(_)
  ws.set({
    value: Some([
      {
        "account": { "sub": "u1", "email": "lin@example.com", "name": "林" },
        "workspaces": [{ "id": "ws1", "name": "星火工作室", "stations": 2, "members": 3 }],
        "invitations": [],
        "loaded": true,
      },
    ]),
    error: None,
    version: 3,
  })
  t.draw()
  // (its Home, the workspace's name at its top)
  assert_eq((reading, t.find("正在读取你的 workspace") is None, t.find("星火工作室") is Some(_)), (true, true, true))
}
