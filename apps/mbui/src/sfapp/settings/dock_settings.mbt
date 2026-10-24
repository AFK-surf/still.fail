// The desktop's dock's settings (apps/desktop/src/main.ts dockSettings, dock.mts dockKinds), kept on this device by its
// host (@ui.dock_kept: the desktop app's userData/dock.json there): shown at all (off until turned on), new ones
// peeking out, and which chats it holds by kind (waiting on the person, failed, unread an agent said last, unread
// someone else did; `unread`, kept before the kinds were, both kinds of unread).

///|
/// What the dock's settings say: on, peek, and each kind (wait, failed, done, message).
pub fn dock_setting(key : String) -> Bool {
  let parsed = @json.parse(@ui.dock_kept()) catch { _ => Json::null() }
  let kept = Some(parsed)
  let unread = field(kept, "unread") != Some(Json::boolean(false))
  let given = match key {
    "on" | "peek" => field(kept, key)
    _ => field(field(kept, "kinds"), key)
  }
  match given {
    Some(True) => true
    Some(False) => false
    _ =>
      match key {
        "on" => false
        "peek" | "wait" | "failed" => true
        _ => unread
      }
  }
}

///|
/// One of the dock's settings changed (on, peek, or a kind), kept as the desktop app keeps them.
pub fn dock_set(key : String, on : Bool) -> Unit {
  let kinds = ["wait", "failed", "done", "message"].map(fn(k) {
    (k, Json::boolean(if k == key { on } else { dock_setting(k) }))
  })
  let done = if key == "done" { on } else { dock_setting("done") }
  let message = if key == "message" { on } else { dock_setting("message") }
  let all : Json = {
    "on": Json::boolean(if key == "on" { on } else { dock_setting("on") }),
    "peek": Json::boolean(if key == "peek" { on } else { dock_setting("peek") }),
    "unread": Json::boolean(done || message),
    "kinds": Json::object(Map::from_array(kinds)),
  }
  @ui.dock_keep(all.stringify())
}
