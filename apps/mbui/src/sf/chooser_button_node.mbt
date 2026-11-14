// A choice drawn as a button (chooser's `as_button`: a ghost button's size and words, the chooser's quiet ink, a
// chevron after its words) as a node of the window's tree, made once: pressed, its menu of choices beside it as
// chooser_node's is (menu_node, made in the layer of the panel it is in, else over the window), on `side` of it.

///|
/// A choice in `parent` drawn as a ghost button (chooser's `as_button`, as a node): `words()` in a button's words and
/// height, their ink quiet but while the hand is on it, it has the focus shown or its menu is open (the hover's ground
/// under it then, eased over dur_ms as a button's), a 16 chevron after them laid out by its ink; its words changed, its
/// ground and words going to where they are laid out as a button's. Pressed (a tap, a click, Enter or Space with the
/// focus on it, a screen reader's press), or Down with the focus on it, its menu of `choices()` (each its value and
/// its words) on `side` of it, 6 off, lined up with its start, 220 wide at least, the one `chosen()` checked; a choice
/// chosen closes it, then `choose` is given its value; Escape, back and a press outside close it alone. Read out a
/// button named by its words, expanded while its menu is open. `card_words`: in a card's foot corner, its words where
/// the card's begin (button_node's). The node.
#callsite(autofill(loc))
pub fn chooser_button_node(
  parent : @view.View,
  words : () -> String,
  choices : () -> Array[(String, String)],
  chosen : () -> String,
  choose : (String) -> Unit,
  side? : @ui.Side = Bottom,
  card_words? : Bool = false,
  loc~ : SourceLoc,
) -> @view.View {
  let layer = match parent.lent(offers_layer_lent) {
    Some(l) => l
    None => parent.tree.root()
  }
  let open = @signals.signal(false, same=fn(a, b) { a == b })
  // (opened by the keyboard: its first row's the focus as it opens)
  let by_key = Ref(false)
  let height = button_height()
  let b = @headless.disclosure(
    made_for=loc,
    parent,
    words,
    fn() { open.get() },
    fn(v) {
      by_key.val = v.focus_shown()
      open.set(!open.untracked())
    },
    fn(v, _) {
      let lit = fn() { lit_node(v) || open.get() }
      let hand = EdgeWay::new(if @signals.untracked(lit) { 1.0 } else { 0.0 })
      v.reacts(lit, fn(on) { hand.go(v, if on { 1.0 } else { 0.0 }, dur_ms) })
      let ink = fn() { if lit() { theme().p.text } else { theme().p.muted } }
      let padx = if card_words { card_foot_words_in(height) } else { button_padx }
      v
      .row(Is(true))
      .height(Is(Some(height)))
      .padding(Is((padx, 0.0, padx, 0.0)))
      .lines_up(Is(Some(Middle)))
      .radius(Is(height / 2.0))
      .ground(By(fn() { alpha(theme().p.hover, hand.shown(v)) }))
      |> ignore
      v.on_key(fn(k) {
        if k.mods == 0 && k.code == @ui.key_code_down && v.focused() && !open.untracked() {
          by_key.val = true
          open.set(true)
          true
        } else {
          false
        }
      })
      |> ignore
      // (what it holds in its middle, as a button's: the old one's justify=JCenter)
      v.box(fn(s) { s.grow(Is(1.0)) |> ignore }) |> ignore
      let w = v.box(fn(w) {
        w
        .words(By(words), look={ size: theme().t.ui, weight: if theme().touch { 600 } else { 500 }, line: theme().t.ui_line, wrap: false, tracking: @view.letters_own, balance: false, max_lines: 0 })
        .ink(By(ink))
        |> ignore
      })
      // (its chevron after its words, the gap a button's between them, laid out by its ink: button's end_icon)
      v.box(fn(g) { g.width(By(fn() { Some(if theme().touch { 8.0 } else { 6.0 }) })) |> ignore }) |> ignore
      let (ink_l, ink_r) = match icon_numbers("chevron-down") {
        Some(d) => @ui.shapes_ink_in(icon_shapes(d, button_icon / 24.0, 0x000000FFL), button_icon)
        None => (0.0, 0.0)
      }
      icon_node(v, "chevron-down", button_icon, By(ink)).margin(Is((-ink_l, 0.0, -ink_r, 0.0))) |> ignore
      v.box(fn(s) { s.grow(Is(1.0)) |> ignore }) |> ignore
      // (its words changed: its ground from the shape it had, its words from where they were, together)
      let m = @motion.moves_for(v, words, spec=button_reshape)
      m.reshapes(v)
      m.moves_with(w)
      // (closed as it starts leaving, and as it is let go)
      v.on_leaving(fn() { open.set(false) }) |> ignore
      v.owns(fn() { open.set(false) }) |> ignore
    },
  )
  // (its menu made as it opens, in the layer, living as long as the choice does; the focus given back to it as it goes)
  let holder = layer.box(fn(h) { h.over(Is(true)) |> ignore }).lives_with(b)
  holder.show(fn() { open.get() }, at_once=true, fn(m) {
    m.over(Is(true)).opened_by(@view.ByNode(b.id())) |> ignore
    let now = chosen()
    let items = choices().map(fn(c) { Some(menu_item_of(c.1, chosen=c.0 == now, fn() { choose(c.0) })) })
    menu_node(
      m,
      fn() { true },
      fn(_) { b },
      fn() { items },
      "",
      Start,
      chooser_menu_off,
      by_key.val,
      false,
      fn(item) {
        open.set(false)
        (item.select)()
      },
      fn() { open.set(false) },
      min_w=chooser_menu_w,
      side~,
    )
  })
  b
}
