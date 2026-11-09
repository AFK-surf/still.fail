// The library's chip (chip's) as a node of the window's tree, made once: a little pill of words and an icon on a tint
// of its ink, the tint deeper under the hand as far as that has eased (dur_ms, eased out, from the moment it changed).

///|
/// A chip in `parent` (chip's, its own corner): `label`, `icon` before it (none: ""), in `ink` (the words' ink where
/// none), 30 high and 30 wide at least, 10 in either side where it has words, 10 round; on a tint of its ink, deeper
/// under the hand; drawn whole in bones. Named `said` (read out a button, its tip in `tips`) where said; `press` done as
/// it is pressed. The node.
#callsite(autofill(loc))
pub fn chip_node(
  parent : @view.View,
  label : () -> String,
  press : () -> Unit,
  icon? : String = "",
  ink? : () -> Int64 = fn() { theme().p.text },
  said? : () -> String = fn() { "" },
  tips? : TipLayer,
  loc~ : SourceLoc,
) -> @view.View {
  parent.box(made_for=loc, fn(v) {
    let lit = fn() {
      v.focus_shown() ||
      (match @ui.pointing() {
        Mouse => v.pointed() || v.pressed()
        Finger => v.pressed()
      })
    }
    let hand = EdgeWay::new(0.0)
    v.reacts(lit, fn(on) { hand.go(v, if on { 1.0 } else { 0.0 }, dur_ms) })
    v
    .row(Is(true))
    .height(Is(Some(30.0)))
    .min_width(Is(Some(30.0)))
    .padding(By(fn() { if label() == "" { (0.0, 0.0, 0.0, 0.0) } else { (10.0, 0.0, 10.0, 0.0) } }))
    .gap(Is(2.0))
    .lines_up(Is(Some(Middle)))
    .lies_along(Is(Middle))
    .radius(Is(10.0))
    .ground(By(fn() { alpha(ink(), 0.07 + 0.05 * hand.shown(v)) }))
    .presses(Is(true))
    .focusable(Is(true))
    .says(By(fn() { if said() == "" { None } else { Some(@view.said(Button, label=said())) } }))
    .on_press(press)
    .bone_whole(Is(true))
    |> ignore
    if icon != "" {
      icon_node(v, icon, 16.0, By(ink)) |> ignore
    }
    v.show(fn() { label() != "" }, fn(w) {
      w
      .words(By(label))
      .words_look(By(fn() { { size: theme().t.meta, weight: 400, line: 18.0, wrap: false, tracking: @view.letters_own, balance: false } }))
      .ink(By(ink))
      |> ignore
    })
    match tips {
      Some(t) => tip_node(t, v, said) |> ignore
      None => ()
    }
    let on_it = fn(d : @view.Drag) { v.finger_target(d.wx, d.wy) }
    v.gesture(
      @ui.touch_slop(),
      tap=fn(d) { if on_it(d) { press() } },
      drag=fn(d) { if d.kind == Up && @ui.pointing() is Mouse && on_it(d) { press() } },
    )
    |> ignore
  })
}

///|
/// A pill (pill's) as a node in `parent`: `words` in its tone's ink on its tone's ground, a capsule pill_h high, pill_in
/// in at either end, cut short where its row has not the room; `icon` leading it (pill_icon, its ink, 4 before its
/// words; "" none); one piece in bones. The node.
#callsite(autofill(loc))
pub fn pill_node(
  parent : @view.View,
  words : () -> String,
  tone? : PillTone = Neutral,
  icon? : String = "",
  loc~ : SourceLoc,
) -> @view.View {
  let colours = fn() {
    let p = theme().p
    match tone {
      Neutral => (p.neutral_bg, p.muted)
      Green => (p.green_bg, p.green_ink)
      Blue => (p.blue_bg, p.blue)
      Amber => (p.amber_bg, p.warn_ink)
      Red => (p.red_bg, p.red)
      Accented => (p.accent_bg, p.accent_text)
    }
  }
  parent.box(made_for=loc, fn(b) {
    b
    .row(Is(true))
    .height(Is(Some(pill_h)))
    .padding(Is((pill_in, 0.0, pill_in, 0.0)))
    // (round at its ends as pill_box is, radius=Full: the same capsule, the corner the old pill said)
    .radius(Is(1.0e6))
    .lines_up(Is(Some(Middle)))
    .ground(By(fn() { colours().0 }))
    .bone_whole(Is(true))
    .shrink(Is(1.0))
    .min_width(Is(Some(0.0)))
    |> ignore
    // (none, the pill as it was: its words alone)
    if icon != "" {
      b.gap(Is(pill_icon_gap)) |> ignore
      icon_node(b, icon, pill_icon, By(fn() { colours().1 })) |> ignore
    }
    b.box(fn(w) {
      w
      .words(By(words))
      .words_look(By(fn() { @ui.style_words(pill_words) }))
      .ink(By(fn() { colours().1 }))
      .cuts(Is(true))
      .min_width(Is(Some(0.0)))
      .allow_ellipsis(Is(true))
      |> ignore
    })
    |> ignore
  })
}
