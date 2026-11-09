// A few of the library's parts (parts.mbt, page.mbt, waiting.mbt, group_rows.mbt) as nodes of the window's tree, made
// once, their styles the same: what a list still waits on, a group's rows coming and going by their keys, what stands
// apart, steps, what was checked and found right.
///|
/// A list with rows already, still waiting on some of it (wait_more's, as nodes) in `parent`, as `note` says it now:
/// under its rows one more of them in its bones (`sample`) while something is still read, and each failure in red.
/// Nothing while it waits on nothing.
pub fn wait_more_node(parent : @view.View, note : () -> WaitNote, sample : (@view.View) -> Unit) -> Unit {
  parent.show(fn() { note().reading }, fn(b) { waiting_node(b, sample) })
  parent.each(fn() { note().failing }, fn(f) { f }, fn(w, f) {
    wait_line_failed_node(w, fn() { f.get() })
  })
}

///|
/// What could not be read, in red in a line of its own (wait_line's `error`: at once, no spinner).
#callsite(autofill(loc))
fn wait_line_failed_node(parent : @view.View, words : () -> String, loc~ : SourceLoc) -> Unit {
  words_node(loc~, parent, words, fn() { wait_words }).ink(By(fn() { theme().p.red })) |> ignore
}

///|
/// A group's rows by their keys (group_rows', as nodes, each followed by its key as it comes and goes) in `parent`: `items` as they are now, each made by `row` with
/// its item; one come after the group was first made opens its room where it is, one gone closes it where it was, on a
/// row's way (@ui.row_size_ms, from the moment it came or went), what is in it as big as its room is open and faded in
/// from half open (seen_at). As they are the first time.
pub fn[T : Eq, K : Hash + Eq] keyed_rows_node(
  parent : @view.View,
  items : () -> Array[T],
  key : (T) -> K,
  row : (@view.View, @signals.Signal[T]) -> Unit,
) -> Unit {
  // (the moment the group is made: a row made in it is there with the group, open; one made at a later moment came
  // after it, opening from then)
  let made_at = parent.cause_at()
  parent.each(items, key, leave=@ui.row_size_ms, fn(r, item) {
    let came = r.cause_at() > made_at
    let open = EdgeWay::new(if came { 0.0 } else { 1.0 })
    if came {
      open.go(r, 1.0, @ui.row_size_ms)
    }
    let share = fn() { dmin(open.shown(r), 1.0 - r.going()) }
    r.opens(By(fn() { Some(share()) })) |> ignore
    r.box(fn(i) {
      i.scale(By(share)).alpha(By(fn() { seen_at(share()) })) |> ignore
      row(i, item)
    })
    |> ignore
  })
}

///|
/// What stands apart from what follows (apart's, as a node) in `parent`, made by `body`: wide, 28 under it; narrow,
/// what it holds 12 apart. The node.
#callsite(autofill(loc))
pub fn apart_node(parent : @view.View, body : (@view.View) -> Unit, loc~ : SourceLoc) -> @view.View {
  let narrow = look_node(parent) is Narrow
  parent.box(made_for=loc, fn(a) {
    style_node(a, fn() { if narrow { wide_block } else { wide_apart } })
    body(a)
  })
}

///|
/// Steps one after another (steps', as nodes) in `parent`: each its number and a dot in a 20 column, what `steps` makes
/// of it beside it in a line that goes on in lines, 8 apart.
#callsite(autofill(loc))
pub fn steps_node(parent : @view.View, steps : Array[(@view.View) -> Unit], loc~ : SourceLoc) -> Unit {
  parent.box(made_for=loc, fn(b) {
    style_node(b, fn() { steps_box })
    for i, step in steps {
      b.box(fn(r) {
        style_node(r, fn() { step_row })
        r.box(fn(n) {
          style_node(n, fn() { step_number }, in_row=true)
          words_node(n, fn() { (i + 1).to_string() + "." }, fn() { step_number_words }) |> ignore
        })
        |> ignore
        r.box(fn(s) {
          style_node(s, fn() { step_body }, in_row=true)
          s.wraps(Is(Some(0.0))) |> ignore
          step(s)
        })
        |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// What was checked and found right (verify_ok's, as a node) in `parent`: a tick in a circle in green, `words` beside
/// it in green.
#callsite(autofill(loc))
pub fn verify_ok_node(parent : @view.View, words : () -> String, loc~ : SourceLoc) -> Unit {
  parent.box(made_for=loc, fn(b) {
    style_node(b, fn() { verify_line })
    icon_node(b, "check-circle", verify_icon, By(fn() { theme().p.green_ink })) |> ignore
    words_node(b, words, fn() { verify_words }) |> ignore
  })
  |> ignore
}

///|
/// A row of a group that says what it is with a control at its end (said_row's `value`: a model's picker), as a node in
/// `parent`: its `title`, and at its end, in the room the title leaves, what `value` makes; going nowhere. A row's room
/// and corner, cutting what it holds there (what lies in its corners stands in the row's, as said_row's row following
/// its card's corner does): narrow, a card's row; wide, a list's row.
#callsite(autofill(loc))
pub fn said_row_node(
  parent : @view.View,
  title : () -> String,
  value : (@view.View) -> Unit,
  loc~ : SourceLoc,
) -> Unit {
  let at = part_of(parent)
  let narrow = at.look is Narrow
  parent.box(made_for=loc, fn(r) {
    r
    .row(Is(true))
    .gap(Is(12.0))
    .padding(Is(if narrow { (text_in, text_in, text_in, text_in) } else { (text_in, wide_row_over, text_in, wide_row_over) }))
    .radius(By(fn() {
      if narrow {
        @ui.concentric(group_corner, list_pad)
      } else if at.list {
        list_row_corner(r)
      } else {
        @ui.tree_theme().corner(Xl2)
      }
    }))
    .clips(Is(true))
    .min_height(By(fn() { Some(theme().items.least) }))
    .lines_up(Is(Some(Middle)))
    |> ignore
    words_node(r, title, fn() { if narrow { pg_row_title_in } else { desk_list_title } }).shrink(Is(0.0)) |> ignore
    r.box(fn(e) {
      e.grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0))).row(Is(true)).lies_along(Is(End)).lines_up(Is(Some(Middle))) |> ignore
      value(e)
    })
    |> ignore
  })
  |> ignore
}
