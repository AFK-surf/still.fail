// The toaster as the window's tree's nodes (toaster_node): each toast's time from the moment it is given, stopped while
// the pointer is over one of them or the focus on one's action and going on from what was left; one given again by its
// id the same node saying what it says now; going out, moved away by half the toasts' width, not by a finger.

///|
/// What a toaster_node case keeps: the toasts given, whether what holds the toaster is there, what was told gone and
/// acted on (by id), what the first's look last drew of it (how far across, how far in).
struct ToastCase {
  toasts : @signals.Signal[Array[@kit.Toast]]
  holder : @signals.Signal[Bool]
  gone : Array[String]
  acted : Array[String]
  drawn : Ref[(Double, Double)]
}

///|
/// A window 390 by 844 from moment 0, a box at its top taking the focus, and toaster_node's toasts (each 1000 ms,
/// 200 by 40, its action a box 60 by 30 in it), `toasts` given, in a node there while the case's `holder` holds.
fn toast_case(toasts : Array[@kit.Toast]) -> (@ui.Tester, ToastCase) {
  let k : ToastCase = {
    toasts: @signals.signal(toasts, same=fn(a, b) { a == b }),
    holder: @signals.signal(true, same=fn(a, b) { a == b }),
    gone: [],
    acted: [],
    drawn: Ref((0.0, 0.0)),
  }
  let t = @ui.Tester::new(fn(_c) {  }, time=0.0, tree=fn(root : @view.View) {
    root.box(fn(e) {
      e.width(Is(Some(50.0))).height(Is(Some(50.0))).presses(Is(true)).focusable(Is(true)).says(Is(Some(@view.said(Button, label="别处")))) |> ignore
    })
    |> ignore
    root.show(fn() { k.holder.get() }, fn(holder) {
      @kit.toaster_node(
        holder,
        fn() { k.toasts.get() },
        fn(_) { 1000.0 },
        fn() { 24.0 },
        fn(b, s) {
          b.box(fn(x) {
            x
            .row(Is(true))
            .width(Is(Some(200.0)))
            .height(Is(Some(40.0)))
            .drawn_off(By(fn() {
              let d = s.dx()
              if s.toast().id == "a" {
                k.drawn.val = (d, s.t())
              }
              (d, 0.0)
            }))
            |> ignore
            x.show(fn() { s.toast().action != "" }, fn(a) {
              a.width(Is(Some(60.0))).height(Is(Some(30.0))) |> ignore
              s.action(a, fn() { s.toast().action }) |> ignore
            })
          })
          |> ignore
        },
        fn(id) { k.acted.push(id) },
        fn(id) { k.gone.push(id) },
      )
      |> ignore
    })
  })
  t.draw()
  (t, k)
}

///|
/// Where toast `title` is read out (its middle), if it is.
fn toast_at(t : @ui.Tester, title : String) -> (Double, Double)? {
  t.query(Status, label=title).map(fn(s) { (s.rect.0 + 20.0, s.rect.1 + s.rect.3 / 2.0) })
}

///|
/// The window's clock run on to `at`.
fn run_to_time(t : @ui.Tester, at : Double) -> Unit {
  t.run_for(at - t.time())
}

///|
test "a toast given at 0: the pointer over it at 400, still at its due 1000, it stays; let go at 1500, it goes at 2100 (what was left), not before" {
  let (t, k) = toast_case([@kit.toast("a", "一")])
  run_to_time(t, 400.0)
  let (x, y) = toast_at(t, "一").unwrap()
  t.move(x, y)
  run_to_time(t, 1000.0)
  let held = (k.gone.copy(), @kit.toast_due("toast"))
  run_to_time(t, 1500.0)
  t.move(380.0, 400.0)
  let due = @kit.toast_due("toast")
  run_to_time(t, 2099.0)
  let before = k.gone.copy()
  run_to_time(t, 2100.0)
  assert_eq((held, due, before, k.gone), (([], -1.0), 2100.0, [], ["a"]))
}

///|
test "toasts: the focus on one's action and the pointer over it, the pointer gone, still held; the focus gone, its time goes on from what was left" {
  let (t, k) = toast_case([@kit.toast("a", "一", action="做")])
  run_to_time(t, 200.0)
  let (x, y) = toast_at(t, "一").unwrap()
  t.move(x, y)
  run_to_time(t, 300.0)
  // (the focus: the box at the top, then the action)
  t.tab()
  t.tab()
  let focused = t.semantics().iter().any(fn(s) { s.label == "做" && s.focused })
  t.move(380.0, 400.0)
  run_to_time(t, 1500.0)
  let held = k.gone.copy()
  t.tab()
  // (from 200, 800 left)
  run_to_time(t, 2299.0)
  let before = k.gone.copy()
  run_to_time(t, 2300.0)
  assert_eq((focused, held, before, k.gone), (true, [], [], ["a"]))
}

///|
test "toasts: the pointer over one, the focus on its action going away, still held; the pointer gone, its time goes on from what was left" {
  let (t, k) = toast_case([@kit.toast("a", "一", action="做")])
  run_to_time(t, 200.0)
  t.tab()
  t.tab()
  let focused = t.semantics().iter().any(fn(s) { s.label == "做" && s.focused })
  run_to_time(t, 300.0)
  let (x, y) = toast_at(t, "一").unwrap()
  t.move(x, y)
  // (the focus away, to the box at the top)
  t.tab()
  run_to_time(t, 1500.0)
  let held = k.gone.copy()
  t.move(380.0, 400.0)
  // (from 200, 800 left)
  run_to_time(t, 2299.0)
  let before = k.gone.copy()
  run_to_time(t, 2300.0)
  assert_eq((focused, held, before, k.gone), (true, [], [], ["a"]))
}

///|
test "toasts: the pointer over one holds them all; let go, each goes on from what it had left" {
  let (t, k) = toast_case([@kit.toast("a", "一")])
  run_to_time(t, 100.0)
  k.toasts.set([@kit.toast("a", "一"), @kit.toast("b", "二")])
  t.frame()
  run_to_time(t, 300.0)
  let (x, y) = toast_at(t, "一").unwrap()
  t.move(x, y)
  run_to_time(t, 2000.0)
  let held = k.gone.copy()
  t.move(380.0, 400.0)
  // (a: 700 left, b: 800)
  run_to_time(t, 2700.0)
  let first = k.gone.copy()
  run_to_time(t, 2800.0)
  assert_eq((held, first, k.gone), ([], ["a"], ["a", "b"]))
}

///|
test "a toast given again by its id saying other words and an action: the same node, saying them; its action its own" {
  let (t, k) = toast_case([@kit.toast("a", "一")])
  run_to_time(t, 200.0)
  let before = t.query(Status, label="一").map(fn(s) { s.id })
  k.toasts.set([@kit.toast("a", "二", action="做")])
  t.frame()
  let after = t.query(Status, label="二").map(fn(s) { s.id })
  let button = t.query(Button, label="做")
  match button {
    Some(b) => t.tap(b.rect.0 + 30.0, b.rect.1 + 15.0)
    None => ()
  }
  assert_eq((before is Some(_), before == after, button is Some(_), k.acted), (true, true, true, ["a"]))
}

///|
test "a toast going out (no longer given), a finger on it: moved away by half the toasts' width as far as it has gone, not by the finger" {
  let (t, k) = toast_case([@kit.toast("a", "一")])
  run_to_time(t, 200.0)
  let (x, y) = toast_at(t, "一").unwrap()
  t.press_at(x, y)
  t.move(x + 30.0, y)
  let held = k.drawn.val.0
  k.toasts.set([])
  t.frame()
  run_to_time(t, 200.0 + @kit.presence_out_ms / 2.0)
  let (dx, s) = k.drawn.val
  // (the window 390 wide: the toasts 358)
  let away = (1.0 - s) * 358.0 * 0.5
  t.release(x + 30.0, y)
  assert_true(held == 30.0 && s > 0.0 && s < 1.0 && (dx - away).abs() < 1.0e-9, msg="\{held} \{dx} \{s} \{away}")
}

///|
test "a toast going out (no longer given), no finger on it: moved away by half the toasts' width as far as it has gone" {
  let (t, k) = toast_case([@kit.toast("a", "一")])
  run_to_time(t, 200.0)
  k.toasts.set([])
  t.frame()
  run_to_time(t, t.time() + @kit.presence_out_ms / 2.0)
  let (dx, s) = k.drawn.val
  let away = (1.0 - s) * 358.0 * 0.5
  assert_true(s > 0.0 && s < 1.0 && (dx - away).abs() < 1.0e-9, msg="\{dx} \{s} \{away}")
}

///|
test "a toast going out at a moment between whole ms: its way out going on till it is let go, drawn by the clock half a ms before; toast_rest its letting go, then none of it left" {
  let (t, k) = toast_case([@kit.toast("a", "一")])
  run_to_time(t, 200.0)
  // (a moment between whole ms: a display's frame, 60 a second)
  t.run_for(frame_60_ms)
  k.toasts.set([])
  t.frame()
  let rest = @kit.toast_rest("toast")
  // (its way out going on till its letting go, its time from its start in whole ms as its letting go is: half a ms
  // before it, still going)
  let early = t.time() < rest - 0.5
  run_to_time(t, rest - 0.5)
  let between = (@ui.view_tree().unwrap().clock_read(), t.query(Status, label="一") is Some(_))
  run_to_time(t, rest)
  let after = (t.query(Status, label="一") is None, @kit.toast_rest("toast"), t.next_wake())
  assert_eq((early, rest == rest.floor(), between, after), (true, false, (true, true), (true, -1.0, None)), msg="\{rest} \{t.time()}")
}

///|
/// A display's frame at 60 a second: a moment between whole ms from a whole one.
let frame_60_ms : Double = 1000.0 / 60.0

///|
test "a toast coming in, what holds the toaster let go: none of it left, read out, said to move or waited for" {
  let (t, k) = toast_case([@kit.toast("a", "一")])
  run_to_time(t, @kit.presence_in_ms / 2.0)
  let coming = (t.query(Status, label="一") is Some(_), t.rest_of("presence/toast") > t.time())
  k.holder.set(false)
  t.frame()
  assert_eq(
    (coming, t.query(Status, label="一") is None, t.rest_of("presence/toast"), t.next_wake(), t.at_rest(), @kit.toast_rest("toast")),
    ((true, true), true, -1.0, None, true, -1.0),
    msg="\{t.moving()} \{t.rest_why()}",
  )
}

///|
test "the last toast going out, given again by its id with another action: the same node, its new action alone; gone again, none of it left" {
  let (t, k) = toast_case([@kit.toast("a", "一", action="做")])
  run_to_time(t, 200.0)
  let first = t.query(Status, label="一").map(fn(s) { s.id })
  k.toasts.set([])
  t.frame()
  run_to_time(t, t.time() + @kit.presence_out_ms / 2.0)
  k.toasts.set([@kit.toast("a", "一", action="再做")])
  t.frame()
  run_to_time(t, t.time() + @kit.presence_in_ms)
  let back = t.query(Status, label="一").map(fn(s) { s.id })
  let button = (t.query(Button, label="再做") is Some(_), t.query(Button, label="做") is None)
  match t.query(Button, label="再做") {
    Some(b) => t.tap(b.rect.0 + 30.0, b.rect.1 + 15.0)
    None => ()
  }
  let acted = k.acted.copy()
  k.toasts.set([])
  t.frame()
  run_to_time(t, @kit.toast_rest("toast"))
  assert_eq(
    (first is Some(_), back == first, button, acted, t.query(Status, label="一") is None, @kit.toast_rest("toast"), t.next_wake()),
    (true, true, (true, true), ["a"], true, -1.0, None),
  )
}
