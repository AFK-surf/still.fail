// Comma's other base parts as nodes of the window's tree: Radio and the groups of checkboxes and radios
// (checkbox/RadioBase, CheckboxGroup), Button groups (Button/ButtonGroup), Slider (slider/Slider, styles.ts),
// Collapse (collapse/Collapse), Indicator (indicator/Indicator) and ScrollArea (scroll-area).

///|
/// Comma's radio in `parent`, on while `on` says: a 16 circle on the main panel's ground in the menu's edge with the xs
/// shadow; brand-solid with a white dot 6 across while on; the disabled colours while `disabled`. Pressed, `pick` is
/// called. Read out a radio named `label`, on or off. The node.
#callsite(autofill(loc))
pub fn radio_node(
  parent : @view.View,
  on : () -> Bool,
  pick : () -> Unit,
  label : () -> String,
  disabled? : () -> Bool = fn() { false },
  loc~ : SourceLoc,
) -> @view.View {
  parent.box(made_for=loc, fn(b) {
    let fill = eased_by(b, on, ms_state_change, ease_surface_smooth_out)
    b
    .width(Is(Some(16.0)))
    .height(Is(Some(16.0)))
    .shrink(Is(0.0))
    .radius(Is(8.0))
    .lines_up(Is(Some(Middle)))
    .lies_along(Is(Middle))
    .ground(By(fn() {
      let c = colors()
      if disabled() {
        c.bg_disabled
      } else {
        mix(c.bg_brand_solid, fill.shown(b), c.main_panel_bg)
      }
    }))
    .edge(By(fn() {
      let c = colors()
      if disabled() {
        (1.0, c.border_disabled)
      } else {
        (1.0, mix(alpha(c.border_menu_primary, 0.0), fill.shown(b), c.border_menu_primary))
      }
    }))
    .shadow(By(fn() { cast(shadow_xs, shadow_dark_xs) }))
    .says(By(fn() { Some(@view.said(Radio, label=label(), check=if on() { On } else { Off })) }))
    |> ignore
    presses_node(b, pick, on=fn() { !disabled() })
    b.box(fn(d) {
      d
      .width(Is(Some(6.0)))
      .height(Is(Some(6.0)))
      .radius(Is(3.0))
      .ground(By(fn() {
        let c = colors()
        alpha(if disabled() { c.fg_disabled } else { c.fg_white }, fill.shown(b))
      }))
      |> ignore
    })
    |> ignore
    ring_node(b, fn() { 8.0 })
  })
}

///|
/// One row of a group of choices: `control` made first, then `label` (small, medium, the secondary's) with `hint`
/// under it (small, the tertiary's), 8 apart.
#callsite(autofill(loc))
fn choice_row(g : @view.View, label : String, hint : String, control : (@view.View) -> Unit, loc~ : SourceLoc) -> Unit {
  g.box(made_for=loc, fn(r) {
    r.row(Is(true)).gap(Is(space_md)).lines_up(Is(Some(Start))) |> ignore
    r.box(fn(c) {
      c.padding(Is((0.0, space_xxs, 0.0, 0.0))) |> ignore
      control(c)
    })
    |> ignore
    r.box(fn(t) {
      t.grow(Is(1.0)) |> ignore
      t.box(fn(w) {
        w.words(Is(label), look=words_in(type_small, weight=weight_medium)).ink(By(fn() { colors().text_secondary })) |> ignore
      })
      |> ignore
      if hint != "" {
        t.box(fn(w) {
          w.words(Is(hint), look=words_in(type_small, wrap=true)).ink(By(fn() { colors().text_tertiary })) |> ignore
        })
        |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// Comma's group of radios in `parent`: one row each of `options` (its words, its hint), 12 apart, the `chosen` one on;
/// a press on a radio chooses it. Read out a radio group named `label`. The node.
#callsite(autofill(loc))
pub fn radio_group_node(
  parent : @view.View,
  options : Array[(String, String)],
  chosen : @signals.Signal[Int],
  label? : String = "",
  loc~ : SourceLoc,
) -> @view.View {
  parent.box(made_for=loc, fn(g) {
    g.gap(Is(space_lg)).says(Is(Some(@view.said(RadioGroup, label~)))) |> ignore
    for i, o in options {
      choice_row(g, o.0, o.1, fn(c) {
        radio_node(c, fn() { chosen.get() == i }, fn() { chosen.set(i) }, fn() { o.0 }) |> ignore
      })
    }
  })
}

///|
/// Comma's group of checkboxes in `parent`: one row each of `options` (its words, its hint), 12 apart, each on as `on`
/// says by its index; a press turns it. Read out a group named `label`. The node.
#callsite(autofill(loc))
pub fn check_group_node(
  parent : @view.View,
  options : Array[(String, String)],
  on : @signals.Signal[Array[Bool]],
  label? : String = "",
  loc~ : SourceLoc,
) -> @view.View {
  parent.box(made_for=loc, fn(g) {
    g.gap(Is(space_lg)).says(Is(Some(@view.said(Group, label~)))) |> ignore
    for i, o in options {
      choice_row(g, o.0, o.1, fn(c) {
        check_node(
          c,
          fn() { on.get().get(i).unwrap_or(false) },
          fn(v) {
            let now = on.untracked().copy()
            if i < now.length() {
              now[i] = v
              on.set(now)
            }
          },
          fn() { o.0 },
        )
        |> ignore
      })
    }
  })
}

///|
/// Comma's button group in `parent`: `labels` side by side in one rounded md box in the primary edge with the xs
/// shadow, a line of it between them; each at least 40 high, 16 in, its words small semibold; the `chosen` one on the
/// secondary's ground in the primary's words, the rest on the page's in the secondary's, lit under the hand. A press
/// chooses one. Each read out a button, pressed while chosen. The node.
#callsite(autofill(loc))
pub fn button_group_node(
  parent : @view.View,
  labels : Array[String],
  chosen : @signals.Signal[Int],
  dot? : Int = -1,
  loc~ : SourceLoc,
) -> @view.View {
  // (in a row of its own: as wide as its buttons, not stretched across what holds it)
  parent.box(made_for=loc, fn(outer) {
    outer.row(Is(true)) |> ignore
    outer.box(fn(g) {
      g
      .row(Is(true))
      .radius(Is(radius_md))
      .clips(Is(true))
      .edge(By(fn() { (1.0, colors().border_primary) }))
      .shadow(By(fn() { cast(shadow_xs, shadow_dark_xs) }))
      |> ignore
      for i, l in labels {
        if i > 0 {
          g.box(fn(d) { d.width(Is(Some(1.0))).ground(By(fn() { colors().border_primary })) |> ignore }) |> ignore
        }
        g.box(fn(b) {
          let on = fn() { chosen.get() == i }
          let hand = eased_by(b, fn() { lit(b, fn() { true }) }, ms_state_change, ease_soft_in_out)
          b
          .row(Is(true))
          .lines_up(Is(Some(Middle)))
          .gap(Is(space_md))
          .min_height(Is(Some(40.0)))
          .padding(Is((space_xl, space_md, space_xl, space_md)))
          .ground(By(fn() {
            let c = colors()
            if on() {
              c.bg_secondary
            } else {
              mix(c.bg_secondary, hand.shown(b), c.bg_primary)
            }
          }))
          .says(By(fn() { Some(@view.said(Button, label=l, pressed=on())) }))
          |> ignore
          presses_node(b, fn() { chosen.set(i) })
          if i == dot {
            b.box(fn(d) {
              d.width(Is(Some(8.0))).height(Is(Some(8.0))).radius(Is(4.0)).ground(By(fn() { colors().fg_success_primary }))
              |> ignore
            })
            |> ignore
          }
          b.box(fn(w) {
            w
            .words(Is(l), look=words_in(type_small, weight=weight_semibold))
            .ink(By(fn() { if on() { colors().text_primary } else { colors().text_secondary } }))
            |> ignore
          })
          |> ignore
          ring_node(b, fn() { 0.0 }, ink=focus_gray.1)
        })
        |> ignore
      }
    })
    |> ignore
  })
}



///|
/// Comma's slider in `parent`, `width` wide (Comma's w-80, 320), at `value` between `least` and `most` in steps of `step`: a rail 6 high, rounded, on the
/// secondary's ground, filled brand-solid up to the value; its handle 20 across on the handle's ground in its edge 2 wide
/// with the md shadow. Dragged along, or stepped by the arrow keys (Home and End to its ends) and a screen reader's
/// Increment and Decrement, `value` set as it goes. Read out a slider named `label`, its range and value. The node.
#callsite(autofill(loc))
pub fn slider_node(
  parent : @view.View,
  value : @signals.Signal[Double],
  label : () -> String,
  least? : Double = 0.0,
  most? : Double = 100.0,
  step? : Double = 1.0,
  width? : Double = 320.0,
  disabled? : () -> Bool = fn() { false },
  loc~ : SourceLoc,
) -> @view.View {
  let share = fn() { ((value.get() - least) / (most - least)).max(0.0).min(1.0) }
  let set = fn(v : Double) {
    let stepped = least + ((v - least) / step).round() * step
    value.set(stepped.max(least).min(most))
  }
  parent.box(made_for=loc, fn(s) {
    s
    .width(Is(Some(width)))
    .height(Is(Some(20.0)))
    .padding(Is((10.0, 0.0, 10.0, 0.0)))
    .lines_up(Is(Some(Middle)))
    .row(Is(true))
    .alpha(By(fn() { if disabled() { 0.5 } else { 1.0 } }))
    .presses(By(fn() { !disabled() }))
    .focusable(By(fn() { !disabled() }))
    .says(By(fn() {
      Some(@view.said(Slider, label=label(), range=(least, most, value.get()), actions=[Increment, Decrement]))
    }))
    |> ignore
    // (the rail, under all of it)
    s.box(fn(r) {
      r
      .over(Is(true))
      .margin(Is((10.0, 7.0, 10.0, 7.0)))
      .radius(Is(3.0))
      .ground(By(fn() { colors().bg_secondary }))
      |> ignore
    })
    |> ignore
    // (the fill up to the value, the handle at its end)
    s.box(fn(f) {
      f
      .width_share(By(share))
      .height(Is(Some(6.0)))
      .radius(Is(3.0))
      .ground(By(fn() { colors().bg_brand_solid }))
      |> ignore
    })
    |> ignore
    s.box(fn(h) {
      h
      .width(Is(Some(20.0)))
      .height(Is(Some(20.0)))
      .shrink(Is(0.0))
      .margin(Is((-10.0, 0.0, -10.0, 0.0)))
      .radius(Is(10.0))
      .ground(By(fn() { colors().slider_handle_bg }))
      .edge(By(fn() { (2.0, colors().slider_handle_border) }))
      .shadow(By(fn() { cast(shadow_md, shadow_dark_md) }))
      |> ignore
      ring_node(h, fn() { 10.0 })
    })
    |> ignore
    s.on_drag(fn(d) {
      if @signals.untracked(disabled) || d.kind == Off {
        return
      }
      let inner = (width - 20.0).max(1.0)
      set(least + (d.x - 10.0) / inner * (most - least))
    })
    |> ignore
    s.on_key(fn(k) {
      if @signals.untracked(disabled) {
        return false
      }
      let now = value.untracked()
      if k.code == @ui.key_code_right || k.code == @ui.key_code_up {
        set(now + step)
        true
      } else if k.code == @ui.key_code_left || k.code == @ui.key_code_down {
        set(now - step)
        true
      } else if k.code == @ui.key_code_home {
        set(least)
        true
      } else if k.code == @ui.key_code_end {
        set(most)
        true
      } else {
        false
      }
    })
    |> ignore
    s.on_step(fn(by) { if !@signals.untracked(disabled) { set(value.untracked() + by.to_double() * step) } }) |> ignore
  })
}

///|
/// Comma's collapse in `parent`: its `title` (small, semibold, the primary's) with a chevron at its end turning as it
/// opens, and what `body` makes under it while `open` says, coming and going on mbui's way down its column. A press on
/// the title turns it. Read out a button named `title`, expanded or not. The node.
#callsite(autofill(loc))
pub fn collapse_node(
  parent : @view.View,
  title : () -> String,
  open : @signals.Signal[Bool],
  body : (@view.View) -> Unit,
  loc~ : SourceLoc,
) -> @view.View {
  parent.box(made_for=loc, fn(c) {
    c.gap(Is(space_sm)) |> ignore
    c.box(fn(h) {
      let turn = eased_by(h, fn() { open.get() }, ms_disclosure_turn, ease_surface_smooth_out)
      h
      .row(Is(true))
      .lines_up(Is(Some(Middle)))
      .gap(Is(space_md))
      .padding(Is((0.0, space_xs, 0.0, space_xs)))
      .says(By(fn() { Some(@view.said(Button, label=title(), expanded=open.get())) }))
      |> ignore
      presses_node(h, fn() { open.set(!open.untracked()) })
      h.box(fn(w) {
        w
        .grow(Is(1.0))
        .words(By(title), look=words_in(type_small, weight=weight_semibold))
        .ink(By(fn() { colors().text_primary }))
        |> ignore
      })
      |> ignore
      h.box(fn(k) {
        chevron(k, 20.0, fn() { colors().fg_quaternary })
        k.turn(By(fn() { 3.141592653589793 * turn.shown(h) })) |> ignore
      })
      |> ignore
      ring_node(h, fn() { radius_sm }, ink=focus_gray.1)
    })
    |> ignore
    c.show(fn() { open.get() }, body)
  })
}

///|
/// An indicator's colour (Comma's Indicator).
#derive(Eq, Debug)
pub(all) enum Signal {
  Idle
  Info
  Good
  Caution
  Bad
}

///|
/// Comma's indicator in `parent`: a dot 6, 8 or 10 across (`size` 0, 1, 2) in its signal's foreground colour. Read
/// out as a status named `label`. The node.
#callsite(autofill(loc))
pub fn indicator_node(
  parent : @view.View,
  signal : Signal,
  label : String,
  size? : Int = 1,
  loc~ : SourceLoc,
) -> @view.View {
  let side = match size {
    0 => 6.0
    2 => 10.0
    _ => 8.0
  }
  parent.box(made_for=loc, fn(d) {
    d
    .width(Is(Some(side)))
    .height(Is(Some(side)))
    .shrink(Is(0.0))
    .radius(Is(side / 2.0))
    .ground(By(fn() {
      let c = colors()
      match signal {
        Idle => c.fg_quaternary
        Info => c.fg_brand_primary
        Good => c.fg_success_primary
        Caution => c.fg_warning_primary
        Bad => c.fg_error_primary
      }
    }))
    .says(Is(Some(@view.said(Status, label~))))
    |> ignore
  })
}

///|
/// Comma's scroll area in `parent`: `height` high, what `body` makes scrolling in it, what goes on past its top and
/// foot fading out over 24 there (its `edgeEffect: mask`). Read out a scroll area named `label`. The node.
#callsite(autofill(loc))
pub fn scroll_area_node(
  parent : @view.View,
  height : Double,
  body : (@view.View) -> Unit,
  label? : String = "",
  loc~ : SourceLoc,
) -> @view.View {
  parent.box(made_for=loc, fn(a) {
    a.height(Is(Some(height))).clips(Is(true)).says(Is(Some(@view.said(ScrollArea, label~)))) |> ignore
    a.fades(Is((0.0, space_3xl, 0.0, space_3xl))) |> ignore
    a.scrolls(@view.Scroll::new(), body) |> ignore
  })
}
