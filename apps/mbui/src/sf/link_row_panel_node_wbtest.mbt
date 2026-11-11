// A row that goes somewhere as a node (link_row_node) in a panel's body beside the old one (link_row) there, each given
// the same rows: a sheet opened by nothing and by a press, a small panel beside what opened it, a dialog in the middle
// of the window, rows in a panel's list in a sheet opened by nothing and by a press; each row where and as big as the
// old one, drawn the same at rest, its words where the old one's are, read out the same, pressed once.

///|
/// What a row beside its old one is given: its title, a note under it, a mark before it, what it says at its end.
priv struct LinkSaid {
  title : String
  note : String
  lead : Bool
  value : String
}

///|
/// The rows each side has, top to bottom: one with a mark and a note (a place's, a folder's), one with a note, one
/// alone, one saying something at its end.
let link_rows : Array[LinkSaid] = [
  { title: "文档", note: "/Users/lin/文档", lead: true, value: "" },
  { title: "会议记录", note: "昨天", lead: false, value: "" },
  { title: "主目录", note: "", lead: false, value: "" },
  { title: "排序", note: "", lead: true, value: "按名称" },
]

///|
/// The old row (link_row's) of `link_rows[i]` in an old view `c`, pressed told `count` as "old " and its title.
fn old_link_row(c : @ui.Ctx, i : Int, count : (String) -> Unit) -> Unit {
  let s = link_rows[i]
  link_row(
    c,
    "link/\{i}",
    s.title,
    note=s.note,
    value=s.value,
    lead?=if s.lead { Some(fn() { icon(c, "folder", size=20.0, color=theme().p.muted) |> ignore }) } else { None },
    on_press=fn() { count("old " + s.title) },
  )
  |> ignore
}

///|
/// The node row (link_row_node's) of `link_rows[i]` in `col`, pressed told `count` as "new " and its title.
fn node_link_row(col : @view.View, i : Int, count : (String) -> Unit) -> Unit {
  let s = link_rows[i]
  link_row_node(
    col,
    fn() { s.title },
    fn() { count("new " + s.title) },
    note=fn() { s.note },
    value=fn() { s.value },
    lead=if s.lead { LeadLine(fn(l) { icon_node(l, "folder", 20.0, By(fn() { theme().p.muted })) |> ignore }) } else { NoLead },
  )
}

///|
/// What each row stood as in a panel's body (its title: where and how big, read out, drawn at rest, its words), and how
/// many times each was pressed: the rows the old panel holds (`old`), else the node panel's (panel_nodes), opened on a
/// window `at` by its 打开 (`pressed`) or by nothing, in a list a share of the window tall where `listed`; at rest;
/// each tapped once in its middle.
fn panel_link_rows(at : (Int, Double, Double), pressed : Bool, old : Bool, listed? : Bool = false) -> (Array[String], Map[String, Int]) raise {
  let count : Map[String, Int] = Map([])
  let tally = fn(k : String) { count[k] = count.get(k).unwrap_or(0) + 1 }
  let n = link_rows.length()
  let open = fn(from : Anchor) {
    let from = if pressed { from } else { Unanchored }
    if old {
      panel("去哪里", from~, tall=if listed { 0.8 } else { 0.0 }, fn(c, _) {
        if listed {
          panel_list(c, "links", n, 60.0, fn(i) { old_link_row(c, i, tally) }) |> ignore
        } else {
          for i in 0..<n {
            old_link_row(c, i, tally)
          }
          // (words under the rows, the last row not at the dialog's foot: the old row's ground in a dialog's corner
          // breaks the corner rule there, the old view's own)
          c.text("以上", style=link_rows_end) |> ignore
        }
      })
    } else {
      panel_nodes("去哪里", from~, tall=if listed { 0.8 } else { 0.0 }, hugs=listed, fn(v, _) {
        if listed {
          panel_list_node(v, fn() { Array::makei(n, fn(i) { i }) }, fn(b, i) { node_link_row(b, i, tally) }, est=60.0) |> ignore
        } else {
          for i in 0..<n {
            node_link_row(v, i, tally)
          }
          words_node(v, fn() { "以上" }, fn() { link_rows_end }) |> ignore
        }
      })
    }
  }
  presenters_reset()
  let (platform, w, h) = at
  // (every old view in still.fail's theme, as the app's window builds them: a panel's head and body are old views of
  // their own, which a page's with_theme does not reach)
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
  let k = fn(v : Double) { (v * 1000.0).round() / 1000.0 }
  for s in link_rows {
    let all = t.all(Link, label=s.title)
    guard all.length() == 1 else { fail("\{s.title}: \{all.length()} rows") }
    let r = all[0].rect
    stood.push("\{s.title} at \{k(r.0)},\{k(r.1)} \{k(r.2)}x\{k(r.3)}")
    stood.push(drawn_within(t, r).join(" "))
    stood.push(
      t
      .words()
      .filter(fn(w) { w.1 >= r.0 - 0.5 && w.2 >= r.1 - 0.5 && w.1 <= r.0 + r.2 + 0.5 && w.2 <= r.1 + r.3 + 0.5 })
      // (where its words start and how high, not how wide their box: an old row's title is as wide as its line (w=Full),
      // the node's as its words, their glyphs the same where they are: drawn_within)
      .map(fn(w) { "\{w.0}@\{k(w.1 - r.0)},\{k(w.2 - r.1)} h\{k(w.4)} a\{w.5}" })
      .join(" "),
    )
  }
  for s in link_rows {
    let all = t.all(Link, label=s.title)
    guard all.length() == 1 else { fail("\{s.title}: \{all.length()} rows to tap") }
    let r = all[0].rect
    t.tap(r.0 + r.2 / 2.0, r.1 + r.3 / 2.0)
    t.run_for(@ui.move_most_ms)
    // (each opened again for the next: a press on one closes nothing, it only goes)
  }
  (stood, count)
}

///|
test "a row that goes somewhere as a node in a panel's body where the old one stands: a sheet opened by nothing and by a press, a small panel beside what opened it, a dialog in the middle of the window, and in a panel's list" {
  for screen in [
    ("sheet opened by nothing", phone, false, false),
    ("sheet opened by a press", phone, true, false),
    ("small panel", (0, 800.0, 600.0), true, false),
    ("dialog", (0, 800.0, 600.0), false, false),
    ("a list in a sheet opened by nothing", phone, false, true),
    ("a list in a sheet opened by a press", phone, true, true),
  ] {
    let (about, at, pressed, listed) = screen
    let (old_stood, old_count) = panel_link_rows(at, pressed, true, listed~)
    let (new_stood, new_count) = panel_link_rows(at, pressed, false, listed~)
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
    for s in link_rows {
      assert_eq(
        (old_count.get("old " + s.title).unwrap_or(0), new_count.get("new " + s.title).unwrap_or(0)),
        (1, 1),
        msg="\{about}: \{s.title} pressed",
      )
    }
  }
}

///|
/// The words under the rows (not a row's: the panel's).
// kept across runs: a value (no field of it changes)
let link_rows_end : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted)
