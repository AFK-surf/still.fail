// A dialog (Radix's Dialog) and an alert dialog (Radix's AlertDialog): a panel in the middle of the window, over the
// page, whether it is open the view's. Modal by default: the page under it dimmed, hidden from the semantics tree and
// taking no press, Tab kept in it, the focus moved into it as it opens and back to what had it (its trigger) as it
// goes (Ctx::overlay). Escape, the system's back, a press outside it and its close button close a dialog. An alert
// dialog asks before something that cannot be undone: a press outside does not close it, and it opens with the focus
// on its cancel button, so that Enter does not do it. Both come in by `dialog_in`, the page under them dimmed by
// `ground_in`, and go at once (@motion.presence).

///|
/// What a dialog's look is given: its title and description, how wide it is, whether a close button lies over its
/// corner.
pub(all) struct DialogState {
  title : String
  description : String
  w : Double
  closes : Bool
}

///|
/// How a dialog comes (still.fail's: parts.css.ts dialog, dialogInKeyframes): from 98% of its size, a little low and
/// clear, to itself over 200 ms on the ease-out; the page under it dimmed over 180 ms (parts.css.ts overlay). Both go
/// at once, as the web's (unmounted) do.
// kept across runs: a value (no field of it changes)
pub let dialog_in : @motion.Trans = @motion.trans(fade=0.0, scale=0.98, dy=6.0, spec=@motion.tween(dialog_ms, ease=Out), ground_first=true)

///|
pub let dialog_ms : Double = 200.0

///|
// kept across runs: a value (no field of it changes)
pub let ground_in : @motion.Trans = @motion.trans(fade=0.0, spec=@motion.tween(180.0, ease=Out))

///|
/// A dialog's ground going: as what it held goes (pop_out), faded as one, no words of its own.
// kept across runs: a value (no field of it changes)
pub let ground_out : @motion.Trans = @motion.trans(fade=0.0, scale=0.97, spec=@motion.tween(pop_out_ms, ease=Leave))

///|
/// `key`'s dialog as it shows now, `open` or not (coming or there; none once it has gone): its panel's look and how
/// much of its ground (the dimmed page) shows.
fn dialog_shows(c : @ui.Ctx, key : String, open : Bool) -> (@ui.Look, Double)? {
  guard @motion.presence(c, "\u{2}dialog/" + key, open, initial=true, enter=dialog_in, exit=pop_out) is Some(shows) else {
    return None
  }
  let ground = match @motion.presence(c, "\u{2}dialog-ground/" + key, open, initial=true, enter=ground_in, exit=ground_out) {
    Some(l) => l.alpha
    None => 0.0
  }
  Some((shows, ground))
}

///|
/// Whether `key`'s dialog (or alert dialog), `open` or not, is drawn now.
pub fn dialog_drawn(c : @ui.Ctx, key : String, open : Bool) -> Bool {
  dialog_shows(c, key, open) is Some(_)
}

///|
/// What an alert dialog reports: whether it is open now, and whether its action was taken (it closes then).
pub(all) struct Alert {
  open : Bool
  confirmed : Bool
}

///|
/// `key`'s dialog (see the file's head), `open` or not, `w` wide, titled `title` (named so for the semantics tree)
/// over `description` ("" none) and what `body` builds; a close button named `close_label` in its corner unless it
/// is "". Whether it is open now (closed by Escape, the back, a press outside unless not `outside`, the close button).
/// `scrim`: what the page under it is dimmed with (the theme's where not said: a picture shown alone over a deeper one).
/// An Escape `on_escape` says it took is a step back within it (Ctx::overlay's), not closing it.
pub fn dialog(
  c : @ui.Ctx,
  key : String,
  open : Bool,
  title : String,
  description? : String = "",
  w? : Double = 520.0,
  modal? : Bool = true,
  outside? : Bool = true,
  close_label? : String = "关闭",
  look? : (@ui.Ctx, DialogState, () -> Unit) -> Unit = dialog_look,
  scrim? : Int64,
  on_escape? : () -> Bool,
  body : () -> Unit,
) -> @ui.Changed[Bool] {
  let mut now = open
  if dialog_shows(c, key, open) is Some((shows, ground)) {
    let st = { title, description, w, closes: close_label != "" }
    let scrim = scrim.unwrap_or(c.theme().scrim)
    let o = c.overlay(key, modal~, outside~, on_escape?, scrim=pick(modal, faded(scrim, ground), 0L), inert=!open, fn() {
      centered(c, key, shows, Dialog, title, description, modal, fn() {
        look(c, st, fn() {
          body()
          if close_label != "" && close_button(c, key + "/close", close_label, inset=26.0, size=32.0) {
            now = false
          }
        })
      })
    })
    if o.dismissed is Some(_) {
      now = false
    }
  }
  { value: now, response: { ..@ui.Response::none(), id: c.id(key), changed: now != open } }
}

///|
/// `key`'s alert dialog (see the file's head), `open` or not: `title` over `description`, what `body` builds, then
/// its `cancel` and `action` buttons (the action in the danger colour when `danger`). Escape, the back and cancel
/// close it; the action closes it confirmed.
pub fn alert_dialog(
  c : @ui.Ctx,
  key : String,
  open : Bool,
  title : String,
  action : String,
  description? : String = "",
  cancel? : String = "取消",
  danger? : Bool = false,
  w? : Double = 420.0,
  look? : (@ui.Ctx, DialogState, () -> Unit) -> Unit = dialog_look,
  body? : () -> Unit = fn() {  },
) -> Alert {
  let mut now = open
  let mut confirmed = false
  if dialog_shows(c, key, open) is Some((shows, ground)) {
    let st = { title, description, w, closes: false }
    let cancel_id = c.id(key + "/cancel")
    let o = c.overlay(
      key,
      modal=true,
      outside=false,
      scrim=faded(c.theme().scrim, ground),
      initial_focus=cancel_id,
      inert=!open,
      fn() {
        centered(c, key, shows, AlertDialog, title, description, true, fn() {
          look(c, st, fn() {
            body()
            c.box(dir=Row, gap=8.0, justify=JEnd, fn() {
              if button(c, cancel, key=key + "/cancel", variant=Outline).clicked {
                now = false
              }
              if button(c, action, key=key + "/action", variant=pick(danger, Danger, Solid)).clicked {
                now = false
                confirmed = true
              }
            })
            |> ignore
          })
        })
      },
    )
    if o.dismissed is Some(_) {
      now = false
    }
  }
  { open: now, confirmed }
}

///|
/// The panel of layer `key` in the middle of the window (by its size as it is laid out), drawn as `shows` (its coming),
/// named for the semantics tree.
fn centered(
  c : @ui.Ctx,
  key : String,
  shows : @ui.Look,
  role : @ui.Role,
  title : String,
  description : String,
  modal : Bool,
  body : () -> Unit,
) -> Unit {
  let pid = c.id(key + "/panel")
  let (ww, wh) = c.window_size()
  let i = c.box(id=pid, max_w=ww - 32.0, body)
  // in the middle by its size as laid out (its first frame too)
  c.place_by_size(i, fn(pw, ph) { ((ww - pw) / 2.0, (wh - ph) / 2.0) })
  c.semantics(i, role, label=title, description~, modal~)
  c.look(i, shows)
}

///|
/// A close button over the top right corner of what it is built in (a dialog's panel, a toast), `inset` in from its
/// edges: ✕ in a circle `size` across, in `ink` (the theme's muted; the words' colour pointed at), named `label`;
/// whether it was pressed.
pub fn close_button(
  c : @ui.Ctx,
  key : String,
  label : String,
  inset? : Double = 12.0,
  size? : Double = 28.0,
  ink? : Int64,
) -> Bool {
  let t = c.theme()
  let id = c.id(key)
  let r = c.interact(id)
  let quiet = ink.unwrap_or(t.muted)
  let lit = ink.unwrap_or(t.fg)
  c.layer(pad=inset, align=AEnd, fn() {
    let i = c.box(
      id~,
      w=Px(size),
      h=Px(size),
      radius=size / 2.0,
      bg=pick(r.pressed, @ui.alpha(lit, 0.12), pick(r.hovered, @ui.alpha(lit, 0.07), 0L)),
      align=ACenter,
      justify=JCenter,
      fn() {
        c.text("✕", size=size * 0.45, color=pick(r.hovered, lit, quiet), wrap=false) |> ignore
        focus_ring(c, r.focus_shown, size / 2.0)
      },
    )
    c.semantics(i, Button, id~, label~, actions=[Activate])
  })
  |> ignore
  r.clicked
}

///|
/// `colour`'s alpha scaled by `t` (0 … 1): a scrim fading in.
fn faded(colour : Int64, t : Double) -> Int64 {
  let k = if t > 1.0 { 1.0 } else if t < 0.0 { 0.0 } else { t }
  let a = ((colour & 0xFFL).to_double() * k).round().to_int64()
  (colour & 0xFFFFFF00L) | a
}

///|
/// A dialog's look by its sizes (still.fail's): the theme's surface, the dialog's corner, `pad` in, a deep shadow;
/// its title (the heading's size, 600) over its description (muted), then what it holds, `gap` apart.
pub fn dialog_look_of(pad? : Double = 24.0, gap? : Double = 16.0) -> (@ui.Ctx, DialogState, () -> Unit) -> Unit {
  fn(c, s, body) {
    let t = c.theme()
    c.box(
      w=Px(s.w),
      pad~,
      // the title's middle on the close button's: 26 + 16, the dialog's corner (the button in it, concentric)
      pt=pad + 2.0,
      gap~,
      bg=t.surface,
      radius=t.radius_dialog,
      border=pick(t.dark, 1.0, 0.0),
      border_color=t.line,
      shadow=64.0,
      shadow_color=t.shadow,
      shadow_y=24.0,
      fn() {
        c.box(gap=6.0, fn() {
          // the title beside the close button (in its corner, its middle on the title's), the description under both
          c.box(min_h=32.0, justify=JCenter, pr=pick(s.closes, 44.0, 0.0), fn() {
            c.text(s.title, size=t.font_heading, weight=600, line=30.0) |> ignore
          })
          |> ignore
          if s.description != "" {
            c.text(s.description, size=t.font, color=t.muted, line=20.0) |> ignore
          }
        })
        |> ignore
        body()
      },
    )
    |> ignore
  }
}

///|
/// The default look: 24 in, the theme's heading.
pub let dialog_look : (@ui.Ctx, DialogState, () -> Unit) -> Unit = dialog_look_of()
