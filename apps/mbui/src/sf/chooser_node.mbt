// A choice that opens a menu of what it can be (chooser's) as a node of the window's tree: quiet words and a small
// chevron; pressed, its menu of choices beside it (menu_node, under it, its start at its start), the one chosen checked,
// on every screen as the old one's dropdown is (not the presenters' sheet on 小屏). Made in the layer of the panel it is
// in (offers_layer_lent, where what a field offers is made: nothing the panel cuts cuts it), else over the window.

///|
/// A choice in `parent` (chooser's, as a node): `words()` (12, quiet; the text's ink while the hand is on it, it has the
/// focus shown or its menu is open, the hover's ground under it then too) and a 12 chevron, 28 high, 8 in, 5 apart, the
/// theme's Lg round. Pressed (a tap, a click, Enter or Space with the focus on it, a screen reader's press), or Down with
/// the focus on it, its menu of `choices()` (each its value and its words) under it, 6 off, lined up with its start,
/// 220 wide at least, the one `chosen()` is checked; opened by a key, the focus on its first row. A choice chosen closes
/// it, then `choose` is given its value; Escape, back and a press outside close it alone, the focus back on the chooser.
/// Read out a button named by its words, expanded while its menu is open.
#callsite(autofill(loc))
pub fn chooser_node(
  parent : @view.View,
  words : () -> String,
  choices : () -> Array[(String, String)],
  chosen : () -> String,
  choose : (String) -> Unit,
  loc~ : SourceLoc,
) -> @view.View {
  // (over all of the panel it is in, as what a field offers is: offers_layer_lent, a sheet's, a dialog's, a small
  // panel's; else over the window)
  let layer = match parent.lent(offers_layer_lent) {
    Some(l) => l
    None => parent.tree.root()
  }
  let open = @signals.signal(false, same=fn(a, b) { a == b })
  // (opened by the keyboard: its first row's the focus as it opens)
  let by_key = Ref(false)
  let made : Ref[@view.View?] = Ref(None)
  parent.box(made_for=loc, fn(b) {
    made.val = Some(b)
    let lit = fn() { lit_node(b) || open.get() || b.focus_shown() }
    presses_node(b, fn() {
      by_key.val = b.focus_shown()
      open.set(!open.untracked())
    })
    b.on_key(fn(k) {
      if k.mods == 0 && k.code == @ui.key_code_down && b.focused() && !open.untracked() {
        by_key.val = true
        open.set(true)
        true
      } else {
        false
      }
    })
    |> ignore
    b
    .row(Is(true))
    .height(Is(Some(chooser_h)))
    .padding(Is((chooser_x, 0.0, chooser_x, 0.0)))
    .gap(Is(chooser_gap_in))
    .radius(By(fn() { @ui.tree_theme().corner(Lg) }))
    .lines_up(Is(Some(Middle)))
    .ground(By(fn() { if lit() { @ui.tree_theme().color(Hover) } else { 0L } }))
    .says(By(fn() { Some(@view.said(Button, label=words(), expanded=open.get())) }))
    |> ignore
    words_node(b, words, fn() { if lit() { chooser_words_lit } else { chooser_words } }) |> ignore
    icon_node(b, "chevron-down", chooser_chevron, By(fn() { if lit() { theme().p.text } else { theme().p.muted } }))
    |> ignore
    // (closed as it starts leaving, and as it is let go)
    b.on_leaving(fn() { open.set(false) }) |> ignore
    b.owns(fn() { open.set(false) }) |> ignore
  })
  |> ignore
  let b = made.val.unwrap()
  // (its menu made as it opens, in the layer, living as long as the chooser does; the focus given back to it as it goes)
  let holder = layer.box(fn(h) { h.over(Is(true)) |> ignore }).lives_with(b)
  holder.show(fn() { open.get() }, at_once=true, fn(m) {
    m.over(Is(true)).opened_by(@view.ByNode(b.id())) |> ignore
    let now = chosen()
    let items = choices().map(fn(c) {
      Some(menu_item_of(c.1, chosen=c.0 == now, fn() { choose(c.0) }))
    })
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
    )
  })
  b
}

///|
/// chooser_box's height (h=S7), room at its sides (px=S2) and between its words and chevron (gap=S1_25).
let chooser_h : Double = 28.0

///|
let chooser_x : Double = 8.0

///|
let chooser_gap_in : Double = 5.0

///|
/// How far under it its menu is (dropdown's offset).
let chooser_menu_off : Double = 6.0
