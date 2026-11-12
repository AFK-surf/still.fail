// A row of a list of choices (choice_row's) as a node of the window's tree: one of them chosen, its check at its end;
// laid out where it stands as the old one is (a narrow page's row, a wide list's, a panel's body's: panel_in_of).

///|
/// A row of a list of choices in `parent` (choice_row's), one of them `chosen()`: what it is given (`body`: its mark,
/// its words; or `lead` before `label` with `tag` after it on its line and `note` under them, a page row's), and
/// `trail` (a part of its own, which takes its own press) before a check at its end while it is the one chosen; the rest
/// of the row takes the press (`press`, as it is let go), lit under the hand and rippling under a finger's press
/// (narrow: a page's row, square, or a card's on a group's card, as the group lends it: on_card_node; wide: a list's
/// row), not while `disabled()` (its words faint). `ink`: its label's own (red for one that takes something away). Read
/// out a button named `label`, selected while chosen.
#callsite(autofill(loc))
pub fn choice_row_node(
  parent : @view.View,
  label : () -> String,
  chosen : () -> Bool,
  press? : () -> Unit,
  note? : () -> String = fn() { "" },
  body? : (@view.View) -> Unit,
  lead? : (@view.View) -> Unit,
  tag? : (@view.View) -> Unit,
  trail? : (@view.View) -> Unit,
  ink? : () -> Int64,
  note_ink? : () -> Int64,
  compact? : Bool = false,
  disabled? : () -> Bool = fn() { false },
  loc~ : SourceLoc,
) -> Unit {
  let t = fn() { theme() }
  let narrow = look_node(parent) is Narrow
  let at = panel_in_of(parent)
  let part = part_of(parent)
  let card = on_card_node(parent)
  let goes = fn() { !disabled() }
  // (its words as a page's row has them: the label, what follows it on its line, a note under them, its end on that
  // line where a note is under them unless `compact` centres it across a two-line panel row)
  let under = fn() { body is None && !compact && note() != "" }
  let chevron = if narrow { pg_chevron } else { desk_chevron }
  // (where it stands across in a panel's body, row_line's: panel_row_at, not on a card; elsewhere a page's row's; on a
  // page's list in a panel's card its ground reaching past it over and under: link_reach)
  let in_panel = panel_row_at(at, own=if narrow { card_pad - corner_inset } else { desk_list_out }, card~)
  let out = match in_panel {
    Some(p) => p.out
    None => 0.0
  }
  let reach = !narrow && part.list && in_pane_node(parent) && at.words == 0.0
  parent.box(made_for=loc, fn(o) {
    if reach {
      o
      .margin(Is((0.0, -link_pane_out, 0.0, -link_pane_out)))
      .padding(Is((0.0, link_pane_out, 0.0, link_pane_out)))
      .radius(By(fn() { list_row_corner(o) }))
      |> ignore
    }
    o.box(fn(r) {
      let (side, over) = if compact {
        let side = match in_panel {
          Some(p) => p.side
          None => if narrow && !card { pg_room_in } else { text_in }
        }
        (side, if narrow { @ui.Space::S2_5.px() } else { menu_row_over })
      } else if in_panel is Some(p) {
        (p.side, if narrow { text_in } else { wide_row_over })
      } else if narrow {
        (if card { text_in } else { pg_room_in }, text_in)
      } else {
        (text_in, wide_row_over)
      }
      let corner = if at.small {
        small_panel_inner(r_menu)
      } else if narrow {
        if card { row_corner } else { 0.0 }
      } else if reach {
        0.0
      } else if part.list {
        list_row_corner(r)
      } else {
        @ui.tree_theme().corner(Xl2)
      }
      r
      .row(Is(true))
      .gap(Is(if compact { panel_row_gap } else { 12.0 }))
      .margin(Is((-out, 0.0, -out, 0.0)))
      .padding(Is((side, over, side, over)))
      .radius(Is(corner))
      .min_height(By(fn() { Some(t().items.least) }))
      .lines_up(By(fn() { Some(if under() { Start } else { Middle }) }))
      |> ignore
      (if reach { o } else { r }).ground(By(fn() { if goes() && lit_node(r) { @ui.tree_theme().color(Hover) } else { 0L } }))
      |> ignore
      // (pressed as an old view's box with an id is, as it is let go: pressed_node's, read out as a choice is)
      let go = fn() {
        match press {
          Some(f) => if goes() { f() }
          None => ()
        }
      }
      r
      .presses(By(goes))
      .focusable(By(goes))
      .on_press(go)
      .says(By(fn() { Some(@view.said(Button, label=label(), selected=chosen())) }))
      |> ignore
      if narrow {
        // (a finger's press rippling over it, its corner the row's: row_ripple's)
        let rippled = press_look(loc~, r, Is(corner), fn() { false })
        let on_it = fn(d : @view.Drag) { r.finger_target(d.wx, d.wy) }
        r.gesture(
          @ui.touch_slop(),
          press=rippled.down,
          tap=fn(d) {
            (rippled.tapped)(d)
            if on_it(d) {
              go()
            }
          },
          drag=fn(d) {
            // (a mouse's moved on it past the slop: still a press as it is let go on it, as a click is)
            if d.kind == Up && @ui.pointing() is Mouse && on_it(d) {
              go()
            }
          },
        )
        |> ignore
      }
      // its end: what it has of its own, then its check while it is the one chosen; none of the row's room while it has
      // neither (the old one's end, drawing nothing)
      let ended = fn() { trail is Some(_) || chosen() }
      let end = fn(e : @view.View) {
        match trail {
          Some(f) => f(e)
          None => ()
        }
        e.show(chosen, at_once=true, fn(k) {
          k.row(Is(true)).lines_up(Is(Some(Middle))) |> ignore
          icon_node(k, "check", chevron, By(fn() { t().p.accent })) |> ignore
        })
      }
      match body {
        // (what it is given made in the row itself, as the old one's body is: its end after it)
        Some(f) => f(r)
        None => {
          match lead {
            Some(f) =>
              r.box(fn(l) {
                // (by its first line where a note is under it: as tall as that line at least, across its middle;
                // row_lead's)
                l
                .row(Is(true))
                .lines_up(Is(Some(Middle)))
                .min_height(By(fn() {
                  if under() {
                    l.words_redone() |> ignore
                    let th = @ui.tree_theme()
                    Some(node_sp(l, if narrow { th.text_size(Body).1 } else { th.leading(L6).unwrap_or(th.text_size(Ui).1) }))
                  } else {
                    None
                  }
                }))
                |> ignore
                f(l)
              })
              |> ignore
            None => ()
          }
          r.box(fn(words) {
            words.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
            if !narrow || compact {
              words.gap(Is(@ui.Space::S0_5.px())) |> ignore
            }
            words.box(fn(first) {
              first.row(Is(true)).gap(Is(12.0)).lines_up(Is(Some(Middle))) |> ignore
              // (its label and what follows it on its line, 6 apart: choice_label_line)
              first.box(fn(line) {
                line.row(Is(true)).gap(Is(6.0)).lines_up(Is(Some(Middle))).grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
                let w = words_node(line, label, fn() {
                  let base = if narrow { pg_row_title } else { desk_list_title }
                  if compact {
                    base.then(@ui.text_style(wrap=false, w=Cut))
                  } else {
                    base.then(in_lines)
                  }
                })
                // (as wide as its line leaves it narrow, pg_row_title's w=Full; wide as its words, desk_list_title's,
                // giving way with what follows it on its line where the row has not the room for them, its words then
                // on more lines, as an old view's words in a row do; `compact`: always cut on one line)
                if narrow || compact {
                  w.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
                } else {
                  w.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
                }
                w
                .ink(By(fn() {
                  if disabled() {
                    t().p.subtle
                  } else {
                    match ink {
                      Some(f) => f()
                      None => t().p.text
                    }
                  }
                }))
                |> ignore
                match tag {
                  Some(f) if narrow => f(line)
                  // (giving way with its label, as wide as it is given: its words on more lines where that is less)
                  Some(f) =>
                    line.box(fn(g) {
                      g.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
                      f(g)
                    })
                    |> ignore
                  None => ()
                }
              })
              |> ignore
              // (its end on its first line where a note is under it)
              first.show(fn() { under() && ended() }, at_once=true, fn(e) {
                e.row(Is(true)).gap(Is(12.0)).lines_up(Is(Some(Middle))) |> ignore
                end(e)
              })
            })
            |> ignore
            words.show(fn() { note() != "" }, at_once=true, fn(n) {
              let nw = words_node(n, note, fn() {
                let base = if narrow { pg_link_note } else { wide_list_note }
                if compact {
                  base.then(@ui.text_style(wrap=false, w=Cut))
                } else {
                  base
                }
              })
              match note_ink {
                Some(f) => nw.ink(By(f)) |> ignore
                None => ()
              }
            })
          })
          |> ignore
        }
      }
      // (its end at the row's where no note is under its words)
      r.show(fn() { !under() && ended() }, at_once=true, fn(e) {
        e.row(Is(true)).gap(Is(12.0)).lines_up(Is(Some(Middle))) |> ignore
        end(e)
      })
    })
    |> ignore
  })
  |> ignore
}
