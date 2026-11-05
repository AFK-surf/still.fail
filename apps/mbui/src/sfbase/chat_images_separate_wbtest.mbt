///|
test "a picture coming and arriving tells only what follows that picture" {
  let images = ChatImages::new()
  let heard_b : Ref[(Json) -> Unit] = Ref(fn(_) {  })
  let done_b : Ref[(Result[(Json, Bytes?), Json]) -> Unit] = Ref(fn(_) {  })
  let reads_a = Ref(0)
  let reads_b = Ref(0)
  let off_a = @signals.effect(fn() {
    images.get("s", "a", "mem:a", fn(_, _) {  }) |> ignore
    images.coming("a") |> ignore
    images.held("a") |> ignore
    reads_a.val += 1
  })
  let off_b = @signals.effect(fn() {
    images.get("s", "b", "mem:b", fn(h, done) { heard_b.val = h; done_b.val = done }) |> ignore
    images.coming("b") |> ignore
    images.held("b") |> ignore
    reads_b.val += 1
  })
  assert_eq((reads_a.val, reads_b.val), (1, 1))
  (heard_b.val)({ "loaded": 5.0, "total": 10.0 })
  assert_eq(images.coming("b"), Some((5.0, Some(10.0))))
  assert_eq((reads_a.val, reads_b.val), (1, 2), msg="b's progress must not work out a again")
  (done_b.val)(Ok(({ "held": true }, Some(b"picture"))))
  assert_true(images.held("b"))
  assert_eq(images.coming("b"), None)
  assert_eq((reads_a.val, reads_b.val), (1, 3), msg="b arriving must not work out a again")
  off_a()
  off_b()
}

///|
test "retrying a station's failed pictures tells only those pictures" {
  let images = ChatImages::new()
  images.get("station-a", "a", "mem:a", fn(_, done) { done(Err({ "code": "mesh" })) }) |> ignore
  images.get("station-b", "b", "mem:b", fn(_, done) { done(Err({ "code": "mesh" })) }) |> ignore
  let (reads_a, reads_b) = (Ref(0), Ref(0))
  let off_a = @signals.effect(fn() { images.unreached("a") |> ignore; reads_a.val += 1 })
  let off_b = @signals.effect(fn() { images.unreached("b") |> ignore; reads_b.val += 1 })
  assert_true(images.unreached("a") && images.unreached("b"))
  images.again("station-a")
  assert_false(images.unreached("a"))
  assert_true(images.unreached("b"))
  assert_eq((reads_a.val, reads_b.val), (2, 1))
  off_a()
  off_b()
}
