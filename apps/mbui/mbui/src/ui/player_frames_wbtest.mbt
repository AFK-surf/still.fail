// A player playing moves on with its own clock, its picture shown by its host whether the app draws or not (Android's
// pictureFrame draws its frames with the app not asked): where it is is the host's to say as it changes, each frame of
// its picture (native.mbt's views_arrive, hostcall.mbt's outside_stood), and the app draws each, whatever frames came
// between (frames of its looks alone among them). The app asks for no frame of its own for it and reads nothing of the
// host while the host says nothing (it once read each frame, and asked for the next only after a frame it painted, so
// that a frame of its looks alone asked for none: the time shown stood still while the picture played on).

///|
test "a player playing: read only as its host says it moved, each time drawn, frames of the looks alone between" {
  let cell : Ref[NativeView?] = { val: None }
  let t = Tester::new(
    fn(c) {
      let v = match cell.val {
        Some(v) => v
        None => {
          let v = NativeView::video("video/mp4", fn(_o, _l, answer) {
            answer(b"", -1.0, false)
            fn() {  }
          })
          cell.val = Some(v)
          v
        }
      }
      c.box(w=Fill(1.0), h=Fill(1.0), fn() {
        c.native(v, h=Px(120.0)) |> ignore
        c.text("at \{(v.position() / 1000.0).to_int()} s", wrap=false) |> ignore
      })
      |> ignore
    },
    w=300.0,
    h=300.0,
  )
  t.draw()
  let v = cell.val.unwrap()
  t.fake.wants = false
  t.set_player(v.id(), duration=60000.0, position=1000.0, playing=true, shown=true)
  assert_true(t.fake.wants, msg="the host's word asks for a frame")
  t.draw()
  assert_true(t.find("at 1 s") is Some(_))
  // (as a host draws it: no frame drawn whole after each to compare)
  t.check_looks(false)
  // the host says nothing: nothing read of it, whatever frames come
  let reads = t.fake.view_reads
  t.clock_frame()
  t.clock_frame()
  assert_eq(t.fake.view_reads, reads)
  // a frame of its picture shown: where it is said, a frame asked for by it, and the time shown with it
  t.fake.wants = false
  t.set_player(v.id(), position=2000.0)
  assert_true(t.fake.wants, msg="the host's word asks for a frame")
  t.clock_frame()
  assert_true(t.find("at 2 s") is Some(_))
  assert_eq(t.fake.view_reads, reads + 1)
}
