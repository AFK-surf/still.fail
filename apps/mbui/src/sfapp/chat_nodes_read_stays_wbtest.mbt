// What the reader has before their eyes does not move (the owner's, said in the old page: sfbase chat_list.mbt's
// reading and its end, sfapp chat.mbt's head), on a chat's page made as nodes (sfbase's chat_page_nodes). Read up (off
// the list's end), that is the message read: the first message whose words start in sight under the page's bar (and
// end over the composer), held by where its words start, not by its block's top, which carries the gap over it. At the
// list's end, the end: the last row over the composer. Whatever else happens (the page before comes, a reply comes, a
// row over or under it grows or goes, the window's width, the side panel), it stays where it is on the screen in every
// frame from the cause to rest, not only at rest. The list's own causes are here and in chat_nodes_read_stays_before_wbtest,
// _before_wide_wbtest, _before_wide_120_wbtest, _before_wide_400_wbtest (the page before) and _rows_wbtest (a row's
// height), each within a CI job's five minutes; the composer's and the keyboard's
// are chat_nodes_read_stays_composer_wbtest's; the helpers both use are chat_nodes_read_stays_help_wbtest's. A test a cause, each on 小屏 (390 by 844, a
// finger) and 大屏 (1280 by 800, a mouse), over the long chat (chat_window_wbtest's LongChat) whose every call to the
// core is answered as late as the run says (0, 120 or 400 ms where the cause goes through the core), between frames.
// Every frame drawn is looked at, at any rate of frames (each frame's look: Tester::each_frame), and a row is held
// within half a device pixel (the Tester's 2 a point), its rows laid on the device's pixels as every host lays them
// (Tester::set_rows_on_pixels: what is held is where things are drawn).
// Not made here: a picture decoded late and a visualisation telling its height (the long chat's messages carry no
// files and no visualisation; a fixture's chat that does keeps its pictures' bytes from the host: chat_page_nodes'),
// so a row's height changes by its words told longer and by its card answered.


// ---------------------------------------------------------------------------------------------------------------------
// 2. A reply at the chat's end, an agent's working line (at the end: what comes there is another principle's)

///|
fn rs_reply(s : (String, Double, Double, Int)) -> Array[String] {
  let broken : Array[String] = []
  let (t, _, k) = rs_open(s)
  rs_read_up(t, s)
  rs_push(
    broken,
    rs_read_held(t, k, s, "\{s.0}: a reply came", fn() { rs_told(k, fn() { k.l.last.set(k.l.last.get() + 1) }) }),
  )
  rs_push(broken, rs_read_held(t, k, s, "\{s.0}: its agent at work", fn() { rs_told(k, fn() { k.working = true }) }))
  rs_push(broken, rs_read_held(t, k, s, "\{s.0}: its agent done", fn() { rs_told(k, fn() { k.working = false }) }))
  broken
}

///|
test "read up on a chat's page made as nodes, 小屏: a reply comes at the chat's end, an agent's working line comes and goes; the message read stays where it is in every frame" {
  assert_eq(rs_reply(long_screens[0]), [])
}

///|
test "read up on a chat's page made as nodes, 大屏: a reply comes at the chat's end, an agent's working line comes and goes; the message read stays where it is in every frame" {
  assert_eq(rs_reply(long_screens[1]), [])
}

// ---------------------------------------------------------------------------------------------------------------------
// 4. The window's width, the side panel (大屏)

///|
/// On screen `s`, read up (else at the end): the window 40 narrower, then as wide again (the same layout).
fn rs_width(s : (String, Double, Double, Int), at_end : Bool) -> Array[String] {
  let broken : Array[String] = []
  let (name, w, h, _) = s
  let (t, _, k) = rs_open(s)
  if !at_end {
    rs_read_up(t, s)
  }
  let held = fn(what : String, cause : () -> Unit) {
    if at_end {
      rs_end_held(t, k, what, cause)
    } else {
      rs_read_held(t, k, s, what, cause)
    }
  }
  rs_push(broken, held("\{name}: the window 40 narrower", fn() { t.resize(w - 40.0, h) }))
  rs_push(broken, held("\{name}: the window as wide again", fn() { t.resize(w, h) }))
  broken
}

///|
/// On 大屏 over a core `late` late, read up (else at the end): the chat's side panel opened (its agent's history), then
/// closed.
fn rs_side(late : Double, at_end : Bool) -> Array[String] {
  let broken : Array[String] = []
  let s = long_screens[1]
  let (t, src, k) = rs_open(s)
  if !at_end {
    rs_read_up(t, s)
  }
  k.late = late
  let held = fn(what : String, cause : () -> Unit) {
    if at_end {
      rs_end_held(t, k, what, cause)
    } else {
      rs_read_held(t, k, s, what, cause)
    }
  }
  let wide = rs_ground(t).map(fn(g) { g.2 })
  rs_push(broken, held("大屏 late \{late}: the side panel opened", fn() { @sfdesk.side_toggle(src, long_ref, "s-c1") }))
  if rs_ground(t).map(fn(g) { g.2 }) == wide {
    broken.push("大屏 late \{late}: the chat no narrower with the side panel opened (the cause not made)")
  }
  rs_push(broken, held("大屏 late \{late}: the side panel closed", fn() { @sfdesk.side_toggle(src, long_ref, "s-c1") }))
  broken
}

///|
test "read up on a chat's page made as nodes, 小屏: the window 40 narrower and as wide again; the message read stays where it is in every frame" {
  assert_eq(rs_width(long_screens[0], false), [])
}

///|
test "at the end of a chat's page made as nodes, 小屏: the window 40 narrower and as wide again; the last row stays over the composer in every frame" {
  assert_eq(rs_width(long_screens[0], true), [])
}

///|
test "read up on a chat's page made as nodes, 大屏: the window 40 narrower and as wide again; the message read stays where it is in every frame" {
  assert_eq(rs_width(long_screens[1], false), [])
}

///|
test "at the end of a chat's page made as nodes, 大屏: the window 40 narrower and as wide again; the last row stays over the composer in every frame" {
  assert_eq(rs_width(long_screens[1], true), [])
}

///|
test "read up on a chat's page made as nodes, 大屏, the core 0 ms late: the side panel opened and closed; the message read stays where it is in every frame" {
  assert_eq(rs_side(0.0, false), [])
}



///|
test "at the end of a chat's page made as nodes, 大屏, the core 0 ms late: the side panel opened and closed; the last row stays over the composer in every frame" {
  assert_eq(rs_side(0.0, true), [])
}
