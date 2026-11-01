// A page's compact bar, the one every pushed page of the phone has (Android Parts.kt NavBar, web mobile/parts.css.ts
// mNavbar): back with where it goes, in the accent, at its start; a centred title (and a line under it, `sub`); what
// it does at its end. The back word, the title's first line and what is at the end share one 32 line at the bar's top,
// each in its middle; a title's second line hangs below it, the bar taller by it. (NavBar sets the title's line 30, 1
// higher, to stand on the back word's baseline, with 2 under it: on the Mac's text its letters then stood 1 over the
// back word's. Here the title's line is the 32 and nothing under it: the line under the title and the bar's height
// are NavBar's.) The title is in the middle of the bar inside its padding (16 at either end) and keeps 84 clear
// at either side.

///|
/// Back: a chevron and where to, 6 after it and 4 over and under, its corner 8; rippled where it is pressed
/// (Parts.kt NavBack: clip(Smooth(8)).clickable).
// kept across runs: a value (no field of it changes)
let nav_back_box : @ui.Style = @ui.css("row pr=S1_5 pt=S1 pb=S1 radius=Lg align=ACenter")

///|
/// Back's word in a link's ink, its chevron the accent (Parts.kt:491 C.link, 490 C.accent).
// kept across runs: a value (no field of it changes)
let nav_back_words : @ui.TextStyle = @ui.text_style(size=Title, leading=Font, color=Link, wrap=false)

///|
/// The bar: 16 in at each end, 6 over and 10 under.
// kept across runs: a value (no field of it changes)
let nav_bar_box : @ui.Style = @ui.css("w=Full px=S4 pt=S1_5 pb=S2_5")

///|
// kept across runs: a value (no field of it changes)
let nav_bar_inner : @ui.Style = @ui.css("w=Full align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let nav_title_column : @ui.Style = @ui.style(w=Cut, pl=nav_title_clear, pr=nav_title_clear, align=ACenter)

///|
/// The title's first line and back and what is at the end: one 32 line, each in its middle. The title and the line
/// under it as wide as they are, cut short where the bar has less (mNavbar's ellipsis): never past the 84 clear.
// kept across runs: a value (no field of it changes)
let nav_line : @ui.Style = @ui.css("w=Cut h=S8 justify=JCenter clip")

///|
// kept across runs: a value (no field of it changes)
let nav_title_words : @ui.TextStyle = @ui.text_style(size=Title, leading=Font, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let nav_sub_row : @ui.Style = @ui.style(row=true, w=Cut, gap=nav_sub_gap, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let nav_ends : @ui.Style = @ui.css("row w=Full h=S8 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let nav_trailing : @ui.Style = @ui.css("row h=S8 align=ACenter")

///|
/// Back: a chevron and where to in a link's ink, the accent's that reads on the page (Parts.kt NavBack; the accent
/// itself, a fill's, was 2.8 to 1 there: docs/ui-panels.md 对比度). Its word no wider than `max_w`
/// (when that is said): there whole or not at all (Ctx::box drop), the chevron alone where it has not the room, as
/// iOS's back button gives way; never cut short past knowing (the user, 2026-10-25). It is still what the button is
/// called. True on the frame after it was tapped.
pub fn nav_back(c : @ui.Ctx, key : String, label : String, max_w? : Double = 0.0) -> Bool {
  let t = theme()
  let id = c.id(key)
  c.box(style=nav_back_box, id~, label=label, fn() {
    icon(c, "chevron-left", size=22.0, color=t.p.accent_text) |> ignore
    if max_w > 0.0 {
      c.box(style=@ui.style(row=true, max_w=Fixed(max_w)), fn() {
        c.box(id=c.id(key + "/word"), taps=false, drop=1, fn() { c.text(label, style=nav_back_words) |> ignore })
        |> ignore
      })
      |> ignore
    } else {
      c.text(label, style=nav_back_words) |> ignore
    }
    @motion.ripple(c, id, 8.0)
  })
  |> ignore
  c.clicked(id)
}

///|
/// The bar (NavBar): back (`back_key` its id, `back` its word, `back_max` how wide the word may be), `title` in the
/// middle and `sub` under it, `trailing` at the end; on `bg` when it is said, from `top` above it down (the status
/// bar's height, the view under it: NavBar's windowInsetsPadding(statusBars)). True on the frame after back was tapped.
pub fn nav_bar(
  c : @ui.Ctx,
  back_key : String,
  back : String,
  title : String,
  sub? : () -> Unit,
  trailing? : () -> Unit,
  back_max? : Double = 0.0,
  bg? : Int64 = 0L,
  top? : Double = 0.0,
) -> Bool {
  nav_bar_in(c, back_key, back, title, sub?, trailing?, back_max~, bg~, top~)
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
  top~ : Double,
) -> Bool {
  let mut went = false
  // det-ok(box-loose): the page's own ground (still.fail's palette, not one of mbui's theme roles yet), as the page has it
  c.box(style=nav_bar_box, bg~, fn() {
    // under the status bar
    if top > 0.0 {
      c.box(style=@ui.style(w=Full, h=Fixed(top)), fn() {  }) |> ignore
    }
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
