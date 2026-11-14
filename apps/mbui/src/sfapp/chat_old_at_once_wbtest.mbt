// What was said before the reader saw it is simply there, on the page the app ships (sfbase's chat_page_nodes off:
// sfbase/chat_list.mbt): chat_old_at_once_help_wbtest's cases 1, 2, 5, 6 and 7, each on 大屏 and 小屏
// (reading up and down, cases 3 and 4, held before and after, are kept apart for their time).

///|
test "old messages at once, case 1, old page: a chat opened, the core answering 0 and 400 ms late: from the frame its messages arrive, drawn as at rest" {
  oa_case1(false)
}

///|
test "old messages at once, case 2, old page: a chat the device holds opened, the core telling more as the real core does (caught up, the app away): drawn as at rest from the frame it is told" {
  oa_case2(false)
}

///|
test "old messages at once, case 5, old page: another chat switched to and back (大屏 by the sidebar, 小屏 back and open), the core 0 and 400 ms late: each drawn as at rest from the frame it arrives" {
  oa_case5(false)
}

///|
test "old messages at once, case 6, old page: another page over the chat while messages come, then the chat shown again: what came is there" {
  oa_case6(false)
}

///|
test "old messages at once, case 7, old page: a long chat with an agent at work opened, the core 0 and 400 ms late: its rows and its working line there as it opens" {
  oa_case7(false)
}
