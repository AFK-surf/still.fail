// What is sent takes a page's list up only (list_sent_up_test), on a host's grid: the list puts its rows on the host's
// pixels (2, 2.75 and 3 a point), so where the rule says the row over the key coming does not move, its top stays on
// the same device pixel at every frame of the way, not a pixel lower for a while (the films of #5960: on 大屏, scale 2,
// the bubble over 再看看 a pixel lower for 230 ms as it made its way; on 小屏, scale 3, for a frame); and where the key
// needs more than all that is given back, it goes up only, never a pixel down. Heights off the grid on purpose. Looked
// at every 10 ms, in one jump and at 60, 120, 24 and 7 a second (rc_walk, list_rows_come_test's).

///|
/// The heights: the agent's line (said to leave its room), the part under the sent words that closes as the next comes
/// (its time line), and the next key, shorter than all that gives back, or taller.
let sp_line : Double = 44.37

///|
let sp_part : Double = 21.71

///|
let sp_short : Double = 41.93

///|
let sp_tall : Double = 90.31

///|
priv struct SpCase {
  tree : @view.Tree
  keys : @signals.Signal[Array[Int]]
  part : @signals.Signal[Bool]
}

///|
/// A page's list 300 by 400 on grid `g`, rows 0 to 9 (40.3 each), following its foot; the sent words (70) 40.6 over
/// their part, the line (50) said to go leaving its room, the next key (72) `next_h` tall. Drawn once, at 0.
fn sp_case(g : Double, next_h : Double) -> SpCase {
  let keys = @signals.signal(Array::makei(10, fn(i) { i }), same=fn(a, b) { a == b })
  let part = @signals.signal(true, same=fn(a, b) { a == b })
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(400.0))) |> ignore
      o.scrolls_window(@view.Scroll::list(), fn() { keys.get() }, est=40.0, follows=fn() { true }, leaves_room=fn(k) {
        k == 50
      }, fn(b, k) {
        if k == 70 {
          b.box(fn(w) { w.height(Is(Some(40.6))).shrink(Is(0.0)).words(Is("行70")) |> ignore }) |> ignore
          b.show(fn() { part.get() }, fn(p) { p.height(Is(Some(sp_part))).shrink(Is(0.0)) |> ignore })
        } else {
          let h = if k == 50 {
            sp_line
          } else if k == 72 {
            next_h
          } else {
            40.3
          }
          b.height(Is(Some(h))).words(Is("行\{k}")) |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  })
  tree.set_rows_grid(g)
  tree.frame(390.0, 844.0) |> ignore
  { tree, keys, part }
}

///|
fn sp_keys(more : Array[Int]) -> Array[Int] {
  let all = Array::makei(10, fn(i) { i })
  all.append(more)
  all
}

///|
/// The sent words come, the line under them, the line gone leaving its room; then in one change the part closes and
/// the next key comes: at each look from the look before that change, the device pixel the sent words' top is on.
fn sp_walk(c : SpCase, g : Double, rate : Double) -> Array[Double] {
  let change = su_change_at
  let events : Array[(Double, () -> Unit)] = [
    (su_sent_at, fn() { c.keys.set(sp_keys([70])) }),
    (su_line_at, fn() { c.keys.set(sp_keys([70, 50])) }),
    (su_gone_at, fn() { c.keys.set(sp_keys([70])) }),
    (change, fn() {
      c.part.set(false)
      c.keys.set(sp_keys([70, 72]))
    }),
  ]
  let looks = []
  let mut at = su_sent_at
  while at <= change + su_after_ms {
    looks.push(at)
    at = at + rc_look_ms
  }
  let all = rc_walk(c.tree, events, looks, rate, fn() {
    let y = rc_y(c.tree, "行70")
    if y == rc_none {
      rc_none
    } else {
      (y * g + 0.5).floor()
    }
  })
  all[su_look(change) - 1:].to_owned()
}

///|
test "on a host's grid of 2, 2.75 and 3: the room of the line and a part of the sent words closing, given back as a shorter key comes: the sent words' top on the same device pixel at every frame of the way" {
  for g in [2.0, 2.75, 3.0] {
    for rate in rc_rates {
      let c = sp_case(g, sp_short)
      let px = sp_walk(c, g, rate)
      for i, p in px {
        assert_true(p == px[0], msg="grid \{g}, at \{rate} a second, look \{i} from the one before the change: pixel \{p}, \{px[0]} before")
      }
    }
  }
}

///|
test "on a host's grid of 2, 2.75 and 3: the same with a key taller than all that is given back: the sent words up only, never a device pixel down" {
  for g in [2.0, 2.75, 3.0] {
    for rate in rc_rates {
      let c = sp_case(g, sp_tall)
      let px = sp_walk(c, g, rate)
      for i in 1..<px.length() {
        assert_true(px[i] <= px[i - 1], msg="grid \{g}, at \{rate} a second, look \{i}: pixel \{px[i - 1]} to \{px[i]}")
      }
      assert_true(px[px.length() - 1] < px[0], msg="grid \{g}, at \{rate} a second: never went up (\{px[0]} to \{px[px.length() - 1]})")
    }
  }
}
