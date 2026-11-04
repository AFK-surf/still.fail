// The quiet chooser at the end of a notice: the same label, height and menu as chooser, kept while its value changes.

///|
pub fn chooser_node(
  parent : @view.View,
  words : () -> String,
  entries : () -> Array[MenuItem?],
  open : () -> Bool,
  set_open : (Bool) -> Unit,
  disabled? : () -> Bool = fn() { false },
  capsule? : () -> Bool = fn() { false },
  side? : @view.Side = Bottom,
  at_foot? : Bool = false,
  as_button? : Bool = false,
) -> @view.View {
  let by_key = @signals.signal(false)
  // (a 28-high one in a card's foot on a button-high line of its own, its capsule where that height meets the card's
  // corner: its words then on the card's line as the buttons' are, wrapped or not: chooser's at_foot)
  let holder = if at_foot && !as_button {
    parent.box(fn(h) {
      h.row(Is(true)).height(Is(Some(button_height()))).lines_up(Is(Some(Middle)))
      .padding(Is((card_foot_in(28.0) - card_foot_in(button_height()), 0.0, 0.0, 0.0))) |> ignore
    })
  } else {
    parent
  }
  let button = holder.box(fn(b) {
    let opened = fn() { open() && !disabled() }
    let lit = fn() { !disabled() && (opened() || b.pointed() || b.pressed() || b.focus_shown()) }
    // (`as_button`: a button's size, its words' look and its gap before the chevron, the chooser's quiet ink and
    // ground: chooser's as_button)
    let height = if as_button { button_height() } else { 28.0 }
    b.row(Is(true)).height(Is(Some(height))).padding(Is({
      // (in a card's foot its words on the card's line, round at its ends: chooser's at_foot)
      let px = if at_foot { card_foot_words_in(height) } else if as_button { button_padx } else { 8.0 }
      (px, 0.0, px, 0.0)
    })).gap(By(fn() { if as_button { if theme().touch { 8.0 } else { 6.0 } } else { 5.0 } }))
    .lines_up(Is(Some(Middle))).radius(By(fn() { if as_button || at_foot || capsule() { height / 2.0 } else { @ui.tree_theme().corner(Lg) } }))
    .ground(By(fn() { if lit() { theme().p.hover } else { 0L } }))
    .presses(By(fn() { !disabled() })).focusable(By(fn() { !disabled() }))
    .on_press(fn() { if !disabled() { by_key.set(b.focus_shown()); set_open(!open()) } })
    .on_key(fn(k) {
      if b.focused() && k.code == @ui.key_code_down && k.mods == 0 && !disabled() && !open() {
        by_key.set(true); set_open(true); true
      } else { false }
    })
    .says(By(fn() { Some(@view.said(Button, label=words(), expanded=opened())) })) |> ignore
    b.reacts(disabled, fn(off) { if off { set_open(false) } })
    b.box(fn(t) {
      if as_button {
        t.words(By(words), look={ size: theme().t.ui, weight: if theme().touch { 600 } else { 500 }, line: theme().t.ui_line, wrap: false, tracking: @view.letters_own, balance: false }) |> ignore
      } else {
        t.words(By(words)).words_look(By(fn() { @ui.style_words(chooser_words) })) |> ignore
      }
      t
      .ink(By(fn() { if lit() { theme().p.text } else { theme().p.muted } })) |> ignore
    }) |> ignore
    if as_button {
      // (by its ink, as a button's icon: button's draw_icon by_ink)
      let (ink_l, ink_r) = match icon_numbers("chevron-down") {
        Some(d) => @ui.shapes_ink_in(icon_shapes(d, button_icon / 24.0, 0x000000FFL), button_icon)
        None => (0.0, 0.0)
      }
      icon_node(b, "chevron-down", button_icon, By(fn() { if lit() { theme().p.text } else { theme().p.muted } }))
      .margin(Is((-ink_l, 0.0, -ink_r, 0.0)))
      |> ignore
    } else {
      icon_node(b, "chevron-down", chooser_chevron, By(fn() { if lit() { theme().p.text } else { theme().p.muted } })) |> ignore
    }
  })
  let popup = popup_root_node(button)
  popup.show(fn() { open() && !disabled() }, fn(slot) {
    // The per-opening scope fills the popup layer; its menu's absolute panel is measured in the window's room.
    slot.over(Is(true)) |> ignore
    menu_node(slot, fn() { open() && !disabled() }, fn(_) { button }, entries, "", Start, 6.0,
      @signals.untracked(fn() { by_key.get() }), @signals.untracked(fn() { !by_key.get() && @ui.pointing() is Finger }),
      fn(item) { set_open(false); (item.select)() }, fn() { set_open(false) }, side~, min_w=chooser_menu_w)
  })
  button
}
