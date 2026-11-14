// A row of a list of choices as a node of the window's tree (choice_row_node) beside the old one (choice_row), each
// given the same: narrow and wide, with touch and with keyboard and mouse; drawn the same where they are (their
// instances, in their own terms), at rest, pointed at and pressed; read out the same; pressed, each its own.

///|
/// What a row beside its old one is given: its label, chosen, its note, a lead, its label's ink, unable; words after
/// its label on its line (a tag), words at its end before its check (a trail); its own words in place of all of it (a
/// body).
priv struct ChoiceSaid {
  label : String
  chosen : Bool
  note : String
  lead : Bool
  red : Bool
  disabled : Bool
  tag : String
  trail : String
  body : String
}

///|
/// The rows each side has, top to bottom: one chosen with a mark before it and a note, one in red with a note, one
/// alone, one that cannot be chosen.
let choice_rows : Array[ChoiceSaid] = [
  { ..choice_plain, label: "压缩上下文", chosen: true, note: "保留摘要，释放上下文空间", lead: true },
  { ..choice_plain, label: "清空上下文", note: "结束当前进程，下一条消息开始新的会话", red: true },
  { ..choice_plain, label: "自动" },
  { ..choice_plain, label: "林的 Max", note: "离线", lead: true, disabled: true },
  { ..choice_plain, label: "整理发布清单", chosen: true, tag: "在 still.fail 里", trail: "3 分钟前", lead: true },
  { ..choice_plain, label: "第二个会话", note: "Willow · ~/Projects", tag: "在 still.fail 里", trail: "昨天" },
  { ..choice_plain, label: "思源黑体", chosen: true, body: "思源黑体 · 已下载" },
]

///|
/// A row given nothing but its label.
let choice_plain : ChoiceSaid = {
  label: "",
  chosen: false,
  note: "",
  lead: false,
  red: false,
  disabled: false,
  tag: "",
  trail: "",
  body: "",
}

///|
/// The old rows (an old view's, its left column) and the node's (its right) side by side, laid out `look`, on a window
/// of `platform`; how many times each was pressed, by side and label, in `pressed`.
fn choice_rows_tester(look : Look, platform : Int, pressed : Map[String, Int], card? : Bool = false) -> @ui.Tester {
  let t = @ui.Tester::new(fn(_c) {  }, w=800.0, h=600.0, platform~)
  t.check_looks(false)
  let count = fn(k : String) { pressed[k] = pressed.get(k).unwrap_or(0) + 1 }
  @ui.set_view_app(fn(root) {
    root.row(Is(true)) |> ignore
    root.box(fn(h) {
      h.width(Is(Some(360.0))) |> ignore
      @ui.old(h, fn(c) {
        with_look(look, fn() {
          let rows = fn() { old_choice_rows(c, count) }
          // (on a card: a group's, its rows on it)
          if card {
            group(c, rows)
          } else {
            c.box(w=Fill(1.0), rows) |> ignore
          }
        })
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
    root.box(fn(g) { g.width(Is(Some(40.0))) |> ignore }) |> ignore
    root.box(fn(col) {
      col.width(Is(Some(360.0))) |> ignore
      look_lent(col, look)
      let rows = fn(col : @view.View) { node_choice_rows(col, count) }
      if card {
        group_node(col, rows)
      } else {
        rows(col)
      }
    })
    |> ignore
  })
  t.draw()
  t
}

///|
/// The old row (left) and the node's (right) read out as `label`.
fn choice_pair(t : @ui.Tester, label : String) -> (@ui.SemNode, @ui.SemNode) {
  let all = t.all(Button, label~)
  guard all.length() == 2 else { @halt.saying("\{label}: \{all.length()} rows") }
  if all[0].rect.0 < all[1].rect.0 { (all[0], all[1]) } else { (all[1], all[0]) }
}

///|
/// The words drawn within `rect`, each where it is in the rect's own terms, how big, how opaque.
fn words_within(t : @ui.Tester, rect : (Double, Double, Double, Double)) -> Array[String] {
  let (rx, ry, rw, rh) = rect
  t
  .words()
  .filter(fn(w) { w.1 >= rx - 0.5 && w.2 >= ry - 0.5 && w.1 <= rx + rw + 0.5 && w.2 <= ry + rh + 0.5 })
  .map(fn(w) { "\{w.0}@\{w.1 - rx},\{w.2 - ry} \{w.3}x\{w.4} a\{w.5}" })
}

///|
/// Each row of the two sides, as it stands, pointed at and pressed (a finger's, held a while), drawn the same in its
/// own terms, its words where the old one's are; read out the same; each pressed alone where it can be.
fn choice_rows_same(look : Look, platform : Int, card? : Bool = false) -> Unit raise {
  let about = "\{Repr(look)} on \{platform}, card \{card}"
  let pressed : Map[String, Int] = Map([])
  let t = choice_rows_tester(look, platform, pressed, card~)
  for s in choice_rows {
    let (o, n) = choice_pair(t, s.label)
    let at = "\{about}, \{s.label}"
    assert_eq((o.rect.1, o.rect.2, o.rect.3), (n.rect.1, n.rect.2, n.rect.3), msg="\{at}: where and how big")
    assert_eq((o.selected, o.disabled), (n.selected, n.disabled), msg="\{at}: read out")
    t.leave()
    t.draw()
    assert_eq(drawn_within(t, o.rect), drawn_within(t, n.rect), msg="\{at}: at rest")
    assert_eq(words_within(t, o.rect), words_within(t, n.rect), msg="\{at}: its words")
    // pointed at: the old one, then the node
    t.move_to(o.rect.0 + 30.0, o.rect.1 + o.rect.3 / 2.0)
    t.draw()
    let old_lit = drawn_within(t, o.rect)
    t.move_to(n.rect.0 + 30.0, n.rect.1 + n.rect.3 / 2.0)
    t.draw()
    assert_eq(old_lit, drawn_within(t, n.rect), msg="\{at}: pointed at")
    t.leave()
    t.draw()
    // pressed and held (a ripple under a finger), then let go: done once, where it can be
    for side in [(o, "old"), (n, "new")] {
      let (r, name) = side
      let (x, y) = (r.rect.0 + 30.0, r.rect.1 + r.rect.3 / 2.0)
      t.press_at(x, y)
      t.run_for(@motion.ripple_tap_ms)
      let held = drawn_within(t, r.rect)
      t.release(x, y)
      t.run_for(@ui.move_most_ms)
      if name == "old" {
        held_drawn.val = held
      } else {
        assert_eq(held_drawn.val, held, msg="\{at}: held")
      }
    }
    let want = if s.disabled { 0 } else { 1 }
    assert_eq((pressed.get("old " + s.label).unwrap_or(0), pressed.get("new " + s.label).unwrap_or(0)), (want, want), msg="\{at}: pressed")
  }
}

///|
/// What the old row drew held, for its node to be set beside.
// kept across runs: written by each pair's old row before its node's is read
let held_drawn : Ref[Array[String]] = Ref([])

///|
test "a choice's row as a node beside the old one, narrow, with touch: drawn the same at rest, pointed at and held; read out the same; pressed alone" {
  choice_rows_same(Narrow, 2)
}

///|
test "a choice's row as a node beside the old one, narrow, with keyboard and mouse" {
  choice_rows_same(Narrow, 0)
}

///|
test "a choice's row as a node beside the old one, wide, with keyboard and mouse" {
  choice_rows_same(Wide, 0)
}

///|
test "a choice's row as a node beside the old one, wide, with touch" {
  choice_rows_same(Wide, 2)
}

///|
test "a choice's row as a node beside the old one, narrow, on a card (a group's), with touch and with keyboard and mouse" {
  choice_rows_same(Narrow, 2, card=true)
  choice_rows_same(Narrow, 0, card=true)
}

///|
/// The old rows (choice_row's) in an old view `c`, each pressed told `count` as "old " and its label.
fn old_choice_rows(c : @ui.Ctx, count : (String) -> Unit) -> Unit {
  for i in 0..<choice_rows.length() {
    old_choice_row(c, i, count)
  }
}

///|
/// The old row (choice_row's) of `choice_rows[i]` in an old view `c`, pressed told `count` as "old " and its label.
fn old_choice_row(c : @ui.Ctx, i : Int, count : (String) -> Unit) -> Unit {
  let s = choice_rows[i]
  {
    choice_row(
      c,
      "choice/\{i}",
      s.chosen,
      s.label,
      note=s.note,
      lead?=if s.lead { Some(fn() { icon(c, "folder", size=18.0, color=theme().p.muted) |> ignore }) } else { None },
      ink?=if s.red { Some(theme().p.red) } else { None },
      disabled=s.disabled,
      tag?=if s.tag != "" { Some(fn() { c.text(s.tag, style=secondary) |> ignore }) } else { None },
      trail?=if s.trail != "" { Some(fn() { c.text(s.trail, style=secondary) |> ignore }) } else { None },
      body?=if s.body != "" { Some(fn() { c.text(s.body, style=body) |> ignore }) } else { None },
      on_press=fn() { count("old " + s.label) },
    )
    |> ignore
  }
}

///|
/// The node rows (choice_row_node's) in `col`, each pressed told `count` as "new " and its label.
fn node_choice_rows(col : @view.View, count : (String) -> Unit) -> Unit {
  for i in 0..<choice_rows.length() {
    node_choice_row(col, i, count)
  }
}

///|
/// The node row (choice_row_node's) of `choice_rows[i]` in `col`, pressed told `count` as "new " and its label.
fn node_choice_row(col : @view.View, i : Int, count : (String) -> Unit) -> Unit {
  let s = choice_rows[i]
  {
    choice_row_node(
      col,
      fn() { s.label },
      fn() { s.chosen },
      press=fn() { count("new " + s.label) },
      note=fn() { s.note },
      lead?=if s.lead { Some(fn(l : @view.View) { icon_node(l, "folder", 18.0, By(fn() { theme().p.muted })) |> ignore }) } else { None },
      ink?=if s.red { Some(fn() { theme().p.red }) } else { None },
      disabled=fn() { s.disabled },
      tag?=if s.tag != "" { Some(fn(v : @view.View) { words_node(v, fn() { s.tag }, fn() { secondary }) |> ignore }) } else { None },
      trail?=if s.trail != "" { Some(fn(v : @view.View) { words_node(v, fn() { s.trail }, fn() { secondary }) |> ignore }) } else { None },
      body?=if s.body != "" { Some(fn(v : @view.View) { words_node(v, fn() { s.body }, fn() { body }) |> ignore }) } else { None },
    )
  }
}

///|
/// What each row stood as in a panel's body (its label: where and how big, read out, drawn at rest, its words), and
/// how many times each was pressed: the rows the old panel holds (`old`), else the node panel's (panel_nodes), opened
/// on a window `at` by its 打开 (`pressed`: a sheet a press opened, a small panel beside it) or by nothing (a sheet, a
/// dialog in the middle of the window), at rest; each tapped once in its middle.
fn panel_choice_rows(at : (Int, Double, Double), pressed : Bool, old : Bool, listed? : Bool = false) -> (Array[String], Map[String, Int]) raise {
  let count : Map[String, Int] = Map([])
  let tally = fn(k : String) { count[k] = count.get(k).unwrap_or(0) + 1 }
  let open = fn(from : Anchor) {
    let from = if pressed { from } else { Unanchored }
    let n = choice_rows.length()
    if old {
      // (a list in a panel a share of the window tall, as the app's lists in panels are)
      panel("选一个", from~, tall=if listed { 0.8 } else { 0.0 }, fn(c, _) {
        if listed {
          panel_list(c, "choices", n, 60.0, fn(i) { old_choice_row(c, i, tally) }) |> ignore
        } else {
          old_choice_rows(c, tally)
        }
      })
    } else {
      // (as tall as what it holds up to its share, as the old one with a list is: hugs)
      panel_nodes("选一个", from~, tall=if listed { 0.8 } else { 0.0 }, hugs=listed, fn(v, _) {
        if listed {
          panel_list_node(v, fn() { Array::makei(n, fn(i) { i }) }, fn(b, i) { node_choice_row(b, i, tally) }, est=60.0) |> ignore
        } else {
          node_choice_rows(v, tally)
        }
      })
    }
  }
  presenters_reset()
  let (platform, w, h) = at
  // (every old view in still.fail's theme, as the app's window builds them (its view's with_theme round all of it): a
  // panel beside what opened it or in the middle of the window is an old view of its own, its head and body, which the
  // page's with_theme does not reach)
  let t = @ui.Tester::new(
    fn(c) { c.with_theme(ui_theme(), fn() { @ui.old_views_here(c) }) },
    tree=presented_tree(presenting_view(open)),
    w~,
    h~,
    platform~,
  )
  t.check_looks(false)
  t.draw()
  open_it(t)
  t.run_for(@ui.move_most_ms)
  t.leave()
  t.draw()
  let stood : Array[String] = []
  for s in choice_rows {
    let all = t.all(Button, label=s.label)
    guard all.length() == 1 else { fail("\{s.label}: \{all.length()} rows") }
    let r = all[0].rect
    // (each place to a thousandth of a point, as drawn_within has the draw list's: laid out by another sum, a place
    // the same differs in its last digits)
    let k = fn(v : Double) { (v * 1000.0).round() / 1000.0 }
    stood.push("\{s.label} at \{k(r.0)},\{k(r.1)} \{k(r.2)}x\{k(r.3)} selected \{@ui.some_text(all[0].selected)} unable \{all[0].disabled}")
    stood.push(drawn_within(t, r).join(" "))
    stood.push(
      t
      .words()
      .filter(fn(w) { w.1 >= r.0 - 0.5 && w.2 >= r.1 - 0.5 && w.1 <= r.0 + r.2 + 0.5 && w.2 <= r.1 + r.3 + 0.5 })
      .map(fn(w) { "\{w.0}@\{k(w.1 - r.0)},\{k(w.2 - r.1)} \{k(w.3)}x\{k(w.4)} a\{w.5}" })
      .join(" "),
    )
  }
  for s in choice_rows {
    let all = t.all(Button, label=s.label)
    guard all.length() == 1 else { fail("\{s.label}: \{all.length()} rows to tap") }
    let r = all[0].rect
    t.tap(r.0 + r.2 / 2.0, r.1 + r.3 / 2.0)
    t.run_for(@ui.move_most_ms)
  }
  (stood, count)
}

///|
test "a choice's row as a node in a panel's body where the old one stands: a sheet opened by nothing and by a press, a small panel beside what opened it, a dialog in the middle of the window, and in a panel's list" {
  for screen in [
    ("sheet opened by nothing", phone, false, false),
    ("sheet opened by a press", phone, true, false),
    ("small panel", (0, 800.0, 600.0), true, false),
    ("dialog", (0, 800.0, 600.0), false, false),
    ("a list in a sheet opened by nothing", phone, false, true),
    ("a list in a sheet opened by a press", phone, true, true),
  ] {
    let (about, at, pressed, listed) = screen
    let (old_stood, old_count) = panel_choice_rows(at, pressed, true, listed~)
    let (new_stood, new_count) = panel_choice_rows(at, pressed, false, listed~)
    assert_eq(new_stood.length(), old_stood.length(), msg=about)
    let differs : Array[String] = []
    for i, line in old_stood {
      if new_stood[i] != line {
        differs.push("\{about}: line \{i}:\n  old \{line}\n  new \{new_stood[i]}")
      }
    }
    if !differs.is_empty() {
      fail(differs.join("\n"))
    }
    for s in choice_rows {
      let want = if s.disabled { 0 } else { 1 }
      assert_eq(
        (old_count.get("old " + s.label).unwrap_or(0), new_count.get("new " + s.label).unwrap_or(0)),
        (want, want),
        msg="\{about}: \{s.label} pressed",
      )
    }
  }
}

