///|
test "a file's card (FileCard): its name and size, how far it has gone up while it goes, why it failed; its ✕ and ↻ pressed" {
  let done : Ref[FileCardDone] = Ref({ removed: false, retried: false, opened: false })
  let pending = Ref(true)
  let failed = Ref("")
  let t = @ui.Tester::new(
    fn(c) {
      let _ = begin(c)
      c.box(style=@ui.css("w=Full h=Full p=S4"), fn() {
        let d = file_card(
          c,
          "card",
          "build.log",
          18432.0,
          pending=pending.val,
          sent=Some(9216.0),
          error=failed.val,
          remove=true,
          retry=failed.val != "",
        )
        // (kept once pressed: the frames after it say no more)
        done.val = { removed: done.val.removed || d.removed, retried: done.val.retried || d.retried, opened: done.val.opened || d.opened }
      })
      |> ignore
    },
    w=400.0,
    h=200.0,
  )
  t.draw()
  assert_true(t.find("build") is Some(_))
  assert_true(t.find(".log") is Some(_))
  // going up: how far, in its size's place (its words' key while the catalog has none)
  assert_true(t.words().iter().any(fn(w) { w.0.contains("web-main.file.uploadingPart") }), msg=t.words().map(fn(w) { w.0 }).join("|"))
  pending.val = false
  failed.val = "上传失败"
  t.draw()
  assert_true(t.find("上传失败") is Some(_))
  let (x, y, w, h) = t.query(Button, label="web-main.composer.retryUpload").unwrap().rect
  t.tap(x + w / 2.0, y + h / 2.0)
  assert_true(done.val.retried)
  let (x, y, w, h) = t.query(Button, label="web-main.file.remove").unwrap().rect
  t.tap(x + w / 2.0, y + h / 2.0)
  assert_true(done.val.removed)
}

///|
test "a quote's card (QuoteCard): whose and the passage, what is said under it; its source pressed to jump, its ✕ to let it go" {
  let done : Ref[QuoteCardDone] = Ref({ jumped: false, removed: false })
  let t = @ui.Tester::new(
    fn(c) {
      let _ = begin(c)
      c.box(style=@ui.css("w=Full h=Full p=S4"), fn() {
        let d = quote_card(c, "q1", "Claude", "其余的行按估计的高度占位", comment="量过再记", jump=true, remove=true)
        done.val = { jumped: done.val.jumped || d.jumped, removed: done.val.removed || d.removed }
      })
      |> ignore
    },
    w=400.0,
    h=200.0,
  )
  t.draw()
  assert_true(t.find("量过再记") is Some(_))
  let (x, y) = t.find("其余的行按估计的高度占位").unwrap()
  t.tap(x, y)
  assert_true(done.val.jumped)
  let (x, y, w, h) = t.query(Button, label="web-main.quote.remove").unwrap().rect
  t.tap(x + w / 2.0, y + h / 2.0)
  assert_true(done.val.removed)
}
