// Where a chat's page made as nodes opens its list (the old list's list_after, put in place once), out of what is known
// as the list is made: its rows, the chat's view, where it was left this run (sfbase's kept_places, chat_read_node's),
// the screen's scale. Asked once, as the list is made (chat_body_node), never as it is laid out.

///|
/// Where a chat's list of rows `rows` (chat view `v`'s) opens, as the row's key and its offset ListPlace::bring takes;
/// None at its end. At its unread line, `lead` under the list's room over its rows (`top`: the chat's bar's); else
/// where it was left this run (`kept`: the message at its top as far under the list's top), unless it was left at its
/// end (then at its end, what came since showing); else where the core says it was left (`v.at`: the first message at
/// or after it, its top `v.at_offset` under the list's in the screen's pixels of `scale`, else just under `top`).
fn chat_open_place(
  rows : ChatBodyRows,
  v : ChatView,
  kept : @sfbase.KeptPlace?,
  scale : Double,
  top : Double,
  lead : Double,
) -> (String, Double)? {
  if rows.rows.contains("line") {
    return Some(("line", -(top + lead)))
  }
  if kept is Some(p) && p.bottom >= 0.0 {
    return None
  }
  // (the first message's row that is one `want` takes, by its key)
  let said = fn(want : (Message) -> Bool) {
    rows.keys.iter().find_first(fn(k) { rows.rows.get(k) is Some(row) && row.entry is Said(m) && want(m) })
  }
  if kept is Some(p) && said(fn(m) { m.seq == p.top }) is Some(k) {
    return Some((k, -p.offset))
  }
  guard v.at is Some(at) && said(fn(m) { m.seq >= at }) is Some(k) else { return None }
  Some(
    (
      k,
      match v.at_offset {
        Some(px) => -(px / scale)
        None => -top
      },
    ),
  )
}
