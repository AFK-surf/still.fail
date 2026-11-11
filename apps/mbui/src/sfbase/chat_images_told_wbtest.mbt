// A chat's pictures read by nodes (chat_images.mbt's `*_told` reads): what reads one is told as that one changes, and
// nothing else is.

///|
test "how far a picture has come, a step of it: what reads that picture told, what reads another not" {
  let images = ChatImages::new()
  let heard : Map[String, (Json) -> Unit] = Map([])
  let ask = fn(id : String) {
    images.get("st", id, "mem:t/" + id, fn(h, _) { heard[id] = h }) |> ignore
  }
  ask("a")
  ask("b")
  let runs_a = Ref(0)
  let runs_b = Ref(0)
  let stop_a = @signals.effect(fn() {
    images.coming_told("a") |> ignore
    runs_a.val += 1
  })
  let stop_b = @signals.effect(fn() {
    images.coming_told("b") |> ignore
    runs_b.val += 1
  })
  assert_eq((runs_a.val, runs_b.val), (1, 1))
  (heard["a"])({ "loaded": 10, "total": 100 })
  assert_eq((runs_a.val, runs_b.val), (2, 1))
  assert_eq(images.coming("a"), Some((10.0, Some(100.0))))
  (heard["a"])({ "loaded": 20, "total": 100 })
  assert_eq((runs_a.val, runs_b.val), (3, 1))
  (heard["b"])({ "loaded": 5 })
  assert_eq((runs_a.val, runs_b.val), (3, 2))
  stop_a()
  stop_b()
}

///|
test "a picture's answer, failed or here, and asked again: what reads it told each time; none made for what reads nothing" {
  let images = ChatImages::new()
  let done : Map[String, (Result[(Json, Bytes?), Json]) -> Unit] = Map([])
  let ask = fn() { images.get("st", "a", "mem:t/a", fn(_, d) { done["a"] = d }) }
  let runs = Ref(0)
  let seen = Ref(false)
  let stop = @signals.effect(fn() {
    ask() |> ignore
    seen.val = images.unreached_told("a")
    runs.val += 1
  })
  assert_eq(runs.val, 1)
  (done["a"])(Err({ "code": "timeout", "message": "slow" }))
  assert_eq(runs.val, 2)
  assert_true(seen.val)
  // (asked again: told, and asked anew as it is read)
  images.again("st")
  assert_eq(runs.val, 3)
  assert_true(!seen.val)
  stop()
  // (read by nothing now: a change of it tells nothing, and what was made for it is let go)
  (done["a"])(Err({ "code": "timeout", "message": "slow" }))
  assert_eq(runs.val, 3)
  assert_true(images.told.get("a") is None)
  // (the old views' reads make nothing)
  images.unreached("a") |> ignore
  images.coming("a") |> ignore
  assert_true(images.told.is_empty())
}
