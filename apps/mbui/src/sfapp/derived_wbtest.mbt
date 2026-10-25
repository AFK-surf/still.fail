// What the pages work out of a topic (sfbase derived.mbt: alien-signals' computed, mbui/signals): once for each
// version of it and of what else it read, however many read it and however often (the user, 2026-10-26: 「不应该有个跟
// preact signals 一样的机制来保证只计算一次吗」「实现可以抄一下 alien-signals」).

///|
test "a topic's value is worked out once for each of its versions, however often the frames read it" {
  let version = Ref(1)
  let src : Source = {
    ..fixture("home"),
    topic: fn(_, _) { { value: Some(Json::number(version.val.to_double())), error: None, version: version.val } },
  }
  let worked = Ref(0)
  let made : @sfbase.Derived[Double] = @sfbase.Derived::new("counted", fn(v) {
    worked.val += 1
    v.as_number().unwrap_or(0.0)
  })
  let seen = Ref(0.0)
  let t = @ui.Tester::new(fn(_) {
    // (read three times a frame: a page, its side panel and the frame round them)
    for _ in 0..<3 {
      seen.val = made.read(src, { "chat": Json::string("c1") }).0.unwrap_or(-1.0)
    }
  })
  t.draw()
  t.draw()
  t.draw()
  assert_eq(seen.val, 1.0)
  assert_eq(worked.val, 1)
  // a new version: worked out again, once
  version.val = 2
  t.draw()
  t.draw()
  assert_eq(seen.val, 2.0)
  assert_eq(worked.val, 2)
}

///|
test "what is worked out of a topic another chat reads is that chat's own" {
  let src : Source = {
    ..fixture("home"),
    topic: fn(_, params) { { value: params.get("chat"), error: None, version: 1 } },
  }
  let made : @sfbase.Derived[String] = @sfbase.Derived::new("named", fn(v) {
    match v {
      String(s) => s
      _ => ""
    }
  })
  let seen : Array[String] = []
  let t = @ui.Tester::new(fn(_) {
    seen.clear()
    for chat in ["c1", "c2"] {
      seen.push(made.read(src, { "chat": Json::string(chat) }).0.unwrap_or(""))
    }
  })
  t.draw()
  assert_eq(seen, ["c1", "c2"])
}

///|
test "what is worked out of a topic and a signal of the page's is worked out again only as one of them changes" {
  let version = Ref(1)
  let src : Source = {
    ..fixture("home"),
    topic: fn(_, _) { { value: Some(Json::number(version.val.to_double())), error: None, version: version.val } },
  }
  let only_io = @signals.signal(false, same=fn(a, b) { a == b })
  let made : @sfbase.Kept[String] = @sfbase.Kept::new()
  let worked = Ref(0)
  let seen = Ref("")
  let t = @ui.Tester::new(fn(_) {
    // (its topic read where it is read, as a page reads it: its version told)
    @sfbase.topic_read(src, "counted", {}) |> ignore
    for _ in 0..<3 {
      seen.val = made.read("rows", fn() {
        worked.val += 1
        let n = @sfbase.topic_read(src, "counted", {}).value.unwrap().as_number().unwrap_or(0.0)
        "\{n.to_int()} \{only_io.get()}"
      })
    }
  })
  t.draw()
  t.draw()
  assert_eq(seen.val, "1 false")
  assert_eq(worked.val, 1)
  // the page's own: once
  only_io.set(true)
  t.draw()
  t.draw()
  assert_eq(seen.val, "1 true")
  assert_eq(worked.val, 2)
  // the topic's: once
  version.val = 2
  t.draw()
  t.draw()
  assert_eq(seen.val, "2 true")
  assert_eq(worked.val, 3)
}
