// A sidebar's rows as nodes of the window's tree (side_rows.mbt's, the settings' sidebar's): a row of one line with
// its ground as the web moves it, the room between two rows, a heading over a part of the list, the room between two
// parts with none, the list under the band scrolling under it. Their looks the theme's (its chats' list's, as the
// old views' are), as they are now.

///|
/// `a` where it says one, else `b` (a side's room said for it alone, else for its axis, else for all).
fn[T] either(a : T?, b : T?) -> T? {
  match a {
    Some(_) => a
    None => b
  }
}

///|
/// Node `v`'s ground as nav_ground has it: the pointer's ground in and out (lit_node), the selected one's (`lit`, the
/// selected grey by default) while `on()`, each over nav_fade from the moment it changes.
pub fn nav_ground_node(v : @view.View, on : () -> Bool, lit? : Int64) -> Unit {
  let hover = EdgeWay::new(0.0)
  let chosen = EdgeWay::new(if @signals.untracked(on) { 1.0 } else { 0.0 })
  v.reacts(fn() { lit_node(v) }, fn(h) { hover.go(v, if h { 1.0 } else { 0.0 }, dur_ms) })
  v.reacts(on, fn(o) { chosen.go(v, if o { 1.0 } else { 0.0 }, dur_ms) })
  v
  .ground(By(fn() {
    let t = theme()
    let lit = lit.unwrap_or(t.p.selected)
    let h = hover.shown(v)
    let o = chosen.shown(v)
    if h <= 0.0 && o <= 0.0 {
      0L
    } else {
      over(alpha(t.p.hover, h * (1.0 - o)), alpha(lit, o))
    }
  }))
  |> ignore
}

///|
/// A row of one line of a sidebar's list as a node (nav_row's): its look the theme's side row's, `across` laid over it
/// where given (how what it holds stands across it), as tall as a row at least (row_least_h); its ground as nav_ground has
/// it, the selected one's while `on()`; pressed, `press`; read out a link named `label()`; another row under it (`more`):
/// the room between them (list_more). What it holds `body` makes. The row's node.
pub fn nav_row_node(
  parent : @view.View,
  on : () -> Bool,
  label : () -> String,
  press : () -> Unit,
  body : (@view.View) -> Unit,
  more? : Bool = false,
  across? : Bool = false,
) -> @view.View {
  let made : Ref[@view.View?] = Ref(None)
  let row = fn(p : @view.View) {
    p.box(fn(r) {
      made.val = Some(r)
      style_node(r, fn() { theme().chat_list.side_row })
      if across {
        r.lines_up(Is(Some(Middle))) |> ignore
      }
      r.min_height(By(fn() { Some(row_least()) })) |> ignore
      nav_ground_node(r, on)
      presses_node(r, press)
      r.says(By(fn() { Some(@view.said(Link, label=label())) })) |> ignore
      body(r)
    })
    |> ignore
  }
  if more {
    parent.box(fn(m) {
      m.padding(Is((0.0, 0.0, 0.0, @ui.Space::px(S0_5)))) |> ignore
      row(m)
    })
    |> ignore
  } else {
    row(parent)
  }
  made.val.unwrap()
}

///|
/// A heading over a part of a sidebar's list as a node (list_heading's, in a side column): the theme's heading's room,
/// in from the list's line as its rows are, its words `label()`.
pub fn side_heading_node(parent : @view.View, label : () -> String) -> Unit {
  parent.box(fn(h) {
    style_node(h, fn() { theme().chat_list.heading })
    h.padding(By(fn() {
      let base = theme().chat_list.heading.base
      let y = fn(s : @ui.Space?) { s.map(fn(s) { s.px() }).unwrap_or(0.0) }
      let x = theme().chat_list.heading_in
      (x, y(either(base.pt, either(base.py, base.p))), x, y(either(base.pb, either(base.py, base.p))))
    }))
    |> ignore
    words_node(h, label, fn() { theme().chat_list.heading_words.then(in_lines) }) |> ignore
  })
  |> ignore
}

///|
/// The room between two parts of a sidebar's list where no heading stands over the second (list_apart's).
pub fn side_apart_node(parent : @view.View) -> Unit {
  parent.box(fn(a) { a.height(Is(Some(@ui.Space::px(S3_5)))) |> ignore }) |> ignore
}

///|
/// A sidebar's list under its band as a node (side_scroll's): in at its sides as the theme's sidebar's lists are, 4
/// under the band, scrolling under the band with the tree's bar where it is taller than the room, the room under its
/// last (list_foot_in); what `rows` makes in it. Its column's node, the one `scroll` scrolls.
pub fn side_scroll_node(parent : @view.View, scroll : @view.Scroll, rows : (@view.View) -> Unit) -> @view.View {
  // (the 4 over it outside what scrolls: the list cut, and its bar's track begun, under them, as side_scroll's)
  parent.box(fn(gap) { gap.height(By(fn() { Some(@ui.Space::px(S1)) })) |> ignore }) |> ignore
  let made : Ref[@view.View?] = Ref(None)
  parent.box(fn(col) {
    made.val = Some(col)
    col.grow(Is(1.0)).basis(Is(Some(0.0))).min_height(Is(Some(0.0))) |> ignore
    col.scrolls(scroll, bar=@ui.tree_scroll_bar(), fn(body) {
      body.box(fn(list) {
        style_node(list, fn() { theme().chat_list.side_list })
        list.padding(By(fn() {
          let base = theme().chat_list.side_list.base
          let x = fn(s : @ui.Space?) { s.map(fn(s) { s.px() }) }
          let side = x(either(base.px, base.p)).unwrap_or(0.0)
          (x(base.pl).unwrap_or(side), 0.0, x(base.pr).unwrap_or(side), list_foot_in(Side))
        }))
        |> ignore
        rows(list)
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
  made.val.unwrap()
}

///|
/// An action in a sidebar's band over its list as a node (band_row's: 返回对话 beside the update): not one of the
/// list's rows but the band's, its height and its words' room the theme's band's, its corner a sidebar row's; its ground
/// as nav_ground has it, the selected one's while `on()`; pressed, `press`; read out a link named `label()`. What it
/// holds `body` makes.
pub fn band_row_node(
  parent : @view.View,
  on : () -> Bool,
  label : () -> String,
  press : () -> Unit,
  body : (@view.View) -> Unit,
) -> Unit {
  parent.box(fn(r) {
    r
    .row(Is(true))
    .grow(Is(1.0))
    .gap(Is(@ui.Space::px(S2)))
    .lines_up(Is(Some(Middle)))
    .radius(By(fn() { @ui.tree_theme().corner(side_row_radius) }))
    .min_height(By(fn() { Some(theme().chat_list.band_h) }))
    .padding(By(fn() {
      let x = theme().chat_list.band_pad
      (x, 0.0, x, 0.0)
    }))
    |> ignore
    nav_ground_node(r, on)
    presses_node(r, press)
    // (an action, not a place: a button, as the old band's box with an id is)
    r.says(By(fn() { Some(@view.said(Button, label=label())) })) |> ignore
    body(r)
  })
  |> ignore
}

///|
/// A row's words in a sidebar as a node (nav_words'): a list's title's look, cut short where the row has not the room.
pub fn nav_words_node(parent : @view.View, words : () -> String) -> Unit {
  parent.box(fn(w) {
    w.grow(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
    words_node(w, words, fn() { theme().chat_list.title.then(nav_cut) }) |> ignore
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let nav_cut : @ui.TextStyle = @ui.text_style(w=Cut)

///|
/// An update in a bar as a node (update_key's, the settings' sidebar's band): `side` across, round, the pointer's ground
/// on it while it can be pressed; its mark `mark` across: offered (`offered()`), a download mark; ready (`ready()`), a
/// restart mark inside the completed accent ring; being put in place (`busy()`), the update arrow going up; while it
/// comes (`coming()`: Some of a known part or of None for an unknown one), its progress in the mark's place. As it
/// becomes ready, the ring completes as its mark changes, on the progress control's ease without moving the
/// key. Read out a button named `label()`, unable to be pressed while busy; `why()` its tip where it says one (in
/// `tips`); pressed while not busy, `press`.
pub fn update_key_node(
  parent : @view.View,
  tips : TipLayer,
  side : Double,
  mark : Double,
  label : () -> String,
  why : () -> String,
  busy : () -> Bool,
  coming : () -> Double??,
  press : () -> Unit,
  offered? : () -> Bool = fn() { false },
  ready? : () -> Bool = fn() { false },
) -> Unit {
  // (its tip on what holds it: said while busy too, the key taking no press then, as the pointer rests on it)
  parent.box(fn(o) {
    o.box(fn(k) {
      let progress = EdgeWay::new(if @signals.untracked(coming) is Some(_) { 1.0 } else { 0.0 })
      k.reacts(fn() { coming() is Some(_) }, fn(on) { progress.go(k, if on { 1.0 } else { 0.0 }, @kit.progress_ms) })
      k
      .width(Is(Some(side)))
      .height(Is(Some(side)))
      // (round as its ground is while there is one, as an old view's key's hovered{} look: at rest none, nothing
      // standing in a corner)
      .radius(By(fn() { if lit_node(k) && !busy() { side / 2.0 } else { 0.0 } }))
      // (its mark in its middle both ways, as update_key_box's: a box lays what it holds down from its top)
      .lines_up(Is(Some(Middle)))
      .lies_along(Is(Middle))
      .ground(By(fn() { if lit_node(k) && !busy() { @ui.tree_theme().color(Hover) } else { 0L } }))
      .says(By(fn() { Some(@view.said(Button, label=label())) }))
      |> ignore
      // (pressed while it is not busy: a press's ripple on it, its press then; read out unable to be pressed while busy)
      let able = fn() { !busy() }
      k.presses(By(able)).focusable(By(able)).on_press(fn() { if able() { press() } }) |> ignore
      let rippled = press_look(k, Is(side / 2.0), fn() { false })
      let on_it = fn(d : @view.Drag) { k.finger_target(d.wx, d.wy) }
      k.gesture(
        @ui.touch_slop(),
        press=fn(d) { if able() { rippled(d) } },
        tap=fn(d) { if on_it(d) && able() { press() } },
        drag=fn(d) { if d.kind == Up && @ui.pointing() is Mouse && on_it(d) && able() { press() } },
      )
      |> ignore
      k.box(fn(m) {
        m.width(Is(Some(mark))).height(Is(Some(mark))) |> ignore
        // (offered: a download mark; ready: restart; busy, the update arrow going up)
        m.box(fn(mark_box) {
          mark_box.over(Is(true)).alpha(By(fn() { 1.0 - progress.shown(mark_box) })) |> ignore
          mark_box.pick(busy, fn(r, b) {
            if b {
              updating_node(r, mark, fn() { theme().p.text })
            } else {
              r.pick(ready, fn(r1, is_ready) {
                if is_ready {
                  update_ready_node(r1, mark, fn() { theme().p.text })
                } else {
                  icon_node(r1, "update", mark, By(fn() { theme().p.text }), name_now=fn() { if offered() { "download" } else { "update" } }) |> ignore
                }
              })
            }
          })
        })
        |> ignore
        // (coming: how far, in the mark's place, faded in as it starts)
        m.show(fn() { coming() is Some(_) || progress.shown(m) > 0.0 }, fn(c) {
          c.over(Is(true)).alpha(By(fn() { progress.shown(c) })) |> ignore
          coming_node(c, fn() { coming().unwrap_or(Some(1.0)) }, mark, fn() { theme().p.text })
        })
      })
      |> ignore
    })
    |> ignore
    ignore(tip_node(tips, o, why, within=true))
  })
  |> ignore
}

///|
/// The completed progress ring with its restart mark in the middle, as update_ready_mark.
fn update_ready_node(parent : @view.View, size : Double, color : () -> Int64) -> Unit {
  let stroke = size * icon_stroke / 24.0
  let ring = size * coming_ring / 24.0 + stroke
  parent.box(fn(b) {
    b.width(Is(Some(size))).height(Is(Some(size))).lines_up(Is(Some(Middle))).lies_along(Is(Middle)) |> ignore
    progress_spinner_node(b, fn() { Some(1.0) }, size=ring, stroke~) |> ignore
    b.box(fn(i) {
      i.over(Is(true)).lines_up(Is(Some(Middle))).lies_along(Is(Middle)) |> ignore
      icon_node(i, "restart-ring", size, By(color)) |> ignore
    }) |> ignore
  }) |> ignore
}

///|
/// What comes as a node (coming_mark's): in an icon's place `size` across, a ring where the icons draw their circles,
/// the accent from its top as far round as `coming()` says (eased to it over progress_ms; None, a quarter turning), a
/// short arrow down in it, in `color()`.
fn coming_node(parent : @view.View, coming : () -> Double?, size : Double, color : () -> Int64) -> Unit {
  let stroke = size * icon_stroke / 24.0
  let ring = size * coming_ring / 24.0 + stroke
  parent.box(fn(b) {
    b.width(Is(Some(size))).height(Is(Some(size))).lines_up(Is(Some(Middle))) |> ignore
    b.box(fn(r) {
      r.width(Is(Some(size))).height(Is(Some(size))).padding(Is(((size - ring) / 2.0, (size - ring) / 2.0, 0.0, 0.0))) |> ignore
      r.pick(fn() { coming() is Some(_) }, fn(p, known) {
        if known {
          let pi = 3.141592653589793
          let mid = ring / 2.0
          let rad = mid - stroke / 2.0
          let at = EdgeWay::new(@signals.untracked(coming).unwrap_or(0.0))
          p.reacts(fn() { coming().unwrap_or(0.0) }, fn(k) { at.go(p, if k < 0.0 { 0.0 } else if k > 1.0 { 1.0 } else { k }, @kit.progress_ms) })
          p.box(fn(l) {
            l
            .width(Is(Some(ring)))
            .height(Is(Some(ring)))
            .lines(By(fn() {
              let t = theme()
              let shown = at.shown(l)
              let lines = [@ui.line(@ui.arc(mid, mid, rad, from=0.0, sweep=2.0 * pi), width=stroke, color=t.p.line_strong)]
              if shown > 0.0 {
                lines.push(@ui.line(@ui.arc(mid, mid, rad, from=-0.5 * pi, sweep=shown * 2.0 * pi), width=stroke, color=t.p.accent))
              }
              lines
            }))
            |> ignore
          })
          |> ignore
        } else {
          spinner_node(p, size=ring, stroke~) |> ignore
        }
      })
    })
    |> ignore
    b.box(fn(i) {
      i.over(Is(true)) |> ignore
      icon_node(i, "download-ring", size, By(color)) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// An update being put in place as a node (updating_mark's): in a ring an arrow up standing a while, then off up through
/// its top as the next comes up from its bottom, eased in and out, once every updating_rise_ms, seen in a round window
/// inside the ring; `size` across, in `color()`, moved by the clock as each frame is drawn.
fn updating_node(parent : @view.View, size : Double, color : () -> Int64) -> Unit {
  let pi = 3.141592653589793
  let k = size / 24.0
  let stroke = 1.75 * k
  let mid = size / 2.0
  let window = 13.0 * k
  let wmid = window / 2.0
  let length = 8.0 * k
  let pitch = window + length
  let arrow = fn(top : Double, ink : Int64) -> Array[@ui.Line] {
    [
      @ui.line([(wmid, top), (wmid, top + length)], width=stroke, color=ink),
      @ui.line([(wmid - 3.0 * k, top + 3.0 * k), (wmid, top), (wmid + 3.0 * k, top + 3.0 * k)], width=stroke, color=ink),
    ]
  }
  let top = wmid - length / 2.0
  parent.box(fn(b) {
    b
    .width(Is(Some(size)))
    .height(Is(Some(size)))
    .lines(By(fn() { [@ui.line(@ui.arc(mid, mid, 8.5 * k, from=0.0, sweep=2.0 * pi), width=stroke, color=color())] }))
    |> ignore
    b.box(fn(w) {
      w
      .over(Is(true))
      .width(Is(Some(window)))
      .height(Is(Some(window)))
      .offset(Is((mid - wmid, mid - wmid)))
      .radius(Is(window / 2.0))
      .clips(Is(true))
      |> ignore
      w.box(fn(a) {
        a
        .width(Is(Some(window)))
        .height(Is(Some(window + pitch)))
        .lines(By(fn() {
          let ink = color()
          let lines = arrow(top, ink)
          lines.push_iter(arrow(top + pitch, ink).iter())
          lines
        }))
        .offset(By(fn() {
          let f = a.cycle(updating_rise_ms)
          let g = if f <= updating_stand { 0.0 } else { (f - updating_stand) / (1.0 - updating_stand) }
          let h = 2.0 - 2.0 * g
          let eased = if g < 0.5 { 4.0 * g * g * g } else { 1.0 - h * h * h / 2.0 }
          (0.0, -eased * pitch)
        }))
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}
