// What the reader has before their eyes does not move, as the composer changes and the keyboard comes and goes, on a
// chat's page made as nodes (chat_nodes_read_stays_wbtest's principle; its long chat, late core and helpers chat_nodes_read_stays_help_wbtest's).
// Read up, the message read (the first whose words start in sight under the bar, held by where its words start) stays
// where it is in every frame. At the list's end the page keeps room under the last row for the composer opened with
// one line, so two things are held there, apart: (a) the last row's own bottom on the screen: the focus taken or let
// go moves it not at all; a line, a file or a quote moves it up only, never down, and it ends up by just what the
// composer grew; (b) in every frame the composer's ground does not come over the last row's words, and stands no
// further under them than it did at rest before or after, whichever is more (the two go one way). Each within half a
// device pixel. The focus is let go as a person lets it go: with a finger the keyboard put away (its own key, Back),
// with keyboard and mouse Tab away from the field.

///|
/// The lowest words drawn over the composer's ground across its width (the last row's at the end): their text, where
/// they start across, and their bottom.
fn rsc_lowest(t : @ui.Tester) -> (String, Double, Double)? {
  guard rs_ground(t) is Some((gx, gy, gw)) else { return None }
  let mut low : (String, Double, Double)? = None
  for wd in t.words() {
    let (text, x, y, _, h, a) = wd
    if a > 0.0 && x >= gx && x < gx + gw && y >= 0.0 && y + h <= gy + 0.5 {
      if low is None || low.unwrap().2 < y + h {
        low = Some((text, x, y + h))
      }
    }
  }
  low
}

///|
/// The bottom of words `text` starting across at `x` now (the lowest of them, if several), if drawn.
fn rsc_bottom(t : @ui.Tester, text : String, x : Double) -> Double? {
  let mut low : Double? = None
  for wd in t.words() {
    let (s, wx, y, _, h, a) = wd
    if a > 0.0 && s == text && (wx - x).abs() < 1.0 && (low is None || low.unwrap() < y + h) {
      low = Some(y + h)
    }
  }
  low
}

///|
/// At the list's end, `cause` held to (a) and (b) (the file's head) over every frame to rest, the last row moved by it
/// not at all (`grows` false) or up by what the composer grows (`grows` true): None where both hold, else which failed
/// and how.
fn rsc_end_held(t : @ui.Tester, k : RsCore, what : String, grows : Bool, cause : () -> Unit) -> String? {
  let what = what + " (at the end)"
  guard rs_ground(t) is Some((_, g0, _)) else { return Some("\{what}: no composer's ground before the cause") }
  guard rsc_lowest(t) is Some((text, x, b0)) else { return Some("\{what}: no last row over the composer") }
  let seen : Array[(Double, Double?, Double?)] = []
  let start = t.time()
  k.look = Some(fn() { seen.push((t.time() - start, rsc_bottom(t, text, x), rs_ground(t).map(fn(g) { g.1 }))) })
  cause()
  rs_run(t, k.late + rs_watch_ms)
  k.look = None
  guard seen.last() is Some((_, Some(b1), Some(g1))) else { return Some("\{what}: the last row or the composer not drawn at rest") }
  let grew = g0 - g1
  let most_gap = if g0 - b0 > g1 - b1 { g0 - b0 } else { g1 - b1 }
  let faults : Array[String] = []
  if grows && grew <= rs_still {
    faults.push("the composer grew \{rs_n(grew)} (the cause not made)")
  }
  // (a) the last row's own bottom
  let mut a_most = 0.0
  let mut a_at = 0.0
  let mut a_n = 0
  let mut down_most = 0.0
  let mut down_at = 0.0
  let mut prev = b0
  // (b) the ground over the words, or further under them than at rest
  let mut over_most = 0.0
  let mut over_at = 0.0
  let mut far_most = 0.0
  let mut far_at = 0.0
  let mut lost : Double? = None
  for f in seen {
    match (f.1, f.2) {
      (Some(b), Some(g)) => {
        if !grows && (b - b0).abs() > rs_still {
          a_n += 1
          if (b - b0).abs() > a_most.abs() {
            a_most = b - b0
            a_at = f.0
          }
        }
        if grows && b - prev > rs_still && b - prev > down_most {
          down_most = b - prev
          down_at = f.0
        }
        prev = b
        if b - g > rs_still && b - g > over_most {
          over_most = b - g
          over_at = f.0
        }
        if g - b - most_gap > rs_still && g - b - most_gap > far_most {
          far_most = g - b - most_gap
          far_at = f.0
        }
      }
      _ => if lost is None { lost = Some(f.0) }
    }
  }
  if a_n > 0 {
    faults.push("(a) the last row moved \{rs_n(a_most)} at most at +\{rs_n(a_at)} ms, in \{a_n} frames, at rest \{rs_n(b1 - b0)}")
  }
  if down_most > 0.0 {
    faults.push("(a) the last row went down \{rs_n(down_most)} in a frame at +\{rs_n(down_at)} ms")
  }
  if grows && (b1 - b0 + grew).abs() > rs_still {
    faults.push("(a) the last row ends up \{rs_n(b0 - b1)} up, the composer grew \{rs_n(grew)}")
  }
  if over_most > 0.0 {
    faults.push("(b) the composer's ground over the last row's words by \{rs_n(over_most)} at most at +\{rs_n(over_at)} ms")
  }
  if far_most > 0.0 {
    faults.push("(b) the composer's ground \{rs_n(far_most)} further under the last row than at rest at most, at +\{rs_n(far_at)} ms (at rest \{rs_n(g0 - b0)} before, \{rs_n(g1 - b1)} after)")
  }
  match lost {
    Some(at) => faults.push("the last row or the composer not drawn from +\{rs_n(at)} ms")
    None => ()
  }
  if faults.is_empty() {
    println("READ-STAYS holds: \{what} (\{seen.length()} frames, the composer grew \{rs_n(grew)})")
    return None
  }
  let path : Array[String] = []
  for i in [0, 1, 2, 3, 5, 8, 12, 20, 30, 45, 60, 90] {
    if i < seen.length() {
      let (at, b, g) = seen[i]
      match (b, g) {
        (Some(b), Some(g)) => path.push("+\{rs_n(at)}:\{rs_n(b - b0)}/\{rs_n(g - b)}")
        _ => path.push("+\{rs_n(at)}:none")
      }
    }
  }
  let said = "\{what}: " + faults.join("; ") + "; frames (+ms:row moved/gap): " + path.join(" ")
  println("READ-STAYS breaks: " + said)
  Some(said)
}

///|
/// Whether a field has the keyboard's focus (the composer's, the only one on the page).
fn rs_field_focused(t : @ui.Tester) -> Bool {
  t.focused() is Some(n) && n.role == @ui.Role::TextField
}

///|
/// The composer's field tapped (the focus given it).
fn rs_focus(t : @ui.Tester) -> Unit {
  match composer_field(t) {
    Some((x, y, w, h)) => t.tap(x + w / 2.0, y + h / 2.0)
    None => ()
  }
}

///|
/// A new line in the composer, as `platform` takes one, and words on it.
fn rs_line(t : @ui.Tester, platform : Int, words : String) -> Unit {
  if platform == 2 {
    t.enter()
  } else {
    t.key(@ui.key_code_enter, mods=@ui.mod_shift_key)
  }
  t.type_text(words)
}

///|
/// The focus let go of the composer as a person lets it go: with a finger the keyboard put away (and Back, where that
/// left it focused), with keyboard and mouse Tab away (and a press on the list's empty side, where that left it).
fn rs_let_go(t : @ui.Tester, s : (String, Double, Double, Int)) -> Unit {
  let (_, w, h, platform) = s
  if platform == 2 {
    t.keyboard_gone()
    if rs_field_focused(t) {
      t.back()
    }
  } else {
    t.tab()
    if rs_field_focused(t) {
      t.tap(w - 6.0, h * 0.3)
    }
  }
}

///|
/// On screen `s` over a core `late` late, read up (else at the end): the focus let go where it opened focused (keyboard
/// and mouse), taken, a second and third line typed, a file added, a quote added, the focus let go, each held as it
/// happens; the file and the quote added only `with_cards` (chat_nodes_read_stays_composer_file_wbtest's, left out of
/// the blocks here).
fn rs_composer(
  s : (String, Double, Double, Int),
  late : Double,
  at_end : Bool,
  with_cards? : Bool = true,
) -> Array[String] {
  let out : Array[String] = []
  // (off the device's pixels, as this was written and holds on main: on them the last row goes by whole pixels and
  // the composer's ground, the old view's, does not, so at the end (b) reads 0.5-0.6 pt on both screens at every
  // lateness, a pixel of the row's: the coordinator of the migration's to rule, #6134)
  let (t, src, k) = rs_open(s, on_pixels=false)
  if !at_end {
    rs_read_up(t, s)
  }
  k.late = late
  let held = fn(what : String, grows : Bool, cause : () -> Unit) {
    if at_end {
      rsc_end_held(t, k, what, grows, cause)
    } else {
      rs_read_held(t, k, s, what, cause)
    }
  }
  let draft = @sfbase.writing(src, "ws1/st1:s-c1")
  let name = "\{s.0} late \{late}"
  let let_go = fn(what : String) {
    rs_push(out, held("\{name}: \{what}", false, fn() { rs_let_go(t, s) }))
    if rs_field_focused(t) {
      out.push("\{name}: \{what}: the composer still focused (the cause not made)")
    }
  }
  if rs_field_focused(t) {
    let_go("the focus let go, as it opened with it")
  }
  rs_push(out, held("\{name}: the focus taken", false, fn() { rs_focus(t) }))
  if !rs_field_focused(t) {
    out.push("\{name}: the composer's field not focused by a tap (the cause not made)")
  }
  t.type_text("第一行")
  rs_run(t, k.late + rs_watch_ms)
  rs_push(out, held("\{name}: a second line typed", true, fn() { rs_line(t, s.3, "第二行") }))
  rs_push(out, held("\{name}: a third line typed", true, fn() { rs_line(t, s.3, "第三行") }))
  let add_file = fn() { @sfbase.writing_add(src, draft, "ws1/st1", "build.log", @utf8.encode("夜里的构建日志")) }
  if with_cards {
    rs_push(out, held("\{name}: a file added", true, add_file))
    rs_push(
      out,
      held("\{name}: a quote added", true, fn() {
        @sfbase.writing_quote(src, draft, { "author": "Claude", "text": "第3条：好。", "ts": "ts3" })
      }),
    )
  }
  let_go("the focus let go")
  out
}

///|
test "read up on a chat's page made as nodes, 小屏, the core 0 ms late: the composer given the focus, a second and third line, and let go; the message read stays where it is in every frame" {
  assert_eq(rs_composer(long_screens[0], 0.0, false, with_cards=false), [])
}

///|
test "read up on a chat's page made as nodes, 小屏, the core 120 ms late: the composer given the focus, a second and third line, and let go; the message read stays where it is in every frame" {
  assert_eq(rs_composer(long_screens[0], 120.0, false, with_cards=false), [])
}

///|
test "read up on a chat's page made as nodes, 小屏, the core 400 ms late: the composer given the focus, a second and third line, and let go; the message read stays where it is in every frame" {
  assert_eq(rs_composer(long_screens[0], 400.0, false, with_cards=false), [])
}

///|
test "read up on a chat's page made as nodes, 大屏, the core 0 ms late: the composer let go of and given the focus, a second and third line, and let go; the message read stays where it is in every frame" {
  assert_eq(rs_composer(long_screens[1], 0.0, false, with_cards=false), [])
}

///|
test "read up on a chat's page made as nodes, 大屏, the core 120 ms late: the composer let go of and given the focus, a second and third line, and let go; the message read stays where it is in every frame" {
  assert_eq(rs_composer(long_screens[1], 120.0, false, with_cards=false), [])
}

///|
test "read up on a chat's page made as nodes, 大屏, the core 400 ms late: the composer let go of and given the focus, a second and third line, and let go; the message read stays where it is in every frame" {
  assert_eq(rs_composer(long_screens[1], 400.0, false, with_cards=false), [])
}

///|
test "at the end of a chat's page made as nodes, 小屏, the core 0 ms late: the composer given the focus, a second and third line, and let go; the last row still or up by what the composer grew, the composer never over it nor further from it" {
  assert_eq(rs_composer(long_screens[0], 0.0, true, with_cards=false), [])
}

///|
test "at the end of a chat's page made as nodes, 小屏, the core 120 ms late: the composer given the focus, a second and third line, and let go; the last row still or up by what the composer grew, the composer never over it nor further from it" {
  assert_eq(rs_composer(long_screens[0], 120.0, true, with_cards=false), [])
}

///|
test "at the end of a chat's page made as nodes, 小屏, the core 400 ms late: the composer given the focus, a second and third line, and let go; the last row still or up by what the composer grew, the composer never over it nor further from it" {
  assert_eq(rs_composer(long_screens[0], 400.0, true, with_cards=false), [])
}

///|
test "at the end of a chat's page made as nodes, 大屏, the core 0 ms late: the composer let go of and given the focus, a second and third line, and let go; the last row still or up by what the composer grew, the composer never over it nor further from it" {
  assert_eq(rs_composer(long_screens[1], 0.0, true, with_cards=false), [])
}

///|
test "at the end of a chat's page made as nodes, 大屏, the core 120 ms late: the composer let go of and given the focus, a second and third line, and let go; the last row still or up by what the composer grew, the composer never over it nor further from it" {
  assert_eq(rs_composer(long_screens[1], 120.0, true, with_cards=false), [])
}

///|
test "at the end of a chat's page made as nodes, 大屏, the core 400 ms late: the composer let go of and given the focus, a second and third line, and let go; the last row still or up by what the composer grew, the composer never over it nor further from it" {
  assert_eq(rs_composer(long_screens[1], 400.0, true, with_cards=false), [])
}

///|
test "a chat's page made as nodes, on 小屏: the keyboard coming up and going, the composer focused; read up the message read stays where it is in every frame, at the end the last row over the composer" {
  let broken : Array[String] = []
  let s = long_screens[0]
  let (_, w, h, _) = s
  let up = fn(t : @ui.Tester) {
    fn() {
      t.set_ime_inset(300.0)
      t.resize_next(w, h - 300.0)
    }
  }
  let down = fn(t : @ui.Tester) {
    fn() {
      t.set_ime_inset(0.0)
      t.resize_next(w, h)
    }
  }
  let (t, _, k) = rs_open(s)
  rs_read_up(t, s)
  rs_focus(t)
  rs_run(t, rs_watch_ms)
  rs_push(broken, rs_read_held(t, k, s, "the keyboard up", up(t)))
  rs_push(broken, rs_read_held(t, k, s, "the keyboard down", down(t)))
  let (t, _, k) = rs_open(s)
  rs_focus(t)
  rs_run(t, rs_watch_ms)
  rs_push(broken, rs_end_held(t, k, "the keyboard up", up(t)))
  rs_push(broken, rs_end_held(t, k, "the keyboard down", down(t)))
  assert_eq(broken, [])
}
