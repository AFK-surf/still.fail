// What changes the height of a chat's list waits for nothing (mbui's view/list_motion.mbt, ListRows): a row comes into
// the list, or what is under a post shows or goes, the moment it does, together with whatever else changes, each
// one's room going to its new height from then. What is kept here is when each did (`started`: what plays for it
// starts from there, whichever frame sees it), and one thing still taken in turn: messages coming out of agents'
// avatars (emit.mbt) ask for their turn (Turns::emits), which starts as the next step of the chat's list sees it
// asked (Turns::step, before the page is built) and lasts till they say none is left (Turns::over). Words sent tell
// it as they set out and as they land (flight.mbt): what moves of them is theirs; here they only set out the chat's
// list's turns (their mover) from that moment.

///|
/// What says it is over (Turns::over): words sent, landed; messages out of avatars, none left.
#derive(Eq, Debug)
pub(all) enum TurnFor {
  Send
  Emits
}

///|
pub(all) struct Turns {
  /// messages out of avatars asking for their turn, not started yet: when they asked (Turns::emits); at most one
  mut asked : Double?
  /// messages out of avatars have their turn now: from the step that started it till they say none is left
  mut open : Bool
  /// what is under a post as shown (Turns::in_turn), by key
  shown : Map[String, Bool]
  /// when each row came in or each change was made, by key, and messages out of avatars' turn's start (emits_turn):
  /// what plays in it starts from there
  started : Map[String, Double]
  /// when words were last sent (-1: none): their landing said over sets the turns out again (Turns::over)
  mut sent_at : Double
  /// the moment they were last played on at (Turns::step): their chat's page shown then; the time handed to what
  /// moves (Moving::sample)
  mut stepped_at : Double
  mut now : Double
  mover : @ui.Mover
}

///|
pub let turns_by : Map[String, Turns] = Map([])

///|
/// Chat `key`'s turns (its station and session, as emits_of's).
pub fn turns_of(key : String) -> Turns {
  match turns_by.get(key) {
    Some(t) => t
    None => {
      let t = {
        asked: None,
        open: false,
        shown: {},
        started: {},
        sent_at: -1.0,
        stepped_at: @double.neg_infinity,
        now: 0.0,
        mover: @ui.Mover::new(),
      }
      turns_by[key] = t
      t
    }
  }
}

///|
/// The key messages out of avatars' turn's start is kept by (Turns::started_at).
pub let emits_turn : String = "\u{1}emits"

///|
/// How close to a frame's time a turn's start counts as in it (sums of declared lengths in ms round off).
let turn_slack_ms : Double = 0.001

///|
/// How far on a frame is owed to a turn whose time came after the frame's step (Moving::rest_at): the next one.
let turn_owed_ms : Double = 1.0

///|
/// The moment now, as what is said to move sets out (Ctx::set_out): they are said to move from it.
pub fn Turns::moment(self : Turns, c : @ui.Ctx) -> Double {
  c.set_out(self.mover, self as &@ui.Moving, what="a chat's list turns")
}

///|
/// The row `key` comes into the list: in it at once, its room opening from now (the list's rows' heights,
/// Ctx::row_size). Said again while it is in the list, it keeps the moment it first came.
pub fn Turns::admit(self : Turns, c : @ui.Ctx, key : String) -> Unit {
  if !self.started.contains(key) {
    self.started[key] = self.moment(c)
  }
}

///|
/// Words sent: on their way at once, whatever plays (flight.mbt); the turns set out from now.
pub fn Turns::send(self : Turns, c : @ui.Ctx) -> Unit {
  self.sent_at = self.moment(c)
}

///|
/// Messages out of avatars: one turn from the first setting out till none is left (Turns::over). Asked now, unless
/// one is under way or asked already; it starts at the next step (Turns::step).
pub fn Turns::emits(self : Turns, c : @ui.Ctx) -> Unit {
  if self.emitting() || self.asked is Some(_) {
    return
  }
  self.asked = Some(self.moment(c))
}

///|
/// Whether messages out of avatars have their turn now.
pub fn Turns::emitting(self : Turns) -> Bool {
  self.open
}

///|
/// `target` (something under a post shown or not: a decision's options, 忽略, a card asking) as it shows: as it is
/// now, on screen or not, nothing waiting. The first time it is asked, as it is, no change; changed since, from now
/// (`started`: its room goes to its new height from then, with whatever else changes).
pub fn Turns::in_turn(self : Turns, c : @ui.Ctx, key : String, target : Bool) -> Bool {
  match self.shown.get(key) {
    None => {
      self.shown[key] = target
      target
    }
    Some(shown) => {
      if shown != target {
        self.shown[key] = target
        self.started[key] = self.moment(c)
      }
      target
    }
  }
}

///|
/// When what is under a post `key` last changed, or row `key` came in (-1: never).
pub fn Turns::started_at(self : Turns, key : String) -> Double {
  self.started.get(key).unwrap_or(-1.0)
}

///|
/// When what is under a post `key` last changed, what plays for it from then; None: it has not changed since it was
/// first asked.
pub fn Turns::start(self : Turns, key : String) -> Double? {
  self.started.get(key)
}

///|
/// Words sent landed (`what` Send: the turns set out again from now, if words were sent here), or messages out of
/// avatars have none left (Emits: their turn under way over, or the one asked and not started yet gone).
pub fn Turns::over(self : Turns, c : @ui.Ctx, what : TurnFor) -> Unit {
  if what == Send {
    if self.sent_at >= 0.0 {
      c.moving(self.mover, self as &@ui.Moving, what="a chat's list turns")
    }
    return
  }
  if self.open {
    self.open = false
    c.moving(self.mover, self as &@ui.Moving, what="a chat's list turns")
  }
  self.asked = None
}

///|
/// Plays the turns on, before the page is built (chat_tick): messages out of avatars' turn, asked by now (to a
/// rounding: moments added up in ms can land a hair past the frame they are due in), starts, from when it was asked.
pub fn Turns::step(self : Turns, c : @ui.Ctx) -> Unit {
  self.stepped_at = c.moment()
  match self.asked {
    Some(at) if at <= self.now + turn_slack_ms => {
      self.asked = None
      self.open = true
      self.started[emits_turn] = dmin(at, self.now)
    }
    _ => ()
  }
}

///|
/// The time the turns are played on at (Turns::step).
impl @ui.Moving for Turns with sample(self, now) {
  self.now = now
}

///|
/// The turns are played on from the time they keep, as the page is built.
impl @ui.Moving for Turns with keeps_time(self) {
  ignore(self)
  true
}

///|
/// A frame while messages out of avatars ask for their turn (at the moment they asked, or the next frame where that was
/// this frame's, after its step); none otherwise.
impl @ui.Moving for Turns with rest_at(self, now, frame) {
  ignore(frame)
  // (not played on at this moment, their chat's page not shown: nothing plays; shown again, its build plays them on)
  if self.stepped_at < now {
    return -1.0
  }
  match self.asked {
    Some(at) => if at <= now + turn_slack_ms { now + turn_owed_ms } else { at }
    None => -1.0
  }
}
