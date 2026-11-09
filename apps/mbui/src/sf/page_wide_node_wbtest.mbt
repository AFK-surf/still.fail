// A page made once laid out wide (page_wide_node.mbt): its sections, groups and rows drawn as page.mbt draws them wide;
// its arrangement by the width it is given, made again only as that arrangement changes, lent to what is made in it
// later as well.

///|
/// What tester `t` draws, each instance's numbers rounded to a hundredth (a glyph's place in its atlas left out), in
/// one order.
fn wide_drawn(t : @ui.Tester) -> Array[String] {
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
/// 关于's blocks on a wide page, 760 wide (a lane's column less its blocks' room), at the system's size of words
/// `scale`: as an old view's (`node` false) or as nodes, each a section of its own titled (heads false: a wide page's
/// title all the same), a list's rows, a card of words with a switch, a list's switch and a row that acts.
fn about_blocks_drawn(node : Bool, scale : Double) -> Array[String] {
  let t = if node {
    @ui.Tester::new(fn(_c) {  }, w=760.0, h=900.0)
  } else {
    @ui.Tester::new(
      fn(c) {
        with_look(Wide, fn() {
          c.box(style=@ui.css("w=Full"), fn() {
            section(c, heads=false, "版本", fn() {
              group(c, fn() {
                link_row(c, "", "still.fail 1.0", goes=false) |> ignore
                link_row(c, "v", "检查更新", note="已是最新版本", chevron=false) |> ignore
                link_row(c, "l", "更新日志") |> ignore
              })
            })
            section(c, heads=false, "隐私", fn() {
              group(c, card=true, fn() { switch_row(c, "r", "发送使用统计", true, note="帮助改进 still.fail") |> ignore })
            })
            section(c, heads=false, "法律", fn() {
              group(c, fn() { link_row(c, "t", "服务条款", out=true) |> ignore })
            })
            section(c, heads=false, "诊断", fn() {
              group(c, fn() {
                switch_row(c, "p", "性能记录", false, note="保存在本机") |> ignore
                link_row(c, "s", "分享记录", acts=true) |> ignore
              })
            })
          })
          |> ignore
        })
      },
      w=760.0,
      h=900.0,
    )
  }
  t.set_font_scale(scale)
  if node {
    @ui.set_view_app(fn(root) {
      root.box(fn(b) {
        b.lends(part_at, { look: Wide, section: false, list: false }) |> ignore
        section_node(b, fn() { "版本" }, heads=false, fn(s) {
          group_node(s, fn(g) {
            link_row_node(g, fn() { "still.fail 1.0" }, fn() {  }, goes=false)
            link_row_node(g, fn() { "检查更新" }, fn() {  }, note=fn() { "已是最新版本" }, chevron=false)
            link_row_node(g, fn() { "更新日志" }, fn() {  })
          })
        })
        section_node(b, fn() { "隐私" }, heads=false, fn(s) {
          group_node(s, card=true, fn(g) {
            switch_row_node(g, fn() { "发送使用统计" }, fn() { true }, fn(_) {  }, note=fn() { "帮助改进 still.fail" })
          })
        })
        section_node(b, fn() { "法律" }, heads=false, fn(s) {
          group_node(s, fn(g) { link_row_node(g, fn() { "服务条款" }, fn() {  }, out=true) })
        })
        section_node(b, fn() { "诊断" }, heads=false, fn(s) {
          group_node(s, fn(g) {
            switch_row_node(g, fn() { "性能记录" }, fn() { false }, fn(_) {  }, note=fn() { "保存在本机" })
            link_row_node(g, fn() { "分享记录" }, fn() {  }, acts=true)
          })
        })
      })
      |> ignore
    })
  }
  wide_drawn(t)
}

///|
test "关于's blocks as nodes on a wide page: titled sections, a list's rows, a card of words with a switch, a list's switch and a row that acts, drawn as the old view's at sizes of words 1 and 2" {
  for scale in [1.0, 2.0] {
    let old = about_blocks_drawn(false, scale)
    let made = about_blocks_drawn(true, scale)
    // (what differs said: what each draws alone)
    let alone = fn(a : Array[String], b : Array[String]) { a.filter(fn(x) { !b.contains(x) }).join("\n  ") }
    assert_eq(made, old, msg="at \{scale}: made's alone:\n  \{alone(made, old)}\nold's alone:\n  \{alone(old, made)}")
  }
}

///|
test "a page made once by the width it is given: made again only as its arrangement changes (wide to narrow), not as it widens or narrows within one; what is shown in it later laid out as the page is then" {
  let _t = @ui.Tester::new(fn(_c) {  }, w=900.0, h=700.0)
  let width = @signals.signal(900.0)
  let shown = @signals.signal(false)
  let made : Array[Look] = []
  let later : Array[Look] = []
  @ui.set_view_app(fn(root) {
    root.box(fn(b) {
      b.height(Is(Some(700.0))) |> ignore
      page_node(
        b,
        fn() { "关于" },
        fn() { ["a"] },
        fn(v, _k) {
          made.push(look_node(v))
          v.show(fn() { shown.get() }, fn(s) { later.push(look_node(s)) })
        },
        on_back=fn() {  },
        width=fn() { width.get() },
      )
    })
    |> ignore
  })
  _t.draw()
  assert_true(made == [Wide])
  // (narrower, wide still: nothing made again)
  width.set(700.0)
  _t.draw()
  assert_true(made == [Wide])
  // (shown later: as the page is laid out)
  shown.set(true)
  _t.draw()
  assert_true(later == [Wide])
  // (narrow now: made again, narrow, what shows in it as well)
  width.set(500.0)
  _t.draw()
  assert_true(made == [Wide, Narrow])
  assert_true(later == [Wide, Narrow])
}
