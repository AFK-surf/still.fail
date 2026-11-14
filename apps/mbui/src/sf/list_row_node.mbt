// A row of a list (list_row's) as a node of the window's tree: a chat's, a station's, a folder's, a profile's are one
// row, its mark beside its first line, its first line (its title and what stands at that line's end), the lines under
// it; its sizes the theme's chats' list's as they are now, how far in and whether its ground is rounded where its list
// stands (ListAt).

///|
/// Lay out the already created `row` standing `at` (list_row's), on `ground` as it is now (lit, pressed or pointed at: the
/// caller's; slotted, square: list_row_slot), its first line made by `head`, the lines under it by `under`, then
/// `after` over it all; `mark` beside its first line where it has one. `high`: as high as a chat's row always is (the
/// theme's `row`), else as what it holds (`item`); `end_room`: room kept at its first line's end as it says now (for
/// what a caller lays over it there: 归档); `corner`: what stands in its foot's end corner while `corner_shown` says,
/// `corner_w` wide (a chat's people and agents), placed there by the corner rule in a side column (aside_end in from the
/// row's end and foot, its room kept at the end of the lines under the first); `end_slot`: how wide what stands at its
/// first line's end is, in one column with the last of what stands in its corner (`corner_end` wide: a face's where it
/// says none). The caller has the row before these bindings run, so they can read its state directly.
#callsite(autofill(loc))
pub fn list_row_node(
  row : @view.View,
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
  loc~ : SourceLoc,
) -> Unit {
  style_node(row, fn() {
    // (a chat's as high as its lines are at the system's size of words: list_looks)
    let look = (if high { list_looks(row).row } else { theme().chat_list.item }).then(list_row_in(at))
    if slotted {
      look.then(list_row_square)
    } else {
      look
    }
  })
  row.ground(By(ground)) |> ignore
  match mark {
    Some(m) =>
      row.box(made_for=loc, fn(k) {
        style_node(k, fn() { list_row_mark }, in_row=true)
        // (as high as its first line: list_looks)
        k.height(By(fn() { Some(list_looks(k).head_h) })) |> ignore
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
      style_node(h, fn() { list_looks(h).head })
      let reach = fn() {
        let l = theme().chat_list
        if at != Whole && end_slot > 0.0 {
          let last = if corner_end() > 0.0 { corner_end() } else { l.face_d }
          band_pad_in(at) + end_slot / 2.0 - (l.aside_end + last / 2.0)
        } else {
          0.0
        }
      }
      // (reaching out past the row's padding where the corner's column is nearer its end, in from it where farther)
      h
      .margin(By(fn() { (0.0, 0.0, -dmax(0.0, reach()), 0.0) }))
      .padding(By(fn() { (0.0, 0.0, end_room() + dmax(0.0, -reach()), 0.0) }))
      |> ignore
      head(h)
    })
    |> ignore
    match (corner, at) {
      // (the room what stands in the corner keeps at the end of the lines under the first)
      (Some(_), Side | Tape) =>
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
    (Some(k), Side | Tape) =>
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
}

///|
/// A row's looks at a size of words (list_looks_at): a chat's row's, its first line's and the lines' under it, and its
/// first line's height.
priv struct ListLooks {
  row : @ui.Style
  head : @ui.Style
  meta : @ui.Style
  head_h : Double
}

///|
/// A row's looks in `v`'s tree (list_looks_at): the theme's at the system's size of words there, followed as either
/// changes (View::words_scale).
fn list_looks(v : @view.View) -> ListLooks {
  list_looks_at(theme().chat_list, v.words_scale())
}

///|
/// A row's looks of list `l` at the system's size of words `scale`, each line as high as its words' line as drawn at that
/// size where that is higher than the theme's (view_line's way: its leading at that size, or its share of its size
/// there), a chat's row higher than the theme's by as much as its two lines are, whatever they say (so rows of a kind
/// are as high): heights fixed, as the theme's are, so a row is laid out without its words measured. Where none is
/// higher (the default size), the theme's own styles. Kept for the last list and size asked (list_looks_kept): the
/// same asked again is the same looks, made once.
fn list_looks_at(l : ChatList, scale : Double) -> ListLooks {
  match list_looks_kept.val {
    Some((k, s, looks)) if physical_equal(k, l) && s == scale => return looks
    _ => ()
  }
  let line = fn(style : @ui.TextStyle) {
    let look = @ui.style_words(style)
    if look.line < 0.0 {
      -look.line * @ui.sp_at(scale, look.size)
    } else {
      @ui.sp_at(scale, look.line)
    }
  }
  let head_h = dmax(l.head_h, line(l.title))
  let meta_h = dmax(l.meta_h, line(l.last))
  let grown = head_h - l.head_h + (meta_h - l.meta_h)
  let looks = if grown > 0.0 {
    {
      row: l.row.then(@ui.style(h=Fixed(l.row_h + grown))),
      head: l.head.then(@ui.style(h=Fixed(head_h))),
      meta: l.meta.then(@ui.style(h=Fixed(meta_h))),
      head_h,
    }
  } else {
    { row: l.row, head: l.head, meta: l.meta, head_h: l.head_h }
  }
  list_looks_kept.val = Some((l, scale, looks))
  looks
}

///|
// kept across runs: the last list and size of words asked and their looks (list_looks_at), worked out again for any other
let list_looks_kept : Ref[(ChatList, Double, ListLooks)?] = Ref(None)

///|
/// A line under a row's first line (list_row_line's) in `parent`: as high as a chat's second line, its parts beside each
/// other, made by `body`.
#callsite(autofill(loc))
pub fn list_row_line_node(parent : @view.View, body : (@view.View) -> Unit, loc~ : SourceLoc) -> Unit {
  parent.box(made_for=loc, fn(l) {
    style_node(l, fn() { list_looks(l).meta })
    body(l)
  })
  |> ignore
}

///|
/// A heading over a part of a list (list_heading's) in `parent`, its words `label` as it says them now, in from the
/// list's left as its rows are where the list stands (`at`).
#callsite(autofill(loc))
pub fn list_heading_node(parent : @view.View, label : () -> String, at : ListAt, loc~ : SourceLoc) -> Unit {
  parent.box(made_for=loc, fn(h) {
    style_node(h, fn() { theme().chat_list.heading.then(list_heading_in(at)) })
    words_node(h, label, fn() { theme().chat_list.heading_words.then(in_lines) }) |> ignore
  })
  |> ignore
}
