// A row of a list (ember web/src/Sidebar.tsx ChatRow; SidebarList.tsx NavItem, "laid out as a chat's"): a chat's, a
// station's, a folder's, a profile's are one row: its mark beside its first line, its first line (its title and what
// stands at that line's end), then the lines under it; its sizes the theme's chats' list's, how far in and whether its
// ground is rounded where its list stands (ListAt).

///|
/// Row `id` of a list standing `at`, on `ground` (lit, pressed or pointed at: the caller's): `mark` beside its first
/// line where it has one (a station's, a profile's), its first line (`head`: its title and what is at its end), the lines
/// under it (`under`), then `after` over it all (a ripple). `high`: as high as a chat's row always is (the theme's
/// `row`), else as what it holds (`item`); `faded`: its words faded (a chat settled); `end_room`: room kept at its
/// first line's end (for what a caller lays over it there: 归档). Its box, the one pressed.
pub fn list_row(
  c : @ui.Ctx,
  id : Int,
  at : ListAt,
  ground : Int64,
  head : () -> Unit,
  under : () -> Unit,
  mark? : () -> Unit,
  high? : Bool = false,
  faded? : Bool = false,
  end_room? : Double = 0.0,
  after? : () -> Unit = fn() {  },
) -> Int {
  let l = theme().chat_list
  let line = @ui.style(h=Fixed(l.head_h))
  c.box(style=(if high { l.row } else { l.item }).then(list_row_in(at)).then(@ui.style(bg=Data(ground))), id~, fn() {
    match mark {
      Some(m) => c.box(style=list_row_mark.then(line), m) |> ignore
      None => ()
    }
    c.box(style=if faded { l.text_settled } else { l.text }, fn() {
      c.box(style=if end_room > 0.0 { l.head.then(@ui.style(pr=room(end_room))) } else { l.head }, head) |> ignore
      under()
    })
    |> ignore
    after()
  })
}

///|
/// A line under a row's first line (SidebarList.css.ts line): as high as a chat's second line, its parts beside each
/// other.
pub fn list_row_line(c : @ui.Ctx, body : () -> Unit) -> Unit {
  c.box(style=theme().chat_list.meta, body) |> ignore
}

///|
/// A row's mark's column (SidebarList.css.ts mark: 16 wide, as high as the first line, its mark in its middle).
// kept across runs: a value (no field of it changes)
let list_row_mark : @ui.Style = @ui.css("w=S4 align=ACenter justify=JCenter")

///|
/// A row's box with another row under it, where its list stands (ListAt): in a side column, where its ground is
/// rounded and in, 2 under it with either input (lit_apart; Sidebar.css.ts navRow `& + &`), so the row pressed or
/// pointed at and the one open never touch and read as one block; across the whole screen the theme's (its rows
/// flush with a finger).
pub fn list_more(at : ListAt) -> @ui.Style {
  match at {
    Side => side_more
    Whole => theme().chat_list.more
  }
}

///|
// kept across runs: a value (no field of it changes)
// (pb: lit_apart's 2, the scale's S0_5)
let side_more : @ui.Style = @ui.css("w=Full pb=S0_5")

///|
/// A heading over a part of a list (SidebarList.tsx NavSection; Sidebar.css.ts navHeading: the chats' days, the
/// profiles' kinds, a sidebar's parts), its look the theme's chats' list's, in from the list's left as its rows are where
/// the list stands (`at`).
pub fn list_heading(c : @ui.Ctx, label : String, at : ListAt) -> Unit {
  let l = theme().chat_list
  c.box(style=l.heading.then(list_heading_in(at)), fn() { c.text(label, style=l.heading_words) |> ignore }) |> ignore
}

///|
/// The room between two groups of a list where no heading stands over the second (the settings' groups in a sidebar):
/// a heading's room over it (`heading`'s 14), so a group reads apart from the one over it as one under a heading does.
pub fn list_apart(c : @ui.Ctx) -> Unit {
  c.box(style=list_apart_room, fn() {  }) |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let list_apart_room : @ui.Style = @ui.css("w=Full h=S3_5")
