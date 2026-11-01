// Notifications, as still.fail's Android app has them (ember apps/android app/Notices.kt, Push.kt, App.kt,
// MainActivity.kt; docs/notifications.md → Clients): one channel (消息), one notification per chat (its tag), a tap
// opening the chat at the message it is about with Back going to its chat list.
//
// - While the app goes on (shown, or put away where its host still runs it: a desktop's app in the notification area
//   or minimized, @ui.app_awake, as still.fail's desktop app showed its notices with no window open): the notices the
//   core's `notify {workspace}` says to show now (not while off, not for the chat looked at, none of a workspace turned
//   off, another workspace's named in its title: client/core-ts attend.ts decides), each shown once it is taken (`notice.claim`). Behind for good (a phone's
//   app behind another, its frames stopped), the topic is left (the core then holds none back for a page: Notices.kt's
//   flow ends with the activity's onStop).
// - What the system lets the app show, told to the core as the app starts and each time it is shown again
//   (`notify.permission`); the system asked once, the first time signed in with notifications on (`notify.set
//   {asked}`), and again as they are turned on in settings (refused there, a toast says where to allow them).
// - A chat on top: its notification taken off (App.kt). A notification tapped: its link read by the core
//   (`link.parse`), its workspace switched to, the chat pushed over Home at the message (chat.mbt `go_to`).
// - Pushes (Push.kt): this device's registration held as the core's `notify` says (`push.register` with the host's
//   token, `push.unregister` while off), a token come later registered then. A push delivered is the app's push
//   service's (android/…/Push.java, as PushService: it asks the core whether to show it, `notice.pushed`, then brings
//   what it is about, `notice.bring`), since the app's frames stop while it is behind.
//
// Nothing of it with Source.read_only (a run on a real account changes nothing in it).

///|
/// What the system is asked through (@ui's, the host's on a device and a Tester's own under one; tests put their own).
pub(all) struct NoticeHost {
  show : (String, String, String, String) -> Unit
  cancel : (String) -> Unit
  permission : () -> String
  ask : () -> Bool
  answer : () -> Bool?
  opened : () -> String
  token : () -> String
  /// the push service that knows the token: "fcm", "apns", "apns-sandbox", "web" (the token a browser's subscription)
  service : () -> String
}

///|
pub fn host_notices() -> NoticeHost {
  {
    show: fn(tag, title, body, opens) {
      @ui.notice_show(channel=@sf.t("android-misc.notify.channel"), tag~, title~, body~, opens~)
    },
    cancel: fn(tag) { @ui.notice_cancel(tag) },
    permission: fn() { @ui.notice_permission() },
    ask: fn() { @ui.notice_ask() },
    answer: fn() { @ui.notice_answer() },
    opened: fn() { @ui.notice_opened() },
    token: fn() { @hostapi.push_token() },
    service: fn() { @hostapi.push_service() },
  }
}

///|
pub let notice_host : Ref[NoticeHost] = Ref(host_notices())

///|
pub(all) struct NoticeState {
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
  /// the push token last seen (a new one, or the first come after the start, registered: PushService.onNewToken)
  mut token : String
  /// the chat whose notification was taken off as it came on top ("" none on top)
  mut cancelled : String
  /// the source last seen, for the system's say between frames
  mut src : Source?
}

///|
pub let notice_state : NoticeState = {
  taken: {},
  following: "",
  told: false,
  asked_once: false,
  from_switch: false,
  synced: false,
  token: "",
  cancelled: "",
  src: None,
}

///|
fn notices_reset() -> Unit {
  notice_state.taken.clear()
  notice_state.following = ""
  notice_state.told = false
  notice_state.asked_once = false
  notice_state.from_switch = false
  notice_state.synced = false
  notice_state.token = ""
  notice_state.cancelled = ""
  notice_state.src = None
  notice_host.val = host_notices()
}


///|
/// The system asked to allow notifications as they are turned on in settings (rememberNotificationAsk, not once).
fn ask_from_switch() -> Unit {
  if (notice_host.val.ask)() {
    notice_state.from_switch = true
  }
}

///|
/// This device's push registration as the core wants it (Push.sync): taken off every account when its `notify`
/// says no pushes, else registered with the host's token (none where the build links no push service). `wanted`: what the core has just
/// answered, else what its `notify` says.
pub fn push_sync(src : Source, wanted : Bool?) -> Unit {
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
        token => {
          let registration : Map[String, Json]? = match (notice_host.val.service)() {
            "apns" => Some({ "kind": "apns", "token": Json::string(token), "sandbox": false })
            "apns-sandbox" => Some({ "kind": "apns", "token": Json::string(token), "sandbox": true })
            // a browser's: its push subscription as the page has it (`{endpoint, keys}`, web/src/mbui/core.ts)
            "web" =>
              match (try Some(@json.parse(token)) catch { _ => None }) {
                Some(Object(sub)) =>
                  match (sub.get("endpoint"), sub.get("keys")) {
                    (Some(String(_) as endpoint), Some(Object(_) as keys)) =>
                      Some({ "kind": "web", "endpoint": endpoint, "keys": keys })
                    _ => None
                  }
                _ => None
              }
            _ => Some({ "kind": "fcm", "token": Json::string(token) })
          }
          if registration is Some(r) {
            (src.call)("push.register", Json::object(r), fn(_) {  })
          }
        }
      }
    None => ()
  }
}

///|
fn notify_params(workspace : String) -> Map[String, Json] {
  { "workspace": Json::string(workspace) }
}

///|
/// Each frame, signed in, the workspace `w` in view.
pub fn notices_frame(src : Source, w : Workspace) -> Unit {
  if src.read_only {
    return
  }
  notice_state.src = Some(src)
  let h = notice_host.val
  let shown = @ui.app_visible()
  let notify = (src.topic)("notify", Map::new()).value
  match notify {
    Some(_) => {
      // what the system allows, as the app starts and each time it is shown again (MainActivity onStart)
      if shown && !notice_state.told {
        notice_state.told = true
        tell_permission(src, notify)
      }
      // asked once, the first time signed in with notifications on (App.kt rememberNotificationAsk(once))
      if !notice_state.asked_once && flag(notify, "on") && field(notify, "asked") is Some(False) {
        notice_state.asked_once = true
        (src.call)("notify.set", { "asked": Json::boolean(true) }, fn(_) {  })
        (h.ask)() |> ignore
      }
      // the registration for pushes, once at the start (MainActivity: Push.sync)
      if !notice_state.synced {
        notice_state.synced = true
        notice_state.token = (h.token)()
        push_sync(src, None)
      }
      // a token come since (the push service's first, given after the start, or a new one): registered as the core
      // says (PushService.onNewToken)
      let token = (h.token)()
      if token != "" && token != notice_state.token {
        notice_state.token = token
        push_sync(src, None)
      }
    }
    None => ()
  }
  // the system's answer to an ask
  match (h.answer)() {
    Some(granted) => {
      if !granted && notice_state.from_switch {
        toast_later(@sf.t("android-misc.notify.allowInSettings", args=[("app", "still.fail")]))
      }
      notice_state.from_switch = false
      (src.call)(
        "notify.permission",
        { "state": Json::string(if granted { "granted" } else { "denied" }) },
        fn(_) {  },
      )
    }
    None => ()
  }
  // the notices to show while the app goes on (Notices.kt showNotices)
  if @ui.app_awake() {
    follow_notices(src, w.id)
  } else {
    leave_notices(src)
  }
  // a notification tapped
  match (h.opened)() {
    "" => ()
    opens => open_notice(src, opens)
  }
  // a chat on top: its notification goes (App.kt LaunchedEffect(top))
  match app.nav.top() {
    Chat(r) => {
      let tag = r.station + "/" + r.session
      if notice_state.cancelled != tag {
        notice_state.cancelled = tag
        (h.cancel)(tag)
      }
    }
    _ => notice_state.cancelled = ""
  }
}

///|
/// The system said the app was hidden or shown again, between frames (Android's activity stopping: no frame comes
/// after it): hidden, what the system allows is told again once shown; behind for good (not going on: `awake`), the
/// notices are not followed any more.
fn notices_app_change(shown : Bool, awake : Bool) -> Unit {
  if shown {
    return
  }
  notice_state.told = false
  match notice_state.src {
    Some(src) if !awake => leave_notices(src)
    _ => ()
  }
}

///|
/// The core's `notify {workspace}`: each notice it says to show now taken (`notice.claim`), and shown when this page
/// is the one that took it.
fn follow_notices(src : Source, workspace : String) -> Unit {
  if notice_state.following != workspace {
    leave_notices(src)
    notice_state.following = workspace
  }
  let v = (src.topic)("notify", notify_params(workspace)).value
  for n in items(v, "show") {
    let id = text(Some(n), "id")
    if id == "" || notice_state.taken.contains(id) {
      continue
    }
    notice_state.taken[id] = true
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
  if notice_state.following != "" {
    (src.leave)("notify", notify_params(notice_state.following))
    notice_state.following = ""
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
/// A notification tapped (MainActivity.handle): its link opened as one from outside (links.mbt: the core's
/// `link.parse`), an item's chat over its workspace's Home at the message it is about; `settings:<page>` (the app's own
/// notifications: 共享调试's, AdbShare.java) that settings page over Home.
fn open_notice(src : Source, opens : String) -> Unit {
  if opens.has_prefix("settings:") {
    let name = opens.view(start_offset=9).to_owned()
    @hostapi.log("notice tapped settings:\{name}")
    match @settings.route_of(name) {
      Some(route) if app.nav.top() != Setting(route) => {
        (shell.val.close_overlays)()
        (shell.val.home)()
        if app.nav.top() != Home {
          app.nav.replace(Home)
        }
        open_page(Setting(route))
      }
      _ => ()
    }
    return
  }
  let (url, seq) = match opens.find("\n") {
    Some(i) => (opens.view(end_offset=i).to_owned(), opens.view(start_offset=i + 1).to_owned())
    None => (opens, "")
  }
  let at = match seq_of(seq) {
    n if n > 0.0 => Some(n)
    _ => None
  }
  @hostapi.log("notice tapped \{url} at \{seq}")
  open_link_in(src, trim_slash(cloud_origin()) + url, outside=true, at~, or_else=fn() {
    @hostapi.log("notice: the link opens nothing here: " + url)
  })
}

///|
/// A message's number as a notification carries it ("12"): 0 when there is none.
pub fn seq_of(s : String) -> Double {
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
pub fn trim_slash(o : String) -> String {
  if o.has_suffix("/") {
    o.view(end_offset=o.length() - 1).to_owned()
  } else {
    o
  }
}
