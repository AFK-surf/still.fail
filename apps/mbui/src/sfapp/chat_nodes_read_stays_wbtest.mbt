// What the reader has before their eyes does not move (the owner's, said in the old page: sfbase chat_list.mbt's
// reading and its end, sfapp chat.mbt's head), on a chat's page made as nodes (sfbase's chat_page_nodes). Read up (off
// the list's end), that is the message read: the first message whose words start in sight under the page's bar (and
// end over the composer), held by where its words start, not by its block's top, which carries the gap over it. At the
// list's end, the end: the last row over the composer. Whatever else happens (the page before comes, a reply comes, a
// row over or under it grows or goes, the window's width, the side panel), it stays where it is on the screen in every
// frame from the cause to rest, not only at rest. The list's own causes are here; the composer's and the keyboard's
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
    k.gate = true
    rs_up(t, s, s.2 * 0.4)
    strokes += 1
    rs_run(t, long_rest_ms * 2.0)
    if k.held.is_empty() {
      k.gate = false
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

///|
test "read up on a chat's page made as nodes, 大屏: the page before comes as the list nears its top, again and again till the last, over a core 0 ms late; the message read stays where it is in every frame" {
  assert_eq(rs_pages_before(long_screens[1], 0.0), [])
}

///|
test "read up on a chat's page made as nodes, 大屏: the page before comes as the list nears its top, again and again till the last, over a core 120 ms late; the message read stays where it is in every frame" {
  assert_eq(rs_pages_before(long_screens[1], 120.0), [])
}

///|
test "read up on a chat's page made as nodes, 大屏: the page before comes as the list nears its top, again and again till the last, over a core 400 ms late; the message read stays where it is in every frame" {
  assert_eq(rs_pages_before(long_screens[1], 400.0), [])
}

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
// 3. A row over or under what is read changing height

///|
fn rs_rows_grow(s : (String, Double, Double, Int)) -> Array[String] {
  let broken : Array[String] = []
  let (t, _, k) = rs_open(s)
  rs_read_up(t, s)
  match rs_read(t, k, s) {
    Some((n, _)) => {
      rs_push(
        broken,
        rs_read_held(t, k, s, "\{s.0}: the row over it (第\{n - 1}条) told longer", fn() {
          rs_told(k, fn() { k.grown.push(n - 1) })
        }),
      )
      rs_push(
        broken,
        rs_read_held(t, k, s, "\{s.0}: a row under it (第\{n + 2}条) told longer", fn() {
          rs_told(k, fn() { k.grown.push(n + 2) })
        }),
      )
    }
    None => broken.push("\{s.0}: no message read up")
  }
  match rs_read(t, k, s) {
    Some((n, _)) => {
      // (a card each, at rest; then answered)
      rs_told(k, fn() {
        k.carded[n - 1] = false
        k.carded[n + 1] = false
      })
      rs_run(t, long_rest_ms * 2.0)
      match rs_read(t, k, s) {
        Some((m, _)) => {
          let over = n - 1
          let under = n + 1
          if t.rect_of("一起换") is None {
            broken.push("\{s.0}: no card drawn on 第\{over}条 or 第\{under}条 (the cause not made)")
          }
          if over < m {
            rs_push(
              broken,
              rs_read_held(t, k, s, "\{s.0}: the card over it (第\{over}条) answered", fn() {
                rs_told(k, fn() { k.carded[over] = true })
              }),
            )
          }
          if under > m {
            rs_push(
              broken,
              rs_read_held(t, k, s, "\{s.0}: the card under it (第\{under}条) answered", fn() {
                rs_told(k, fn() { k.carded[under] = true })
              }),
            )
          }
        }
        None => broken.push("\{s.0}: no message read up once cards came")
      }
    }
    None => ()
  }
  broken
}

///|
fn rs_rows_grow_end(s : (String, Double, Double, Int)) -> Array[String] {
  let broken : Array[String] = []
  let (t, _, k) = rs_open(s)
  let last = k.l.last.get()
  rs_push(
    broken,
    rs_end_held(t, k, "\{s.0}: the row over the last (第\{last - 2}条) told longer", fn() {
      rs_told(k, fn() { k.grown.push(last - 2) })
    }),
  )
  rs_push(
    broken,
    rs_end_held(t, k, "\{s.0}: the last row (第\{last}条) told longer", fn() { rs_told(k, fn() { k.grown.push(last) }) }),
  )
  rs_told(k, fn() { k.carded[last - 1] = false })
  rs_run(t, long_rest_ms * 2.0)
  if t.rect_of("一起换") is None {
    broken.push("\{s.0}: no card drawn on 第\{last - 1}条 at the end (the cause not made)")
  }
  rs_push(
    broken,
    rs_end_held(t, k, "\{s.0}: the card over the last (第\{last - 1}条) answered", fn() {
      rs_told(k, fn() { k.carded[last - 1] = true })
    }),
  )
  broken
}

///|
test "read up on a chat's page made as nodes, 小屏: a row over what is read and one under it told longer, a card on each answered; the message read stays where it is in every frame" {
  assert_eq(rs_rows_grow(long_screens[0]), [])
}

///|
test "read up on a chat's page made as nodes, 大屏: a row over what is read and one under it told longer, a card on each answered; the message read stays where it is in every frame" {
  assert_eq(rs_rows_grow(long_screens[1]), [])
}

///|
test "at the end of a chat's page made as nodes, 小屏: the row over the last and the last told longer, a card over the last answered; the last row stays over the composer in every frame" {
  assert_eq(rs_rows_grow_end(long_screens[0]), [])
}

///|
test "at the end of a chat's page made as nodes, 大屏: the row over the last and the last told longer, a card over the last answered; the last row stays over the composer in every frame" {
  assert_eq(rs_rows_grow_end(long_screens[1]), [])
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
