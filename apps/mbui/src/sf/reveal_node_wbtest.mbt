// A room opening and closing on what it holds as a node (reveal_node), drawn as an old view's room is (@motion.reveal's
// `middle`, followed as way_in follows it: a Move per point of what it holds): its words where they are drawn and how
// opaque, and how they fade out towards its cut, at its start, on its way and at its end, opening and closing.

///|
/// Longer than any of a room's ways here takes (a Move as far as two lines are tall, or four).
let past_any_way_ms : Double = 600.0

///|
/// Two lines said under something 300 wide.
let reveal_words : String = "Waiting for the browser to finish signing in, a while now: come back here once it is done"

///|
/// The words in a room 300 wide at the window's top left, as an old view or as a node, open as `on` says; the Tester.
fn reveal_pair(on : @signals.Signal[Bool], node : Bool) -> @ui.Tester {
  let style = @ui.text_style(size=Meta, color=Muted, center=true, w=Full)
  let t = @ui.Tester::new(
    fn(c) {
      if !node {
        c.box(w=Px(300.0), fn() {
          let target = if on.get() { 1.0 } else { 0.0 }
          let open = @motion.anim(c, "t/said", target, global=true)
          open.follow(target, @motion.move().per_unit(@motion.reveal_height("t/said")))
          let share = open.get()
          if share > 0.0 {
            @motion.reveal(c, "t/said", share, middle=true, fn() { c.text(reveal_words, style~) |> ignore })
          }
        })
        |> ignore
      }
    },
    w=400.0,
    h=300.0,
  )
  t.check_looks(false)
  if node {
    @ui.set_view_app(fn(root) {
      root.box(fn(b) {
        b.width(Is(Some(300.0))) |> ignore
        @motion.reveal_node(b, fn() { on.get() }, fn(h) {
          // (as the old one's words are set: the meta's size and its own line)
          let (size, line) = @ui.tree_theme().text_size(Meta)
          h
          .words(Is(reveal_words), look={ size, weight: 400, line, wrap: true })
          .ink(By(fn() { @ui.tree_theme().color(Muted) }))
          .words_centered(Is(true))
          |> ignore
        })
        |> ignore
      })
      |> ignore
    })
  }
  t.draw()
  t
}

///|
/// What is drawn of the words: each glyph's place and colour, and how the instances fade out towards the cut.
fn reveal_drawn(t : @ui.Tester) -> (Array[(Double, Double, Int64)], Array[(Int, Double, Double, Double, Double, Double, Double)]) {
  (t.drawn_glyphs(), t.drawn_fades().filter(fn(f) { f.0 == 1 }))
}

///|
test "a room on two lines said as a node, opened and closed: drawn as an old view's room once each is over" {
  let seen = fn(node : Bool) {
    let on = @signals.signal(false, same=fn(a, b) { a == b })
    let t = reveal_pair(on, node)
    let shut = reveal_drawn(t)
    on.set(true)
    t.frame()
    t.run_for(past_any_way_ms)
    let open = reveal_drawn(t)
    on.set(false)
    t.frame()
    t.run_for(past_any_way_ms)
    (shut, open, reveal_drawn(t))
  }
  let old = seen(false)
  let new = seen(true)
  assert_eq(
    (new == old, old.1.0.length() > 0, old.0.0.length(), old.2.0.length()),
    (true, true, 0, 0),
    msg="old \{old.1.0[:2]}\nnode \{new.1.0[:2]}",
  )
}

///|
/// The words in a room at the window's top left, as a node, open as `on` says, as wide as `width`, saying `words`; a
/// button 60 wide under them at its left, pressed counted in `pressed`. The Tester and the room.
fn node_room(
  on : @signals.Signal[Bool],
  width : @signals.Signal[Double],
  words : @signals.Signal[String],
  pressed : Ref[Int],
) -> (@ui.Tester, Ref[@view.View?]) {
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  t.check_looks(false)
  let room_at : Ref[@view.View?] = Ref(None)
  @ui.set_view_app(fn(root) {
    root.box(fn(b) {
      b.width(By(fn() { Some(width.get()) })) |> ignore
      room_at.val = Some(
        @motion.reveal_node(b, fn() { on.get() }, fn(h) {
          let (size, line) = @ui.tree_theme().text_size(Meta)
          h.box(fn(w) {
            w.words(By(fn() { words.get() }), look={ size, weight: 400, line, wrap: true }).words_centered(Is(true)) |> ignore
          })
          |> ignore
          h.box(fn(k) {
            k
            .width(Is(Some(60.0)))
            .height(Is(Some(20.0)))
            .ground(Is(0x3366CCFFL))
            .on_press(fn() { pressed.val += 1 })
            .says(Is(Some(@view.said(Button, label="Go"))))
            |> ignore
          })
          |> ignore
        }),
      )
    })
    |> ignore
  })
  t.draw()
  (t, room_at)
}

///|
/// How tall the room is, how tall what it holds is laid out (its own layout, not as drawn), and where the button is
/// drawn (its middle across, as it is grown or shrunk about the middle of what is drawn).
fn room_sizes(room : @view.View) -> (Double, Double) {
  let held = room.kids()[0]
  (room.laid_size().1, held.laid_size().1)
}

///|
/// The share of its way a room's Move as far as `natural` has gone `at` after `t0` from `from` to `to`.
fn move_share(natural : Double, t0 : Double, at : Double, from? : Double = 0.0, to? : Double = 1.0) -> Double {
  let way = @motion.Way::new(from)
  way.go(to, @motion.move().per_unit(natural), at=t0)
  way.value_at(t0 + at)
}

///|
test "a room as a node opened the first time, each moment looked at in a run of its own, frames drawn all along or none: as tall as the Move's share of what it holds at that moment, from its first frame" {
  let seen = fn(at : Double, stepped : Bool) {
    let on = @signals.signal(false, same=fn(a, b) { a == b })
    let (t, room) = node_room(on, @signals.signal(300.0), @signals.signal(reveal_words), Ref(0))
    let t0 = t.time()
    on.set(true)
    if stepped {
      while t.time() + 16.0 < t0 + at {
        t.frame_at(t.time() + 16.0)
      }
    }
    t.frame_at(t0 + at)
    room_sizes(room.val.unwrap())
  }
  let moments = [16.0, 60.0, 120.0]
  let stepped = moments.map(fn(at) { seen(at, true) })
  let jumped = moments.map(fn(at) { seen(at, false) })
  let natural = stepped[0].1
  let want = moments.map(fn(at) { natural * move_share(natural, 0.0, at) })
  assert_eq(
    (stepped == jumped, stepped.map(fn(s) { (s.0 * 1000.0).round() }) == want.map(fn(w) { (w * 1000.0).round() }), natural > 30.0),
    (true, true, true),
    msg="\{stepped} \{jumped} want \{want}",
  )
}

///|
test "a room as a node turned back half way open: closing from where it was, on the Move back from there" {
  let on = @signals.signal(false, same=fn(a, b) { a == b })
  let (t, room) = node_room(on, @signals.signal(300.0), @signals.signal(reveal_words), Ref(0))
  let t0 = t.time()
  on.set(true)
  t.frame_at(t0 + 60.0)
  let (_, natural) = room_sizes(room.val.unwrap())
  on.set(false)
  t.frame_at(t0 + 100.0)
  let (h, _) = room_sizes(room.val.unwrap())
  // (the same way turned back at 60: from where it is then, as fast as it goes then)
  let way = @motion.Way::new(0.0)
  way.go(1.0, @motion.move().per_unit(natural), at=t0)
  let k = way.value_at(t0 + 60.0)
  way.go(0.0, @motion.move().per_unit(natural), at=t0 + 60.0)
  let back = way.value_at(t0 + 100.0)
  assert_eq(((h * 1000.0).round(), back < k), ((natural * back * 1000.0).round(), true), msg="\{k} \{back}")
}

///|
test "a room as a node made narrower, then its words longer, on its way open: as tall as its share of what it holds comes to then, at that moment" {
  let on = @signals.signal(false, same=fn(a, b) { a == b })
  let width = @signals.signal(300.0, same=fn(a, b) { a == b })
  let words = @signals.signal(reveal_words, same=fn(a, b) { a == b })
  let (t, room) = node_room(on, width, words, Ref(0))
  let t0 = t.time()
  on.set(true)
  t.frame_at(t0 + 40.0)
  let (_, natural) = room_sizes(room.val.unwrap())
  width.set(180.0)
  t.frame_at(t0 + 60.0)
  let (h1, n1) = room_sizes(room.val.unwrap())
  words.set(reveal_words + " " + reveal_words)
  t.frame_at(t0 + 80.0)
  let (h2, n2) = room_sizes(room.val.unwrap())
  // (its way said once, by how tall it was as it set off: its share at each moment that one's)
  let k1 = move_share(natural, t0, 60.0)
  let k2 = move_share(natural, t0, 80.0)
  assert_eq(
    ((h1 - n1 * k1).abs() < 1.0e-6, (h2 - n2 * k2).abs() < 1.0e-6, n1 > natural, n2 > n1),
    (true, true, true, true),
    msg="\{natural} \{n1} \{n2}; \{h1} \{h2}",
  )
}

///|
test "a room as a node grown about the middle of what it draws: a button at its left grows where it is, not toward the page's middle" {
  let on = @signals.signal(false, same=fn(a, b) { a == b })
  let (t, room) = node_room(on, @signals.signal(300.0), @signals.signal(""), Ref(0))
  let t0 = t.time()
  on.set(true)
  t.frame_at(t0 + 60.0)
  let held = room.val.unwrap().kids()[0]
  let button = held.kids()[1]
  let (x, _, w, _) = button.rect()
  // (what is drawn: the button alone, 60 wide at the left; grown about its middle, 30 in)
  assert_eq(((x + w / 2.0) * 1000.0).round(), 30000.0, msg="\{button.rect()}")
}

///|
test "a room as a node closing and shut: from the moment it is told to close, with no frame drawn, what it holds is not pressed by its id nor read out; open, it is" {
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let pressed = Ref(0)
  let (t, room) = node_room(on, @signals.signal(300.0), @signals.signal(reveal_words), pressed)
  let tree = @ui.view_tree().unwrap()
  let button = room.val.unwrap().kids()[0].kids()[1].id()
  let read = fn() { tree.said_order().iter().any(fn(n) { n.id == button && !n.hidden }) }
  let open_read = read()
  let open_pressed = tree.activate_at(button, t.time())
  on.set(false)
  // (no frame drawn: as of the moment it was told)
  let closing = (tree.activate_at(button, t.time()), tree.run_press_at(button, t.time()), read())
  t.run_for(past_any_way_ms)
  let shut = (tree.activate_at(button, t.time()), tree.run_press_at(button, t.time()), read())
  assert_eq(
    (open_read, open_pressed, closing, shut, pressed.val),
    (true, true, (false, false, false), (false, false, false), 1),
  )
}

///|
test "a room on two lines said as a node, opened and closed a second time (the old one's height of them known): drawn as an old view's room on its way, the old one's way set off at its first frame after what opened or closed it" {
  // (the old one's way is set off as it is built, the frame after its cause, 16 later here; the node's at its cause:
  // the node at `x` after it is the old one at 16 + `x`, as open)
  let seen = fn(node : Bool) {
    let on = @signals.signal(false, same=fn(a, b) { a == b })
    let t = reveal_pair(on, node)
    // (the old one's first opening: its words' height not known yet, nothing to go over)
    on.set(true)
    t.frame()
    t.run_for(past_any_way_ms)
    on.set(false)
    t.frame()
    t.run_for(past_any_way_ms)
    let out = []
    let lag = if node { 0.0 } else { 16.0 }
    let t0 = t.time()
    on.set(true)
    t.frame_at(t0 + 16.0)
    for at in [40.0, 80.0, 120.0] {
      t.frame_at(t0 + lag + at)
      out.push(reveal_drawn(t))
    }
    t.run_for(past_any_way_ms)
    let t1 = t.time()
    on.set(false)
    t.frame_at(t1 + 16.0)
    for at in [40.0, 80.0, 120.0] {
      t.frame_at(t1 + lag + at)
      out.push(reveal_drawn(t))
    }
    out
  }
  let old = seen(false)
  let new = seen(true)
  // (each number the same but for what working it out in another order leaves in a double's last digits)
  let near = fn(a : Double, b : Double) { (a - b).abs() <= 1.0e-9 }
  let alike = Array::makei(old.length(), fn(k) {
    let (o, n) = (old[k], new[k])
    o.0.length() == n.0.length() &&
    o.0.iter().zip(n.0.iter()).all(fn(p) { near(p.0.0, p.1.0) && near(p.0.1, p.1.1) && p.0.2 == p.1.2 }) &&
    o.1.length() == n.1.length() &&
    o.1
    .iter()
    .zip(n.1.iter())
    .all(fn(p) {
      p.0.0 == p.1.0 &&
      near(p.0.1, p.1.1) &&
      near(p.0.2, p.1.2) &&
      near(p.0.3, p.1.3) &&
      near(p.0.4, p.1.4) &&
      near(p.0.5, p.1.5) &&
      near(p.0.6, p.1.6)
    })
  })
  assert_eq(
    alike,
    Array::make(old.length(), true),
    msg="old \{old.map(fn(o) { (o.0[:1], o.1[:1]) })}\nnode \{new.map(fn(o) { (o.0[:1], o.1[:1]) })}",
  )
}
