// What is on show, by key (Ctx::lives): said by what builds it, said again with a kept row's or part's nodes as they
// are put back, so a part kept is on show as much as one built. Each key's showing is a signal (Ctx::on_show), set as
// the frame that first shows it or no longer does ends: never in a build, never each frame. What a thing does while it
// shows reads it, whoever built it (a page drawn as another's part, a pane, a page sliding out): one says, the frame,
// not a guess at it from elsewhere.

///|
/// The keys the pass being built says are on show, and each key's showing as the last frame ended.
// kept across runs: put back as a run begins (lives_forget), the first each frame
let lives_now : Map[String, Bool] = {}

///|
// kept across runs: put back as a run begins (lives_forget)
let lives_shown : Map[String, @signals.Signal[Bool]] = {}

///|
/// What is built here is on show, as `key` (a chat's page: its key): so said as long as it is built or kept.
pub fn Ctx::lives(self : Ctx, key : String) -> Unit {
  ignore(self)
  lives_now[key] = true
  // (the row or part being built, and those holding it: an island in an island said as shown with what holds it)
  let mut at = nodes_run.building
  while at is Some(rn) {
    rn.lives.push(key)
    at = rn.holder.val
  }
}

///|
/// Whether what is said as `key` is on show (Ctx::lives), as the last frame ended: a signal, what reads it told as
/// that changes.
pub fn on_show(key : String) -> Bool {
  lives_signal(key).get()
}

///|
fn lives_signal(key : String) -> @signals.Signal[Bool] {
  match lives_shown.get(key) {
    Some(s) => s
    None => {
      let s = @signals.signal(false, same=fn(a, b) { a == b })
      lives_shown[key] = s
      s
    }
  }
}

///|
/// A pass of a frame's build begins: what it says is on show, from nothing.
fn lives_pass_start() -> Unit {
  lives_now.clear()
}

///|
/// The frame is built: what shows now and did not, and what showed and does not, said so.
fn lives_frame_end() -> Unit {
  for key, s in lives_shown {
    let now = lives_now.contains(key)
    if @signals.untracked(fn() { s.get() }) != now {
      s.set(now)
    }
  }
  for key, _ in lives_now {
    if !lives_shown.contains(key) {
      lives_signal(key).set(true)
    }
  }
}

///|
/// As a run begins: nothing on show.
fn lives_forget() -> Unit {
  lives_now.clear()
  for _, s in lives_shown {
    s.set(false)
  }
  lives_shown.clear()
}
