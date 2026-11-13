// One of several to tick (check_row's, the phone's PickRow) as a node of the window's tree, made once.

///|
/// One of several to tick in `parent` (check_row's): its box, then `lead` (a workspace's mark: workspace_badge_node),
/// then what it is (`label`, `note` quieter under it), the whole row pressed to tick it or not, its ground lit under the
/// hand. Its room, its words and its box the theme's rows' (Rows: a finger's with touch, a list row's with keyboard and
/// mouse), as each changes. `on`, `turn`: what it is now, told what it is to be as it is pressed (its box or the row
/// past it); none of it pressed while `disabled`. Its box read out a checkbox named `label`, on or off.
#callsite(autofill(loc))
pub fn check_row_node(
  parent : @view.View,
  label : () -> String,
  on : () -> Bool,
  turn : (Bool) -> Unit,
  note? : () -> String = fn() { "" },
  disabled? : () -> Bool = fn() { false },
  lead? : (@view.View) -> Unit,
  loc~ : SourceLoc,
) -> Unit {
  parent.box(made_for=loc, fn(r) {
    style_node(r, fn() { check_row_box.then(@ui.style(min_h=Fixed(theme().items.least))) })
    // (check_row_box's hovered{bg=Hover} pressed{bg=Hover}: a mouse over any of it, or it pressed)
    r.ground(By(fn() { if hovered_in_node(r) || r.pressed() { @ui.tree_theme().color(Hover) } else { 0L } })) |> ignore
    // (the row pressed, past its box: ticked or not as its box would be)
    presses_node(r, on=fn() { !disabled() }, fn() {
      if !@signals.untracked(disabled) {
        turn(!@signals.untracked(on))
      }
    })
    check_row_box_node(r, on, turn, label, disabled)
    match lead {
      Some(make) => make(r)
      None => ()
    }
    // (its words as a setting row's: what is left of the row)
    r.box(fn(words) {
      style_node(words, fn() { switch_row_words }, in_row=true)
      words_node(words, label, fn() { theme().rows.title }) |> ignore
      words.show(fn() { note() != "" }, fn(n) { styled_words(n, note, fn() { theme().rows.note }) |> ignore })
    })
    |> ignore
  })
  |> ignore
}

///|
/// A tick row's box in `parent` (check_row's @kit.checkbox in checkbox_look_of the theme's rows' `check` and
/// `check_corner`): as check_node's, its side and corner the theme's rows'.
#callsite(autofill(loc))
fn check_row_box_node(
  parent : @view.View,
  on : () -> Bool,
  turn : (Bool) -> Unit,
  label : () -> String,
  disabled : () -> Bool,
  loc~ : SourceLoc,
) -> Unit {
  let side = fn() { theme().rows.check }
  let corner = fn() { theme().rows.check_corner }
  parent.box(made_for=loc, fn(b) {
    b
    .width(By(fn() { Some(side()) }))
    .height(By(fn() { Some(side()) }))
    .radius(By(corner))
    .lines_up(Is(Some(Middle)))
    .lies_along(Is(Middle))
    .ground(By(fn() {
      let t = @ui.tree_theme()
      if on() { t.primary } else { t.bg }
    }))
    .edge(By(fn() {
      let t = @ui.tree_theme()
      let line = if on() {
        t.primary
      } else if b.pointed() && !disabled() {
        t.field_hover
      } else {
        t.border
      }
      (1.0, line)
    }))
    .alpha(By(fn() { if disabled() { check_disabled_alpha } else { 1.0 } }))
    .says(By(fn() { Some(@view.said(Checkbox, label=label(), check=if on() { On } else { Off })) }))
    |> ignore
    presses_node(b, on=fn() { !disabled() }, fn() {
      if !@signals.untracked(disabled) {
        turn(!@signals.untracked(on))
      }
    })
    b.show(on, fn(m) {
      m
      .words(Is("✓"))
      .words_look(By(fn() {
        { size: side() * 0.7, weight: 700, line: side(), wrap: false, tracking: @view.letters_own, balance: false, max_lines: 0 }
      }))
      .ink(By(fn() { @ui.tree_theme().on_primary }))
      |> ignore
    })
    // (the keyboard's focus on it: a ring round it, its gap and width the theme's: focus_ring's)
    b.show(fn() { b.focus_shown() }, fn(ring) {
      let out = fn() {
        let t = @ui.tree_theme()
        t.focus_gap + t.focus_w
      }
      ring
      .over(Is(true))
      .margin(By(fn() { (-out(), -out(), -out(), -out()) }))
      .radius(By(fn() { corner() + out() }))
      .edge(By(fn() { (@ui.tree_theme().focus_w, @ui.tree_theme().focus) }))
      |> ignore
    })
  })
  |> ignore
}

///|
/// A tick row's mark in `parent` where the row itself takes the press (choice_row_node's `lead`): its side and corner
/// the theme's rows' (`check`, `check_corner`), standing `row_corner` in from a rounded row's edge (as
/// check_row_box's `pl=room(row_corner)`), filled in the primary ink with its check when `on` (or quiet on
/// `neutral_bg` in `muted` when `dimmed`, as the last ticked row that cannot be unticked).
#callsite(autofill(loc))
pub fn check_mark_node(
  parent : @view.View,
  on : () -> Bool,
  mixed? : () -> Bool = fn() { false },
  dimmed? : () -> Bool = fn() { false },
  loc~ : SourceLoc,
) -> Unit {
  let side = fn() { theme().rows.check }
  let corner = fn() { theme().rows.check_corner }
  let narrow = look_node(parent) is Narrow
  let at = panel_in_of(parent)
  let card = on_card_node(parent)
  let reach = !narrow && part_of(parent).list && in_pane_node(parent) && at.words == 0.0
  let inset = if (narrow && !card && !at.small) || reach {
    0.0
  } else {
    let pad = match panel_row_at(at, own=if narrow { card_pad - corner_inset } else { desk_list_out }, card~) {
      Some(p) => p.side
      None => text_in
    }
    dmax(0.0, row_corner - pad + 0.001)
  }
  let active = fn() { on() || mixed() }
  parent.box(made_for=loc, fn(b) {
    if inset > 0.0 {
      b.margin(Is((inset, 0.0, 0.0, 0.0))) |> ignore
    }
    b
    .width(By(fn() { Some(side()) }))
    .height(By(fn() { Some(side()) }))
    .radius(By(corner))
    .lines_up(Is(Some(Middle)))
    .lies_along(Is(Middle))
    .ground(By(fn() {
      let t = @ui.tree_theme()
      let p = theme().p
      if !active() {
        t.bg
      } else if dimmed() {
        p.neutral_bg
      } else {
        t.primary
      }
    }))
    .edge(By(fn() {
      let t = @ui.tree_theme()
      if active() && !dimmed() {
        (1.0, t.primary)
      } else {
        (1.0, t.border)
      }
    }))
    |> ignore
    b.show(fn() { on() && !mixed() }, fn(m) {
      m
      .words(Is("✓"))
      .words_look(By(fn() {
        { size: side() * 0.7, weight: 700, line: side(), wrap: false, tracking: @view.letters_own, balance: false, max_lines: 0 }
      }))
      .ink(By(fn() { if dimmed() { theme().p.muted } else { @ui.tree_theme().on_primary } }))
      |> ignore
    })
    b.show(mixed, fn(bar) {
      bar
      .width(By(fn() { Some((side() * 0.52).round()) }))
      .height(Is(Some(2.0)))
      .radius(Is(1.0))
      .ground(By(fn() { if dimmed() { theme().p.muted } else { @ui.tree_theme().on_primary } }))
      |> ignore
    })
  })
  |> ignore
}
