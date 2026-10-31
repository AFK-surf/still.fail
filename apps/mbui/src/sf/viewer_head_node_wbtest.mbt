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
  // (its numbers to a millionth: the same fade worked out by another way ending a last digit apart)
  let even = fn(line : String) {
    line
    .split(" ")
    .map(fn(v) {
      match number_of(v.to_string()) {
        Some(d) => ((d * 1000000.0).round() / 1000000.0).to_string()
        None => v.to_string()
      }
    })
    .collect()
    .join(" ")
  }
  (drawn_within(tt, (0.0, 0.0, tt.ctx().width, 120.0)).map(even), x.rect)
}

///|
/// The tools a head_tester's head can have, in their order.
let head_icons : Array[String] = ["edit", "copy", "check", "download"]

///|
/// A head (the old one's or the node's: `old`) in a window of its own, made as `s` says and taken through `steps`
/// (each a change to what it says and how long to go on after it), what it draws and where its × is after each:
/// one window at a time (a Tester's globals its own), all of what was seen kept before another is made.
fn head_run(
  old : Bool,
  name : String,
  tools : Array[String],
  steps : Array[(String, (HeadState) -> Unit, Double)],
  w? : Double = 390.0,
) -> Array[(String, Array[String], (Double, Double, Double, Double))] raise {
  let s = HeadState::new(name, tools)
  let t = head_tester(s, old, w~)
  let out = []
  let (d, x) = head_drawn(t)
  out.push(("made", d, x))
  for st in steps {
    let (what, change, ms) = st
    change(s)
    if ms > 0.0 {
      t.run_for(ms)
    } else {
      t.draw()
      t.draw()
    }
    let (d, x) = head_drawn(t)
    out.push((what, d, x))
  }
  out
}

///|
/// The node's run and the old one's, each step said to be alike.
fn head_alike(name : String, tools : Array[String], steps : Array[(String, (HeadState) -> Unit, Double)]) -> Array[(String, Array[String], (Double, Double, Double, Double))] raise {
  let old = head_run(true, name, tools, steps)
  let new = head_run(false, name, tools, steps)
  for i, n in new {
    let o = old[i]
    assert_eq(n.2, o.2, msg="\{n.0}: its ×, new \{n.2} old \{o.2}")
    // (where they differ first, said so)
    let at = (0).until(if n.1.length() > o.1.length() { n.1.length() } else { o.1.length() }).find_first(fn(k) {
      n.1.get(k) != o.1.get(k)
    })
    match at {
      Some(k) => fail("\{n.0}: new [\{k}] \{n.1.get(k)} old \{o.1.get(k)}; \{n.1.length()} drawn, old \{o.1.length()}")
      None => ()
    }
  }
  new
}

///|
test "the floating head as nodes beside the old one: drawn the same, its × where the old one's is; another name (cut short), another tool, as the old one draws them then" {
  head_alike("photo.png", ["edit", "copy"], []) |> ignore
  head_alike("a-very-long-name-of-a-picture-sent-from-far-away-2026-10-31.png", ["edit", "copy", "download"], []) |> ignore
  head_alike("photo.png", [], []) |> ignore
  // (changed once made: as the old one draws what it says then)
  head_alike("photo.png", ["copy"], [
    (
      "another name, other tools",
      fn(s) {
        s.name.set("another-picture.jpg")
        s.tools.set(["edit", "check", "download"])
      },
      0.0,
    ),
  ])
  |> ignore
}

///|
test "the floating head as nodes never narrower once open: tools gone, a shorter name, as wide as it was, as the old one is" {
  let new = head_alike("a-longer-name.png", ["edit", "copy", "download"], [
    (
      "fewer, shorter",
      fn(s) {
        s.name.set("a.png")
        s.tools.set([])
      },
      0.0,
    ),
  ])
  assert_eq(new[1].2, new[0].2, msg="its × where it was")
}

///|
/// How opaque the head is drawn (its glass's opacity, the last of what drawn_within says of the first it draws), as
/// head_run saw it.
fn head_alpha(drawn : Array[String]) -> Double {
  match drawn {
    [first, ..] =>
      match first.split(" ").map(fn(v) { v.to_string() }).to_array() {
        [.., last] => number_of(last).unwrap_or(-1.0)
        _ => -1.0
      }
    [] => 0.0
  }
}

///|
test "the floating head as nodes going as it sleeps and coming as it wakes, from where it is at that moment: at each moment as its way says (sleep_ms out, wake_ms in, eased out), as the old one" {
  let new = head_alike("photo.png", ["copy"], [
    ("half asleep", fn(s) { s.awake.set(false) }, sleep_ms / 2.0),
    ("woken half way, half back", fn(s) { s.awake.set(true) }, wake_ms / 2.0),
    ("awake", fn(_) {  }, wake_ms),
    ("asleep", fn(s) { s.awake.set(false) }, sleep_ms + 10.0),
  ])
  let ease = fn(p : Double) { @ui.Ease::Out.at(p) }
  let half = 1.0 - ease(0.5)
  let back = half + (1.0 - half) * ease(0.5)
  let want = [1.0, half, back, 1.0, 0.0]
  for i, w in want {
    let got = head_alpha(new[i].1)
    assert_true((got - w).abs() < 0.001, msg="\{new[i].0}: \{got}, its way says \{w}")
  }
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
/// A head 196 wide with three tools and a long name (the old one's or the node's): each tool's (and ×'s) rect and what
/// is drawn within it; the name's words read out, and the glyphs drawn of it with how far right each is cut to, and
/// where the first tool begins.
fn narrow_head(old : Bool) -> (Array[((Double, Double, Double, Double), Array[String])], Bool, Array[(Double, Double)], Double) raise {
  let name = "a-very-long-name-of-a-picture.png"
  let tools = ["edit", "copy", "download"]
  let tt = head_tester(HeadState::new(name, tools), old, w=196.0)
  let rects = []
  for icon in tools + ["close"] {
    let label = if icon == "close" { t("web-main.preview.closeKey") } else { head_label(icon) }
    let b = tt.get(Button, label~)
    rects.push((b.rect, drawn_within(tt, b.rect)))
  }
  let words = tt.all(Text, label=name)
  let first = tt.get(Button, label=head_label("edit")).rect.0
  let glyphs = match words {
    [w, ..] => glyph_clips_right(tt, w.rect.1 - 2.0, w.rect.1 + w.rect.3 + 2.0)
    _ => []
  }
  (rects, words.length() == 1, glyphs, first)
}

///|
test "the floating head as nodes with next to no room for its name: what is drawn of it within the room it is given, the tools whole and where the old one has them, the name read out whole (the old one's none of it)" {
  let (old_tools, old_read, _, _) = narrow_head(true)
  let (new_tools, new_read, glyphs, first) = narrow_head(false)
  assert_eq(new_tools, old_tools, msg="the tools whole, where the old one has them")
  // (the old one's cut to nothing reads out none of it)
  assert_true(new_read, msg="the name read out whole: new \{new_read} old \{old_read}")
  assert_true(glyphs.length() > 0, msg="something of the name drawn")
  for g in glyphs {
    let (x, right) = g
    assert_true(right <= first + 0.01, msg="a glyph at \{x} cut at \{right}, past the first tool at \{first}: \{glyphs}")
  }
}
