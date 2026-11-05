///|
test "a quote made once keeps the old source and comment positions, in a message and the composer" {
  set_words(fn(key, args) { if key == "web-main.quote.author" { args[0].1 + ": " } else { key } })
  for composer in [false, true] {
    let text = "这是一段长引用，超过两行后应该在同一个字结束。留下评论以后仍然保留原来的引用。"
    let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=390.0, h=500.0, platform=2)
    let author = @signals.signal("林")
    let comment = @signals.signal("我的评论")
    let made : Ref[QuoteCardNode?] = Ref(None)
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(ui_theme_now)
      root.box(fn(h) {
        h.width(Is(Some(350.0))).height(Is(Some(200.0))) |> ignore
        @ui.old(h, fn(c) {
          c.with_theme(ui_theme(), fn() {
            quote_card(c, "before", author.get(), text, comment=comment.get(), composer~, words_key="before/words") |> ignore
          })
        }).grow(Is(1.0)) |> ignore
      }) |> ignore
      root.box(fn(h) {
        h.width(Is(Some(350.0))) |> ignore
        made.val = Some(quote_card_node(h, fn() { author.get() }, fn() { text }, comment=fn() { comment.get() }, composer~))
      }) |> ignore
    })
    t.draw()
    let id = made.val.unwrap().words.id()
    let same = fn() raise {
      let all = t.drawn_glyphs()
      let old = all.filter(fn(g) { g.1 < 200.0 })
      let now = all.filter(fn(g) { g.1 >= 200.0 }).map(fn(g) { (g.0, g.1 - 200.0, g.2) })
      assert_true(old.length() > 10)
      assert_eq(now, old, msg="composer=\{composer}, old-width=\{@ui.current().words_of("before/words").map(fn(w) { w.pieces.map(fn(p) { (p.x, p.y, p.w, p.h) }) })}, node=\{made.val.unwrap().words.rect()}, card=\{made.val.unwrap().card.rect()}, old=\{old}, now=\{now}")
      if !composer {
        let cards = t.boxes_held().filter(fn(b) { b.radius == quote_corner && b.w == 350.0 && b.bg != 0L })
        let before = cards.iter().find_first(fn(b) { b.y < 200.0 }).unwrap()
        let after = cards.iter().find_first(fn(b) { b.y >= 200.0 }).unwrap()
        assert_eq(after.bg, before.bg, msg="a sent quote keeps the original message card's ground")
      }
    }
    same()
    author.set("新的来源")
    comment.set("改了评论")
    t.draw()
    same()
    assert_eq(made.val.unwrap().words.id(), id)
  }
}

///|
test "a quote's flying copy reserves its picture's room without making or owning that picture again" {
  set_words(fn(key, args) { if key == "web-main.quote.author" { args[0].1 + ": " } else { key } })
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=390.0, h=700.0, platform=2)
  let visible = @signals.signal(true)
  let height = @signals.signal(90.0)
  let copies = @signals.signal(false)
  let made = Ref(0)
  let released = Ref(0)
  let original : Ref[QuoteCardNode?] = Ref(None)
  let flying : Ref[QuoteCardNode?] = Ref(None)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    let card = quote_card_node(root, fn() { "Ana" }, fn() { "图片的引用" }, comment=fn() { "留在图片下的评论" },
      picture_shown=fn() { visible.get() },
      // (the box its picture is laid out in, as its caller says it: the copy's room for it)
      picture_box=fn(p) {
        p.box(fn(content) { content.width(Is(Some(180.0))).height(By(fn() { Some(height.get()) })) |> ignore }) |> ignore
      },
      picture=fn(p) {
        made.val += 1
        p.owns(fn() { released.val += 1 }) |> ignore
        p.box(fn(content) {
          content.width(Is(Some(180.0))).height(By(fn() { Some(height.get()) }))
          .words(Is("这里由图片自己的飞行副本绘制")) |> ignore
        }) |> ignore
      })
    original.val = Some(card)
    root.show(fn() { copies.get() }, fn(p) { flying.val = Some((card.copy)(p, fn() { None })) })
  })
  t.draw()
  copies.set(true)
  t.draw()
  assert_eq(made.val, 1, msg="the flight must not replace the real picture's landing or preview registration")
  let same_room = fn() raise {
    assert_eq(flying.val.unwrap().card.laid_size(), original.val.unwrap().card.laid_size())
    assert_eq(t.words().filter(fn(s) { s.0 == "这里由图片自己的飞行副本绘制" }).length(), 1)
  }
  same_room()
  height.set(140.0)
  t.draw()
  same_room()
  visible.set(false)
  t.draw()
  assert_eq(released.val, 1)
  assert_eq(flying.val.unwrap().card.laid_size(), original.val.unwrap().card.laid_size())
  visible.set(true)
  t.draw()
  assert_eq(made.val, 2)
  same_room()
  copies.set(false)
  t.draw()
  assert_eq(released.val, 1, msg="letting the flying copy go cannot release the real picture")
}
