// A page's compact bar, the one every pushed page of the phone has (Android Parts.kt NavBar, web mobile/parts.css.ts
// mNavbar): back with where it goes, in the accent, at its start; a centred title (and a line under it, `sub`); what
// it does at its end. The back word, the title's first line and what is at the end share one 32 line at the bar's top,
// each in its middle; a title's second line hangs below it, the bar taller by it. (NavBar sets the title's line 30, 1
// higher, to stand on the back word's baseline, with 2 under it: on the Mac's text its letters then stood 1 over the
// back word's. Here the title's line is the 32 and nothing under it: the line under the title and the bar's height
// are NavBar's.) The title is in the middle of the bar inside its padding (10 at the start, 16 at the end) and keeps 84 clear
// at either side.

///|
/// Back: a chevron and where to, 6 after it and 4 over and under, its corner 8; quieter while pressed.
// kept across runs: a value (no field of it changes)
let nav_back_box : @ui.Style = @ui.style(
  row=true,
  pr=S1_5,
  pt=S1,
  pb=S1,
  radius=Lg,
  align=ACenter,
  pressed=@ui.patch(opacity=O60),
)

///|
/// Back's word in a link's ink, its chevron the accent (Parts.kt:491 C.link, 490 C.accent).
// kept across runs: a value (no field of it changes)
let nav_back_words : @ui.TextStyle = @ui.text_style(size=Xl2, leading=Font, color=Link, wrap=false)

///|
/// The bar: 10 in at its start, 16 at its end, 6 over and 10 under (NavBar).
// kept across runs: a value (no field of it changes)
let nav_bar_box : @ui.Style = @ui.style(w=Full, pl=S2_5, pr=S4, pt=S1_5, pb=S2_5)

///|
// kept across runs: a value (no field of it changes)
let nav_bar_inner : @ui.Style = @ui.style(w=Full, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let nav_title_column : @ui.Style = @ui.style(pl=nav_title_clear, pr=nav_title_clear, align=ACenter)

///|
/// The title's first line and back and what is at the end: one 32 line, each in its middle.
// kept across runs: a value (no field of it changes)
let nav_line : @ui.Style = @ui.style(h=S8, justify=JCenter, clip=true)

///|
// kept across runs: a value (no field of it changes)
let nav_title_words : @ui.TextStyle = @ui.text_style(size=Xl, leading=Font, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let nav_sub_row : @ui.Style = @ui.style(row=true, gap=nav_sub_gap, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let nav_ends : @ui.Style = @ui.style(row=true, w=Full, h=S8, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let nav_trailing : @ui.Style = @ui.style(row=true, h=S8, align=ACenter)

///|
/// Back: a chevron in the accent and where to in a link's ink (Parts.kt NavBack); its word no wider than `max_w` when it is said.
/// True on the frame after it was tapped.
pub fn nav_back(c : @ui.Ctx, key : String, label : String, max_w? : Double = 0.0) -> Bool {
  let t = theme()
  let id = c.id(key)
  // its styles' tokens in still.fail's theme, whatever page it is on (only settings' pages put it round them)
  c.with_theme(ui_theme(), fn() {
    c.box(style=nav_back_box, id~, fn() {
      icon(c, "chevron-left", size=22.0, color=t.p.accent) |> ignore
      if max_w > 0.0 {
        c.box(style=@ui.style(max_w=Fixed(max_w)), fn() { c.text(label, style=nav_back_words) |> ignore }) |> ignore
      } else {
        c.text(label, style=nav_back_words) |> ignore
      }
    })
    |> ignore
  })
  c.clicked(id)
}

///|
/// The bar (NavBar): back (`back_key` its id, `back` its word, `back_max` how wide the word may be), `title` in the
/// middle and `sub` under it, `trailing` at the end; on `bg` when it is said. True on the frame after back was tapped.
pub fn nav_bar(
  c : @ui.Ctx,
  back_key : String,
  back : String,
  title : String,
  sub? : () -> Unit,
  trailing? : () -> Unit,
  back_max? : Double = 0.0,
  bg? : Int64 = 0L,
) -> Bool {
  let mut went = false
  c.with_theme(ui_theme(), fn() { went = nav_bar_in(c, back_key, back, title, sub?, trailing?, back_max~, bg~) })
  went
}

///|
fn nav_bar_in(
  c : @ui.Ctx,
  back_key : String,
  back : String,
  title : String,
  sub? : () -> Unit,
  trailing? : () -> Unit,
  back_max~ : Double,
  bg~ : Int64,
) -> Bool {
  let mut went = false
  // det-ok(box-loose): the page's own ground (still.fail's palette, not one of mbui's theme roles yet), as the page has it
  c.box(style=nav_bar_box, bg~, fn() {
    c.box(style=nav_bar_inner, fn() {
      // the title, in the flow: as tall as its lines make the bar
      c.box(style=nav_title_column, fn() {
        c.box(style=nav_line, fn() { c.text(title, style=nav_title_words) |> ignore }) |> ignore
        match sub {
          // its line drawn 4 up, under the title's (NavBar's offset)
          Some(f) => c.box(style=nav_sub_row, ty=-4.0, fn() { f() }) |> ignore
          None => ()
        }
      })
      |> ignore
      // back and what is at the end, on the 32 line at its top
      c.layer(fn() {
        c.box(style=nav_ends, fn() {
          went = nav_back(c, back_key, back, max_w=back_max)
          c.spacer()
          match trailing {
            Some(f) => c.box(style=nav_trailing, fn() { f() }) |> ignore
            None => ()
          }
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
  went
}
