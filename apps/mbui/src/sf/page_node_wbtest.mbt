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
  let all = t.drawn_instances().map(fn(a) {
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
