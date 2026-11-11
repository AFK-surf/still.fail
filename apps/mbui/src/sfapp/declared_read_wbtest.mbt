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
