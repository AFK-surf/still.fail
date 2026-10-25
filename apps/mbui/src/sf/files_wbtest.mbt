///|
test "a file's card (FileCard): its name and size, how far it has gone up while it goes, why it failed; its ✕ and ↻ pressed" {
  let done : Ref[FileCardDone] = Ref({ removed: false, retried: false, restored: false, opened: false })
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
        done.val = {
          removed: done.val.removed || d.removed,
          retried: done.val.retried || d.retried,
          restored: done.val.restored || d.restored,
          opened: done.val.opened || d.opened,
        }
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
test "pasted words' card (PendingFile's pasted card): what they begin with and how many in place of name and size; ✎ puts them back" {
  let restored = Ref(false)
  let t = @ui.Tester::new(
    fn(c) {
      let _ = begin(c)
      c.box(style=@ui.css("w=Full h=Full p=S4"), fn() {
        let d = file_card(
          c,
          "paste",
          "pasted-text-1.txt",
          6000.0,
          title="发布前要核对的条目",
          meta="6,000 字符",
          remove=true,
          restore=true,
          remove_label="删除粘贴片段",
        )
        if d.restored {
          restored.val = true
        }
      })
      |> ignore
    },
    w=400.0,
    h=200.0,
  )
  t.draw()
  assert_true(t.find("发布前要核对的条目") is Some(_))
  assert_true(t.find("6,000 字符") is Some(_))
  assert_true(t.find("pasted-text") is None)
  assert_true(t.query(Button, label="删除粘贴片段") is Some(_))
  let (x, y, w, h) = t.query(Button, label="web-main.composer.expandPaste").unwrap().rect
  t.tap(x + w / 2.0, y + h / 2.0)
  assert_true(restored.val)
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

///|
test "a station's file named by its path (RefCard): no ground, its edge dashed in the strong line, where it is and how it goes in the quiet ink, not a failure's" {
  let t = @ui.Tester::new(
    fn(c) {
      let _ = begin(c)
      c.box(style=@ui.css("w=Full h=Full p=S4"), fn() {
        file_card(c, "ref", "发布清单.md", 4210.0, named=true, meta="Studio · 路径", open=true, remove=true) |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=200.0,
  )
  t.draw()
  let card = t.boxes().filter(fn(l) { l.dashed })
  assert_eq(card.length(), 1)
  assert_eq((card[0].bg & 0xFFL, card[0].border_w, card[0].border_c), (0L, 1.0, theme().p.line_strong))
  let said = t.boxes().filter(fn(l) { l.text == "Studio · 路径" })
  assert_eq(said.length(), 1)
  assert_eq(said[0].color, ui_theme().color(Muted))
}

///|
test "a file going up while how far is not known: a spinner where its sheet is, turning; known, its sheet filling" {
  let sent : Ref[Double?] = Ref(None)
  let t = @ui.Tester::new(
    fn(c) {
      let _ = begin(c)
      c.box(style=@ui.css("w=Full h=Full p=S4"), fn() {
        file_card(c, "zip", "设计稿.zip", 0.0, pending=true, sent=sent.val, remove=true) |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=200.0,
  )
  t.draw()
  let first = t.drawn_lines()
  assert_true(first.length() > 0, msg="no spinner")
  t.run_for(200.0)
  t.draw()
  assert_true(t.drawn_lines() != first, msg="the spinner stands still")
  sent.val = Some(0.0)
  t.draw()
  assert_eq(t.drawn_lines().length(), 0)
}
