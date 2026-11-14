// chat_nodes_read_stays_wbtest's (what the reader has before their eyes does not move: its head says the rule and how
// it is held): the page before on 大屏, one walk to the top (小屏's, each lateness a walk of its own, is
// chat_nodes_read_stays_before_wbtest's, where the fault was).
// Eight of its arrivals are held and looked at, the core's lateness going round them: the fault was never in how many
// pages came, and three walks of all of them, every display frame drawn, were a third of what the default rate's four
// CI groups had to give (the coordinator of the migration, 2026-11-14).

///|
/// How late the core is at each arrival looked at, in turn (ms).
let rs_spread_lates : Array[Double] = [0.0, 120.0, 400.0]

///|
/// Read up on screen `s` to the top (第1条 held, the row saying more is coming gone), each page before let come as it
/// is asked, answered at once, but eight of them held till the list is at rest after the stroke that asked it and then
/// let come over a late core and looked at: the first three, the last, and four spread evenly between (all of them
/// where there are no more than eight), the lateness going round them (rs_spread_lates).
fn rs_pages_before_spread(s : (String, Double, Double, Int)) -> Array[String] {
  let broken : Array[String] = []
  let (t, _, k) = rs_open(s)
  rs_read_up(t, s)
  // (how many messages a page before brings, and how many arrivals there are to be in all: known from the first)
  let mut page = 0
  let mut total = 0
  // (which arrivals between the third and the last are looked at, and how many of those are behind)
  let between : Array[Int] = []
  let mut passed = 0
  let mut came = 0
  let mut looked = 0
  let mut strokes = 0
  while k.l.first.get() > 1 && strokes < 60 {
    let first = k.l.first.get()
    let look = came < 3 ||
      total <= 8 ||
      first - page <= 1 ||
      (passed < between.length() && came + 1 >= between[passed])
    // (a stroke further up; what it asks held till the list is at rest where it is looked at, else answered at once)
    k.late = 0.0
    k.gate.val = look
    let asked = k.older
    rs_up(t, s, s.2 * 0.4)
    strokes += 1
    rs_rest(t, long_rest_ms * 2.0)
    if look {
      // (the stroke asked for no page before: whatever else it asked is let come, and the next stroke goes on)
      if k.older == asked {
        k.gate.val = false
        continue
      }
      let late = rs_spread_lates[looked % rs_spread_lates.length()]
      k.late = late
      let what = "\{s.0} late \{late}: the page before #\{came + 1} (from 第\{first}条)"
      let said = rs_read_held(t, k, s, what, fn() { rs_open_gate(k) })
      k.late = 0.0
      looked += 1
      let now = k.l.first.get()
      rs_push(broken, said.map(fn(m) { if now == 1 { m + " [the last: 第1条 now held]" } else { m + " [to 第\{now}条]" } }))
    }
    let now = k.l.first.get()
    if now == first {
      continue
    }
    if page == 0 {
      // (the first: a page is as many as it brought, and so many arrivals are still to come)
      page = first - now
      total = 1 + (now - 1 + page - 1) / page
      for j in 1..<5 {
        between.push(3 + (j * (total - 4) + 2) / 5)
      }
      came = 1
    } else {
      // (one stroke's asks answered at once may be more than one page)
      came += (first - now + page - 1) / page
    }
    while passed < between.length() && between[passed] <= came {
      passed += 1
    }
  }
  if k.l.first.get() > 1 {
    broken.push("\{s.0}: the top not reached in \{strokes} strokes (第\{k.l.first.get()}条 held)")
  }
  let wanted = if total < 8 { total } else { 8 }
  if looked < wanted {
    let spread = between.map(fn(n) { "#\{n}" }).join(", ")
    broken.push("\{s.0}: \{looked} of \{total} arrivals looked at, \{wanted} meant (#1, #2, #3, \{spread}, the last)")
  }
  broken
}

///|
test "read up on a chat's page made as nodes, 大屏: the page before comes as the list nears its top, again and again till the last, eight of them over a core 0, 120 and 400 ms late in turn; the message read stays where it is in every frame" {
  assert_eq(rs_pages_before_spread(long_screens[1]), [])
}
