// The pictures kept past their budget let go of, least recently drawn first; what is decoded after that known by its own
// number (a host never numbers one anew as one let go of was), told ready as its host says so; the bytes kept what is
// kept adds up to.

///|
/// What the kept decodes' bytes add up to, each counted.
fn kept_bytes() -> Double {
  let mut total = 0.0
  for _, list in image_cache {
    for e in list {
      total = total + e.w * e.h * 4.0
    }
  }
  total
}

///|
test "a picture decoded after one let go of past the budget: its own number, told ready as its host says so; the bytes kept what is kept adds up to" {
  let shown : Ref[Array[String]] = Ref(["a.jpg"])
  let t = Tester::new(
    fn(c) {
      for src in shown.val {
        c.image(src, w=Px(4000.0), h=Px(4000.0)) |> ignore
      }
    },
    images=["a.jpg", "b.jpg", "c.jpg", "d.jpg", "e.jpg", "f.jpg"].map(fn(s) { (s, 8000, 8000) }),
    finish=false,
  )
  let all_done = fn() {
    for p in t.pending() {
      if p.0 == 1 {
        t.finish(1, p.1)
      }
    }
  }
  t.draw()
  all_done()
  t.draw()
  assert_eq(image_state("a.jpg"), 1)
  // (four more, each 4096 square: a, drawn no more, let go of as the five go past the budget)
  shown.val = ["b.jpg", "c.jpg", "d.jpg", "e.jpg"]
  t.draw()
  all_done()
  t.draw()
  t.draw()
  assert_true(!image_cache.contains("a.jpg"), msg="a let go of past the budget")
  assert_eq(image_bytes.val, kept_bytes())
  // (one more: its decode a number none of those kept has)
  shown.val = ["b.jpg", "c.jpg", "d.jpg", "e.jpg", "f.jpg"]
  t.draw()
  let f_id = image_cache.get("f.jpg").unwrap()[0].id
  for src, list in image_cache {
    for e in list {
      assert_true(src == "f.jpg" || e.id != f_id, msg="f's number \{f_id} is \{src}'s too")
    }
  }
  all_done()
  t.draw()
  assert_eq(image_state("f.jpg"), 1, msg="f ready as its host says so")
  assert_eq(image_bytes.val, kept_bytes())
}
