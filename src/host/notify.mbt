// The system's notifications, as still.fail's Android app shows them (ember apps/android app/Notices.kt, Push.kt;
// docs/notifications.md → Clients): one channel, one notification per tag (a newer one with the same tag replaces the
// older), tapped it brings the app to the front with what it was shown with (`opens`); whether the system lets the
// app show them, asking it to; and a push service's token and what it delivered. (A link the system opens the app with
// comes on the system's channel: system.mbt.)
//
// Android: NotificationManager (dev.mbui.Notices: the channel made as a notification is shown, POST_NOTIFICATIONS
// asked for from the activity, a tap a PendingIntent back to MainActivity). A push service is the app's own (its Java
// linking Firebase Cloud Messaging hands dev.mbui.Notices the token and each push delivered: still.fail's Push.java):
// `push_token` and `push_next` give what it handed, none where the app links none. macOS: UNUserNotificationCenter (mac_app.m) when the app is a bundle (its .app); a bare
// executable has no bundle for it, and keeps what would be shown, said on the log (`NOTICE …`), as iOS, Windows and the
// page do (no way in there yet). A scripted run taps one by its words everywhere (@host.drive 6, src/ui/drive.mbt
// `notice`), as on Android.

///|
/// Shows a notification in the app's `channel` (its name as the system's settings list it), replacing any with the
/// same `tag`; tapped, `notice_opened` gives `opens` back once.
pub fn notice_show(
  channel~ : String,
  tag~ : String,
  title~ : String,
  body~ : String,
  opens~ : String,
) -> Unit {
  nt_show(channel, tag, title, body, opens)
}

///|
/// The notification of `tag` taken off, if it shows.
pub fn notice_cancel(tag : String) -> Unit {
  nt_cancel(tag)
}

///|
/// What the system lets the app show: "granted", "denied", "ask" (not shown, and the system may never have been asked:
/// Android 13 on, where the app knows whether it asked), or "unknown" (this host cannot tell).
pub fn notice_permission() -> String {
  match nt_state(0) {
    1 => "granted"
    2 => "denied"
    3 => "ask"
    _ => "unknown"
  }
}

///|
/// Asks the system to let the app show notifications (Android's POST_NOTIFICATIONS dialog): false when nothing was
/// asked (allowed already, or no way to ask here). Its answer comes in `notice_answer`.
pub fn notice_ask() -> Bool {
  nt_state(1) != 0
}

///|
/// The system's answer to the last `notice_ask`, once: Some(true) allowed, Some(false) refused, None not yet (or none
/// asked).
pub fn notice_answer() -> Bool? {
  match nt_state(2) {
    1 => Some(true)
    0 => Some(false)
    _ => None
  }
}

///|
/// The `opens` of a notification tapped since the last look, once ("" none). A frame is asked for as one comes.
pub fn notice_opened() -> String {
  nt_text(0)
}

///|
/// This device's push token for the app ("" none: no push service in this build).
pub fn push_token() -> String {
  nt_text(1)
}

///|
/// A push delivered while the app runs, once: its data as JSON (an object of strings), "" none.
pub fn push_next() -> String {
  nt_text(2)
}
