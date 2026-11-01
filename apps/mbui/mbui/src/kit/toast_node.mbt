// Toasts as nodes of the window's tree (toaster's, made once): the toasts given at the window's foot in its middle, the
// newest last; each in as it is given (presence_in_ms, eased out) and out as it is no longer given, its time out, swiped
// away or its action taken (presence_out_ms); one given again by its id the same toast, saying what it says now; the
// time of all of them stopped while the pointer is over one or the focus in one, going on from what each had left as
// they leave; one swiped to the right past a third of it, or quick, put away. As one starts going out its time is let
// go (what is leaving takes no press, drag or focus: View::leave). Only the toasts take a press, not the room round
// them. Read out politely as they come (a status), in a region. What each looks like is its look's (toaster_node's
// `look`): this is how they live. When the next goes and when those moving are done, as toaster's are: toast_due,
// toast_rest.

///|
/// A toast as its look is given it: what it says now, how far in it is (0 … 1) and how far it is moved across (swiped,
/// or put away: going) as it is drawn; whether it is still there (not going out).
pub struct ToastNode {
  priv item : @signals.Signal[Toast]
  priv node : @view.View
  priv shown : ToastWay
  priv dx : @signals.Signal[Double]
  priv away_w : () -> Double
  priv live : @signals.Signal[Bool]
  priv focus_in : @signals.Signal[Bool]
  priv acted : () -> Unit
}

///|
/// What toast `s` says now (given again by its id: as it is given then), followed.
pub fn ToastNode::toast(self : ToastNode) -> Toast {
  self.item.get()
}

///|
/// How far toast `s` is in (0 … 1) as it is drawn.
pub fn ToastNode::t(self : ToastNode) -> Double {
  let k = self.shown.shown(self.node)
  if k > 1.0 {
    1.0
  } else if k < 0.0 {
    0.0
  } else {
    k
  }
}

///|
/// How far toast `s` is moved across as it is drawn: the finger's way while it is held; going out, put away as far as
/// it has gone of half the toasts' width (toaster's: not the finger's way on top of it).
pub fn ToastNode::dx(self : ToastNode) -> Double {
  if self.live.get() {
    self.dx.get()
  } else {
    (1.0 - self.t()) * (self.away_w)() * 0.5
  }
}

///|
/// Whether toast `s` is still there (not going out), followed.
pub fn ToastNode::live(self : ToastNode) -> Bool {
  self.live.get()
}

///|
/// Node `a` (in the toast's look) its action: pressed, the toast's action taken (once) and it goes; the focus on it,
/// the toasts' time stopped; read out a button `label` says, as it says it.
pub fn ToastNode::action(self : ToastNode, a : @view.View, label : () -> String) -> @view.View {
  let s = self
  a
  .presses(Is(true))
  .focusable(Is(true))
  .says(By(fn() { Some(@view.said(Button, label=label())) }))
  .on_press(fn() { (s.acted)() })
  |> ignore
  a.reacts(fn() { a.focused() }, fn(f) { s.focus_in.set(f) })
  a.owns(fn() { s.focus_in.set(false) }) |> ignore
  a
}

///|
/// While `on` says so of node `n`, one more holding the toasts' time (`held`), let go with it.
fn hold_while(n : @view.View, held : @signals.Signal[Int], on : () -> Bool) -> Unit {
  let had = Ref(false)
  n.reacts(on, fn(h) {
    if h != had.val {
      had.val = h
      let d = if h { 1 } else { -1 }
      held.set(@signals.untracked(fn() { held.get() }) + d)
    }
  })
  n.owns(fn() {
    if had.val {
      had.val = false
      held.set(@signals.untracked(fn() { held.get() }) - 1)
    }
  })
  |> ignore
}

///|
/// When what each toast of a toaster_node does next is due (toast_due, toast_rest): by the toast's id, the moment its
/// time is out (-1 while it is stopped or let go) and the moment its way in or out ends (-1 where it goes none now).
priv struct ToastTimes {
  key : String
  rows : Map[String, (() -> Double, () -> Double)]
}

///|
/// The toaster_nodes there are, by their key (toast_due's, toast_rest's).
// kept across runs: each put as its toaster is made, taken out as it is let go
let toast_nodes : Map[String, ToastTimes] = Map([])

///|
/// When the next of toaster_node `key`'s toasts goes by itself (its time out), -1 where none is counting (none, or
/// their time stopped); None where there is no toaster_node `key`.
fn toast_node_due(key : String) -> Double? {
  guard toast_nodes.get(key) is Some(t) else { return None }
  let mut due = -1.0
  for _, r in t.rows {
    let d = (r.0)()
    if d >= 0.0 && (due < 0.0 || d < due) {
      due = d
    }
  }
  Some(due)
}

///|
/// When toaster_node `key`'s toasts are done coming in and going out, -1 where none moves; None where there is no
/// toaster_node `key`.
fn toast_node_rest(key : String) -> Double? {
  guard toast_nodes.get(key) is Some(t) else { return None }
  let mut rest = -1.0
  for _, r in t.rows {
    let e = (r.1)()
    if e > rest {
      rest = e
    }
  }
  Some(rest)
}

///|
/// The toasts `toasts` gives as it changes in `parent`, over all of it: `bottom` over the window's foot in its middle,
/// as wide as the window less 16 each side and `w` at most; each staying `duration(toast)` ms (as it says now); `look`
/// building each (its ToastNode); `acted` and `gone` told with a toast's id as its action is taken and as it goes by
/// itself (its time out, swiped away), each once, each its own. Read out as a region named `label`; its times as
/// `key`'s (toast_due, toast_rest). The node.
pub fn toaster_node(
  parent : @view.View,
  toasts : () -> Array[Toast],
  duration : (Toast) -> Double,
  bottom : () -> Double,
  look : (@view.View, ToastNode) -> Unit,
  acted : (String) -> Unit,
  gone : (String) -> Unit,
  key? : String = "toast",
  w? : Double = 560.0,
  label? : String = "通知",
) -> @view.View {
  // (how many hold the time of all of them: the pointer over one, the focus in one)
  let held = @signals.signal(0, same=fn(a, b) { a == b })
  let times : ToastTimes = { key, rows: Map([]) }
  toast_nodes[key] = times
  parent.box(fn(v) {
    v.owns(fn() {
      if toast_nodes.get(key) is Some(t) && physical_equal(t, times) {
        toast_nodes.remove(key)
      }
    })
    |> ignore
    let width = fn() {
      let ww = v.window().0
      if w < ww - 32.0 {
        w
      } else {
        ww - 32.0
      }
    }
    // (over all else of the window, the old frame's sheets and dialogs and the tree's modal layers too: View::over_all)
    v.over(Is(true)).over_all(Is(true)) |> ignore
    // (while one is given, and as the last given goes out: none, nothing of it, as toaster's builds nothing then)
    v.show(fn() { !toasts().is_empty() }, fn(room) {
      room.grow(Is(1.0)).lines_up(Is(Some(Middle))).padding(By(fn() { (0.0, 0.0, 0.0, bottom()) })) |> ignore
      room.box(fn(s) { s.grow(Is(1.0)) |> ignore }) |> ignore
      room.box(fn(region) {
        region
        .width(By(fn() { Some(width()) }))
        .gap(Is(8.0))
        .lines_up(Is(Some(Middle)))
        .says(Is(Some(@view.said(Region, label~))))
        |> ignore
        region.each(
          toasts,
          fn(to) { to.id },
          fn(row, item) { toast_lives(row, item, duration, held, times, width, look, acted, gone) },
          leave=presence_out_ms,
        )
      })
      |> ignore
    }, leave=presence_out_ms)
  })
}

///|
/// Toast `item` in `row` (toaster_node's): its way in and out, its time, its swipe; built by `look`.
fn toast_lives(
  row : @view.View,
  item : @signals.Signal[Toast],
  duration : (Toast) -> Double,
  held : @signals.Signal[Int],
  times : ToastTimes,
  width : () -> Double,
  look : (@view.View, ToastNode) -> Unit,
  acted : (String) -> Unit,
  gone : (String) -> Unit,
) -> Unit {
  let id = @signals.untracked(fn() { item.get().id })
  let shown = ToastWay::new(0.0, times.key + "/" + id)
  shown.go(row, 1.0, @motion.tween(presence_in_ms, ease=Out))
  let live = @signals.signal(true, same=fn(a, b) { a == b })
  let dx = @signals.signal(0.0, same=fn(a, b) { a == b })
  let focus_in = @signals.signal(false, same=fn(a, b) { a == b })
  // its time: how long it stays (as it says now), what is left of it while it is stopped, when it is out while it
  // counts (None: stopped: one moment kept, not worked out again as nothing changes), its wake (let go as it stops, as
  // it goes)
  let stays = Ref(@signals.untracked(fn() { duration(item.get()) }))
  let left = Ref(stays.val)
  let ends : Ref[Double?] = Ref(None)
  let due : Ref[() -> Unit] = Ref(fn() {  })
  let stop = fn(at : Double) {
    (due.val)()
    due.val = fn() {  }
    match ends.val {
      Some(e) => {
        left.val = e - at
        ends.val = None
      }
      None => ()
    }
  }
  // (going out from this moment: its time let go; told once, its own)
  let leave = fn(f : (String) -> Unit) {
    if @signals.untracked(fn() { live.get() }) {
      live.set(false)
      stop(row.cause_at())
      f(id)
    }
  }
  // (the one place its time is counted from: as it is made, as the toasts are held and let go, as it says it stays
  // otherwise, as it goes)
  row.reacts(fn() { (held.get() > 0 || !live.get(), duration(item.get())) }, fn(now) {
    let (stopped, d) = now
    let at = row.cause_at()
    let more = d - stays.val
    stays.val = d
    // (its time on screen: what is shown does not wait for it, as toaster's said `later`; toast_due says it)
    let count = fn(e : Double) {
      (due.val)()
      ends.val = Some(e)
      due.val = row.at_moment(e, fn() { leave(gone) }, later=true)
    }
    match (stopped, ends.val) {
      (true, _) => {
        stop(at)
        left.val = left.val + more
      }
      // (counting on: its moment as it was, moved only by how much longer it says it stays)
      (false, Some(e)) => if more != 0.0 { count(e + more) }
      (false, None) => {
        left.val = left.val + more
        count(at + left.val)
      }
    }
  })
  // (as it starts going out, no longer given, and as it comes back given again as it goes: View::leaving, told then)
  let was_leaving = Ref(false)
  row.reacts(
    fn() { row.leaving() },
    fn(l) {
      if l && !was_leaving.val {
        live.set(false)
        shown.go(row, 0.0, @motion.tween(presence_out_ms, ease=Leave))
      } else if !l && was_leaving.val {
        live.set(true)
        shown.go(row, 1.0, @motion.tween(presence_in_ms, ease=Out))
      }
      was_leaving.val = l
    },
  )
  // (done, as of `now`, when its way in or out ends and, going out, as it is let go: View::leaves_at, the later; let go
  // with what holds it, done: ToastWay's `alive`)
  shown.rest = fn(now) {
    guard shown.alive else { return -1.0 }
    let way = if shown.way.ends_at() >= 0.0 && shown.way.end() > now { shown.way.end() } else { -1.0 }
    let gone = row.leaves_at()
    if gone > now && gone > way {
      gone
    } else {
      way
    }
  }
  times.rows[id] = (
    fn() { ends.val.unwrap_or(-1.0) },
    fn() { (shown.rest)(row.logic_at()) },
  )
  row.owns(fn() {
    (due.val)()
    (shown.due)()
    // (said to move no more: nothing of it is drawn, whatever its way would have done)
    shown.alive = false
    match times.rows.get(id) {
      Some(_) => times.rows.remove(id)
      None => ()
    }
  })
  |> ignore
  let s : ToastNode = { item, node: row, shown, dx, away_w: width, live, focus_in, acted: fn() { leave(acted) } }
  row.box(fn(b) {
    b
    .presses(Is(true))
    .says(By(fn() {
      let to = item.get()
      Some(@view.said(Status, label=to.title, description=to.description))
    }))
    |> ignore
    // (held: the pointer on it (on its action too, nothing over it there) or the focus on its action, one of the toasts holding them all)
    hold_while(b, held, fn() { b.pointed_in() || focus_in.get() })
    // swiped: followed while held, put away past a third of it (as wide as it is) or quick, else back
    let x0 = Ref(0.0)
    let last = Ref((0.0, 0.0))
    let quick = Ref(0.0)
    b.on_drag(fn(d) {
      match d.kind {
        Down => {
          x0.val = d.x
          last.val = (d.x, d.at)
          quick.val = 0.0
        }
        Moved => {
          dx.set(if d.x - x0.val > 0.0 { d.x - x0.val } else { 0.0 })
          let (lx, lt) = last.val
          if d.at > lt {
            quick.val = (d.x - lx) / (d.at - lt)
          }
          last.val = (d.x, d.at)
        }
        Up =>
          if d.x - x0.val > d.w / 3.0 || quick.val > 0.5 {
            leave(gone)
          } else {
            dx.set(0.0)
          }
        Off => dx.set(0.0)
      }
    })
    |> ignore
    look(b, s)
  })
  |> ignore
}

///|
/// A way a toast's look goes (motion's Way, from the moment of its cause, drawn where it is at the moment it is drawn
/// while it goes): what reads it told as it ends. Said to move as it sets out, by `name` (the toaster's key and the
/// toast's id, as toaster's presence is: Tester::rest_of, Tester::moving), till `rest` says it is done as of the
/// moment the frames are at (its end, and going out its letting go); let go with its toast (`alive` no more), done.
priv struct ToastWay {
  way : @motion.Way
  ended : @signals.Signal[Int]
  mut due : () -> Unit
  mover : @ui.Mover
  name : String
  mut rest : (Double) -> Double
  mut alive : Bool
}

///|
fn ToastWay::new(v : Double, name : String) -> ToastWay {
  { way: @motion.Way::new(v), ended: @signals.signal(0), due: fn() {  }, mover: @ui.Mover::new(), name, rest: fn(_) { -1.0 }, alive: true }
}

///|
impl @ui.Moving for ToastWay with rest_at(self, now, frame) {
  // (as of the moment the frames are at, as any of what is said to move answers: Ctx::motion_owed's)
  ignore(frame)
  (self.rest)(now)
}

///|
fn ToastWay::go(self : ToastWay, n : @view.View, to : Double, spec : @motion.Spec) -> Unit {
  (self.due)()
  self.way.go(to, spec, at=n.cause_at())
  self.due = if self.way.ends_at() >= 0.0 {
    n.at_moment(self.way.end(), fn() { self.ended.set(@signals.untracked(fn() { self.ended.get() }) + 1) })
  } else {
    fn() {  }
  }
  @ui.current().moving_as(self.mover, self as &@ui.Moving, "Anim \"\u{2}presence/" + self.name + "\" to \{to}")
}

///|
fn ToastWay::shown(self : ToastWay, n : @view.View) -> Double {
  self.way.said()
  self.ended.get() |> ignore
  if self.way.goes_at(n.logic_at()) {
    self.way.value_at(n.drawn_at())
  } else {
    self.way.target()
  }
}
