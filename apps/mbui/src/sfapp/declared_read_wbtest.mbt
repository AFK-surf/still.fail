// What the workspace in view's first screen opens on is declared as the workspace comes to be in view (sfbase's
// opens_ahead_node: each shell's home_opens or frame_opens), asked of the core then and taken over by the readers
// that come to read it (sfbase's declare_topic). Held here on each screen, opened over the made-up core through the
// app's own client: once the first screen is at rest, none of it is left declared and read by no reader (a
// declaration of what that screen does not read: mended in its opens, never let be: the coordinator of the
// migration, 2026-11-12), and from the declaration through the reader taking it the core is told of no topic left
// and asked again (the same subscription all along).

///|
/// What the client sent the made-up core, `heard` (round_trip_again's), read for a topic let go of and asked again:
/// each such, by its topic.
fn asked_again(heard : Array[String]) -> Array[String] {
  let by_id : Map[Int, String] = Map([])
  let left : Map[String, Bool] = Map([])
  let again : Array[String] = []
  for h in heard {
    guard h.has_prefix("out ") else { continue }
    let j = @json.parse(h.exact_view(start=4).to_owned()) catch { _ => continue }
    guard j is Object(m) && m.get("id") is Some(Number(n, ..)) else { continue }
    let id = n.to_int()
    match (m.get("subscribe"), m.get("unsubscribe")) {
      (Some(t), _) => {
        let key = t.stringify()
        if left.contains(key) {
          again.push(key)
        }
        by_id[id] = key
      }
      (_, Some(_)) =>
        match by_id.get(id) {
          Some(key) => left[key] = true
          None => ()
        }
      _ => ()
    }
  }
  again
}

///|
test "what the first screen opens on, declared as its workspace comes in view: on 小屏, 中屏 and 大屏 all of it read once the screen is at rest, none of it let go of and asked again on the way" {
  let faults : Array[String] = []
  for s in switch_screens {
    let (name, w, h, platform) = s
    let heard : Array[String] = []
    let _ = switch_on(fn(_) { 60.0 }, heard, w, h, platform, 60.0)
    let unread = @sfbase.declared_unread()
    if unread.length() > 0 {
      faults.push("\{name}: declared and read by none at rest: " + unread.join(", "))
    }
    let again = asked_again(heard)
    if again.length() > 0 {
      faults.push("\{name}: let go of and asked again as it opened: " + again.join(", "))
    }
  }
  assert_eq(faults, [])
}

///|
test "what a run declared and no reader took is let go of as the next run begins: the core told, not left followed by nothing into it" {
  fresh_app()
  let base = fixture("home")
  let let_go : Array[String] = []
  let src : Source = {
    ..base,
    release: fn(name, params) {
      let_go.push(name + " " + Json::object(params).stringify())
      (base.release)(name, params)
    },
  }
  let params : Map[String, Json] = { "scope": Json::string("ws1") }
  @sfbase.declare_topic(src, "longJobs", params) |> ignore
  assert_eq(@sfbase.declared_unread().length(), 1)
  assert_eq(let_go, [])
  // the next run begins
  fresh_app()
  assert_eq(let_go, ["longJobs " + Json::object(params).stringify()])
  assert_eq(@sfbase.declared_unread(), [])
}

///|
test "a chat's page's reads declared as it comes on top: asked at that moment, the frames that build it asking nothing more till its view is answered (what that leads to its readers'), and all of them read once it is at rest, on 小屏 and 大屏" {
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  let faults : Array[String] = []
  for w in [390.0, 1280.0] {
    new_run()
    let base = fixture("home")
    // (each topic the app comes to follow, as it is first read of the made-up core; after the chat came on top, those
    // first read then; the chat's view not answered till `answered`)
    let seen : Map[String, Bool] = Map([])
    let after : Array[String] = []
    let opened = Ref(false)
    let answered = @signals.signal(true)
    let src : Source = {
      ..base,
      topic_read: fn(name, params) {
        let key = name + " " + Json::object(params).stringify()
        if !seen.contains(key) {
          seen[key] = true
          if opened.val {
            after.push(key)
          }
        }
        if name == "chat" && !answered.get() {
          return { value: None, error: None, version: 0 }
        }
        base.topic(name, params).get().snapshot()
      },
    }
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h=800.0, platform=0)
    t.run_for(@sf.local_ms)
    answered.set(false)
    @sfbase.open_chat(r)
    opened.val = true
    t.run_for(@sf.local_ms)
    if after.length() > 0 {
      faults.push("\{w}: asked as a frame built it, not declared: " + after.join(", "))
    }
    answered.set(true)
    t.run_for(@sf.local_ms)
    let unread = @sfbase.declared_unread()
    if unread.length() > 0 {
      faults.push("\{w}: declared and read by none at rest: " + unread.join(", "))
    }
  }
  assert_eq(faults, [])
}
