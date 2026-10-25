// What opens by a trigger, put beside it (Ctx::place, Radix's Popper: on a side, flipped and moved to stay in the
// window): a popover (Radix's Popover: opened by the view, as its trigger is pressed; the focus goes into it; Escape,
// the back and a press outside but on its trigger close it), a hover card (Radix's HoverCard: for a mouse, opened
// once the pointer has rested on its trigger, kept open while it is over the trigger or the card), a tooltip (Radix's
// Tooltip: words about its trigger, shown once the pointer has rested on it or at once when the keyboard's focus comes
// to it; shut by a press on the trigger and by Escape until the pointer leaves; one shown soon after another closed
// skips the wait; to a finger, which rests on nothing, shown as it is held on the trigger, as Android's tooltips are).
// They come in growing out of the side of what they hang on (@motion.presence: `pop_in`, a tooltip `tip_in`) and go
// back into it, a little quicker (`pop_out`).

///|
/// What a popover's, a hover card's or a tooltip's look is given: the side of its trigger it went on, how tall it can be
/// there (Ctx::room_beside, Radix's --radix-popper-available-height) and the panel's box (its size read back): what it
/// holds is kept within that room by in_room, or it runs out of the window.
pub(all) struct PopState {
  side : @ui.Side
  room : Double
  panel : Int
}

///|
/// What panel `s` holds (`body`, as its look is given it), kept within the room the panel has where it went (Radix's
/// content at its available height, its overflow auto): as it is while the panel fits, and while it is no taller than
/// `most` (what a list scrolls past); else scrolling in a box as tall as that room leaves it once the rest of the panel
/// (its padding, its lines, what stands over and under this) is taken off, each read back as it is laid out. `gap`
/// between what it holds, `padx` in from its sides, which reach `mx` out (below 0: across the panel's padding, so that
/// what it holds scrolls to the panel's sides). `key`: its scroll's (by default the panel's). Whether it scrolls so.
pub fn in_room(
  c : @ui.Ctx,
  s : PopState,
  body : () -> Unit,
  key? : String = "",
  most? : Double = 1.0e9,
  gap? : Double = 0.0,
  padx? : Double = 0.0,
  mx? : Double = 0.0,
) -> Bool {
  let (key, view, whole, tall, held) = room_of(c, s, key, most)
  let what = fn() { c.box(id=whole, taps=false, w=Fill(1.0), padx~, gap~, body) |> ignore }
  c.box(id=view, taps=false, w=Fill(1.0), mx~, fn() {
    if held {
      c.capped(key, tall, what) |> ignore
    } else {
      what()
    }
  })
  |> ignore
  held
}

///|
/// How a small panel by its trigger comes (still.fail's: controls.css.ts popover, popKeyframes): from 97% of its size
/// and clear to itself over 140 ms on the ease-out, growing out of the side of what it hangs on; it goes the way it
/// came, back to 97% and clear over 100 ms on the leaving fade's ease (not at once as the web's, unmounted: still.fail's Android
/// app, pengxiao 2026-10-25, its dialogs and menus vanishing as they closed). A popover's, a menu's, a select's, a
/// hover card's, a dialog's by default.
// kept across runs: a value (no field of it changes)
pub let pop_in : @motion.Trans = @motion.trans(fade=0.0, scale=0.97, spec=@motion.tween(pop_ms, ease=Out))

///|
pub let pop_ms : Double = 140.0

///|
// kept across runs: a value (no field of it changes)
pub let pop_out : @motion.Trans = @motion.trans(fade=0.0, scale=0.97, spec=@motion.tween(pop_out_ms, ease=LeaveFade))

///|
pub let pop_out_ms : Double = 100.0

///|
/// How a tooltip comes (parts.css.ts tooltip: fadeKeyframes, 120 ms on the ease-out); it goes at once.
// kept across runs: a value (no field of it changes)
pub let tip_in : @motion.Trans = @motion.trans(fade=0.0, spec=@motion.tween(120.0, ease=Out))

///|
/// `key`'s popover (see the file's head), `open` or not, by the trigger `anchor` (its id; or by the rectangle `at`, a
/// Radix Popover.Anchor apart from its trigger), on its `side` (lined up `along` it, `offset` away), named `label` for
/// the semantics tree; `modal`: the page under it takes no press and Tab stays in it; not `focus`: the focus stays
/// where it is as it opens (Radix's onOpenAutoFocus prevented: what a field offers as it is typed in, the field keeping
/// the keys). It comes by `enter` and goes by `exit`. Whether it is open now.
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
  focus? : Bool = true,
  look? : (@ui.Ctx, PopState, () -> Unit) -> Unit = popover_look,
  at? : (Double, Double, Double, Double),
  enter? : @motion.Trans = pop_in,
  exit? : @motion.Trans = pop_out,
  body : () -> Unit,
) -> @ui.Changed[Bool] {
  let mut now = open
  if @motion.presence(c, "\u{2}pop/" + key, open, initial=true, enter~, exit~) is Some(shows) {
    let o = c.overlay(key, modal~, anchor~, initial_focus=if focus { -1 } else { 0 }, inert=!open, fn() {
      beside(c, key, anchor, side, along, offset, shows, Dialog, label, look, body, at?)
    })
    if o.dismissed is Some(_) {
      now = false
    }
  }
  { value: now, response: { ..@ui.Response::none(), id: c.id(key), changed: now != open } }
}

///|
/// How long a mouse rests on a hover card's trigger before it opens (ms), and how long after it has left both the
/// trigger and the card it closes: `hover_card`'s defaults.
pub let hover_card_open_ms : Double = 700.0

///|
pub let hover_card_close_ms : Double = 300.0

///|
/// `key`'s hover card (see the file's head) for the trigger `trigger` (its id): opened once a mouse has rested on the
/// trigger `open_delay` ms, closed `close_delay` ms after it has left both, and by Escape and a press outside. A finger
/// rests on nothing: it holds the trigger (long_press_ms) to open it, or with `tap` (a trigger that does nothing else
/// when tapped) taps it, and it stays until a press outside or another tap on the trigger. Whether it is open.
pub fn hover_card(
  c : @ui.Ctx,
  key : String,
  trigger : Int,
  open_delay? : Double = hover_card_open_ms,
  close_delay? : Double = hover_card_close_ms,
  side? : @ui.Side = Bottom,
  along? : @ui.Along = Middle,
  offset? : Double = 6.0,
  tap? : Bool = false,
  look? : (@ui.Ctx, PopState, () -> Unit) -> Unit = popover_look,
  enter? : @motion.Trans = pop_in,
  exit? : @motion.Trans = pop_out,
  body : () -> Unit,
) -> Bool {
  install()
  let id = c.id(key)
  let was = kit.val.opens.get(id).unwrap_or(false)
  let mut open = match @ui.pointing() {
    Finger => {
      let tapped = tap && c.clicked(trigger)
      if was { !tapped } else { tapped || c.held_long(trigger) }
    }
    Mouse => {
      let on_trigger = c.hovered(trigger)
      let on_card = was && pointer_in(c, c.id(key + "/panel"))
      if was {
        !after(c, key + "/out", !(on_trigger || on_card), close_delay)
      } else {
        after(c, key + "/in", on_trigger, open_delay)
      }
    }
  }
  if @motion.presence(c, "\u{2}pop/" + key, open, initial=true, enter~, exit~) is Some(shows) {
    let o = c.overlay(key, anchor=trigger, initial_focus=0, inert=!open, fn() {
      beside(c, key, trigger, side, along, offset, shows, Group, "", look, body)
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
  kit.val.opens[id] = open
  open
}

///|
/// What marks a tooltip closing (Ctx::mark): one opened soon after any closed skips its delay.
let tip_closed : Int = @ui.stable_hash("kit/tooltip closed").to_int()

///|
/// How long a mouse rests on a tooltip's trigger before it shows (ms), and how soon after another tooltip closed one
/// shows at once: `tooltip`'s defaults.
pub let tooltip_delay_ms : Double = 700.0

///|
pub let tooltip_skip_ms : Double = 300.0

///|
/// How long a tooltip a finger held open stays once it is lifted (Android's: 1500 ms).
pub let tooltip_lifted_ms : Double = 1500.0

///|
/// `key`'s tooltip (see the file's head) for the trigger `trigger` (its id), saying `text`: shown once a mouse has
/// rested on it `delay` ms (at once within `skip` ms of another closing), or at once while it has the focus by the
/// keyboard, or held by a finger on the trigger (long_press_ms: the press is then no tap) until tooltip_lifted_ms
/// after it is lifted; beside the trigger, or beside `at` (a rect in the window: a point, the pointer, for a tip that follows
/// it along a tall thin trigger, the web's usePointerTip). `shown`: held open by the app meanwhile (a mark that only
/// explains itself, tapped by a finger, which rests on nothing). Whether it shows.
pub fn tooltip(
  c : @ui.Ctx,
  key : String,
  trigger : Int,
  text : String,
  delay? : Double = tooltip_delay_ms,
  skip? : Double = tooltip_skip_ms,
  side? : @ui.Side = Top,
  along? : @ui.Along = Middle,
  offset? : Double = 6.0,
  look? : (@ui.Ctx, PopState, String) -> Unit = tooltip_look,
  at? : (Double, Double, Double, Double),
  shown? : Bool = false,
) -> Bool {
  install()
  let id = c.id(key)
  let was = kit.val.opens.get(id).unwrap_or(false)
  // over its trigger: by where the pointer is, not by what is on top there (the tip itself, the frame it first comes
  // before it is placed, lies over the trigger: hovered alone, it shut and opened again every frame)
  // (a mouse's: a finger held on a button or dragging a list over one shows no tip, @ui.pointing)
  let hovered = @ui.pointing() is Mouse && (c.hovered(trigger) || pointer_in(c, trigger))
  let focused = c.focus_shown(trigger)
  // a finger held on the trigger: shown while it stays down and a moment after
  if @ui.pointing() is Finger && c.held_long(trigger) {
    kit.val.held_tips[id] = true
  }
  if kit.val.held_tips.contains(id) {
    let (_, _, down) = c.pointer()
    if after(c, key + "/lifted", !down, tooltip_lifted_ms) {
      kit.val.held_tips.remove(id)
    }
  }
  let held = kit.val.held_tips.contains(id)
  // pressed, or Escape: shut until the pointer and the focus have left it
  if c.pressed(trigger) || c.clicked(trigger) {
    kit.val.shut[id] = true
  }
  if !hovered && !focused {
    kit.val.shut.remove(id)
  }
  let shut = kit.val.shut.contains(id)
  let soon = c.within(tip_closed, skip)
  let rested = after(c, key + "/in", hovered, if soon { 0.0 } else { delay })
  let mut open = shown || held || (!shut && (focused || rested || (was && hovered)))
  if @motion.presence(c, "\u{2}pop/" + key, open, initial=true, enter=tip_in, exit=pop_out) is Some(shows) {
    let o = c.overlay(key, anchor=trigger, outside=false, initial_focus=0, inert=!open, fn() {
      beside(c, key, trigger, side, along, offset, shows, Tooltip, text, fn(c, s, _) { look(c, s, text) }, fn() {  }, at?=at)
    })
    if o.dismissed is Some(_) {
      kit.val.shut[id] = true
      kit.val.held_tips.remove(id)
      open = false
    }
  }
  if was && !open {
    c.mark(tip_closed)
  }
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
/// Layer `key`'s content by the trigger `anchor` (Ctx::place, by its size as it is laid out), drawn as `shows` (its
/// coming and going) growing out of the side it went on, named for the semantics tree.
fn beside(
  c : @ui.Ctx,
  key : String,
  anchor : Int,
  side : @ui.Side,
  along : @ui.Along,
  offset : Double,
  shows : @ui.Look,
  role : @ui.Role,
  label : String,
  look : (@ui.Ctx, PopState, () -> Unit) -> Unit,
  body : () -> Unit,
  at? : (Double, Double, Double, Double),
) -> Unit {
  let pid = c.id(key + "/panel")
  let ar = match at {
    Some(r) => r
    None => c.rect_of(anchor).unwrap_or((0.0, 0.0, 0.0, 0.0))
  }
  let went = went_side(c, pid, ar, side, along, offset)
  let room = c.room_beside(ar, went, offset~)
  let i = c.box(id=pid, fn() { look(c, { side: went, room, panel: pid }, body) })
  c.place_by_size(i, fn(pw, ph) {
    let (x, y, _) = c.place(ar, pw, ph, side~, along~, offset~)
    (x, y)
  })
  c.semantics(i, role, label~)
  c.look(i, grown_from(shows, went, along))
}

///|
/// The side of `ar` that panel `pid` goes on as this frame lays it out (read back: laid out another size, the frame is
/// built again; before it is first laid out, `side`, asked for), so the room its look is given is the room on the side
/// it is placed on; its place is worked out as it is laid out, from its size then.
fn went_side(
  c : @ui.Ctx,
  pid : Int,
  ar : (Double, Double, Double, Double),
  side : @ui.Side,
  along : @ui.Along,
  offset : Double,
) -> @ui.Side {
  match c.laid_size(pid) {
    Some((w, h)) if w > 0.0 => c.place(ar, w, h, side~, along~, offset~).2
    _ => side
  }
}

///|
/// `shows` growing out of the edge of what hangs on side `went` of its trigger, where it lines up `along` it (Radix's
/// transform origin).
fn grown_from(shows : @ui.Look, went : @ui.Side, along : @ui.Along) -> @ui.Look {
  let across = match along {
    Start => 0.0
    Middle => 0.5
    End => 1.0
  }
  let (ox, oy) = match went {
    Bottom => (across, 0.0)
    Top => (across, 1.0)
    Right => (0.0, across)
    Left => (1.0, across)
  }
  { ..shows, ox, oy }
}

///|
/// Whether what panel `s` holds would scroll in in_room with the same `key` and `most` (asked before it is drawn: what
/// it holds lays itself out by it).
pub fn held_in_room(c : @ui.Ctx, s : PopState, key? : String = "", most? : Double = 1.0e9) -> Bool {
  room_of(c, s, key, most).4
}

///|
/// in_room's key, its two boxes (the room it is given, what it holds whole), how tall it may be, and whether it scrolls.
fn room_of(c : @ui.Ctx, s : PopState, key : String, most : Double) -> (String, Int, Int, Double, Bool) {
  let key = if key == "" { "\u{2}room/\{s.panel}" } else { key }
  let view = c.id(key + "/view")
  let whole = c.id(key + "/whole")
  // (the rest of the panel: what it is laid out taller than this)
  let rest = match (c.laid_size(s.panel), c.laid_size(view)) {
    (Some((_, ph)), Some((_, vh))) => dmax(ph - vh, 0.0)
    _ => 0.0
  }
  let tall = dmax(dmin(most, s.room - rest), 0.0)
  // (what it holds laid out whole either way, scrolling or not: by its own height)
  let held = match c.laid_size(whole) {
    Some((_, h)) => h > tall + 0.5
    None => false
  }
  (key, view, whole, tall, held)
}

///|
/// A popover's (and a hover card's) look by its sizes (still.fail's small panels): the theme's surface, its large
/// corner, `pad` in (a panel's 6 and a row's 10: its words where a menu's rows put theirs), a line round it, a shadow;
/// what it holds within the room it has (in_room).
pub fn popover_look_of(pad? : Double = 16.0, gap? : Double = 8.0) -> (@ui.Ctx, PopState, () -> Unit) -> Unit {
  fn(c, s, body) {
    let t = c.theme()
    c.box(
      pad~,
      bg=t.surface,
      radius=t.radius_lg,
      border=1.0,
      border_color=t.line,
      shadow=32.0,
      shadow_color=t.shadow,
      shadow_y=12.0,
      fn() { in_room(c, s, body, gap~) |> ignore },
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
