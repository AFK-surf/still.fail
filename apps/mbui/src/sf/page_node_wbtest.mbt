// A group's rows made once as nodes (page_node.mbt) drawn as page.mbt draws them narrow: a row with an icon, its title
// and a line under it, beside one with no line, each instance where and as the old view's are, at the system's size of
// words 1 and 2 (the icon by its first line, as tall as that line is drawn at least: row_lead's).

///|
/// What is drawn of the group: as an old view's (`node` false) or as nodes, at the system's size of words `scale`, each
/// instance's numbers rounded to a hundredth (a glyph's place in its atlas left out), in one order.
fn rows_drawn(node : Bool, scale : Double) -> Array[String] {
  let t = if node {
    @ui.Tester::new(fn(_c) {  }, w=390.0, h=600.0, platform=2)
  } else {
    @ui.Tester::new(
      fn(c) {
        with_look(Narrow, fn() {
          c.box(style=pg_room, fn() {
            group(c, fn() {
              link_row(c, "a", "Station", note="两台在线，一台离线", lead=fn() {
                icon(c, "server", size=row_icon, color=theme().p.muted) |> ignore
              })
              |> ignore
              link_row(c, "b", "连接", value="3 个") |> ignore
            })
          })
          |> ignore
        })
      },
      w=390.0,
      h=600.0,
      platform=2,
    )
  }
  t.set_font_scale(scale)
  if node {
    @ui.set_view_app(fn(root) {
      root.box(fn(b) {
        page_block(b, fn(room) {
          group_node(room, fn(g) {
            link_row_node(g, fn() { "Station" }, fn() {  }, note=fn() { "两台在线，一台离线" }, lead=LeadIcon("server"))
            link_row_node(g, fn() { "连接" }, fn() {  }, value=fn() { "3 个" })
          })
        })
      })
      |> ignore
    })
  }
  t.draw()
  let all = t.drawn_instances_keyed().map(fn(a) {
    a
    .mapi(fn(j, x) {
      if a[5] == 1.0 && j == 12 {
        if x >= 16384.0 { "colour" } else { "mono" }
      } else if a[5] == 1.0 && j == 13 {
        "-"
      } else {
        ((x * 100.0).round() / 100.0).to_string()
      }
    })
    .join(",")
  })
  all.sort()
  all
}

///|
test "a group's rows as nodes: a row with an icon and a line under its title, and one with neither, drawn as the old view's at sizes of words 1 and 2" {
  for scale in [1.0, 2.0] {
    let old = rows_drawn(false, scale)
    assert_eq(rows_drawn(true, scale), old, msg="at \{scale}")
  }
}

///|
/// A page made once (page_node, a finger's, 390 × 844) of 30 blocks each 60 tall (counted 80 before they are laid out),
/// dragged up by a finger `times` times across most of the window: where its last block is drawn then, top and foot.
fn page_dragged(times : Int) -> (Double, Double) {
  let t = @ui.Tester::new(fn(_c) {  }, w=390.0, h=844.0, platform=2)
  @ui.set_view_app(fn(root) {
    root.box(fn(b) {
      b.height(Is(Some(844.0))).width(Is(Some(390.0))) |> ignore
      page_node(b, fn() { "Title" }, fn() { Array::makei(30, fn(i) { "b\{i}" }) }, fn(v, k) {
        v.box(fn(w) { w.height(Is(Some(60.0))).words(Is("block " + k)) |> ignore }) |> ignore
      }, on_back=fn() {  })
    })
    |> ignore
  })
  t.draw()
  for _ in 0..<times {
    t.drag(195.0, 700.0, 195.0, 100.0)
    t.run_for(@ui.move_most_ms)
  }
  match @ui.view_tree() {
    Some(tree) =>
      match tree.drawn().search_by(fn(d) { d.words == "block b29" }) {
        Some(i) => (tree.drawn()[i].y, tree.drawn()[i].y + tree.drawn()[i].h)
        None => (-1.0, -1.0)
      }
    None => (-1.0, -1.0)
  }
}

///|
test "a page made once dragged on past its end, counted taller there than it is: at its end as it really is, its foot's room under its last block" {
  let (_, foot) = page_dragged(6)
  assert_eq(foot, 844.0 - pg_foot)
}

///|
/// What is drawn of `old` (built as an old view's, narrow, in the page's room) or of `made` (as nodes, in a page's
/// block), 390 wide, at the system's size of words `scale`, as rows_drawn reads it.
fn page_part_drawn(node : Bool, scale : Double, old : (@ui.Ctx) -> Unit, made : (@view.View) -> Unit) -> Array[String] {
  let t = if node {
    @ui.Tester::new(fn(_c) {  }, w=390.0, h=600.0, platform=2)
  } else {
    @ui.Tester::new(fn(c) { with_look(Narrow, fn() { c.box(style=pg_room, fn() { old(c) }) |> ignore }) }, w=390.0, h=600.0, platform=2)
  }
  t.set_font_scale(scale)
  if node {
    @ui.set_view_app(fn(root) { root.box(fn(b) { page_block(b, made) }) |> ignore })
  }
  t.draw()
  let all = t.drawn_instances_keyed().map(fn(a) {
    a
    .mapi(fn(j, x) {
      if a[5] == 1.0 && j == 12 {
        if x >= 16384.0 { "colour" } else { "mono" }
      } else if a[5] == 1.0 && j == 13 {
        "-"
      } else {
        ((x * 100.0).round() / 100.0).to_string()
      }
    })
    .join(",")
  })
  all.sort()
  all
}

///|
test "a row with words under it as a node: its title and what it says in a line, what it says under the title where the line has not the room, as the old view's at sizes of words 1 and 2; one with none under it on one line" {
  for scale in [1.0, 2.0] {
    let old = page_part_drawn(false, scale, fn(c) {
      group(c, fn() {
        link_row(c, "a", "判断是否完成", note="标记完成后判断是否推荐归档", value="1 台 station 已启用") |> ignore
        link_row(c, "b", "Willow", value="全局记忆 · 项目记忆") |> ignore
      })
    }, fn(_) { () })
    let made = page_part_drawn(true, scale, fn(_) { () }, fn(room) {
      group_node(room, fn(g) {
        link_row_node(g, fn() { "判断是否完成" }, fn() {  }, note=fn() { "标记完成后判断是否推荐归档" }, value=fn() { "1 台 station 已启用" })
        link_row_node(g, fn() { "Willow" }, fn() {  }, value=fn() { "全局记忆 · 项目记忆" })
      })
    })
    assert_true(old.length() > 0)
    assert_eq(made, old, msg="at \{scale}")
  }
}

///|
test "a page's card as a node: its words 20 in and 14 apart, round, on the card's ground, 10 over what follows; with a button at its foot, the capsule's room under it; as the old view's at sizes of words 1 and 2" {
  for footed in [false, true] {
    for scale in [1.0, 2.0] {
      let old = page_part_drawn(false, scale, fn(c) {
        page_card(c, footed~, fn() {
          c.text("Willow", style=pg_heading) |> ignore
          c.text("空闲超过下面的天数就归档。只看状态，不读内容。", style=pg_note) |> ignore
        })
        c.box(style=@ui.css("w=Full h=S5 bg=Card"), fn() {  }) |> ignore
      }, fn(_) { () })
      let made = page_part_drawn(true, scale, fn(_) { () }, fn(room) {
        page_card_node(room, footed~, fn(k) {
          k.box(fn(w) { styled_words(w, fn() { "Willow" }, fn() { pg_heading }) |> ignore }) |> ignore
          k.box(fn(w) { styled_words(w, fn() { "空闲超过下面的天数就归档。只看状态，不读内容。" }, fn() { pg_note }) |> ignore }) |> ignore
        })
        room.box(fn(f) {
          f.height(Is(Some(20.0))).ground(By(fn() { @ui.tree_theme().color(Card) })) |> ignore
        })
        |> ignore
      })
      assert_true(old.length() > 0)
      assert_eq(made, old, msg="footed \{footed} at \{scale}")
    }
  }
}

///|
/// A page titled `title` with a choice of `labels` at its title's line's end (what it does), `w` wide, at the system's
/// size of words `scale`: as an old view's (page, its head_end's segmented) or made once (page_node's `actions`,
/// seg_head_node); what is drawn, as rows_drawn reads it.
fn head_end_drawn(
  node : Bool,
  w : Double,
  scale : Double,
  title : String,
  labels : Array[String],
  share? : Bool = false,
) -> Array[String] {
  let at = @signals.signal(0)
  let t = if node {
    @ui.Tester::new(fn(c) { begin(c) |> ignore }, w~, h=400.0, platform=2)
  } else {
    @ui.Tester::new(
      fn(c) {
        begin(c) |> ignore
        c.with_theme(ui_theme(), fn() {
          page(c, "head-end", title, [], on_back=fn() {  }, actions=fn() {
            if share {
              icon_button(c, "share", key="head-share", label="分享卡片") |> ignore
            }
            let k = segmented(c, "days", labels, at.get())
            if k != at.get() {
              at.set(k)
            }
          })
        })
      },
      w~,
      h=400.0,
      platform=2,
    )
  }
  t.set_font_scale(scale)
  if node {
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(ui_theme_now)
      root.box(fn(b) {
        b.height(Is(Some(400.0))) |> ignore
        page_node(b, fn() { title }, fn() { [] }, fn(_, _) {  }, on_back=fn() {  }, actions=fn(a) {
          if share {
            icon_button_node(a, "share", fn() { "分享卡片" }, fn() {  }) |> ignore
          }
          seg_head_node(a, fn() { labels }, fn() { at.get() }, fn(k) { at.set(k) }) |> ignore
        })
      })
      |> ignore
    })
  }
  t.run_for(@ui.move_most_ms)
  let all = t.drawn_instances_keyed().map(fn(a) {
    a
    .mapi(fn(j, x) {
      if a[5] == 1.0 && j == 12 {
        if x >= 16384.0 { "colour" } else { "mono" }
      } else if a[5] == 1.0 && j == 13 {
        "-"
      } else {
        ((x * 100.0).round() / 100.0).to_string()
      }
    })
    .join(",")
  })
  all.sort()
  all
}

///|
test "what a page does at its title's line's end as nodes (a choice of days there): beside its title as wide as its options, giving way first where the line has not the room, as the old view's at sizes of words 1 and 2" {
  for case in [(390.0, 1.0, "用量"), (390.0, 2.0, "用量"), (260.0, 1.0, "用量"), (300.0, 2.0, "按 station 的用量")] {
    let (w, scale, title) = case
    let old = head_end_drawn(false, w, scale, title, ["7 天", "30 天"])
    assert_true(old.length() > 0)
    seg_same(head_end_drawn(true, w, scale, title, ["7 天", "30 天"]), old, "\{Repr(case)}")
  }
}

///|
test "分享 and a choice of days at a page's title's line's end as nodes, the line narrower than they ask but with the room for their least beside the title: on one line, sharing its lack as the old view's" {
  for case in [(390.0, 1.0, "用量"), (390.0, 2.0, "按 station 的用量"), (340.0, 2.0, "按 station 的用量"), (300.0, 1.0, "按 station 的用量的明细")] {
    let (w, scale, title) = case
    let old = head_end_drawn(false, w, scale, title, ["7 天", "30 天"], share=true)
    assert_true(old.length() > 0)
    seg_same(head_end_drawn(true, w, scale, title, ["7 天", "30 天"], share=true), old, "\{Repr(case)}")
  }
  // (each but the first narrower than they ask: the choice less wide than in a wide window, all on the title's line)
  for case in [(390.0, 2.0, "按 station 的用量"), (340.0, 2.0, "按 station 的用量"), (300.0, 1.0, "按 station 的用量的明细")] {
    let (w, scale, title) = case
    let (_, _, _, _, share, seg) = titled_ends(1000.0, title~, scale~)
    let (_, _, whole) = ends_drawn(share, seg, title~)
    let (_, _, _, _, share, seg) = titled_ends(w, title~, scale~)
    let (words, sh, sg) = ends_drawn(share, seg, title~)
    assert_true(sg.2 < whole.2 - 0.5, msg="\{Repr(case)}: the choice given way: \{sg.2} of \{whole.2}")
    assert_true(sh.1 < words.1 + words.3 && sg.1 < words.1 + words.3, msg="\{Repr(case)}: one line: \{Repr(words)} \{Repr(sh)} \{Repr(sg)}")
  }
}

///|
test "what a page does at its title's line's end as nodes, where the line has not the room for the title at its least beside the choice at its least (220 wide, words twice as large): the title on its line within the window, the choice under it whole within it, at the line's end, chosen by a tap (the old view's title ran past the window, its choice gone: not kept)" {
  let at = @signals.signal(0)
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=220.0, h=400.0, platform=2)
  t.set_font_scale(2.0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.box(fn(b) {
      b.height(Is(Some(400.0))) |> ignore
      page_node(b, fn() { "按 station 的用量" }, fn() { [] }, fn(_, _) {  }, on_back=fn() {  }, actions=fn(a) {
        seg_head_node(a, fn() { ["7 天", "30 天"] }, fn() { at.get() }, fn(k) { at.set(k) }) |> ignore
      })
    })
    |> ignore
  })
  t.run_for(@ui.move_most_ms)
  let drawn = @ui.view_tree().unwrap().drawn()
  let of = fn(w : String) { drawn.filter(fn(d) { d.words == w }) }
  for w in ["按 station 的用量", "7 天", "30 天"] {
    assert_true(of(w).length() == 1, msg="\{w} drawn once: \{of(w).length()}")
    let d = of(w)[0]
    assert_true(d.x >= 0.0 && d.x + d.w <= 220.0 && d.w > 0.0, msg="\{w} within the window: \{d.x} + \{d.w}")
  }
  // (the choice under the title, not over it, its end the line's: 16 in from the window's)
  let title = of("按 station 的用量")[0]
  let first = of("7 天")[0]
  let last = of("30 天")[0]
  assert_true(first.y >= title.y + title.h, msg="under the title: \{title.y} + \{title.h}, \{first.y}")
  assert_true(last.x + last.w <= 204.0, msg="within the line: \{last.x} + \{last.w}")
  t.tap_text("30 天")
  t.run_for(@ui.move_most_ms)
  assert_eq(at.get(), 1, msg="30 天 chosen by a tap")
}

///|
/// One step of words with shorter ones in their place: the box's width, the words, the shorter ones, whether they wrap.
priv struct ShorterStep {
  w : Double
  said : String
  alts : Array[String]
  wrap : Bool
}

///|
/// The same words node (an old view's text with `shorter`; as nodes, View::shorter) through `steps` in turn, in a box as
/// wide as each says: at each, every instance drawn (their glyphs and the box's, as rows_drawn reads them) and what the
/// Tester finds as words.
fn shorter_seen(node : Bool, steps : Array[ShorterStep]) -> Array[String] {
  let at = @signals.signal(steps[0])
  let look = fn(s : ShorterStep) { pg_note.then(if s.wrap { @ui.text_style(wrap=true) } else { one_line }) }
  let t = if node {
    @ui.Tester::new(fn(_c) {  }, w=390.0, h=300.0, platform=2)
  } else {
    @ui.Tester::new(fn(c) {
      let s = at.get()
      c.box(w=Px(s.w), clip=true, bg=0x33669910L, fn() { c.text(s.said, style=look(s), shorter=s.alts) |> ignore }) |> ignore
    }, w=390.0, h=300.0, platform=2)
  }
  if node {
    @ui.set_view_app(fn(root) {
      root.lines_up(Is(Some(Start))) |> ignore
      root.box(fn(b) {
        b.width(By(fn() { Some(at.get().w) })).clips(Is(true)).ground(Is(0x33669910L)) |> ignore
        words_node(b, fn() { at.get().said }, fn() { look(at.get()) }).shorter(By(fn() { at.get().alts })).allow_ellipsis(Is(true))
        |> ignore
      })
      |> ignore
    })
  }
  let out = []
  for i, s in steps {
    at.set(s)
    t.draw()
    t.draw()
    let drawn = t.drawn_instances_keyed().map(fn(a) {
      a.mapi(fn(j, x) { if a[5] == 1.0 && (j == 12 || j == 13) { "-" } else { ((x * 100.0).round() / 100.0).to_string() } }).join(",")
    })
    drawn.sort()
    out.push("step \{i} (\{s.w}) words: " + t.words().map(fn(w) { w.0 }).join(" | "))
    for d in drawn {
      out.push("step \{i}: " + d)
    }
  }
  out
}

///|
test "words with shorter ones in their place, as nodes, the same node throughout: their own where they have the room; narrowed, the first shorter that has it, else the last cut short; widened, their own again; none said, or wrapping, their own; the words changed; every instance drawn as the old view's, found as their own words" {
  let said = "2026 年 5 月"
  let alts = ["5 月", "5"]
  let one = fn(w : Double, alts : Array[String]) -> ShorterStep { { w, said, alts, wrap: false } }
  let steps : Array[ShorterStep] = [
    one(200.0, alts),
    one(50.0, alts),
    one(22.0, alts),
    one(4.0, alts),
    one(200.0, alts),
    one(22.0, alts),
    // (none said in their place now, the same node: its own, cut short)
    one(22.0, []),
    one(22.0, alts),
    // (wrapping now: its own, on its lines)
    { w: 22.0, said, alts, wrap: true },
    one(22.0, alts),
    // (none fits but "": nothing)
    one(10.0, [""]),
    // (the words said otherwise)
    { w: 22.0, said: "2027 年 6 月", alts: ["6 月", "6"], wrap: false },
    { w: 300.0, said: "2027 年 6 月", alts: ["6 月", "6"], wrap: false },
  ]
  let made = shorter_seen(true, steps)
  let old = shorter_seen(false, steps)
  assert_true(old.length() > steps.length())
  if made != old {
    let only_old = old.filter(fn(x) { !made.contains(x) })
    let only_made = made.filter(fn(x) { !old.contains(x) })
    fail("old's alone:\n  \{only_old.join("\n  ")}\nmade's alone:\n  \{only_made.join("\n  ")}")
  }
}

///|
/// Words saying shorter ones, as wide as what of them is drawn, in a row `w` wide beside a box 40 by 10 (an old view's
/// text with `shorter`; as nodes, View::shorter): every instance drawn, at each of `widths` in turn, as rows_drawn reads
/// them.
fn shorter_row_seen(node : Bool, said : String, alts : Array[String], widths : Array[Double]) -> Array[String] {
  let w = @signals.signal(widths[0])
  // (as wide as its words: no w of its own)
  let look = secondary.then(one_line)
  let t = if node {
    @ui.Tester::new(fn(_c) {  }, w=390.0, h=300.0, platform=2)
  } else {
    @ui.Tester::new(fn(c) {
      c.box(dir=Row, w=Px(w.get()), fn() {
        c.text(said, style=look, shorter=alts) |> ignore
        c.box(w=Px(40.0), h=Px(10.0), bg=0x996633FFL, fn() {  }) |> ignore
      })
      |> ignore
    }, w=390.0, h=300.0, platform=2)
  }
  if node {
    @ui.set_view_app(fn(root) {
      root.lines_up(Is(Some(Start))) |> ignore
      root.box(fn(r) {
        r.row(Is(true)).width(By(fn() { Some(w.get()) })) |> ignore
        words_node(r, fn() { said }, fn() { look }).shorter(Is(alts)).allow_ellipsis(Is(true)) |> ignore
        r.box(fn(b) { b.width(Is(Some(40.0))).height(Is(Some(10.0))).ground(Is(0x996633FFL)) |> ignore }) |> ignore
      })
      |> ignore
    })
  }
  let out = []
  for x in widths {
    w.set(x)
    t.draw()
    t.draw()
    let drawn = t.drawn_instances_keyed().map(fn(a) {
      a.mapi(fn(j, v) { if a[5] == 1.0 && (j == 12 || j == 13) { "-" } else { ((v * 100.0).round() / 100.0).to_string() } }).join(",")
    })
    drawn.sort()
    for d in drawn {
      out.push("at \{x}: " + d)
    }
  }
  out
}

///|
test "words saying shorter ones as wide as what of them is drawn, a box beside them where their row puts it, as the old view's: their own, a shorter one, the last cut short" {
  let widths = [300.0, 120.0, 70.0, 50.0, 300.0]
  let made = shorter_row_seen(true, "2026 年 5 月", ["5 月", "5"], widths)
  let old = shorter_row_seen(false, "2026 年 5 月", ["5 月", "5"], widths)
  assert_true(old.length() > 0)
  if made != old {
    let only_old = old.filter(fn(x) { !made.contains(x) })
    let only_made = made.filter(fn(x) { !old.contains(x) })
    fail("old's alone:\n  \{only_old.join("\n  ")}\nmade's alone:\n  \{only_made.join("\n  ")}")
  }
}

///|
/// Where a box 40 wide stands after words saying shorter ones in a row 50 wide (as nodes), the words given way and
/// made as narrow as `setup` says of them, then as `change` changes them (the same node): its x before and after.
fn give_way_seen(setup : (@view.View) -> Unit, change : (@ui.Tester) -> Unit) -> (Double, Double) {
  let t = @ui.Tester::new(fn(_c) {  }, w=390.0, h=300.0, platform=2)
  @ui.set_view_app(fn(root) {
    root.lines_up(Is(Some(Start))) |> ignore
    root.box(fn(r) {
      r.row(Is(true)).width(Is(Some(50.0))) |> ignore
      setup(words_node(r, fn() { "2026 年 5 月" }, fn() { secondary.then(one_line) }))
      r.box(fn(b) { b.width(Is(Some(40.0))).height(Is(Some(10.0))).ground(Is(0x996633FFL)) |> ignore }) |> ignore
    })
    |> ignore
  })
  let box_x = fn() {
    t.draw()
    t.draw()
    match @ui.view_tree().unwrap().drawn().search_by(fn(d) { d.ground == 0x996633FFL }) {
      Some(i) => @ui.view_tree().unwrap().drawn()[i].x
      None => -1.0
    }
  }
  let before = box_x()
  change(t)
  (before, box_x())
}

///|
test "words saying shorter ones give way along their row down to the last of them as they look now; what is said of how they give way and how narrow they may be theirs, said before or after; saying none, as ever" {
  let alts = @signals.signal(["5 月", "5"])
  // (giving way down to the last, "5": the box beside them where that leaves it, not past the row)
  let (given, _) = give_way_seen(fn(w) { w.shorter(By(fn() { alts.get() })) |> ignore }, fn(_) {  })
  assert_true(given > 0.0 && given <= 10.5, msg="given way: \{given}")
  // (said not to give way, before or after: as wide as the shorter one that fits the row)
  let (kept_after, _) = give_way_seen(fn(w) { w.shorter(Is(["5 月", "5"])).shrink(Is(0.0)) |> ignore }, fn(_) {  })
  let (kept_before, _) = give_way_seen(fn(w) { w.shrink(Is(0.0)).shorter(Is(["5 月", "5"])) |> ignore }, fn(_) {  })
  assert_true(kept_after > 10.5 && kept_after == kept_before, msg="not giving way: \{kept_after}, \{kept_before}")
  // (said how narrow, before or after: that)
  let (least_after, _) = give_way_seen(fn(w) { w.shorter(Is(["5 月", "5"])).min_width(Is(Some(20.0))) |> ignore }, fn(_) {  })
  let (least_before, _) = give_way_seen(fn(w) { w.min_width(Is(Some(20.0))).shorter(Is(["5 月", "5"])) |> ignore }, fn(_) {  })
  assert_true(least_after == 20.0 && least_before == 20.0, msg="as narrow as said: \{least_after}, \{least_before}")
  // (the same node saying none now: as words give way of themselves, none, as wide as they are)
  let none_said = @signals.signal(["5 月", "5"])
  let (with_some, with_none) = give_way_seen(fn(w) { w.shorter(By(fn() { none_said.get() })) |> ignore }, fn(_) { none_said.set([]) })
  assert_true(with_none > 50.0 && with_some <= 10.5, msg="saying none: \{with_some} then \{with_none}")
  // (the system's words larger, the same node: as narrow as the last of them is now, wider)
  let (small, large) = give_way_seen(fn(w) { w.shorter(Is(["5 月", "5"])) |> ignore }, fn(t) { t.set_font_scale(2.0) })
  assert_true(large > small, msg="the last as wide as it is now: \{small} then \{large}")
}

///|
test "said not cut short (View::cuts false) after it was said to give way, it gives way nowhere, whatever is said after it or its shorter words come to: a box 100 wide in a row 50 wide, words saying shorter ones" {
  let t = @ui.Tester::new(fn(_c) {  }, w=390.0, h=300.0, platform=2)
  let alts = @signals.signal(["5 月", "5"])
  let least = @signals.signal(0.0)
  @ui.set_view_app(fn(root) {
    root.lines_up(Is(Some(Start))) |> ignore
    root.box(fn(r) {
      r.row(Is(true)).width(Is(Some(50.0))) |> ignore
      r.box(fn(b) {
        b.width(Is(Some(100.0))).height(Is(Some(10.0))).ground(Is(0x336699FFL)).shrink(Is(1.0)).cuts(Is(false)).min_width(By(fn() { Some(least.get()) }))
        |> ignore
      })
      |> ignore
    })
    |> ignore
    root.box(fn(r) {
      r.row(Is(true)).width(Is(Some(50.0))) |> ignore
      words_node(r, fn() { "2026 年 5 月" }, fn() { secondary.then(one_line) }).shorter(By(fn() { alts.get() })).cuts(Is(false)).ground(Is(0x996633FFL))
      |> ignore
      // (a box beside them their row has not the room for: they keep the room the shorter one fitting it takes)
      r.box(fn(b) { b.width(Is(Some(40.0))).height(Is(Some(10.0))) |> ignore }) |> ignore
    })
    |> ignore
  })
  let w_of = fn(ink : Int64) {
    t.draw()
    t.draw()
    match @ui.view_tree().unwrap().drawn().search_by(fn(d) { d.ground == ink }) {
      Some(i) => @ui.view_tree().unwrap().drawn()[i].w
      None => -1.0
    }
  }
  assert_eq(w_of(0x336699FFL), 100.0, msg="the box, as said")
  let words = w_of(0x996633FFL)
  // (as wide as "5 月", the first shorter one the row's 50 has: not given way to "5", 10 left beside the box)
  assert_true(words > 10.5, msg="the words not given way: \{words}")
  // (what is said after, and what its words come to: still none)
  least.set(1.0)
  // (two again, other ones: the first fits the 50 alone but not the 10 beside the box, the last does)
  alts.set(["6 月", "6"])
  t.set_font_scale(1.5)
  assert_eq(w_of(0x336699FFL), 100.0, msg="the box, said how narrow after")
  assert_true(w_of(0x996633FFL) > 10.5, msg="the words, other shorter ones, larger: \{w_of(0x996633FFL)}")
}

///|
test "words saying shorter ones in a column: as narrow as nothing there, cut to the column's width (their least along a row alone)" {
  let t = @ui.Tester::new(fn(_c) {  }, w=390.0, h=300.0, platform=2)
  @ui.set_view_app(fn(root) {
    root.lines_up(Is(Some(Start))) |> ignore
    root.box(fn(c) {
      c.width(Is(Some(4.0))).clips(Is(true)) |> ignore
      words_node(c, fn() { "2026 年 5 月" }, fn() { secondary.then(one_line) }).shorter(Is(["5 月", "5"])).ground(Is(0x996633FFL)) |> ignore
    })
    |> ignore
  })
  t.draw()
  t.draw()
  let w = match @ui.view_tree().unwrap().drawn().search_by(fn(d) { d.ground == 0x996633FFL }) {
    Some(i) => @ui.view_tree().unwrap().drawn()[i].w
    None => -1.0
  }
  assert_eq(w, 4.0, msg="as wide as the column")
}

///|
test "words saying shorter ones, then in pieces (View::words_runs): giving way and as narrow as nothing again, as words in pieces are; words alone again, as their shorter ones say" {
  let t = @ui.Tester::new(fn(_c) {  }, w=390.0, h=300.0, platform=2)
  let pieces = @signals.signal(false)
  @ui.set_view_app(fn(root) {
    root.lines_up(Is(Some(Start))) |> ignore
    root.box(fn(r) {
      r.row(Is(true)).width(Is(Some(50.0))) |> ignore
      r.box(fn(w) {
        w.words(Is("2026 年 5 月"), look=@ui.style_words(secondary.then(one_line))).shorter(Is(["5 月", "5"])) |> ignore
        // (the same node's words said in pieces from then on: its words' binding said anew)
        w.reacts(fn() { pieces.get() }, fn(on) {
          if on {
            w.words_runs(Is([@view.words_run("2026 年 5 月")]), look=@ui.style_words(secondary.then(one_line))) |> ignore
          }
        })
      })
      |> ignore
      r.box(fn(b) { b.width(Is(Some(40.0))).height(Is(Some(10.0))).ground(Is(0x996633FFL)) |> ignore }) |> ignore
    })
    |> ignore
  })
  let box_x = fn() {
    t.draw()
    t.draw()
    match @ui.view_tree().unwrap().drawn().search_by(fn(d) { d.ground == 0x996633FFL }) {
      Some(i) => @ui.view_tree().unwrap().drawn()[i].x
      None => -1.0
    }
  }
  let alone = box_x()
  pieces.set(true)
  let in_pieces = box_x()
  assert_true(in_pieces > alone, msg="in pieces, given way as words in pieces are (none): \{alone} then \{in_pieces}")
}

///|
/// A page titled 用量 with 分享 and a choice of days (seg_head_node) at its title's line's end, at the system's size of
/// words twice as large in a window `w` wide: the window's tree, made once; what made it (its actions made how many
/// times), its title's words, 分享 and the choice.
fn titled_ends(
  w : Double,
  title? : String = "用量",
  scale? : Double = 2.0,
) -> (@ui.Tester, Ref[Int], Ref[Int], @signals.Signal[Int], Ref[@view.View?], Ref[@view.View?]) {
  let at = @signals.signal(0)
  let shared = Ref(0)
  let made = Ref(0)
  let share : Ref[@view.View?] = Ref(None)
  let seg : Ref[@view.View?] = Ref(None)
  // (the presenters as the app begins: what a test before this one left presented is over this page else, its press
  // that one's)
  presenters_reset()
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w~, h=600.0, platform=2)
  t.set_font_scale(scale)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.box(fn(b) {
      b.height(Is(Some(600.0))) |> ignore
      page_node(b, fn() { title }, fn() { [] }, fn(_, _) {  }, on_back=fn() {  }, actions=fn(a) {
        made.val += 1
        share.val = Some(icon_button_node(a, "share", fn() { "分享卡片" }, fn() { shared.val += 1 }))
        seg.val = Some(seg_head_node(a, fn() { ["7 天", "30 天"] }, fn() { at.get() }, fn(k) { at.set(k) }))
      })
    })
    |> ignore
    @ui.old(root, fn(c) { presented(c) }).over(Is(true)) |> @ui.old_takes_own |> ignore
    presented_nodes(root)
  })
  t.run_for(@ui.move_most_ms)
  (t, made, shared, at, share, seg)
}

///|
/// Where the title's words, 分享 and the choice are drawn now (x, y, w, h each).
fn ends_drawn(
  share : Ref[@view.View?],
  seg : Ref[@view.View?],
  title? : String = "用量",
) -> ((Double, Double, Double, Double), (Double, Double, Double, Double), (Double, Double, Double, Double)) raise {
  let tree = @ui.view_tree().unwrap()
  let title = match tree.drawn().search_by(fn(d) { d.words == title }) {
    Some(i) => tree.drawn()[i]
    None => fail("the title drawn")
  }
  ((title.x, title.y, title.w, title.h), share.val.unwrap().rect(), seg.val.unwrap().rect())
}

///|
test "a page's title with 分享 and a choice of days at its line's end, where even their least has not the room beside the title's (220 wide, words twice as large): those two under the title, together, at the line's end; each within the window and none over another, 分享 pressed, either day chosen (the choice its chosen one and a pick: seg_head_node's)" {
  let (t, made, shared, at, share, seg) = titled_ends(220.0)
  let (title, sh, sg) = ends_drawn(share, seg)
  for p in [("title", title), ("分享", sh), ("the choice", sg)] {
    let (x, y, w, h) = p.1
    assert_true(x >= 0.0 && x + w <= 220.0 + 0.01 && y >= 0.0 && w > 0.0 && h > 0.0, msg="\{p.0} within the window: \{Repr(p.1)}")
  }
  // (under the title, 分享 then the choice, the choice's end the line's: 16 in from the window's)
  assert_true(sh.1 >= title.1 + title.3 && sg.1 >= title.1 + title.3, msg="under the title: \{Repr(title)} \{Repr(sh)} \{Repr(sg)}")
  assert_true(sh.0 + sh.2 <= sg.0 + 0.01, msg="分享 before the choice: \{Repr(sh)} \{Repr(sg)}")
  assert_true((sg.0 + sg.2 - 204.0).abs() < 0.01, msg="the choice's end the line's: \{Repr(sg)}")
  t.tap(sh.0 + sh.2 / 2.0, sh.1 + sh.3 / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(shared.val, 1, msg="分享 pressed once")
  // (the other day: by a tap on it where both show, else from the pick the chosen one opens; then back)
  let tree = @ui.view_tree().unwrap()
  for k in [1, 0] {
    let other = if k == 1 { "30 天" } else { "7 天" }
    if !tree.drawn().iter().any(fn(d) { d.words == other }) {
      t.tap(sg.0 + sg.2 / 2.0, sg.1 + sg.3 / 2.0)
      t.run_for(@ui.move_most_ms)
    }
    t.tap_text(other)
    t.run_for(@ui.move_most_ms)
    assert_eq(at.get(), k, msg="\{other} chosen")
  }
  assert_eq(made.val, 1, msg="made once")
}

///|
test "a page's title with what it does at its line's end, its window narrowed and widened across where their least has the room beside each other (words twice as large): on one line, the title at its least or more, then under it, each width as it was coming either way; nothing made again" {
  let (t, made, _, _, share, seg) = titled_ends(390.0)
  // (each width, from 390 down to 220 and up again: one line or two, and where each is)
  let seen : Map[Int, String] = Map([])
  let mut lines_at : Int? = None
  let widths = []
  for w = 390; w >= 220; w = w - 2 {
    widths.push(w)
  }
  for w = 222; w <= 390; w = w + 2 {
    widths.push(w)
  }
  for w in widths {
    t.resize(w.to_double(), 600.0)
    t.run_for(@ui.move_most_ms)
    let (title, sh, sg) = ends_drawn(share, seg)
    let one = sh.1 < title.1 + title.3 && sg.1 < title.1 + title.3
    // (the choice's end the line's either way; on one line the title at least 80 wide, before 分享)
    assert_true((sg.0 + sg.2 - (w.to_double() - 16.0)).abs() < 0.01, msg="\{w}: the choice's end the line's: \{Repr(sg)}")
    if one {
      assert_true(sh.0 - 16.0 >= 80.0 + 10.0 - 0.01, msg="\{w}: the title at its least: \{Repr(title)} \{Repr(sh)}")
    } else {
      assert_true(sh.1 >= title.1 + title.3 && sg.1 >= title.1 + title.3, msg="\{w}: under the title")
    }
    // (one line from some width up, two under it: never one line narrower than two)
    match lines_at {
      None => if !one { lines_at = Some(w) }
      Some(under) => if one { assert_true(w > under, msg="\{w}: one line under \{under}") }
    }
    let now = "\{@ui.rect_text(title)} \{@ui.rect_text(sh)} \{@ui.rect_text(sg)}"
    match seen.get(w) {
      Some(was) => assert_eq(now, was, msg="\{w}: as it was coming the other way")
      None => seen[w] = now
    }
    // (and the same frame after frame)
    t.draw()
    let (title2, sh2, sg2) = ends_drawn(share, seg)
    assert_eq("\{@ui.rect_text(title2)} \{@ui.rect_text(sh2)} \{@ui.rect_text(sg2)}", now, msg="\{w}: still")
  }
  assert_true(lines_at is Some(_), msg="two lines somewhere at 220…390")
  assert_true(seen.get(390).unwrap() != seen.get(220).unwrap())
  assert_eq(made.val, 1, msg="made once")
}
