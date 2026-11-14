// chat_nodes_read_stays_wbtest's (what the reader has before their eyes does not move: its head says the rule and how
// it is held): a row over or under what is read changing height, and at the end.
// A file of its own: the rule's eighteen blocks in one process did not end in a CI job's five minutes at 120 a second.

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
      rs_rest(t, long_rest_ms * 2.0)
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
  rs_rest(t, long_rest_ms * 2.0)
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

