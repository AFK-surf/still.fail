// The keyboard as actions (keymap.mbt): a key matched from where the focus is outwards, the innermost first, its
// contexts the chain's; a sequence of keys under way ends by a cause alone, said as it ends.

///|
fn km(bindings : Array[(Array[(Int, Int)], String, String)], pending_ms? : Double? = None) -> @view.Keymap {
  @view.Keymap::new(
    bindings.map(fn(b) {
      {
        keys: b.0.map(fn(k) { { code: k.0, mods: k.1 } }),
        action: b.1,
        when: @view.KeyWhen::parse(b.2).unwrap(),
      }
    }),
    pending_ms~,
  )
}

///|
test "keymap: a context's predicate as written" {
  assert_eq(@view.KeyWhen::parse(""), Some(Always))
  assert_eq(@view.KeyWhen::parse("Chat && !Field"), Some(All([In("Chat"), Not(In("Field"))])))
  assert_eq(
    @view.KeyWhen::parse("!Field || FieldEmpty && Chat"),
    Some(Any([Not(In("Field")), All([In("FieldEmpty"), In("Chat")])])),
  )
  assert_eq(@view.KeyWhen::parse("(A || B) && C"), Some(All([Any([In("A"), In("B")]), In("C")])))
  assert_eq(@view.KeyWhen::parse("A &&"), None)
  assert_eq(@view.KeyWhen::parse("A B"), None)
}

///|
test "keymap: from the focus outwards, the innermost first; false passes it on; its contexts the chain's, with the key's facts; none focused, every node that does it, the one drawn last first" {
  let told : Array[String] = []
  let inner : Ref[@view.View?] = Ref(None)
  let t = @view.Tree::new(
    fn(root) {
      root
      .keymap(Is(km([([(11, 8)], "find", "Chat"), ([(12, 8)], "new", ""), ([(32, 0)], "focus", "!Field")])))
      .on_action("new", fn(_) {
        told.push("root new")
        true
      })
      .on_action("focus", fn(_) {
        told.push("root focus")
        true
      })
      |> ignore
      root.box(fn(chat) {
        chat
        .key_context("Chat")
        .on_action("find", fn(a) {
          told.push("chat find \{a.keys.length()}")
          true
        })
        .on_action("new", fn(_) {
          told.push("chat new passed")
          false
        })
        |> ignore
        chat.box(fn(f) {
          f.focusable(Is(true)) |> ignore
          inner.val = Some(f)
        })
        |> ignore
      })
      |> ignore
      // (beside the chat, not holding the focus: no Chat context of its own)
      root.box(fn(side) {
        side.on_action("find", fn(_) {
          told.push("side find")
          true
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  let from = Some(inner.val.unwrap().id())
  assert_eq(t.stroke(11, 8, 10.0, from~), true)
  assert_eq(t.stroke(12, 8, 20.0, from~), true)
  assert_eq(t.stroke(32, 0, 30.0, from~, facts=["Field"]), false)
  assert_eq(t.stroke(32, 0, 40.0, from~), true)
  // (none focused: the chat's find in its chain still; the side's never, no Chat there)
  assert_eq(t.stroke(11, 8, 50.0), true)
  assert_eq(told.copy(), ["chat find 1", "chat new passed", "root new", "root focus", "chat find 1"])
  // asked by name: the first that does it, no binding asked for; the keys a menu shows
  told.clear()
  assert_eq(t.ask_action("new", 60.0, from~), true)
  assert_eq(told.copy(), ["chat new passed", "root new"])
  assert_eq(t.keys_for("find", from~), [[{ code: 11, mods: 8 }]])
  assert_eq(t.keys_for("focus", from~, facts=["Field"]), [])
  assert_eq(t.actions_here(from~), ["find", "new", "focus"])
}

///|
test "keymap: a sequence under way ends by its cause, said: done, a key that goes on with none (that one matched alone then, no sequence of its own), Escape, the keymap changed, the focus moved" {
  let told : Array[String] = []
  let map = @signals.signal(
    km([([(11, 8), (3, 0)], "left", ""), ([(11, 8), (4, 0)], "right", ""), ([(5, 0)], "up", "")]),
  )
  let a : Ref[@view.View?] = Ref(None)
  let b : Ref[@view.View?] = Ref(None)
  let t = @view.Tree::new(
    fn(root) {
      root.keymap(By(fn() { map.get() })) |> ignore
      for name in ["left", "right", "up"] {
        root.on_action(name, fn(_) {
          told.push(name)
          true
        })
        |> ignore
      }
      root.box(fn(v) { a.val = Some(v.focusable(Is(true))) }) |> ignore
      root.box(fn(v) { b.val = Some(v.focusable(Is(true))) }) |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  assert_eq(t.keys_ended(), NotYet)
  assert_eq(t.stroke(11, 8, 10.0), true)
  assert_eq(t.keys_pending(), [{ code: 11, mods: 8 }])
  assert_eq(t.stroke(3, 0, 11.0), true)
  assert_eq(t.keys_ended(), Done("left"))
  assert_eq(t.keys_pending(), [])
  // (one that goes on with none: ended so, and the key alone done)
  assert_eq(t.stroke(11, 8, 20.0), true)
  assert_eq(t.stroke(5, 0, 21.0), true)
  assert_eq(t.keys_ended(), Unmatched)
  assert_eq(told.copy(), ["left", "up"])
  assert_eq(t.stroke(11, 8, 30.0), true)
  assert_eq(t.stroke(6, 0, 31.0), false)
  assert_eq(t.keys_ended(), Unmatched)
  assert_eq(t.stroke(11, 8, 40.0), true)
  assert_eq(t.stroke(17, 0, 41.0), true)
  assert_eq(t.keys_ended(), Cancelled)
  assert_eq(t.stroke(11, 8, 50.0), true)
  map.set(km([([(11, 8), (3, 0)], "left", "")]))
  t.frame(390.0, 844.0, now=51.0) |> ignore
  assert_eq(t.keys_ended(), KeymapChanged)
  assert_eq(t.keys_pending(), [])
  // (begun from one focus, the next key from another)
  let from_a = Some(a.val.unwrap().id())
  assert_eq(t.stroke(11, 8, 60.0, from=from_a), true)
  assert_eq(t.stroke(3, 0, 61.0, from=Some(b.val.unwrap().id())), false)
  assert_eq(t.keys_ended(), FocusMoved)
  // (and the tree's own focus moved meanwhile)
  assert_eq(t.stroke(11, 8, 70.0, from=from_a), true)
  t.focus_to(Some(b.val.unwrap().id())) |> ignore
  assert_eq(t.keys_ended(), FocusMoved)
  assert_eq(told.copy(), ["left", "up"])
}

///|
/// How long a sequence under way waits for its next key in the test of its time out, and the moments it is asked at:
/// long past the first one's end, and a second begun after it.
let keys_wait_ms : Double = 1000.0

///|
let keys_long_past_at : Double = 5000.0

///|
let keys_again_at : Double = 6000.0

///|
test "keymap: a sequence's time out is a moment declared from its first key's, on the tree's timeline, whatever frames are drawn" {
  let told : Array[String] = []
  let t = @view.Tree::new(
    fn(root) {
      root.keymap(Is(km([([(11, 8), (3, 0)], "left", "")], pending_ms=Some(keys_wait_ms)))).on_action("left", fn(_) {
        told.push("left")
        true
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  assert_eq(t.stroke(11, 8, 100.0), true)
  // (in one jump past its end: ended at its moment, the key after it alone)
  t.advance(keys_long_past_at)
  assert_eq(t.keys_ended(), TimedOut)
  assert_eq(t.stroke(3, 0, keys_long_past_at), false)
  // (before its end: done)
  assert_eq(t.stroke(11, 8, keys_again_at), true)
  assert_eq(t.stroke(3, 0, keys_again_at + keys_wait_ms - 1.0), true)
  assert_eq(t.keys_ended(), Done("left"))
  t.advance(keys_again_at + keys_wait_ms * 3.0)
  assert_eq(t.keys_ended(), Done("left"))
  assert_eq(told.copy(), ["left"])
}

///|
test "keymap: a node let go does nothing of what it said; under a modal layer that does not hold it, nothing" {
  let there = @signals.signal(true, same=fn(a, b) { a == b })
  let modal = @signals.signal(false, same=fn(a, b) { a == b })
  let told : Array[String] = []
  let t = @view.Tree::new(
    fn(root) {
      root.keymap(Is(km([([(12, 8)], "new", "")]))) |> ignore
      root.show(fn() { there.get() }, fn(v) {
        v.on_action("new", fn(_) {
          told.push("new")
          true
        })
        |> ignore
      })
      root.show(fn() { modal.get() }, fn(m) { m.modal(Is(true)) |> ignore })
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  assert_eq(t.stroke(12, 8, 10.0), true)
  modal.set(true)
  t.frame(390.0, 844.0, now=15.0) |> ignore
  assert_eq(t.stroke(12, 8, 20.0), false)
  modal.set(false)
  there.set(false)
  t.frame(390.0, 844.0, now=25.0) |> ignore
  assert_eq(t.stroke(12, 8, 30.0), false)
  assert_eq(told.copy(), ["new"])
}
