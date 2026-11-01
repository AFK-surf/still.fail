// old_anchor: a node of the tree where an old view's target is, told as the old frame publishes its targets, and the
// same frames as the old frame's own way to it (a build reading Ctx::rect_of, as kit's anchor_of does): the tree
// settled, the pointer still, only the old target moved; never drawn yet, drawn, moved, gone, the node going out.

///|
test "old_anchor: follows an old target the frame the old frame's own reading of it does; never drawn, where it was told; gone, where it was last, going out there" {
  let (drawn, at, open) = (@signals.signal(false), @signals.signal(100.0), @signals.signal(false))
  let trig = Ref(-1)
  // (what the old frame's build read of it, as kit's anchor_of reads it: the last frame's targets)
  let read : Ref[(Double, Double, Double, Double)?] = Ref(None)
  let node = Ref(None)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  set_view_app(fn(root) {
    old(root, fn(c) {
      let id = c.id("trigger")
      trig.val = id
      read.val = c.rect_of(id)
      c.box(w=Fill(1.0), h=Fill(1.0), fn() {
        c.box(w=Px(10.0), h=Px(at.get()), fn() {  }) |> ignore
        if drawn.get() {
          c.box(id~, w=Px(50.0), h=Px(20.0), fn() {  }) |> ignore
          c.clicked(id) |> ignore
        }
      })
      |> ignore
    })
    .grow(Is(1.0))
    |> ignore
    root.show(fn() { open.get() }, fn(l) {
      l.over(Is(true)) |> ignore
      let a = old_anchor(l, trig.val, (7.0, 8.0, 0.0, 0.0))
      a.ground(Is(0xff0000ffL)) |> ignore
      node.val = Some(a.id())
    }, leave=anchor_leave_ms)
  })
  t.draw()
  // (opened once the old view has said what it calls its target)
  open.set(true)
  t.draw()
  let tree = view_tree().unwrap()
  let placed = fn() {
    match tree.drawn().iter().find_first(fn(d) { Some(d.id) == node.val }) {
      Some(d) => Some((d.x, d.y, d.w, d.h))
      None => None
    }
  }
  // (each frame: what the old build read, where the node is)
  let frames = fn(n : Int) {
    let out = []
    for _ in 0..<n {
      t.frame()
      out.push((read.val, placed()))
    }
    out
  }
  let never = frames(3)
  drawn.set(true)
  let shown = frames(3)
  // (all at rest: the tree, the pointer; only the old target moved)
  t.run_for(anchor_leave_ms)
  at.set(200.0)
  let moved = frames(3)
  drawn.set(false)
  let gone = frames(3)
  open.set(false)
  t.frame()
  let going = placed()
  t.run_for(anchor_leave_ms)
  let r1 = Some((0.0, 100.0, 50.0, 20.0))
  let r2 = Some((0.0, 200.0, 50.0, 20.0))
  let nowhere = Some((7.0, 8.0, 0.0, 0.0))
  println("OLDANCHOR never \{never} shown \{shown} moved \{moved} gone \{gone} going \{going}")
  assert_eq(never, [(None, nowhere), (None, nowhere), (None, nowhere)])
  // (the node where the old build's reading is, each frame it reads one)
  for f in shown + moved {
    if f.0 is Some(_) {
      assert_eq(f.1, f.0, msg="\{shown} \{moved}")
    }
  }
  assert_eq((shown[shown.length() - 1], moved[moved.length() - 1]), ((r1, r1), (r2, r2)))
  assert_eq((gone[gone.length() - 1], going, placed()), ((None, r2), r2, None))
}

///|
let anchor_leave_ms : Double = 100.0
