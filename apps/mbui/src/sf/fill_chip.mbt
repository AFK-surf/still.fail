// A rounded box with a figure in it whose ground fills from the left (components.tsx FillChip, which the web's
// QuotaChip, MeterChip and ProgressChip draw): an allowance's window, a machine's CPU, memory or disk, a download. One
// part for every page that shows one (a profile's row, a station's row and its peek, a chat's agents, the model
// control), so that they are one size, one corner and one colour wherever they stand.

///|
/// A fill chip's height: tall enough that the ladder's small corner leaves it no capsule (in a card's corner, 20 in, as
/// concentric with it as a block is). The web's is 20, a capsule nearly; the ladder's corner wants this.
pub let fill_chip_h : Double = 22.0

///|
/// A small one's (`small`: where a line is lower than a row, a station's row, the model control): 16, a capsule.
pub let fill_chip_small_h : Double = 16.0

///|
/// How full, as a colour: the core's level (components.css.ts quotaChip's data-level).
pub fn level_color(level : String) -> Int64 {
  let t = theme()
  match level {
    "red" => t.p.red
    "amber" => t.p.warn_ink
    "progress" => t.p.accent
    _ => t.p.green
  }
}

///|
/// The chip (FillChip): its ground the neutral one, filled from the left as far as `fill` (0–100), grey while the
/// level is ok, faintly the level's colour once it is not (the accent's ink for `progress`: chip_fill_share); its figure
/// and its `mark` before it in the text's colour, whatever the level: the fill says the level, and over it the level's
/// ink, or a grey a step quieter, read too faint (amber 3.3 to 1, the mark 3.9 to 1 in the dark; docs/ui-panels.md
/// 对比度). Its words are the caption's, a screen's own (11 with keyboard and mouse, 12 with touch), 600, tabular.
pub fn fill_chip(
  c : @ui.Ctx,
  fill : Int,
  level : String,
  mark : String,
  words : String,
  small? : Bool = false,
  drop? : Int = 0,
  keep? : Bool = false,
) -> Unit {
  let t = theme()
  let tone = level_color(level)
  let low = level == "amber" || level == "red"
  let ground = if low {
    alpha(tone, chip_fill_share)
  } else if level == "progress" {
    alpha(t.p.accent_text, chip_fill_share)
  } else {
    alpha(t.p.muted, chip_fill_share)
  }
  let fill = if fill < 0 { 0 } else if fill > 100 { 100 } else { fill }
  let rest = 100 - fill
  // (its fill a plain rectangle the chip's clip cuts along its corners; its end square where it stops)
  c.box(style=if small { chip_box_small } else { chip_box }, drop~, keep~, fn() {
    if fill > 0 {
      c.layer(fn() {
        c.box(style=chip_fill_row, fn() {
          c.box(style=chip_fill_part.then(@ui.style(w=Grow(fill.to_double()), bg=Data(ground))), fn() {  }) |> ignore
          if rest > 0 {
            c.box(style=chip_fill_part.then(@ui.style(w=Grow(rest.to_double()))), fn() {  }) |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    }
    c.box(style=if small { chip_words_small } else { chip_words }, fn() {
      if mark != "" {
        c.text(mark, style=chip_text) |> ignore
      }
      c.text(words, style=chip_text) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// How strong its fill is (of the level's colour, the accent's ink, the muted grey): as far off the chip's ground as
/// what is drawn with nothing in it stands (@ui's contrast.mbt), on whatever the chip lies on (a menu's grey too: at
/// the web's 20% an amber fill was 1.24 to 1 there, the accent's light orange less on any).
let chip_fill_share : Double = 0.28

///|
/// Its words: the caption's (11 with keyboard and mouse, 12 with touch: the screen's type), 600, on a line of 16.
// kept across runs: a value (no field of it changes)
let chip_text : @ui.TextStyle = @ui.text_style(size=Caption, weight=Semibold, leading=L4, wrap=false, color=Fg, narrow=@ui.text_patch(size=Xs))

///|
/// The chip: on the neutral ground, round by the ladder's small corner (fill_chip_corner), its words in its middle.
// kept across runs: a value (no field of it changes)
let chip_box : @ui.Style = @ui.style(h=Fixed(fill_chip_h), radius=rounded(fill_chip_corner), bg=Neutral, clip=true, justify=JCenter)

///|
// kept across runs: a value (no field of it changes)
let chip_box_small : @ui.Style = chip_box.then(@ui.style(h=Fixed(fill_chip_small_h)))

///|
// kept across runs: a value (no field of it changes)
let chip_fill_row : @ui.Style = @ui.css("row w=Full h=Full")

///|
// kept across runs: a value (no field of it changes)
let chip_fill_part : @ui.Style = @ui.css("h=Full")

///|
/// Its mark and figure 5 apart, 8 in (a small one's 5).
// kept across runs: a value (no field of it changes)
let chip_words : @ui.Style = @ui.css("row px=S2 gap=S1_25 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let chip_words_small : @ui.Style = @ui.css("row px=S1_25 gap=S1_25 align=ACenter")
