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
/// A row of a sidebar's list (Sidebar.css.ts navRow): 32 high at least, 6 by 10 in (`tall`, a list's item: 7, its words from
/// the top), its corner a sidebar row's (@sf.side_row_radius); the pointer's ground on hover, the selected one's ground when it is the page in view.
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
let nav_row_look : @ui.Style = @ui.css("row w=Full min_h=S8 px=S2_5 py=S1_5 gap=S2").then(@ui.style(radius=@sf.side_row_radius))

///|
// kept across runs: a value (no field of it changes)
let nav_row_phone : @ui.Style = @ui.css("row w=Full pr=S4 py=S2_5 gap=S2 align=ACenter").then(@ui.style(pl=@sf.phone_row_in))

///|
// kept across runs: a value (no field of it changes)
let nav_row_tall : @ui.Style = @ui.css("row w=Full min_h=S8 px=S2_5 gap=S2 align=AStart").then(
  @ui.style(py=@sf.row_in, radius=@sf.side_row_radius),
)

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
/// The action over a list (SidebarList.tsx NavAction, in its band: Sidebar.css.ts navNew, 6 over it, 8 at its sides, 2
/// under, the list's own 4 then): its ＋ (16, the row's mark column, ICON) and words, a row of its own; none, and no
/// band, where it cannot be done.
pub fn nav_action(c : @ui.Ctx, key : String, label : String, run : (() -> Unit)?) -> Unit {
  let t = @sf.theme()
  match run {
    Some(go) =>
      c.box(style=nav_new, fn() {
        if nav_row(c, key, false, fn() {
            @sf.icon(c, "plus", size=nav_mark_side, color=t.p.muted) |> ignore
            nav_words(c, label)
          }) {
          go()
        }
      })
      |> ignore
    None => ()
  }
}

///|
/// The band an action over a list stands in (Sidebar.css.ts navNew): 6 over, 8 at its sides, 2 under; what is beside
/// the action 4 from it.
// kept across runs: a value (no field of it changes)
pub let nav_new : @ui.Style = @ui.css("row w=Full px=S2 pt=S1_5 pb=S0_5 gap=S1 align=ACenter")

///|
/// The list under a sidebar's band (Sidebar.css.ts navScroll): 8 in at its sides, 4 under the band.
// kept across runs: a value (no field of it changes)
pub let side_list : @ui.Style = @ui.css("w=Full h=Full px=S2 pt=S1")

///|
/// A row's mark's side (SidebarList.css.ts mark, the action's icon: ICON's 16).
pub let nav_mark_side : Double = 16.0

///|
/// A row of a list in a sidebar, a station's, a profile's, a folder's (SidebarList.tsx NavItem, laid out as a chat's
/// row): its `mark` in a column 16 wide on its first line's middle, 8 before the rest; its `title` on a line of 20
/// (nav_title) with what is at that line's `end` (12, muted, never cut: the title gives way); then the `lines` under
/// them (nav_line each), 2 apart; 7 over and under. True when pressed.
pub fn nav_item(
  c : @ui.Ctx,
  key : String,
  on : Bool,
  mark : () -> Unit,
  title : () -> Unit,
  end? : () -> Unit,
  lines? : () -> Unit,
) -> Bool {
  nav_row(c, key, on, tall=true, fn() {
    c.box(style=nav_item_mark, mark) |> ignore
    c.box(style=nav_item_text, fn() {
      c.box(style=nav_item_head, fn() {
        title()
        match end {
          Some(e) => c.box(style=nav_item_end, e) |> ignore
          None => ()
        }
      })
      |> ignore
      match lines {
        Some(l) => l()
        None => ()
      }
    })
    |> ignore
  })
}

///|
/// A line under a row's title (SidebarList.css.ts line): 18 high at least, its parts 4 apart, centred.
pub fn nav_line(c : @ui.Ctx, body : () -> Unit) -> Unit {
  c.box(style=nav_line_box, body) |> ignore
}

///|
/// A row's title (SidebarList.css.ts title): 13 on 20, as long as there is room; `away`, what it is not there now:
/// faint.
pub fn nav_title(c : @ui.Ctx, words : String, away? : Bool = false) -> Unit {
  c.text(words, style=if away { nav_title_away } else { nav_title_look }) |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let nav_item_mark : @ui.Style = @ui.css("w=S4 h=S5 align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let nav_item_text : @ui.Style = @ui.style(w=@sf.grow, gap=S0_5)

///|
// kept across runs: a value (no field of it changes)
let nav_item_head : @ui.Style = @ui.css("row w=Full h=S5 gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let nav_item_end : @ui.Style = @ui.css("row gap=S1_25 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let nav_line_box : @ui.Style = @ui.css("row w=Full min_h=S4_5 gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let nav_title_look : @ui.TextStyle = @ui.text_style(size=Sm, color=Fg, leading=L6, wrap=false, w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let nav_title_away : @ui.TextStyle = nav_title_look.then(@ui.text_style(color=Muted))

///|
/// What a row says in a line under its title or at its end (SidebarList.css.ts line, end): 12 on 18, muted.
// kept across runs: a value (no field of it changes)
pub let nav_meta : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, leading=L5, wrap=false)
