// What a windowed list tells seen (View::scrolls_window's `seen`) as what it holds changes while it goes on by itself:
// rows come, gone, moved among the rest or grown, said in an event on its way. What it tells is what came in sight at
// the logic's moments; what it is held to here is what frames drawn every millisecond at their moments show come in
// sight one after another (a sample of those moments, the one compared with): the same whatever frames came on the way
// (none, many, drawn ahead of their host's moment), each once.

///|
/// A column 300 by 100 holding, while `there` says so, a windowed list of `keys` from its top, each as tall as `tall`
/// says, put `put` down it first: what it told seen pushed to `told`, the keys in sight said in `shown`. Its tree, what
/// draws a frame for a moment (the second) with its host at another (the first), what it said to tell once it is
/// painted told, and its scroll.
fn changing_case(
  keys : @signals.Signal[Array[Int]],
  tall : Map[Int, @signals.Signal[Double]],
  there : @signals.Signal[Bool],
  told : Array[Int],
  shown : @signals.Signal[Array[Int]],
  put : Double,
  from_end? : Bool = false,
  align_end? : Bool = true,
) -> (@view.Tree, (Double, Double) -> Unit, @view.Scroll) {
  let scroll = @view.Scroll::list()
  if put > 0.0 {
    scroll.put(put)
  }
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
      o.show(fn() { there.get() }, fn(p) {
        p.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
        p.scrolls_window(scroll, fn() { keys.get() }, est=40.0, from_end~, align_end~, shown~, seen=fn(came) { told.append(came) }, fn(b, k) {
          let h = tall.get(k).unwrap()
          b.height(By(fn() { Some(h.get()) })) |> ignore
        })
        |> ignore
      })
    })
    |> ignore
  })
  let draw = fn(host : Double, drawn : Double) {
    if drawn > host {
      tree.at(drawn)
    }
    tree.frame(300.0, 100.0, now=host) |> ignore
    for f in tree.take_after_paint() {
      f()
    }
  }
  (tree, draw, scroll)
}

///|
/// changing_case's list flung by a finger, 80 in 10 ms up the column or `down` it, through `tree` (what is in sight
/// looked at after each step by `look`): what takes it found where it goes down as the tree is brought to that moment,
/// no frame drawn; each step taken by the list, let go at 11 gliding on past that moment.
fn flung(tree : @view.Tree, scroll : @view.Scroll, down : Bool, look : () -> Unit) -> Unit raise {
  let (from_y, to_y) = if down { (10.0, 90.0) } else { (90.0, 10.0) }
  tree.bring_to(1.0)
  guard tree.claimer_of(tree.claimers_at(150.0, from_y), 0.0, to_y - from_y) is Some(id) else {
    fail("nothing takes the finger")
  }
  let took : Array[Bool] = []
  took.push(tree.drag_at(id, Down, 150.0, from_y, 1.0))
  look()
  took.push(tree.drag_at(id, Moved, 150.0, (from_y + to_y) / 2.0, 6.0))
  look()
  took.push(tree.drag_at(id, Moved, 150.0, to_y, 11.0))
  look()
  took.push(tree.drag_at(id, Up, 150.0, to_y, 11.0))
  look()
  assert_eq(took, [true, true, true, true])
  assert_true(scroll.glides_till() is Some(till) && till > 11.0, msg="gliding till \{scroll.glides_till()}")
}

///|
/// What changing_case's list (`0..<400`, 40 tall, put `put` down it first) did, flung (flung: up the column or `down`
/// it, let go at 11), `change` done in an event at 120 on its way and its page closed in an event at 300, with `frames`
/// drawn between (given what draws a frame, after one moment and before the other): what it told seen after its first
/// frame, as told; what came in sight as it was laid out (each key new to those in sight, in the order shown); those in
/// sight as the event at 120 began; those in sight as it was last laid out (as the event at 300 began).
fn changed_on_the_way(
  change : (@signals.Signal[Array[Int]], Map[Int, @signals.Signal[Double]]) -> Unit,
  frames : ((Double, Double) -> Unit, Double, Double) -> Unit,
  down? : Bool = false,
  put? : Double = 0.0,
  from_end? : Bool = false,
  align_end? : Bool = true,
) -> (Array[Int], Array[Int], Array[Int], Array[Int]) raise {
  let keys = @signals.signal(Array::makei(400, fn(i) { i }), same=fn(a, b) { physical_equal(a, b) })
  let tall : Map[Int, @signals.Signal[Double]] = {}
  for k in 0..<400 {
    tall[k] = @signals.signal(40.0)
  }
  for k in 1000..<1005 {
    tall[k] = @signals.signal(40.0)
  }
  let there = @signals.signal(true)
  let told : Array[Int] = []
  let shown : @signals.Signal[Array[Int]] = @signals.signal([])
  let (tree, draw, scroll) = changing_case(keys, tall, there, told, shown, put, from_end~, align_end~)
  draw(0.0, 0.0)
  let first = told.length()
  let came : Array[Int] = []
  let was = Ref(shown.get())
  let look = fn() {
    let now = shown.get()
    for k in now {
      if !was.val.contains(k) {
        came.push(k)
      }
    }
    was.val = now
  }
  flung(tree, scroll, down, look)
  let drawn = fn(host : Double, at : Double) {
    draw(host, at)
    look()
  }
  frames(drawn, 11.0, 120.0)
  let at_120 : Ref[Array[Int]] = Ref([])
  tree.event_said(120.0, fn() {  }, fn() {
    at_120.val = shown.get()
    change(keys, tall)
  })
  look()
  frames(drawn, 120.0, 300.0)
  let at_300 : Ref[Array[Int]] = Ref([])
  tree.event_said(300.0, fn() {  }, fn() {
    at_300.val = shown.get()
    there.set(false)
  })
  look()
  let out = told[first:].to_array()
  tree.dispose()
  (out, came, at_120.val, at_300.val)
}

///|
/// Frames every `dt` ms after one moment and before another, each drawn for `ahead` ms later than its host is.
fn frames_every(dt : Double, ahead : Double) -> ((Double, Double) -> Unit, Double, Double) -> Unit {
  fn(draw, from, to) {
    let mut t = (from / dt).floor() * dt + dt
    while t < to {
      draw(t, t + ahead)
      t = t + dt
    }
  }
}

///|
/// The ways frames come on the way: every millisecond at their moments, and one at the moment of what is changed on
/// the way as soon as it is done (what came in sight then, one after another); none, every 16 ms, every 16 ms each drawn
/// 16 later, every 7 ms, one drawn for 200 with its host at 100.
fn frame_histories() -> Array[(String, ((Double, Double) -> Unit, Double, Double) -> Unit)] {
  [
    (
      "every 1 ms",
      fn(draw, from, to) {
        if from > 11.0 {
          draw(from, from)
        }
        frames_every(1.0, 0.0)(draw, from, to)
      },
    ),
    ("none", fn(_, _, _) {  }),
    ("every 16 ms", frames_every(16.0, 0.0)),
    ("every 16 ms, each drawn 16 later", frames_every(16.0, 16.0)),
    ("every 7 ms", frames_every(7.0, 0.0)),
    (
      "one drawn for 200 with its host at 100",
      fn(draw, from, to) {
        if from < 100.0 && 100.0 < to {
          draw(100.0, 200.0)
        }
      },
    ),
  ]
}

///|
/// Keys `at` and `other` of `keys` changing places.
fn keys_swapped(keys : @signals.Signal[Array[Int]], at : Int, other : Int) -> Unit {
  let a = keys.get().copy()
  let k = a[at]
  a[at] = a[other]
  a[other] = k
  keys.set(a)
}

///|
/// The key at `at` of `keys` moved to `to`.
fn key_moved(keys : @signals.Signal[Array[Int]], at : Int, to : Int) -> Unit {
  let a = keys.get().copy()
  let k = a.remove(at)
  a.insert(to, k)
  keys.set(a)
}

///|
/// `count` keys of `keys` from `at` on gone.
fn keys_gone(keys : @signals.Signal[Array[Int]], at : Int, count : Int) -> Unit {
  let a = keys.get().copy()
  for _ in 0..<count {
    a.remove(at) |> ignore
  }
  keys.set(a)
}

///|
/// Keys 1000 to 1004 come into `keys` at `at`.
fn keys_come(keys : @signals.Signal[Array[Int]], at : Int) -> Unit {
  let a = keys.get().copy()
  for i in 0..<5 {
    a.insert(at + i, 1000 + i)
  }
  keys.set(a)
}

///|
/// Changes to what changing_case's list holds, said by the first and the last row in sight as they were (keys and
/// places the same then): rows changing places with one long gone past, moved on, gone, come, grown and shrunk; and
/// whether rows' heights changed.
fn list_changes(
  first_in : Int,
  last_in : Int,
) -> Array[(String, Bool, (@signals.Signal[Array[Int]], Map[Int, @signals.Signal[Double]]) -> Unit)] {
  [
    ("the last in sight and the second row changed places", false, fn(keys, _) { keys_swapped(keys, last_in, 1) }),
    ("the first in sight and the second row changed places", false, fn(keys, _) { keys_swapped(keys, first_in, 1) }),
    ("the first in sight moved 60 rows on", false, fn(keys, _) { key_moved(keys, first_in, first_in + 60) }),
    ("the last in sight moved 60 rows on", false, fn(keys, _) { key_moved(keys, last_in, last_in + 60) }),
    ("the first in sight gone", false, fn(keys, _) { keys_gone(keys, first_in, 1) }),
    ("the last in sight gone", false, fn(keys, _) { keys_gone(keys, last_in, 1) }),
    ("the three under the last in sight gone", false, fn(keys, _) { keys_gone(keys, last_in + 1, 3) }),
    ("five come two under the last in sight", false, fn(keys, _) { keys_come(keys, last_in + 3) }),
    ("five come under the first row", false, fn(keys, _) { keys_come(keys, 1) }),
    (
      "the five under the last in sight three times as tall",
      true,
      fn(_, tall) {
        for k in (last_in + 1)..=(last_in + 5) {
          tall.get(k).unwrap().set(120.0)
        }
      },
    ),
    (
      "the one under the first in sight twice as tall",
      true,
      fn(_, tall) { tall.get(first_in + 1).unwrap().set(80.0) },
    ),
    (
      "those over the first in sight half as tall",
      true,
      fn(_, tall) {
        for k in 0..<first_in {
          tall.get(k).unwrap().set(20.0)
        }
      },
    ),
  ]
}

///|
/// For each of list_changes made at 120 to changing_case's list flung `down` (or up) from `put`: what it told against
/// what frames every millisecond showed come in sight, for each way frames came, where it was laid out at 300 as those
/// frames lay it out; what is apart, said (`laid`: where it was laid out apart from them, rows come, gone or moved).
/// A row grown or shrunk after it was measured is gone past as tall as it was measured till it is laid out again
/// (list_laid_from_end's `known`), so where the frames between had it laid out again and these did not, the list is
/// laid out elsewhere: what it told is not compared there, where it is laid out being the layout's, not seen's.
fn changed_apart(down : Bool, put : Double) -> (Array[String], Array[String]) raise {
  let histories = frame_histories()
  let (_, _, at_120, _) = changed_on_the_way(fn(_, _) {  }, histories[0].1, down~, put~)
  guard at_120.length() > 1 else { return (["in sight at 120: \{at_120}"], []) }
  let apart : Array[String] = []
  let laid : Array[String] = []
  for c in list_changes(at_120[0], at_120[at_120.length() - 1]) {
    let (name, grown, change) = c
    let (by_ms, shown, _, at_300) = changed_on_the_way(change, histories[0].1, down~, put~)
    if by_ms != shown {
      apart.push("\{name}, every 1 ms: told \{by_ms}; came in sight \{shown}")
    }
    for h in histories[1:] {
      let (told, _, _, at) = changed_on_the_way(change, h.1, down~, put~)
      if at != at_300 {
        if !grown {
          laid.push("\{name}, \{h.0}: in sight at 300 \{at}, every 1 ms \{at_300}; told \{told}; came in sight every 1 ms \{shown}")
        }
      } else if told != shown {
        apart.push("\{name}, \{h.0}: told \{told}; came in sight every 1 ms \{shown}")
      }
    }
  }
  (apart, laid)
}

///|
test "scrolls_window flung up the column, what it holds changed in an event on its way (rows changing places with one gone past, moved on, gone, come, grown, shrunk): told seen of what came in sight at the logic's moments, as frames every millisecond show them come, in that order, whatever frames came on the way (none, every 16 or 7 ms, drawn ahead)" {
  let (apart, laid) = changed_apart(false, 0.0)
  // (apart in what it told, where it was laid out the same; laid out elsewhere)
  assert_eq(apart + laid, [], msg=(apart.map(fn(a) { "TOLD " + a }) + laid.map(fn(l) { "LAID " + l })).join("\n"))
}

///|
test "scrolls_window put 200 rows down and flung down the column, what it holds changed in an event on its way: told seen of what came in sight at the logic's moments, as frames every millisecond show them come, in that order, whatever frames came on the way" {
  let (apart, laid) = changed_apart(true, 8000.0)
  // (apart in what it told, where it was laid out the same; laid out elsewhere)
  assert_eq(apart + laid, [], msg=(apart.map(fn(a) { "TOLD " + a }) + laid.map(fn(l) { "LAID " + l })).join("\n"))
}

///|
test "an end-following list that becomes short during a glide tells seen with the same top alignment at the logic moment" {
  let histories = frame_histories()
  let shrink = fn(keys : @signals.Signal[Array[Int]], _) { keys.set([1000, 1001]) }
  let (expected, shown, _, at_end) = changed_on_the_way(
    shrink, histories[0].1, down=true, from_end=true, align_end=false,
  )
  assert_eq(expected, shown)
  assert_eq(at_end, [1000, 1001])
  for history in histories[1:] {
    let (told, _, _, final_rows) = changed_on_the_way(
      shrink, history.1, down=true, from_end=true, align_end=false,
    )
    assert_eq(final_rows, at_end, msg=history.0)
    assert_eq(told, expected, msg=history.0)
  }
}
