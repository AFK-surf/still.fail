// A chat's talk on the desktop (ember web/src/Chat.tsx ChatShown): its list (sfpages chat_list.mbt) over the pane, the
// bar over it, the composer at its foot, what is picked and dropped over them.

///|
/// How tall the chat's bar over the list is (pageBar: 45; in a panel of its own as much taller as puts its buttons in
/// the panel's corner concentric with it: chat_bar_box_tape), and the list's room under it over its first row (24).
fn chat_bar_room() -> Double {
  @sf.wide_bar_h + (if @sf.in_pane() { @sf.tape_bar_over() } else { 0.0 })
}

///|
let list_head_gap : Double = 24.0

///|
/// The last message's room over the composer (the old chat_list's default foot).
let list_foot_gap : Double = 24.0
