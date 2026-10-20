// The system's notifications, through the framework (as @host's notify.mbt has them), so that a test's fake host keeps
// what the app shows (Tester::notices) and taps one (Tester::tap_notice) as the system would.

///|
/// A notification the app had shown: its channel, its tag (shown again by it: the same one, replaced), its title and
/// words, what it opens when tapped.
pub(all) struct Notice {
  channel : String
  tag : String
  title : String
  body : String
  opens : String
} derive(Eq, Debug)

///|
/// Shows a notification (@host.notice_show): one of the same tag is replaced.
pub fn notice_show(channel~ : String, tag~ : String, title~ : String, body~ : String, opens~ : String) -> Unit {
  match fake.val {
    Some(f) => {
      let kept = f.notices.filter(fn(n) { tag == "" || n.tag != tag })
      f.notices.clear()
      f.notices.append(kept)
      f.notices.push({ channel, tag, title, body, opens })
    }
    None => @host.notice_show(channel~, tag~, title~, body~, opens~)
  }
}

///|
/// Takes back the notification of `tag` (@host.notice_cancel).
pub fn notice_cancel(tag : String) -> Unit {
  match fake.val {
    Some(f) => {
      let kept = f.notices.filter(fn(n) { n.tag != tag })
      f.notices.clear()
      f.notices.append(kept)
    }
    None => @host.notice_cancel(tag)
  }
}

///|
/// What the notification tapped opens, once ("" none since the last ask: @host.notice_opened).
pub fn notice_opened() -> String {
  match fake.val {
    Some(f) => {
      let o = f.notice_opened
      f.notice_opened = ""
      o
    }
    None => @host.notice_opened()
  }
}

///|
/// What the system lets the app show (@host.notice_permission): "granted", "denied", "ask", "unknown". A Tester's
/// host lets it unless the test says otherwise (Tester::set_notice_permission).
pub fn notice_permission() -> String {
  match fake.val {
    Some(f) => f.notice_perm
    None => @host.notice_permission()
  }
}

///|
/// Asks the system to let the app show notifications (@host.notice_ask): false when nothing was asked (allowed
/// already, or a host that cannot tell has no way to ask: "unknown", as macOS, Windows and the web say). Under a
/// Tester the person answers as the test said (Tester::set_notice_reply), from the next frame.
pub fn notice_ask() -> Bool {
  match fake.val {
    Some(f) => {
      if f.notice_perm == "granted" || f.notice_perm == "unknown" {
        return false
      }
      f.notice_asks += 1
      f.notice_due = match f.notice_reply {
        Some(yes) => Some((yes, g().frame_no))
        None => None
      }
      f.wants = true
      true
    }
    None => @host.notice_ask()
  }
}

///|
/// The system's answer to the last `notice_ask`, once (@host.notice_answer): Some(true) allowed, Some(false) refused,
/// None not yet.
pub fn notice_answer() -> Bool? {
  match fake.val {
    Some(f) =>
      match f.notice_due {
        Some((yes, asked)) if g().frame_no > asked => {
          f.notice_due = None
          f.notice_perm = if yes { "granted" } else { "denied" }
          Some(yes)
        }
        _ => None
      }
    None => @host.notice_answer()
  }
}

///|
/// What the system lets the app show from the next frame on: "granted", "denied", "ask" (not asked yet), "unknown".
pub fn Tester::set_notice_permission(self : Tester, state : String) -> Unit {
  self.fake.notice_perm = state
  self.fake.wants = true
}

///|
/// What the person answers when the app asks to show notifications: Some(true) allows, Some(false) refuses, None never
/// answers (the dialog left open).
pub fn Tester::set_notice_reply(self : Tester, reply : Bool?) -> Unit {
  self.fake.notice_reply = reply
}

///|
/// How often the app asked to show notifications (notice_ask).
pub fn Tester::notice_asks(self : Tester) -> Int {
  self.fake.notice_asks
}
