// A row of a list (list_row's) as a node of the window's tree: a chat's, a station's, a folder's, a profile's are one
// row, its mark beside its first line, its first line (its title and what stands at that line's end), the lines under
// it; its sizes the theme's chats' list's as they are now, how far in and whether its ground is rounded where its list
// stands (ListAt).

///|
/// A row of a list standing `at` (list_row's) in `parent`, on `ground` as it is now (lit, pressed or pointed at: the
/// caller's; slotted, square: list_row_slot), its first line made by `head`, the lines under it by `under`, then
/// `after` over it all; `mark` beside its first line where it has one. `high`: as high as a chat's row always is (the
/// theme's `row`), else as what it holds (`item`); `end_room`: room kept at its first line's end as it says now (for
/// what a caller lays over it there: 归档); `corner`: what stands in its foot's end corner while `corner_shown` says,
/// `corner_w` wide (a chat's people and agents), placed there by the corner rule in a side column (aside_end in from the
/// row's end and foot, its room kept at the end of the lines under the first); `end_slot`: how wide what stands at its
/// first line's end is, in one column with the last of what stands in its corner (`corner_end` wide: a face's where it
/// says none). The row's node, the one pressed.
pub fn list_row_node(
  parent : @view.View,
  at : ListAt,
  head : (@view.View) -> Unit,
  under : (@view.View) -> Unit,
  ground? : () -> Int64 = fn() { 0L },
  mark? : (@view.View) -> Unit,
  high? : Bool = false,
  end_room? : () -> Double = fn() { 0.0 },
  corner? : (@view.View) -> Unit,
  corner_shown? : () -> Bool = fn() { true },
  corner_w? : () -> Double = fn() { 0.0 },
  after? : (@view.View) -> Unit,
  slotted? : Bool = false,
  end_slot? : Double = 0.0,
  corner_end? : () -> Double = fn() { 0.0 },
) -> @view.View {
  let made : Ref[@view.View?] = Ref(None)
  parent.box(fn(row) {
    made.val = Some(row)
    style_node(row, fn() {
      let l = theme().chat_list
      let look = (if high { l.row } else { l.item }).then(list_row_in(at))
      if slotted {
        look.then(list_row_square)
      } else {
        look
      }
    })
    row.ground(By(ground)) |> ignore
    match mark {
      Some(m) =>
        row.box(fn(k) {
          style_node(k, fn() { list_row_mark }, in_row=true)
          k.height(By(fn() { Some(theme().chat_list.head_h) })) |> ignore
          m(k)
        })
        |> ignore
      None => ()
    }
    row.box(fn(text) {
      style_node(text, fn() { theme().chat_list.text }, in_row=true)
      // (its first line: in a side column, what stands at its end (`end_slot` wide: a chat's station) in one column with
      // what stands in its foot's end corner (a chat's people and agents, concentric with the row's corner: aside_end),
      // the line reaching into the row's room for it where it must)
      text.box(fn(h) {
        style_node(h, fn() { theme().chat_list.head })
        h
        .margin(By(fn() {
          let l = theme().chat_list
          let reach = if at == Side && end_slot > 0.0 {
            let last = if corner_end() > 0.0 { corner_end() } else { l.face_d }
            dmax(0.0, l.band_pad + end_slot / 2.0 - (l.aside_end + last / 2.0))
          } else {
            0.0
          }
          (0.0, 0.0, -reach, 0.0)
        }))
        .padding(By(fn() { (0.0, 0.0, end_room(), 0.0) }))
        |> ignore
        head(h)
      })
      |> ignore
      match (corner, at) {
        // (the room what stands in the corner keeps at the end of the lines under the first)
        (Some(_), Side) =>
          text.box(fn(line) {
            line.row(Is(true)) |> ignore
            line.box(fn(u) {
              u.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
              under(u)
            })
            |> ignore
            line.box(fn(k) { k.width(By(fn() { Some(if corner_shown() { corner_w() } else { 0.0 }) })) |> ignore }) |> ignore
          })
          |> ignore
        _ => under(text)
      }
    })
    |> ignore
    // (in its foot's end corner, aside_end in from both)
    match (corner, at) {
      (Some(k), Side) =>
        row.show(corner_shown, fn(o) {
          o
          .over(Is(true))
          .lines_up(Is(Some(End)))
          .lies_along(Is(End))
          |> ignore
          // (in from its end and foot as an old view's is placed there, right= and bottom=: where it stands, no room of
          // the row's)
          o.box(fn(b) {
            b
            .margin(By(fn() {
              let e = theme().chat_list.aside_end
              (0.0, 0.0, e, e)
            }))
            |> ignore
            k(b)
          })
          |> ignore
        })
      _ => ()
    }
    match after {
      Some(f) => f(row)
      None => ()
    }
  })
  |> ignore
  made.val.unwrap()
}

///|
/// A line under a row's first line (list_row_line's) in `parent`: as high as a chat's second line, its parts beside each
/// other, made by `body`.
pub fn list_row_line_node(parent : @view.View, body : (@view.View) -> Unit) -> Unit {
  parent.box(fn(l) {
    style_node(l, fn() { theme().chat_list.meta })
    body(l)
  })
  |> ignore
}

///|
/// A heading over a part of a list (list_heading's) in `parent`, its words `label` as it says them now, in from the
/// list's left as its rows are where the list stands (`at`).
pub fn list_heading_node(parent : @view.View, label : () -> String, at : ListAt) -> Unit {
  parent.box(fn(h) {
    style_node(h, fn() { theme().chat_list.heading.then(list_heading_in(at)) })
    words_node(h, label, fn() { theme().chat_list.heading_words.then(in_lines) }) |> ignore
  })
  |> ignore
}
