// Words picked by a finger held still on a cover of the window's tree over them, its hold handed through to them
// (View::gesture's `through`): as with no cover, frames drawn between or none.

///|
let pick_later_ms : Double = 100.0

///|
/// When words are laid out for picking: always, or only as they are held (a press in them, a hold handed them).
enum Laid {
  Always
  Held
}

///|
/// Words in an old view, a cover of the tree's over them holding through; a finger held still on the first word past a
/// long press and let go, frames drawn as it is held or (`frames` false) none between its down and its up. What was
/// picked then, and what the cover was told.
fn picked_through(frames : Bool, laid? : Laid = Always) -> ((Int, Int, Bool), Array[String]) {
  let p = @kit.Pick::new()
  let said : Array[String] = []
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=200.0, platform=2)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    root.box(fn(b) {
      b.over(Is(true)).width(Is(Some(400.0))).height(Is(Some(200.0))) |> ignore
      @ui.old(b, fn(c) {
        let id = c.id("w")
        c.takes_presses(id)
        let box = c.box(id~, fn() { c.rich([@ui.plain("alpha beta gamma delta")], wrap=false) |> ignore })
        // (its words laid out: always; or only while a press is in it, or a hold handed it, or once picked, as a
        // chat's message lays out its words)
        let lays = match laid {
          Always => true
          Held => p.of("w") || ((c.press().down || c.handed_hold() is Some(_)) && c.press_within(id))
        }
        if lays {
          c.words(box, "w", a=p.a, b=p.b, color=0x3B82F640L)
        }
        if p.hold(c, "w", id) {
          c.take_press()
        }
        p.slide(c)
      })
      .over(Is(true))
      |> ignore
      b.box(fn(cv) {
        cv
        .over(Is(true))
        .width(Is(Some(400.0)))
        .height(Is(Some(200.0)))
        .gesture(
          @ui.touch_slop(),
          press=fn(_) { said.push("cover press") },
          tap=fn(_) { said.push("cover tap") },
          drag=fn(d) { said.push("cover drag \{d.kind}") },
          through=@ui.long_press_ms,
        )
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let (rx, ry, _, rh) = t.rect_of("alpha beta gamma delta").unwrap()
  let (x, y) = (rx + 4.0, ry + rh / 2.0)
  t.touch(0, x, y)
  if frames {
    t.draw()
    t.run_for(@ui.long_press_ms + pick_later_ms)
  } else {
    t.advance(@ui.long_press_ms + pick_later_ms)
  }
  t.touch(2, x, y)
  t.draw()
  ((p.a, p.b, p.of("w")), said)
}

///|
test "words under a cover holding through, held still past a long press and let go: the word under the finger picked, the cover's hold called off (no tap); with no frame between its down and its up, the same" {
  let want = ((0, 5, true), ["cover press", "cover drag Off"])
  assert_eq(picked_through(true), want, msg="frames between")
  assert_eq(picked_through(false), want, msg="no frame between")
}

///|
test "words laid out only as they are held, under a cover holding through: held past a long press and let go with no frame between, the frame after picks the word under the finger, as with frames between; once" {
  let want = ((0, 5, true), ["cover press", "cover drag Off"])
  assert_eq(picked_through(true, laid=Held), want, msg="frames between")
  assert_eq(picked_through(false, laid=Held), want, msg="no frame between")
}

///|
/// What comes after a finger held past a long press on words under a cover holding through, with no frame between
/// (handed_lost's): nothing; the press called off instead of let go; or, let go, before a frame: the words not shown in
/// the frame it comes to (shown in the one after), a modal layer over them, their old view taking no presses, the
/// window's tree made anew, a press on a button of the tree's (as it goes down now, or `same`: said to go down at the moment the first did).
enum After {
  Nothing
  Off
  Hidden
  Modal
  Inert
  Anew
  Button(same~ : Bool)
} derive(Show)

///|
/// Words laid out only as they are held under a cover holding through (picked_through's), a button of the tree's below
/// them, the finger held past a long press with no frame between, then `after`: whether a word is picked once frames come.
fn handed_lost(after : After) -> Bool {
  let p = @kit.Pick::new()
  let shown = @signals.signal(true)
  let open = @signals.signal(true)
  let modal = @signals.signal(false)
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=2)
  t.check_looks(false)
  let make = fn(root : @view.View) {
    root.box(fn(b) {
      b.over(Is(true)).width(Is(Some(400.0))).height(Is(Some(300.0))) |> ignore
      @ui.old(b, fn(c) {
        if !shown.get() {
          return
        }
        let id = c.id("w")
        c.takes_presses(id)
        let box = c.box(id~, fn() { c.rich([@ui.plain("alpha beta gamma delta")], wrap=false) |> ignore })
        if p.of("w") || ((c.press().down || c.handed_hold() is Some(_)) && c.press_within(id)) {
          c.words(box, "w", a=p.a, b=p.b, color=0x3B82F640L)
        }
        if p.hold(c, "w", id) {
          c.take_press()
        }
      })
      .over(Is(true))
      .presses(By(fn() { open.get() }))
      |> ignore
      b.box(fn(cv) {
        cv.over(Is(true)).width(Is(Some(400.0))).height(Is(Some(200.0))).gesture(@ui.touch_slop(), through=@ui.long_press_ms) |> ignore
      })
      |> ignore
      b.box(fn(bt) {
        bt.offset(Is((0.0, 220.0))).width(Is(Some(100.0))).height(Is(Some(60.0))).on_press(fn() {  }) |> ignore
      })
      |> ignore
      b.box(fn(l) {
        l.over(Is(true)).modal(By(fn() { modal.get() })) |> ignore
      })
      |> ignore
    })
    |> ignore
  }
  @ui.set_view_app(make)
  t.draw()
  let (rx, ry, _, rh) = t.rect_of("alpha beta gamma delta").unwrap()
  let (x, y) = (rx + 4.0, ry + rh / 2.0)
  let down = t.time()
  t.touch(0, x, y)
  t.advance(@ui.long_press_ms + pick_later_ms)
  t.touch(if after is Off { 3 } else { 2 }, x, y)
  match after {
    Hidden => {
      shown.set(false)
      t.draw()
      shown.set(true)
    }
    Modal => modal.set(true)
    Inert => open.set(false)
    Anew => @ui.set_view_app(make)
    Button(same~) =>
      if same {
        t.touch_at(0, 50.0, 250.0, down)
        t.touch_at(2, 50.0, 250.0, down)
      } else {
        t.touch(0, 50.0, 250.0)
        t.touch(2, 50.0, 250.0)
      }
    _ => ()
  }
  t.draw()
  modal.set(false)
  open.set(true)
  t.draw()
  t.draw()
  p.of("w")
}

///|
test "a hold handed through and not taken yet: called off, or let go and, before a frame, what it was held on not shown in the frame it came to, a modal layer over it, its old view taking no presses, the tree made anew, another press down (on a button of the tree's; at the same moment as it): picks nothing later" {
  let picked = [Off, Hidden, Modal, Inert, Anew, Button(same=false), Button(same=true)].filter(handed_lost).map(fn(a) {
    "\{a}"
  })
  assert_eq(picked, [])
  // (none of them: picked, as picked_through has it)
  assert_eq(handed_lost(Nothing), true)
}

///|
/// Words in an old view, under a cover of the tree's: one a finger drags only once held (`held_first`; `swiped`: a
/// finger down on the first word moved past the slop at once, let go there with no other move), or one holding through
/// (not `swiped`: a finger held still on the first word past a long press and let go); frames drawn between or none.
/// What was picked, whether anything was, how many times the words' hold took the press, what the cover was told, and what was felt (a hold handed to words through a
/// cover is felt by nothing of theirs: as with picked_through).
fn picked_under(swiped : Bool, frames : Bool) -> ((Int, Int, Bool), Int, Array[String], Array[@ui.Haptic]) {
  let p = @kit.Pick::new()
  // (how many times its hold took the press: picked)
  let took = Ref(0)
  let said : Array[String] = []
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=200.0, platform=2)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    root.box(fn(b) {
      b.over(Is(true)).width(Is(Some(400.0))).height(Is(Some(200.0))) |> ignore
      @ui.old(b, fn(c) {
        let id = c.id("w")
        c.takes_presses(id)
        let box = c.box(id~, fn() { c.rich([@ui.plain("alpha beta gamma delta")], wrap=false) |> ignore })
        c.words(box, "w", a=p.a, b=p.b, color=0x3B82F640L)
        if p.hold(c, "w", id) {
          c.take_press()
          took.val += 1
        }
        p.slide(c)
      })
      .over(Is(true))
      |> ignore
      b.box(fn(cv) {
        cv.over(Is(true)).width(Is(Some(400.0))).height(Is(Some(200.0))) |> ignore
        let press = fn(_d : @view.Drag) { said.push("cover press") }
        let tap = fn(_d : @view.Drag) { said.push("cover tap") }
        let drag = fn(d : @view.Drag) { said.push("cover drag \{d.kind}") }
        if swiped {
          cv.gesture(@ui.touch_slop(), press~, tap~, drag~, hold=(@ui.long_press_ms, fn(_) { said.push("cover held") }), held_first=fn(_) {
            true
          })
          |> ignore
        } else {
          cv.gesture(@ui.touch_slop(), press~, tap~, drag~, through=@ui.long_press_ms) |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let (rx, ry, _, rh) = t.rect_of("alpha beta gamma delta").unwrap()
  let (x, y) = (rx + 4.0, ry + rh / 2.0)
  let t0 = t.time() + pick_later_ms
  t.advance(t0 - t.time())
  t.touch_raw(0, 1, x, y, t0)
  if swiped {
    let at = t0 + pick_later_ms
    if frames {
      t.frame_at(t0 + pick_later_ms / 2.0)
    }
    t.advance(at - t.time())
    t.touch_raw(1, 1, x + @ui.touch_slop() * 4.0, y, at)
    t.touch_raw(2, 1, x + @ui.touch_slop() * 4.0, y, at)
  } else {
    let at = t0 + @ui.long_press_ms + pick_later_ms
    if frames {
      t.frame_at(t0 + pick_later_ms)
      t.frame_at(t0 + @ui.long_press_ms + pick_later_ms / 2.0)
    }
    t.advance(at - t.time())
    t.touch_raw(2, 1, x, y, at)
  }
  t.run_for(@ui.long_press_ms * 2.0)
  ((p.a, p.b, p.of("w")), took.val, said, t.haptics())
}

///|
test "words under a cover a finger drags only once held, the finger moved past the slop at once and let go: nothing picked, nothing felt; under one holding through, held past a long press: the word picked once (a hold handed through felt by none, as ever); frames or none" {
  for frames in [true, false] {
    let (picked, took, said, felt) = picked_under(true, frames)
    assert_eq((picked.2, took, said, felt), (false, 0, ["cover press", "cover drag Off"], []), msg="swiped, frames \{frames}: \{picked}")
    let held = picked_under(false, frames)
    assert_eq(held, ((0, 5, true), 1, ["cover press", "cover drag Off"], []), msg="held, frames \{frames}: \{held}")
  }
}
