// The bar along what scrolls (a list, a box kept to a height, a box scrolled sideways, a field of more lines than it
// shows), saying where its view is in what it holds: one look and one way of showing for every one of them, as
// still.fail's web draws its own for a mouse (web/src/scrollbars.ts). A finger has none (the user, 2026-10-25: on a
// touch screen what it scrolls moving under it says enough; a bar drawn over a strip of choices was ugly): a bar is
// the pointer's, a response of the hand's (@ui.pointing), not the layout's.
//
// A thumb scroll_bar_size wide, round, scroll_bar_inset in from the edge it runs along (the right of what scrolls up
// and down, the foot of what scrolls sideways), in the words' colour at 26% (45% pointed at or held), at least
// scroll_bar_least long. Over what scrolls up and down, taking no room from it; what scrolls sideways keeps its foot
// clear for it while it can scroll (scroll_bar_room under what it holds, Ctx::sideways), so it never lies over what it
// holds (the user, 2026-10-25: a table's bar over its last row). Drawn in its clip after what it holds: what lies
// over what scrolls (a menu, a dialog) lies over its bar too. It runs along what of that edge shows: clear of what
// floats over the top and the foot of what scrolls (Ctx::floats_over: a page's bar, a composer) and scroll_bar_clear
// more, and of the rounding of the corners it is cut by; where that leaves less than two thumbs' room, along all of it.
//
// It shows while what it is for scrolls, whatever moves it (a finger, the wheel, the keys, a fling, the app sending
// it to a row or gliding it to its end, rows come at the end it follows; not where it is first put) and
// scrollbar_hold_ms after; then it fades out over scrollbar_fade_ms, as it comes in. With a mouse also while the
// pointer is along its edge (scroll_bar_near in from it), or holds its thumb, and as long after: its thumb (and a
// little round it) is a target as any, pressed and dragged to scroll, nothing under it pressed.

///|
/// A bar's thumb: how wide, how far in from the edge it runs along and from its track's ends, how long at least (the
/// web's SIZE, INSET, MIN_THUMB).
pub let scroll_bar_size : Double = 3.0

///|
pub let scroll_bar_inset : Double = 2.0

///|
pub let scroll_bar_least : Double = 28.0

///|
/// The room a bar along a foot takes: itself and its inset either side.
pub let scroll_bar_room : Double = scroll_bar_size + 2.0 * scroll_bar_inset

///|
/// How far in from the edge a bar runs along the pointer brings it out (the web's NEAR).
pub let scroll_bar_near : Double = 12.0

///|
/// How far round its thumb the pointer takes it (the web's thumb's `::before`, 4 out).
let scroll_bar_grab : Double = 4.0

///|
/// How far a bar keeps from what floats over what scrolls (the web's chat list's scroll-padding-bottom over its
/// composer: 8).
pub let scroll_bar_clear : Double = 8.0

///|
/// How long a bar shows after what it is for last scrolled (or the pointer left its edge, or let go of its thumb), and
/// how long it then takes to fade out, or to come in (the web's HIDE_AFTER, and its opacity's transition, ease-out).
pub let scrollbar_hold_ms : Double = 900.0

///|
pub let scrollbar_fade_ms : Double = 200.0

///|
/// How a bar shows (the file's head): what scrolls holds one; how long it scrolls the bar is told by it.
struct Bar {
  /// when it last came in (the frames' clock), and from how far it showed then
  mut in_at : Double
  mut in_from : Double
  /// the pointer along its edge (a mouse's), and when it last left it
  mut near : Bool
  mut near_left : Double
  /// its thumb held, and when it was last let go
  mut held : Bool
  mut let_go : Double
}

///|
fn Bar::new() -> Bar {
  { in_at: -1.0e9, in_from: 0.0, near: false, near_left: -1.0e9, held: false, let_go: -1.0e9 }
}

///|
/// When it starts to fade out, what it is for scrolled until `scrolled`: never while the pointer is at it or holds it.
fn Bar::hides_at(self : Bar, scrolled : Double) -> Double {
  if self.near || self.held {
    @double.infinity
  } else {
    dmax(scrolled, dmax(self.near_left, self.let_go)) + scrollbar_hold_ms
  }
}

///|
/// Whether bars are drawn at all: for a mouse, not a finger (the file's head).
fn bars_drawn() -> Bool {
  pointing() is Mouse
}

///|
/// How far it shows at `now` (0-1): coming in from when it came in, going from when it hides; a function of the time.
/// None for a finger.
fn Bar::shown(self : Bar, now : Double, scrolled : Double) -> Double {
  if !bars_drawn() {
    return 0.0
  }
  let hide = self.hides_at(scrolled)
  let come = fn(t : Double) {
    self.in_from + (1.0 - self.in_from) * Ease::at(Out, (t - self.in_at) / scrollbar_fade_ms)
  }
  if now < hide {
    come(now)
  } else {
    come(hide) * (1.0 - Ease::at(Out, (now - hide) / scrollbar_fade_ms))
  }
}

///|
/// It comes out at `now` (what it is for scrolls, the pointer comes to it), from how far it shows then, unless it is
/// out already.
fn Bar::wake(self : Bar, now : Double, scrolled : Double) -> Unit {
  if now >= self.hides_at(scrolled) {
    self.in_from = self.shown(now, scrolled)
    self.in_at = now
  }
}

///|
/// When it is at rest (-1: it is at `now`; inf: what it is for scrolls on to a time not known yet). A finger's none: at
/// rest.
fn Bar::rest(self : Bar, now : Double, scrolled : Double) -> Double {
  if !bars_drawn() {
    return -1.0
  }
  let t = if self.near || self.held {
    self.in_at + scrollbar_fade_ms
  } else {
    self.hides_at(scrolled) + scrollbar_fade_ms
  }
  if t > now {
    t
  } else {
    -1.0
  }
}

///|
/// A bar as a frame drew it, for the pointer: what it is for (its id; `foot`: along its foot), where what scrolls shows
/// (x0 y0 x1 y1) and how much of its top and foot what floats over it takes (Ctx::floated, along its right), its thumb
/// (x y w h), how far what scrolls goes for a point the thumb moves, and the thumb's id as a target.
struct BarAt {
  id : Int
  foot : Bool
  x0 : Double
  y0 : Double
  x1 : Double
  y1 : Double
  top_in : Double
  foot_in : Double
  tx : Double
  ty : Double
  tw : Double
  th : Double
  ratio : Double
  thumb : Int
}

///|
/// Whether (x, y) is along the edge its thumb runs along, within scroll_bar_near of it.
fn BarAt::near(self : BarAt, x : Double, y : Double) -> Bool {
  if x < self.x0 || x >= self.x1 || y < self.y0 || y >= self.y1 {
    return false
  }
  if self.foot {
    y >= self.y1 - scroll_bar_near
  } else {
    x >= self.x1 - scroll_bar_near
  }
}

///|
/// Where a thumb runs along an edge `len` long from `at`, what scrolls `size` long, what it holds `content`, scrolled
/// `off` into it, `start` and `end` of the edge kept clear: where the thumb starts, how long it is, how far what
/// scrolls goes for a point it moves. Pulled past an end, it stays at that end of its track.
fn bar_track(
  at : Double,
  len : Double,
  size : Double,
  content : Double,
  off : Double,
  start : Double,
  end : Double,
) -> (Double, Double, Double) {
  let (s, track) = if len - start - end < scroll_bar_least * 2.0 {
    (0.0, len)
  } else {
    (start, len - start - end)
  }
  let long = dmin(track, dmax(scroll_bar_least, track * size / content)) - scroll_bar_inset * 2.0
  let room = track - scroll_bar_inset * 2.0 - long
  let p = dclamp(off / (content - size), 0.0, 1.0)
  (at + s + scroll_bar_inset + p * room, long, (content - size) / dmax(room, 1.0))
}

///|
/// The target a bar's thumb is (what it is for `id`'s).
fn bar_thumb_id(id : Int) -> Int {
  mix(id, 0x5c801b)
}

///|
/// Box `i` floats over what scrolls under it (a page's bar, a composer, what is to be decided over it): the bars of
/// what it lies over, across it within its sides, keep clear of it and scroll_bar_clear more at the end it is nearer.
pub fn Ctx::floats_over(self : Ctx, i : Int) -> Unit {
  if i >= 0 && i < self.count {
    self.nodes[i].floats = true
  }
}

///|
/// What floats over what scrolls (Node's `floats`), from the nodes once all are made: the frame's `floating`.
fn Ctx::floating_found(self : Ctx) -> Unit {
  self.floating.clear()
  for i in 0..<self.count {
    if self.nodes[i].floats {
      self.floating.push(i)
    }
  }
}

///|
/// How much of the top and of the foot of what scrolls, `n`, in (x0 y0 x1 y1) what floats over it takes
/// (Ctx::floats_over; not what it holds itself, which scrolls with it), with scroll_bar_clear more each, and the
/// system's bars over the window's edges (the status bar, the navigation bar): 0 where nothing does.
fn Ctx::floated(self : Ctx, n : Node, x0 : Double, y0 : Double, x1 : Double, y1 : Double) -> (Double, Double) {
  let bars = system_bars()
  let mut top = dmax(0.0, bars.top - y0)
  let mut foot = dmax(0.0, y1 - (self.height - bars.bottom))
  for i in self.floating {
    let (t, f) = self.float_takes(i, x0, y0, x1, y1, Some(n))
    top = dmax(top, t)
    foot = dmax(foot, f)
  }
  (top, foot)
}

///|
/// What node `i`, floating, takes of the top and of the foot of (x0 y0 x1 y1), with scroll_bar_clear more: none where
/// it lies past its sides or ends, or is in `n` (what scrolls there: it scrolls with it).
fn Ctx::float_takes(
  self : Ctx,
  i : Int,
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
  n : Node?,
) -> (Double, Double) {
  let f = self.nodes[i]
  if f.fw <= 0.0 ||
    f.fh <= 0.0 ||
    f.x < x0 - 0.5 ||
    f.x + f.fw > x1 + 0.5 ||
    f.y >= y1 ||
    f.y + f.fh <= y0 {
    return (0.0, 0.0)
  }
  match n {
    Some(n) => {
      let mut p = f.parent
      while p >= 0 && !physical_equal(self.nodes[p], n) {
        p = self.nodes[p].parent
      }
      if p >= 0 {
        return (0.0, 0.0)
      }
    }
    None => ()
  }
  if f.y + f.fh / 2.0 < (y0 + y1) / 2.0 {
    (f.y + f.fh - y0 + scroll_bar_clear, 0.0)
  } else {
    (0.0, y1 - f.y + scroll_bar_clear)
  }
}

///|
/// Whether node `i` is node `root` or in it.
fn Ctx::under(self : Ctx, i : Int, root : Int) -> Bool {
  let mut p = i
  while p >= 0 {
    if p == root {
      return true
    }
    p = self.nodes[p].parent
  }
  false
}

///|
/// The bar of what scrolls `id` (a list's, a sideways or capped box's), until when what it is for scrolls, and the
/// theme it was built in.
fn Ctx::bar_owner(self : Ctx, id : Int) -> (Bar, Double, Theme)? {
  match self.lists.get(id) {
    Some(st) => Some((st.bar, st.shown_until(), st.theme))
    None =>
      match sideways.get(id) {
        Some(s) => Some((s.bar, s.bar_until(), s.theme))
        None => None
      }
  }
}

///|
/// The bars as the hand has them (near the pointer, held, let go), told as that changes (Ctx::bar_moved): what draws
/// them (Ctx::bar_at, as the frame is painted) reads it, painted again as it changes.
// kept across runs: only counts on
let bars_said : @signals.Signal[Int] = @signals.signal(0)

///|
/// What shows the bar of `id` (its list's or box's motion) told again: when it is at rest has changed. What it was
/// said to be stays (a fling, a glide: what moves with the bar).
fn Ctx::bar_moved(self : Ctx, id : Int) -> Unit {
  bars_said.set(@signals.untracked(fn() { bars_said.get() }) + 1)
  let again = fn(who : Mover, m : &Moving, what : String) {
    let mut said = what
    for e in self.movers {
      if physical_equal(e.who, who) {
        said = e.what
      }
    }
    self.moving_as(who, m, said)
  }
  match self.lists.get(id) {
    Some(st) => again(st.ease_mover, st as &Moving, "a list's scroll bar")
    None =>
      match sideways.get(id) {
        Some(s) => again(s.mover, s as &Moving, "a box scrolled inside a list and its scroll bar")
        None => ()
      }
  }
}

///|
/// The bar the last frame drew for `id`, if any.
fn Ctx::bar_drawn(self : Ctx, id : Int) -> BarAt? {
  let mut k = self.bars.length() - 1
  while k >= 0 {
    if self.bars[k].id == id {
      return Some(self.bars[k])
    }
    k = k - 1
  }
  None
}

///|
/// The bar of what scrolls in node `n` (a list, a sideways or capped box), its own clip pushed: where it runs, kept
/// for the pointer (the frame's bars), to draw once what it holds is drawn (Ctx::paint_bar). None where nothing of it
/// scrolls past its view, or it is one of boxes scrolled as one (drawn along the list they are in: Ctx::across_bars).
fn Ctx::bar_at(self : Ctx, n : Node) -> BarAt? {
  let b = self.bar_where(n)
  match b {
    // (kept with the frame's targets where they are found alone: Ctx::node_targets)
    Some(at) if !dr.targets_said => self.next_bars.push(at)
    _ => ()
  }
  b
}

///|
/// Where the bar of what scrolls in node `n` runs (Ctx::bar_at), nothing kept of it: what its thumb is a target where
/// (Ctx::bar_target), as the frame's targets are found.
fn Ctx::bar_where(self : Ctx, n : Node) -> BarAt? {
  // (where the hand has the bars: read so)
  bars_said.get() |> ignore
  let ((cx0, cy0, cx1, cy1), (_, r_tr, r_br, r_bl), _) = clip_at(clip_top())
  let x0 = dmax(n.x, cx0)
  let y0 = dmax(n.y, cy0)
  let x1 = dmin(n.x + n.fw, cx1)
  let y1 = dmin(n.y + n.fh, cy1)
  if x1 - x0 < 1.0 || y1 - y0 < 1.0 {
    return None
  }
  // along its right: what it holds, how far into it its view is
  let side = fn(content : Double, off : Double) -> BarAt? {
    let size = n.fh
    if content <= size + 1.0 {
      return None
    }
    // (what floats over it is read across its own box, as its ends are: the clip it shows in may cut its sides short
    // of what floats over it, a sidebar's list a point inside its panel's line, its band not cut so)
    let (top, foot) = self.floated(n, n.x, n.y, n.x + n.fw, n.y + n.fh)
    let (ty, th, ratio) = bar_track(n.y, n.fh, size, content, off, dmax(top, r_tr), dmax(foot, r_br))
    if th <= 0.0 {
      return None
    }
    Some({
      id: n.id,
      foot: false,
      x0,
      y0,
      x1,
      y1,
      top_in: dmax(0.0, n.y + top - y0),
      foot_in: dmax(0.0, y1 - (n.y + n.fh - foot)),
      tx: x1 - scroll_bar_inset - scroll_bar_size,
      ty,
      tw: scroll_bar_size,
      th,
      ratio,
      thumb: bar_thumb_id(n.id),
    })
  }
  let b = if n.kind == kind_list {
    match self.lists.get(n.id) {
      Some(st) if st.count > 0 => side(st.above(st.count), st.above(imin(st.anchor, st.count)) + st.anchor_off)
      _ => None
    }
  } else {
    match sideways.get(n.id) {
      Some(st) if st.max > 1.0 =>
        if st.vertical {
          side(n.fh + st.max, st.x)
        } else if st.across {
          self.across_seen.push((n.id, n.x, n.fw))
          None
        } else {
          // (along the view it is for: `bar_in` in from either side, what it holds as wide less that)
          let b = dclamp(st.bar_in, 0.0, dmax(0.0, n.fw / 2.0 - scroll_bar_least))
          let shows = (dmax(x0, n.x + b), y0, dmin(x1, n.x + n.fw - b), y1)
          foot_bar(n.id, n.x + b, n.fw - 2.0 * b, n.fw + st.max - 2.0 * b, st.x, shows, dmax(0.0, r_bl - b), dmax(0.0, r_br - b))
        }
      _ => None
    }
  }
  b
}

///|
/// A bar along the foot of what shows in (x0 y0 x1 y1) of a box `w` wide from `x` (scrolled sideways), what it holds
/// `content` wide, scrolled `off` into it, the corners at its foot rounded `r_bl` and `r_br`.
fn foot_bar(
  id : Int,
  x : Double,
  w : Double,
  content : Double,
  off : Double,
  shows : (Double, Double, Double, Double),
  r_bl : Double,
  r_br : Double,
) -> BarAt? {
  let (x0, y0, x1, y1) = shows
  let (tx, tw, ratio) = bar_track(x, w, w, content, off, r_bl, r_br)
  if tw <= 0.0 {
    return None
  }
  Some({
    id,
    foot: true,
    x0,
    y0,
    x1,
    y1,
    top_in: 0.0,
    foot_in: 0.0,
    tx,
    ty: y1 - scroll_bar_inset - scroll_bar_size,
    tw,
    th: scroll_bar_size,
    ratio,
    thumb: bar_thumb_id(id),
  })
}

///|
/// The bars of the boxes scrolled as one (Ctx::sideways `across`: a long text's lines, each a row of list `n`) drawn
/// since `from` in its rows: one each, along the list's foot under them, kept and drawn as any (its clip pushed).
fn Ctx::across_bars(self : Ctx, n : Node, from : Int, alpha : Double) -> Unit {
  for b in self.across_found(n, from) {
    if !dr.targets_said {
      self.next_bars.push(b)
    }
    self.paint_bar(b, alpha)
  }
}

///|
/// The bars along the foot of list `n` of the boxes in its rows scrolled as one, seen since `from` (Ctx::across_bars),
/// where each runs: those seen let go.
fn Ctx::across_found(self : Ctx, n : Node, from : Int) -> Array[BarAt] {
  let found : Array[BarAt] = []
  if self.across_seen.length() <= from {
    return found
  }
  let ((cx0, cy0, cx1, cy1), (_, _, r_br, r_bl), _) = clip_at(clip_top())
  let done : Array[Int] = []
  for k in from..<self.across_seen.length() {
    let (id, x, w) = self.across_seen[k]
    if done.contains(id) {
      continue
    }
    done.push(id)
    match sideways.get(id) {
      Some(st) => {
        let shows = (dmax(x, cx0), dmax(n.y, cy0), dmin(x + w, cx1), dmin(n.y + n.fh, cy1))
        match foot_bar(id, x, w, w + st.max, st.x, shows, r_bl, r_br) {
          Some(b) => found.push(b)
          None => ()
        }
      }
      None => ()
    }
  }
  self.across_seen.truncate(from)
  found
}

///|
/// Their thumbs' targets (Ctx::node_targets), where they show.
fn Ctx::across_targets(self : Ctx, n : Node, from : Int, alpha : Double) -> Unit {
  for b in self.across_found(n, from) {
    self.next_bars.push(b)
    if self.bar_shows(b) * alpha > 0.002 {
      self.bar_target(b)
    }
  }
}

///|
/// Bar `b` drawn as it shows now (none while hidden), its thumb a target for a mouse.
fn Ctx::paint_bar(self : Ctx, b : BarAt, alpha : Double) -> Unit {
  guard self.bar_owner(b.id) is Some((bar, until, theme)) else { return }
  // (the clock followed only while it fades in or out: shown or hidden, it is the same each frame, woken as it begins
  // to hide)
  let hide = bar.hides_at(until)
  let t = self.clock
  let fading = t < bar.in_at + scrollbar_fade_ms || (t >= hide && t < hide + scrollbar_fade_ms)
  if !fading && t < hide && hide < @double.infinity {
    self.wake_at_time(hide, later=true)
  }
  let shown = bar.shown(if fading { self.now() } else { t }, until) * alpha
  if shown <= 0.002 {
    return
  }
  // (lit while held or pointed at: what the pointer is over read as the hand says it as the frame begins, followed, so
  // that it is drawn again as the pointer comes over it or leaves it, whatever moved it there: hand.mbt)
  let lit = bar.held || hand.over.has(b.thumb)
  self.emit_rect(
    b.tx,
    b.ty,
    b.tw,
    b.th,
    scroll_bar_size / 2.0,
    theme.fg,
    0.0,
    0L,
    (if lit { 0.45 } else { 0.26 }) * shown,
  )
  self.bar_target(b)
}

///|
/// Bar `b`'s thumb a target for a mouse where it shows (Ctx::paint_bar draws it so): as the frame's targets are found.
fn Ctx::bar_target(self : Ctx, b : BarAt) -> Unit {
  if pointing() is Mouse {
    let ((cx0, cy0, cx1, cy1), _, _) = clip_at(clip_top())
    let g = scroll_bar_grab
    self.push_hit(
      b.thumb,
      dmax(b.tx - g, cx0),
      dmax(b.ty - g, cy0),
      dmin(b.tx + b.tw + g, cx1),
      dmin(b.ty + b.th + g, cy1),
    )
    |> ignore
  }
}

///|
/// How much of bar `b` shows now (0 hidden), as it is drawn (Ctx::paint_bar), what it wakes for aside.
fn Ctx::bar_shows(self : Ctx, b : BarAt) -> Double {
  guard self.bar_owner(b.id) is Some((bar, until, _)) else { return 0.0 }
  let hide = bar.hides_at(until)
  let t = self.clock
  let fading = t < bar.in_at + scrollbar_fade_ms || (t >= hide && t < hide + scrollbar_fade_ms)
  bar.shown(if fading { self.now() } else { t }, until)
}

///|
/// The bar the pointer (a mouse's) at (x, y) is along the edge of: that of what the wheel scrolls there (what scrolls
/// innermost there and goes further than it shows, past what only drags), when (x, y) is near the edge it runs along;
/// 0 none.
fn Ctx::bar_near_at(self : Ctx, x : Double, y : Double) -> Int {
  let ids = self.scroll_ids
  let rects = self.scroll_rects
  let mut k = ids.length() - 1
  while k >= 0 {
    let r = k * 4
    if x >= rects[r] && x < rects[r + 2] && y >= rects[r + 1] && y < rects[r + 3] {
      let id = ids[k]
      match self.bar_drawn(id) {
        Some(b) => return if b.near(x, y) { id } else { 0 }
        None =>
          // (what scrolls no further than it shows, or only drags: what it lies in; else what takes the wheel there)
          if !(drags.contains(id) || self.lists.contains(id) || sideways.contains(id)) {
            return 0
          }
      }
    }
    k = k - 1
  }
  0
}

///|
/// The pointer at (x, y) (-1: gone): the bar it is along the edge of comes out, the one it left goes after a while. A
/// mouse's only, not while it is pressed.
fn Ctx::bar_pointer(self : Ctx, x : Double, y : Double) -> Unit {
  if self.down {
    return
  }
  let at = if pointing() is Mouse && x >= 0.0 { self.bar_near_at(x, y) } else { 0 }
  if at == self.bar_near {
    return
  }
  match self.bar_owner(self.bar_near) {
    Some((b, _, _)) => {
      b.near = false
      b.near_left = self.clock
      self.bar_moved(self.bar_near)
    }
    None => ()
  }
  match self.bar_owner(at) {
    Some((b, until, _)) => {
      b.wake(self.clock, until)
      b.near = true
      self.bar_moved(at)
    }
    None => ()
  }
  self.bar_near = at
}

///|
/// A press on `target`: a bar's thumb (drawn last frame) is held from here, and the press is none of anything else's
/// (true).
fn Ctx::bar_press(self : Ctx, target : Int) -> Bool {
  if target == 0 {
    return false
  }
  let mut k = self.bars.length() - 1
  while k >= 0 {
    let b = self.bars[k]
    if b.thumb == target {
      match self.bar_owner(b.id) {
        Some((bar, until, _)) => {
          bar.wake(self.clock, until)
          bar.held = true
          // (what moved by itself stops where it is)
          match self.lists.get(b.id) {
            Some(st) => {
              st.stop()
              st.ease = 0.0
              st.ease_v = 0.0
              st.ease_done = 0.0
              st.glide = false
            }
            None =>
              match sideways.get(b.id) {
                Some(s) => {
                  s.vel = 0.0
                  s.rest = -1.0
                }
                None => ()
              }
          }
          self.bar_drag = b.id
          self.bar_moved(b.id)
          return true
        }
        None => return false
      }
    }
    k = k - 1
  }
  false
}

///|
/// The pointer holding a bar's thumb moved to (x, y): what it is for scrolled as far as the thumb went, by the bar's
/// track as last drawn.
fn Ctx::bar_drag_move(self : Ctx, x : Double, y : Double) -> Unit {
  // (in an old view drawn as nothing now: nothing moved by the pointer, old_bar_takes)
  if !old_bar_takes(self, self.bar_drag) {
    return
  }
  match self.bar_drawn(self.bar_drag) {
    Some(b) => {
      let d = (if b.foot { x - self.last_x } else { y - self.last_y }) * b.ratio
      if d == 0.0 {
        return
      }
      match self.lists.get(b.id) {
        Some(_) => self.scroll_list(b.id, d)
        None =>
          match sideways.get(b.id) {
            Some(s) => {
              let was = s.x
              s.x = dclamp(s.x + d, 0.0, dmax(s.max, 0.0))
              if s.x != was {
                self.sideways_scrolled(s)
              }
            }
            None => ()
          }
      }
    }
    None => ()
  }
}

///|
/// The thumb held let go: its bar shows a while more.
fn Ctx::bar_let_go(self : Ctx) -> Unit {
  match self.bar_owner(self.bar_drag) {
    Some((b, _, _)) => {
      b.held = false
      b.let_go = self.clock
      self.bar_moved(self.bar_drag)
    }
    None => ()
  }
  self.bar_drag = 0
}

///|
/// As a frame ends, its bars drawn: what holds a thumb gone, it is let go; the pointer's bar found again where it
/// rests (what moved under it).
fn Ctx::bars_frame_end(self : Ctx) -> Unit {
  if self.bar_drag != 0 {
    if self.bar_drawn(self.bar_drag) is None {
      self.bar_let_go()
    }
    return
  }
  self.bar_pointer(self.px, self.py)
}

///|
/// The bar of a column of the window's tree's that scrolls (@view.View::scrolls' `bar`), as these bars are: drawn for a
/// mouse alone, in the words' colour at 26% (45% pointed at or held), as wide, as far in, as long at least, brought out
/// as near, taken as far round, held and fading as long, coming and going as these do.
pub fn tree_scroll_bar() -> @view.ScrollBar {
  let at = fn(share : Double) {
    fn() {
      let fg = tree_theme().fg
      (fg & 0xFFFFFF00L) | ((fg & 0xFFL).to_double() * share).round().to_int64()
    }
  }
  {
    drawn: fn() { bars_drawn() },
    ink: at(0.26),
    ink_held: at(0.45),
    ease: fn(t) { Ease::at(Out, t) },
    size: scroll_bar_size,
    inset: scroll_bar_inset,
    least: scroll_bar_least,
    near: scroll_bar_near,
    grab: scroll_bar_grab,
    hold_ms: scrollbar_hold_ms,
    fade_ms: scrollbar_fade_ms,
  }
}
