// What of notifications both frames' settings ask (src/sfapp notices.mbt has the rest, as the app shows them): the
// system asked through (the host's, or a test's), how it stands, the system asked as they are turned on in settings,
// and this device's push registration as the core wants it.

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
