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
          let rows = fn() {
            for i, s in choice_rows {
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
            }
          }
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
      let rows = fn(col : @view.View) {
      for s in choice_rows {
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
  guard all.length() == 2 else { abort("\{label}: \{all.length()} rows") }
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
  let about = "\{look} on \{platform}, card \{card}"
  let pressed : Map[String, Int] = {}
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
    t.move(o.rect.0 + 30.0, o.rect.1 + o.rect.3 / 2.0)
    t.draw()
    let old_lit = drawn_within(t, o.rect)
    t.move(n.rect.0 + 30.0, n.rect.1 + n.rect.3 / 2.0)
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
