// A row of a chat's list as a node of the window's tree (chat_list.mbt row_box's, the row's half of it): the node it
// is, found by its key (sfbase's Entry::id: `m:<ts>`, `o:<id>`, `act:<agent>`, `state`, `older`, `newer`, `empty`,
// `line`), and its room: in from the pane's sides to the column, the room over it. What is laid over a row (the band of
// a message gone to, of one whose menu is open) is hung on it by what draws those, through `over`, by its key and the
// moment it began: a row is told nothing of it, and writes nothing for anything else (what else needs to know of a row
// reads it by its key in the chat's view).

///|
/// A row of a chat's list as made: its key (Entry::id) and its outermost node, what is anchored on it (a menu, the bar
/// over picked words, where words sent land) anchored there; whether its own ⋯'s menu is open (as that changes; never,
/// for a row with none: what is laid over it lit meanwhile, by what draws that).
// the chat's page as nodes: held by its tests, not used by the app yet
#warnings("-unused_field")
priv struct MessageRowNode {
  key : String
  node : @view.View
  menu_on : () -> Bool
}

///|
/// Which kind of room over a row `room` is (chat_body_gap_room's): 0 none, 1 a joined one's, 2 the gap between
/// messages, whichever of its two widths.
fn row_top_kind(room : Double) -> Int {
  if room <= 0.0 {
    0
  } else if room <= joined_gap {
    1
  } else {
    2
  }
}

///|
/// A row's room in `parent` (row_box's, but its bands): `top` over it (as that changes: none, joined_gap, list_gap),
/// in from the pane's sides by `side` each (as the list's width gives it: row_side's; the trailing side the system's
/// inset beside its bars, native_row_inset's), its body made by `body` in the column's middle, as wide as is left.
/// `over`, told the row's outermost node and `key` once as it is made, before what it holds: what is laid over it (the
/// bands) hung there, under its words.
fn message_row_frame_node(
  parent : @view.View,
  key : String,
  side : () -> Double,
  top : () -> Double,
  body : (@view.View) -> Unit,
  over? : (@view.View, String) -> Unit = fn(_, _) {  },
) -> MessageRowNode {
  let node = parent.box(fn(root) {
    @sf.style_node(root, fn() { row_column })
    over(root, key)
    // (the room over it, as the row before it says: one kind of room in the other's place as that changes (none, a
    // joined one's, the gap between messages), the row's own structure, its way the column's; the list's way of it with
    // its neighbours' once it holds a block's. How tall that kind is follows the list's width at once: the narrow
    // list's gap for the wide's is what the window or the system's bars did, no motion of the row's (sf/motion.mbt).
    // Picked by the room itself, a list narrowed under chat_narrow_w by the bars the system took made its way from
    // the wide gap to the narrow, laid out none till its end, then stepped there: chat_pops_wbtest's 中屏 beside them)
    root.pick(fn() { row_top_kind(top()) }, fn(gap, _) { gap.height(By(fn() { Some(top()) })) |> ignore })
    root.box(fn(line) {
      @sf.style_node(line, fn() { row_line })
      line.box(fn(s) { s.width(By(fn() { Some(side()) })) |> ignore }) |> ignore
      line.box(fn(m) {
        @sf.style_node(m, fn() { row_middle }, in_row=true)
        body(m)
      })
      |> ignore
      line.box(fn(s) {
        s.width(By(fn() { Some(if @sf.native_side() { native_row_inset() } else { side() }) })) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  { key, node, menu_on: fn() { false } }
}
