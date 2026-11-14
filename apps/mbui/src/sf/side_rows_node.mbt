// A sidebar's rows as nodes of the window's tree (side_rows.mbt's, the settings' sidebar's): a row of one line with
// its ground as the web moves it, the room between two rows, a heading over a part of the list, the room between two
// parts with none, the list under the band scrolling under it. Their looks the theme's (its chats' list's, as the
// old views' are), as they are now.

///|
/// Node `v`'s ground as nav_ground_by has it: the pointer's ground in and out (lit_node), the selected one's (`lit`, the
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
/// An action in a sidebar's band over its list as a node (band_row's: 返回对话 beside the update): not one of the
/// list's rows but the band's, its height and its words' room the theme's band's, its corner a sidebar row's; its ground
/// as nav_ground_by has it, the selected one's while `on()`; pressed, `press`; read out a link named `label()`. What it
/// holds `body` makes. `at`: where its list stands (its words' room: band_pad_in).
#callsite(autofill(loc))
pub fn band_row_node(
  parent : @view.View,
  on : () -> Bool,
  label : () -> String,
  press : () -> Unit,
  at : ListAt,
  body : (@view.View) -> Unit,
  loc~ : SourceLoc,
) -> Unit {
  @headless.button(made_for=loc, parent, label, fn(_) { press() }, fn(r, _) {
    r
    .row(Is(true))
    .grow(Is(1.0))
    .gap(Is(@ui.Space::px(S2)))
    .lines_up(Is(Some(Middle)))
    .radius(By(fn() { @ui.tree_theme().corner(side_row_radius) }))
    .min_height(By(fn() { Some(theme().chat_list.band_h) }))
    .padding(By(fn() {
      let x = band_pad_in(at)
      (x, 0.0, x, 0.0)
    }))
    |> ignore
    nav_ground_node(r, on)
    body(r)
  })
  |> ignore
}

///|
/// A row's words in a sidebar as a node (nav_words'): a list's title's look, cut short where the row has not the room.
#callsite(autofill(loc))
pub fn nav_words_node(parent : @view.View, words : () -> String, loc~ : SourceLoc) -> Unit {
  parent.box(made_for=loc, fn(w) {
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
/// on it while it can be pressed; its mark `mark` across: offered (`offered()`), the download mark;
/// ready to restart (`restart()`), only the update mark's outer ring
/// turns green; being put in place
/// (`busy()`), that arrow going up (updating_node); while it comes (`coming()`: Some of a known part or of None for an
/// unknown one), its progress in the mark's place, the two marks faded between each other over a control's ease (dur_ms)
/// without moving the key. Read out a button named `label()`, unable to be pressed while busy; `why()` its tip where it
/// says one (in `tips`); pressed while not busy, `press`.
#callsite(autofill(loc))
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
  restart? : () -> Bool = fn() { false },
  loc~ : SourceLoc,
) -> Unit {
  // (its tip on what holds it: said while busy too, the key taking no press then, as the pointer rests on it)
  parent.box(made_for=loc, fn(o) {
    let hand = tip_node(tips, o, why, within=true)
    let progress = EdgeWay::new(if @signals.untracked(coming) is Some(_) { 1.0 } else { 0.0 })
    o.reacts(fn() { coming() is Some(_) }, fn(on) { progress.go(o, if on { 1.0 } else { 0.0 }, dur_ms) })
    let action = fn() { if restart() { "restart" } else if coming() is Some(_) { "progress" } else if offered() { "download" } else { "update" } }
    // Each action is a button of its own: a press begun on download cannot end on restart after the state changes.
    o.pick(action, fn(slot, was) {
      let rippled : Ref[PressLook?] = Ref(None)
      @headless.button(
        slot,
        label,
        fn(_) { if @signals.untracked(action) == was { press() } },
        disabled=busy,
        hold=@headless.Hold::new(
          @ui.touch_slop(),
          @ui.long_press_ms,
          fn() { @ui.pointing() is Finger },
          on_hold=hand.hold,
          on_lift=hand.lift,
          on_cancel=hand.cancel,
          down=fn(d) { if rippled.val is Some(r) { (r.down)(d) } },
          tapped=fn(d) { if rippled.val is Some(r) { (r.tapped)(d) } },
        ),
        fn(k, b) {
          k
          .width(Is(Some(side)))
          .height(Is(Some(side)))
          .radius(By(fn() { if lit_node(k) && !b.disabled() { side / 2.0 } else { 0.0 } }))
          .lines_up(Is(Some(Middle)))
          .lies_along(Is(Middle))
          .ground(By(fn() { if lit_node(k) && !b.disabled() { @ui.tree_theme().color(Hover) } else { 0L } }))
          |> ignore
          rippled.val = Some(press_look(k, Is(side / 2.0), fn() { false }))
          k.box(fn(m) {
            m.width(Is(Some(mark))).height(Is(Some(mark))) |> ignore
            // The existing marks stay; only the update mark's ring changes colour when a press will restart.
            m.box(fn(ready) {
              ready.over(Is(true)).alpha(By(fn() { 1.0 - progress.shown(ready) })) |> ignore
              ready.pick(busy, fn(r, b) {
                if b {
                  updating_node(r, mark, fn() { theme().p.text })
                } else {
                  r.pick(offered, fn(i, download) {
                    if download {
                      icon_node(i, "download", mark, By(fn() { theme().p.text })) |> ignore
                    } else {
                      icon_inks_node(i, "update", mark, fn(_) {
                        let p = theme().p
                        [([0], if restart() { p.green } else { p.text }), ([1, 2], p.text)]
                      }).drawn_as(Is("/icon/update/")) |> ignore
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
        },
      )
      |> ignore
    })
  })
  |> ignore
}

///|
/// What comes as a node (coming_mark's): in an icon's place `size` across, a ring where the icons draw their circles,
/// the accent from its top as far round as `coming()` says (eased to it over progress_ms; None, a quarter turning), a
/// short arrow down in it, in `color()`.
#callsite(autofill(loc))
fn coming_node(
  parent : @view.View,
  coming : () -> Double?,
  size : Double,
  color : () -> Int64,
  loc~ : SourceLoc,
) -> Unit {
  let stroke = size * icon_stroke / 24.0
  let ring = size * coming_ring / 24.0 + stroke
  parent.box(made_for=loc, fn(b) {
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
#callsite(autofill(loc))
fn updating_node(parent : @view.View, size : Double, color : () -> Int64, loc~ : SourceLoc) -> Unit {
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
  parent.box(made_for=loc, fn(b) {
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
