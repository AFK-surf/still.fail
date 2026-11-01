// A confirm (confirm_dialog's) as nodes of the window's tree, made as it opens and let go once it has gone: a modal layer
// over the whole window (at its place in the window's stack of layers as what holds it says: presented_nodes), what is
// under it dimmed by the theme's scrim as far as its ground has come (@kit.ground_in, ground_out), taking presses (a
// press outside an alert does not close it: confirm_dialog's outside=false); in its middle the panel as confirm_dialog
// draws it (confirm_w wide at most, the window less dialog_margin; dialog_r round, the panel's ground, its line, its
// shadow; its title, its words, then cancel and the action at its foot's end), coming in by @kit.dialog_in and going
// by @kit.pop_out from the moments it opens and closes; read out a dialog named by its title. Escape, back and cancel
// close it (`cancel`); the action does `confirm`. The focus on cancel as it opens (an alert's: Enter does not do it).

///|
/// A confirm in `parent` while `open()` (going over pop_out_ms once not): `title`, its `words`, `action` (solid red
/// when `danger`, the primary's otherwise) beside the library's cancel. Where it is in the window's stack of layers is
/// what holds it's (View::stacked on the root's node it is in: presented_nodes).
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
  shown? : () -> Unit = fn() {  },
  gone? : () -> Unit = fn() {  },
) -> Unit {
  parent.show(
    open,
    fn(layer) {
      shown()
      layer.owns(gone) |> ignore
      // (how far in it is, its look's and its ground's, from the moment it opened; out from the moment it closed)
      let shown = EdgeWay::new(0.0)
      let dim = EdgeWay::new(0.0)
      layer.reacts(fn() { layer.leaving() }, fn(going) {
        if going {
          shown.go(layer, 0.0, @kit.pop_out_ms, ease=Leave)
          dim.go(layer, 0.0, @kit.pop_out_ms, ease=Leave)
        } else {
          shown.go(layer, 1.0, @kit.dialog_ms)
          dim.go(layer, 1.0, confirm_ground_ms)
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
      layer
      .over(Is(true))
      // (modal while open: closing, what is under it its own again as it begins to go)
      .modal(By(live))
      // (a back gesture under way as it opens goes on to what it began on, as the old frame's layers let it: chosen as
      // it began; the next its)
      .held_back_goes_on()
      .ground(By(fn() { confirm_faded(@ui.tree_theme().scrim, dim.shown(layer)) }))
      // (a press outside it its own: an alert stays open)
      .presses(Is(true))
      .on_key(fn(k) {
        if k.code == @ui.key_escape && @signals.untracked(live) {
          cancel()
          true
        } else {
          false
        }
      })
      .takes_back(fn() {
        if @signals.untracked(live) {
          cancel()
        }
      })
      |> ignore
      // (in its middle by its size as laid out: centered's)
      layer.box(fn(s) { s.grow(Is(1.0)) |> ignore }) |> ignore
      layer.box(fn(across) {
        across.row(Is(true)) |> ignore
        across.box(fn(s) { s.grow(Is(1.0)) |> ignore }) |> ignore
        let no = confirm_panel(across, layer, look, title, words, action, danger, cancel, confirm)
        // (the focus on cancel as it opens: an alert's, so that Enter does not do it; back to what had it as it goes)
        layer.focus_opens(no) |> ignore
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
fn confirm_panel(
  parent : @view.View,
  layer : @view.View,
  look : () -> @ui.Look,
  title : () -> String,
  words : () -> String,
  action : () -> String,
  danger : Bool,
  cancel : () -> Unit,
  confirm : () -> Unit,
) -> @view.View {
  let theme = fn() { @ui.tree_theme() }
  let cancel_at : Ref[@view.View?] = Ref(None)
  parent.box(fn(d) {
    d
    .width(By(fn() { Some(dmin(confirm_w, layer.window().0 - dialog_margin)) }))
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
    .says(By(fn() { Some(@view.said(Dialog, label=title(), description=words())) }))
    |> ignore
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
    // (its foot: its buttons at its end, 8 apart, 8 over them; as far from its foot and sides as its corner has them:
    // dialog_corner_foot)
    d.box(fn(f) {
      let at = capsule_in(dialog_r, button_height())
      f
      .row(Is(true))
      .lines_up(Is(Some(Middle)))
      .gap(Is(@ui.Space::px(S2)))
      .padding(Is((at - dialog_pad, @ui.Space::px(S2), at - dialog_pad, at)))
      |> ignore
      f.box(fn(s) { s.grow(Is(1.0)) |> ignore }) |> ignore
      // (going, they take nothing: what is leaving takes no press, focus or key; drawn as they were, going with it)
      let no = button_node(f, fn() { t("common.cancel") }, cancel, tone=Ghost, words_in~)
      button_node(f, action, confirm, tone=if danger { DangerSolid } else { Primary }, words_in~) |> ignore
      cancel_at.val = Some(no)
    })
    |> ignore
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
