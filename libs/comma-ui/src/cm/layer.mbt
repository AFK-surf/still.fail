// Where Comma's floating parts are drawn (a tooltip, a menu, a dropdown's list, a popup, a dialog, the toasts): a node
// over all of the window, given once as the app makes its tree; each floating part is made in it as it first opens,
// lives with what opened it, and comes and goes there by its own fade.

///|
/// The layer floating parts are drawn in: the node `layer_node` made.
pub struct Layer {
  at : Ref[@view.View?]
}

///|
/// A layer not made yet (layer_node makes it).
pub fn Layer::new() -> Layer {
  { at: Ref(None) }
}

///|
/// The layer in `parent`, the window's root (View::over_all is over all else only among what the root holds): over all
/// of the window, whatever the root holds made after it, taking no press itself.
#callsite(autofill(loc))
pub fn layer_node(parent : @view.View, layer : Layer, loc~ : SourceLoc) -> Unit {
  parent.box(made_for=loc, fn(l) {
    l.over(Is(true)) |> ignore
    l.over_all(Is(true)) |> ignore
    layer.at.val = Some(l)
  })
  |> ignore
}

///|
/// A holder for one floating part of `owner` in the layer: over all of it, living with `owner` (gone as it goes).
#callsite(autofill(loc))
fn Layer::holder(self : Layer, owner : @view.View, loc~ : SourceLoc) -> @view.View {
  match self.at.val {
    Some(l) => l.box(made_for=loc, fn(h) { h.over(Is(true)) |> ignore }).lives_with(owner)
    None => @halt.saying("cm: a floating part made before its layer (layer_node)")
  }
}

///|
/// How far in a floating part is (0 gone, 1 there): 1 while `open`, over `in_ms` coming and `out_ms` going, eased
/// surface-smooth-out, from the moment it changed.
fn opening(n : @view.View, open : () -> Bool, in_ms : Double, out_ms : Double) -> Eased {
  let e = Eased::new(if @signals.untracked(open) { 1.0 } else { 0.0 })
  n.reacts(open, fn(now) { e.go(n, if now { 1.0 } else { 0.0 }, if now { in_ms } else { out_ms }, ease_surface_smooth_out) })
  e
}

///|
/// Comma's opacity for what comes or goes by its scale (Cue's AGENTS.md, Client UI 5): none at half its size or less,
/// whole at its full size.
fn seen_at(scale : Double) -> Double {
  ((scale - 0.5) * 2.0).max(0.0).min(1.0)
}

///|
/// A press anywhere in `h` (over all of the window) closing what floats in it: under it, named for a screen reader.
#callsite(autofill(loc))
fn closes_outside(h : @view.View, close : () -> Unit, label : String, loc~ : SourceLoc) -> Unit {
  h.box(made_for=loc, fn(c) {
    c.over(Is(true)).says(Is(Some(@view.said(Button, label~)))) |> ignore
    c.presses(Is(true)).on_press(close) |> ignore
  })
  |> ignore
}

///|
/// Escape in `h`, while `open`, closes it.
fn escape_closes(h : @view.View, open : () -> Bool, close : () -> Unit) -> Unit {
  h.on_key(fn(k) {
    if k.code == @ui.key_escape && @signals.untracked(open) {
      close()
      true
    } else {
      false
    }
  })
  |> ignore
}
