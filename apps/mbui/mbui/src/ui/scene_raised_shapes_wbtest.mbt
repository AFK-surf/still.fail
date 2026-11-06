// Two layers' shapes in a layer, one of them put over the old frame's scrim (View::over_scrim): its instances after the
// other's in the frame, its pieces still before them. Each frame after, both drawn again with more pieces, then again
// with as many, then kept: every band's pieces the ones a frame drawn anew in that state gives it, piece for piece.

///|
/// Outlines side by side from the left, each 10 across, `n` of them: squares (`square`), else triangles.
fn raised_outlines(n : Int, square : Bool, fill : Int64) -> Array[@paint.Shape] {
  // (and one of no outline first: a band of no pieces, if any, between others' pieces)
  let none = [@paint.shape_of([([], true)], fill~)]
  none + Array::makei(n, fn(i) {
    let x0 = i.to_double() * 12.0
    let points = if square {
      [x0, 0.0, x0 + 10.0, 0.0, x0 + 10.0, 10.0, x0, 10.0]
    } else {
      [x0, 10.0, x0 + 5.0, 0.0, x0 + 10.0, 10.0]
    }
    @paint.shape_of([(points, true)], fill~)
  })
}

///|
/// The page: two shapes' layers in a layer (`a` squares at the top, over the scrim while `menu`; `b` triangles below
/// it), `many` outlines each in `tint`; the old frame's modal layer and its scrim up while `menu`.
fn raised_shapes_page(
  menu : @signals.Signal[Bool],
  many : @signals.Signal[Int],
  tint : @signals.Signal[Int64],
) -> Unit {
  set_view_app(fn(root) {
    // (in a layer in a layer: what holds the one parted, and what holds that, kept round it or not as the frame drawn
    // anew has it)
    root.show(fn() { true }, fn(outer) {
      outer.width(Is(Some(400.0))).height(Is(Some(200.0))) |> ignore
      outer.show(fn() { true }, fn(holder) {
        holder.width(Is(Some(400.0))).height(Is(Some(200.0))) |> ignore
        holder.show(fn() { true }, fn(a) {
          a
          .width(Is(Some(200.0)))
          .height(Is(Some(20.0)))
          .over_scrim(By(fn() { menu.get() }))
          .shapes(By(fn() { raised_outlines(many.get(), true, 0x336699FFL) }))
          .tint(By(fn() { tint.get() }))
          |> ignore
        })
        holder.show(fn() { true }, fn(b) {
          b
          .offset(Is((0.0, 40.0)))
          .width(Is(Some(200.0)))
          .height(Is(Some(20.0)))
          .shapes(By(fn() { raised_outlines(many.get(), false, 0x993366FFL) }))
          .tint(By(fn() { tint.get() }))
          |> ignore
        })
      })
    })
    old(root, fn(c) {
      if menu.get() {
        c.overlay("menu", modal=true, scrim=0x00000040L, fn() {
          c.box(w=Px(80.0), h=Px(80.0), bg=0xFFFFFFFFL, fn() {  }) |> ignore
        })
        |> ignore
      }
    })
    .height(Is(Some(100.0)))
    |> ignore
  })
}

///|
/// Of the frame drawn last, each band (in the order of the frame's instances): where it is, its instance, and the
/// pieces it says are its (each piece's four numbers), those in the frame.
fn raised_bands() -> Array[(Double, Double, Int, Array[Double])] {
  let c = g()
  let pieces = c.segs.length() / 4
  let out = []
  for k in 0..<c.ninst {
    let q = k * inst_size
    if c.inst[q + 5] == 11.0 {
      let first = c.inst[q + 12].to_int()
      let n = c.inst[q + 13].to_int()
      let mine = []
      for p in first..<(first + n) {
        if p >= 0 && p < pieces {
          for j in 0..<4 {
            mine.push(c.segs[p * 4 + j])
          }
        } else {
          mine.push(-1.0e18)
        }
      }
      out.push((c.inst[q], c.inst[q + 1], k, mine))
    }
  }
  out
}

///|
/// The bands a frame drawn anew with `menu`, `many` and `tint` draws, each where it is and its pieces (no instance's
/// place: a frame put together may hold them elsewhere among the rest).
fn raised_anew(menu : Bool, many : Int, tint : Int64) -> Array[(Double, Double, Array[Double])] {
  let _t = Tester::new(fn(_) {  }, w=400.0, h=300.0)
  raised_shapes_page(@signals.signal(menu), @signals.signal(many), @signals.signal(tint))
  _t.draw()
  raised_bands().map(fn(b) { (b.0, b.1, b.3) })
}

///|
test "a layer put over the scrim after its sibling, both drawn again longer, then as long, then kept: each band its own pieces" {
  let menu = @signals.signal(false, same=fn(a, b) { a == b })
  let many = @signals.signal(2, same=fn(a, b) { a == b })
  let tint = @signals.signal(0x000000FFL, same=fn(a, b) { a == b })
  let steps : Array[(String, () -> Unit, Bool, Int, Int64)] = [
    ("first", fn() {  }, false, 2, 0x000000FFL),
    ("over the scrim", fn() { menu.set(true) }, true, 2, 0x000000FFL),
    ("both drawn again longer", fn() { many.set(4) }, true, 4, 0x000000FFL),
    ("both drawn again as long", fn() { tint.set(0x202020FFL) }, true, 4, 0x202020FFL),
    ("kept", fn() {  }, true, 4, 0x202020FFL),
    ("the scrim down", fn() { menu.set(false) }, false, 4, 0x202020FFL),
  ]
  // (each state's frame drawn anew first, alone: what the frame put together after it must come to)
  let anews = steps.map(fn(s) { raised_anew(s.2, s.3, s.4) })
  let said : Array[String] = []
  let splices : Array[(Int, Int, Int)] = []
  let t = Tester::new(fn(_) {  }, w=400.0, h=300.0)
  raised_shapes_page(menu, many, tint)
  for i, s in steps {
    let (when, step, m, _, _) = s
    let anew = anews[i]
    step()
    let before = scene_done()
    let sp = spliced_said.val
    t.draw()
    let work = scene_done()
    let spliced = (spliced_said.val.0 - sp.0, spliced_said.val.1 - sp.1, spliced_said.val.2 - sp.2)
    splices.push(spliced)
    let bands = raised_bands()
    // (the squares over the scrim: their bands after the triangles' in the frame)
    let top = bands.filter(fn(b) { b.1 < 20.0 }).map(fn(b) { b.2 })
    let below = bands.filter(fn(b) { b.1 >= 20.0 }).map(fn(b) { b.2 })
    let raised = top.length() > 0 && below.length() > 0 && top[0] > below[below.length() - 1]
    let empty = bands.filter(fn(b) { b.3.is_empty() }).length()
    said.push("\{when}: raised \{raised}, \{bands.length()} bands, \{empty} of no pieces, layers drawn \{work.layers - before.layers}, copied \{work.copied - before.copied}, spliced (all, pieces in another order, drawn to another number) \{spliced}")
    assert_eq(raised, m, msg="\{when}: \{said}")
    assert_eq(bands.map(fn(b) { (b.0, b.1, b.3) }), anew, msg="\{when}: \{said}")
  }
  println("raised shapes: \{said}")
  // (how many of its frames were spliced, said: none of these is (the frame drawn otherwise); scene_spliced_order_wbtest
  // splices the order this makes)
  ignore(splices)
}
