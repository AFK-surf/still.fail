// A segmented choice as the web's narrow pages have it (web/src/mobile/parts.tsx Seg; Android's Parts.kt Seg): mbui's
// sliding toggle group in Seg's look. Not a part of its own: `segmented` (parts.mbt) draws it on a narrow page, the
// web's Segmented on a wide one.

///|
/// A segmented choice (Seg): mbui's sliding toggle group (@kit.toggle_group: the arrows move along it, a screen reader
/// reads its options) in Seg's look: a track the ink at 6%, a light thumb (a hairline round it) sliding to the one
/// chosen. `fill`: as wide as where it is, each option an equal share, none narrower than its words (one that needs
/// more keeps that, the others sharing what is left); where they all need more than its width, as option_widths has
/// them: their sides narrower, else their words smaller alike (to the system's own size of words), else the chosen one
/// alone, the others in a pick (choice_pick). Always one line, each one's words whole: nothing wrapped, cut or scrolled.
/// `pill`: the web's wide pill
/// (controls.css.ts seg: options as wide as their words, 105 at least, `compact` as wide as their words alone; 36
/// high). Answers the one chosen (a tap's, this frame).
fn seg(
  c : @ui.Ctx,
  key : String,
  options : Array[String],
  selected : Int,
  fill? : Bool = false,
  height? : Double = 30.0,
  radius? : Double = 10.0,
  pill? : Bool = false,
  compact? : Bool = false,
) -> Int {
  let t = theme()
  let fill = fill && !pill
  let height = if pill { 36.0 } else { height }
  let radius = if pill { 18.0 } else { radius }
  let inset = 2.0
  let thumb = if t.dark { 0x3A3B40FFL } else { 0xFFFFFFFFL }
  let items = options.mapi(fn(i, l) { @kit.item(i.to_string(), label=l) })
  let words_size : @ui.TextSize = if pill { Lg } else if fill { Base } else { Sm }
  // filling: where its options' words with their sides need more than the track (as last laid out: read back), as
  // option_widths has them in it (as alike as the flex has them till then)
  let track = c.id(key + "/track")
  let base = c.text_size(words_size).0
  let fit = if fill {
    match c.laid_size(track) {
      Some((w, _)) => {
        let size = c.sp(base)
        let words = options.map(fn(l) { @ui.text_advance(l, size~) })
        let room = w - 2.0 * inset
        if words.fold(init=0.0, fn(s, x) { s + x + 2.0 * seg_side }) > room + 0.5 {
          Some(fitted(c, options, room, base, 400, seg_side, seg_least))
        } else {
          None
        }
      }
      None => None
    }
  } else {
    None
  }
  // its track: round its options, or round the chosen one's words where they do not fit side by side
  let track_box = fn(inner : () -> Unit) -> Int {
    // det-ok(box-loose): its height and corner said where it is used (34 on a page), the ink at 6%
    c.box(
      style=if fill { seg_track_full } else { seg_track },
      id=track,
      h=Px(height),
      radius~,
      // det-ok(style-literal): the ink at 6%, Seg's own (Parts.kt)
      bg=alpha(t.p.text, 0.06),
      inner,
    )
  }
  // (not side by side: the chosen one in its track, as wide; all of them in a pick)
  if fit is Some({ fit: Menu, .. }) {
    return choice_pick(c, key, track, options, selected, fn(c, _, words) {
      track_box(fn() {
        c.box(style=seg_menu, fn() {
          c.text(words, style=seg_menu_words) |> ignore
          icon(c, "chevron-down", size=seg_chevron, color=t.p.muted) |> ignore
        })
        |> ignore
      })
    })
  }
  // (made smaller to fit: their words drawn that much smaller)
  let smaller = match fit {
    Some({ fit: Smaller(k), .. }) => k
    _ => 1.0
  }
  let now = c.words_smaller(smaller, fn() {
    @kit.toggle_group(
      c,
      key,
      items,
      [selected.to_string()],
      slide=true,
      grow=fill,
      widths=fit.map(fn(f) { f.widths.map(fn(w) { (w, w) }) }).unwrap_or([]),
      look=fn(c, st) {
        c.box(
          style=if pill && !compact {
            seg_pill_option
          } else if fit is Some(_) {
            seg_squeezed_option
          } else if fill {
            seg_full_option
          } else {
            seg_option
          },
          keep=fill,
          fn() {
            // Parts.kt:424 (14sp filling, else 13sp; the pill the wide pages' 13)
            c.text(st.label, style=@ui.text_style(size=words_size, color=if st.on { Fg } else { Muted }, wrap=false))
            |> ignore
          },
        )
        |> ignore
      },
      // the thumb behind the options, over the one chosen: to another on its spring, placed at once the first time (as
      // Seg's first placement jumps)
      thumb=fn(c, w, h) {
        // det-ok(box-loose, style-literal): the thumb's size the group works out, its corner concentric in the track's
        c.box(w=Px(w), h=Px(h), radius=inner_corner(radius, inset), bg=thumb, border=0.5, border_color=t.p.line, fn() {  })
        |> ignore
      },
      ground=fn(c, _, options) {
        // (in a row, as wide as its options: not stretched to its parent's width)
        if pill {
          c.box(style=seg_pill_line, fn() { track_box(options) |> ignore }) |> ignore
        } else {
          track_box(options) |> ignore
        }
      },
    ).value
  })
  // the chosen one tapped again stays chosen
  match now {
    [v] => items.search_by(fn(it) { it.value == v }).unwrap_or(selected)
    _ => selected
  }
}

///|
/// Seg's track (its height and corner said where it is used): its options in a line, 2 in; as wide as where it is
/// (`fill`) or as they are.
// kept across runs: a value (no field of it changes)
let seg_track : @ui.Style = @ui.css("row p=S0_5")

///|
// kept across runs: a value (no field of it changes)
let seg_track_full : @ui.Style = seg_track.then(@ui.css("w=Full"))

///|
/// An option: its words in its middle, 10 in (in a row: as wide as its words at least); where the track fills, an
/// equal share, 8 in at least (the web's narrow Seg: five parts' English words in a phone's 320); the pill's 101 at
/// least.
// kept across runs: a value (no field of it changes)
let seg_option : @ui.Style = @ui.css("row h=Full px=S2_5 align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let seg_full_option : @ui.Style = seg_option.then(@ui.css("w=Full px=S2"))

///|
/// A filling option short of room (option_widths): its words its least in from its sides (seg_least).
// kept across runs: a value (no field of it changes)
let seg_squeezed_option : @ui.Style = seg_full_option.then(@ui.css("px=S1"))

///|
/// A filling Seg whose options do not fit side by side (choice_pick), in its track: the chosen one's words at its
/// start (as far in as an option's, the same size, in ink, cut short where they must be), a chevron at its end; a
/// press on the track opens the pick.
// kept across runs: a value (no field of it changes)
let seg_menu : @ui.Style = @ui.css("row w=Full h=Full px=S2_5 gap=S2 align=ACenter justify=JBetween")

///|
// kept across runs: a value (no field of it changes)
let seg_menu_words : @ui.TextStyle = @ui.text_style(size=Body, color=Fg, w=Cut, wrap=false)

///|
let seg_chevron : Double = 16.0

///|
/// A filling option's words' sides (seg_full_option's px=S2), and how little they go to where the room is short
/// (seg_squeezed_option's px=S1).
let seg_side : Double = @ui.Space::px(S2)

///|
let seg_least : Double = @ui.Space::px(S1)

///|
/// How a choice's options fit the room option_widths gives them: their words at their size; their words made smaller
/// alike, by this much (down to the system's own size of words, as the systems' own segmented controls make theirs);
/// or not side by side at all, the chosen one alone and the others offered in a pick (choice_pick).
priv enum Fit {
  Whole
  Smaller(Double)
  Menu
} derive(Eq, Show, Debug)

///|
/// How wide each of a choice's options is in `room` (all of it, the gaps between them aside), their words `words`
/// wide, and how they fit it: as alike as they can be, none narrower than its words with `side` either side; where
/// those come to more than the room, each its words with their sides narrower alike (to `least`); where even that is
/// too much, their words made smaller alike till they fit with the least either side, `smallest` of their size at the
/// least; else not side by side (Menu, no widths). Always one line, each one's words whole: nothing wrapped, cut or
/// scrolled (the user, 2026-10-25: a sideways scroll and words on two lines alike ugly).
fn option_widths(
  words : Array[Double],
  room : Double,
  side : Double,
  least : Double,
  smallest : Double,
) -> (Array[Double], Fit) {
  let room = dmax(room, 0.0)
  let n = words.length().to_double()
  let total = words.fold(init=0.0, fn(s, w) { s + w })
  if total + 2.0 * side * n <= room {
    return (shares(room, words.map(fn(w) { w + 2.0 * side }), words.map(fn(_) { 1.0 })), Whole)
  }
  if total + 2.0 * least * n <= room {
    let s = (room - total) / (2.0 * n)
    return (words.map(fn(w) { w + 2.0 * s }), Whole)
  }
  let k = if total > 0.0 { (room - 2.0 * least * n) / total } else { 0.0 }
  if k >= smallest && k > 0.0 {
    (words.map(fn(w) { w * k + 2.0 * least }), Smaller(k))
  } else {
    ([], Menu)
  }
}

///|
/// A choice's options fitted to its room (option_widths): their widths, and how they fit (made smaller, their words
/// drawn so: Ctx::words_smaller).
priv struct Fitted {
  widths : Array[Double]
  fit : Fit
}

///|
/// `labels`' options fitted to `room`, their words said in `base` and `weight`, `side` either side and `least` at the
/// least: made smaller, their widths those words' as drawn then, what is left shared alike.
fn fitted(
  c : @ui.Ctx,
  labels : Array[String],
  room : Double,
  base : Double,
  weight : Int,
  side : Double,
  least : Double,
) -> Fitted {
  let size = c.sp(base)
  let words = labels.map(fn(l) { @ui.text_advance(l, size~, weight~) })
  // (no smaller than the app says them: the size the system's own size of words draws)
  let (widths, fit) = option_widths(words, room, side, least, dmin(1.0, base / size))
  match fit {
    // (their words as drawn that much smaller, what is left shared alike)
    Smaller(k) => {
      let drawn = labels.map(fn(l) { @ui.text_advance(l, size=size * k, weight~) })
      let left = (room - drawn.fold(init=0.0, fn(s, w) { s + w })) / labels.length().to_double()
      { widths: drawn.map(fn(w) { w + left }), fit }
    }
    _ => { widths, fit }
  }
}

///|
/// A choice whose options do not fit side by side (choice_pick): the pick opened from it (as presented: 0, none yet),
/// and what was picked in it, till its caller has it.
priv struct ChoicePick {
  mut serial : Int
  mut picked : Int?
}

///|
/// Each choice that has been drawn not side by side, by its key.
let choice_picks : Map[String, ChoicePick] = {}

///|
fn init {
  @ui.on_reset(fn() { choice_picks.clear() })
}

///|
/// A choice of a few whose options do not fit side by side (option_widths: Menu): `look` draws the chosen one's words
/// in box `id` (its track's: as wide as where it is, read back as the track is), a chevron beside them; pressed, a pick
/// of them all opens under it (a sheet for a finger), the chosen one marked. What is chosen now: what was picked, from
/// the frame the pick tells it till `chosen` is it.
fn choice_pick(
  c : @ui.Ctx,
  key : String,
  id : Int,
  labels : Array[String],
  chosen : Int,
  look : (@ui.Ctx, Int, String) -> Int,
) -> Int {
  let p = match choice_picks.get(key) {
    Some(p) => p
    None => {
      let p = { serial: 0, picked: None }
      choice_picks[key] = p
      p
    }
  }
  let now = match p.picked {
    Some(i) if i != chosen => i
    _ => {
      p.picked = None
      chosen
    }
  }
  c.cursor(id, Hand)
  if c.clicked(id) {
    let choices = labels.mapi(fn(i, l) { choice(i.to_string(), l) })
    pick("", choices, now.to_string(), fn(k) { p.picked = Some(labels_at(labels, k, now)) }, from=Of(id))
    p.serial = last_presented()
  }
  let words = labels.get(now).unwrap_or("")
  let b = look(c, id, words)
  c.semantics(b, Button, id~, label=words, expanded=p.serial != 0 && presented_drawn_of(p.serial))
  now
}

///|
/// The option of `labels` a pick's key `k` names (its index), else `none`.
fn labels_at(labels : Array[String], k : String, none : Int) -> Int {
  for i in 0..<labels.length() {
    if i.to_string() == k {
      return i
    }
  }
  none
}

///|
/// `room` shared by `weights`, none given less than its floor: those whose share falls short take their floor, the
/// rest sharing what is left by theirs (as CSS's flex with min-widths). Where the floors come to more than the room,
/// the room shared by them.
fn shares(room : Double, floors : Array[Double], weights : Array[Double]) -> Array[Double] {
  let floored = floors.fold(init=0.0, fn(s, f) { s + f })
  if floored >= room && floored > 0.0 {
    return floors.map(fn(f) { room * f / floored })
  }
  let held = floors.map(fn(_) { false })
  for _ in 0..=floors.length() {
    let mut left = room
    let mut weight = 0.0
    for i, f in floors {
      if held[i] {
        left = left - f
      } else {
        weight = weight + weights[i]
      }
    }
    let mut more = false
    for i, f in floors {
      if !held[i] && left * weights[i] / weight < f {
        held[i] = true
        more = true
      }
    }
    if !more {
      return floors.mapi(fn(i, f) { if held[i] { f } else { left * weights[i] / weight } })
    }
  }
  floors
}

///|
// kept across runs: a value (no field of it changes)
let seg_pill_option : @ui.Style = seg_option.then(@ui.style(min_w=seg_pill_min))

///|
/// The pill in a line of its own, not stretched to its width.
// kept across runs: a value (no field of it changes)
let seg_pill_line : @ui.Style = @ui.css("row w=Full")
