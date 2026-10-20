// Notifications, as still.fail's Android app has them (ember apps/android app/Notices.kt, Push.kt, App.kt,
// MainActivity.kt; docs/notifications.md → Clients): one channel (消息), one notification per chat (its tag), a tap
// opening the chat at the message it is about with Back going to its chat list.
//
// - While the app is shown: the notices the core's `notify {workspace}` says to show now (not while off, not for the
//   chat looked at, only of the workspace in view: client/core-ts attend.ts decides), each shown once it is taken
//   (`notice.claim`). Hidden, the topic is left (the core then holds none back for a page: Notices.kt's flow ends
//   with the activity's onStop).
// - What the system lets the app show, told to the core as the app starts and each time it is shown again
//   (`notify.permission`); the system asked once, the first time signed in with notifications on (`notify.set
//   {asked}`), and again as they are turned on in settings (refused there, a toast says where to allow them).
// - A chat on top: its notification taken off (App.kt). A notification tapped: its link read by the core
//   (`link.parse`), its workspace switched to, the chat pushed over Home at the message (chat.mbt `go_to`).
// - Pushes (Push.kt): this device's registration held as the core's `notify` says (`push.register` with the host's
//   token, `push.unregister` while off); a push delivered while the app runs shown unless the core says not
//   (`notice.pushed`), then what it is about brought onto the device (`notice.bring`). No push service is linked in
//   this build (src/host/notify.mbt): there is no token, and nothing is delivered.
//
// Nothing of it with Source.read_only (a run on a real account changes nothing in it).

///|
/// What the system is asked through (@ui's, the host's on a device and a Tester's own under one; tests put their own).
priv struct NoticeHost {
  show : (String, String, String, String) -> Unit
  cancel : (String) -> Unit
  permission : () -> String
  ask : () -> Bool
  answer : () -> Bool?
  opened : () -> String
  token : () -> String
  pushed : () -> String
}

///|
fn host_notices() -> NoticeHost {
  {
    show: fn(tag, title, body, opens) {
      @ui.notice_show(channel=tr("android-misc.notify.channel"), tag~, title~, body~, opens~)
    },
    cancel: fn(tag) { @ui.notice_cancel(tag) },
    permission: fn() { @ui.notice_permission() },
    ask: fn() { @ui.notice_ask() },
    answer: fn() { @ui.notice_answer() },
    opened: fn() { @ui.notice_opened() },
    token: fn() { @host.push_token() },
    pushed: fn() { @host.push_next() },
  }
}

///|
let notice_host : Ref[NoticeHost] = Ref(host_notices())

///|
priv struct NoticeState {
  /// the notices of `notify.show` taken already, by id
  taken : Map[String, Bool]
  /// the workspace whose `notify` is followed ("" none)
  mut following : String
  /// what the system allows was told since the app was last shown
  mut told : Bool
  /// the system asked once (the first time signed in with notifications on)
  mut asked_once : Bool
  /// an ask from settings' switch is under way: refused, a toast says where to allow them
  mut from_switch : Bool
  /// the push registration held as the core says, once at the start
  mut synced : Bool
  /// the chat whose notification was taken off as it came on top ("" none on top)
  mut cancelled : String
  /// the source last seen, for the system's say between frames
  mut src : Source?
}

///|
let nt : NoticeState = {
  taken: {},
  following: "",
  told: false,
  asked_once: false,
  from_switch: false,
  synced: false,
  cancelled: "",
  src: None,
}

///|
fn notices_reset() -> Unit {
  nt.taken.clear()
  nt.following = ""
  nt.told = false
  nt.asked_once = false
  nt.from_switch = false
  nt.synced = false
  nt.cancelled = ""
  nt.src = None
  notice_host.val = host_notices()
}

///|
fn notify_params(workspace : String) -> Map[String, Json] {
  { "workspace": Json::string(workspace) }
}

///|
/// Each frame, signed in, the workspace `w` in view.
fn notices_frame(src : Source, w : Workspace) -> Unit {
  if src.read_only {
    return
  }
  nt.src = Some(src)
  let h = notice_host.val
  let shown = @ui.app_visible()
  let notify = (src.topic)("notify", Map::new()).value
  match notify {
    Some(_) => {
      // what the system allows, as the app starts and each time it is shown again (MainActivity onStart)
      if shown && !nt.told {
        nt.told = true
        tell_permission(src, notify)
      }
      // asked once, the first time signed in with notifications on (App.kt rememberNotificationAsk(once))
      if !nt.asked_once && flag(notify, "on") && field(notify, "asked") is Some(False) {
        nt.asked_once = true
        (src.call)("notify.set", { "asked": Json::boolean(true) }, fn(_) {  })
        (h.ask)() |> ignore
      }
      // the registration for pushes, once at the start (MainActivity: Push.sync)
      if !nt.synced {
        nt.synced = true
        push_sync(src, None)
      }
    }
    None => ()
  }
  // the system's answer to an ask
  match (h.answer)() {
    Some(granted) => {
      if !granted && nt.from_switch {
        app.toast = fill("android-misc.notify.allowInSettings", [("app", "still.fail")])
        app.toast_at = -1.0
      }
      nt.from_switch = false
      (src.call)(
        "notify.permission",
        { "state": Json::string(if granted { "granted" } else { "denied" }) },
        fn(_) {  },
      )
    }
    None => ()
  }
  // the notices to show while the app is shown (Notices.kt showNotices)
  if shown {
    follow_notices(src, w.id)
  } else {
    leave_notices(src)
  }
  // a notification tapped
  match (h.opened)() {
    "" => ()
    opens => open_notice(src, w, opens)
  }
  // a push delivered while the app runs
  match (h.pushed)() {
    "" => ()
    data => pushed(src, data)
  }
  // a chat on top: its notification goes (App.kt LaunchedEffect(top))
  match app.nav.top() {
    Chat(r) => {
      let tag = r.station + "/" + r.session
      if nt.cancelled != tag {
        nt.cancelled = tag
        (h.cancel)(tag)
      }
    }
    _ => nt.cancelled = ""
  }
}

///|
/// The system said the app was hidden or shown again, between frames (Android's activity stopping: no frame comes
/// after it): hidden, the notices are not followed any more, and what the system allows is told again once shown.
fn notices_app_change(shown : Bool) -> Unit {
  if shown {
    return
  }
  nt.told = false
  match nt.src {
    Some(src) => leave_notices(src)
    None => ()
  }
}

///|
/// The core's `notify {workspace}`: each notice it says to show now taken (`notice.claim`), and shown when this page
/// is the one that took it.
fn follow_notices(src : Source, workspace : String) -> Unit {
  if nt.following != workspace {
    leave_notices(src)
    nt.following = workspace
  }
  let v = (src.topic)("notify", notify_params(workspace)).value
  for n in items(v, "show") {
    let id = text(Some(n), "id")
    if id == "" || nt.taken.contains(id) {
      continue
    }
    nt.taken[id] = true
    (src.call)("notice.claim", { "id": Json::string(id) }, fn(r) {
      match r {
        Ok(a) if flag(Some(a), "show") => show_notice(n)
        _ => ()
      }
    })
  }
}

///|
fn leave_notices(src : Source) -> Unit {
  if nt.following != "" {
    (src.leave)("notify", notify_params(nt.following))
    nt.following = ""
  }
}

///|
/// A notice shown (Notifier.show): its chat's tag, its title and words; tapped, it opens its `url` at its `seq`.
fn show_notice(n : Json) -> Unit {
  let seq = match field(Some(n), "seq") {
    Some(Number(s, ..)) if s > 0.0 => s.to_int().to_string()
    _ => ""
  }
  (notice_host.val.show)(
    text(Some(n), "tag"),
    text(Some(n), "title"),
    text(Some(n), "body"),
    text(Some(n), "url") + "\n" + seq,
  )
}

///|
/// What the system lets the app show, to the core (Notifier.permission): the host's say, "default" while the system
/// can still be asked and never was.
fn tell_permission(src : Source, notify : Json?) -> Unit {
  let state = match (notice_host.val.permission)() {
    "ask" => if field(notify, "asked") is Some(False) { "default" } else { "denied" }
    s => s
  }
  (src.call)("notify.permission", { "state": Json::string(state) }, fn(_) {  })
}

///|
/// The system asked to allow notifications as they are turned on in settings (rememberNotificationAsk, not once).
fn ask_from_switch() -> Unit {
  if (notice_host.val.ask)() {
    nt.from_switch = true
  }
}

///|
/// This device's push registration as the core wants it (Push.sync): taken off every account when its `notify`
/// says no pushes, else registered with the host's token (none in this build). `wanted`: what the core has just
/// answered, else what its `notify` says.
fn push_sync(src : Source, wanted : Bool?) -> Unit {
  let push = match wanted {
    Some(b) => Some(b)
    None =>
      match field((src.topic)("notify", Map::new()).value, "push") {
        Some(True) => Some(true)
        Some(False) => Some(false)
        _ => None
      }
  }
  match push {
    Some(false) => (src.call)("push.unregister", Json::object(Map::new()), fn(_) {  })
    Some(true) =>
      match (notice_host.val.token)() {
        "" => ()
        token =>
          (src.call)(
            "push.register",
            { "kind": Json::string("fcm"), "token": Json::string(token) },
            fn(_) {  },
          )
      }
    None => ()
  }
}

///|
/// A notification tapped (MainActivity.handle): its link read by the core (`link.parse`), an item's chat opened over
/// its workspace's Home at the message it is about.
fn open_notice(src : Source, w : Workspace, opens : String) -> Unit {
  let (url, seq) = match opens.find("\n") {
    Some(i) => (opens.view(end_offset=i).to_owned(), opens.view(start_offset=i + 1).to_owned())
    None => (opens, "")
  }
  let at = match seq_of(seq) {
    n if n > 0.0 => Some(n)
    _ => None
  }
  (src.call)("link.parse", { "url": Json::string(trim_slash(cloud_origin()) + url) }, fn(r) {
    match r {
      Ok(t) if text(Some(t), "opens") == "item" && text(Some(t), "session") != "" => {
        let ws = text(Some(t), "workspace")
        let station = ws + "/" + text(Some(t), "station")
        let session = text(Some(t), "session")
        @host.log("notice opens \{station}|\{session} at \{seq}")
        open_item(src, w, ws, station, session, at)
      }
      Ok(_) => @host.log("notice: the link opens nothing here: " + url)
      Err(e) => @host.log("notice: link.parse failed: " + text(Some(e), "message"))
    }
  })
}

///|
/// An item's chat from outside (AppState.openItem): its workspace in view, nothing over Home but the chat, opened at
/// `at` (the message a notification is about).
fn open_item(src : Source, w : Workspace, ws : String, station : String, session : String, at : Double?) -> Unit {
  if ws != "" && ws != w.id {
    app.picked = ws
    (src.call)("prefs.set", { "workspace": Json::string(ws) }, fn(_) {  })
  }
  home()
  if app.nav.top() != Home {
    app.nav.replace(Home)
  }
  let r : ChatRef = { station, session, title: "", station_name: "" }
  match at {
    Some(seq) => go_to(r, seq)
    None => ()
  }
  app.nav.push(Chat(r))
}

///|
/// A push delivered (PushService.onMessageReceived): shown unless the core says not (`notice.pushed`: off, a page in
/// view, another workspace's, its kind off), then what it is about brought onto the device (`notice.bring`).
fn pushed(src : Source, data : String) -> Unit {
  let parsed = @json.parse(data) catch { _ => Json::null() }
  let d = match parsed {
    Object(_) => Some(parsed)
    _ => None
  }
  if text(d, "type") != "notice" || text(d, "tag") == "" || text(d, "url") == "" {
    return
  }
  let ask : Map[String, Json] = {}
  for k in ["workspace", "kind"] {
    if text(d, k) != "" {
      ask[k] = Json::string(text(d, k))
    }
  }
  (src.call)("notice.pushed", Json::object(ask), fn(r) {
    let show = match r {
      Ok(a) => flag(Some(a), "show")
      // the core not answering: shown unless the app is in front (it shows its own)
      Err(_) => !@ui.app_focused()
    }
    if !show {
      return
    }
    (notice_host.val.show)(
      text(d, "tag"),
      text(d, "title"),
      text(d, "body"),
      text(d, "url") + "\n" + text(d, "seq"),
    )
    let ws = text(d, "workspace")
    let st = text(d, "station")
    let session = text(d, "session")
    if ws == "" || st == "" || session == "" {
      return
    }
    let bring : Map[String, Json] = {
      "station": Json::string(ws + "/" + st),
      "session": Json::string(session),
    }
    let seq = seq_of(text(d, "seq"))
    if seq > 0.0 {
      bring["seq"] = Json::number(seq)
    }
    (src.call)("notice.bring", Json::object(bring), fn(_) {  })
  })
}

///|
/// A message's number as a notification carries it ("12"): 0 when there is none.
fn seq_of(s : String) -> Double {
  let mut n = 0.0
  if s == "" {
    return 0.0
  }
  for ch in s {
    if ch < '0' || ch > '9' {
      return 0.0
    }
    n = n * 10.0 + (ch.to_int() - '0'.to_int()).to_double()
  }
  n
}

///|
fn trim_slash(o : String) -> String {
  if o.has_suffix("/") {
    o.view(end_offset=o.length() - 1).to_owned()
  } else {
    o
  }
}
