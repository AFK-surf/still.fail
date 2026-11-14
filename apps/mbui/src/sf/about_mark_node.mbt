// The library's mark saying what a thing is for (about's) as a node of the window's tree, made once: the info icon in
// a round 20 (about_box), the subtle ink's, the text's where the hand is on it; what it says its tip, under it, as the
// pointer rests on it, or as a finger taps it or it is pressed by a key or a screen reader (shown till the next tap,
// wherever it lands: on it again shuts it); read out a button by its name.

///|
/// The mark in `parent`, saying `words` in its tip (in `tips`), read out `label`. The node.
#callsite(autofill(loc))
pub fn about_mark_node(
  parent : @view.View,
  words : () -> String,
  label : () -> String,
  tips : TipLayer,
  loc~ : SourceLoc,
) -> @view.View {
  let press_ref : Ref[(Bool) -> Unit] = Ref(fn(_) {  })
  @headless.button(made_for=loc, parent, label, fn(_) { (press_ref.val)(false) }, fn(v, b) {
    let lit = fn() { b.focus_shown() || b.hovered() || b.pressed() }
    let side = @ui.Space::px(S5)
    let pad = (side - about_icon) / 2.0
    v
    .width(Is(Some(side)))
    .height(Is(Some(side)))
    .padding(Is((pad, pad, pad, pad)))
    .radius(Is(side / 2.0))
    |> ignore
    icon_node(v, "info", about_icon, By(fn() { if lit() { theme().p.text } else { theme().p.subtle } })) |> ignore
    let tip = tip_node(tips, v, words, side=Bottom)
    // (a finger's tap shows what it says till the next tap, wherever it lands; that one on it shuts it and no more: as
    // about's, about_open and tapped_anywhere; pressed by a key or a screen reader, the button's press: the same)
    let toggle = fn(tapped : Bool) {
      if (tip.opened)() {
        (tip.cancel)()
      } else {
        (tip.open)(tapped)
      }
    }
    press_ref.val = toggle
    v.gesture(@ui.touch_slop(), tap=fn(d) {
      if @ui.pointing() is Finger && v.finger_target(d.wx, d.wy) {
        toggle(true)
      }
    })
    |> ignore
  })
}
