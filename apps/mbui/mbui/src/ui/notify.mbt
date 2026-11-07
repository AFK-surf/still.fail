// The system's notifications, through the framework (as @hostapi's notify.mbt has them), so that a test's fake host keeps
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
/// Shows a notification (@hostapi.notice_show): one of the same tag is replaced.
pub fn notice_show(channel~ : String, tag~ : String, title~ : String, body~ : String, opens~ : String) -> Unit {
  match fake.val {
    Some(f) => {
      let kept = f.notices.filter(fn(n) { tag == "" || n.tag != tag })
      f.notices.clear()
      f.notices.append(kept)
      f.notices.push({ channel, tag, title, body, opens })
    }
    None => @hostapi.notice_show(channel~, tag~, title~, body~, opens~)
  }
}

///|
/// Takes back the notification of `tag` (@hostapi.notice_cancel).
pub fn notice_cancel(tag : String) -> Unit {
  match fake.val {
    Some(f) => {
      let kept = f.notices.filter(fn(n) { n.tag != tag })
      f.notices.clear()
      f.notices.append(kept)
    }
    None => @hostapi.notice_cancel(tag)
  }
}

///|
/// What the system said of its notifications since a frame last read it (notices_arrive), each a signal with how
/// many have come: the notification tapped (what it opens), the answer to the last ask. What reads them (the app's
/// poll, told once its frame is built: Ctx::after_build) is built again in the frame they come in, whether or not
/// anything else of it is: the host keeps them and only asks for a frame, telling nothing of what changed.
priv struct NoticesSaid {
  opened : @signals.Signal[(Int, String)]
  answer : @signals.Signal[(Int, Bool)]
  mut opened_taken : Int
  mut answer_taken : Int
}

///|
// kept across runs: put back by each Tester (notices_reset)
let notices_said : NoticesSaid = {
  opened: @signals.signal((0, "")),
  answer: @signals.signal((0, false)),
  opened_taken: 0,
  answer_taken: 0,
}

///|
/// As at the start: nothing said, nothing taken.
fn notices_reset() -> Unit {
  notices_said.opened.set((0, ""))
  notices_said.answer.set((0, false))
  notices_said.opened_taken = 0
  notices_said.answer_taken = 0
}

///|
/// What the system said of its notifications since the last frame, read of it as a frame begins (frame_drawn, as the
/// streams and the native views are: `frame_begins`) or as the app asks between frames: each its signal set, once.
fn notices_arrive(frame_begins? : Bool = false) -> Unit {
  let opened = match fake.val {
    Some(f) => {
      let o = f.notice_opened
      f.notice_opened = ""
      o
    }
    None => @hostapi.notice_opened()
  }
  if opened != "" {
    let (n, _) = @signals.untracked(fn() { notices_said.opened.get() })
    notices_said.opened.set((n + 1, opened))
  }
  let answer = match fake.val {
    Some(f) =>
      match f.notice_due {
        // (a Tester's person answers as the frame after the ask begins: never before it, between frames)
        Some((yes, _)) if frame_begins => {
          f.notice_due = None
          f.notice_perm = if yes { "granted" } else { "denied" }
          Some(yes)
        }
        _ => None
      }
    None => @hostapi.notice_answer()
  }
  match answer {
    Some(yes) => {
      let (n, _) = @signals.untracked(fn() { notices_said.answer.get() })
      notices_said.answer.set((n + 1, yes))
    }
    None => ()
  }
}

///|
/// What the notification tapped opens, once ("" none since the last ask: @hostapi.notice_opened): read as a signal,
/// what reads it built again as one is tapped.
pub fn notice_opened() -> String {
  if !frame_running.val {
    notices_arrive()
  }
  let (n, opens) = notices_said.opened.get()
  if n > notices_said.opened_taken {
    notices_said.opened_taken = n
    opens
  } else {
    ""
  }
}

///|
/// What the system lets the app show (@hostapi.notice_permission): "granted", "denied", "ask", "unknown". A Tester's
/// host lets it unless the test says otherwise (Tester::set_notice_permission).
pub fn notice_permission() -> String {
  match fake.val {
    Some(f) => f.notice_perm
    None => @hostapi.notice_permission()
  }
}

///|
/// Asks the system to let the app show notifications (@hostapi.notice_ask): false when nothing was asked (allowed
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
    None => @hostapi.notice_ask()
  }
}

///|
/// The system's answer to the last `notice_ask`, once (@hostapi.notice_answer): Some(true) allowed, Some(false) refused,
/// None not yet. Read as a signal: what reads it built again as the answer comes.
pub fn notice_answer() -> Bool? {
  if !frame_running.val {
    notices_arrive()
  }
  let (n, yes) = notices_said.answer.get()
  if n > notices_said.answer_taken {
    notices_said.answer_taken = n
    Some(yes)
  } else {
    None
  }
}

///|
/// Opens the system's settings of the app's notifications, where they are allowed or turned off
/// (@hostapi.notice_settings): false where it has none to open. Under a Tester counted (Tester::notice_settings_opened).
pub fn notice_settings() -> Bool {
  match fake.val {
    Some(f) => {
      f.notice_settings += 1
      true
    }
    None => @hostapi.notice_settings()
  }
}

///|
/// Whether the system shows the number the app puts on its icon (@hostapi.badge_shown). Under a Tester, or a program
/// playing another system (set_platform), as that system does: macOS and iOS.
pub fn badge_shown() -> Bool {
  match fake.val {
    None if said_platform.val < 0 => @hostapi.badge_shown()
    _ => {
      let p = platform()
      p == 0 || p == 1
    }
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

///|
/// How often the app opened the system's settings of its notifications (notice_settings).
pub fn Tester::notice_settings_opened(self : Tester) -> Int {
  self.fake.notice_settings
}
