// The keys of a bar for what goes on by itself as nodes (sync_key_node.mbt).

///|
/// A sync key node said by `syncing`, in a Tester; whether it is read out (its Status) at each moment asked.
fn sync_key_tester(syncing : @signals.Signal[String?]) -> @ui.Tester {
  let t = @ui.Tester::new(fn(_c) {  }, w=200.0, h=100.0)
  @ui.set_view_app(fn(root) {
    let tips = TipLayer::new(fn() { Some(root) })
    root.box(fn(b) {
      b.row(Is(true)) |> ignore
      sync_key_node(b, tips, 34.0, 20.0, fn() { syncing.get() })
    })
    |> ignore
  })
  t.draw()
  t
}

///|
fn sync_key_said(t : @ui.Tester, words : String) -> Bool {
  t.query(Status, label=words) is Some(_)
}

///|
test "sync key node: a moment's catching up shows nothing; once it has gone on, it turns; all here, it ticks, stands, then goes" {
  let syncing = @signals.signal(Some("正在同步 · 还剩 3 个对话"))
  let t = sync_key_tester(syncing)
  let words = "正在同步 · 还剩 3 个对话"
  // (not yet: nothing laid out or read out)
  let at_first = sync_key_said(t, words)
  t.run_for(later_ms + @kit.presence_in_ms)
  let after_wait = sync_key_said(t, words)
  // (turning by the clock: drawn otherwise a quarter turn on)
  let turning_a = t.drawn_instances_keyed()
  t.run_for(sync_turn_ms / 4.0)
  let turning_b = t.drawn_instances_keyed()
  syncing.set(None)
  t.draw()
  // (all here: still there, ticking, under the words it said last)
  let ticking = sync_key_said(t, words)
  t.run_for(sync_settle_most + sync_back_ms + sync_tick_ms + sync_done_ms / 2.0)
  let standing = sync_key_said(t, words)
  t.run_for(sync_done_ms / 2.0 + sync_out_ms)
  let gone = sync_key_said(t, words)
  assert_eq((at_first, after_wait, turning_a != turning_b, ticking, standing, gone), (false, true, true, true, true, false))
}

///|
test "sync key node: catching up ended before it showed, nothing; begun again, it waits its moment again" {
  let syncing = @signals.signal(Some("正在同步"))
  let t = sync_key_tester(syncing)
  t.run_for(later_ms / 2.0)
  syncing.set(None)
  t.draw()
  t.run_for(later_ms + sync_done_ms)
  let never = sync_key_said(t, "正在同步")
  syncing.set(Some("正在同步"))
  t.draw()
  t.run_for(later_ms / 2.0)
  let half = sync_key_said(t, "正在同步")
  t.run_for(later_ms / 2.0 + @kit.presence_in_ms)
  assert_eq((never, half, sync_key_said(t, "正在同步")), (false, false, true))
}
