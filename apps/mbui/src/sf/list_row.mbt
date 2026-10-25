// A row of a list (ember web/src/Sidebar.tsx ChatRow; SidebarList.tsx NavItem, "laid out as a chat's"): a chat's, a
// station's, a folder's, a profile's are one row: its mark beside its first line, its first line (its title and what
// stands at that line's end), then the lines under it; its sizes the theme's chats' list's, how far in and whether its
// ground is rounded where its list stands (ListAt).

///|
/// Row `id` of a list standing `at`, on `ground` (lit, pressed or pointed at: the caller's): `mark` beside its first
/// line where it has one (a station's, a profile's), its first line (`head`: its title and what is at its end), the lines
/// under it (`under`), then `after` over it all (a ripple). `high`: as high as a chat's row always is (the theme's
/// `row`), else as what it holds (`item`); `faded`: its words faded (a chat settled); `head_room`: room at its first
/// line's end (归档 over it). Its box, the one pressed.
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
  head_room? : Bool = false,
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
      c.box(style=if head_room { l.head_room } else { l.head }, head) |> ignore
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
