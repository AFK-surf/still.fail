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
/// What the system lets the app show (@host.notice_permission): a test's host lets it.
pub fn notice_permission() -> String {
  match fake.val {
    Some(_) => "granted"
    None => @host.notice_permission()
  }
}
