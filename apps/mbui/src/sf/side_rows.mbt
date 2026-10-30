// A sidebar's rows (ember web/src/Sidebar.css.ts navRow, navNew, navScroll; SidebarList.tsx NavItem, NavAction): a
// row of one line, a row laid out as a chat's (list_row), the band's action over a list, the list under the band; a
// row's ground as the web moves it. The sidebar's frame (its top row, its width, its fold)
// is the shell's.

///|
/// A row's or a place's ground as the web moves it (Sidebar.css.ts navRow, Rail.css.ts item: `transition: background
/// 140ms` ease out): the pointer's ground in and out, the lit one's (`lit`, the selected grey by default), as the state
/// changes.
pub fn nav_ground(c : @ui.Ctx, key : String, hover : Bool, on : Bool, lit? : Int64) -> Int64 {
  let t = theme()
  let lit = lit.unwrap_or(t.p.selected)
  let h = @kit.animate(c, key + "/hover", if hover { 1.0 } else { 0.0 }, transition=nav_fade)
  let o = @kit.animate(c, key + "/on", if on { 1.0 } else { 0.0 }, transition=nav_fade)
  if h <= 0.0 && o <= 0.0 {
    0L
  } else {
    over(alpha(t.p.hover, h * (1.0 - o)), alpha(lit, o))
  }
}

///|
/// Node `i`'s ground as nav_ground has it, worked out as it is painted (@ui.Ctx::bg_by): its easing to the pointer's
/// ground and to the selected one read as it is drawn, so the row is not built again each frame it eases (docs/retained.md,
/// motion in what is made once).
pub fn nav_ground_on(c : @ui.Ctx, i : Int, key : String, hover : Bool, on : Bool, lit? : Int64) -> Unit {
  let t = theme()
  let lit = lit.unwrap_or(t.p.selected)
  let hover_ink = t.p.hover
  // (the same numbers animate kept them as: @kit.animate's keys)
  let h = @motion.told(c, "\u{2}animate/" + key + "/hover", if hover { 1.0 } else { 0.0 }, spec=nav_fade)
  let o = @motion.told(c, "\u{2}animate/" + key + "/on", if on { 1.0 } else { 0.0 }, spec=nav_fade)
  c.bg_by(i, fn() {
    let h = h.get()
    let o = o.get()
    if h <= 0.0 && o <= 0.0 {
      0L
    } else {
      over(alpha(hover_ink, h * (1.0 - o)), alpha(lit, o))
    }
  })
}

///|
/// What a state's ground changes over (vars.dur: 140 ms, ease out).
// kept across runs: a value (no field of it changes)
pub let nav_fade : @motion.Spec = @motion.tween(dur_ms, ease=Out)

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
  let l = theme().chat_list
  let id = c.id(key)
  let look = l.side_row.then(@ui.style(align~))
  let hover = c.lit(id) || c.pressed(id)
  nav_apart(c, more, fn() {
    let i = c.box(style=look.then(row_least_h()), id~, body)
    nav_ground_on(c, i, key, hover, on)
  })
  c.clicked(id)
}

///|
/// A sidebar's row `row` with another row under it (`more`): the room between two things that light up under it
/// (Sidebar.css.ts navRow `& + &`: 2 over the one after; list_more), so the row
/// pointed at and the page in view never touch and read as one block. The last of a run, a heading under it, as it
/// is: the heading's room is its own.
pub fn nav_apart(c : @ui.Ctx, more : Bool, row : () -> Unit) -> Unit {
  if more {
    c.box(style=list_more(Side), row) |> ignore
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
  let l = theme().chat_list
  let id = c.id(key)
  let hover = c.lit(id) || c.pressed(id)
  let look = band_row_look.then(@ui.style(min_h=Fixed(l.band_h), px=room_of(l.band_pad)))
  let i = c.box(style=look, id~, body)
  nav_ground_on(c, i, key, hover, on)
  c.clicked(id)
}

///|
// kept across runs: a value (no field of it changes)
let band_row_look : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter").then(@ui.style(radius=side_row_radius))

///|
/// A band's action's mark, as large as the search's (the theme's band's).
pub fn band_mark(c : @ui.Ctx, name : String, color : Int64) -> Unit {
  icon(c, name, size=theme().chat_list.band_icon, color~) |> ignore
}

///|
/// A band's action's words, as long as there is room (the theme's band's: the search field's size).
pub fn band_words(c : @ui.Ctx, words : String) -> Unit {
  c.text(words, style=theme().chat_list.band_words) |> ignore
}

///|
/// How high a band's row is (the theme's band's).
pub fn band_row_h() -> Double {
  theme().chat_list.band_h
}

///|
/// A row's words, as long as there is room (`color`: the words' own by default): a list's title's (the theme's chats'
/// list's: 13 on 20 with keyboard and mouse, 16 on 22 with touch).
pub fn nav_words(c : @ui.Ctx, words : String, color? : Int64) -> Unit {
  let base = theme().chat_list.title
  let look = match color {
    Some(k) => base.then(@ui.text_style(color=Data(k)))
    None => base
  }
  c.text(words, style=look) |> ignore
}

///|
/// The action over a list (SidebarList.tsx NavAction, in its band: Sidebar.css.ts navNew, 6 over it, 8 at its sides, 2
/// under, the list's own 4 then): its ＋ (16, the row's mark column, ICON) and words, a row of its own; none, and no
/// band, where it cannot be done. Pressed, `run` goes on with it as what opened what it puts up.
pub fn nav_action(c : @ui.Ctx, key : String, label : String, run : ((Beside) -> Unit)?) -> Unit {
  let t = theme()
  match run {
    Some(go) =>
      c.box(style=nav_new(), fn() {
        if band_row(c, key, false, fn() {
            band_mark(c, "plus", t.p.muted)
            band_words(c, label)
          }) {
          go(Of(c.id(key)))
        }
      })
      |> ignore
    None => ()
  }
}

///|
/// The band an action over a list stands in (Sidebar.css.ts navNew): 6 over, 2 under, as far in at its sides as the
/// theme's band (the search's field's); what is beside the action (the filter, 更新) as far from it as keys are
/// (keys_gap: 4 with keyboard and mouse, 12 with touch).
pub fn nav_new() -> @ui.Style {
  nav_new_look.then(@ui.style(px=room_of(theme().chat_list.band_in), gap=keys_gap()))
}

///|
// kept across runs: a value (no field of it changes)
let nav_new_look : @ui.Style = @ui.css("row w=Full pt=S1_5 pb=S0_5 align=ACenter")

///|
/// The list under a sidebar's band (Sidebar.css.ts navScroll): in at its sides as the theme's sidebar's lists are, 4
/// under the band.
pub fn side_list() -> @ui.Style {
  theme().chat_list.side_list.then(side_list_top)
}

///|
// kept across runs: a value (no field of it changes)
let side_list_top : @ui.Style = @ui.css("pt=S1")

///|
/// A sidebar's list under its band (side_list): what `rows` builds and the room under its last (list_foot_in),
/// scrolling under the band when it is taller than the room (a list of one: `key` keeps where it is scrolled to).
pub fn side_scroll(c : @ui.Ctx, key : String, rows : () -> Unit) -> Unit {
  // The rows keep their inset; the scroll track belongs to the whole sidebar.
  c.box(style=side_list().then(@ui.style(px=S0)), fn() {
    c.list(key, 1, side_scroll_est, fn(_) {
      c.box(style=theme().chat_list.side_list.then(@ui.style(h=Hug)), fn() {
        rows()
        // (the room under its last)
        c.box(style=@ui.style(h=Fixed(list_foot_in(Side))), fn() {  }) |> ignore
      })
      |> ignore
    })
    |> ignore
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
/// row, laid out as a chat's (list_row): its `mark` beside its first line, its `title` (nav_title) with what is at
/// that line's `end` (muted, never cut: the title gives way), then the `lines` under them (list_row_line each; `keep_lines` of
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
  let ground = nav_ground(c, key, c.lit(id) || c.pressed(id), on)
  nav_apart(c, more, fn() {
    list_row(
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
/// A row's title (SidebarList.css.ts title: the theme's chats' list's, a chat's title's), as long as there is room;
/// `away`, what it is not there now: faint.
pub fn nav_title(c : @ui.Ctx, words : String, away? : Bool = false) -> Unit {
  let look = theme().chat_list.title.then(nav_title_grow)
  c.text(words, style=if away { look.then(nav_title_away) } else { look }) |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let nav_item_end : @ui.Style = @ui.css("row gap=S1_25 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let nav_title_grow : @ui.TextStyle = @ui.text_style(w=grow)

///|
// kept across runs: a value (no field of it changes)
let nav_title_away : @ui.TextStyle = @ui.text_style(color=Muted)

///|
/// What a row says in a line under its title or at its end (SidebarList.css.ts line, end): a chat's second line's
/// words (the theme's chats' list's), as long as they are.
pub fn nav_meta() -> @ui.TextStyle {
  theme().chat_list.last.then(nav_meta_hug)
}

///|
// kept across runs: a value (no field of it changes)
let nav_meta_hug : @ui.TextStyle = @ui.text_style(w=Hug)
