// Words said by a size alone, an old view's (Ctx::text's `size`, `color`) beside the node's (sized_words_node), with a
// finger and with keyboard and mouse: wrapped within their width, on one line as wide as they are (`wrap=false`), and
// on one line cut short where their row leaves them less (`max_lines=1`): where each stands, how big, its lines, what
// shows of it, the same; none of it taken for words that do not fit and never said they may be cut.

///|
/// What the column shows: a note wrapped within it, a status on one line, a path cut short before a status.
let sized_note : String = "按已发现的服务请求计算，新资源出现时更新，这一句长到要折行"

///|
let sized_path : String = "/api/builds/2026-11-10/a-very-long-name-of-a-resource.json"

///|
/// The old column (left, at 20) and the node's (right, at 220), each 160 wide, on a window of `platform`.
fn sized_tester(platform : Int) -> @ui.Tester {
  let t = @ui.Tester::new(fn(_c) {  }, w=420.0, h=300.0, platform~)
  t.check_looks(false)
  let caption = fn() { theme().t.caption }
  let meta = fn() { theme().t.meta }
  let muted = fn() { theme().p.muted }
  @ui.set_view_app(fn(root) {
    root.row(Is(true)).padding(Is((20.0, 20.0, 20.0, 20.0))).gap(Is(40.0)) |> ignore
    root.box(fn(h) {
      h.width(Is(Some(160.0))) |> ignore
      @ui.old(h, fn(c) {
        c.box(w=Fill(1.0), fn() {
          c.text(sized_note, size=caption(), color=muted()) |> ignore
          c.text("200", size=caption(), color=muted(), wrap=false) |> ignore
          c.box(dir=Row, w=Fill(1.0), gap=10.0, fn() {
            c.box(w=Fill(1.0), fn() { c.text(sized_path, size=meta(), color=muted(), max_lines=1) |> ignore }) |> ignore
            c.text("正在读取", size=caption(), color=muted(), wrap=false) |> ignore
          })
          |> ignore
        })
        |> ignore
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
    root.box(fn(col) {
      col.width(Is(Some(160.0))) |> ignore
      sized_words_node(col, fn() { sized_note }, caption, muted) |> ignore
      sized_words_node(col, fn() { "200" }, caption, muted, wrap=false) |> ignore
      col.box(fn(line) {
        line.row(Is(true)).gap(Is(10.0)) |> ignore
        sized_words_node(line, fn() { sized_path }, meta, muted, cut=true).grow(Is(1.0)).basis(Is(Some(0.0))) |> ignore
        sized_words_node(line, fn() { "正在读取" }, caption, muted, wrap=false) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
/// The words drawn from `x0` to `x0 + 160`, each where it is from (x0, 20), how big, how opaque, and the glyphs drawn
/// there (what shows of words cut short: as many, at the same places, in the same ink).
fn sized_side(t : @ui.Tester, x0 : Double) -> (Array[String], Array[String]) {
  let words = t
    .words()
    .filter(fn(w) { w.1 >= x0 - 0.5 && w.1 <= x0 + 160.0 })
    .map(fn(w) { "\{w.0}@\{w.1 - x0},\{w.2 - 20.0} \{w.3}x\{w.4} a\{w.5}" })
  words.sort()
  let glyphs = t
    .drawn_glyphs()
    .filter(fn(g) { g.0 >= x0 - 0.5 && g.0 <= x0 + 160.0 })
    .map(fn(g) { "\{g.0 - x0},\{g.1 - 20.0} \{g.2}" })
  glyphs.sort()
  (words, glyphs)
}

///|
test "words said by a size alone: the node's where the old view's are, as big, on lines as high, what shows of them cut short the same; with a finger and with keyboard and mouse" {
  for platform in [2, 0] {
    let t = sized_tester(platform)
    let (old_words, old_glyphs) = sized_side(t, 20.0)
    let (new_words, new_glyphs) = sized_side(t, 220.0)
    assert_eq(new_words, old_words, msg="platform \{platform}: the words")
    assert_eq(new_glyphs, old_glyphs, msg="platform \{platform}: the glyphs")
    // (the note wrapped, the path cut short: there is something to see in each)
    assert_true(old_words.iter().any(fn(w) { w.has_prefix(sized_note) }), msg="platform \{platform}: \{Repr(old_words)}")
    let lines = t.words().filter(fn(w) { w.0 == sized_note })
    assert_true(lines.length() == 2 && lines.iter().all(fn(w) { w.4 > 30.0 }), msg="platform \{platform}: wrapped \{Repr(lines)}")
    // (the node's said to be cut where it has less room: no fault of words that do not fit of its; the old view's path,
    // max_lines=1, is taken for words wrapped narrower than they need, its own way)
    let faults = t.squeeze_faults().filter(fn(f) { !f.contains("in an old view") })
    assert_eq(faults, [], msg="platform \{platform}: \{Repr(faults)}")
  }
}
