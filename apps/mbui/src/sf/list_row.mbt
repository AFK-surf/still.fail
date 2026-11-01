// A row of a list (ember web/src/Sidebar.tsx ChatRow; SidebarList.tsx NavItem, "laid out as a chat's"): a chat's, a
// station's, a folder's, a profile's are one row: its mark beside its first line, its first line (its title and what
// stands at that line's end), then the lines under it; its sizes the theme's chats' list's, how far in and whether its
// ground is rounded where its list stands (ListAt).

///|
/// Row `id` of a list standing `at`, on `ground` (lit, pressed or pointed at: the caller's): `mark` beside its first
/// line where it has one (a station's, a profile's), its first line (`head`: its title and what is at its end), the lines
/// under it (`under`), then `after` over it all (a ripple). `high`: as high as a chat's row always is (the theme's
/// `row`), else as what it holds (`item`); `end_room`: room kept at its
/// first line's end (for what a caller lays over it there: 归档); `corner`: what stands in its foot's end corner (a
/// chat's people and agents), `corner_w` wide, placed there by the corner rule: where its ground is rounded (a side
/// column's), as far in from the row's end and foot as makes it concentric with the row's corner (the theme's
/// `aside_end`), its room kept at the end of the lines under the first (across the whole screen, square, the caller
/// says it in its lines); `lines`: how many lines under its first it always has (list_row_line's), those `under` does
/// not draw kept empty, so rows of a kind are as high whatever each says (a station's, up or away); `slotted`: in the
/// slot it is moved across in (list_row_slot: a finger's swipe), whose corners are its: its own ground square, so
/// nothing shows between it and what it uncovers beside it as it moves; `end_slot`: how wide what stands at its first
/// line's end is, in one column with the last of what stands in its corner (`corner_end` wide: a face's by default).
/// `foot`: a last line across the row, under the mark's column too. `foot_capsule`: the height of a capsule on that
/// line, whose foot must be at the corner's inset. Its box, the one pressed.
pub fn list_row(
  c : @ui.Ctx,
  id : Int,
  at : ListAt,
  ground : Int64,
  head : () -> Unit,
  under : () -> Unit,
  mark? : () -> Unit,
  high? : Bool = false,
  end_room? : Double = 0.0,
  corner? : () -> Unit,
  corner_w? : Double = 0.0,
  lines? : Int = 0,
  after? : () -> Unit = fn() {  },
  slotted? : Bool = false,
  end_slot? : Double = 0.0,
  corner_end? : Double = 0.0,
  ground_by? : () -> Int64,
  foot? : () -> Unit,
  foot_capsule? : Double,
) -> Int {
  let l = theme().chat_list
  let line = @ui.style(h=Fixed(l.head_h))
  // (the lines under its first: those it says, then empty ones up to `lines`)
  let under = fn() {
    let was = lines_drawn.val
    lines_drawn.val = 0
    under()
    for _ in lines_drawn.val..<lines {
      list_row_line(c, fn() {  })
    }
    lines_drawn.val = was
  }
  // (its ground worked out as it is painted where it is given so: @ui.Ctx::bg_by)
  let ground = match ground_by {
    Some(_) => @ui.style()
    None => @ui.style(bg=Data(ground))
  }
  let ground = if slotted { ground.then(list_row_square) } else { ground }
  // A capsule on the last line can reach the row's foot corner. Its centre is at the middle of that line; keep its
  // foot as far in as a capsule of its height is from the corner, with the line's own space around it counted.
  let item = match (at, foot_capsule) {
    (Side, Some(h)) => {
      let bottom = capsule_in(row_corner, h) - (l.meta_h - h) / 2.0
      l.item.then(@ui.style(pb=room(bottom)))
    }
    _ => l.item
  }
  let top = fn() {
    match mark {
      Some(m) => c.box(style=list_row_mark.then(line), m) |> ignore
      None => ()
    }
    c.box(style=l.text, fn() {
      // (in a side column, what stands at its first line's end (`end_slot` wide: a chat's station) in one column with
      // what stands in its foot's end corner (a chat's people and agents, concentric with the row's corner: aside_end),
      // their middles on one line down the list, the first line reaching into the row's room for it where it must)
      let reach = match at {
        Side if end_slot > 0.0 => {
          let last = if corner_end > 0.0 { corner_end } else { l.face_d }
          dmax(0.0, l.band_pad + end_slot / 2.0 - (l.aside_end + last / 2.0))
        }
        _ => 0.0
      }
      let head_style = if reach > 0.0 { l.head.then(@ui.style(mr=room(-reach))) } else { l.head }
      c.box(style=if end_room > 0.0 { head_style.then(@ui.style(pr=room(end_room))) } else { head_style }, head) |> ignore
      match (corner, at) {
        // (the room what stands in the corner keeps at the end of the lines under the first)
        (Some(_), Side) =>
          c.box(style=list_row_under_line, fn() {
            c.box(style=list_row_under, under) |> ignore
            // (as wide as what stands in the corner: list_row `corner_w`)
            c.box(style=@ui.style(w=Fixed(corner_w)), fn() {  }) |> ignore
          })
          |> ignore
        _ => under()
      }
    })
    |> ignore
  }
  let row = c.box(style=(if high { l.row } else { item }).then(list_row_in(at)).then(ground), id~, fn() {
    match foot {
      None => top()
      Some(f) =>
        c.box(style=l.text, fn() {
          c.box(style=@ui.style(row=true, w=Full, gap=S2, align=AStart), top) |> ignore
          // A foot may take more than one line when what it says cannot fit on one; a single line keeps the same
          // height and centring as the row's other metadata lines.
          c.box(style=l.meta.then(@ui.style(h=Hug, min_h=Fixed(l.meta_h))), f) |> ignore
        })
        |> ignore
    }
    match (corner, at) {
      (Some(k), Side) => c.box(right=l.aside_end, bottom=l.aside_end, k) |> ignore
      _ => ()
    }
    after()
  })
  match ground_by {
    Some(f) => c.bg_by(row, f)
    None => ()
  }
  row
}

///|
// kept across runs: a value (no field of it changes)
let list_row_square : @ui.Style = @ui.css("radius=Sharp")

///|
// kept across runs: a value (no field of it changes)
let list_row_under : @ui.Style = @ui.style(w=grow)

///|
// kept across runs: a value (no field of it changes)
let list_row_under_line : @ui.Style = @ui.css("row w=Full")

///|
/// Keys over a row's top end (a chat's 归档, an archived one's 恢复 and 删除), drawn by `body` (each row_key_box): in a
/// layer over the row, 2 apart, each a circle as far in from the row's top and end as makes it concentric with the
/// row's corner (capsule_in: the ladder's row corner less its half, 6), not standing off it in the row's first line
/// (the user, 2026-10-25). The row keeps its first line's end clear for them (list_row's end_room: row_keys_room).
pub fn row_corner_keys(c : @ui.Ctx, body : () -> Unit) -> Unit {
  c.layer(fn() { c.box(style=row_keys_at, fn() { c.box(style=row_keys_line, body) |> ignore }) |> ignore }) |> ignore
}

///|
/// A row's key (row_corner_keys): round, 24 across, the pointer's ground on it.
// kept across runs: a value (no field of it changes)
pub let row_key_box : @ui.Style = @ui.css("w=S6 h=S6 radius=Full align=ACenter justify=JCenter hovered{bg=Hover}")

///|
/// The room `n` keys take at a row's first line's end (row_corner_keys): theirs and what is between them.
pub fn row_keys_room(n : Int) -> Double {
  n.to_double() * row_key_side + (n - 1).to_double() * row_keys_gap
}

///|
/// Where the keys stand (row_corner_keys).
// kept across runs: a value (no field of it changes)
let row_keys_at : @ui.Style = @ui.style(
  w=Full,
  align=AEnd,
  pt=room(capsule_in(row_corner, row_key_side)),
  pr=room(capsule_in(row_corner, row_key_side)),
)

///|
// kept across runs: a value (no field of it changes)
let row_keys_line : @ui.Style = @ui.css("row gap=S0_5 align=ACenter")

///|
/// A row's key's side (row_key_box: S6), and the room between keys (row_keys_line: S0_5).
let row_key_side : Double = 24.0

///|
let row_keys_gap : Double = 2.0

///|
/// A line under a row's first line (SidebarList.css.ts line): as high as a chat's second line, its parts beside each
/// other.
pub fn list_row_line(c : @ui.Ctx, body : () -> Unit) -> Unit {
  lines_drawn.val += 1
  c.box(style=theme().chat_list.meta, body) |> ignore
}

///|
/// How many lines under its first the row being drawn has drawn so far (list_row `lines`).
// kept across runs: said again by every row as it draws its lines (list_row)
let lines_drawn : Ref[Int] = Ref(0)

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
  c.box(style=l.heading.then(list_heading_in(at)), fn() { c.text(label, style=l.heading_words.then(in_lines)) |> ignore }) |> ignore
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
