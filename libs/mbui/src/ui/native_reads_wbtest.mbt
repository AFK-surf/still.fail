///|
/// A player reads on while no frame comes (the app's window off the screen, Android's GL thread paused: 2026-10-31,
/// a film left playing a quarter of an hour behind another app said 无法播放 on coming back, its reads never taken):
/// the host's word that it waits on the app (outside_view, 0) hands them to its `read` at once.
test "a player's reads are taken as its host says it waits on the app, with no frame coming" {
  let cell : Ref[NativeView?] = { val: None }
  let asked : Array[Double] = []
  let t = Tester::new(fn(c) {
    let v = match cell.val {
      Some(v) => v
      None => {
        let v = NativeView::video("video/mp4", fn(offset, length, answer) {
          asked.push(offset)
          answer(Bytes::make(length, b'\x01'), 100000.0, false)
          fn() {  }
        })
        cell.val = Some(v)
        v
      }
    }
    c.native(v, h=Px(220.0)) |> ignore
  })
  t.draw()
  let v = cell.val.unwrap()
  let r = t.view_reads(v.id(), 8192.0, 4096)
  on_outside(outside_view, v.id(), 0)
  assert_eq(asked, [8192.0])
  assert_eq(t.view_answers(v.id()), [(r, 4096, 100000.0)])
}
