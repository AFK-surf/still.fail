// The keyboard's focus on a node of the window's tree (View::focusable, Tree::focus_to): what can take it in the tree's
// order with what hosts an old view at its place; the one with it and whether it shows told only as that changes; let
// go of, what hosts the tree told so once, at the cause that keeps its node from input.

///|
test "focus: what can take it, in the tree's order with what hosts an old view at its place; one taking no press, or said to take no focus, none of it; one pressed by no key, one all the same" {
  let ids : Map[String, @view.NodeId] = {}
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(a) {
        ids["a"] = a.id()
        a.focusable(Is(true)) |> ignore
        a.box(fn(a1) {
          ids["a1"] = a1.id()
          a1.focusable(Is(true), keys=@view.focus_space) |> ignore
        })
        |> ignore
      })
      |> ignore
      root.hosted(make=fn(h) { ids["h"] = h.id() }) |> ignore
      root.box(fn(off) { off.focusable(Is(true)).presses(Is(false)) |> ignore }) |> ignore
      root.box(fn(no) { no.focusable(Is(false)) |> ignore }) |> ignore
      root.box(fn(k0) {
        ids["k0"] = k0.id()
        k0.focusable(Is(true), keys=0) |> ignore
      })
      |> ignore
      root.box(fn(b) {
        ids["b"] = b.id()
        b.focusable(Is(true)) |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  let both = @view.focus_enter | @view.focus_space
  assert_eq(t.focus_order(), [
    { id: ids["a"], hosted: false, keys: both },
    { id: ids["a1"], hosted: false, keys: @view.focus_space },
    { id: ids["h"], hosted: true, keys: 0 },
    { id: ids["k0"], hosted: false, keys: 0 },
    { id: ids["b"], hosted: false, keys: both },
  ])
}

///|
test "focus: given to a node, it and the one before told, each once, nothing else; shown only where the keyboard gave it; none given to one that cannot take it" {
  let ids : Map[String, @view.NodeId] = {}
  let views : Map[String, @view.View] = {}
  let t = @view.Tree::new(
    fn(root) {
      for k in ["a", "b", "c"] {
        root.box(fn(v) {
          ids[k] = v.id()
          views[k] = v
          v.focusable(Is(k != "c")) |> ignore
        })
        |> ignore
      }
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  let told : Array[String] = []
  let stops = ["a", "b", "c"].map(fn(k) {
    let v = views[k]
    @signals.effect(fn() {
      let f = v.focused()
      let s = v.focus_shown()
      @signals.untracked(fn() { told.push("\{k} \{f} \{s}") })
    })
  })
  told.clear()
  assert_true(t.focus_to(Some(ids["a"]), visible=true))
  assert_eq(told.copy(), ["a true true"])
  told.clear()
  assert_true(t.focus_to(Some(ids["b"])))
  assert_eq(told.copy(), ["a false false", "b true false"])
  told.clear()
  assert_false(t.focus_to(Some(ids["c"])), msg="c takes no focus")
  assert_eq(t.focused_now(), (Some(ids["b"]), false))
  assert_eq(told.copy(), [])
  assert_true(t.focus_to(None))
  assert_eq(told.copy(), ["b false false"])
  for s in stops {
    s()
  }
}

///|
/// A tree of one focusable node under what `show`, `leave`, `presses`, `focus` and a modal layer over it (`modal`)
/// say, the focus given it: what hosts the tree is told of its focus let go, in `lost`.
fn focus_held(
  show : @signals.Signal[Bool],
  presses : @signals.Signal[Bool],
  focus : @signals.Signal[Bool],
  modal : @signals.Signal[Bool],
  leave? : Double = 0.0,
  lost~ : Array[@view.NodeId],
) -> (@view.Tree, @view.NodeId) raise {
  let id : Ref[@view.NodeId?] = Ref(None)
  let t = @view.Tree::new(
    fn(root) {
      root.show(fn() { show.get() }, leave~, fn(v) {
        v.presses(By(fn() { presses.get() })) |> ignore
        v.box(fn(f) {
          id.val = Some(f.id())
          f.focusable(By(fn() { focus.get() })) |> ignore
        })
        |> ignore
      })
      root.box(fn(m) { m.over(Is(true)).modal(By(fn() { modal.get() })) |> ignore }) |> ignore
    },
    time=fn() { 0.0 },
  )
  t.on_focus_lost(fn(n) { lost.push(n) })
  t.frame(390.0, 844.0) |> ignore
  let f = id.val.unwrap()
  assert_true(t.focus_to(Some(f), visible=true))
  (t, f)
}

///|
test "focus: let go of at the cause that keeps its node from input, what hosts the tree told once: the node let go, leaving, said to take no press, said to take no focus, a modal layer over it" {
  let cases = ["let go", "leaving", "no press", "no focus", "modal"]
  for case in cases {
    let show = @signals.signal(true, same=fn(a, b) { a == b })
    let presses = @signals.signal(true, same=fn(a, b) { a == b })
    let focus = @signals.signal(true, same=fn(a, b) { a == b })
    let modal = @signals.signal(false, same=fn(a, b) { a == b })
    let lost : Array[@view.NodeId] = []
    let leave = if case == "leaving" { 200.0 } else { 0.0 }
    let (t, f) = focus_held(show, presses, focus, modal, leave~, lost~)
    // (at the cause's moment, no frame drawn after it)
    t.event(10.0, fn() {
      match case {
        "let go" | "leaving" => show.set(false)
        "no press" => presses.set(false)
        "no focus" => focus.set(false)
        _ => modal.set(true)
      }
    })
    assert_eq(t.focused_now(), (None, false), msg=case)
    assert_eq(lost.copy(), [f], msg=case)
    assert_false(t.focus_to(Some(f)), msg="\{case}: none given it again")
  }
}

///|
test "focus: what holds a node said to take the focus no more keeps nothing from it: the node in it keeps the focus; said to take no press, it is let go of" {
  let outer_focus = @signals.signal(true, same=fn(a, b) { a == b })
  let outer_presses = @signals.signal(true, same=fn(a, b) { a == b })
  let ids : Map[String, @view.NodeId] = {}
  let lost : Array[@view.NodeId] = []
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(o) {
        ids["outer"] = o.id()
        o.focusable(By(fn() { outer_focus.get() })).presses(By(fn() { outer_presses.get() })) |> ignore
        o.box(fn(i) {
          ids["inner"] = i.id()
          i.focusable(Is(true)) |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.on_focus_lost(fn(n) { lost.push(n) })
  t.frame(390.0, 844.0) |> ignore
  assert_true(t.focus_to(Some(ids["inner"]), visible=true))
  t.event(10.0, fn() { outer_focus.set(false) })
  assert_eq(t.focused_now(), (Some(ids["inner"]), true), msg="what holds it takes the focus no more: it keeps it")
  assert_eq(lost.copy(), [])
  t.event(20.0, fn() { outer_presses.set(false) })
  assert_eq(t.focused_now(), (None, false), msg="what holds it takes no press: let go of")
  assert_eq(lost.copy(), [ids["inner"]])
}

///|
test "focus: what holds a node, with the focus, said to take it no more: let go of then" {
  let outer_focus = @signals.signal(true, same=fn(a, b) { a == b })
  let outer : Ref[@view.NodeId?] = Ref(None)
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(o) {
        outer.val = Some(o.id())
        o.focusable(By(fn() { outer_focus.get() })) |> ignore
        o.box(fn(i) { i.focusable(Is(true)) |> ignore }) |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  assert_true(t.focus_to(outer.val))
  t.event(10.0, fn() { outer_focus.set(false) })
  assert_eq(t.focused_now(), (None, false))
}
