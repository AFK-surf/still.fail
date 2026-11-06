// What holds a layer drawn otherwise than by the tree alone (glass, an old view, a native view's anchor) kept round it
// as it moves, is cut otherwise and grows: each frame draws what a frame drawn anew in that state draws, instance for
// instance, those of glass and the old view with them (what drew each again, what was kept, said).

///|
/// The page: a box moved down by `y`, `h` tall, cut to its round corners, holding words, a pane of glass of a layer of
/// its own, an old view and a native view's anchor.
fn own_kept_page(y : @signals.Signal[Double], h : @signals.Signal[Double], ground : @signals.Signal[Int64]) -> Unit {
  set_view_app(fn(root) {
    root.box(fn(page) {
      page.width(Is(Some(400.0))).height(Is(Some(300.0))).ground(Is(0xFFFFFFFFL)) |> ignore
      page.show(fn() { true }, fn(holder) {
        holder
        .width(Is(Some(300.0)))
        .height(By(fn() { Some(h.get()) }))
        .offset(By(fn() { (10.0, y.get()) }))
        .clips(Is(true))
        .radius(Is(12.0))
        .ground(By(fn() { ground.get() }))
        |> ignore
        holder.box(fn(w) { w.words(Is("held words")) |> ignore }) |> ignore
        holder.show(fn() { true }, fn(g) {
          g.over(Is(true)).offset(Is((20.0, 30.0))).width(Is(Some(80.0))).height(Is(Some(40.0))).radius(Is(20.0)).glass(Is(Some(tree_frost)))
          |> ignore
        })
        old(holder.box(fn(_) {  }), fn(c) { c.box(w=Px(60.0), h=Px(20.0), bg=0x336699FFL, fn() {  }) |> ignore })
        .height(Is(Some(20.0)))
        |> ignore
        holder.box(fn(a) { a.width(Is(Some(40.0))).height(Is(Some(30.0))).native_anchor(Is("field")) |> ignore }) |> ignore
      })
    })
    |> ignore
  })
}

///|
/// What a frame drawn anew with the box at `y`, `h` tall, draws.
fn own_kept_anew(y : Double, h : Double, ground : Int64) -> Array[Array[Double]] {
  let t = Tester::new(fn(_) {  }, w=400.0, h=300.0)
  own_kept_page(@signals.signal(y), @signals.signal(h), @signals.signal(ground))
  t.draw()
  t.drawn_instances()
}

///|
test "what holds glass, an old view and a native view's anchor kept round them, moved, cut otherwise, grown: as drawn anew" {
  let (blue, red) = (0xEEF2FFFFL, 0xFFE0E0FFL)
  let steps : Array[(String, Double, Double, Int64)] = [
    ("first", 20.0, 120.0, blue),
    ("moved by whole pixels", 26.0, 120.0, blue),
    ("moved between them", 26.75, 120.0, blue),
    ("again", 31.25, 120.0, blue),
    ("grown", 31.25, 160.0, blue),
    ("kept", 31.25, 160.0, blue),
    ("what is behind the glass otherwise", 31.25, 160.0, red),
    ("moved past the foot", 230.0, 160.0, red),
    ("back", 20.0, 120.0, blue),
  ]
  let anews = steps.map(fn(s) { own_kept_anew(s.1, s.2, s.3) })
  let y = @signals.signal(steps[0].1)
  let h = @signals.signal(steps[0].2)
  let ground = @signals.signal(steps[0].3)
  let t = Tester::new(fn(_) {  }, w=400.0, h=300.0)
  own_kept_page(y, h, ground)
  let said : Array[String] = []
  for i, s in steps {
    let (when, at, tall, ink) = s
    y.set(at)
    h.set(tall)
    ground.set(ink)
    let before = scene_done()
    let (own0, along0) = (scene_own_redrawn.val, scene_along_own.val)
    t.draw()
    let work = scene_done()
    said.push(
      "\{when}: layers drawn \{work.layers - before.layers}, copied \{work.copied - before.copied}, of its own drawn again where its reference is \{scene_own_redrawn.val - own0} (moved with what holds them \{scene_along_own.val - along0})",
    )
    let now = t.drawn_instances()
    let anew = anews[i]
    let mut first = "\{now.length()} and \{anew.length()} instances"
    for k in 0..<now.length() {
      if k < anew.length() && now[k] != anew[k] {
        let ds = []
        for j in 0..<now[k].length() {
          if now[k][j] != anew[k][j] {
            ds.push("\{j}: \{now[k][j]}/\{anew[k][j]}")
          }
        }
        first = "\{first}, instance \{k} of kind \{anew[k][5]}: \{ds}"
        break
      }
    }
    assert_true(now == anew, msg="\{when}: \{first}; \{said}")
  }
  println("own only kept: \{said}")
}
