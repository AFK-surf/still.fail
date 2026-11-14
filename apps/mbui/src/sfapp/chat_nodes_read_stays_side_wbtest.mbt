// The four 大屏 side-panel blocks of chat_nodes_read_stays_wbtest over a core 120 and 400 ms late, read up and at the
// end (its rs_side, over chat_nodes_read_stays_help_wbtest's helpers): apart, as each stops on the side panel's own
// sizes_steady fault (sfdesk/history.mbt:113's column 28 in one frame) before its own assertion (the coordinator of the
// migration, 2026-11-14).

///|
test "read up on a chat's page made as nodes, 大屏, the core 120 ms late: the side panel opened and closed; the message read stays where it is in every frame" {
  assert_eq(rs_side(120.0, false), [])
}

///|
test "read up on a chat's page made as nodes, 大屏, the core 400 ms late: the side panel opened and closed; the message read stays where it is in every frame" {
  assert_eq(rs_side(400.0, false), [])
}

///|
test "at the end of a chat's page made as nodes, 大屏, the core 120 ms late: the side panel opened and closed; the last row stays over the composer in every frame" {
  assert_eq(rs_side(120.0, true), [])
}

///|
test "at the end of a chat's page made as nodes, 大屏, the core 400 ms late: the side panel opened and closed; the last row stays over the composer in every frame" {
  assert_eq(rs_side(400.0, true), [])
}
