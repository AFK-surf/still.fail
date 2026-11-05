///|
/// A window layer for a control's popups. It lives with that control, but its available room and clipping are the
/// window's: a menu cannot inherit a row's height, scrolling bounds or layout motion. Made at the window's root as one of
/// them first shows (Popup::show, Popup::layer), nothing of it as the control is made: a row's control, made as its
/// list lays the row out, makes nothing out of the row (docs/retained.md rule 10).
pub struct Popup {
  priv owner : @view.View
  priv made : Ref[@view.View?]
}

///|
/// The popups' layer of control `owner` (Popup), made as one of them first shows.
pub fn popup_root_node(owner : @view.View) -> Popup {
  { owner, made: Ref(None) }
}

///|
/// The layer, made at the window's root as it is first asked for (as something of it shows, never as its control is
/// made), let go with its control.
pub fn Popup::layer(self : Popup) -> @view.View {
  match self.made.val {
    Some(l) if l.alive() => l
    _ => {
      let mut root = self.owner
      while root.parent() is Some(p) {
        root = p
      }
      let l = root.box(fn(layer) { layer.over(Is(true)).over_all(Is(true)) |> ignore }).lives_with(self.owner)
      self.made.val = Some(l)
      l
    }
  }
}

///|
/// `then`'s node in the layer while `when` holds (View::show's), the layer made as it first comes to.
pub fn Popup::show(self : Popup, when : () -> Bool, then : (@view.View) -> Unit, leave? : Double = 0.0) -> Unit {
  self.owner.show_in(fn() { self.layer() }, when, then, leave~)
}

///|
/// What a node is shown in while something holds (View::show's way): a node itself, or a control's popups' layer
/// (Popup::show), made there as it first shows.
pub(open) trait ShowsIn {
  shows_in(Self, () -> Bool, (@view.View) -> Unit, Double) -> Unit
}

///|
pub impl ShowsIn for @view.View with shows_in(self, when, then, leave) {
  self.show(when, then, leave~)
}

///|
pub impl ShowsIn for Popup with shows_in(self, when, then, leave) {
  self.show(when, then, leave~)
}
