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
/// Back's word in a link's ink, its chevron the accent (490 C.accent).
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
/// The title's line with what is beside it, 6 after it (as the wide head's title_about).
// kept across runs: a value (no field of it changes)
let nav_line_after : @ui.Style = nav_line.then(@ui.css("row gap=S1_5 align=ACenter"))

///|
/// What a mark after the title takes (an icon's room).
// kept across runs: a value (no field of it changes)
let nav_mark_room : @ui.Style = @ui.css("w=S5 h=S5")

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
/// itself, a fill's, was 2.8 to 1 there: mbui ui/contrast.mbt). Its word no wider than `max_w`
/// (when that is said): there whole or not at all (Ctx::box drop), the chevron alone where it has not the room, as
/// iOS's back button gives way; never cut short past knowing (the user, 2026-10-25). It is still what the button is
/// called. `on_press` as it is pressed.
pub fn nav_back(c : @ui.Ctx, key : String, label : String, max_w? : Double = 0.0, on_press? : () -> Unit) -> Unit {
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
  match on_press {
    Some(f) => c.on_press(id, f)
    None => ()
  }
}

///|
/// The bar (NavBar): back (`back_key` its id, `back` its word, `back_max` how wide the word may be), `title` in the
/// middle and `sub` under it (`title_after` after it, a mark as wide as an icon's room, S5: an ⓘ; the title kept in
/// the middle, as without it), `trailing` at the end; on `bg` when it is said, from `top` above it down (the status
/// bar's height, the view under it: NavBar's windowInsetsPadding(statusBars)). `on_press` when back is tapped.
pub fn nav_bar(
  c : @ui.Ctx,
  back_key : String,
  back : String,
  title : String,
  sub? : () -> Unit,
  title_after? : () -> Unit,
  trailing? : () -> Unit,
  back_max? : Double = 0.0,
  bg? : Int64 = 0L,
  top? : Double = 0.0,
  on_press? : () -> Unit,
) -> Unit {
  nav_bar_in(c, back_key, back, title, sub?, title_after?, trailing?, back_max~, bg~, top~, on_press?)
}

///|
fn nav_bar_in(
  c : @ui.Ctx,
  back_key : String,
  back : String,
  title : String,
  sub? : () -> Unit,
  title_after? : () -> Unit,
  trailing? : () -> Unit,
  back_max~ : Double,
  bg~ : Int64,
  top~ : Double,
  on_press? : () -> Unit,
) -> Unit {
  // det-ok(box-loose): the page's own ground (still.fail's palette, not one of mbui's theme roles yet), as the page has it
  c.box(style=nav_bar_box, bg~, fn() {
    // under the status bar
    if top > 0.0 {
      c.box(style=@ui.style(w=Full, h=Fixed(top)), fn() {  }) |> ignore
    }
    c.box(style=nav_bar_inner, fn() {
      // the title, in the flow: as tall as its lines make the bar
      c.box(style=nav_title_column, fn() {
        match title_after {
          Some(f) =>
            c.box(style=nav_line_after, fn() {
              // (as much room before the title as the mark takes after it: the title where it stands without one)
              c.box(style=nav_mark_room, fn() {  }) |> ignore
              c.text(title, style=nav_title_words) |> ignore
              f()
            })
            |> ignore
          None => c.box(style=nav_line, fn() { c.text(title, style=nav_title_words) |> ignore }) |> ignore
        }
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
          nav_back(c, back_key, back, max_w=back_max, on_press?)
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
}

///|
/// The bar (nav_bar's) as nodes in `parent`: back to where `back` says (nav_back_node), `on_back` as it is pressed;
/// `title` in the middle, 84 clear of either side, cut short where it has less; what `trailing` makes at its end, on
/// back's 32 line; on the page's ground, from `top` above it down (the status bar's height as it is).
#callsite(autofill(loc))
pub fn nav_bar_node(
  parent : @view.View,
  back : () -> String,
  title : () -> String,
  on_back : () -> Unit,
  top? : () -> Double = fn() { 0.0 },
  trailing? : (@view.View) -> Unit,
  loc~ : SourceLoc,
) -> Unit {
  parent.box(made_for=loc, fn(b) {
    b
    .padding(Is((nav_bar_x, nav_bar_top, nav_bar_x, nav_bar_foot)))
    .ground(By(fn() { theme().p.bg }))
    |> ignore
    // under the status bar
    b.box(fn(s) { s.height(By(fn() { Some(top()) })) |> ignore }) |> ignore
    b.box(fn(i) {
      i.lines_up(Is(Some(Middle))) |> ignore
      // the title, in the flow: as tall as its line makes the bar
      i.box(fn(col) {
        col.padding(Is((nav_title_x, 0.0, nav_title_x, 0.0))).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
        col.box(fn(l) {
          l.height(Is(Some(nav_line_h))).lies_along(Is(Middle)).clips(Is(true)).min_width(Is(Some(0.0))) |> ignore
          l.box(fn(w) {
            styled_words(w, title, fn() { nav_title_words }).cuts(Is(true)).min_width(Is(Some(0.0))) |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
      // back and what is at the end, on the 32 line at its top
      i.box(fn(e) {
        e.over(Is(true)).row(Is(true)).height(Is(Some(nav_line_h))).lines_up(Is(Some(Middle))) |> ignore
        nav_back_node(e, back, on_back)
        e.box(fn(gap) { gap.grow(Is(1.0)) |> ignore }) |> ignore
        match trailing {
          Some(f) =>
            e.box(fn(t) {
              t.row(Is(true)).height(Is(Some(nav_line_h))).lines_up(Is(Some(Middle))) |> ignore
              f(t)
            })
            |> ignore
          None => ()
        }
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// nav_bar_box's room (16 at either end, 6 over, 10 under), the title's clear of either side (nav_title_clear) and
/// the line back, the title and what is at the end share (nav_line's 32).
let nav_bar_x : Double = 16.0

///|
let nav_bar_top : Double = 6.0

///|
let nav_bar_foot : Double = 10.0

///|
let nav_title_x : Double = 84.0

///|
let nav_line_h : Double = 32.0
