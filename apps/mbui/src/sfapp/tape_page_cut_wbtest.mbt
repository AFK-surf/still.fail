// The page's panel on a tape 600 wide, beside the sidebar, reaching past the window's edge: nothing of what it holds
// wholly beyond that edge drawn, as the old frame drew nothing past the window (a line of words running on past it is
// drawn whole, as main's are).

///|
/// A number as Tester::frame_export says it: whole, or a half after it (".5"), signed.
fn export_half(s : String) -> Double {
  let neg = s.has_prefix("-")
  let body = if neg { s.view(start_offset=1).to_string() } else { s }
  let (whole, half) = match body.find(".") {
    Some(i) => (body.view(end_offset=i).to_string(), 0.5)
    None => (body, 0.0)
  }
  let mut n = half
  let mut place = 1.0
  for i = whole.length() - 1; i >= 0; i = i - 1 {
    n = n + (whole[i].to_int() - '0'.to_int()).to_double() * place
    place = place * 10.0
  }
  if neg { -n } else { n }
}

///|
/// The nodes of the window's tree that drew something in the last frame lying wholly past the window's left edge or its
/// right edge `w` where they are drawn, with the first thing each drew (Tester::frame_export's `by`): a row partly
/// inside it whose words are left past the edge not counted.
fn drawn_past(t : @ui.Tester, w : Double) -> Array[String] {
  let first : Map[String, String] = {}
  for l in t.frame_export() {
    let f = l.split(" ").map(fn(s) { s.to_string() }).collect()
    guard f.length() > 5 else { continue }
    let by = match f.iter().find_first(fn(x) { x.has_prefix("by=") }) {
      Some(b) => b
      None => continue
    }
    let (x, bw) = (export_half(f[1]), export_half(f[3]))
    let past = x >= w || x + bw <= 0.0
    if past && !first.contains(by) {
      first[by] = l
    }
  }
  // (the tree's nodes where they are drawn, by their index: frame_export's `tree:N`)
  let boxes : Map[String, (Double, Double)] = {}
  match @ui.view_tree() {
    // (one turned by as far as it can reach turned, about any point of it: its diagonal round its box)
    Some(tree) =>
      for d in tree.drawn() {
        let out = if tree.turn_of(d.id).0 == 0.0 { 0.0 } else { (d.w * d.w + d.h * d.h).sqrt() }
        boxes["by=tree:\{d.id.at}"] = (d.x - out, d.w + 2.0 * out)
      }
    None => ()
  }
  first
  .iter()
  .filter(fn(e) {
    match boxes.get(e.0) {
      // (touching the edge reaching it, as the tree's cull has it)
      Some((x, bw)) => x > w || x + bw < 0.0
      // (the old frame's: cut as its own clip says, its root the window's, as main's)
      None => false
    }
  })
  .map(fn(e) { e.1 })
  .collect()
}

///|
test "the page's panel on a tape 600 wide, beside the sidebar: nothing of it wholly past the window's edge drawn" {
  for platform in [0, 2] {
    let t = tape_chat(platform, 600.0, 900.0)
    assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
    assert_eq(drawn_past(t, 600.0), [])
  }
}

///|
test "the tape 600 wide moving to the page and back: in no frame of it anything wholly past the window's edge drawn" {
  for platform in [0, 2] {
    let t = tape_chat(platform, 600.0, 900.0)
    let past : Array[String] = []
    let frames = Ref(0)
    t.each_frame(Some(fn() {
      frames.val = frames.val + 1
      for d in drawn_past(t, 600.0) {
        past.push("frame \{frames.val}: \{d}")
      }
    }))
    // (the page over, the sidebar's column going off the window's left as the page's panel comes in from its right)
    t.tap(600.0 - @sfdesk.tape_shows / 2.0, 400.0)
    t.run_for(@ui.move_most_ms)
    assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
    @sfdesk.wide.tape_ask.set(Some(@sfdesk.TapePane::Side))
    t.run_for(@ui.move_most_ms)
    t.each_frame(None)
    assert_true(frames.val > 10, msg="\{frames.val} frames")
    assert_eq(past.length(), 0, msg="\{past.length()} past the edge: \{past}")
  }
}
