// What was said before the reader saw it is simply there, on the chat's page made as nodes (sfbase's chat_page_nodes
// on: sfpages/chat_body_node.mbt): chat_old_at_once_help_wbtest's cases 1, 2, 5, 6 and 7, each on 大屏 and 小屏
// (reading up and down, cases 3 and 4, held before and after, are kept apart for their time).

///|
test "old messages at once, case 1, new page: a chat opened, the core answering 0 and 400 ms late: from the frame its messages arrive, drawn as at rest" {
  oa_case1(true)
}

///|
test "old messages at once, case 2, new page: a chat the device holds opened, the core telling more as the real core does (caught up, the app away): drawn as at rest from the frame it is told" {
  oa_case2(true)
}

///|
test "old messages at once, case 5, new page: another chat switched to and back (大屏 by the sidebar, 小屏 back and open), the core 0 and 400 ms late: each drawn as at rest from the frame it arrives" {
  oa_case5(true)
}

///|
test "old messages at once, case 6, new page: another page over the chat while messages come, then the chat shown again: what came is there" {
  oa_case6(true)
}

///|
test "old messages at once, case 7, new page: a long chat with an agent at work opened, the core 0 and 400 ms late: its rows and its working line there as it opens" {
  oa_case7(true)
}
