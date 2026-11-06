// A page's choice row, made once in the window's tree. The caller supplies its changing state and owns its action.

///|
/// A choice with `lead` before its label, `tag` after it, and `trail` before the check at its end. A note is laid
/// under the first line; the end and lead stay on that line. `body` replaces the label, lead, tag and note for a
/// custom choice. `ink` is the label's colour, unless disabled. The row, its words, and its accessibility state follow
/// their inputs without rebuilding it. A control made in `trail` takes its own press, even while the row is disabled
/// or busy. The returned node is the row.
pub fn choice_row_node(
  parent : @view.View,
  label : () -> String,
  chosen : () -> Bool,
  press : () -> Unit,
  body? : (@view.View) -> Unit,
  note? : () -> String = fn() { "" },
  lead? : (@view.View) -> Unit,
  tag? : (@view.View) -> Unit,
  trail? : (@view.View) -> Unit,
  ink? : () -> Int64,
  disabled? : () -> Bool = fn() { false },
  busy? : () -> Bool = fn() { false },
) -> @view.View {
  let at = part_of(parent)
  let narrow = at.look is Narrow
  let pane = in_pane_node(parent)
  let under = fn() { body is None && note() != "" }
  let live = fn() { !disabled() && !busy() }
  // On a panel's list card the ground reaches over and under the row to the card's inset, while the hit area remains
  // the row's. As in wide_link_row_node, the reach is present only when the row can be pressed.
  let reach = !narrow && at.list && pane
  let row : Ref[@view.View?] = Ref(None)
  parent.box(fn(out) {
    if reach {
      out
      .margin(By(fn() { if live() { (0.0, -link_pane_out, 0.0, -link_pane_out) } else { (0.0, 0.0, 0.0, 0.0) } }))
      .padding(By(fn() { if live() { (0.0, link_pane_out, 0.0, link_pane_out) } else { (0.0, 0.0, 0.0, 0.0) } }))
      .radius(By(fn() { list_row_corner(out) })) |> ignore
    }
    row.val = Some(out.box(fn(r) {
      let corner = fn() {
        if narrow {
          if at.list { if pane { inner_corner(card_corner, corner_inset) } else { inner_corner(group_corner, list_pad) } } else { 0.0 }
        } else if at.list {
          if pane { 0.0 } else { list_row_corner(r) }
        } else {
          @ui.tree_theme().corner(Xl2)
        }
      }
      let end_size = if narrow { pg_chevron } else { desk_chevron }
      r
      .row(Is(true))
      .gap(Is(12.0))
      .padding(Is(if narrow {
        (if at.list { text_in } else { pg_room_in }, text_in, if at.list { text_in } else { pg_room_in }, text_in)
      } else {
        (text_in, wide_row_over, if pane { card_control_end } else { text_in }, wide_row_over)
      }))
      .radius(By(corner))
      .min_height(By(fn() { Some(theme().items.least) }))
      .lines_up(By(fn() { Some(if under() { Start } else { Middle }) }))
      // turned_off affects the row alone, unlike presses(false), which would also disable its independent trail.
      .turned_off(By(fn() { !live() }))
      .focusable(By(live))
      .says(By(fn() { Some(@view.said(Button, label=label(), selected=chosen())) }))
      .on_press(fn() { if live() { press() } }) |> ignore
      (if reach { out } else { r }).ground(By(fn() {
        if live() && lit_in_node(r) { @ui.tree_theme().color(Hover) } else { 0L }
      })) |> ignore
      let ripple = if narrow { Some(press_look(r, By(corner), fn() { false })) } else { None }
      let on_it = fn(d : @view.Drag) { r.finger_target(d.wx, d.wy) }
      r.gesture(
        @ui.touch_slop(),
        press=fn(d) {
          if @signals.untracked(live) && @ui.pointing() is Finger {
            match ripple { Some(f) => f(d); None => () }
          }
        },
        tap=fn(d) { if @signals.untracked(live) && on_it(d) { press() } },
        drag=fn(d) { if d.kind == Up && @ui.pointing() is Mouse && @signals.untracked(live) && on_it(d) { press() } },
      ) |> ignore
      let end = fn(v : @view.View) {
        match trail { Some(make) => make(v); None => () }
        v.show(busy, fn(s) { spinner_node(s, size=end_size) |> ignore })
        v.show(fn() { !busy() && chosen() }, fn(s) {
          icon_node(s, "check", end_size, By(fn() { theme().p.accent })) |> ignore
        })
      }
      match body {
        Some(make) => { make(r); end(r) }
        None => {
          match lead {
            Some(make) => r.box(fn(l) {
              l.row(Is(true)).lines_up(Is(Some(Middle))).min_height(By(fn() {
                if under() {
                  l.words_redone() |> ignore
                  Some(@ui.current().sp(if narrow { @ui.tree_theme().text_size(Body).1 } else {
                    @ui.tree_theme().leading(L6).unwrap_or(@ui.tree_theme().text_size(Ui).1)
                  }))
                } else { None }
              })) |> ignore
              make(l)
            }) |> ignore
            None => ()
          }
          r.box(fn(words) {
            words.grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0)))
            .gap(Is(if narrow { 0.0 } else { desk_list_gap })) |> ignore
            words.box(fn(first) {
              first.row(Is(true)).gap(Is(12.0)).lines_up(Is(Some(Middle))) |> ignore
              first.box(fn(line) {
                line.row(Is(true)).gap(Is(6.0)).lines_up(Is(Some(Middle)))
                .grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
                line.box(fn(w) {
                  w.grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
                  styled_words(w, label, fn() { (if narrow { pg_row_title } else { desk_list_title }).then(in_lines) }) |> ignore
                  w.ink(By(fn() { if disabled() { theme().p.subtle } else { match ink { Some(f) => f(); None => theme().p.text } } })) |> ignore
                }) |> ignore
                match tag { Some(make) => make(line); None => () }
              }) |> ignore
              end(first)
            }) |> ignore
            words.show(fn() { note() != "" }, fn(n) {
              styled_words(n, note, fn() { if narrow { pg_link_note } else { wide_list_note } }) |> ignore
            })
          }) |> ignore
        }
      }
    }))
  }) |> ignore
  row.val.unwrap()
}
