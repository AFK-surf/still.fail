// A confirm (confirm_dialog's) as nodes of the window's tree, made as it opens and let go once it has gone: a modal layer
// over the whole window (at its place in the window's stack of layers as what holds it says: presented_nodes), what is
// under it dimmed by the theme's scrim as far as its ground has come (@kit.ground_in, ground_out), taking presses (a
// press outside an alert does not close it: confirm_dialog's outside=false); in its middle the panel as confirm_dialog
// draws it (confirm_w wide at most, the window less dialog_margin; dialog_r round, the panel's ground, its line, its
// shadow; its title, its words, then cancel and the action at its foot's end), coming in by @kit.dialog_in and going
// by @kit.pop_out from the moments it opens and closes; read out a dialog named by its title. Escape, back and cancel
// close it (`cancel`); the action does `confirm`. The focus on its own ground as it opens (confirm_dialog's: a layer
// that traps it with no stop of its own), back to what had it as it goes.

///|
/// A confirm in `parent` while `open()` (going over pop_out_ms once not): `title`, its `words`, `action` (solid red
/// when `danger`, the primary's otherwise) beside the library's cancel, with an optional red `warning`. Where it is in
/// the window's stack of layers is what holds it's (View::stacked on the root's node it is in: presented_nodes).
/// `shown`: as its layer is made (it opens); `gone`: once its way out is over (let go).
pub fn confirm_node(
  parent : @view.View,
  open : () -> Bool,
  title : () -> String,
  words : () -> String,
  action : () -> String,
  danger : Bool,
  cancel : () -> Unit,
  confirm : () -> Unit,
  warning? : String = "",
  shown? : () -> Unit = fn() {  },
  gone? : () -> Unit = fn() {  },
  dims? : () -> Bool = fn() { true },
  covered? : () -> Bool = fn() { false },
) -> Unit {
  // (a press outside an alert does not close it: confirm_dialog's outside=false)
  dialog_layer_node(parent, open, cancel, shown~, gone~, dims~, covered~, fn(across, layer, look, veil) {
    confirm_panel(across, layer, look, veil, title, words, warning, action, danger, cancel, confirm) |> ignore
    // (the focus on its own ground as it opens, as confirm_dialog's (an overlay that traps it, with no stop of its own:
    // the layer's own), Enter and Space doing nothing there; back to what had it as it goes)
    layer
  })
}

///|
/// A dialog of the presenters' as nodes of the window's tree in `parent` while `open()` (going over pop_out_ms once not):
/// a modal layer over the whole window, what is under it dimmed as far as its ground has come, its panel (`panel`: built
/// in the row across the window's middle, looking as the look it is given says; the node given the focus as it opens)
/// in its middle, coming in by @kit.dialog_in and going by @kit.pop_out; Escape and back close it (`cancel`), and a
/// press outside its panel where `outside` (a dialog's; an alert's not). `shown` as its layer is made, `gone` once its
/// way out is over. Escape and back offered to `within` first (a step back within it: true where it took them so). What
/// is under it dimmed only while `dims` (read as it changes: one presented under it that dims
/// already, presenters' scrim_owner, and its ground clear). `first_stop`: the focus given as it opens to the first of
/// what it holds that takes it, where the panel names no node of its own for it (Ctx::overlay's initial_focus by
/// default: a panel's, with its fields; a confirm's ground is its own; asked once the panel is made, which may say its
/// ground keeps it: a search at hand by touch); `first_takes`: only to the first of them that says what
/// it holds (a dialog of nodes: what takes what is typed or the arrows), its ground keeping it where none does. `scrim`: what dims what is under it, as far as
/// its ground has come (the theme's; a stage's its own night, stage_scrim), over `ground_ms` (a stage's night its
/// surface, in by the time what it holds begins to come: stage_node).
fn dialog_layer_node(
  parent : @view.View,
  open : () -> Bool,
  cancel : () -> Unit,
  panel : (@view.View, @view.View, () -> @ui.Look, () -> Int64) -> @view.View,
  outside? : Bool = false,
  shown? : () -> Unit = fn() {  },
  gone? : () -> Unit = fn() {  },
  dims? : () -> Bool = fn() { true },
  covered? : () -> Bool = fn() { false },
  within? : () -> Bool = fn() { false },
  first_stop? : () -> Bool = fn() { false },
  first_takes? : (@view.Said) -> Bool,
  scrim? : () -> Int64 = fn() { @ui.tree_theme().scrim },
  ground_ms? : Double = confirm_ground_ms,
  night_with_ground? : Bool = false,
) -> Unit {
  parent.show(
    open,
    fn(layer) {
      shown()
      layer.owns(gone) |> ignore
      // (how far in it is, its look's and its ground's, from the moment it opened; out from the moment it closed)
      let shown = EdgeWay::new(0.0)
      let dim = EdgeWay::new(0.0)
      // (another dialog over it: it takes nothing then, dimmed over itself as what is under them is, coming and going
      // as that one's ground does)
      let veiled = EdgeWay::new(0.0)
      layer.reacts(covered, fn(on) { veiled.go(layer, if on { 1.0 } else { 0.0 }, confirm_ground_ms) }) |> ignore
      let veil = fn() { confirm_faded(@ui.tree_theme().scrim, veiled.shown(layer)) }
      layer.reacts(fn() { layer.leaving() }, fn(going) {
        if going {
          shown.go(layer, 0.0, @kit.pop_out_ms, ease=Leave)
          dim.go(layer, 0.0, @kit.pop_out_ms, ease=Leave)
        } else {
          shown.go(layer, 1.0, @kit.dialog_ms)
          dim.go(layer, 1.0, ground_ms)
        }
      })
      let look = fn() {
        let p = shown.shown(layer)
        if layer.leaving() {
          @kit.pop_out.at(p, p)
        } else {
          @kit.dialog_in.at(p, p)
        }
      }
      let live = fn() { !layer.leaving() }
      // (a submenu row's menu in what it holds made in it: submenu_layer_lent)
      submenu_layer_lend(layer)
      layer
      .over(Is(true))
      // (modal while open: closing, what is under it its own again as it begins to go)
      .modal(By(live))
      // (going, nothing of it read out: as an old layer on its way out, inert, is hidden from what reads the screen, as
      // panel_node's)
      .hides(By(fn() { layer.leaving() }))
      // (a back gesture under way as it opens goes on to what it began on, as the old frame's layers let it: chosen as
      // it began; the next its)
      .held_back_goes_on()
      // (`night_with_ground`: as far in as what it shows' ground (its look's, ground first): the night whole as its words
      // begin, gone only after they have, never words over the page's seen through a night not yet in)
      .ground(By(fn() {
        if !dims() {
          0L
        } else if night_with_ground {
          confirm_faded(scrim(), look().alpha)
        } else {
          confirm_faded(scrim(), dim.shown(layer))
        }
      }))
      // (a press outside its panel its own, nothing under it pressed: closing it as it goes down where it is a dialog's,
      // as the old frame's layer is dismissed then (Ctx::overlay's outside), whatever the finger does after; nothing
      // where an alert's)
      .presses(Is(true))
      // (the focus its own as it opens: no key presses it)
      .focusable(Is(true), keys=0, tab=false)
      .on_drag(fn(d) {
        if d.kind == Down && outside && @signals.untracked(live) {
          cancel()
        }
      })
      // (Escape and back a step back within it first, where it says it took them so: one that goes in steps)
      .on_key(fn(k) {
        if k.code == @ui.key_escape && @signals.untracked(live) {
          if !within() {
            cancel()
          }
          true
        } else {
          false
        }
      })
      .takes_back(fn() {
        if @signals.untracked(live) && !within() {
          cancel()
        }
      })
      |> ignore
      // (in its middle by its size as laid out: centered's; the middle of the room the system's bars leave, over_room's)
      layer.padding(By(fn() {
        let (top, right, foot, left) = layer.clear()
        (left, top, right, foot)
      }))
      |> ignore
      layer.box(fn(s) { s.grow(Is(1.0)) |> ignore }) |> ignore
      layer.box(fn(across) {
        across.row(Is(true)) |> ignore
        across.box(fn(s) { s.grow(Is(1.0)) |> ignore }) |> ignore
        let first = panel(across, layer, look, veil)
        // (the focus given as it opens; back to what had it as it goes: where `first_stop` and the panel gives it to the
        // layer's own ground, to the first of what it holds that takes it instead, as an old trapping overlay's does)
        if first_stop() && physical_equal(first, layer) {
          layer.focus_opens_first(takes?=first_takes) |> ignore
        } else {
          layer.focus_opens(first) |> ignore
        }
        across.box(fn(s) { s.grow(Is(1.0)) |> ignore }) |> ignore
      })
      |> ignore
      layer.box(fn(s) { s.grow(Is(1.0)) |> ignore }) |> ignore
    },
    leave=@kit.pop_out_ms,
  )
}

///|
/// The confirm's panel in `parent` (confirm_node's), as confirm_dialog's look: looking as `look()` says, its words as
/// far in as it says. Its cancel button.
#callsite(autofill(loc))
fn confirm_panel(
  parent : @view.View,
  layer : @view.View,
  look : () -> @ui.Look,
  veil : () -> Int64,
  title : () -> String,
  words : () -> String,
  warning : String,
  action : () -> String,
  danger : Bool,
  cancel : () -> Unit,
  confirm : () -> Unit,
  loc~ : SourceLoc,
) -> @view.View {
  let theme = fn() { @ui.tree_theme() }
  let cancel_at : Ref[@view.View?] = Ref(None)
  parent.box(made_for=loc, fn(d) {
    d
    .width(By(fn() { Some(dmin(confirm_w, over_room(layer).0 - dialog_margin)) }))
    // (confirm_box: 24 in at its sides, 28 over its title, 8 between its title, its words and its foot)
    .padding(Is((dialog_pad, confirm_top, dialog_pad, 0.0)))
    .gap(Is(@ui.Space::px(S2)))
    .radius(Is(dialog_r))
    .ground(By(fn() { panel_ground() }))
    .edge(By(fn() { (1.0, theme().color(Line)) }))
    .shadow(By(fn() { (dialog_shadow, dialog_shadow_y, library_theme().p.shadow) }))
    .alpha(By(fn() { look().alpha }))
    .scale(By(fn() { look().sx }))
    .offset(By(fn() { (look().dx, look().dy) }))
    .says(By(fn() { Some(@view.said(Dialog, label=title(), description=if warning == "" { words() } else { words() + "\n" + warning })) }))
    |> ignore
    // (all it holds as far in as its look says, past its own ground, edge and shadow: each part of it, its title, its
    // words, its foot and its buttons, the same, Look's `words` as a surface's are)
    let words_in = fn() { look().words }
    d.box(fn(t) {
      t
      .words(By(title), look=toast_words_look(Heading, Font, 600, true))
      .ink(By(fn() { theme().color(Fg) }))
      .alpha(By(words_in))
      |> ignore
    })
    |> ignore
    d.box(fn(t) {
      t
      .words(By(words), look=toast_words_look(Meta, L6, 400, true))
      .ink(By(fn() { theme().color(Muted) }))
      .alpha(By(words_in))
      |> ignore
    })
    |> ignore
    if warning != "" {
      d.box(fn(t) {
        t
        .words(Is(warning), look=toast_words_look(Meta, L6, 400, true))
        .ink(By(fn() { theme().color(Danger) }))
        .alpha(By(words_in))
        |> ignore
      })
      |> ignore
    }
    // (its foot: its buttons at its end, 8 apart, 8 over them; as far from its foot and sides as its corner has them:
    // dialog_corner_foot)
    d.box(fn(f) {
      let at = @ui.capsule_in(dialog_r, button_height())
      f
      .row(Is(true))
      .lines_up(Is(Some(Middle)))
      .gap(Is(@ui.Space::px(S2)))
      .padding(Is((at - dialog_pad, @ui.Space::px(S2), at - dialog_pad, at)))
      // (its buttons, their grounds and words, as far in as the rest of what it holds)
      .alpha(By(words_in))
      |> ignore
      f.box(fn(s) { s.grow(Is(1.0)) |> ignore }) |> ignore
      // (going, they take nothing: what is leaving takes no press, focus or key; drawn as they were, going with it)
      let no = button_node(f, fn() { t("common.cancel") }, cancel, tone=Ghost)
      button_node(f, action, confirm, tone=if danger { DangerSolid } else { Primary }) |> ignore
      cancel_at.val = Some(no)
    })
    |> ignore
    // (another dialog over it: dimmed over all of itself, its corners its own)
    d.box(fn(v) { v.over(Is(true)).radius(Is(dialog_r)).ground(By(veil)) |> ignore }) |> ignore
  })
  |> ignore
  cancel_at.val.unwrap()
}

///|
/// How long a confirm's ground takes to come (@kit.ground_in's).
let confirm_ground_ms : Double = 180.0

///|
/// Over its title (confirm_box's pt=S7).
let confirm_top : Double = 28.0

///|
/// `colour` as far in as `t` (0 to 1): its alpha so much of its own.
fn confirm_faded(colour : Int64, t : Double) -> Int64 {
  let k = if t > 1.0 { 1.0 } else if t < 0.0 { 0.0 } else { t }
  let a = ((colour & 0xFFL).to_double() * k).round().to_int64()
  (colour & 0xFFFFFF00L) | a
}
