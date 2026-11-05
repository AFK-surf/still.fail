// The catching up as nodes (sync_key_node) moves as the old view's (sync_key) did, frame by frame: coming after its
// moment, turning, brought to rest from where it is as it stops, its arrows drawn back, the tick drawn, held, faded.

///|
/// What is drawn each frame (60 a second) of a catching up shown at once, stopped at `stop` ms, for `whole` ms in
/// all: the old view's (`old`) or the node's, each frame's draw list (what a renderer draws: each shape's pieces, how
/// it is turned, its colour and opacity).
fn sync_frames(old : Bool, stop : Double, whole : Double) -> Array[String] {
  let shown = @signals.signal(true)
  let t = @ui.Tester::new(
    fn(c) { if old { sync_key(c, "k", 34.0, 20.0, shown.get(), "正在同步") } },
    w=100.0,
    h=100.0,
    platform=0,
  )
  if !old {
    @ui.set_view_app(fn(root) {
      sync_key_node(root, TipLayer::new(fn() { Some(root) }), 34.0, 20.0, fn() { shown.get() }, fn() { "正在同步" })
    })
  }
  t.draw()
  let frame = 1000.0 / 60.0
  let out = []
  let mut at = 0.0
  while at < whole {
    if at <= stop && at + frame > stop {
      shown.set(false)
    }
    t.run_for(frame)
    at = at + frame
    out.push(t.drawlist())
  }
  out
}

///|
test "the catching up as nodes, frame by frame as sync_key: turning, at rest, drawn back, the tick drawn, faded" {
  let wrong : Array[String] = []
  // (stopped early, mid-turn, near a turn's end: each brought to rest its own way)
  for stop in [600.0, 1234.0, 2050.0] {
    let new = sync_frames(false, stop, stop + 3000.0)
    let old = sync_frames(true, stop, stop + 3000.0)
    for i, f in old {
      let n = new[i]
      if f != n && wrong.length() < 6 {
        let fl = f.split("\n").map(fn(l) { l.to_string() }).to_array()
        let nl = n.split("\n").map(fn(l) { l.to_string() }).to_array()
        let mut k = 0
        while k < fl.length() && k < nl.length() && fl[k] == nl[k] {
          k = k + 1
        }
        wrong.push("stopped at \{stop}, frame \{i}, line \{k}: old \{fl.get(k)}, node \{nl.get(k)}")
      }
    }
  }
  assert_eq(wrong, [])
}

///|
test "what the frame compare compares: the mark drawn, turning (each frame another), drawn back, the tick drawn" {
  let old = sync_frames(true, 1234.0, 4234.0)
  let mut moved = 0
  for i in 1..<old.length() {
    if old[i] != old[i - 1] {
      moved = moved + 1
    }
  }
  let turned = old.filter(fn(f) { f.contains("mbui-dl 5") || f.contains("mbui-dl 6") || f.contains("mbui-dl 7") || f.contains("mbui-dl 8") || f.contains("mbui-dl 9") }).length()
  // (24 frames before its moment, 60 of the tick held still, 37 gone once faded: the rest each another)
  assert_true(moved > 120, msg="changed in \{moved} of \{old.length()} frames")
  assert_true(turned > 40, msg="turned in \{turned} frames")
}
