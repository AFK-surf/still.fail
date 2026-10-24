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
//   token, `push.unregister` while off), a token come later registered then. A push delivered is the app's push
//   service's (android/…/Push.java, as PushService: it asks the core whether to show it, `notice.pushed`, then brings
//   what it is about, `notice.bring`), since the app's frames stop while it is behind.
//
// Nothing of it with Source.read_only (a run on a real account changes nothing in it).

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
        app.toast = fill("android-misc.notify.allowInSettings", [("app", "still.fail")])
        app.toast_n += 1
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
  // the notices to show while the app is shown (Notices.kt showNotices)
  if shown {
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
/// after it): hidden, the notices are not followed any more, and what the system allows is told again once shown.
fn notices_app_change(shown : Bool) -> Unit {
  if shown {
    return
  }
  notice_state.told = false
  match notice_state.src {
    Some(src) => leave_notices(src)
    None => ()
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
/// `link.parse`), an item's chat over its workspace's Home at the message it is about.
fn open_notice(src : Source, opens : String) -> Unit {
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
