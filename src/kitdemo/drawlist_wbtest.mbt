///|
/// The controls page as kept from mini1 (textrec_mini1_controls_wbtest.mbt), its last frame drawn again.
fn controls_kept() -> @ui.Tester {
  let t = @ui.Tester::new(fn(c) { gallery(c, "controls") }, w=960.0, h=720.0, text=run_mini1_controls, scale=1.0, time=7950001676.833502 - 16.0, stable=true)
  t.replay_frames(run_mini1_controls) |> ignore
  t
}

///|
test "the controls page's last frame as a draw list: a line an instance, every glyph named by what the host shaped" {
  let t = controls_kept()
  let dl = t.drawlist()
  let lines = dl.split("\n").map(fn(l) { l.to_string() }).to_array()
  assert_eq(lines[0], "mbui-dl 3")
  assert_eq(lines[1], "window 960 720 1")
  assert_eq(lines[2], "clear 0.961 0.961 0.969")
  let insts = lines.filter(fn(l) { l.has_prefix("i ") })
  assert_true(insts.length() > 100)
  assert_true(insts.iter().all(fn(l) { l.split(" ").count() == 29 }))
  let glyphs = lines.filter(fn(l) { l.has_prefix("glyph ") })
  assert_true(glyphs.length() > 20)
  // named: its font, the cluster and the words the host shaped
  assert_eq(glyphs.filter(fn(l) { l.has_suffix(" -1 \"\"") }), [])
  // numbered as first drawn, each once
  for n, l in glyphs {
    assert_true(l.has_prefix("glyph \{n} "))
  }
  // the same frame, the same list
  assert_eq(t.drawlist(), dl)
}

///|
/// A page with words and a picture (`pic`: its source), and `extra` words above them when not "", on mini1's kept text.
fn with_picture(pic : Ref[String], extra? : Ref[String] = Ref("")) -> @ui.Tester {
  @ui.Tester::new(
    fn(c) {
      c.column(fn() {
        if extra.val != "" {
          c.text(extra.val, size=12.0, weight=600, wrap=false) |> ignore
        }
        c.text("Switch", size=12.0, weight=600, wrap=false) |> ignore
        c.image(pic.val, w=Px(40.0), h=Px(40.0)) |> ignore
      })
      |> ignore
    },
    w=200.0,
    h=200.0,
    text=run_mini1_controls,
    scale=1.0,
    images=[("one.png", 80, 80), ("two.png", 80, 80)],
  )
}

///|
test "the same screen reached by other steps is the same draw list: glyphs and pictures by what they are, not their places or ids" {
  // straight there
  let a = with_picture(Ref("two.png"))
  a.draw()
  a.draw()
  // by way of another picture first (decoded first: another id), and other words drawn before (other atlas places)
  let pic = Ref("one.png")
  let extra = Ref("Light")
  let b = with_picture(pic, extra~)
  b.draw()
  b.draw()
  pic.val = "two.png"
  extra.val = ""
  b.draw()
  b.draw()
  assert_eq(b.drawlist(), a.drawlist())
  assert_true(a.drawlist().contains("image 0 "))
}

///|
test "a draw list can carry the pictures handed over as bytes: a list a renderer draws by itself" {
  let t = @ui.Tester::new(
    fn(c) {
      c.image_bytes("mem:dot", b"\x89PNG three")
      c.image("mem:dot", w=Px(20.0), h=Px(20.0)) |> ignore
    },
    w=100.0,
    h=100.0,
  )
  t.draw()
  t.draw()
  let carried = t.drawlist(bytes=true)
  assert_true(carried.contains("\nbytes 0 iVBORyB0aHJlZQ==\n"))
  assert_false(t.drawlist().contains("\nbytes "))
}
