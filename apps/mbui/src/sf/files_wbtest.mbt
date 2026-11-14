///|
test "a file's card (FileCard): its name and size, how far it has gone up while it goes, why it failed; its ✕ and ↻ pressed" {
  let done : Array[FileCardPress] = []
  let pending = Ref(true)
  let failed = Ref("")
  let sent = Ref(9216.0)
  let t = @ui.Tester::new(
    fn(c) {
      let _ = begin(c)
      c.box(style=@ui.css("w=Full h=Full p=S4"), fn() {
        file_card(
          c,
          "card",
          "build.log",
          18432.0,
          pending=pending.val,
          sent=Some(sent.val),
          error=failed.val,
          remove=true,
          retry=failed.val != "",
          on_press=fn(on) { done.push(on) },
        )
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
  // all of it gone, the station not yet saying it has it: waiting for it, not 100%
  sent.val = 18432.0
  t.draw()
  assert_true(t.words().iter().any(fn(w) { w.0.contains("common.uploadConfirming") }), msg=t.words().map(fn(w) { w.0 }).join("|"))
  pending.val = false
  failed.val = "上传失败"
  t.draw()
  assert_true(t.find("上传失败") is Some(_))
  let (x, y, w, h) = t.query(Button, label="web-main.composer.retryUpload").unwrap().rect
  t.tap(x + w / 2.0, y + h / 2.0)
  assert_eq(done, [Retry])
  let (x, y, w, h) = t.query(Button, label="web-main.file.remove").unwrap().rect
  t.tap(x + w / 2.0, y + h / 2.0)
  assert_eq(done, [Retry, Remove])
}

///|
test "pasted words' card (PendingFile's pasted card): what they begin with and how many in place of name and size; ✎ puts them back" {
  let restored = Ref(false)
  let t = @ui.Tester::new(
    fn(c) {
      let _ = begin(c)
      c.box(style=@ui.css("w=Full h=Full p=S4"), fn() {
        file_card(
          c,
          "paste",
          "pasted-text-1.txt",
          6000.0,
          title="发布前要核对的条目",
          meta="6,000 字符",
          remove=true,
          restore=true,
          remove_label="删除粘贴片段",
          on_press=fn(on) { if on == Restore { restored.val = true } },
        )
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
  let jumped = Ref(false)
  let removed = Ref(false)
  let t = @ui.Tester::new(
    fn(c) {
      let _ = begin(c)
      c.box(style=@ui.css("w=Full h=Full p=S4"), fn() {
        quote_card(c, "q1", "Claude", "其余的行按估计的高度占位", comment="量过再记", on_jump=fn() { jumped.val = true }, on_remove=fn() {
          removed.val = true
        })
        |> ignore
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
  assert_true(jumped.val)
  assert_false(removed.val)
  let (x, y, w, h) = t.query(Button, label="web-main.quote.remove").unwrap().rect
  t.tap(x + w / 2.0, y + h / 2.0)
  assert_true(removed.val)
}

///|
test "a quote's picture with nothing said under it: as far over its card's foot as in from its side" {
  let card = Ref(-1)
  let picture = Ref(-1)
  let t = @ui.Tester::new(
    fn(c) {
      let _ = begin(c)
      c.box(style=@ui.css("w=Full h=Full p=S4"), fn() {
        card.val = quote_card(c, "q1", "Opus", "ref4.png", picture=fn() {
          picture.val = c.box(style=@ui.style(w=Fixed(120.0), h=Fixed(80.0)), fn() {  })
        })
      })
      |> ignore
    },
    w=400.0,
    h=300.0,
  )
  t.draw()
  let laid = t.boxes()
  let q = laid.iter().find_first(fn(l) { l.index == card.val }).unwrap()
  let p = laid.iter().find_first(fn(l) { l.index == picture.val }).unwrap()
  assert_eq(q.y + q.h - (p.y + p.h), p.x - q.x)
}

///|
test "a quote waiting in the composer has its ✕ hung on its corner, as everything waiting there: its centre on the curve, the quote its room across, the ✕ past its side as far as past its top" {
  let removed = Ref(false)
  let t = @ui.Tester::new(
    fn(c) {
      let _ = begin(c)
      c.box(style=@ui.css("w=Full h=Full p=S4"), fn() {
        quote_card(c, "q1", "Claude", "其余的行按估计的高度占位", composer=true, on_remove=fn() { removed.val = true }) |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=200.0,
  )
  t.draw()
  let (x, y, w, h) = t.query(Button, label="web-main.quote.remove").unwrap().rect
  // (the one ✕ of what waits to go: 20 round, solid)
  assert_eq((w, h), (20.0, 20.0))
  // the quote's ground: the widest rounded box drawn
  let mut q = (0.0, 0.0, 0.0, 0.0, 0.0)
  for r in t.drawn_rect_corners() {
    if r.2 > q.2 && (r.5).1 > 0.0 {
      q = (r.0, r.1, r.2, r.3, (r.5).1)
    }
  }
  let m = @ui.smooth_middle(q.4)
  let near = fn(a : Double, b : Double) { (a - b).abs() < 0.01 }
  assert_true(near(x + w / 2.0, q.0 + q.2 - m), msg="across: \{x + w / 2.0}, the corner's curve at \{q.0 + q.2 - m}")
  assert_true(near(y + h / 2.0, q.1 + m), msg="down: \{y + h / 2.0}, the corner's curve at \{q.1 + m}")
  // nothing beside it, no room kept at its end: the quote ends where its room does (16 in from the window's edge), its
  // ✕ past that as far as past its top (the user, 2026-10-26: 上边距和右边距不一致)
  assert_true(near(q.0 + q.2, 400.0 - 16.0), msg="its end at \{q.0 + q.2}")
  assert_true(near(x + w - (q.0 + q.2), q.1 - y), msg="past its side \{x + w - (q.0 + q.2)}, past its top \{q.1 - y}")
  t.tap(x + w / 2.0, y + h / 2.0)
  assert_true(removed.val)
}

///|
test "a station's file named by its path (RefCard): no ground, its edge dashed in the strong line, where it is and how it goes in the quiet ink, not a failure's" {
  let t = @ui.Tester::new(
    fn(c) {
      let _ = begin(c)
      c.box(style=@ui.css("w=Full h=Full p=S4"), fn() {
        file_card(c, "ref", "发布清单.md", 4210.0, named=true, meta="Willow · 路径", open=true, remove=true) |> ignore
        // (a file's card beside it: its size in the quiet ink)
        file_card(c, "file", "build.log", 18432.0, meta="18 KB", remove=true) |> ignore
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
  let said = t.boxes().filter(fn(l) { l.text == "Willow · 路径" })
  let size = t.boxes().filter(fn(l) { l.text == "18 KB" })
  assert_eq((said.length(), size.length()), (1, 1))
  assert_eq(said[0].color, size[0].color)
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
  t.run_for(spinner_turn_ms / 4.0)
  t.draw()
  assert_true(t.drawn_lines() != first, msg="the spinner stands still")
  sent.val = Some(0.0)
  t.draw()
  assert_eq(t.drawn_lines().length(), 0)
}
