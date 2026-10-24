// What every sidebar is made of (ember web/src/Sidebar.css.ts brand, navRow, navHeading, navEmpty; SidebarList.tsx
// NavItem): its top row, its rows to press, a heading over a part of a list, rows to come breathing.

///|
/// The band's first row (Sidebar.css.ts brand): beside the rail only a margin (8); in a window with its buttons in the
/// app's top row, their row (44), which drags the window; none in the closed bar, which starts under that row: where
/// the block's move has got to (frame's --brand).
pub fn side_top(c : @ui.Ctx) -> Unit {
  let id = c.id("side/top")
  if @ui.window_inset() && !side_folded() {
    c.window_drag(id)
  }
  c.box(style=side_full.then(@ui.style(h=Fixed(wide.brand_h))), id~, fn() {  }) |> ignore
}

///|
/// The band's first row's height (side_top).
pub fn side_top_h() -> Double {
  wide.brand_h
}

///|
let side_top_inset : Double = 44.0

///|
let side_top_web : Double = 8.0

///|
// kept across runs: a value (no field of it changes)
let side_full : @ui.Style = @ui.css("w=Full")

///|
/// A row of a sidebar's list (Sidebar.css.ts navRow): 32 high at least, 6 by 10 in (`tall`: 8, its words from the
/// top), its corner the nav's; the pointer's ground on hover, the selected one's ground when it is the page in view.
/// `phone`: as a finger's list has it (SidebarList.css.ts phone): as wide as its box, 22 in on the left and 16 on the
/// right, 10 over and under, its words a size up (nav_words's `phone`). True on the frame after a press.
pub fn nav_row(
  c : @ui.Ctx,
  key : String,
  on : Bool,
  body : () -> Unit,
  tall? : Bool = false,
  align? : @ui.Align = ACenter,
  phone? : Bool = false,
) -> Bool {
  let id = c.id(key)
  c.cursor(id, Hand)
  let look = if phone {
    nav_row_phone
  } else if tall {
    nav_row_tall
  } else {
    nav_row_look.then(@ui.style(align~))
  }
  let ground = nav_ground(c, key, c.lit(id) || c.pressed(id), on)
  c.box(style=look.then(@ui.style(bg=Data(ground))), id~, body) |> ignore
  c.clicked(id)
}

///|
// kept across runs: a value (no field of it changes)
let nav_row_look : @ui.Style = @ui.css("row w=Full min_h=S8 px=S2_5 py=S1_5 gap=S2 radius=Xl")

///|
// kept across runs: a value (no field of it changes)
let nav_row_phone : @ui.Style = @ui.css("row w=Full pr=S4 py=S2_5 gap=S2 align=ACenter").then(@ui.style(pl=@sf.phone_row_in))

///|
// kept across runs: a value (no field of it changes)
let nav_row_tall : @ui.Style = @ui.css("row w=Full min_h=S8 px=S2_5 py=S2 gap=S2 align=AStart radius=Xl")

///|
/// A heading over a part of a list (Sidebar.css.ts navHeading): 12 on 18, muted, 14 above, 4 under; `phone`, as a
/// finger's list has it (SidebarList.css.ts phoneHeading: as the chats' days are): 15, bold, in the words' colour, 14
/// above, 6 under, 20 in.
pub fn nav_heading(c : @ui.Ctx, label : String, phone? : Bool = false) -> Unit {
  c.box(style=if phone { nav_heading_phone } else { nav_heading_box }, fn() {
    c.text(label, style=if phone { nav_heading_phone_words } else { nav_heading_words }) |> ignore
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let nav_heading_phone : @ui.Style = @ui.css("w=Full px=S5 pt=S3_5 pb=S1_5")

///|
// kept across runs: a value (no field of it changes)
let nav_heading_phone_words : @ui.TextStyle = @ui.text_style(size=Lg, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let nav_heading_box : @ui.Style = @ui.css("w=Full px=S2 pt=S3_5 pb=S1")

///|
// kept across runs: a value (no field of it changes)
let nav_heading_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, leading=L5, wrap=false)

///|
/// A row's words, 13 on 20, as long as there is room (`color`: the words' own by default); `phone`, 16 on 22 (a
/// finger's list: SidebarList.css.ts phone's title).
pub fn nav_words(c : @ui.Ctx, words : String, color? : Int64, phone? : Bool = false) -> Unit {
  let base = if phone { nav_words_phone } else { nav_words_look }
  let look = match color {
    Some(k) => base.then(@ui.text_style(color=Data(k)))
    None => base
  }
  c.text(words, style=look) |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let nav_words_look : @ui.TextStyle = @ui.text_style(size=Sm, color=Fg, leading=L6, wrap=false, w=Full)

///|
// kept across runs: a value (no field of it changes)
let nav_words_phone : @ui.TextStyle = @ui.text_style(size=Xl, color=Fg, leading=L7, wrap=false, w=Full)

///|
/// Rows to come, breathing (Waiting shape rows, dense): six, each a title and a line under it.
pub fn side_breathing(c : @ui.Ctx) -> Unit {
  let breath = @sf.breath(c)
  c.box(style=breathing_list, fn() {
    for k in 0..<6 {
      let row = c.box(style=breathing_row, fn() {
        c.box(style=if k % 2 == 0 { breathing_title } else { breathing_title_long }, fn() {  }) |> ignore
        c.box(style=breathing_line, fn() {  }) |> ignore
      })
      c.look(row, @ui.look(alpha=breath))
    }
  })
  |> ignore
}

///|
/// The waiting rows' bars: a title 120 or 150 long and 12 high, a line 180 long and 10 high (Waiting dense).
let breath_title_w : Double = 120.0

///|
let breath_title_long_w : Double = 150.0

///|
let breath_line_w : Double = 180.0

///|
// kept across runs: a value (no field of it changes)
let breathing_list : @ui.Style = @ui.css("w=Full pt=S2 gap=S3 px=S2_5")

///|
// kept across runs: a value (no field of it changes)
let breathing_row : @ui.Style = @ui.css("w=Full gap=S1_5")

///|
// kept across runs: a value (no field of it changes)
let breathing_title : @ui.Style = @ui.style(w=Fixed(breath_title_w), h=S3, radius=Full, bg=Neutral)

///|
// kept across runs: a value (no field of it changes)
let breathing_title_long : @ui.Style = @ui.style(w=Fixed(breath_title_long_w), h=S3, radius=Full, bg=Neutral)

///|
// kept across runs: a value (no field of it changes)
let breathing_line : @ui.Style = @ui.style(w=Fixed(breath_line_w), h=S2_5, radius=Full, bg=Neutral)

///|
/// The action at the top of a list (SidebarList.tsx NavTop's NavAction): its ＋ and words, a row of its own; none where
/// it cannot be done.
pub fn nav_action(c : @ui.Ctx, key : String, label : String, run : (() -> Unit)?) -> Unit {
  let t = @sf.theme()
  match run {
    Some(go) =>
      if nav_row(c, key, false, fn() {
          @sf.icon(c, "plus", size=@sf.row_icon, color=t.p.muted) |> ignore
          nav_words(c, label)
        }) {
        go()
      }
    None => ()
  }
}
