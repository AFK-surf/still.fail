// What changes the height of a chat's list plays one at a time (ListTurns.kt, web/src/listQueue.ts, docs/list-motion.md):
// words sent flying in from the composer, a message simply coming in, the agent's line coming, messages coming out of
// its avatar, what comes under a post (what is answered there goes only out of sight: Turns::in_turn). Each waits its
// turn here, in the order they came, but words sent: they fly at once, in the list the frame they are sent
// (flight.mbt), and what is asked after them waits till they have landed (the list does not follow its end while they
// fly: a row come in then would move it at once; an answer out of its avatar under way as they were sent waits for
// them too: emit_step). A turn is over once
// its own motion is and the list is where it moved it to (its glide after what came over: Ctx::list_info's
// `glide_rest`; the reader's hand on it, a finger holding it, a fling, holds nothing back). What only fades, turns or
// changes its words is not in it. A row waiting its turn is not in the list yet: its room comes when its turn does.
//
// Motion as data: each turn's start is declared (where the one before was declared to end, or the list's rest, or when
// it was asked, whichever is last) and what plays in it starts from there (`started`), whichever frame sees it; a turn
// of a known length ends at its start and that, one that lasts till something is over (messages out of avatars, till
// none is left) when that says it is (Turns::over), as words sent say they have landed.

///|
/// What a turn is for: a row coming in (by its key), something under a post shown or not (by its key), words sent,
/// messages coming out of avatars, the row of what the viewer just did here, not made yet (Turns::keep_turn).
pub(all) enum TurnFor {
  Admit(String)
  Change(String)
  Send
  Emits
  Kept
} derive(Eq, Show)

///|
/// A turn asked for: what for, how long its motion takes (inf: till said over), and whether it goes after the others
/// asked with it (an agent's line, after what closes under a post as it starts: Chat.kt `after`).
pub(all) struct TurnAsk {
  what : TurnFor
  ms : Double
  after : Bool
  /// when it was asked (the frames' clock), and the how-manieth (in order)
  at : Double
  n : Int
}

///|
pub(all) struct Turns {
  asks : Array[TurnAsk]
  /// the turn under way and until when (its start and its motion's length; one lasting till said over, till then at
  /// most turn_most_ms: `open`); -1: none since
  mut on : TurnFor?
  mut until : Double
  mut open : Bool
  mut asked_n : Int
  /// rows waiting their turn, by key: kept out of the list till then
  waiting : Map[String, Bool]
  /// what is under a post as shown (Turns::in_turn), by key, and what it is to become in its turn
  shown : Map[String, Bool]
  wants : Map[String, Bool]
  /// when each row came in or each change was made, by key (what plays in it starts from there)
  started : Map[String, Double]
  /// words last sent: when (-1: none), and till when what is asked after them waits (their landing, as they say it:
  /// Turns::over; till then the most their way can take: their wait for their row and their flight)
  mut sent_at : Double
  mut sent_until : Double
  /// the list's glide after what came, as last seen: over from then (inf: under way, its end not known yet)
  mut list_rest : Double
  /// the frame they were last played on in (Turns::step): their chat's page shown then; that frame's time, as handed
  /// to what moves (Moving::sample)
  mut stepped : Int
  mut now : Double
  mover : @ui.Mover
}

///|
pub let turns_by : Map[String, Turns] = {}

///|
/// Chat `key`'s turns (its station and session, as emits_of's).
pub fn turns_of(key : String) -> Turns {
  match turns_by.get(key) {
    Some(t) => t
    None => {
      let t = {
        asks: [],
        on: None,
        until: -1.0,
        open: false,
        asked_n: 0,
        waiting: {},
        shown: {},
        wants: {},
        started: {},
        sent_at: -1.0,
        sent_until: -1.0,
        list_rest: -1.0,
        stepped: -1,
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
/// How long after its motion a turn holds the next (ListTurns.kt: the list looked at from two frames on, still in
/// both, at 60 frames a second), and how much later than the others asked with it one going after them is asked.
pub let turn_calm_ms : Double = 2.0 * 1000.0 / 60.0

///|
/// The most a turn holds the next one back, whatever it does (one whose motion never ends: ListTurns.kt MOST_MS).
pub let turn_most_ms : Double = 3000.0

///|
pub fn Turns::ask(self : Turns, c : @ui.Ctx, what : TurnFor, ms : Double, after? : Bool = false) -> Unit {
  self.asked_n = self.asked_n + 1
  // (said once as it is asked, from the moment it is: frames until its turn is played, Moving below)
  let at = self.moment(c)
  // (one going after the others asked with it asked a couple of frames on: ListTurns.kt take's `after`)
  self.asks.push({ what, ms, after, at: if after { at + turn_calm_ms } else { at }, n: self.asked_n })
}

///|
/// The moment now, as what is said to move sets out (Ctx::set_out): they are said to move from it.
pub fn Turns::moment(self : Turns, c : @ui.Ctx) -> Double {
  c.set_out(self.mover, self as &@ui.Moving, what="a chat's list turns")
}

///|
/// The row `key` comes into the list in its turn, its own motion taking `ms` (`after`: see TurnAsk).
pub fn Turns::admit(self : Turns, c : @ui.Ctx, key : String, ms : Double, after? : Bool = false) -> Unit {
  ignore(ms)
  ignore(after)
  // (in the list at once, its room opening from now: the list's rows' heights, Ctx::row_size)
  if !self.started.contains(key) || self.waiting.contains(key) {
    self.waiting.remove(key) |> ignore
    self.started[key] = self.moment(c)
  }
}

///|
/// Words sent: on their way at once, whatever plays; what is asked after them waits for them to land (Turns::over).
pub fn Turns::send(self : Turns, c : @ui.Ctx, way_ms : Double) -> Unit {
  self.sent_at = self.moment(c)
  self.sent_until = self.sent_at + way_ms + turn_calm_ms
}

///|
/// Messages out of avatars: one turn from the first setting out till none is left (Turns::over).
pub fn Turns::emits(self : Turns, c : @ui.Ctx) -> Unit {
  // (one under way, or asked: none more; one over, a new one for what came since)
  if self.emitting() || self.asks.iter().any(fn(a) { a.what == Emits }) {
    return
  }
  self.ask(c, Emits, @double.infinity)
}

///|
/// Whether messages out of avatars have their turn now.
pub fn Turns::emitting(self : Turns) -> Bool {
  self.on == Some(Emits) && self.open
}

///|
/// `target` (something under a post shown or not: a decision's options, 忽略, a card asking) as it shows. What changes
/// out of sight (`seen` false: its row not on screen the frame before, Reading::sees) changes at once, its motion over
/// before it is seen (`started` long ago: unseen_at). On screen, what comes waits its turn among what changes the
/// list's height and holds the next for `ms` (its motion) once made; what goes does not go: it stays as it is, its
/// room with it, until it is out of sight (the user, 2026-10-29: what is answered on screen moves nothing, the list
/// changing only for what comes). The first time it is asked, as it is.
pub fn Turns::in_turn(self : Turns, c : @ui.Ctx, key : String, target : Bool, ms : Double, seen~ : Bool) -> Bool {
  ignore(ms)
  ignore(seen)
  match self.shown.get(key) {
    None => {
      self.shown[key] = target
      target
    }
    Some(shown) => {
      self.wants[key] = target
      if shown != target {
        // (changed now, on screen or not: its room goes to its new height from now, with whatever else changes)
        self.shown[key] = target
        self.started[key] = self.moment(c)
      }
      target
    }
  }
}

///|
/// When what changed out of sight is said to have changed (Turns::in_turn): long before any frame, its motion over.
pub let unseen_at : Double = -1.0e9

///|
/// The row of what the viewer just did here (a card's option picked: their answer, in the outbox) takes its turn as
/// they do it, before what comes of it (the agent's line taking it up): the next row asked comes in it
/// (web/src/listQueue.ts reserveRow), the options staying as they are, none pressed. No row by
/// turn_most_ms (an option that closes the card without one), the turn goes.
pub fn Turns::keep_turn(self : Turns, c : @ui.Ctx) -> Unit {
  ignore(self)
  ignore(c)
}

///|
/// When what is under a post `key` last changed in its turn, or a row came in (-1: not in one).
pub fn Turns::started_at(self : Turns, key : String) -> Double {
  self.started.get(key).unwrap_or(-1.0)
}

///|
/// When what is under a post `key` last changed (in its turn, or out of sight: unseen_at), what plays for it from
/// then; None: it has not changed since it was first asked.
pub fn Turns::start(self : Turns, key : String) -> Double? {
  self.started.get(key)
}

///|
/// The turn under way, of words sent or messages out of avatars, is over (`at`: when it was declared to end).
pub fn Turns::over(self : Turns, c : @ui.Ctx, what : TurnFor, at : Double) -> Unit {
  // (words sent landed: what waits for them goes from here)
  if what == Send && self.sent_at >= 0.0 {
    self.sent_until = dmin(self.sent_until, at + turn_calm_ms)
    c.moving(self.mover, self as &@ui.Moving, what="a chat's list turns")
    return
  }
  if self.on == Some(what) && self.open {
    self.open = false
    self.until = dmin(self.until, at + turn_calm_ms)
    c.moving(self.mover, self as &@ui.Moving, what="a chat's list turns")
  }
  // (one asked and not come yet, over before it came: it goes)
  match self.asks.search_by(fn(a) { a.what == what }) {
    Some(i) if what == Emits => self.asks.remove(i) |> ignore
    _ => ()
  }
}

///|
/// The next ask in order: the first asked, those going after the others asked with them last.
pub fn Turns::next_ask(self : Turns) -> Int? {
  let mut best = -1
  for i, a in self.asks {
    if best < 0 {
      best = i
    } else {
      let b = self.asks[best]
      let sooner = if a.at != b.at { a.at < b.at } else if a.after != b.after { !a.after } else { a.n < b.n }
      if sooner {
        best = i
      }
    }
  }
  if best < 0 {
    None
  } else {
    Some(best)
  }
}

///|
/// When the next turn may start (inf: not known yet): the one under way over (at most turn_most_ms after it began), the
/// list at rest, and it asked.
pub fn Turns::free_at(self : Turns, a : TurnAsk) -> Double {
  // (nothing waits for another: docs/list-motion.md)
  a.at
}

///|
/// What ask `a` waits for of words sent: their landing, asked after they were sent (-1: nothing).
pub fn Turns::after_sent(self : Turns, a : TurnAsk) -> Double {
  if self.sent_at >= 0.0 && a.at >= self.sent_at {
    self.sent_until
  } else {
    -1.0
  }
}

///|
/// Plays the turns on, before the page is built (chat_tick): each one whose turn has come starts, from when it came.
/// `list_rest`: when the list's glide after what came is over (Ctx::list_info's `glide_rest`; inf: under way, its end
/// not known), not the reader's hand on it (listQueue.ts listStill).
pub fn Turns::step(self : Turns, c : @ui.Ctx, list_rest : Double) -> Unit {
  self.list_rest = list_rest
  self.stepped = c.frame_number()
  let mut steps = 0
  while steps < 16 {
    steps = steps + 1
    let i = match self.next_ask() {
      Some(i) => i
      None => return
    }
    let a = self.asks[i]
    let at = self.free_at(a)
    // (its time come, to a rounding: the ends added up in ms can land a hair past the frame they are due in)
    if at > self.now + turn_slack_ms {
      return
    }
    let at = dmin(at, self.now)
    self.asks.remove(i) |> ignore
    self.on = Some(a.what)
    self.open = a.ms == @double.infinity
    self.until = at + (if self.open { turn_most_ms } else { a.ms }) + turn_calm_ms
    match a.what {
      Admit(k) => {
        self.waiting.remove(k) |> ignore
        self.started[k] = at
        // (the list goes after it as this frame lays it out: where and till when, not known before then)
        self.list_rest = @double.infinity
      }
      Change(k) => {
        self.shown[k] = self.wants.get(k).unwrap_or(!self.shown.get(k).unwrap_or(false))
        self.started[k] = at
      }
      Send | Kept => ()
      Emits => self.started[emits_turn] = at
    }
  }
}

///|
/// Frames while a turn waits to come (its start known: the one before declared to end, the list at rest), none once
/// all have come; one under way that lasts till said over is said by what it waits on (its own motion).
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
impl @ui.Moving for Turns with rest_at(self, now, frame) {
  // (their chat's page not shown this frame: nothing plays; shown again, its build plays them on)
  if self.stepped < frame {
    return -1.0
  }
  match self.next_ask() {
    // (its time come and not started yet: asked, or the one before said over, as the view built, after this frame's
    // step; the next frame, a moment on, starts it from when it came)
    Some(i) => {
      let at = self.free_at(self.asks[i])
      if at <= now + turn_slack_ms {
        now + turn_owed_ms
      } else {
        at
      }
    }
    None => -1.0
  }
}

///|
/// How long a turn holds the next: a row coming in (its rise: Chat.kt admit, 320), an agent's line (its room opening,
/// 220), a decision's options closing (their leave and the delayed close: ListMotion.kt CLOSE_TURN_MS), 忽略 going
/// (Chat.kt AskDismiss, 280).
pub let row_turn_ms : Double = 320.0

///|
pub let working_turn_ms : Double = 220.0

///|
pub let close_turn_ms : Double = 520.0

///|
pub let dismiss_turn_ms : Double = 280.0

///|
/// When what is under a post `key` changes, or row `key` comes in: when it did, or, still to come, when its turn is
/// declared to start (the turns before it in order each from where the one before them ends, the list at rest); inf
/// while that is not known (a turn before it lasts till said over, the list's glide not set out).
pub fn Turns::start_of(self : Turns, key : String) -> Double {
  let order = self.asks.copy()
  order.sort_by(fn(a, b) {
    if a.at != b.at {
      a.at.compare(b.at)
    } else if a.after != b.after {
      if a.after { 1 } else { -1 }
    } else {
      a.n.compare(b.n)
    }
  })
  let mut end = if self.open { @double.infinity } else { self.until }
  for a in order {
    ignore(end)
    let start = a.at
    if a.what == Admit(key) || a.what == Change(key) {
      return start
    }
    end = start + a.ms
  }
  self.started_at(key)
}

///|
/// When what is under a post whose key starts with `prefix` ("ask/": a card's options closing, "dismiss/": 忽略
/// going) changes in its turn: the one waiting for its turn (its declared start: Turns::start_of), else the last that
/// changed; -1 none. For a test that says the moment its motion starts from.
pub fn under_turn(prefix : String) -> Double {
  let mut waiting = -1.0
  let mut last = -1.0
  for _, tu in turns_by {
    for a in tu.asks {
      match a.what {
        Change(k) if k.has_prefix(prefix) => waiting = dmax(waiting, tu.start_of(k))
        _ => ()
      }
    }
    for k, at in tu.started {
      if k.has_prefix(prefix) {
        last = dmax(last, at)
      }
    }
  }
  if waiting >= 0.0 {
    waiting
  } else {
    last
  }
}

