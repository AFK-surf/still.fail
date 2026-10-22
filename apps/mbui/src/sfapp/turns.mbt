// What changes the height of a chat's list plays one at a time (ListTurns.kt, web/src/listQueue.ts, docs/list-motion.md):
// words sent flying in from the composer, a message simply coming in, the agent's line coming, messages coming out of
// its avatar, a decision's options closing, what goes from under a post. Each waits its turn here, in the order they
// came; a turn is over once its own motion is and the list is where it moved it to (the list's own motion, its glide
// after what came, at rest: Ctx::list_info's `rest`). What only fades, turns or changes its words is not in it. A row
// waiting its turn is not in the list yet: its room comes when its turn does.
//
// Motion as data: each turn's start is declared (where the one before was declared to end, or the list's rest, or when
// it was asked, whichever is last) and what plays in it starts from there (`started`), whichever frame sees it; a turn
// of a known length ends at its start and that, one that lasts till something is over (words sent, till they have
// landed; messages out of avatars, till none is left) when that says it is (Turns::over).

///|
/// What a turn is for: a row coming in (by its key), something under a post shown or not (by its key), words sent,
/// messages coming out of avatars.
priv enum TurnFor {
  Admit(String)
  Change(String)
  Send
  Emits
} derive(Eq)

///|
/// A turn asked for: what for, how long its motion takes (inf: till said over), and whether it goes after the others
/// asked with it (an agent's line, after what closes under a post as it starts: Chat.kt `after`).
priv struct TurnAsk {
  what : TurnFor
  ms : Double
  after : Bool
  /// when it was asked (the frames' clock), and the how-manieth (in order)
  at : Double
  n : Int
}

///|
priv struct Turns {
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
  /// words sent waiting their turn: their row kept out of the list, the words over the composer
  mut send_waiting : Bool
  /// the list's own motion, as last seen: at rest from then (inf: under way, its end not known yet)
  mut list_rest : Double
  /// the frame they were last played on in (Turns::step): their chat's page shown then; that frame's time, as handed
  /// to what moves (Moving::sample)
  mut stepped : Int
  mut now : Double
  mover : @ui.Mover
}

///|
let turns_by : Map[String, Turns] = {}

///|
/// Chat `key`'s turns (its station and session, as emits_of's).
fn turns_of(key : String) -> Turns {
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
        send_waiting: false,
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
let emits_turn : String = "\u{1}emits"

///|
/// How far on a frame is owed to a turn whose time came after the frame's step (Moving::rest_at): the next one.
let turn_owed_ms : Double = 1.0

///|
/// The most a turn holds the next one back, whatever it does (one whose motion never ends: ListTurns.kt MOST_MS).
let turn_most_ms : Double = 3000.0

///|
fn Turns::ask(self : Turns, c : @ui.Ctx, what : TurnFor, ms : Double, after? : Bool = false) -> Unit {
  self.asked_n = self.asked_n + 1
  // (said once as it is asked, from the moment it is: frames until its turn is played, Moving below)
  let at = self.moment(c)
  self.asks.push({ what, ms, after, at, n: self.asked_n })
}

///|
/// The moment now, as what is said to move sets out (Ctx::set_out): they are said to move from it.
fn Turns::moment(self : Turns, c : @ui.Ctx) -> Double {
  c.set_out(self.mover, self as &@ui.Moving, what="a chat's list turns")
}

///|
/// The row `key` comes into the list in its turn, its own motion taking `ms` (`after`: see TurnAsk).
fn Turns::admit(self : Turns, c : @ui.Ctx, key : String, ms : Double, after? : Bool = false) -> Unit {
  if self.waiting.contains(key) {
    return
  }
  self.waiting[key] = true
  self.ask(c, Admit(key), ms, after~)
}

///|
/// Words sent: their row comes in its turn, which lasts till they have landed (Turns::over).
fn Turns::send(self : Turns, c : @ui.Ctx) -> Unit {
  self.send_waiting = true
  self.ask(c, Send, @double.infinity)
}

///|
/// Messages out of avatars: one turn from the first setting out till none is left (Turns::over).
fn Turns::emits(self : Turns, c : @ui.Ctx) -> Unit {
  // (one under way, or asked: none more; one over, a new one for what came since)
  if self.emitting() || self.asks.iter().any(fn(a) { a.what == Emits }) {
    return
  }
  self.ask(c, Emits, @double.infinity)
}

///|
/// Whether messages out of avatars have their turn now.
fn Turns::emitting(self : Turns) -> Bool {
  self.on == Some(Emits) && self.open
}

///|
/// `target` (something under a post shown or not: a decision's options, 忽略) as it shows, changed in its turn among
/// what changes the list's height: the change waits for it, and holds the next for `ms` (its motion) once made. The
/// first time it is asked, as it is.
fn Turns::in_turn(self : Turns, c : @ui.Ctx, key : String, target : Bool, ms : Double) -> Bool {
  match self.shown.get(key) {
    None => {
      self.shown[key] = target
      target
    }
    Some(shown) => {
      let asked = self.asks.iter().any(fn(a) { a.what == Change(key) })
      if shown != target && !asked {
        self.ask(c, Change(key), ms)
      }
      self.wants[key] = target
      shown
    }
  }
}

///|
/// When what is under a post `key` last changed in its turn, or a row came in (-1: not in one).
fn Turns::started_at(self : Turns, key : String) -> Double {
  self.started.get(key).unwrap_or(-1.0)
}

///|
/// The turn under way, of words sent or messages out of avatars, is over (`at`: when it was declared to end).
fn Turns::over(self : Turns, c : @ui.Ctx, what : TurnFor, at : Double) -> Unit {
  if self.on == Some(what) && self.open {
    self.open = false
    self.until = dmin(self.until, at)
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
fn Turns::next_ask(self : Turns) -> Int? {
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
fn Turns::free_at(self : Turns, a : TurnAsk) -> Double {
  dmax(dmax(self.until, self.list_rest), a.at)
}

///|
/// Plays the turns on, before the page is built (chat_tick): each one whose turn has come starts, from when it came.
/// `list_rest`: when the list's own motion is at rest (Ctx::list_info's `rest`; inf: under way, its end not known).
fn Turns::step(self : Turns, c : @ui.Ctx, list_rest : Double) -> Unit {
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
    if at > self.now {
      return
    }
    self.asks.remove(i) |> ignore
    self.on = Some(a.what)
    self.open = a.ms == @double.infinity
    self.until = at + (if self.open { turn_most_ms } else { a.ms })
    match a.what {
      Admit(k) => {
        self.waiting.remove(k) |> ignore
        self.started[k] = at
      }
      Change(k) => {
        self.shown[k] = self.wants.get(k).unwrap_or(!self.shown.get(k).unwrap_or(false))
        self.started[k] = at
      }
      Send => self.send_waiting = false
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
      if at <= now {
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
let row_turn_ms : Double = 320.0

///|
let working_turn_ms : Double = 220.0

///|
let close_turn_ms : Double = 520.0

///|
let dismiss_turn_ms : Double = 280.0

///|
/// When what is under a post `key` changes, or row `key` comes in: when it did, or, still to come, when its turn is
/// declared to start (the turns before it in order each from where the one before them ends, the list at rest); inf
/// while that is not known (a turn before it lasts till said over, the list's glide not set out).
fn Turns::start_of(self : Turns, key : String) -> Double {
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
    let start = dmax(dmax(end, self.list_rest), a.at)
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
