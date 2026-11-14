// 主题色's control (外观): the colour themes (tokens.mbt `accents`) as a row of dots, each in its own colour as the
// theme draws it now (light or dark), the chosen one with a check on it; 自定义 last, a hue of the person's own.

///|
/// The colour themes' dots in a line (`names`: each one's name, what a screen reader says; then `custom`'s, 自定义's,
/// last), the one `chosen` says (its key, the prefs' `accent`) with a check on it (narrow, its first as far in as a
/// section's heading): each a dot 24 across (28 with touch), their middles a press's least room apart
/// (@ui.room_least: 36, 44 with touch; what each reaches, overlapping none). 自定义 last: chosen, a dot in its hue's
/// accent and a slider of hues under the dots, as wide as they are (`hue`: what a screen reader calls it), its track
/// every hue's accent, its knob the one's; not chosen, a ＋ in an outline, which takes the hue it had last
/// (custom_hue_kept). `choose` told the key a person chooses (a press's, a step's or a drag's along the hues; the
/// caller says it chosen then: `chosen` follows it).
#callsite(autofill(loc))
pub fn accent_pick_node(
  parent : @view.View,
  names : () -> Array[String],
  custom : () -> String,
  hue : () -> String,
  chosen : () -> String,
  choose : (String) -> Unit,
  loc~ : SourceLoc,
) -> Unit {
  let own = fn() { custom_hue(chosen()) }
  // (the hue 自定义 takes as it is pressed: the one it has while it is chosen)
  parent.reacts(own, fn(h) {
    match h {
      Some(h) => custom_hue_kept.val = h
      None => ()
    }
  })
  let ink_of = fn(a : AccentTone) { if theme().dark { a.dark } else { a.light } }
  // a dot: in `ink` (an outline round a ＋ where none), with a check where `on`; `press` done as it is pressed
  let a_dot = fn(row : @view.View, ink : () -> Int64?, on : () -> Bool, name : () -> String, press : () -> Unit) {
    row.box(fn(d) {
      let side = dot_side(theme())
      let mark = side * accent_check_part
      let ring = fn() {
        if ink() is None {
          alpha(theme().p.text, accent_open_line)
        } else if lit_node(d) && !on() {
          alpha(theme().p.text, accent_lit_line)
        } else {
          accent_no_ring
        }
      }
      d
      .width(Is(Some(side)))
      .height(Is(Some(side)))
      // (round as a pill is said to be, Full: as round as it can be)
      .radius(Is(1.0e6))
      .lines_up(Is(Some(Middle)))
      .lies_along(Is(Middle))
      .ground(By(fn() { ink().unwrap_or(accent_no_ring) }))
      .edge(By(fn() { (2.0, ring()) }))
      .says(By(fn() { Some(@view.said(Radio, label=name(), selected=on())) }))
      |> ignore
      presses_node(d, press)
      d.show(on, fn(c) { icon_node(c, "check", mark, Is(0xFFFFFFFFL)) |> ignore })
      d.show(fn() { !on() && ink() is None }, fn(c) { icon_node(c, "plus", mark, By(fn() { theme().p.muted })) |> ignore })
    })
    |> ignore
  }
  parent.box(made_for=loc, fn(col) {
    // (narrow, a section's own: in from the page's edge as far as its heading's words, as its note is)
    let start = if look_node(col) is Narrow { accent_narrow_in } else { 0.0 }
    col.gap(Is(accent_column_gap)).padding(Is((start, 0.0, 0.0, 0.0))) |> ignore
    col.box(fn(row) {
      row
      .row(Is(true))
      .gap(Is(8.0))
      .lines_up(Is(Some(Middle)))
      .says(Is(Some(@view.said(RadioGroup))))
      |> ignore
      for i, a in accents {
        let key = a.key
        a_dot(row, fn() { Some(ink_of(a)) }, fn() { chosen() == key }, fn() { names().get(i).unwrap_or(key) }, fn() {
          choose(key)
        })
      }
      a_dot(row, fn() { own().map(fn(h) { ink_of(custom_tone(h)) }) }, fn() { own() is Some(_) }, custom, fn() {
        if @signals.untracked(own) is None {
          choose("custom:" + custom_hue_kept.val.to_string())
        }
      })
    })
    |> ignore
    // 自定义's hues, as wide as the dots
    col.show(fn() { own() is Some(_) }, fn(s) {
      hue_slider_node(s, fn() { own().unwrap_or(custom_hue_kept.val) }, hue, fn(h) {
        custom_hue_kept.val = h
        choose("custom:" + h.to_string())
      })
    })
  })
  |> ignore
}

///|
/// The hues' slider (@kit.slider's geometry, the look the old view's hue_look gave it), as wide as the dots over it: a track 6 high of every hue's
/// accent as the theme draws it, 10 in from each end, round; the knob, 24 across, the hue's accent ringed 2 in the
/// card's ground, its middle running from half the slider's thumb room in to as far from the end. A drag along it, an
/// arrow with the keyboard's focus on it, a screen reader's step (View::on_step) each `step_to` a hue (0 to 355, 5
/// apart), read out as `label`'s slider.
#callsite(autofill(loc))
fn hue_slider_node(
  parent : @view.View,
  now : () -> Int,
  label : () -> String,
  step_to : (Int) -> Unit,
  loc~ : SourceLoc,
) -> Unit {
  let n = (accents.length() + 1).to_double()
  let wide = fn() {
    let side = dot_side(theme())
    n * side + (n - 1.0) * 8.0
  }
  let at = fn() { hue_clamp(now().to_double() / custom_hue_most, 0.0, 1.0) }
  let to_hue = fn(h : Double) {
    let k = (hue_clamp(h, 0.0, custom_hue_most) / custom_hue_step).round()
    (k * custom_hue_step).to_int()
  }
  let go = fn(h : Int) {
    if h != @signals.untracked(now) {
      step_to(h)
    }
  }
  parent.box(made_for=loc, fn(s) {
    s
    .width(By(fn() { Some(wide()) }))
    .height(Is(Some(hue_slider_h)))
    .lies_along(Is(Middle))
    .focusable(Is(true))
    .presses(Is(true))
    .says(By(fn() {
      let h = now().to_double()
      Some(
        @view.said(Slider, label=label(), value=now().to_string(), range=(0.0, h, custom_hue_most), actions=[
          Increment, Decrement,
        ]),
      )
    }))
    .on_step(fn(by) { go(to_hue(@signals.untracked(now).to_double() + by.to_double() * custom_hue_step)) })
    // (held and dragged along: the hue where the hand is, its knob's middle from half its room in to as far from the
    // end)
    .on_drag(fn(d) {
      match d.kind {
        Down | Moved if d.w > hue_thumb_room =>
          go(to_hue(hue_clamp((d.x - hue_thumb_room / 2.0) / (d.w - hue_thumb_room), 0.0, 1.0) * custom_hue_most))
        _ => ()
      }
    })
    // (with the keyboard's focus on it: ← and ↓ a step down, → and ↑ a step up, Home and End its ends)
    .on_key(fn(k) {
      if !s.focused() || k.mods != 0 {
        return false
      }
      let h = @signals.untracked(now).to_double()
      let to = if k.code == @ui.key_code_left || k.code == @ui.key_code_down {
        Some(h - custom_hue_step)
      } else if k.code == @ui.key_code_right || k.code == @ui.key_code_up {
        Some(h + custom_hue_step)
      } else if k.code == @ui.key_code_home {
        Some(0.0)
      } else if k.code == @ui.key_code_end {
        Some(custom_hue_most)
      } else {
        None
      }
      match to {
        Some(t) => {
          go(to_hue(t))
          true
        }
        None => false
      }
    })
    |> ignore
    // its track, every hue's accent
    s.box(fn(t) {
      t
      .height(Is(Some(hue_track_h)))
      .margin(Is((hue_track_in, 0.0, hue_track_in, 0.0)))
      .radius(Is(hue_track_h / 2.0))
      .clips(Is(true))
      .image(By(fn() { Some((hue_strip(theme().dark), "", hue_strip_most)) }))
      |> ignore
    })
    |> ignore
    // its knob, over the track where the hue is along it
    s.box(fn(o) {
      o.over(Is(true)).row(Is(true)).lines_up(Is(Some(Middle))) |> ignore
      o.box(fn(b) { b.grow(By(at)) |> ignore }) |> ignore
      o.box(fn(k) {
        k
        .width(Is(Some(hue_knob_d)))
        .height(Is(Some(hue_knob_d)))
        .radius(Is(hue_knob_d / 2.0))
        .ground(By(fn() { ink_of_hue(now()) }))
        .edge(By(fn() { (2.0, theme().p.canvas) }))
        |> ignore
      })
      |> ignore
      o.box(fn(b) { b.grow(By(fn() { 1.0 - at() })) |> ignore }) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// Hue `h`'s accent as the theme draws it now (light or dark).
fn ink_of_hue(h : Int) -> Int64 {
  let a = custom_tone(h)
  if theme().dark {
    a.dark
  } else {
    a.light
  }
}

///|
/// How much of the slider's width its knob's middle does not run along (@kit.slider's thumb_room: half at each end).
let hue_thumb_room : Double = 22.0

///|
/// The slider's height (h=S7), its track's (h=S1_5) and how far in from each end it is (mx=S2_5), the knob's side
/// (w=S6).
let hue_slider_h : Double = 28.0

///|
let hue_track_h : Double = 6.0

///|
let hue_track_in : Double = 10.0

///|
let hue_knob_d : Double = 24.0

///|
/// The check on the chosen dot (and 自定义's ＋): 0.6 of its side.
let accent_check_part : Double = 0.6

///|
/// The dots and 自定义's hues under them, 8 apart (gap=S2); narrow, a section's own, its first dot as far in as the
/// heading's words (pl=S3).
let accent_column_gap : Double = 8.0

///|
let accent_narrow_in : Double = 12.0

///|
/// A dot's side: 24 across with keyboard and mouse, 28 with touch (w=S6, w=S7).
fn dot_side(t : Theme) -> Double {
  if t.touch {
    28.0
  } else {
    24.0
  }
}

///|
/// The hue 自定义 takes as it is pressed: the one it had last, at first a blue between the five's (210).
// kept across runs: put back as a Tester starts (icons.mbt)
let custom_hue_kept : Ref[Int] = Ref(210)

///|
/// The hues' slider: 0 to 355, 5 apart.
let custom_hue_most : Double = 355.0

///|
let custom_hue_step : Double = 5.0

///|
/// How many pixels across the hues' track's picture is made, each its hue's accent, stretched over the track.
let hue_cells : Int = 72

///|
/// The picture of every hue's accent by day or by night (hue_strip_px across, 1 high), by the key the host keeps it at:
/// made the first time it is asked for (gradient.mbt's way: mbui fills no gradient itself).
fn hue_strip(dark : Bool) -> String {
  let key = "mem:sf-hues/\{dark}/\{hue_cells}"
  if !@ui.has_image(key) {
    let px = FixedArray::make(hue_cells * 4, b'\x00')
    for i in 0..<hue_cells {
      let a = custom_tone((i.to_double() * 360.0 / hue_cells.to_double()).to_int())
      let ink = if dark { a.dark } else { a.light }
      for k in 0..<4 {
        px[i * 4 + k] = ((ink >> (24 - k * 8)) & 0xFFL).to_int().to_byte()
      }
    }
    @ui.add_image(key, @pixels.png(hue_cells, 1, px))
  }
  key
}

///|
/// The outline round 自定义's ＋ while it is not chosen: the ink at 24%.
let accent_open_line : Double = 0.24

///|
/// The ring round a dot under the pointer: the ink at 30%; none round the others.
let accent_lit_line : Double = 0.3

///|
let accent_no_ring : Int64 = 0L

///|
/// The most pixels the hues' picture is asked at (mark_node's pictures').
let hue_strip_most : Int = 8192

///|
fn hue_clamp(x : Double, lo : Double, hi : Double) -> Double {
  if x < lo {
    lo
  } else if x > hi {
    hi
  } else {
    x
  }
}
