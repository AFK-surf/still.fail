// A flat stack's pages made once as nodes of the tree's (nav_flat_view's `made`) under what the frame puts over each
// (`head`), its owner keeping the one shown while the one put in its place waits (page_wait.mbt's): which way each is
// drawn decided as the stack stands whole, never the half between a change and its owner's keeping; the page kept made
// once, its head and its page the same nodes, let go once as the other shows.

///|
/// What a made stack did: the pages made (by what each was as made), those let go, the heads made and let go.
priv struct FlatMadeLog {
  made : Array[String]
  /// the entry each made page was told it is (its fifth argument), as made
  serials : Array[Int]
  dropped : Array[String]
  heads : Array[Int]
  heads_dropped : Array[Int]
  left : Array[String]
}

///|
/// A stack drawn flat, its pages "a", "b" made once (words: the page's name), "x" its old view; each under a head 30
/// tall of the tree's; with an owner as the panes', said before the stack's node or after it (`owner_first`). The
/// stack, the readiness, what was done.
fn flat_made(owner_first : Bool) -> (Tester, Nav[String], @signals.Signal[Bool], FlatMadeLog) {
  let log : FlatMadeLog = { made: [], serials: [], dropped: [], heads: [], heads_dropped: [], left: [] }
  // (what each entry's page said of itself, by the entry: its head says it)
  let said : Map[Int, @signals.Signal[String]] = Map([])
  let said_of = fn(k : Int) {
    match said.get(k) {
      Some(s) => s
      None => {
        let s = @signals.signal("")
        said[k] = s
        s
      }
    }
  }
  let nav = Nav::new("a", on_leave=fn(p) { log.left.push(p) })
  let ready = @signals.signal(true)
  let t = Tester::new(fn(_c) {  }, w=390.0, h=600.0)
  set_view_app(fn(root) {
    let owner = fn() {
      nav.flat_owned(true)
      let shown = Ref(@signals.untracked(fn() { nav.top_stay() }))
      root.reacts(fn() { nav.top_stay() }, fn(stay) {
        if stay == shown.val {
          return
        }
        if ready.untracked() {
          shown.val = stay
          nav.flat_keep(None)
        } else {
          nav.flat_keep(Some(shown.val))
        }
      })
      root.reacts(fn() { (nav.top_stay(), ready.get()) }, fn(now) {
        if now.1 && now.0 != shown.val {
          shown.val = now.0
          nav.flat_keep(None)
        }
      })
    }
    if owner_first {
      owner()
    }
    nav_flat_view(
      root,
      nav,
      fn(c, p) { c.text(p, size=12.0) |> ignore },
      fn(_) { true },
      0.0,
      head=fn(b, k, _) {
        log.heads.push(k)
        b.box(fn(h) { h.height(Is(Some(30.0))).words(By(fn() { "head " + said_of(k).get() })) |> ignore }) |> ignore
        b.owns(fn() { log.heads_dropped.push(k) }) |> ignore
      },
      made=fn(p) {
        if p == "x" {
          return None
        }
        Some(
          (
            "page",
            fn(v, page, _under, _stint, k) {
              let name = @signals.untracked(page)
              log.made.push(name)
              log.serials.push(k)
              // (what it says of itself, kept by its entry)
              said_of(k).set(name)
              v.box(fn(w) { w.words(By(fn() { page() })) |> ignore }) |> ignore
              v.owns(fn() { log.dropped.push(name) }) |> ignore
            },
          ),
        )
      },
    )
    |> ignore
    if !owner_first {
      owner()
    }
  })
  t.draw()
  (t, nav, ready, log)
}

///|
/// The tree's own nodes drawing `words` now: each one's id.
fn flat_made_nodes(words : String) -> Array[@view.NodeId] {
  view_tree().unwrap().drawn().filter(fn(d) { !d.hosted && d.words == words && d.alpha > 0.0 }).map(fn(d) { d.id })
}

///|
test "a flat stack's made pages: the one shown kept, its page and head the same nodes, as the one put in its place waits, its owner said before or after the stack; let go once as the other shows" {
  for owner_first in [false, true] {
    let (t, nav, ready, log) = flat_made(owner_first)
    let page = flat_made_nodes("a")
    let head = flat_made_nodes("head a")
    assert_eq((page.length(), head.length()), (1, 1), msg="\{owner_first}")
    assert_eq((log.made, log.heads.length()), (["a"], 1), msg="\{owner_first}")
    // (the entry it was told it is, the head's the same)
    assert_eq(log.serials, [log.heads[0]], msg="\{owner_first}")
    ready.set(false)
    nav.replace("b")
    t.draw()
    // (kept: the same nodes, nothing made or let go)
    assert_eq(flat_made_nodes("a"), page, msg="\{owner_first}")
    // (its head still what it said of itself, the one put in its place not shown)
    assert_eq(flat_made_nodes("head a"), head, msg="\{owner_first}")
    assert_eq(flat_made_nodes("head b"), [], msg="\{owner_first}")
    assert_eq((log.made, log.dropped, log.heads.length(), log.heads_dropped, log.left), (["a"], [], 1, [], []), msg="\{owner_first}")
    // (it shows what it waited for: the other made, the one kept let go once)
    ready.set(true)
    t.draw()
    assert_eq(flat_made_nodes("b").length(), 1, msg="\{owner_first}")
    assert_eq(flat_made_nodes("a"), [], msg="\{owner_first}")
    assert_eq(flat_made_nodes("head b").length(), 1, msg="\{owner_first}")
    assert_eq(log.serials.length(), 2, msg="\{owner_first}")
    assert_eq(log.serials[1], log.heads[1], msg="\{owner_first}")
    assert_eq((log.made, log.dropped, log.left), (["a", "b"], ["a"], ["a"]), msg="\{owner_first}")
    assert_eq((log.heads.length(), log.heads_dropped.length()), (2, 1), msg="\{owner_first}")
    t.draw()
    assert_eq((log.made, log.dropped, log.left), (["a", "b"], ["a"], ["a"]), msg="\{owner_first}")
  }
}

///|
test "a flat stack's made page become one drawn by its old view: drawn so, the made one let go once; become one made again: made anew" {
  let (t, nav, _, log) = flat_made(false)
  nav.become("x")
  t.draw()
  assert_eq(log.dropped, ["a"])
  assert_true(t.find("x") is Some(_))
  nav.become("b")
  t.draw()
  assert_eq(log.made, ["a", "b"])
  assert_eq(flat_made_nodes("b").length(), 1)
}

///|
test "a flat stack's made page under its head: what it holds in the room left under the head, cut to it; the stack's back over both" {
  let (t, nav, _, _) = flat_made(false)
  nav.push("b")
  t.draw()
  nav.push_over("c")
  t.draw()
  t.run_for(move_ms(390.0) * 2.0)
  let head = view_tree().unwrap().drawn().filter(fn(d) { d.words == "head c" && d.alpha > 0.0 })
  let page = view_tree().unwrap().drawn().filter(fn(d) { d.words == "c" })
  assert_eq((head.length(), page.length()), (1, 1))
  assert_true(page[0].y >= head[0].y + 30.0, msg="page at \{page[0].y}, head at \{head[0].y}")
  // (back from the head's edge: off)
  t.drag(4.0, head[0].y + 10.0, 300.0, head[0].y + 10.0)
  t.run_for(move_ms(390.0) * 2.0)
  assert_eq(nav.pages(), ["a", "b"])
}

///|
test "a flat stack's page made or drawn by its old view as what `made` reads says, the stack told nothing: each way as it comes, the same way kept, not made again" {
  let width = @signals.signal(400.0)
  let built : Array[String] = []
  let nav = Nav::new("a")
  let t = Tester::new(fn(_c) {  }, w=390.0, h=600.0)
  set_view_app(fn(root) {
    nav_flat_view(root, nav, fn(c, p) { c.text("old " + p, size=12.0) |> ignore }, fn(_) { true }, 0.0, made=fn(_) {
      // (made where it is narrow, none where its width is not known yet)
      let w = width.get()
      if w <= 0.0 || w >= 640.0 {
        return None
      }
      Some(
        (
          "page",
          fn(v, page, _under, _stint, _k) {
            built.push(@signals.untracked(page))
            v.box(fn(n) { n.words(By(fn() { page() })) |> ignore }) |> ignore
          },
        ),
      )
    })
    |> ignore
  })
  t.draw()
  assert_eq((built, flat_made_nodes("a").length()), (["a"], 1))
  // (as narrow: kept)
  width.set(500.0)
  t.draw()
  assert_eq((built, flat_made_nodes("a").length()), (["a"], 1))
  // (wide: its old view; not known: its old view too)
  width.set(700.0)
  t.draw()
  assert_eq(flat_made_nodes("a"), [])
  assert_true(t.find("old a") is Some(_))
  width.set(0.0)
  t.draw()
  assert_eq(built, ["a"])
  assert_true(t.find("old a") is Some(_))
  // (narrow again: made anew)
  width.set(400.0)
  t.draw()
  assert_eq((built, flat_made_nodes("a").length()), (["a", "a"], 1))
}
