// A segmented choice as the web's narrow pages have it (web/src/mobile/parts.tsx Seg; Android's Parts.kt Seg): mbui's
// sliding toggle group in Seg's look. The wide pages' pill is `segmented` (parts.mbt), the web's controls' Segmented.

///|
/// A segmented choice (Seg): mbui's sliding toggle group (@kit.toggle_group: the arrows move along it, a screen reader
/// reads its options) in Seg's look: a track the ink at 6%, a light thumb (a hairline round it) sliding to the one
/// chosen. `fill`: as wide as where it is, each option an equal share, none narrower than its words (one that needs
/// more keeps that, the others sharing what is left); where they all need more than its width, as option_widths has
/// them (their sides narrower, else their words on more lines; cut short only where not even each one's longest word
/// fits): nothing out of view, nothing scrolled. `pill`: the web's wide pill
/// (controls.css.ts seg: options as wide as their words, 105 at least, `compact` as wide as their words alone; 36
/// high). Answers the one chosen (a tap's, this frame).
pub fn seg(
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
  // filling: where its options' words with their sides need more than the track (as last laid out: read back), each
  // as option_widths has it in the track (as alike as the flex has them till then)
  let track = c.id(key + "/track")
  let squeezed = if fill {
    match c.laid_size(track) {
      Some((w, _)) => {
        let size = c.sp(c.text_size(words_size).0)
        let words = options.map(fn(l) { @ui.text_advance(l, size~) })
        let room = w - 2.0 * inset
        if words.fold(init=0.0, fn(s, x) { s + x + 2.0 * seg_side }) > room + 0.5 {
          Some(option_widths(words, options.map(fn(l) { @ui.text_least(l, size~) }), room, seg_side, seg_least))
        } else {
          None
        }
      }
      None => None
    }
  } else {
    None
  }
  let lie = squeezed.map(fn(s) { s.1 }).unwrap_or(OneLine)
  let wraps = lie == Wrapped
  let now = @kit.toggle_group(
    c,
    key,
    items,
    [selected.to_string()],
    slide=true,
    grow=fill,
    widths=squeezed.map(fn(s) { s.0.map(fn(w) { (w, w) }) }).unwrap_or([]),
    look=fn(c, st) {
      c.box(
        style=if pill && !compact {
          seg_pill_option
        } else if fill {
          match squeezed {
            None => seg_full_option
            Some((_, Wrapped)) => seg_wrapped_option
            Some(_) => seg_squeezed_option
          }
        } else {
          seg_option
        },
        keep=fill,
        fn() {
          // Parts.kt:424 (14sp filling, else 13sp; the pill the wide pages' 13)
          c.text(
            st.label,
            style=@ui.text_style(
              size=words_size,
              color=if st.on { Fg } else { Muted },
              wrap=wraps,
              center=wraps,
              w?=match lie {
                OneLine => None
                Wrapped => Some(Full)
                CutShort => Some(Cut)
              },
            ),
          )
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
      let track_box = fn() {
        // (its options wrapped: as tall as they are, that at least)
        // det-ok(box-loose): its height and corner said where it is used (34 on a page), the ink at 6%
        c.box(
          style=if fill { seg_track_full } else { seg_track },
          id=track,
          h?=if wraps { None } else { Some(Px(height)) },
          min_h=height,
          radius~,
          // det-ok(style-literal): the ink at 6%, Seg's own (Parts.kt)
          bg=alpha(t.p.text, 0.06),
          options,
        )
        |> ignore
      }
      // (in a row, as wide as its options: not stretched to its parent's width)
      if pill {
        c.box(style=seg_pill_line, fn() { track_box() }) |> ignore
      } else {
        track_box()
      }
    },
  ).value
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
/// A filling option short of room (option_widths): its words its least in from its sides (seg_least); wrapped, as tall
/// as they are, as far from its top and foot (in the middle of its item, as tall as the tallest: @kit.toggle_group).
// kept across runs: a value (no field of it changes)
let seg_squeezed_option : @ui.Style = seg_full_option.then(@ui.css("px=S1"))

///|
// kept across runs: a value (no field of it changes)
let seg_wrapped_option : @ui.Style = seg_squeezed_option.then(@ui.css("h=Hug py=S1"))

///|
/// A filling option's words' sides (seg_full_option's px=S2), and how little they go to where the room is short
/// (seg_squeezed_option's px=S1).
let seg_side : Double = @ui.Space::px(S2)

///|
let seg_least : Double = @ui.Space::px(S1)

///|
/// How a choice's options' words lie in the widths option_widths gives them: whole on one line, on as many lines as
/// they take (never broken inside a word, nor narrower than four of a script's that breaks anywhere: @ui.text_least),
/// or on one line cut short with an ellipsis, where not even that leaves each its longest word (as the systems' own
/// segmented controls cut theirs).
priv enum OptionWords {
  OneLine
  Wrapped
  CutShort
} derive(Eq, Show, Debug)

///|
/// How wide each of a choice's options is in `room` (all of it, the gaps between them aside), their words `words` wide
/// on one line and `least_words` at their narrowest wrapped (@ui.text_least), and how their words lie in it. As alike
/// as they can be, none narrower than its words with `side` either side; where those come to more than the room, each
/// its words with narrower sides alike (to `least`); where even that is too much, the longest words wrapped, one by
/// one till the rest fit on one line (their sides `side` again, all as alike as they can be, a wrapped one no narrower
/// than its longest word); all wrapped, their sides narrower; and where not even each one's longest word fits, cut
/// short, as alike as they can be, none wider than its words need (the shorter whole, the longer cut alike). Nothing
/// out of view, nothing scrolled.
fn option_widths(
  words : Array[Double],
  least_words : Array[Double],
  room : Double,
  side : Double,
  least : Double,
) -> (Array[Double], OptionWords) {
  let room = dmax(room, 0.0)
  let n = words.length()
  let sum = fn(a : Array[Double]) { a.fold(init=0.0, fn(s, x) { s + x }) }
  let alike = words.map(fn(_) { 1.0 })
  let total = sum(words)
  if total + 2.0 * side * n.to_double() <= room {
    return (shares(room, words.map(fn(w) { w + 2.0 * side }), alike), OneLine)
  }
  if total + 2.0 * least * n.to_double() <= room {
    let s = (room - total) / (2.0 * n.to_double())
    return (words.map(fn(w) { w + 2.0 * s }), OneLine)
  }
  // the longest first
  let order = Array::makei(n, fn(i) { i })
  order.sort_by(fn(a, b) { words[b].compare(words[a]) })
  let wrapped = words.map(fn(_) { false })
  for k in order {
    wrapped[k] = true
    let floors = words.mapi(fn(i, w) { (if wrapped[i] { least_words[i] } else { w }) + 2.0 * side })
    if sum(floors) <= room {
      return (shares(room, floors, alike), Wrapped)
    }
  }
  let floors = least_words.map(fn(w) { w + 2.0 * least })
  if sum(floors) <= room {
    (shares(room, floors, alike), Wrapped)
  } else {
    (capped(room, floors), CutShort)
  }
}

///|
/// `room` shared alike, none given more than its cap: those whose cap is under their share take it, the rest sharing
/// what is left (all their caps, where those come to less than the room).
fn capped(room : Double, caps : Array[Double]) -> Array[Double] {
  let held = caps.map(fn(_) { false })
  for _ in 0..=caps.length() {
    let mut left = room
    let mut free = 0
    for i, c in caps {
      if held[i] {
        left = left - c
      } else {
        free = free + 1
      }
    }
    if free == 0 {
      break
    }
    let share = left / free.to_double()
    let mut more = false
    for i, c in caps {
      if !held[i] && c <= share {
        held[i] = true
        more = true
      }
    }
    if !more {
      return caps.mapi(fn(i, c) { if held[i] { c } else { share } })
    }
  }
  caps
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
