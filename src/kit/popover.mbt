// What opens by a trigger, put beside it (Ctx::place, Radix's Popper: on a side, flipped and moved to stay in the
// window): a popover (Radix's Popover: opened by the view, as its trigger is pressed; the focus goes into it; Escape,
// the back and a press outside but on its trigger close it), a hover card (Radix's HoverCard: for a mouse, opened
// once the pointer has rested on its trigger, kept open while it is over the trigger or the card), a tooltip (Radix's
// Tooltip: words about its trigger, shown once the pointer has rested on it or at once when the keyboard's focus comes
// to it; shut by a press on the trigger and by Escape until the pointer leaves; one shown soon after another closed
// skips the wait). They come in from their side by `presence`.

///|
/// What a popover's, a hover card's or a tooltip's look is given: the side of its trigger it went on, how far in it
/// is (0 … 1).
pub(all) struct PopState {
  side : @ui.Side
  t : Double
}

///|
/// `key`'s popover (see the file's head), `open` or not, by the trigger `anchor` (its id), on its `side` (lined up
/// `along` it, `offset` away), named `label` for the semantics tree; `modal`: the page under it takes no press and
/// Tab stays in it. Whether it is open now.
pub fn popover(
  c : @ui.Ctx,
  key : String,
  open : Bool,
  anchor : Int,
  side? : @ui.Side = Bottom,
  along? : @ui.Along = Middle,
  offset? : Double = 6.0,
  label? : String = "",
  modal? : Bool = false,
  look? : (@ui.Ctx, PopState, () -> Unit) -> Unit = popover_look,
  body : () -> Unit,
) -> @ui.Changed[Bool] {
  let p = presence(c, key, open)
  let mut now = open
  if p.built {
    let o = c.overlay(key, modal~, anchor~, initial_focus=-1, inert=p.leaving(), fn() {
      beside(c, key, anchor, side, along, offset, p.t, Dialog, label, look, body)
    })
    if o.dismissed is Some(_) {
      now = false
    }
  }
  { value: now, response: { ..@ui.Response::none(), id: c.id(key), changed: told(c, now != open) } }
}

///|
/// `key`'s hover card (see the file's head) for the trigger `trigger` (its id): opened once a mouse has rested on the
/// trigger `open_delay` ms, closed `close_delay` ms after it has left both, and by Escape and a press outside. Whether
/// it is open.
pub fn hover_card(
  c : @ui.Ctx,
  key : String,
  trigger : Int,
  open_delay? : Double = 700.0,
  close_delay? : Double = 300.0,
  side? : @ui.Side = Bottom,
  along? : @ui.Along = Middle,
  offset? : Double = 6.0,
  look? : (@ui.Ctx, PopState, () -> Unit) -> Unit = popover_look,
  body : () -> Unit,
) -> Bool {
  install()
  let id = c.id(key)
  let was = kit.val.opens.get(id).unwrap_or(false)
  let on_trigger = c.hovered(trigger)
  let on_card = was && pointer_in(c, c.id(key + "/panel"))
  let mut open = if was {
    !after(c, key + "/out", !(on_trigger || on_card), close_delay)
  } else {
    after(c, key + "/in", on_trigger, open_delay)
  }
  let p = presence(c, key, open)
  if p.built {
    let o = c.overlay(key, anchor=trigger, initial_focus=0, inert=p.leaving(), fn() {
      beside(c, key, trigger, side, along, offset, p.t, Group, "", look, body)
    })
    if o.dismissed is Some(_) {
      open = false
    }
  }
  if open != was {
    // from nothing again, the next way
    ignore(after(c, key + "/in", false, open_delay))
    ignore(after(c, key + "/out", false, close_delay))
  }
  ignore(told(c, open != was))
  kit.val.opens[id] = open
  open
}

///|
/// `key`'s tooltip (see the file's head) for the trigger `trigger` (its id), saying `text`: shown once a mouse has
/// rested on it `delay` ms (at once within `skip` ms of another closing), or at once while it has the focus by the
/// keyboard. Whether it shows.
pub fn tooltip(
  c : @ui.Ctx,
  key : String,
  trigger : Int,
  text : String,
  delay? : Double = 700.0,
  skip? : Double = 300.0,
  side? : @ui.Side = Top,
  along? : @ui.Along = Middle,
  offset? : Double = 6.0,
  look? : (@ui.Ctx, PopState, String) -> Unit = tooltip_look,
) -> Bool {
  install()
  let id = c.id(key)
  let was = kit.val.opens.get(id).unwrap_or(false)
  let hovered = c.hovered(trigger)
  let focused = c.focus_shown(trigger)
  // pressed, or Escape: shut until the pointer and the focus have left it
  if c.pressed(trigger) || c.clicked(trigger) {
    kit.val.shut[id] = true
  }
  if !hovered && !focused {
    kit.val.shut.remove(id)
  }
  let shut = kit.val.shut.contains(id)
  let soon = kit.val.tip_closed >= 0.0 && c.now() - kit.val.tip_closed < skip
  let rested = after(c, key + "/in", hovered, if soon { 0.0 } else { delay })
  let mut open = !shut && (focused || rested || (was && hovered))
  let p = presence(c, key, open, enter=@motion.tween(100.0, ease=Out))
  if p.built {
    let o = c.overlay(key, anchor=trigger, outside=false, initial_focus=0, inert=p.leaving(), fn() {
      beside(c, key, trigger, side, along, offset, p.t, Tooltip, text, fn(c, s, _) { look(c, s, text) }, fn() {  })
    })
    if o.dismissed is Some(_) {
      kit.val.shut[id] = true
      open = false
    }
  }
  if was && !open {
    kit.val.tip_closed = c.now()
  }
  ignore(told(c, open != was))
  kit.val.opens[id] = open
  open
}

///|
/// Whether the pointer is over what `id` drew last frame.
fn pointer_in(c : @ui.Ctx, id : Int) -> Bool {
  match c.rect_of(id) {
    Some((x, y, w, h)) => {
      let (px, py, _) = c.pointer()
      px >= x && px < x + w && py >= y && py < y + h
    }
    None => false
  }
}

///|
/// Layer `key`'s content by the trigger `anchor` (Ctx::place, by its size last frame; the first, unseen, a frame is
/// asked for), coming in from its side, named for the semantics tree.
fn beside(
  c : @ui.Ctx,
  key : String,
  anchor : Int,
  side : @ui.Side,
  along : @ui.Along,
  offset : Double,
  t : Double,
  role : @ui.Role,
  label : String,
  look : (@ui.Ctx, PopState, () -> Unit) -> Unit,
  body : () -> Unit,
) -> Unit {
  let pid = c.id(key + "/panel")
  let ar = c.rect_of(anchor).unwrap_or((0.0, 0.0, 0.0, 0.0))
  let (pw, ph, seen) = match c.rect_of(pid) {
    Some((_, _, w, h)) if w > 0.0 => (w, h, true)
    _ => (0.0, 0.0, false)
  }
  if !seen {
    c.request_frame()
  }
  let (x, y, went) = c.place(ar, pw, ph, side~, along~, offset~)
  let k = if t > 1.0 { 1.0 } else if t < 0.0 { 0.0 } else { t }
  // from 4 towards its trigger
  let back = (1.0 - k) * 4.0
  let (dx, dy) = match went {
    Top => (0.0, back)
    Bottom => (0.0, -back)
    Left => (back, 0.0)
    Right => (-back, 0.0)
  }
  let i = c.box(id=pid, tx=x + dx, ty=y + dy, opacity=if seen { dmax(k, 0.003) } else { 0.003 }, fn() {
    look(c, { side: went, t }, body)
  })
  c.semantics(i, role, label~)
}

///|
/// A popover's (and a hover card's) look by its sizes (still.fail's small panels): the theme's surface, its large
/// corner, `pad` in (a panel's 6 and a row's 10: its words where a menu's rows put theirs), a line round it, a shadow.
pub fn popover_look_of(pad? : Double = 16.0, gap? : Double = 8.0) -> (@ui.Ctx, PopState, () -> Unit) -> Unit {
  fn(c, _, body) {
    let t = c.theme()
    c.box(
      pad~,
      gap~,
      bg=t.surface,
      radius=t.radius_lg,
      border=1.0,
      border_color=t.line,
      shadow=32.0,
      shadow_color=t.shadow,
      shadow_y=12.0,
      body,
    )
    |> ignore
  }
}

///|
/// The default look: 16 in.
pub let popover_look : (@ui.Ctx, PopState, () -> Unit) -> Unit = popover_look_of()

///|
/// A tooltip's default look (still.fail's): small words on the primary ink, a corner of 8, a soft shadow.
pub fn tooltip_look(c : @ui.Ctx, _s : PopState, text : String) -> Unit {
  let t = c.theme()
  c.box(padx=10.0, pady=5.0, bg=t.primary, radius=8.0, max_w=300.0, shadow=12.0, shadow_color=t.shadow, shadow_y=4.0, fn() {
    c.text(text, size=t.font_sm, color=t.on_primary, line=t.font_sm * 1.4) |> ignore
  })
  |> ignore
}
