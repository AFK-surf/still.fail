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
/// A row of one line of a sidebar's list (Sidebar.css.ts navRow; touch's SidebarList.css.ts phone: the theme's
/// chats' list's `side_row`): the pointer's ground on hover, the selected one's ground when it is the page in view;
/// `more`, another row under it (nav_apart). True on the frame after a press.
pub fn nav_row(
  c : @ui.Ctx,
  key : String,
  on : Bool,
  body : () -> Unit,
  align? : @ui.Align = ACenter,
  more? : Bool = false,
) -> Bool {
  let l = @sf.theme().chat_list
  let id = c.id(key)
  c.cursor(id, Hand)
  let look = l.side_row.then(@ui.style(align~))
  let ground = nav_ground(c, key, c.lit(id) || c.pressed(id), on)
  nav_apart(c, more, fn() {
    c.box(style=look.then(@sf.finger_least_h()).then(@ui.style(bg=Data(ground))), id~, body) |> ignore
  })
  c.clicked(id)
}

///|
/// A sidebar's row `row` with another row under it (`more`): the room between two things that light up under it
/// (Sidebar.css.ts navRow `& + &`: 2 over the one after; @sf.list_more), so the row
/// pointed at and the page in view never touch and read as one block. The last of a run, a heading under it, as it
/// is: the heading's room is its own.
fn nav_apart(c : @ui.Ctx, more : Bool, row : () -> Unit) -> Unit {
  if more {
    c.box(style=@sf.list_more(Side), row) |> ignore
  } else {
    row()
  }
}


///|
/// An action in a sidebar's band over its list (新建对话, Pin 文件夹, 待处理: Sidebar.css.ts navNew's row): not one of the
/// list's rows but the band's, on one line with what else stands over the list (the search's field): its height, its
/// words' room and its words the theme's chats' list's band's; its corner a sidebar row's; the pointer's ground on
/// hover, the selected one's when it is the page in view. True on the frame after a press.
pub fn band_row(c : @ui.Ctx, key : String, on : Bool, body : () -> Unit) -> Bool {
  let l = @sf.theme().chat_list
  let id = c.id(key)
  c.cursor(id, Hand)
  let ground = nav_ground(c, key, c.lit(id) || c.pressed(id), on)
  let look = band_row_look.then(@ui.style(min_h=Fixed(l.band_h), px=@sf.room_of(l.band_pad), bg=Data(ground)))
  c.box(style=look, id~, body) |> ignore
  c.clicked(id)
}

///|
// kept across runs: a value (no field of it changes)
let band_row_look : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter").then(@ui.style(radius=@sf.side_row_radius))

///|
/// A band's action's mark, as large as the search's (the theme's band's).
pub fn band_mark(c : @ui.Ctx, name : String, color : Int64) -> Unit {
  @sf.icon(c, name, size=@sf.theme().chat_list.band_icon, color~) |> ignore
}

///|
/// A band's action's words, as long as there is room (the theme's band's: the search field's size).
pub fn band_words(c : @ui.Ctx, words : String) -> Unit {
  c.text(words, style=@sf.theme().chat_list.band_words) |> ignore
}

///|
/// How high a band's row is (the theme's band's).
fn band_row_h() -> Double {
  @sf.theme().chat_list.band_h
}

///|
/// A row's words, as long as there is room (`color`: the words' own by default): a list's title's (the theme's chats'
/// list's: 13 on 20 with keyboard and mouse, 16 on 22 with touch).
pub fn nav_words(c : @ui.Ctx, words : String, color? : Int64) -> Unit {
  let base = @sf.theme().chat_list.title
  let look = match color {
    Some(k) => base.then(@ui.text_style(color=Data(k)))
    None => base
  }
  c.text(words, style=look) |> ignore
}

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
      c.box(style=nav_new(), fn() {
        if band_row(c, key, false, fn() {
            band_mark(c, "plus", t.p.muted)
            band_words(c, label)
          }) {
          go()
        }
      })
      |> ignore
    None => ()
  }
}

///|
/// The band an action over a list stands in (Sidebar.css.ts navNew): 6 over, 2 under, as far in at its sides as the
/// theme's band (the search's field's); what is beside the action 4 from it.
pub fn nav_new() -> @ui.Style {
  nav_new_look.then(@ui.style(px=@sf.room_of(@sf.theme().chat_list.band_in)))
}

///|
// kept across runs: a value (no field of it changes)
let nav_new_look : @ui.Style = @ui.css("row w=Full pt=S1_5 pb=S0_5 gap=S1 align=ACenter")

///|
/// The list under a sidebar's band (Sidebar.css.ts navScroll): in at its sides as the theme's sidebar's lists are, 4
/// under the band.
pub fn side_list() -> @ui.Style {
  @sf.theme().chat_list.side_list.then(side_list_top)
}

///|
// kept across runs: a value (no field of it changes)
let side_list_top : @ui.Style = @ui.css("pt=S1")

///|
/// A sidebar's list under its band (side_list): what `rows` builds, scrolling under the band when it is taller than
/// the room (a list of one: `key` keeps where it is scrolled to).
pub fn side_scroll(c : @ui.Ctx, key : String, rows : () -> Unit) -> Unit {
  c.box(style=side_list(), fn() {
    c.list(key, 1, side_scroll_est, fn(_) { c.box(style=side_full, fn() { rows() }) |> ignore }) |> ignore
  })
  |> ignore
}

///|
/// A sidebar's list's height guessed before it is laid out (side_scroll).
let side_scroll_est : Double = 600.0

///|
/// A row's mark's side (SidebarList.css.ts mark, the action's icon: ICON's 16).
pub let nav_mark_side : Double = 16.0

///|
/// A row of a list in a sidebar, a station's, a profile's, a folder's (SidebarList.tsx NavItem): the library's list
/// row, laid out as a chat's (@sf.list_row): its `mark` beside its first line, its `title` (nav_title) with what is at
/// that line's `end` (muted, never cut: the title gives way), then the `lines` under them (nav_line each; `keep_lines` of
/// them always, empty where it says none: list_row `lines`); the pointer's
/// ground on hover, the selected one's when it is the page in view; `more`, another row under it (nav_apart). True
/// when pressed.
pub fn nav_item(
  c : @ui.Ctx,
  key : String,
  on : Bool,
  mark : () -> Unit,
  title : () -> Unit,
  end? : () -> Unit,
  lines? : () -> Unit,
  keep_lines? : Int = 0,
  more? : Bool = false,
) -> Bool {
  let id = c.id(key)
  c.cursor(id, Hand)
  let ground = nav_ground(c, key, c.lit(id) || c.pressed(id), on)
  nav_apart(c, more, fn() {
    @sf.list_row(
      c,
      id,
      Side,
      ground,
      mark~,
      fn() {
        title()
        match end {
          Some(e) => c.box(style=nav_item_end, e) |> ignore
          None => ()
        }
      },
      fn() {
        match lines {
          Some(l) => l()
          None => ()
        }
      },
      lines=keep_lines,
    )
    |> ignore
  })
  c.clicked(id)
}

///|
/// A line under a row's title (SidebarList.css.ts line: @sf.list_row_line).
pub fn nav_line(c : @ui.Ctx, body : () -> Unit) -> Unit {
  @sf.list_row_line(c, body)
}

///|
/// A row's title (SidebarList.css.ts title: the theme's chats' list's, a chat's title's), as long as there is room;
/// `away`, what it is not there now: faint.
pub fn nav_title(c : @ui.Ctx, words : String, away? : Bool = false) -> Unit {
  let look = @sf.theme().chat_list.title.then(nav_title_grow)
  c.text(words, style=if away { look.then(nav_title_away) } else { look }) |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let nav_item_end : @ui.Style = @ui.css("row gap=S1_25 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let nav_title_grow : @ui.TextStyle = @ui.text_style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let nav_title_away : @ui.TextStyle = @ui.text_style(color=Muted)

///|
/// What a row says in a line under its title or at its end (SidebarList.css.ts line, end): a chat's second line's
/// words (the theme's chats' list's), as long as they are.
pub fn nav_meta() -> @ui.TextStyle {
  @sf.theme().chat_list.last.then(nav_meta_hug)
}

///|
// kept across runs: a value (no field of it changes)
let nav_meta_hug : @ui.TextStyle = @ui.text_style(w=Hug)
