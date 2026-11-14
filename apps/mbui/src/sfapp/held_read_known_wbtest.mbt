// What holds something read with nothing following it, as a Tester made in each file finds it (mbui's held_read.mbt):
// how many such places (read from, computed read), counted 2026-11-14 on the files the chat's page as nodes is tested
// by, at 120 judged; each only falls. Nothing stops on it yet. Every file here finds sfbase's declarations
// (`declare_topic`, `declare_page_topic`: source.mbt) reading a topic's holder with nothing following it, on purpose:
// held ahead of the reader that takes it over.

///|
fn init {
  @ui.held_read_known([
    ("src/sfapp/chat_line_room_wbtest.mbt", 3),
    ("src/sfapp/chat_nodes_read_stays_help_wbtest.mbt", 2),
    ("src/sfapp/chat_nodes_told_wbtest.mbt", 2),
    // (and what reads a chat's view, sfbase's view_of_chat, from where nothing says: a handler or a frame's own work)
    ("src/sfapp/chat_page_nodes_wbtest.mbt", 3),
    ("src/sfapp/chat_reply_place_wbtest.mbt", 2),
    ("src/sfapp/chat_sent_seen_wbtest.mbt", 2),
    ("src/sfapp/core_signal_wbtest.mbt", 2),
    ("src/sfapp/declared_read_wbtest.mbt", 2),
    ("src/sfapp/late_core_wbtest.mbt", 1),
  ])
}
