// chat_nodes_read_stays_wbtest's (what the reader has before their eyes does not move: its head says the rule and how
// it is held): the page before, on 小屏, each lateness a walk of all its arrivals (大屏's one walk is
// chat_nodes_read_stays_before_wide_wbtest's).
// A file of its own: the rule's eighteen blocks in one process did not end in a CI job's five minutes at 120 a second.

// ---------------------------------------------------------------------------------------------------------------------
// 1. The page before, as the list nears its top (at the end it is not asked: nothing to hold there)

///|
/// Read up on screen `s` over a core `late` late: each page before held till the list is at rest after the stroke that
/// asked it, then let come; every one till the last (第1条 held, the row saying more is coming gone).
fn rs_pages_before(s : (String, Double, Double, Int), late : Double) -> Array[String] {
  let broken : Array[String] = []
  let (t, _, k) = rs_open(s)
  rs_read_up(t, s)
  k.late = late
  let mut came = 0
  let mut strokes = 0
  while k.l.first.get() > 1 && strokes < 60 {
    // (a stroke further up, what it asks held till the list is at rest)
    k.gate.val = true
    rs_up(t, s, s.2 * 0.4)
    strokes += 1
    rs_rest(t, long_rest_ms * 2.0)
    if k.held.is_empty() {
      k.gate.val = false
      continue
    }
    let first = k.l.first.get()
    let what = "\{s.0} late \{late}: the page before #\{came + 1} (from 第\{first}条)"
    let said = rs_read_held(t, k, s, what, fn() { rs_open_gate(k) })
    came += 1
    let now = k.l.first.get()
    rs_push(broken, said.map(fn(m) { if now == 1 { m + " [the last: 第1条 now held]" } else { m + " [to 第\{now}条]" } }))
  }
  if k.l.first.get() > 1 {
    broken.push("\{s.0} late \{late}: the top not reached in \{strokes} strokes (第\{k.l.first.get()}条 held)")
  }
  broken
}

///|
test "read up on a chat's page made as nodes, 小屏: the page before comes as the list nears its top, again and again till the last, over a core 0 ms late; the message read stays where it is in every frame" {
  assert_eq(rs_pages_before(long_screens[0], 0.0), [])
}

///|
test "read up on a chat's page made as nodes, 小屏: the page before comes as the list nears its top, again and again till the last, over a core 120 ms late; the message read stays where it is in every frame" {
  assert_eq(rs_pages_before(long_screens[0], 120.0), [])
}

///|
test "read up on a chat's page made as nodes, 小屏: the page before comes as the list nears its top, again and again till the last, over a core 400 ms late; the message read stays where it is in every frame" {
  assert_eq(rs_pages_before(long_screens[0], 400.0), [])
}

