// A segmented choice as the web's narrow pages have it (web/src/mobile/parts.tsx Seg; Android's Parts.kt Seg): mbui's
// sliding toggle group in Seg's look. The wide pages' pill is `segmented` (parts.mbt), the web's controls' Segmented.

///|
/// A segmented choice (Seg): mbui's sliding toggle group (@kit.toggle_group: the arrows move along it, a screen reader
/// reads its options) in Seg's look: a track the ink at 6%, a light thumb (a hairline round it) sliding to the one
/// chosen; an option's words are never cut. `fill`: as wide as where it is, each option an equal share, none narrower
/// than its words (one that needs more keeps that, the others sharing what is left). `pill`: the web's wide pill
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
  let now = @kit.toggle_group(
    c,
    key,
    items,
    [selected.to_string()],
    slide=true,
    grow=fill,
    look=fn(c, st) {
      c.box(
        style=if pill && !compact {
          seg_pill_option
        } else if fill {
          seg_full_option
        } else {
          seg_option
        },
        keep=fill,
        fn() {
          // Parts.kt:424 (14sp filling, else 13sp; the pill the wide pages' 13)
          c.text(
            st.label,
            style=@ui.text_style(size=if pill { Lg } else if fill { Base } else { Sm }, color=if st.on { Fg } else { Muted }, wrap=false),
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
      let track = fn() {
        // det-ok(box-loose, style-literal): its height and corner said where it is used (34 on a page), the ink at 6%
        c.box(style=if fill { seg_track_full } else { seg_track }, h=Px(height), radius~, bg=alpha(t.p.text, 0.06), options)
        |> ignore
      }
      // (in a row, as wide as its options: not stretched to its parent's width)
      if pill {
        c.box(style=seg_pill_line, fn() { track() }) |> ignore
      } else {
        track()
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
// kept across runs: a value (no field of it changes)
let seg_pill_option : @ui.Style = seg_option.then(@ui.style(min_w=seg_pill_min))

///|
/// The pill in a line of its own, not stretched to its width.
// kept across runs: a value (no field of it changes)
let seg_pill_line : @ui.Style = @ui.css("row w=Full")
