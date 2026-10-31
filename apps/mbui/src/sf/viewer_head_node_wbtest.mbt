// The floating bar of a file opened in the Small tier as nodes (viewer_head_node) beside the old one (viewer_head), each
// in the same state, alone in a window as wide: drawn the same (its glass, its name cut short, its tools, ×), read out
// the same; what it says changed once made (its name, another tool) drawn as the old one is then; never narrower once
// open; there and gone as it is awake, from where it is at that moment.

///|
/// What a head shows (head_tester's): the file's name, which tools it has (by their icons, × after them).
struct HeadState {
  name : @signals.Signal[String]
  tools : @signals.Signal[Array[String]]
  awake : @signals.Signal[Bool]
  closed : Ref[Int]
}

///|
fn HeadState::new(name : String, tools : Array[String]) -> HeadState {
  {
    name: @signals.signal(name, same=fn(a, b) { a == b }),
    tools: @signals.signal(tools, same=fn(a, b) { a == b }),
    awake: @signals.signal(true, same=fn(a, b) { a == b }),
    closed: Ref(0),
  }
}

///|
/// The tool `icon`'s words (its label, read out).
fn head_label(icon : String) -> String {
  "tool " + icon
}

///|
/// A window `w` wide with the head in it: the old one's (`old`: an old view's over all of it, its widest kept from
/// frame to frame as vf_bar keeps it) or the node's, saying what `s` says.
fn head_tester(s : HeadState, old : Bool, w? : Double = 390.0) -> @ui.Tester {
  let t = @ui.Tester::new(fn(_c) {  }, w~, h=300.0, platform=0)
  t.check_looks(false)
  let ink = page_viewer_ink()
  let widest = Ref(0.0)
  @ui.set_view_app(fn(root) {
    if old {
      @ui.old(root, fn(c) {
        let (closed, wide) = viewer_head(c, "h", s.name.get(), "", s.awake.get(), widest.val, 1.0, ink, fn() {
          for icon in s.tools.get() {
            viewer_tool(c, "h/" + icon, icon, head_label(icon), ink) |> ignore
          }
        })
        if wide > widest.val {
          widest.val = wide
        }
        if closed {
          s.closed.val += 1
        }
      }).over(Is(true))
      |> ignore
    } else {
      viewer_head_node(
        root,
        fn() { s.name.get() },
        fn() { "" },
        fn() { s.awake.get() },
        fn(_) { 1.0 },
        fn() { (viewer_host().room)().0 },
        fn() { w },
        fn() { page_viewer_ink() },
        fn() { viewer_page_glass() },
        fn(row) {
          // (each it can have in its place, there while said)
          for icon in head_icons {
            row.show(fn() { s.tools.get().contains(icon) }, fn(r) {
              tool_node(r, fn() { { icon, label: head_label(icon), on: false, disabled: false } }, fn() { page_viewer_ink() }, Is(tool_side / 2.0), fn() {  })
              |> ignore
            })
          }
        },
        fn() { s.tools.get().join(",") },
        fn() { s.closed.val += 1 },
      )
      |> ignore
    }
  })
  t.draw()
  t
}

///|
/// What the head draws (all of the window but its foot), and where its × is read out.
fn head_drawn(tt : @ui.Tester) -> (Array[String], (Double, Double, Double, Double)) raise {
  let x = tt.get(Button, label=t("web-main.preview.closeKey"))
  (drawn_within(tt, (0.0, 0.0, tt.ctx().width, 120.0)), x.rect)
}

///|
test "the floating head as nodes beside the old one: drawn the same, its × where the old one's is; another name (cut short), another tool, as the old one draws them then" {
  let states : Array[(String, String, Array[String])] = [
    ("a name and two tools", "photo.png", ["edit", "copy"]),
    ("a name too long for its room, cut short", "a-very-long-name-of-a-picture-sent-from-far-away-2026-10-31.png", ["edit", "copy", "download"]),
    ("no tool but ×", "photo.png", []),
  ]
  for st in states {
    let (what, name, tools) = st
    let olds = HeadState::new(name, tools)
    let news = HeadState::new(name, tools)
    let (old_drawn, old_x) = head_drawn(head_tester(olds, true))
    let (new_drawn, new_x) = head_drawn(head_tester(news, false))
    assert_eq(new_x, old_x, msg="\{what}: ×")
    assert_eq(new_drawn, old_drawn, msg="\{what}: new \{new_drawn} old \{old_drawn}")
  }
  // (changed once made: as the old one draws what it says then)
  let olds = HeadState::new("photo.png", ["copy"])
  let news = HeadState::new("photo.png", ["copy"])
  let o = head_tester(olds, true)
  let n = head_tester(news, false)
  for s in [olds, news] {
    s.name.set("another-picture.jpg")
    s.tools.set(["edit", "check", "download"])
  }
  o.draw()
  n.draw()
  let (old_drawn, _) = head_drawn(o)
  let (new_drawn, _) = head_drawn(n)
  assert_eq(new_drawn, old_drawn, msg="changed: new \{new_drawn} old \{old_drawn}")
}

///|
/// The tools a head_tester's head can have, in their order.
let head_icons : Array[String] = ["edit", "copy", "check", "download"]

///|
test "the floating head as nodes never narrower once open: tools gone, a shorter name, as wide as it was, as the old one is" {
  let olds = HeadState::new("a-longer-name.png", ["edit", "copy", "download"])
  let news = HeadState::new("a-longer-name.png", ["edit", "copy", "download"])
  let o = head_tester(olds, true)
  let n = head_tester(news, false)
  let (_, wide_x) = head_drawn(n)
  for s in [olds, news] {
    s.name.set("a.png")
    s.tools.set([])
  }
  o.draw()
  n.draw()
  o.draw()
  let (old_drawn, old_x) = head_drawn(o)
  let (new_drawn, new_x) = head_drawn(n)
  assert_eq(new_x, wide_x, msg="its × where it was")
  assert_eq(new_x, old_x, msg="as the old one's")
  assert_eq(new_drawn, old_drawn, msg="new \{new_drawn} old \{old_drawn}")
}

///|
test "the floating head as nodes going as it sleeps and coming as it wakes, from where it is at that moment: as the old one, at each moment" {
  let olds = HeadState::new("photo.png", ["copy"])
  let news = HeadState::new("photo.png", ["copy"])
  let o = head_tester(olds, true)
  let n = head_tester(news, false)
  let both = fn(f : (@ui.Tester) -> Unit) {
    f(o)
    f(n)
  }
  let same = fn(what : String) raise {
    let (od, _) = head_drawn(o)
    let (nd, _) = head_drawn(n)
    assert_eq(nd, od, msg="\{what}: new \{nd} old \{od}")
  }
  olds.awake.set(false)
  news.awake.set(false)
  both(fn(t) { t.run_for(sleep_ms / 2.0) })
  same("half asleep")
  // (woken half way: back from there)
  olds.awake.set(true)
  news.awake.set(true)
  both(fn(t) { t.run_for(wake_ms / 2.0) })
  same("woken half way, half back")
  both(fn(t) { t.run_for(wake_ms) })
  same("awake")
  olds.awake.set(false)
  news.awake.set(false)
  both(fn(t) { t.run_for(sleep_ms + 10.0) })
  same("asleep")
}

///|
/// The glyphs drawn of words `s`'s line where the draw list has them (kind 1, a glyph's): how far right each is cut to
/// (its clip's right, the window's where nothing cuts it nearer).
fn glyph_clips_right(t : @ui.Tester, top : Double, bottom : Double) -> Array[(Double, Double)] {
  let out = []
  for line in t.drawlist().split("\n") {
    let f = line.split(" ").map(fn(v) { v.to_string() }).to_array()
    if f.length() >= 21 && f[0] == "i" && f[6] == "1" {
      match (number_of(f[1]), number_of(f[2]), number_of(f[19])) {
        (Some(x), Some(y), Some(r)) if y >= top && y <= bottom => out.push((x, r))
        _ => ()
      }
    }
  }
  out
}

///|
test "the floating head as nodes with next to no room for its name: what is drawn of it within the room it is given, the tools whole and where the old one has them, the name read out whole" {
  let name = "a-very-long-name-of-a-picture.png"
  let tools = ["edit", "copy", "download"]
  let olds = HeadState::new(name, tools)
  let news = HeadState::new(name, tools)
  let o = head_tester(olds, true, w=196.0)
  let n = head_tester(news, false, w=196.0)
  for icon in tools + ["close"] {
    let label = if icon == "close" { t("web-main.preview.closeKey") } else { head_label(icon) }
    let ob = o.get(Button, label~)
    let nb = n.get(Button, label~)
    assert_eq(nb.rect, ob.rect, msg="\{icon}: where the old one has it")
    assert_eq(drawn_within(n, nb.rect), drawn_within(o, ob.rect), msg="\{icon}: drawn whole, as the old one")
  }
  let words = n.get(Text, label=name)
  let first = n.get(Button, label=head_label("edit"))
  let (_, wy, _, wh) = words.rect
  let glyphs = glyph_clips_right(n, wy - 2.0, wy + wh + 2.0)
  for g in glyphs {
    let (x, right) = g
    assert_true(right <= first.rect.0 + 0.01, msg="a glyph at \{x} cut at \{right}, past the first tool at \{first.rect.0}: \{glyphs}")
  }
}
