// Stream's frames let go here, against the frame that takes them (stream.mbt Stream::let_go).

///|
let wb_avcc : Bytes = b"\x01\x42\xc0\x1f\xff\xe1\x00\x06\x67\x42\xc0\x1f\xda\x01\x01\x00\x04\x68\xce\x3c\x80"

///|
test "a frame let go in a frame that took its events already: the next frame is owed, takes it and says it shown" {
  let cell : Ref[Stream?] = Ref::new(None)
  let feed : Ref[Bool] = Ref::new(false)
  let t = Tester::new(
    fn(c) {
      match cell.val {
        Some(s) => {
          c.stream(s, h=Px(200.0)) |> ignore
          if feed.val {
            feed.val = false
            // handed over while the frame builds, its events taken as it began: before any key frame, let go here
            s.frame(b"\x00\x00\x00\x01\x41", false, 7.0)
          }
        }
        None => ()
      }
    },
    h264=true,
  )
  let acks = []
  let s = Stream::new(shown=fn(ts) { acks.push(ts) }, broken=fn() {  })
  cell.val = Some(s)
  s.h264(wb_avcc, 640, 360)
  t.draw()
  feed.val = true
  // one frame only: the one that lets it go
  t.frame()
  assert_eq(acks, [])
  assert_false(t.at_rest())
  // the next is owed (else none would come and the frame would stay out for good)
  assert_true(t.owed_now())
  // drawn, it takes the "d" and says it shown once painted
  t.draw()
  assert_eq(acks, [7.0])
  assert_true(t.at_rest(), msg=t.rest_why())
  s.close()
}
