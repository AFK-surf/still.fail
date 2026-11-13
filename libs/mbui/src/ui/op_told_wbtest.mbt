// How a run of the password manager's `op` ended, and the login the system's autofill gave, are taken as the host's
// word says they came (hostcall.mbt's outside_take, kinds outside_op and outside_autofill), into signals what waits on
// them reads (@hostapi.OpRun::done, @hostapi.autofill_take): a node's binding or `reacts` told at that moment, at any
// frame rate; while it waits, nothing of it asks for a frame, nothing is built again (they were read as the clock is,
// @hostapi.polled: what read them was built again each frame). The host's word is said here as a host says it
// (on_outside, between frames), what it keeps given it the moment before.

///|
/// How long the test runs before it asks (any while), and between what it does (past what a frame drawn for the last
/// needs, at the slowest rate).
let op_before : Double = 100.0

///|
let op_between : Double = 400.0

///|
/// While it waits: at rest (no frame asked between frames, nothing moving, no wake: no ticket is held for these),
/// nothing for the clock, no frame drawn but the one run_for draws at its end (tester_time.mbt's run_for: its last
/// `frame_at` is the end's; on its way it draws one only as the app asks, Tester::asks_frames, or as something is due).
fn op_waits_quietly(t : Tester) -> Unit raise {
  assert_true(t.at_rest(), msg=t.rest_why())
  let on = t.frames_on()
  let drawn = t.ctx().frame_no
  t.run_for(op_between)
  assert_eq(t.ctx().frame_no, drawn + 1)
  assert_true(t.at_rest(), msg=t.rest_why())
  assert_eq(t.frames_on(), on)
}

///|
test "a run of op: what reads how it ended told at the moment the host's word says it did, at any rate; nothing while it runs" {
  let run : @signals.Signal[@hostapi.OpRun?] = @signals.signal(None)
  let told : Array[(Int, Double)] = []
  let t = Tester::new(fn(_c) {  })
  fake_op.val = Some(fn(_) { (0, "[]", "") })
  fake_op_pending.val = true
  set_view_app(fn(root) {
    root.box(fn(n) {
      n
      .words(By(fn() {
        match run.get().map(fn(r) { r.done() }) {
          Some(Some(d)) => "ended \{d.code}"
          _ => "running"
        }
      }))
      |> ignore
      n.reacts(fn() { run.get().map(fn(r) { r.done().map(fn(d) { d.code }) }) }, fn(c) {
        match c {
          Some(Some(code)) => told.push((code, n.cause_at()))
          _ => ()
        }
      })
    })
    |> ignore
  })
  t.run_for(op_before)
  run.set(@hostapi.op_run(["item", "list"]))
  t.run_for(op_before)
  assert_true(t.find("running") is Some(_))
  op_waits_quietly(t)
  // it ends: the host's word, now
  fake_op_pending.val = false
  let came = t.time()
  on_outside(outside_op, 1, 1)
  t.run_for(op_between)
  assert_eq(told, [(0, came)])
  assert_true(t.find("ended 0") is Some(_))
  // read again, the same; nothing told again
  assert_eq(run.get().unwrap().done().map(fn(d) { d.out }), Some("[]"))
  on_outside(outside_op, 1, 1)
  t.run_for(op_between)
  assert_eq(told.length(), 1)
  op_waits_quietly(t)
}

///|
test "a run of op ended by the app: a word the host says of it after is nothing" {
  let t = Tester::new(fn(_c) {  })
  fake_op.val = Some(fn(_) { (0, "[]", "") })
  fake_op_pending.val = true
  t.run_for(op_before)
  let r = @hostapi.op_run(["item", "list"]).unwrap()
  r.end()
  fake_op_pending.val = false
  on_outside(outside_op, 1, 1)
  t.run_for(op_between)
  assert_true(r.done() is None)
}

///|
test "the autofill's login: what reads it told at the moment the host's word says the person picked one, once; let go, none" {
  let told : Array[(String, Double)] = []
  let t = Tester::new(fn(_c) {  })
  fake_autofill.val = true
  set_view_app(fn(root) {
    root.box(fn(n) {
      n
      .words(By(fn() {
        match @hostapi.autofill_take() {
          Some((_, user, _)) => "picked " + user
          None => "offered"
        }
      }))
      |> ignore
      n.reacts(fn() { @hostapi.autofill_take().map(fn(l) { l.1 }) }, fn(u) {
        match u {
          Some(user) => told.push((user, n.cause_at()))
          None => ()
        }
      })
    })
    |> ignore
  })
  t.run_for(op_before)
  assert_true(@hostapi.autofill_ask("github.com"))
  t.run_for(op_before)
  assert_true(t.find("offered") is Some(_))
  op_waits_quietly(t)
  // the person picks a login: the host's word, now
  fake_autofill_picks("github.com", "mona", "secret")
  let came = t.time()
  on_outside(outside_autofill, 1, 1)
  t.run_for(op_between)
  assert_eq(told, [("mona", came)])
  assert_true(t.find("picked mona") is Some(_))
  // picked again in the same offer: that one, at its moment
  fake_autofill_picks("github.com", "octo", "secret2")
  let again = t.time()
  on_outside(outside_autofill, 1, 1)
  t.run_for(op_between)
  assert_eq(told, [("mona", came), ("octo", again)])
  // let go of: none, the host's offer withdrawn
  @hostapi.autofill_end()
  t.run_for(op_between)
  assert_eq(@hostapi.autofill_take(), None)
  assert_true(t.find("offered") is Some(_))
  assert_eq(fake_autofill_asks, ["github.com", ""])
  op_waits_quietly(t)
}
