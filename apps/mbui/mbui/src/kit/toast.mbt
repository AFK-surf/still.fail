// Toasts (Radix's Toast): short messages at the bottom of the window that go by themselves, the list of them the
// view's; or at its top (`top`), dropping in from over its edge (a phone's: as its own notices come), the newest
// first, flicked up to put one away. Each goes once it has shown `duration` ms; the time stops while the pointer is over them or the focus is in
// one (so that it can be read and acted on). Each has a close button and may have an action; a swipe to the right
// (past a third of it, or quick) puts it away. Read out politely as they come (a status). A toast put away comes out
// by `presence` before it is gone. (Radix's F8, the key to their region, waits for the hosts to send function keys.)

///|
/// A toast: its id (the view's, unique among those showing), its title, its description ("" none), its action's
/// words ("" none).
pub(all) struct Toast {
  id : String
  title : String
  description : String
  action : String
} derive(Eq, Show)

///|
/// A toast of `title` (its id `id`).
pub fn toast(id : String, title : String, description? : String = "", action? : String = "") -> Toast {
  { id, title, description, action }
}

///|
/// What a toast's look is given: the toast, how far in it is (0 … 1; past 1 on a spring that goes past it), how far it
/// is swiped (to the right; at the top, up: `dy`, negative), pointed at, whether the toasts are at the window's top.
pub(all) struct ToastState {
  toast : Toast
  t : Double
  dx : Double
  dy : Double
  hovered : Bool
  top : Bool
}

///|
/// What the toasts report: those still showing (what the view keeps), and the id of the one whose action was taken
/// (it goes too).
pub(all) struct Toasts {
  open : Array[Toast]
  acted : String?
}

///|
/// A viewport's toasts as drawn last frame, in order, those of them put away (coming out), and where the pointer was
/// as each came (a pointer that has not moved since is not on it: it came under it).
priv struct Kept {
  mut drawn : Array[Toast]
  gone : Map[String, Bool]
  came : Map[String, (Double, Double)]
}

///|
/// `key`'s toasts (see the file's head), `toasts` showing, the newest last, `bottom` above the window's foot in its
/// middle (or `top` under the window's top, the newest first: 0 or more), at most `w` wide; each goes after `duration`
/// ms; coming in by `enter`; named `label` for the semantics tree, and their close buttons `close_label`.
pub fn toaster(
  c : @ui.Ctx,
  key : String,
  toasts : Array[Toast],
  duration? : Double = 5000.0,
  w? : Double = 560.0,
  bottom? : Double = 24.0,
  top? : Double = -1.0,
  enter? : @motion.Spec = @motion.tween(presence_in_ms, ease=Out),
  label? : String = "通知",
  close_label? : String = "关闭",
  look? : (@ui.Ctx, ToastState, () -> Unit, () -> Unit) -> Unit = toast_look,
) -> Toasts {
  install()
  let vid = c.id(key)
  let kept = match kit.val.toasts.get(vid) {
    Some(k) => k
    None => {
      let k = { drawn: [], gone: {}, came: {} }
      kit.val.toasts[vid] = k
      k
    }
  }
  // as drawn last frame (those no longer given put away), then the new ones
  let order : Array[Toast] = []
  for to in kept.drawn {
    match toasts.search_by(fn(x) { x.id == to.id }) {
      Some(k) => order.push(toasts[k])
      None => {
        kept.gone[to.id] = true
        order.push(to)
      }
    }
  }
  let (px, py, _) = c.pointer()
  for to in toasts {
    if !kept.drawn.iter().any(fn(x) { x.id == to.id }) {
      order.push(to)
      if !kept.came.contains(to.id) {
        kept.came[to.id] = (px, py)
      }
    }
  }
  let open : Array[Toast] = []
  let mut acted : String? = None
  let drawn : Array[Toast] = []
  // (when the next of them goes, as this frame has it: toast_due)
  let mut due = -1.0
  if order.is_empty() {
    kept.drawn = drawn
    kit.val.toast_dues.remove(key)
    return { open, acted }
  }
  // the time stops while the pointer is over one (a mouse over it, a finger on it: Ctx::hand_on; not one that came
  // under where the pointer rests, unmoved since) or the focus is in one
  let paused = order.iter().any(fn(to) {
    let moved = match kept.came.get(to.id) {
      Some((x, y)) => x != px || y != py
      None => true
    }
    (moved && c.hand_on(c.id(key + "/" + to.id))) || focus_in(c, key, to.id)
  })
  let (ww, _) = c.window_size()
  let width = dmin(w, ww - 32.0)
  let at_top = top >= 0.0
  let (room_top, room_foot) = if at_top { (top, 0.0) } else { (0.0, bottom) }
  // (at the top the newest first, nearest the edge it comes from)
  let order = if at_top { order.rev() } else { order }
  let mut region = 0
  c.overlay(key, escape=false, outside=false, initial_focus=0, fn() {
    // at the bottom of the window, in its middle (still.fail's), or at its top; only the toasts take a press, not the
    // room round them
    c.box(
      w=Fill(1.0),
      h=Fill(1.0),
      justify=if at_top { JStart } else { JEnd },
      align=ACenter,
      pb=room_foot,
      pt=room_top,
      fn() {
    region = c.box(
      w=Px(width),
      gap=8.0,
      align=ACenter,
      fn() {
      for to in order {
        let k = key + "/" + to.id
        let tid = c.id(k)
        let mut live = !kept.gone.contains(to.id)
        let mut dx = 0.0
        let mut dy = 0.0
        if live {
          let mut away = after(c, k, !paused, duration, keep=true, later=true)
          let d = c.held_due(k)
          if d >= 0.0 && (due < 0.0 || d < due) {
            due = d
          }
          // the swipe: followed while held, put away past a third or quick, else back (at the top: up, past a third
          // of its height; down, it gives a little)
          match c.drag_of(tid) {
            Some(d) => {
              if at_top {
                if d.down && d.moving {
                  let up = d.y - d.y0
                  dy = if up < 0.0 { up } else { up * toast_give }
                }
                let th = match c.rect_of(tid) {
                  Some((_, _, _, h)) if h > 0.0 => h
                  _ => 40.0
                }
                if d.take_end() && (d.y0 - d.y > th / 3.0 || d.vy < -0.5) {
                  away = true
                }
              } else {
                if d.down && d.moving {
                  dx = dmax(0.0, d.x - d.x0)
                }
                // a third of it (as wide as its words)
                let tw = match c.rect_of(tid) {
                  Some((_, _, w, _)) if w > 0.0 => w
                  _ => width
                }
                if d.take_end() && (d.x - d.x0 > tw / 3.0 || d.vx > 0.5) {
                  away = true
                }
              }
            }
            None => ()
          }
          if away {
            kept.gone[to.id] = true
            live = false
          }
        }
        let p = presence(c, k, live, enter~)
        if !p.built {
          kept.gone.remove(to.id)
          kept.came.remove(to.id)
          continue
        }
        drawn.push(to)
        let st = {
          toast: to,
          t: p.t,
          dx: if live || at_top { dx } else { (1.0 - p.t) * width * 0.5 },
          dy,
          hovered: c.lit(tid),
          top: at_top,
        }
        let i = c.drag_area(if live { tid } else { 0 }, axis=if at_top { Vertical } else { Horizontal }, fn() {
          look(
            c,
            st,
            fn() {
              if live && to.action != "" && toast_button(c, k + "/action", to.action, to.action, false) {
                acted = Some(to.id)
                live = false
              }
            },
            fn() {
              if live && toast_button(c, k + "/close", "✕", close_label, true) {
                live = false
              }
            },
          )
        })
        c.semantics(i, Status, label=to.title, description=to.description)
        if live {
          open.push(to)
        } else {
          kept.gone[to.id] = true
        }
      }
    })
    })
    |> ignore
    c.semantics(region, Region, label~)
  })
  |> ignore
  kept.drawn = drawn
  if due >= 0.0 {
    kit.val.toast_dues[key] = due
  } else {
    kit.val.toast_dues.remove(key)
  }
  { open, acted }
}

///|
/// How much of a pull down a toast at the top follows (it is where it goes already).
let toast_give : Double = 0.25

///|
/// Whether the keyboard's focus is on toast `id`'s action or close button.
fn focus_in(c : @ui.Ctx, key : String, id : String) -> Bool {
  c.has_focus(c.id(key + "/" + id + "/action")) || c.has_focus(c.id(key + "/" + id + "/close"))
}

///|
/// A toast's default look (still.fail's): the primary ink, a corner of 20; its title over its description (fainter)
/// over what `action` builds (its action), what `close` builds (its close button) in its top right corner; it fades
/// and rises as it comes in (at the top, comes down), slides away as it goes out and is swiped.
pub fn toast_look(c : @ui.Ctx, s : ToastState, action : () -> Unit, close : () -> Unit) -> Unit {
  let t = c.theme()
  let k = if s.t > 1.0 { 1.0 } else if s.t < 0.0 { 0.0 } else { s.t }
  let rise = if s.top { s.dy - (1.0 - k) * 12.0 } else { (1.0 - k) * 12.0 }
  c.box(
    // a small panel's: 6 in, its words 10 further (16), its buttons at the 6 in its corners, concentric
    dir=Row,
    pad=6.0,
    gap=8.0,
    align=AStart,
    bg=t.primary,
    radius=20.0,
    max_w=560.0,
    shadow=24.0,
    shadow_color=t.shadow,
    shadow_y=8.0,
    tx=s.dx,
    ty=rise,
    opacity=k,
    fn() {
      // the first line of words on the close button's middle
      c.box(fn() {
        c.box(gap=2.0, padx=10.0, pt=4.0, pb=pick(s.toast.action != "", 0.0, 4.0), fn() {
          c.text(s.toast.title, size=t.font, weight=500, color=t.on_primary, line=20.0) |> ignore
          if s.toast.description != "" {
            c.text(s.toast.description, size=t.font_sm, color=@ui.alpha(t.on_primary, 0.7), line=18.0) |> ignore
          }
        })
        |> ignore
        if s.toast.action != "" {
          c.box(dir=Row, pt=8.0, fn() { action() }) |> ignore
        }
      })
      |> ignore
      close()
    },
  )
  |> ignore
}

///|
/// A button on a toast (its look's): `text` on a faint ground of the ink's words (`round`: a circle, the close
/// button's), named `label`; whether it was pressed.
pub fn toast_button(c : @ui.Ctx, key : String, text : String, label : String, round : Bool) -> Bool {
  let t = c.theme()
  let id = c.id(key)
  let r = c.interact(id)
  let i = c.box(
    id~,
    h=Px(28.0),
    min_w=28.0,
    // its words on the toast's words' line (6 + 10)
    padx=if round { 0.0 } else { 10.0 },
    radius=14.0,
    align=ACenter,
    justify=JCenter,
    bg=@ui.alpha(t.on_primary, if r.pressed { 0.24 } else if r.hovered { 0.18 } else if round { 0.0 } else { 0.12 }),
    fn() {
      c.text(text, size=if round { 12.0 } else { t.font }, weight=500, color=@ui.alpha(t.on_primary, if round { 0.7 } else { 1.0 }), wrap=false)
      |> ignore
      focus_ring(c, r.focus_shown, r.rect, 14.0)
    },
  )
  c.semantics(i, Button, id~, label~, actions=[Activate])
  r.clicked
}

///|
/// When the next of `key`'s toasts (toaster) goes, its time out, as the last frame had it: the frames' clock; -1 when
/// none shows, or each is paused (the pointer over them, the focus in one). A toast's time is a wake said `later` (what
/// is shown does not wait for it): what goes on to it by name, as a run's end goes on to every time told (a toast left
/// on screen at the end not decided by where the end's last frame happens to fall).
pub fn toast_due(key : String) -> Double {
  kit.val.toast_dues.get(key).unwrap_or(-1.0)
}

///|
/// When the toasts of `key` (toaster) have done moving, those going away among them (their exit by `presence`): the
/// frames' clock; -1 when none moves, +inf when one is told and has not started. What a test runs to after a toast
/// goes (its time out, closed, swiped). Its time on screen is a timer, not a motion: toast_due, or `run_for` the
/// toaster's duration.
pub fn toast_rest(key : String) -> Double {
  @ui.rest_of("\u{2}presence/" + key + "/")
}
