// 主题色's control (外观): the colour themes (tokens.mbt `accents`) as a row of dots, each in its own colour as the
// theme draws it now (light or dark), the chosen one with a check on it; 自定义 last, a hue of the person's own.

///|
/// The colour themes' dots in a line (`names`: each one's name, what a screen reader says; then `custom`'s, 自定义's,
/// last), the one `chosen` says (its key, the prefs' `accent`) with a check on it (narrow, its first as far in as a
/// section's heading): each a dot 24 across (28 with touch), their middles a press's least room apart
/// (@ui.room_least: 36, 44 with touch; what each reaches, overlapping none). 自定义 last: chosen, a dot in its hue's
/// accent and a slider of hues under the dots, as wide as they are (`hue`: what a screen reader calls it), its track
/// every hue's accent, its knob the one's; not chosen, a ＋ in an outline, which takes the hue it had last
/// (custom_hue_kept). `on_pick`: what choosing another does, given its key, as it is chosen (a dot pressed, the hue
/// moved), outside any build. Answers the key chosen (a press's, a drag's, this frame).
pub fn accent_pick(
  c : @ui.Ctx,
  key : String,
  names : Array[String],
  custom : String,
  hue : String,
  chosen : String,
  on_pick? : (String) -> Unit,
) -> String {
  let told = fn(k : String) {
    match on_pick {
      Some(f) if k != chosen => f(k)
      _ => ()
    }
  }
  let t = theme()
  // (a dot 24 across with keyboard and mouse, 28 with touch, the gap between the rest of a press's least room)
  let (dot, row_gap) = if t.touch { (accent_dot_touch, accent_row_touch) } else { (accent_dot_mouse, accent_row_mouse) }
  let mut picked = chosen
  let own = custom_hue(chosen)
  match own {
    Some(h) => custom_hue_kept.val = h
    None => ()
  }
  // a dot: in `ink` (an outline round a ＋ where none), with a check where `on`; true on the frame it is pressed
  let a_dot = fn(n : Int, ink : Int64?, on : Bool, name : String, picks : () -> String) -> Bool {
    let id = c.id(key + "/" + n.to_string())
    c.on_press(id, fn() { told(picks()) })
    let lit = c.lit(id)
    let ring = if ink is None { alpha(t.p.text, accent_open_line) } else if lit && !on { alpha(t.p.text, accent_lit_line) } else { accent_no_ring }
    let b = c.box(style=dot.then(@ui.style(bg=Data(ink.unwrap_or(accent_no_ring)), border_color=Data(ring))), id~, fn() {
      let mark = if t.touch { accent_check_touch } else { accent_check_mouse }
      if on {
        icon(c, "check", size=mark, color=0xFFFFFFFFL) |> ignore
      } else if ink is None {
        icon(c, "plus", size=mark, color=t.p.muted) |> ignore
      }
    })
    c.semantics(b, Radio, id~, label=name, selected=on)
    c.clicked(id)
  }
  // (narrow, a section's own: in from the page's edge as far as its heading's words, as its note is)
  let column = if look() is Narrow && in_card.val == 0 { accent_column.then(accent_row_narrow) } else { accent_column }
  c.box(style=column, fn() {
    let row = c.box(style=row_gap, fn() {
      for i, a in accents {
        if a_dot(i, Some(if t.dark { a.dark } else { a.light }), chosen == a.key, names.get(i).unwrap_or(a.key), fn() { a.key }) {
          picked = a.key
        }
      }
      let ink = own.map(fn(h) {
        let a = custom_tone(h)
        if t.dark {
          a.dark
        } else {
          a.light
        }
      })
      // (pressed while chosen: it stays as it is)
      let mine = fn() { if own is None { "custom:" + custom_hue_kept.val.to_string() } else { chosen } }
      if a_dot(accents.length(), ink, own is Some(_), custom, mine) && own is None {
        picked = "custom:" + custom_hue_kept.val.to_string()
      }
    })
    c.semantics(row, RadioGroup)
    // 自定义's hues, as wide as the dots
    match own {
      Some(h) => {
        let n = (accents.length() + 1).to_double()
        let wide = n * dot_side(t) + (n - 1.0) * (@ui.room_least() - dot_side(t))
        c.box(style=@ui.style(w=Fixed(wide)), fn() {
          let now = @kit.slider(
            c,
            key + "/hue",
            h.to_double(),
            min=0.0,
            max=custom_hue_most,
            step=custom_hue_step,
            w=Fill(1.0),
            label=hue,
            look=hue_look,
            on_change=fn(v) { told("custom:" + v.to_int().to_string()) },
          ).value.to_int()
          if now != h {
            picked = "custom:" + now.to_string()
          }
        })
        |> ignore
      }
      None => ()
    }
  })
  |> ignore
  picked
}

///|
/// A dot's side (accent_dot_mouse, accent_dot_touch).
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
/// The hues' slider's look (@kit.slider's geometry: its knob's middle from 11 in to 11 from the end): a track 6 high of every hue's accent as the theme draws it, round at its ends; the knob the hue's accent,
/// ringed in the card's ground.
fn hue_look(c : @ui.Ctx, s : @kit.SliderState) -> Unit {
  let t = theme()
  let f = if s.t < 0.0 { 0.0 } else if s.t > 1.0 { 1.0 } else { s.t }
  let ink_of = fn(h : Double) {
    let a = custom_tone(h.to_int())
    if t.dark {
      a.dark
    } else {
      a.light
    }
  }
  c.box(style=hue_slider_box, fn() {
    c.box(style=hue_track, fn() {
      c.image(hue_strip(t.dark), w=Fill(1.0), h=Fill(1.0), fit=FitFill, bg=accent_no_ring, fade=false) |> ignore
    })
    |> ignore
    c.layer(fn() {
      c.box(style=hue_knob_row, fn() {
        c.box(style=@ui.style(w=Grow(f)), fn() {  }) |> ignore
        let ink = ink_of(f * custom_hue_most)
        c.box(style=hue_knob.then(@ui.style(bg=Data(ink), border_color=Data(t.p.canvas))), fn() {  }) |> ignore
        let rest = 1.0 - f
        c.box(style=@ui.style(w=Grow(rest)), fn() {  }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// The slider's height, its track 10 in from each end (about half the knob), 6 high and round.
// kept across runs: a value (no field of it changes)
let hue_slider_box : @ui.Style = @ui.css("w=Full h=S7 justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let hue_track : @ui.Style = @ui.css("row w=Full h=S1_5 mx=S2_5 radius=Full clip")

///|
// kept across runs: a value (no field of it changes)
let hue_knob_row : @ui.Style = @ui.css("row w=Full h=Full align=ACenter")

///|
/// The knob, 24 across, ringed 2 in the card's ground.
// kept across runs: a value (no field of it changes)
let hue_knob : @ui.Style = @ui.css("w=S6 h=S6 radius=Full border=B2")

///|
/// A dot with keyboard and mouse (24 across), and with touch (28).
// kept across runs: a value (no field of it changes)
let accent_dot_mouse : @ui.Style = @ui.css("w=S6 h=S6 radius=Full align=ACenter justify=JCenter border=B2")

///|
// kept across runs: a value (no field of it changes)
let accent_dot_touch : @ui.Style = @ui.css("w=S7 h=S7 radius=Full align=ACenter justify=JCenter border=B2")

///|
/// The dots' row with keyboard and mouse (12 apart: 24 and 12, a pointer's least room, 36), and with touch (16: 28 and
/// 16, a finger's 44).
// kept across runs: a value (no field of it changes)
let accent_row_mouse : @ui.Style = @ui.css("row gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let accent_row_touch : @ui.Style = @ui.css("row gap=S4 align=ACenter")

///|
/// The check on the chosen dot, 0.6 of its side.
let accent_check_mouse : Double = 14.4

///|
let accent_check_touch : Double = 16.8

///|
/// The outline round 自定义's ＋ while it is not chosen: the ink at 24%.
let accent_open_line : Double = 0.24

///|
/// The ring round a dot under the pointer: the ink at 30%; none round the others.
let accent_lit_line : Double = 0.3

///|
let accent_no_ring : Int64 = 0L

///|
/// The dots, and 自定义's hues under them.
// kept across runs: a value (no field of it changes)
let accent_column : @ui.Style = @ui.css("gap=S2")

///|
/// Narrow, a section's own: its first dot as far in as the heading's words.
// kept across runs: a value (no field of it changes)
let accent_row_narrow : @ui.Style = @ui.css("pl=S3")
