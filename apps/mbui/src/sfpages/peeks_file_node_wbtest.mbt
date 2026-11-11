// What a file's card holds as nodes (peeks_file_node.mbt's file_card_node) set beside the old view's (peeks.mbt
// file_card) in the same room, as the same reading of the file says: the words where they were and the rectangles
// drawn the same, in each state it shows (a text's lines, the one named marked, before and after the core says their
// colours; a picture; a directory's entries; a file that is no text; why not, refused; its bones while it is read; its
// path copied, and as it stops saying so; its words at 1.3).

///|
/// What a card stands in, in both: a hover card's width, a little under the window's top, what it holds as far in
/// as a hover card holds it (hover_inner).
// kept across runs: a value (no field of it changes)
let pf_frame : @ui.Style = @ui.css("pt=S4").then(@ui.style(w=@sf.hover_card_w))

///|
/// The station and the session that name the file.
// kept across runs: a value
let pf_station : String = "ws1/st1"

///|
// kept across runs: a value
let pf_session : String = "s-c1"

///|
/// How the core says a file's colours in a case: not asked of one (none here), asked and not yet said, said at once.
#derive(Eq)
priv enum PfInk {
  NoCore
  Asked
  Said
}

///|
/// What each piece of the fixture's code is, as the test's core says it: all of each line of it a function's colour.
fn pf_ink(code : String) -> String {
  "i" + code.length().to_string()
}

///|
/// The test's core, bound as the run's first frame is built (a Tester's start forgets what was bound before it), as
/// `ink` says.
fn pf_core(ink : PfInk) -> Unit {
  if @sf.ink_read.val is None && ink != NoCore {
    pf_asked.val = 0
    @sf.ink_read.val = Some(fn(code, _, done) {
      pf_asked.val += 1
      if ink == Said {
        done(Some(pf_ink(code)))
      }
    })
  }
}

///|
/// How many times the test's core was asked a file's colours, since it was bound.
// kept across runs: counted from where pf_core binds the core
let pf_asked : Ref[Int] = Ref(0)

///|
/// The source the card reads, the file as `read` says it (the `filePeek` topic's value and error); the pictures it
/// names counted as they are asked (pf_pictures), kept in `held` till the test answers them where it is given; the
/// rest the fixture's.
fn pf_src(read : () -> (Json?, Json?), held? : Array[(String, Json, (Result[(Json, Bytes), Json]) -> Unit)]) -> Source {
  @sfbase.reset()
  @sf.set_words(@sfbase.fill)
  pf_pictures.val = 0
  let made = @sffixture.fixture("rich-chat")
  {
    ..made,
    read_bytes: fn(name, params, done) {
      if name == "file.peek.picture" {
        pf_pictures.val += 1
      }
      match held {
        Some(h) => h.push((name, params, done))
        None => (made.read_bytes)(name, params, done)
      }
    },
    topic_read: fn(name, params) {
      if name == "filePeek" {
        let (value, error) = read()
        { value, error, version: if value is None && error is None { 0 } else { 1 } }
      } else {
        made.topic(name, params).get().snapshot()
      }
    },
  }
}

///|
/// How many times the source made last was asked a file's picture.
// kept across runs: counted from where pf_src makes the source
let pf_pictures : Ref[Int] = Ref(0)

///|
/// The params the card is read by.
fn pf_params(path : String, line : Int?) -> Map[String, Json] {
  file_peek_params(pf_station, pf_session, path, line)
}

///|
/// The old view's card (file_card) of `path` at `line`, read as `read` says, colours as `ink` says.
fn pf_old(path : String, line : Int?, read : () -> (Json?, Json?), ink : PfInk, scale? : Double = 1.0) -> @ui.Tester {
  let src = pf_src(read)
  let t = @ui.Tester::new(
    fn(c) {
      @sfbase.held_build()
      c.after_build("held/end", fn() { @sfbase.held_end() })
      @sf.begin(c) |> ignore
      pf_core(ink)
      c.with_theme(@sf.ui_theme(), fn() {
        c.box(style=pf_frame, fn() {
          c.box(style=hover_inner, fn() {
            file_card(c, src, "pf", pf_params(path, line), pf_station, pf_session, path, line)
          })
          |> ignore
        })
        |> ignore
      })
    },
    w=400.0,
    h=720.0,
    native=Mouse,
    pointing=Mouse,
  )
  if scale != 1.0 {
    t.set_font_scale(scale)
  }
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// The nodes' card (file_card_node) of the same, in the same room.
fn pf_new(
  path : String,
  line : Int?,
  read : () -> (Json?, Json?),
  ink : PfInk,
  scale? : Double = 1.0,
  held? : Array[(String, Json, (Result[(Json, Bytes), Json]) -> Unit)],
) -> @ui.Tester {
  let src = pf_src(read, held?)
  let t = @ui.Tester::new(
    fn(c) {
      @sf.begin(c) |> ignore
      c.with_theme(@sf.ui_theme(), fn() { @ui.old_views_here(c) })
    },
    tree=fn(root) {
      @ui.set_tree_theme(@sf.ui_theme_now)
      pf_core(ink)
      root.box(fn(f) {
        @sf.style_node(f, fn() { pf_frame })
        f.box(fn(inner) {
          @sf.style_node(inner, fn() { hover_inner })
          let read = @sfbase.hold(src, "pf-node", "filePeek", pf_params(path, line))
          file_card_node(inner, src, pf_station, pf_session, path, line, read)
        })
        |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=720.0,
    native=Mouse,
    pointing=Mouse,
  )
  if scale != 1.0 {
    t.set_font_scale(scale)
  }
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// The fixture's files the core reads, by what they are.
fn pf_dir() -> Json {
  {
    "kind": "dir",
    "path": "/Users/lin/shop/src/list/",
    "name": "list",
    "count": 5,
    "entries": ["place.mbt", "rows.mbt", "moon.pkg", "tests/", "README.md"],
    "time": { "mtime": { "at": 0, "ago": "5 分钟前", "full": "10/26 11:00", "until": "", "past": true } },
  }
}

///|
fn pf_binary() -> Json {
  {
    "kind": "binary",
    "path": "/Users/lin/shop/build/app.wasm",
    "name": "app.wasm",
    "size": 1234567,
    "time": { "mtime": { "at": 0, "ago": "1 小时前", "full": "10/26 10:00", "until": "", "past": true } },
  }
}

///|
/// What a Tester draws (head_drawn's), each place and size to a hundredth of a point: a bar of a card's bones is worked
/// out as a sum in one and a difference in the other, 6.600000000000001 and 6.6.
fn pf_drawn(t : @ui.Tester) -> String {
  let r = fn(x : Double) { (x * 100.0).round() / 100.0 }
  t.words().map(fn(w) { "\{w.0}@\{r(w.1)},\{r(w.2)} \{r(w.3)}x\{r(w.4)} a\{w.5}" }).join("\n") +
  "\n" +
  t.drawn_rects().map(fn(d) { "\{r(d.0)},\{r(d.1)} \{r(d.2)}x\{r(d.3)} \{d.4}" }).join("\n")
}

///|
/// How many of a file's lines `t.audit()` says are too faint to read: code in the colours the core says (vitesse's,
/// made to read on a code block's ground, ink.mbt) on the hover's ground a line stands on, or the accent's pale one the
/// line named does (4.48:1 and less, under 4.5). As the old view draws them, the same colours on the same grounds: its
/// colours are the product's, kept as they are (the brief: contrast is how it looks, not moved here). Read before the
/// nodes' Tester is made.
fn pf_faint(old : @ui.Tester) -> Int {
  old.audit().filter(fn(f) { f.contains(":1, under 4.5") }).length()
}

///|
/// What `t.audit()` says of the nodes' card, but its lines too faint to read where the old view's were too, as many
/// (pf_faint's `faint`): one more or one fewer is a fault, so that once their colours are mended this is taken out.
fn pf_audit(t : @ui.Tester, faint : Int) -> Array[String] {
  let all = t.audit()
  let known = all.filter(fn(f) { f.contains(":1, under 4.5") && f.contains("sfpages/peeks_file_node.mbt") })
  let faults = all.filter(fn(f) { !known.contains(f) })
  if known.length() != faint {
    faults.push("lines too faint \{known.length()} times, \{faint} as the old view drew them: " + known.join(" | "))
  }
  faults
}

///|
/// Each state, by name: the path, the line, what the core reads, how it says the colours.
fn pf_cases() -> Array[(String, String, Int?, (Json?, Json?), PfInk)] {
  let text = Some(@sffixture.fixture_file_peek("src/list/place.mbt"))
  [
    ("lines, no core to colour them", "src/list/place.mbt", Some(12), (text, None), NoCore),
    ("lines, colours asked", "src/list/place.mbt", Some(12), (text, None), Asked),
    ("lines, colours said", "src/list/place.mbt", Some(12), (text, None), Said),
    ("a picture", "shots/list.png", None, (Some(@sffixture.fixture_file_peek("shots/list.png")), None), Said),
    ("a directory", "src/list/", None, (Some(pf_dir()), None), Said),
    ("no text", "build/app.wasm", None, (Some(pf_binary()), None), Said),
    ("refused", "src/gone.mbt", None, (None, Some({ "message": "没有这个文件" })), Said),
    ("read", "src/list/place.mbt", Some(12), (None, None), Said),
  ]
}

///|
test "a file's card made once as nodes holds what the old view's did: lines marked and coloured as the core says, a picture, a directory, no text, refused, its bones" {
  for c in pf_cases() {
    let (name, path, line, read, ink) = c
    let old = pf_old(path, line, fn() { read }, ink)
    let was = pf_drawn(old)
    let faint = pf_faint(old)
    let t = pf_new(path, line, fn() { read }, ink)
    assert_eq(pf_drawn(t), was, msg=name)
    // (its colours asked once where it shows lines of a language; in its bones, made-up lines, never)
    let asks = if ink == NoCore || path != "src/list/place.mbt" || read.0 is None { 0 } else { 1 }
    assert_eq(pf_asked.val, asks, msg=name)
    // (its picture asked once, as the file is read, where it names one; none asked for another or its bones)
    assert_eq(pf_pictures.val, if name == "a picture" { 1 } else { 0 }, msg=name)
    assert_eq(pf_audit(t, faint), [], msg=name)
  }
}

///|
test "a file's card's path copied says so copied_ms from the press, then asks to be copied again, as the old view's did" {
  let read = (Some(@sffixture.fixture_file_peek("src/list/place.mbt")), None)
  let old = pf_old("src/list/place.mbt", Some(12), fn() { read }, NoCore)
  old.tap_text(@sf.t("web-main.preview.copyPath"))
  old.run_for(@ui.move_most_ms)
  let said = pf_drawn(old)
  old.run_for(@sf.copied_ms)
  let again = pf_drawn(old)
  let faint = pf_faint(old)
  let t = pf_new("src/list/place.mbt", Some(12), fn() { read }, NoCore)
  t.tap_text(@sf.t("web-main.preview.copyPath"))
  t.run_for(@ui.move_most_ms)
  assert_eq(pf_drawn(t), said)
  assert_true(t.find(@sf.t("common.copied")) is Some(_))
  t.run_for(@sf.copied_ms)
  assert_eq(pf_drawn(t), again)
  assert_true(t.find(@sf.t("web-main.preview.copyPath")) is Some(_))
  assert_eq(pf_audit(t, faint), [])
}

///|
test "a file's card at the system's words set to 1.3 holds what the old view's did: its lines, a directory" {
  for c in pf_cases() {
    let (name, path, line, read, ink) = c
    guard name == "lines, colours said" || name == "a directory" else { continue }
    let old = pf_old(path, line, fn() { read }, ink, scale=1.3)
    let was = pf_drawn(old)
    let faint = pf_faint(old)
    let t = pf_new(path, line, fn() { read }, ink, scale=1.3)
    assert_eq(pf_drawn(t), was, msg=name)
    assert_eq(pf_audit(t, faint), [], msg=name)
  }
}

///|
test "a file's card read while it shows: its bones, then the file in their place as the old view's shows it, coloured" {
  let text : (Json?, Json?) = (Some(@sffixture.fixture_file_peek("src/list/place.mbt")), None)
  let old = pf_old("src/list/place.mbt", Some(12), fn() { text }, Said)
  let was = pf_drawn(old)
  let faint = pf_faint(old)
  let read : @signals.Signal[(Json?, Json?)] = @signals.signal((None, None))
  let t = pf_new("src/list/place.mbt", Some(12), fn() { read.get() }, Said)
  assert_true(t.find("place.mbt:12") is None)
  assert_eq(pf_asked.val, 0, msg="nothing asked of its bones")
  read.set(text)
  t.run_for(@ui.move_most_ms)
  assert_eq(pf_drawn(t), was)
  assert_eq(pf_asked.val, 1)
  assert_eq(pf_audit(t, faint), [])
}

///|
test "a file's card's picture told as it comes: its bones till then, asked once as the file is read, then the picture as the old view's shows it" {
  let read : (Json?, Json?) = (Some(@sffixture.fixture_file_peek("shots/list.png")), None)
  let old = pf_old("shots/list.png", None, fn() { read }, Said)
  let was = pf_drawn(old)
  let faint = pf_faint(old)
  let held = []
  let t = pf_new("shots/list.png", None, fn() { read }, Said, held~)
  assert_eq(held.map(fn(a) { a.0 }), ["file.peek.picture"], msg="asked once as it is read")
  assert_eq(pf_pictures.val, 1)
  assert_true(pf_drawn(t) != was, msg="its bones while the picture comes")
  // (the picture's answer, from outside: shown the frame after)
  let now = held.copy()
  held.clear()
  for a in now {
    (a.2)(@sffixture.fixture_peek_picture(a.0, a.1).unwrap())
  }
  @ui.came_from_outside()
  t.run_for(@ui.move_most_ms)
  assert_eq(pf_drawn(t), was)
  assert_eq(pf_pictures.val, 1, msg="asked no more")
  assert_eq(pf_audit(t, faint), [])
}
