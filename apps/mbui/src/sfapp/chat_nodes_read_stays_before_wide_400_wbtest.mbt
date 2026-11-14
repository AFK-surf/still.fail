// chat_nodes_read_stays_wbtest's (what the reader has before their eyes does not move: its head says the rule and how
// it is held): the page before on 大屏, the core 400 ms late (rs_pages_before is chat_nodes_read_stays_before_wbtest's).
// A file of its own: 大屏's 32 arrivals over one lateness are a third of a CI job's five minutes at 120 frames a second,
// and the whole of the rule's eighteen blocks in one process did not end in them.

///|
test "read up on a chat's page made as nodes, 大屏: the page before comes as the list nears its top, again and again till the last, over a core 400 ms late; the message read stays where it is in every frame" {
  assert_eq(rs_pages_before(long_screens[1], 400.0), [])
}
