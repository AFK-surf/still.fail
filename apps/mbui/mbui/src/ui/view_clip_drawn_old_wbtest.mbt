// A node's round clip as it is painted (View::clip_drawn) against an old view's rounded clipping box (Ctx::box's
// `clip` and `radius`), side by side: the same geometry built either way, drawn the same (where what it holds is, its
// clip's rect, its corners and how smooth they are, its outer clip), and a press at every point of the window reaching
// what it holds in the one where it does in the other; a still pointer over it as its corners change, alike.

///|
/// A clipping box: where it is in what holds it (x, y), how big (w, h), how round.
priv struct RoundCut {
  x : Double
  y : Double
  w : Double
  h : Double
  r : Double
}

///|
/// What is drawn of the red target last frame (its instance's numbers: its rect, its clip, its corners' radii and how
/// smooth they are, its outer clip), and its window rect as drawn, (x0, y0, x1, y1).
fn red_drawn() -> Array[Double] {
  let c = g()
  let want = ((red >> 24) & 0xFFL).to_double() / 255.0
  let mut found : Array[Double] = []
  for k in 0..<c.ninst {
    let b = k * inst_size
    if c.inst[b + 5] == 0.0 && c.inst[b + 8] == want && c.inst[b + 9] == (0x3B : Int).to_double() / 255.0 {
      found = [0, 1, 2, 3, 16, 17, 18, 19, 24, 25, 26, 27, 28, 29, 30, 31, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51].map(
        fn(j) { c.inst[b + j] },
      )
    }
  }
  found
}

///|
/// The cuts each in the one before, the red target (`tx`, `ty`, `tw`, `th`) in the last, as old views (an old
/// view's id for the target into `id`, whether it is lit into `lit`); the last's radius `radius` when said.
fn round_cuts_old(
  cuts : Array[RoundCut],
  target : (Double, Double, Double, Double),
  id : Ref[Int],
  lit : Ref[Bool],
  radius : @signals.Signal[Double]?,
) -> (Ctx) -> Unit {
  fn(c) {
    fn go(i : Int) -> Unit {
      if i == cuts.length() {
        let t = c.id("target")
        id.val = t
        lit.val = c.hovered(t)
        if c.clicked(t) {
          ()
        }
        c.box(w=Px(target.2), h=Px(target.3), ml=target.0, mt=target.1, bg=red, id=t, fn() {  }) |> ignore
      } else {
        let k = cuts[i]
        let r = match radius {
          Some(s) if i == cuts.length() - 1 => s.get()
          _ => k.r
        }
        c.box(w=Px(k.w), h=Px(k.h), ml=k.x, mt=k.y, radius=r, clip=true, align=AStart, fn() { go(i + 1) }) |> ignore
      }
    }

    c.box(align=AStart, fn() { go(0) }) |> ignore
  }
}

///|
/// The same as the window's tree: each cut a node over the one before, placed so, cutting what it holds to itself as it
/// is painted, round as it is; the target over the last, taking a press (into `node`).
fn round_cuts_tree(
  cuts : Array[RoundCut],
  target : (Double, Double, Double, Double),
  node : Ref[@view.View?],
  radius : @signals.Signal[Double]?,
) -> (@view.View) -> Unit {
  fn(root) {
    fn go(v : @view.View, i : Int) -> Unit {
      v.box(fn(n) {
        n.over(Is(true)) |> ignore
        if i == cuts.length() {
          node.val = Some(n)
          n
          .offset(Is((target.0, target.1)))
          .width(Is(Some(target.2)))
          .height(Is(Some(target.3)))
          .ground(Is(red))
          .presses(Is(true))
          .on_press(fn() {  })
          |> ignore
        } else {
          let k = cuts[i]
          let r : @view.Live[Double] = match radius {
            Some(s) if i == cuts.length() - 1 => By(fn() { s.get() })
            _ => Is(k.r)
          }
          n
          .offset(Is((k.x, k.y)))
          .width(Is(Some(k.w)))
          .height(Is(Some(k.h)))
          .radius(r)
          .clip_drawn(Is(Some((0.0, 0.0, k.w, k.h))))
          |> ignore
          go(n, i + 1)
        }
      })
      |> ignore
    }

    go(root, 0)
  }
}

///|
/// The points of the window a press at reaches the target, each half a point in from a whole one, one apart.
fn round_reached(w : Int, h : Int, hits : (Double, Double) -> Bool) -> Array[Bool] {
  let out = []
  for y in 0..<h {
    for x in 0..<w {
      out.push(hits(x.to_double() + 0.5, y.to_double() + 0.5))
    }
  }
  out
}

///|
/// The same geometry as old views and as the window's tree at `scale`: drawn the same, a press reaching the target at
/// the same points; some of the target's own rect cut away, some reached, some not (each case met).
fn round_cuts_alike(cuts : Array[RoundCut], target : (Double, Double, Double, Double), scale : Double, msg : String) -> Unit raise {
  let (w, h) = (160, 160)
  let id = Ref(0)
  let lit = Ref(false)
  let t = Tester::new(round_cuts_old(cuts, target, id, lit, None), w=w.to_double(), h=h.to_double(), scale~)
  t.draw()
  t.draw()
  let old_drawn = red_drawn()
  let c = t.ctx()
  let old = round_reached(w, h, fn(x, y) { hit_in(c.hit_ids, c.hit_rects, x, y) == id.val })
  let node : Ref[@view.View?] = Ref(None)
  let t2 = Tester::new(fn(_c) {  }, w=w.to_double(), h=h.to_double(), scale~)
  set_view_app(round_cuts_tree(cuts, target, node, None))
  t2.draw()
  t2.frame()
  let tree = view_tree().unwrap()
  let n = node.val.unwrap()
  let tree_drawn = red_drawn()
  let now = round_reached(w, h, fn(x, y) {
    match tree.target_at(x, y) {
      @view.Pressed(i) => i == n.id()
      _ => false
    }
  })
  assert_true(old_drawn.length() > 0, msg="\{msg}: the target drawn as old views")
  assert_eq(tree_drawn, old_drawn, msg="\{msg}: drawn the same")
  let apart = []
  let mut hit = 0
  let mut cut = 0
  for i in 0..<old.length() {
    let (x, y) = ((i % w).to_double() + 0.5, (i / w).to_double() + 0.5)
    if old[i] != now[i] {
      apart.push((x, y, old[i]))
    }
    if old[i] {
      hit += 1
    }
    // (in the rect it is drawn in, cut away)
    if !old[i] && x >= old_drawn[0] && y >= old_drawn[1] && x < old_drawn[0] + old_drawn[2] && y < old_drawn[1] + old_drawn[3] {
      cut += 1
    }
  }
  assert_eq(apart.length(), 0, msg="\{msg}: pressed apart at \{apart.iter().take(12).collect()}")
  assert_true(hit > 0 && cut > 0, msg="\{msg}: \{hit} points reached, \{cut} of its rect cut away")
}

///|
test "a node's round clip as painted against an old view's: one, two nested, one partly past the other, a small target reached from round it; at two scales" {
  let one = [{ x: 20.0, y: 20.0, w: 80.0, h: 40.0, r: 12.0 }]
  let nested = [{ x: 20.0, y: 20.0, w: 80.0, h: 80.0, r: 16.0 }, { x: 0.0, y: 0.0, w: 40.0, h: 80.0, r: 6.0 }]
  let across = [{ x: 20.0, y: 20.0, w: 80.0, h: 80.0, r: 16.0 }, { x: 50.0, y: 10.0, w: 50.0, h: 50.0, r: 10.0 }]
  for scale in [1.0, 2.0] {
    round_cuts_alike(one, (0.0, 0.0, 80.0, 40.0), scale, "one at \{scale}")
    round_cuts_alike(nested, (0.0, 0.0, 40.0, 80.0), scale, "nested at \{scale}")
    round_cuts_alike(across, (0.0, 0.0, 50.0, 50.0), scale, "across at \{scale}")
    // (smaller than a press's room: reached from round it, within the round corner cutting it)
    round_cuts_alike(one, (2.0, 2.0, 10.0, 10.0), scale, "small in a corner at \{scale}")
  }
}

///|
test "a node's round clip as painted against an old view's: a still pointer at its corner over it as its corners go square, not as they are round again, alike" {
  let cuts = [{ x: 20.0, y: 20.0, w: 80.0, h: 40.0, r: 12.0 }]
  let target = (0.0, 0.0, 80.0, 40.0)
  // (outside the round corner, within its rect: tl corner's curve crosses the diagonal at about 23.26)
  let (px, py) = (21.5, 21.5)
  let radius = @signals.signal(12.0, same=fn(a, b) { a == b })
  let id = Ref(0)
  let lit = Ref(false)
  let t = Tester::new(round_cuts_old(cuts, target, id, lit, Some(radius)), w=160.0, h=160.0, platform=0)
  t.draw()
  t.move(px, py)
  t.draw()
  t.draw()
  let old_round = lit.val
  radius.set(0.0)
  t.draw()
  t.draw()
  let old_square = lit.val
  radius.set(12.0)
  let node : Ref[@view.View?] = Ref(None)
  let t2 = Tester::new(fn(_c) {  }, w=160.0, h=160.0, platform=0)
  set_view_app(round_cuts_tree(cuts, target, node, Some(radius)))
  t2.draw()
  t2.frame()
  t2.move(px, py)
  t2.frame()
  let n = node.val.unwrap()
  let tree_round = n.pointed()
  t2.record_host()
  radius.set(0.0)
  t2.frame_at(t2.next_frame_time())
  let tree_square = n.pointed()
  radius.set(12.0)
  t2.frame_at(t2.next_frame_time())
  let tree_round_again = n.pointed()
  assert_eq((old_round, old_square), (false, true))
  assert_eq((tree_round, tree_square, tree_round_again), (old_round, old_square, old_round))
}
