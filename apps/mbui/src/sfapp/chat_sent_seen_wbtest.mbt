// Words sent on a chat's page made as nodes (sfbase's chat_page_nodes on; no flight there) are seen in every frame
// from the press (the coordinator of the migration, 2026-11-14: the result is there in the cause's frame; at the end
// the content only goes up; one cause, one motion): in the press's frame their row stands whole, at full ink and its
// size, its top at its rest against the key before it, drawn over the composer it leaves, and rides up with the list's
// one way as its room opens and the composer closes (mbui's View::scrolls_window `comes_whole`, chat_body_node's). No
// frame shows the words both in the field and in their row, none in neither; the message before goes up only, and where
// the composer gives back lines (three sent) from rest in the first frame drawn after the press, on one way. A quote's
// words and a quoted picture the same. On 小屏 and 大屏, its rows on the host's pixels, every frame a host draws.

///|
/// The screens: name, width, height, platform.
let ss_screens : Array[(String, Double, Double, Int)] = [("小屏", 390.0, 844.0, 2), ("大屏", 1280.0, 800.0, 0)]

///|
/// The composer's ground drawn now (the lowest wide glass): x, y, w, h, and where among the instances it is.
fn ss_glass(t : @ui.Tester) -> ((Double, Double, Double, Double), Int)? {
  let order = t.drawn_order()
  let mut best : ((Double, Double, Double, Double), Int)? = None
  for i, o in order {
    let (kind, x, y, w, h, _) = o
    if (kind == 5 || kind == 6) && w > 150.0 {
      match best {
        Some(((_, by, _, _), _)) if by >= y => ()
        _ => best = Some(((x, y, w, h), i))
      }
    }
  }
  best
}

///|
/// What one frame shows of words `w` sent: drawn in their row (the tree's: where, how big, how opaque), whether glyphs of
/// the text's ink are in the composer's field outside that row's words, whether the row's words are drawn cut, whether
/// any instance in their box is drawn under the composer's ground where they meet it, and where the key before the sent
/// one is (its order among the list's keys `before`).
priv struct SsFrame {
  at : Double
  row : (Double, Double, Double, Double, Double)?
  field : Bool
  cut : String?
  under : Bool
  prev : Double?
  glass_h : Double
  block_h : Double
}

///|
fn ss_look(t : @ui.Tester, w : String, before : Int) -> SsFrame {
  let tree = @ui.view_tree().unwrap()
  let row = match tree.drawn().iter().find_first(fn(d) { d.words.has_prefix(w) && d.bones == 0L }) {
    Some(d) => Some((d.x, d.y, d.w, d.h, d.alpha))
    None => None
  }
  let in_row = fn(x : Double, y : Double) {
    match row {
      Some((rx, ry, rw, rh, a)) => a > 0.0 && x >= rx - 1.0 && x <= rx + rw + 1.0 && y >= ry - 1.0 && y <= ry + rh + 1.0
      None => false
    }
  }
  let field = match composer_field(t) {
    Some((fx, fy, fw, fh)) => {
      let ink = @sf.theme().p.text
      t.drawn_glyphs().iter().any(fn(g) { g.2 == ink && g.0 >= fx && g.0 <= fx + fw && g.1 >= fy && g.1 <= fy + fh && !in_row(g.0, g.1) })
    }
    None => false
  }
  let under = match (row, ss_glass(t)) {
    (Some((rx, ry, rw, rh, _)), Some(((gx, gy, gw, gh), gi))) if ry + rh > gy && ry < gy + gh && rx + rw > gx && rx < gx + gw =>
      t.drawn_order().mapi(fn(i, o) { (i, o) }).iter().any(fn(p) {
        let (i, (kind, x, y, _, _, a)) = p
        kind != 0 && kind != 4 && kind != 5 && kind != 6 && a > 0.0 &&
          x >= rx && x <= rx + rw && y >= ry && y <= ry + rh && y >= gy && i < gi
      })
    _ => false
  }
  let (prev, block_h) = match tree.list_in_front() {
    Some(l) =>
      (
        match l.rows.iter().find_first(fn(r) { r.0 == before }) {
          Some((_, _, (_, y, _, _))) => Some(y)
          None => None
        },
        match l.rows.iter().find_first(fn(r) { r.0 == before + 1 }) {
          Some((_, _, (_, _, _, h))) => h
          None => 0.0
        },
      )
    None => (None, 0.0)
  }
  let glass_h = match ss_glass(t) {
    Some(((_, _, _, h), _)) => h
    None => 0.0
  }
  { at: t.time(), row, field, cut: cr_cut([w], None), under, prev, glass_h, block_h }
}

///|
/// Words sent on `t` (its composer holding them): every frame a host draws from the one before the press till they and
/// what they set going rest, and the row's words at rest.
fn ss_walk(t : @ui.Tester, w : String) -> Array[SsFrame] {
  let before = match @ui.view_tree().unwrap().list_in_front() {
    Some(l) => l.count - 1
    None => -1
  }
  let frames = [ss_look(t, w, before)]
  t.each_frame(Some(fn() { frames.push(ss_look(t, w, before)) }))
  tap_send(t)
  t.run_shown(@ui.move_most_ms + 200.0)
  t.each_frame(None)
  frames.push(ss_look(t, w, before))
  frames
}

///|
/// What is wrong among `frames` (from the one before the press): the words in their row before it, in the field after
/// it, in both or neither; drawn in their row at less than full ink or another size than at rest, cut, under the
/// composer's ground; the key before them down. None, or what.
fn ss_faults(frames : Array[SsFrame], at : String) -> Array[String] {
  let out = []
  let rest = frames[frames.length() - 1]
  let rest_size = match rest.row {
    Some((_, _, w, h, _)) => (w, h)
    None => {
      out.push("\{at}: not drawn at rest")
      return out
    }
  }
  let first = frames[0]
  if !first.field {
    out.push("\{at}: not in the field before the press")
  }
  if first.row is Some((_, _, _, _, a)) && a > 0.0 {
    out.push("\{at}: in their row before the press")
  }
  let mut high = first.prev
  for i in 1..<frames.length() {
    let f = frames[i]
    let at = "\{at}, frame \{i} at \{f.at}"
    if f.field {
      out.push("\{at}: still in the field")
    }
    match f.row {
      Some((_, _, w, h, a)) => {
        if (a - 1.0).abs() > 0.001 {
          out.push("\{at}: drawn at \{a}")
        }
        if (w - rest_size.0).abs() > 0.01 || (h - rest_size.1).abs() > 0.01 {
          out.push("\{at}: drawn \{w}×\{h}, \{rest_size.0}×\{rest_size.1} at rest")
        }
      }
      None => out.push("\{at}: drawn nowhere")
    }
    match f.cut {
      Some(c) => out.push("\{at}: \{c}")
      None => ()
    }
    if f.under {
      out.push("\{at}: drawn under the composer's ground")
    }
    match (high, f.prev) {
      (Some(h), Some(y)) => {
        if y > h + 0.01 {
          out.push("\{at}: the key before down from \{h} to \{y}")
        }
        if y < h {
          high = Some(y)
        }
      }
      _ => ()
    }
  }
  out
}

///|
/// `lines` typed in the composer of the fixture's chat on `screen` (a finger's new line, else ⇧Enter), rows on pixels.
fn ss_typed(screen : (String, Double, Double, Int), lines : Array[String]) -> @ui.Tester raise {
  let t = cr_open(screen, fix_pace.val, on_pixels=true)
  ss_type(t, lines, screen.3 == 2)
  t
}

///|
fn ss_type(t : @ui.Tester, lines : Array[String], finger : Bool) -> Unit raise {
  guard composer_field(t) is Some((fx, fy, fw, fh)) else { fail("no composer's field") }
  t.tap(fx + fw / 2.0, fy + fh / 2.0)
  for i, l in lines {
    if i > 0 {
      if finger {
        t.type_text("\n")
      } else {
        t.key(@ui.key_code_enter, mods=@ui.mod_shift_key)
      }
    }
    t.type_text(l)
  }
  t.run_for(@ui.move_most_ms)
}

///|
test "a chat's page made as nodes, 小屏 and 大屏: one line sent, nothing given back: whole in their row from the press's frame, at full ink, over the composer, never in the field after it, the message before up only" {
  for screen in ss_screens {
    let t = ss_typed(screen, ["先上屏"])
    assert_eq(ss_faults(ss_walk(t, "先上屏"), "\{screen.0}"), [])
  }
}

///|
test "a chat's page made as nodes, 小屏 and 大屏: one line sent into the room an agent's line left: whole from the press's frame, nothing moving" {
  for screen in ss_screens {
    let (t, _, _) = cr_turn(screen, 300.0)
    t.set_rows_on_pixels(true)
    ss_type(t, ["再看看"], screen.3 == 2)
    assert_eq(ss_faults(ss_walk(t, "再看看"), "\{screen.0}"), [])
  }
}

///|
test "a chat's page made as nodes, 小屏 and 大屏: three lines sent, the composer giving two back: whole from the press's frame; the message before up from rest in the first frame drawn after the press, its first three steps each larger, up as far as the row is tall less what was given back" {
  for screen in ss_screens {
    let t = ss_typed(screen, ["第一行", "第二行", "第三行"])
    let frames = ss_walk(t, "第一行")
    let at = "\{screen.0}"
    assert_eq(ss_faults(frames, at), [])
    println("SENTSEEN \{at} the key before: \{Repr(frames.map(fn(f) { (f.at, f.prev) }))}")
    // (from the frame before the press, then each drawn after the press's moment: those drawn at it show nothing gone)
    let pressed = frames[0].at
    let ys = [frames[0].prev.unwrap()] + frames.filter(fn(f) { f.at > pressed + 0.001 }).filter_map(fn(f) { f.prev })
    assert_true(ys.length() > 4, msg="\{at}: \{ys.length()} frames with the key before")
    let steps = [ys[0] - ys[1], ys[1] - ys[2], ys[2] - ys[3]]
    // (from rest: its first step in the first frame drawn after the press, the next larger; on a Move the third is
    // about its fastest, so no smaller than the second by more than a device pixel's half)
    let half_px = 0.5 / 2.0
    assert_true(
      steps[0] > 0.0 && steps[1] > steps[0] && steps[2] >= steps[1] - half_px,
      msg="\{at}: its first steps \{Repr(steps)}",
    )
    // (up as far as the row is tall less what was given back: the row's rest less the two lines the composer gave)
    // (to where it rests on the send's own way, before the station's row of it comes)
    let settled = frames.filter(fn(f) { f.at <= pressed + @ui.move_most_ms && f.prev is Some(_) })
    let rest = settled[settled.length() - 1]
    let up = ys[0] - rest.prev.unwrap()
    let want = rest.block_h - (frames[0].glass_h - rest.glass_h)
    println("SENTSEEN \{at}: up \{up}, the row \{rest.block_h} less \{frames[0].glass_h - rest.glass_h} given back")
    assert_true((up - want).abs() <= half_px, msg="\{at}: up \{up}, \{want} wanted")
  }
}

///|
/// The fixture's chat on `screen` with passage `quote_passage` quoted into its draft (`file`: a picture with it).
fn ss_quoting(screen : (String, Double, Double, Int), file? : Json) -> (@ui.Tester, Source) {
  let (_, w, h, platform) = screen
  new_run()
  @sfbase.chat_page_nodes.set(true)
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~)
  t.set_rows_on_pixels(true)
  t.run_for(@ui.move_most_ms)
  @sfbase.writing_quote(src, @sfbase.writing(src, "ws1/st1:s-c1"), { "author": "Ana", "text": quote_passage, "ts": "ts8" }, file?)
  t.run_for(@ui.move_most_ms + @ui.image_fade_ms)
  (t, src)
}

///|
/// The quote's words drawn now: in the composer's card (an old view's: Tester::words not of the tree) and in their row
/// (the tree's, at full ink).
fn ss_quote_seen(t : @ui.Tester) -> (Bool, Bool) {
  let tree_n = @ui.view_tree().unwrap().drawn().filter(fn(d) { d.words.contains(quote_passage) && d.bones == 0L })
  let row = tree_n.iter().any(fn(d) { d.alpha > 0.999 })
  let all = t.words().filter(fn(w) { w.0.contains(quote_passage) && w.5 > 0.0 }).length()
  (all > tree_n.length(), row)
}

///|
test "a chat's page made as nodes, 小屏 and 大屏: a quote with a comment sent: its words in the composer's card in the frame before the press, in their row whole at full ink in every frame after it, never both, never neither" {
  for screen in ss_screens {
    let (t, _) = ss_quoting(screen)
    t.type_text("这里要对齐")
    t.run_for(@ui.move_most_ms)
    let seen = [ss_quote_seen(t)]
    t.each_frame(Some(fn() { seen.push(ss_quote_seen(t)) }))
    tap_send(t)
    t.run_shown(@ui.move_most_ms + 200.0)
    t.each_frame(None)
    assert_eq(seen[0], (true, false), msg="\{screen.0}: before the press")
    for i in 1..<seen.length() {
      assert_eq(seen[i], (false, true), msg="\{screen.0}, frame \{i}")
    }
  }
}

///|
test "a chat's page made as nodes, 小屏 and 大屏: a quoted picture with an empty comment sent: in its card's tile in the frame before the press, at its place in the row, whole at full ink, in every frame after it" {
  for screen in ss_screens {
    let name = "seen.png"
    let file : Json = { "name": Json::string(name), "path": Json::string("/w/uploads/" + name), "size": 120, "width": 1600, "height": 900, "owner": "s-c1" }
    let (t, _) = ss_quoting(screen, file~)
    let pics = fn() -> Array[(Double, Double)] {
      let all = picture_instances(t, "mem:fixture/" + name) catch { _ => [] }
      all.map(fn(p) { p.1 }).filter(fn(a) { a[11] > 0.0 }).map(fn(a) { (a[2], a[11]) })
    }
    let seen = [pics()]
    t.each_frame(Some(fn() { seen.push(pics()) }))
    tap_send(t)
    t.run_shown(@ui.move_most_ms + @ui.image_fade_ms + 200.0)
    t.each_frame(None)
    let rest = seen[seen.length() - 1]
    assert_true(rest.length() == 1 && rest[0].0 > 60.0, msg="\{screen.0}: at rest \{Repr(rest)}")
    assert_true(seen[0].length() == 1 && (seen[0][0].0 - 56.0).abs() < 0.5, msg="\{screen.0}: before the press \{Repr(seen[0])}")
    for i in 1..<seen.length() {
      let s = seen[i]
      assert_true(
        s.length() == 1 && (s[0].0 - rest[0].0).abs() < 0.01 && s[0].1 > 0.999,
        msg="\{screen.0}, frame \{i}: \{Repr(s)}, \{Repr(rest)} at rest",
      )
    }
  }
}
