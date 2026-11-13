// A list's rows' heights as they change (2026-10-30 the user: 「那些会变长或缩短的消息
// 列表内容的动效协同起来的效果，需要系统性设计一下」「为啥每个改动都要自己处理一遍」). The page gives its list its rows
// each build, each by its key and its version (ListRows): from one build to the next the list itself works out what
// came (a key new to it: its room opening from nothing), what went (a key gone: kept in the list as it last was while
// its room closes) and what changed (another version: from the height it had to the new one), the row laid out that
// tall and cut there. Every row stands where the rows before it end, so rows never lie over one another nor leave a
// gap, however many change at once, and nothing waits for another; what is in view stays where the list's own rule has
// it. A row's height going is its layout's alone: what is kept of a row's build is kept (its height looked up by its
// key as it is laid out), nothing is built again for it.
//
// What changes together moves as one (2026-10-30 the user: 「在有决策卡片的时候发消息，整个消息列表会频繁来回移动」):
// the rows on their way go on one way, the list's, set out at the last cause's moment and over at the latest end any
// of them was given (a message sent, as long as its words fly). Each was off from its height by some way as it set
// out, and what is left of each is the same share of it at every moment, so what is over and under them, the sum of
// theirs, goes one way: a card's options closing over a message sent under it, each on a curve of its own, had what
// was over them go up for the one, then down for the other. What a row's content does to its height itself (what is
// in it opening or closing: Ctx::row_way) is its own, the list closing only what was off as it changed.

///|
/// What changed a row's height, and when (the frames' clock): it came into the list (from nothing), it goes from it
/// (to nothing: the row stays in the list till then), or what it holds changed (from the height it had then).
#derive(Eq)
pub(all) enum RowSize {
  Comes(Double)
  Goes(Double)
  Changed(Double)
}

///|
fn RowSize::at(self : RowSize) -> Double {
  match self {
    Comes(t) | Goes(t) | Changed(t) => t
  }
}

///|
/// A row on the list's way, as it stood as the way last set out (another cause come, the way given another end): what
/// was off of its height `to` then (`a`: as tall as it was then, less `to`), closing by the way's end as every row on
/// it does, by the same share of it at every moment (way_share): so what is over and under them, the sum of theirs,
/// goes one way to where it all comes to stand, the rows' heights shared out in it (2026-11-03 the user: 「一旦一个新的
/// 运动加入，就把当前运动的剩余部分跟新的运动结合起来，高度作为一个整体往终态走，然后在里面分配各自的高度」「这样整体高度不会来回
/// 变」). `before`: the way it was on till the way set out again later than now (a row's cause timed on: words sent
/// leaving the composer), `a`, `to`, `start`, `end` and its speed's share as there. `k`: the share's speed as the way
/// set out, as last known (RowCauses::way_k).
priv struct RowSizing {
  mut cause : RowSize
  mut a : Double
  mut to : Double
  mut start : Double
  mut end : Double
  mut k : Double
  mut before : (Double, Double, Double, Double, Double)?
  /// the frame it was last laid out in, and how it stood as that frame found it (a frame laid out twice, built again
  /// from what it read, lays it out the same: from there each time)
  mut frame : Int
  mut was : (RowSize, Double, Double, Double, Double, Double, (Double, Double, Double, Double, Double)?)
  /// the room over what it holds (its lead) as its cause came, and as the frame before this one laid it out: a lead
  /// another as it changed goes there on the way with its height, what it holds not stepped in its row (row_lead_off)
  mut lead : Double
  mut seen_lead : Double
}

///|
/// What is left of what was off as the rows' way set out at `start` (1 then, 0 at `end`), and how fast that goes (a
/// share a ms), at `t`: a Move's way from the speed `k` it set out at (@ui.move_path).
fn way_share(t : Double, start : Double, end : Double, k : Double) -> (Double, Double) {
  if t <= start {
    (1.0, k)
  } else {
    move_path(1.0, k, @flex.time_gone(t, start), end - start)
  }
}

///|
/// Row `r`'s height at `t` and how fast it goes (points a ms), `to` the height it goes to now (its own, where its
/// content goes on the way itself: Ctx::row_way), the way's speed `k`.
fn RowSizing::at(self : RowSizing, t : Double, to : Double, k : Double) -> (Double, Double) {
  match self.before {
    Some((a, bto, start, end, bk)) if t < self.start => {
      let (x, v) = way_share(t, start, end, bk)
      (bto + a * x, a * v)
    }
    _ => {
      let (x, v) = way_share(t, self.start, self.end, k)
      (to + self.a * x, self.a * v)
    }
  }
}

///|
/// How long a row's height takes to go to its new one: a near Move's (sf/motion.mbt Curves). Not yet as long as its
/// way is far, as every other move is: a row's height is worked out by its key as the list is laid out (ListRows),
/// its way's length to come with that.
pub let row_size_ms : Double = 300.0

///|
/// How far open a row coming or going where it is has what it holds out of sight (ListRows::enter, leave): it shrinks
/// with its room all the while, as tall as the room is open, and is gone by the time it is half its size, not seen
/// small: view's row_gone_at, the one a page's list's block on its way is seen by too.
pub let row_gone_at : Double = @view.row_gone_at

///|
/// What a row coming or going where it is holds, its room `p` open (0 to 1): as big as it is open, faded in from
/// row_gone_at on.
pub fn row_held_look(p : Double, ox? : Double = 0.5, oy? : Double = 0.5) -> Look {
  look(alpha=@view.row_seen_at(p), scale=p, ox~, oy~)
}

///|
/// What node `i` holds, coming or going where it is as far as `p` of it is open (row_held_look), as it is painted:
/// grown and shrunk about the middle of what of it is drawn (its words, pictures, grounds), not of the box it is in,
/// a page's width as it may be (2026-10-31 the user: 「有些东西就应该偏心缩放」「每个都在整个页面宽度中心缩放感觉不是很
/// 对」): a bubble to its side, a card under a post where it is. `top`: about the top of what it draws, not its middle
/// down (what comes into a room opening below what was there, growing down into it with it as it opens).
pub fn Ctx::held_look(self : Ctx, i : Int, p : Double, top? : Bool = false) -> Look {
  if p >= 1.0 {
    return still_look
  }
  let n = self.nodes[i]
  let mut x0 = 1.0e18
  let mut y0 = 1.0e18
  let mut x1 = -1.0e18
  let mut y1 = -1.0e18
  fn take(j : Int) {
    let m = self.nodes[j]
    if m.fw > 0.0 && m.fh > 0.0 && (m.kind != kind_box || m.grounded()) {
      x0 = dmin(x0, m.x)
      y0 = dmin(y0, m.y)
      x1 = dmax(x1, m.x + m.fw)
      y1 = dmax(y1, m.y + m.fh)
    }
    let mut ch = m.first
    while ch >= 0 {
      take(ch)
      ch = self.nodes[ch].next
    }
  }
  take(i)
  if x1 < x0 || n.fw <= 0.0 || n.fh <= 0.0 {
    return row_held_look(p, oy=if top { 0.0 } else { 0.5 })
  }
  let pivot = if top { y0 } else { (y0 + y1) / 2.0 }
  row_held_look(p, ox=((x0 + x1) / 2.0 - n.x) / n.fw, oy=(pivot - n.y) / n.fh)
}

///|
/// Row `k`, laid out `natural` tall, as tall as what changed it has it at `now` (its list's ListRows, by its key): off
/// from it as it was as its cause came (from nothing, one coming; from the height it had, one changed), by less as the
/// list's way goes, every row on it by the same share (RowSizing).
fn ListState::row_sized(self : ListState, k : Int, natural : Double, now : Double, frame : Int) -> Double {
  let (c, key, cause) = match self.causes {
    Some(c) if k < c.keys.length() => {
      c.read()
      match c.by.get(c.keys[k]) {
        Some((cause, _)) => (c, c.keys[k], cause)
        None => return natural
      }
    }
    _ => return natural
  }
  let to = match cause {
    Goes(_) => 0.0
    _ => natural
  }
  // (its way over before it was laid out on it, or as it is: as tall as it is; a hair short of its end, a sum of ms
  // rounded off, at it, as ListRows::rows has it over there, laid out again or built anew)
  if now >= c.end - 0.001 {
    c.opened.remove(key)
    return to
  }
  // (its rows laid out on the way till its end, as it was declared: what is dropped of it a hair before is the list's)
  self.sizes_end = c.end
  // (not of a row coming in: it goes from nothing to what it is laid out at, and what its content puts on at once
  // on the way (a card's options come to their post a frame or two after it, there at once as they are) goes there
  // with it, on from where it is, below; taken for its content's own going, the list put that whole room on in one
  // frame and all over the row went up by it, rows_steady.mbt's rows_step_least)
  let own = c.own.contains(key) && !(cause is Comes(_))
  // (gone and back elsewhere: new where it is now, from nothing, not on from as tall as it had closed to)
  if c.anew.contains(key) {
    c.anew.remove(key)
    self.sizes.remove(key)
  }
  c.way_begun(frame)
  let r = match self.sizes.get(key) {
    Some(r) => r
    None => {
      let from = match cause {
        Comes(_) => 0.0
        // (as tall as it was last laid out, by its key: what is had by its place in the list may be another row's as
        // the rows given change; a copy of a row gone and back elsewhere, as tall as that row stood)
        _ => c.carried.get(key).unwrap_or(self.shown_h.get(key).unwrap_or(natural))
      }
      // (off as the way set out: laid out first a while on, it is where the way has it by then)
      let r = {
        cause,
        a: from - to,
        to,
        start: c.start,
        end: c.end,
        k: 0.0,
        before: None,
        frame: -1,
        was: (cause, from - to, to, c.start, c.end, 0.0, None),
        lead: self.shown_lead.get(key).unwrap_or(c.leads.get(key).unwrap_or(0.0)),
        seen_lead: self.shown_lead.get(key).unwrap_or(c.leads.get(key).unwrap_or(0.0)),
      }
      self.sizes[key] = r
      c.way_off(key, from - to, 0.0)
      r
    }
  }
  if r.frame == frame {
    let (was_cause, a, was_to, start, end, rk, before) = r.was
    r.cause = was_cause
    r.a = a
    r.to = was_to
    r.start = start
    r.end = end
    r.k = rk
    r.before = before
  } else {
    r.frame = frame
    r.was = (r.cause, r.a, r.to, r.start, r.end, r.k, r.before)
    r.seen_lead = self.shown_lead.get(key).unwrap_or(r.seen_lead)
  }
  // (its content going on the way itself: where it goes is where it is laid out now, so that a cause after this one,
  // its content no longer on the way, goes on from where it was laid out, not from where it was as it set out)
  if own {
    r.to = to
  }
  // (the way's speed as it set out, once every row on it has said what was off of it: the frame after)
  if r.start == c.start && r.end == c.end {
    match c.way_k(frame) {
      Some(wk) => r.k = wk
      None => ()
    }
  }
  // its height laid out as it goes to: its own, where its content goes on the way itself (only what was off of it as it
  // changed is the way's)
  let base = fn(r : RowSizing) { if own { to } else { r.to } }
  // what it goes by changed (another cause, the way set out again or given another end): what is left of it, from
  // where it is as the way sets out (how fast it goes then telling how fast the rows' sum goes), one share of the
  // whole that goes on from there (RowCauses::way_k)
  if r.cause == cause && r.start == c.start && r.end != c.end && now >= r.start {
    // (the way given another end, set out as it was: on from where it is, by the share of the new way left)
    let (h, _) = r.at(now, base(r), r.k)
    r.end = c.end
    let (x, _) = way_share(now, r.start, r.end, r.k)
    r.a = if x > 0.02 { (h - base(r)) / x } else { 0.0 }
  } else if r.cause != cause || r.start != c.start || r.end != c.end {
    let t = c.start
    // A future way replaces another future way, not the motion already under way. Keep that motion until the new
    // start, including when the future way is retimed again or a closing row is due to return.
    let before = if t <= now {
      None
    } else if cause.at() > now && r.cause.at() == now &&
      ((cause is Comes(_) && r.cause is Comes(_)) || (cause is Changed(_) && r.cause is Changed(_))) {
      // The row's own start was just moved into the future, before that change set out.
      let (h, _) = r.at(now, base(r), r.k)
      Some((h - base(r), base(r), @double.infinity, @double.infinity, 0.0))
    } else if r.start > now {
      match r.before {
        Some(previous) => Some(previous)
        None => Some((r.a, base(r), @double.infinity, @double.infinity, 0.0))
      }
    } else {
      Some((r.a, base(r), r.start, r.end, r.k))
    }
    let (h, v) = match before {
      Some((a, bto, start, end, k)) => {
        let (x, speed) = way_share(t, start, end, k)
        (bto + a * x, a * speed)
      }
      None => r.at(t, base(r), r.k)
    }
    r.before = before
    r.a = h - to
    r.to = to
    r.lead = r.seen_lead
    r.start = c.start
    r.end = c.end
    r.k = 0.0
    r.cause = cause
    c.way_off(key, r.a, v)
  } else if !own && (to - r.to).abs() > 0.5 {
    // what it is laid out at stepping on the way (a picture come to its size, the core's row joined to the one before):
    // on from where it is, by the share of the way left
    let (h, _) = r.at(now, r.to, r.k)
    let (x, _) = way_share(now, r.start, r.end, r.k)
    r.a = if x > 0.02 && now >= r.start { (h - to) / x } else { r.a + r.to - to }
    r.to = to
  }
  // (in the frame the way sets out, its speed not known till every row on it has said where it was: where the way has
  // them as it set out, a sliver of a frame before now, not on from rest and then at its speed the frame after)
  let t = if r.start == c.start && r.end == c.end && c.way_speed is None { dmin(now, r.start) } else { now }
  let shown = r.at(t, base(r), r.k).0
  // (one coming or going where it is, how far open: what it holds is drawn by it as it is painted, ListRows::enter,
  // leave)
  // (not one laid out coming on this way already as what brought it had it, said to come by its room only since
  // (words sent before the last, their flight over or let go as more were sent): it goes on as it went. Put in the
  // middle of its room from then, what it holds stepped there in one frame, 14 points with a row 500 ms on its way)
  if !(cause is Changed(_)) && c.by_room.contains(key) && !c.not_by_room.contains(key) {
    c.opened[key] = (shown, natural)
  } else if cause is Comes(_) {
    c.not_by_room.add(key)
  }
  c.stood[key] = shown
  shown
}

///|
/// How far down from where its row lays it what row `k` holds is placed at `now`, its lead (the room over it at its
/// top, ListRows::enter) another as it changed: from where the lead put it then, going as far as its height has gone
/// on the rows' way (the row's room between rows going there with it, not what it holds stepped in it); none once
/// there, nor for a row coming or going, nor one whose lead is as it was.
fn ListState::row_lead_off(self : ListState, k : Int, now : Double) -> Double {
  let (c, key) = match self.causes {
    Some(c) if k < c.keys.length() && c.end > now => (c, c.keys[k])
    _ => return 0.0
  }
  match (c.by.get(key), self.sizes.get(key)) {
    (Some((Changed(_), _)), Some(r)) => {
      let lead = c.leads.get(key).unwrap_or(0.0)
      if (r.lead - lead).abs() < 0.001 || now < r.start {
        return if now < r.start { r.lead - lead } else { 0.0 }
      }
      (r.lead - lead) * way_share(now, r.start, r.end, r.k).0
    }
    _ => 0.0
  }
}

///|
/// Whether row `k` comes or goes where it is (ListRows::enter, leave), its room opening or closing now: what it holds
/// drawn in the middle of it, what it cuts off fading out to its edges (row_soft).
fn ListState::row_by_room(self : ListState, k : Int) -> Bool {
  match self.causes {
    Some(c) if k < c.keys.length() => c.opened.contains(c.keys[k])
    _ => false
  }
}

///|
/// How far down what row `k` holds is placed as its room is `shown` tall of the `h` it is laid out, coming or going
/// where it is (row_by_room): what it holds under its lead (the room over it at its top, ListRows::enter) in the middle
/// of what is open, the lead opening and closing with it, so that it is cut alike at both ends however far down in its
/// row it is; none once it is open.
fn ListState::row_middle(self : ListState, k : Int, shown : Double, h : Double) -> Double {
  let lead = match self.causes {
    Some(c) if k < c.keys.length() => c.leads.get(c.keys[k]).unwrap_or(0.0)
    _ => 0.0
  }
  if h <= 0.0 {
    0.0
  } else {
    (shown - h) / 2.0 * (h + lead) / h
  }
}

///|
/// How far before the edges of its room, `shown` tall of the `h` it is laid out, what a row coming or going holds fades
/// out (ListRows::enter, leave): as far as is cut off it at each end, at most cut_soft_most, and no more than half of
/// what shows, so that a line of words half cut shows half faded, never a hard edge across it.
fn row_soft(shown : Double, h : Double) -> Double {
  cut_soft((h - shown) / 2.0, shown / 2.0)
}

///|
/// The rows of lists cut by their rooms as they come and go, as this frame was laid out: what each holds fading out to
/// its room's edges (Drawn's `fades`), from where they are laid out now, for this frame alone.
fn Ctx::rows_soft_after_layout(self : Ctx) -> Unit {
  for rs in dr.rows_soft {
    let (r, soft) = rs
    if r < self.count {
      for ch in self.room_held_in(r) {
        self.fade_to(ch, r, top=soft, foot=soft)
      }
    }
  }
  dr.rows_soft.clear()
}

///|
/// What row `r` (a list's row, laid out) holds that comes and goes in its room (Node's `room_held`, the first found
/// down each way), or all it holds where nothing in it is so (what is drawn on nothing of its own).
fn Ctx::room_held_in(self : Ctx, r : Int) -> Array[Int] {
  let out : Array[Int] = []
  fn find(n : Int) {
    if self.nodes[n].room_held {
      out.push(n)
      return
    }
    let mut ch = self.nodes[n].first
    while ch >= 0 {
      find(ch)
      ch = self.nodes[ch].next
    }
  }
  find(r)
  if out.is_empty() {
    let mut ch = self.nodes[r].first
    while ch >= 0 {
      out.push(ch)
      ch = self.nodes[ch].next
    }
  }
  out
}

///|
/// Row `k` laid out `h` tall, what it holds `lead_off` down from where its lead puts it (row_lead_off): so tall and its
/// lead so, by its key, for a change of it from there (a list whose rows' heights move).
fn ListState::row_shown(self : ListState, k : Int, h : Double, lead_off? : Double = 0.0) -> Unit {
  match self.causes {
    Some(c) if k < c.keys.length() => {
      // (only the rows given now kept: what went from the list long since forgotten)
      if self.shown_h.length() > 2 * c.keys.length() + 16 {
        self.shown_h.clear()
      }
      self.shown_h[c.keys[k]] = h
      if self.shown_lead.length() > 2 * c.keys.length() + 16 {
        self.shown_lead.clear()
      }
      self.shown_lead[c.keys[k]] = c.leads.get(c.keys[k]).unwrap_or(0.0) + lead_off
    }
    _ => ()
  }
}

///|
/// Whether row `k`'s content goes to its height on the rows' way at `now` (Ctx::row_way).
fn ListState::row_own_way(self : ListState, k : Int, now : Double) -> Bool {
  match self.causes {
    Some(c) => now < c.end - 0.001 && k < c.keys.length() && c.own.contains(c.keys[k])
    None => false
  }
}

///|
/// When the list's way a row was last laid out on is over (-1: none was).
fn ListState::sizes_rest(self : ListState) -> Double {
  self.sizes_end
}

///|
/// The rows' ways forgotten once the list's is over.
fn ListState::sizes_kept(self : ListState, now : Double) -> Unit {
  match self.causes {
    Some(c) if now < c.end - 0.001 => ()
    _ => self.sizes.clear()
  }
}

///|
/// A list's rows' ways to their heights as what moves (frames till the last is over, the list laid out again each).
priv struct Sizes {
  st : ListState
}

///|
impl Moving for Sizes with rest_at(self, now, frame) {
  ignore(frame)
  // (over: at rest, whatever is kept of a way gone by)
  // (a hair past now, a sum of ms rounded off: at rest, as at its end)
  let t = self.st.sizes_rest()
  if t > now + 0.001 {
    t
  } else {
    -1.0
  }
}


///|
/// Why each row of a list goes to another height, by its key, and the keys of its rows in order as last given (its
/// ListRows' answer, for its layout: Ctx::list's `sized`).
pub struct RowCauses {
  by : Map[String, (RowSize, Double)]
  mut keys : Array[String]
  /// told as any of it changes: what its layout reads it by (Ctx::list), and what a row reads of it (ListRows::came,
  /// went)
  priv said : @signals.Signal[Int]
  priv mut n : Int
  /// the rows' way: set out at the last cause's moment, over at the latest end one was given (-1: none under way)
  priv mut start : Double
  priv mut end : Double
  /// the rows whose content goes on the way itself (Ctx::row_way), by their keys: the list closes only what was off
  /// as their cause came
  priv own : Set[String]
  /// the rows that come and go where they are (ListRows::enter, leave), by their keys, and of those coming or going,
  /// how tall each is laid out now and how tall it is (by its layout, read as it is painted)
  priv by_room : Set[String]
  /// the rows coming that were laid out on the way not so (brought some other way: words flying to their row): none
  /// of them turns so on its way (ListState::row_sized)
  priv not_by_room : Set[String]
  priv opened : Map[String, (Double, Double)]
  /// how tall each row on the way was last laid out, by its key (ListState::row_sized)
  priv stood : Map[String, Double]
  /// a row gone that came back elsewhere while its room still closed (ListRows::rows): the copy of it left closing
  /// where it stood, by its key, as tall as the row stood then (`stood`); and the row itself, new where it is now,
  /// from nothing
  priv carried : Map[String, Double]
  priv anew : Set[String]
  /// of those, the room over what each holds, at its top (its gap to the row before: ListRows::enter's `lead`)
  priv leads : Map[String, Double]
  /// the frame its list was last laid out in (shown): one not shown the frame before is shown anew, as it is
  priv mut laid : Int
  /// the way as its rows last set out on it (`start`, -1 none), the frame they did, what was off of each and how fast
  /// it went then, by its key, and the speed the share of what is left sets out at once all have said (way_k)
  priv mut way_at : Double
  priv mut way_frame : Int
  priv way_offs : Map[String, (Double, Double)]
  priv mut way_speed : Double?
}

///|
/// The rows set out on the way as it is now, in frame `frame`: what each said of the way before forgotten.
fn RowCauses::way_begun(self : RowCauses, frame : Int) -> Unit {
  if self.way_at != self.start {
    self.way_at = self.start
    self.way_frame = frame
    self.way_offs.clear()
    self.way_speed = None
  }
}

///|
/// Row `key` set out on the way `off` off of where it goes, going `v` (points a ms) then.
fn RowCauses::way_off(self : RowCauses, key : String, off : Double, v : Double) -> Unit {
  self.way_offs[key] = (off, v)
}

///|
/// The speed what is left of every row's way sets out at (a share a ms: 0 from rest), once all on it have said where
/// they were (a frame after it set out; None till then): what is off of them all together, and how fast that went as
/// the way set out, so that the rows' sum goes on as fast as it went where it went toward where it all comes to stand,
/// not a step slower or faster; from rest where it went the other way (stopped there, no further that way first), and
/// never so fast it passes where it comes to stand.
fn RowCauses::way_k(self : RowCauses, frame : Int) -> Double? {
  match self.way_speed {
    Some(k) => return Some(k)
    None => ()
  }
  if frame <= self.way_frame {
    return None
  }
  let mut d = 0.0
  let mut v = 0.0
  self.way_offs.each(fn(_, o) {
    d = d + o.0
    v = v + o.1
  })
  let len = self.end - self.start
  // (from rest where a row's content goes on the way itself (Ctx::row_way: a Move from its start, from rest), so that
  // its share and every other's are the same at every moment)
  let k = if d.abs() < 0.5 || len <= 0.0 || !self.own.is_empty() {
    0.0
  } else {
    dmin(0.0, dmax(v / d, -move_k / len))
  }
  self.way_speed = Some(k)
  Some(k)
}

///|
/// Its rows' keys now (`keys`), and whether why any goes to another height changed (`moved`): what reads it told if
/// either did (not for the same keys given anew).
fn RowCauses::told(self : RowCauses, keys : Array[String], moved : Bool) -> Unit {
  let was = self.keys
  self.keys = keys
  if moved || !(physical_equal(was, keys) || was == keys) {
    self.n += 1
    self.said.set(self.n)
  }
}

///|
/// What reads it is told as it changes from now.
fn RowCauses::read(self : RowCauses) -> Unit {
  self.said.get() |> ignore
}

///|
/// A row gone from a list, in it still as it last was while its room closes: it, when it went, the row it came after.
priv struct GoingRow[T] {
  item : T
  at : Double
  after : String
}

///|
/// A list's rows as the page gives them each build (ListRows::rows), and what the list made of them.
pub struct ListRows[T] {
  priv was : Map[String, String]
  priv mut order : Array[(String, T)]
  priv going : Map[String, GoingRow[T]]
  priv causes : RowCauses
  priv mut given : Bool
  priv mut last_keys : Array[String]
  priv mut last_items : Array[T]
  /// the keys going, read by each row as whether it is one
  priv going_said : @signals.Keyed[String]
}

///|
pub fn[T] ListRows::new() -> ListRows[T] {
  { was: {}, order: [], going: {}, causes: { by: {}, keys: [], said: @signals.signal(0), n: 0, start: -1.0, end: -1.0, own: Set([]), by_room: Set([]), not_by_room: Set([]), opened: {}, stood: {}, carried: {}, anew: Set([]), leads: {}, laid: -10, way_at: -1.0, way_frame: -1, way_offs: {}, way_speed: None }, given: false, last_keys: [], last_items: [], going_said: @signals.keyed() }
}

///|
/// The rows of a list as they are now (`keys`, `items` by the same index, `version` of each: what it shows), with what
/// went from them still among them (after the row each came after) while its room closes, and their keys. What changed
/// since they were last given is said from now: a key new comes, one gone goes, another version changes. Not
/// `watched` (the list not followed, its page another's, a page of it read anew): what changed is so at once.
/// `ms`: how long a row's coming takes where it goes with another motion of its cause (words flying to it), a row's
/// move otherwise; `from`: the moment such a row's change sets out where that motion has it later than now (words
/// sent coming in as they leave the composer, the composer's room let go as they do), from which it is `ms` long, the
/// row as it was till then. `comes`: whether a row new to the list comes now (false: it was there before, only brought now, as
/// what was caught up on), there at once.
pub fn[T] ListRows::rows(
  self : ListRows[T],
  c : Ctx,
  keys : Array[String],
  items : Array[T],
  version : (T) -> String,
  watched? : Bool = true,
  ms? : (String) -> Double? = fn(_) { None },
  from? : (String) -> Double? = fn(_) { None },
  comes? : (T) -> Bool = fn(_) { true },
  moves? : (T) -> Bool = fn(_) { false },
) -> (Array[T], Array[String]) {
  let now = c.moment()
  // (its list not shown the frame before, its page come back to, its pane slid to: shown as it is, nothing coming)
  let watched = watched && self.causes.laid >= c.frame_number() - 1
  // (the same arrays as last given: nothing of them changed, nothing to look over)
  let same = self.given &&
    physical_equal(keys, self.last_keys) &&
    physical_equal(items, self.last_items)
  // A fresh set of items can still have the same keys in the same order. Their versions must be read, but no row
  // can have moved or gone; finding the longest retained order again would do work proportional to the whole list.
  let same_keys = if same {
    true
  } else if self.given && keys.length() == self.order.length() && keys.length() == self.was.length() {
    // Compare against the recorded order, not the caller's last array: a caller may have changed that array in place
    // while giving new items. Duplicate keys keep the ordinary path too.
    let mut equal = true
    for i, k in keys {
      if k != self.order[i].0 {
        equal = false
        break
      }
    }
    equal
  } else {
    false
  }
  self.last_keys = keys
  self.last_items = items
  let here : Map[String, Bool] = Map([])
  if !same_keys {
    for k in keys {
      here[k] = true
    }
  }
  // (whether any of what the list and its rows read of it changed: told them as it did)
  let mut moved = false
  // the rows' way over: what went out of the list at its end, what made it forgotten
  // (a hair short of it, a sum of ms rounded off, is there)
  if self.causes.end >= 0.0 && now >= self.causes.end - 0.001 {
    moved = moved || !self.going.is_empty() || !self.causes.by.is_empty()
    self.going.clear()
    self.causes.by.clear()
    self.causes.start = -1.0
    self.causes.end = -1.0
    self.causes.own.clear()
    self.causes.by_room.clear()
    self.causes.not_by_room.clear()
    self.causes.opened.clear()
    self.causes.stood.clear()
    self.causes.carried.clear()
    self.causes.anew.clear()
    self.causes.leads.clear()
  }
  // (whether a row sets out now: the rows' way sets out again from here)
  let mut began = false
  if same && watched {
    ()
  } else if self.given && watched {
    for i, k in keys {
      let v = version(items[i])
      // (gone, its room still closing, and given again: where it went by, before it is said to come)
      let went_by = if self.going.contains(k) { self.causes.by.get(k) } else { None }
      match self.was.get(k) {
        None =>
          if comes(items[i]) {
            self.causes.by[k] = (Comes(from(k).unwrap_or(now)), ms(k).unwrap_or(row_size_ms))
            self.causes.own.remove(k)
            began = true
          }
        // (changed as it comes: still coming, on to what it is now)
        Some(w) if w != v =>
          match self.causes.by.get(k) {
            Some((Comes(_), _)) => ()
            _ => {
              self.causes.by[k] = (Changed(from(k).unwrap_or(now)), ms(k).unwrap_or(row_size_ms))
              // (its content going on the way itself for the cause before, not said for this one till it says so again:
              // Ctx::row_way)
              self.causes.own.remove(k)
              began = true
            }
          }
        _ => ()
      }
      match self.going.get(k) {
        Some(g) => {
          // back elsewhere than it stood (rows come since between: where a chat stands, gone as its agent set to
          // work, back at the list's end as the turn was over a moment after): it leaves where it was, a copy of it
          // as it was, and comes where it is from nothing, as a row gone ahead of others does (`moves`). Taken up
          // where it is now as tall as it had closed to, that room went from over the rows between to under them in
          // one frame, all of them a step up (rows_steady.mbt's rows_step_least). Back where it stood, it turns
          // back from where it is
          let copy = k + row_moved_mark
          let stood_after = if i > 0 { keys[i - 1] } else { "" }
          if g.after != stood_after && !self.going.contains(copy) && self.causes.by.get(k) is Some((Comes(_), _)) {
            self.going[copy] = g
            self.causes.by[copy] = match went_by {
              Some((Goes(at), dur)) => (Goes(at), dur)
              _ => (Goes(g.at), row_size_ms)
            }
            match self.causes.stood.get(k) {
              Some(h) => self.causes.carried[copy] = h
              None => ()
            }
            self.causes.anew.add(k)
          }
          self.going.remove(k)
          moved = true
        }
        None => ()
      }
    }
    // the rows gone ahead of others (`moves`: a chat with news to its list's top): each leaves where it was, a copy of
    // it as it was, and comes where it is, as a row gone and a row new do (2026-10-31 the user: 「原地缩下去再从目标点挤
    // 出来更合理」, not across the rows between, which it would cover)
    // Those that moved are the fewest whose order changed: all but the most rows kept in the order they had (one gone
    // down past others moved, not each it passed, which only kept their order among themselves)
    if !same_keys {
      let ahead : Set[String] = Set([])
      let before : Map[String, Int] = Map([])
      for j, r in self.order {
        before[r.0] = j
      }
      let at : Array[Int] = []
      let was_at : Array[Int] = []
      for i, k in keys {
        match before.get(k) {
          Some(b) => {
            at.push(i)
            was_at.push(b)
          }
          None => ()
        }
      }
      let kept = in_order_most(was_at)
      for n, i in at {
        if !kept[n] && moves(items[i]) {
          let k = keys[i]
          ahead.add(k)
          self.causes.by[k] = (Comes(from(k).unwrap_or(now)), ms(k).unwrap_or(row_size_ms))
          began = true
        }
      }
      let mut prev = ""
      for r in self.order {
        let (k, item) = r
        if ahead.contains(k) {
          let copy = k + row_moved_mark
          let at = from(k).unwrap_or(now)
          self.going[copy] = { item, at, after: prev }
          self.causes.by[copy] = (Goes(at), ms(k).unwrap_or(row_size_ms))
          prev = copy
          continue
        }
        if !here.contains(k) && !self.going.contains(k) {
          let at = from(k).unwrap_or(now)
          self.going[k] = { item, at, after: prev }
          self.causes.by[k] = (Goes(at), ms(k).unwrap_or(row_size_ms))
          began = true
        }
        if here.contains(k) || self.going.contains(k) {
          prev = k
        }
      }
    }
  } else if !self.going.is_empty() || !self.causes.by.is_empty() {
    self.going.clear()
    self.causes.by.clear()
    moved = true
  }
  // (coming or changing with another motion of its cause, told anew when and how long: words sent, timed once they
  // know their way)
  let retimed : Array[(String, RowSize, Double)] = []
  self.causes.by.each(fn(k, cm) {
    let (cause, was) = cm
    // (when, only while it has not set out: one on its way goes on as it goes)
    let at = if cause.at() >= now { from(k).unwrap_or(cause.at()) } else { cause.at() }
    let now_ms = ms(k).unwrap_or(was)
    if cause is Goes(_) || (at == cause.at() && now_ms == was) {
      return
    }
    retimed.push((k, match cause { Comes(_) => Comes(at); _ => Changed(at) }, now_ms))
  })
  for r in retimed {
    self.causes.by[r.0] = (r.1, r.2)
    moved = true
    // (the way setting out with it, later than said: a row whose content goes on it itself goes from then, row_way)
    if r.1.at() > self.causes.start {
      self.causes.start = r.1.at()
    }
  }
  // (told sooner than said, the way not set out yet: from the latest of its causes now, as it would have been said so,
  // not from the moment said first: words sent timed once their row is laid out, their row's coming earlier than the
  // usual way's share had it)
  if !retimed.is_empty() && self.causes.start > now {
    let mut start = now
    self.causes.by.each(fn(_, cm) { start = dmax(start, cm.0.at()) })
    self.causes.start = start
  }
  self.given = true
  // the rows' way: from the last cause's moment to the latest end any was given
  if began {
    // (from the latest moment one sets out: now, or later where one's cause has it so: `from`)
    let mut start = now
    self.causes.by.each(fn(_, cm) { start = dmax(start, cm.0.at()) })
    self.causes.start = start
    moved = true
  }
  let mut end = -1.0
  self.causes.by.each(fn(_, cm) { end = dmax(end, cm.0.at() + cm.1) })
  if self.causes.by.is_empty() {
    self.causes.start = -1.0
    self.causes.own.clear()
    self.causes.by_room.clear()
    self.causes.not_by_room.clear()
    self.causes.opened.clear()
    self.causes.stood.clear()
    self.causes.carried.clear()
    self.causes.anew.clear()
    self.causes.leads.clear()
  }
  self.causes.end = end
  // (built again at its end: what goes out of the list then)
  if !self.going.is_empty() && end > now {
    c.shows_until(end - 0.001)
  }
  if !same {
    self.was.clear()
    for i, k in keys {
      self.was[k] = version(items[i])
    }
    self.order = keys.mapi(fn(i, k) { (k, items[i]) })
  }
  self.going_said.set(self.going.keys().collect())
  // (nothing going: the arrays as given, the same ones while they are, so what is worked out of them is kept)
  if self.going.is_empty() {
    self.causes.told(keys, moved)
    return (items, keys)
  }
  // the rows going among them, each after the row it came after (the first, before all)
  let all_keys = keys.copy()
  let all_items = items.copy()
  {
    let order = self.going.to_array()
    order.sort_by(fn(a, b) { a.1.at.compare(b.1.at) })
    // (each once the row it came after is in, itself gone too maybe, as it went before this one: a row put before all
    // where that was never found)
    let mut pending = order
    while !pending.is_empty() {
      let later : Array[(String, GoingRow[T])] = []
      for g in pending {
        let (k, go) = g
        let mut at = -1
        if go.after == "" {
          at = 0
        } else {
          for i, kk in all_keys {
            if kk == go.after {
              at = i + 1
            }
          }
        }
        if at < 0 {
          later.push(g)
          continue
        }
        // (after those gone before it that came after the same row: it stood after them, only not given with them as
        // it went, they being gone already; else it is put over them, they and it each a step the other way at once)
        while at < all_keys.length() &&
              (match self.going.get(all_keys[at]) {
                Some(o) => o.after == go.after && o.at <= go.at
                None => false
              }) {
          at = at + 1
        }
        all_keys.insert(at, k)
        all_items.insert(at, go.item)
      }
      if later.length() == pending.length() {
        for g in later {
          all_keys.insert(0, g.0)
          all_items.insert(0, g.1.item)
        }
        break
      }
      pending = later
    }
  }
  self.causes.told(all_keys, moved)
  (all_items, all_keys)
}

///|
/// What a row gone ahead of others leaves by where it was is keyed by: its key and this (ListRows::rows' `moves`).
pub let row_moved_mark : String = "\u{2}was"

///|
/// Which of `was` (the rows' places before, in their order now) are among the most that are still in the order they
/// had: a longest increasing run of them, not necessarily side by side. The others are the fewest that moved.
fn in_order_most(was : Array[Int]) -> Array[Bool] {
  let n = was.length()
  // ends[l]: the index into `was` that ends the run of l + 1 found with the least last place; back[i]: the one before
  // i in its run (-1 none)
  let ends : Array[Int] = []
  let back = Array::make(n, -1)
  for i in 0..<n {
    let mut lo = 0
    let mut hi = ends.length()
    while lo < hi {
      let mid = (lo + hi) / 2
      if was[ends[mid]] < was[i] {
        lo = mid + 1
      } else {
        hi = mid
      }
    }
    if lo > 0 {
      back[i] = ends[lo - 1]
    }
    if lo == ends.length() {
      ends.push(i)
    } else {
      ends[lo] = i
    }
  }
  let kept = Array::make(n, false)
  let mut i = if ends.is_empty() { -1 } else { ends[ends.length() - 1] }
  while i >= 0 {
    kept[i] = true
    i = back[i]
  }
  kept
}

///|
/// What changed its rows' heights, for the list's layout (Ctx::list's `sized`).
pub fn[T] ListRows::sized(self : ListRows[T]) -> RowCauses {
  self.causes
}

///|
/// When row `key` came into the list as it was watched, while it opens its room (None: it did not, or it is open).
pub fn[T] ListRows::came(self : ListRows[T], key : String) -> Double? {
  self.causes.read()
  match self.causes.by.get(key) {
    Some((Comes(at), _)) => Some(at)
    _ => None
  }
}

///|
/// When row `key` went from the list, as its room closes (None: it is in it): the moment its room sets out closing
/// (ListRows::leave).
pub fn[T] ListRows::went(self : ListRows[T], key : String) -> Double? {
  if !self.going_said.has(key) {
    return None
  }
  self.going.get(key).map(fn(g) { g.at })
}

///|
/// What a row coming or going where it is holds, as it is drawn: its room `shown` tall of the `h` it is laid out,
/// grown to its size as far as it is open and faded in from half open (row_held_look), what its room cuts off it fading out to its
/// edges (Ctx::list's row_soft); laid out in the middle of it by its list (so drawn, tapped and found there).
fn Ctx::row_look(self : Ctx, i : Int, shown : Double, h : Double) -> Look {
  let p = dmax(dmin(if h > 0.0 { shown / h } else { 1.0 }, 1.0), 0.0)
  if p >= 1.0 {
    still_look
  } else {
    self.held_look(i, p)
  }
}

///|
/// Row `key`, built as node `i`, as it goes from the list (ListRows::went): its room closes at once on the list's way,
/// what it holds in the middle of it, shrunk with it as it closes and faded out by half closed (row_held_look), cut by it at both ends,
/// what is cut fading out to them (2026-10-31 the user: 「这样会影响速度吧，你要不两头裁呢？再加上淡化的边缘」), drawn only
/// (nothing in it tapped). A row coming (ListRows::enter) played back. By how far it is open as the list lays it out,
/// read as it is painted, its row not built again for it. Nothing for a row not going.
pub fn[T] ListRows::leave(
  self : ListRows[T],
  c : Ctx,
  i : Int,
  key : String,
  lead? : Double = 0.0,
) -> Unit {
  match self.went(key) {
    Some(_) => {
      self.causes.by_room.add(key)
      self.causes.leads[key] = lead
      c.nodes[i].room_held = true
      c.draw_only(i)
      let causes = self.causes
      // (its node where it is as it is painted: its row kept as its nodes is put back where its list lays it then)
      let row = c.node_held(i)
      c.look_by(i, fn() {
        causes.read()
        // (as it was laid out last on the list's way; none once that is over, laid out again or not)
        match (causes.by.get(key), causes.opened.get(key), row.at()) {
          (Some((Goes(_), _)), Some((shown, h)), Some(i)) if c.moment() < causes.end - 0.001 =>
            c.row_look(i, shown, h)
          _ => still_look
        }
      })
    }
    None => ()
  }
}

///|
/// Row `key`, built as node `i`, as it comes into the list where it is (no flight brings it; `lead`: the room over what
/// it holds at its top, its gap to the row before, opening with it): its room opens on the
/// list's way at once, what it holds in the middle of it, faded in and grown from
/// row_held_look as it opens, cut by it at both ends, what is cut fading out to them: a row going (ListRows::leave)
/// played back. By how far it is open as the list lays it out, read as it is painted, its row not built again for it.
/// Nothing once it is open, nor for a row there already. Not `grown`: what it holds as it is (it comes in a way of its
/// own: words a glyph at a time), only cut by its room.
pub fn[T] ListRows::enter(
  self : ListRows[T],
  c : Ctx,
  i : Int,
  key : String,
  lead? : Double = 0.0,
  grown? : Bool = true,
) -> Unit {
  self.causes.by_room.add(key)
  self.causes.leads[key] = lead
  c.nodes[i].room_held = true
  if !grown {
    return
  }
  let causes = self.causes
  // (its node where it is as it is painted: its row kept as its nodes is put back where its list lays it then)
  let row = c.node_held(i)
  c.look_by(i, fn() {
    causes.read()
    // (one going drawn as it goes, not as it came: ListRows::leave)
    // (as it was laid out last on the list's way; none once that is over, laid out again or not)
    match (causes.by.get(key), causes.opened.get(key), row.at()) {
      (Some((Goes(_), _)), _, _) => still_look
      (_, Some((shown, h)), Some(i)) if c.moment() < causes.end - 0.001 => c.row_look(i, shown, h)
      _ => still_look
    }
  })
}

///|
/// Whether a row come into the list still opens its room: built again as the last of them is open.
pub fn[T] ListRows::opening(self : ListRows[T], c : Ctx) -> Bool {
  let now = c.moment()
  // (by the end it was given: where another changed after it came, the rows' way it goes on is longer, the last of
  // its opening, most of it in view by then)
  let mut last = -1.0
  self.causes.by.each(fn(_, cm) {
    match cm {
      (Comes(at), ms) if at + ms > now => last = dmax(last, at + ms)
      _ => ()
    }
  })
  if last > now {
    c.shows_until(last)
    true
  } else {
    false
  }
}

///|
/// What changes the heights of the rows the list laying them out now has (Ctx::place_list): what a row's content reads
/// of its way as it is built.
// kept across runs: set and put back as each list lays its rows out
let rows_laid_by : Ref[(RowCauses, Int)?] = Ref(None)

///|
/// The way the rows of the list a row is built in go to their heights (its start, how long), while it is under way:
/// what in the row changes its height itself as its version changes (a card's options closing as it is answered) goes
/// on it, from its start and as long, so that it moves as one with the rows round it (None: built in no such list, or
/// none on its way, or its row not: what changes in a row whose version did not change is not the way's, which set out
/// for others before it).
pub fn Ctx::row_way(self : Ctx) -> (Double, Double)? {
  match rows_laid_by.val {
    Some((c, k)) if c.end > self.clock && c.start >= 0.0 && k < c.keys.length() && c.by.contains(c.keys[k]) => {
      // (what it does to its row's height its own from now: ListState::row_sized)
      c.own.add(c.keys[k])
      Some((c.start, c.end - c.start))
    }
    _ => None
  }
}
