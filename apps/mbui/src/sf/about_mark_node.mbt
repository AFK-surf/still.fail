// The library's mark saying what a thing is for (about's) as a node of the window's tree, made once: the info icon in
// a round 20 (about_box), the subtle ink's, the text's where the hand is on it; what it says its tip, under it, as the
// pointer rests on it, or as a finger taps it or it is pressed by a key or a screen reader (shown till the next tap,
// wherever it lands: on it again shuts it); read out a button by its name.

///|
/// The mark in `parent`, saying `words` in its tip (in `tips`), read out `label`. The node.
pub fn about_mark_node(parent : @view.View, words : () -> String, label : () -> String, tips : TipLayer) -> @view.View {
  parent.box(fn(v) {
    let lit = fn() {
      v.focus_shown() ||
      (match @ui.pointing() {
        Mouse => v.pointed() || v.pressed()
        Finger => v.pressed()
      })
    }
    let side = @ui.Space::px(S5)
    let pad = (side - about_icon) / 2.0
    v
    .width(Is(Some(side)))
    .height(Is(Some(side)))
    .padding(Is((pad, pad, pad, pad)))
    .radius(Is(side / 2.0))
    .presses(Is(true))
    .focusable(Is(true))
    .says(By(fn() { Some(@view.said(Button, label=label())) }))
    |> ignore
    icon_node(v, "info", about_icon, By(fn() { if lit() { theme().p.text } else { theme().p.subtle } })) |> ignore
    let tip = tip_node(tips, v, words, side=Bottom)
    // (a finger's tap shows what it says till the next tap, wherever it lands; that one on it shuts it and no more: as
    // about's, about_open and tapped_anywhere)
    let toggle = fn(tapped : Bool) {
      if (tip.opened)() {
        (tip.cancel)()
      } else {
        (tip.open)(tapped)
      }
    }
    v.gesture(@ui.touch_slop(), tap=fn(d) {
      if @ui.pointing() is Finger && v.finger_target(d.wx, d.wy) {
        toggle(true)
      }
    })
    |> ignore
    // (pressed by a key or a screen reader (its press, View::on_press: what a tap of its gesture is not): the same)
    v.on_press(fn() { toggle(false) }) |> ignore
  })
}
