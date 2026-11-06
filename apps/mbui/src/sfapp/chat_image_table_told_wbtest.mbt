// A message's table whose one cell is only images: the images as its words and files are told last, whether the table
// was made with them as they are now or first with a file told another size, another file, the files in another
// order, one more or fewer, or words.

///|
/// A chat whose last message is a table of one column, its cell only 乙; 乙's file told wide (640×320) when
/// `last_wide`, else upright (320×640), told the other way first when `first`, its column's head `head`: what is seen of 乙 (its press's room, the
/// pictures drawn), what pressing it opens, and 乙 after the preview is shut.
fn table_told(last_wide : Bool, first? : Bool = false, head? : String = "图") -> String raise {
  let images = @sfbase.ChatImages::new()
  let calls : Array[Made] = []
  let told = @signals.signal(0)
  let text = "| \{head} |\n| --- |\n| ![乙](row-b.png) |"
  let tree : Json = [["table", [["tr", [["th", [Json::string(head)]]]], ["tr", [["td", [["img", { "src": "row-b.png" }]]]]]]]]
  let t = wide_tester(calls, mode="chat-many-images", w=390.0, h=844.0, platform=2, wrap=fn(base) {
    { ..base, images,
      topic: fn(name, params) {
        let got = (base.topic)(name, params)
        if name != "chat" { return got }
        let version = told.get()
        guard version > 0 && got.value is Some(value) else { return got }
        // (version 1: the other way first; 2: as it is last)
        let wide = if version == 1 { !last_wide } else { last_wide }
        let (w, h) = if wide { (640, 320) } else { (320, 640) }
        let files : Array[Json] = [
          { "name": "row-b.png", "path": "work/s-c1/row-b.png", "owner": "s-c1", "width": Json::number(w.to_double()), "height": Json::number(h.to_double()) },
        ]
        { ..got, version: got.version + version, value: Some(with_chat_message(value, 129.0, [
          ("text", Json::string(text)), ("placed", ["row-b.png"]), ("attachments", Json::array(files)),
        ])) }
      },
      file: fn(station, owner, name) {
        images.get(station, @sfbase.file_image_id(station, owner, name), "mem:table-told/" + name, fn(_, done) {
          done(Ok((Json::object({}), Some(fixture_file_png("many-0.png")))))
        })
      },
    }
  })
  // (the picture as big as its file is last told)
  if last_wide {
    t.add_image("mem:table-told/row-b.png", 640, 320)
  } else {
    t.add_image("mem:table-told/row-b.png", 320, 640)
  }
  t.check_looks(false)
  t.run_for(first_page_ms + @ui.move_most_ms + @sfpages.reveal_ms)
  @sf.markdown_read.val = Some(fn(words, done) { done(if words == text { Some(tree) } else { None }) })
  told.set(if first { 1 } else { 2 })
  t.run_for(@ui.move_most_ms)
  let ids = fn() { t.semantics().filter(fn(s) { s.label.contains("row-b.png") }).map(fn(s) { s.id }) }
  let was = ids()
  if first {
    told.set(2)
    t.run_for(@ui.move_most_ms)
  }
  let kept = if first { " (the same image as first told: \{ids() == was && was.length() > 0})" } else { "" }
  let r = fn(x : Double) { x.round() }
  let rect = fn(q : (Double, Double, Double, Double)) { (r(q.0), r(q.1), r(q.2), r(q.3)) }
  let seen = fn() {
    let found = t.semantics().filter(fn(s) { s.label.contains("row-b.png") })
    let room = found.map(fn(s) { "\{rect((s.rect.0, s.rect.1, s.rect.2, s.rect.3))}" })
    let drawn = t.drawn_images().filter(fn(i) { i[8] > 0.5 && i[2] > 40.0 }).map(fn(i) { rect((i[0], i[1], i[2], i[3])) })
    "room \{room}, drawn \{drawn}"
  }
  let shown = seen()
  let found = t.semantics().filter(fn(s) { s.label.contains("row-b.png") })
  guard found.length() > 0 else { fail("乙 not found: \{shown}") }
  let b = found[0].rect
  t.tap(b.0 + b.2 / 2.0, b.1 + b.3 / 2.0)
  let opened = viewer.get().map(fn(v) { v.file.path })
  t.run_for(@ui.move_most_ms * 2.0)
  t.back()
  t.run_for(@ui.move_most_ms * 2.0)
  let after = seen()
  @sf.markdown_read.val = None
  "\{if head != "图" { "under a wide head, " } else { "" }}\{if first { "told the other way first, then " } else { "" }}\{if last_wide { "wide" } else { "upright" }}\{kept}: \{shown}; pressed at its middle, opened \{opened}; shut, \{after}, open \{viewer.get() is Some(_)}"
}

///|
/// (a head wider than either image: its column wider than the cell's images)
let wide_head = "这一列的标题写得比图片宽很多很多很多"

///|
test "a table's cell of only an image whose file is told another size after the table is made: the same as the table made with the file as it is now, as wide as its proportion says under a wide head too" {
  let seen = [
    table_told(false), table_told(false, first=true), table_told(true), table_told(true, first=true),
    table_told(false, head=wide_head), table_told(false, first=true, head=wide_head), table_told(true, head=wide_head),
    table_told(true, first=true, head=wide_head),
  ]
  // (told the other way first, then as it is: what is seen, pressed and shut the same as the table made with it so)
  let body = fn(s : String) { s.view(start_offset=s.find(": room").unwrap()).to_owned() }
  for i in [0, 2, 4, 6] {
    assert_eq(body(seen[i + 1]), body(seen[i]))
  }
  // (under a wide head as under a narrow one: as wide as cell_image_width says, not as the column)
  assert_eq(body(seen[4]), body(seen[0]))
  assert_eq(body(seen[6]), body(seen[2]))
  inspect(
    seen.join("\n"),
    content=(
      #|upright: room [(16, 424, 128, 240)], drawn [(16, 62, 358, 269), (16, 424, 128, 240)]; pressed at its middle, opened Some(work/s-c1/row-b.png); shut, room [(16, 424, 128, 240)], drawn [(16, 62, 358, 269), (16, 424, 128, 240)], open false
      #|told the other way first, then upright (the same image as first told: true): room [(16, 424, 128, 240)], drawn [(16, 62, 358, 269), (16, 424, 128, 240)]; pressed at its middle, opened Some(work/s-c1/row-b.png); shut, room [(16, 424, 128, 240)], drawn [(16, 62, 358, 269), (16, 424, 128, 240)], open false
      #|wide: room [(16, 584, 160, 80)], drawn [(16, -118, 358, 269), (16, 222, 358, 269), (16, 584, 160, 80)]; pressed at its middle, opened Some(work/s-c1/row-b.png); shut, room [(16, 584, 160, 80)], drawn [(16, -118, 358, 269), (16, 222, 358, 269), (16, 584, 160, 80)], open false
      #|told the other way first, then wide (the same image as first told: true): room [(16, 584, 160, 80)], drawn [(16, -118, 358, 269), (16, 222, 358, 269), (16, 584, 160, 80)]; pressed at its middle, opened Some(work/s-c1/row-b.png); shut, room [(16, 584, 160, 80)], drawn [(16, -118, 358, 269), (16, 222, 358, 269), (16, 584, 160, 80)], open false
      #|under a wide head, upright: room [(16, 424, 128, 240)], drawn [(16, 62, 358, 269), (16, 424, 128, 240)]; pressed at its middle, opened Some(work/s-c1/row-b.png); shut, room [(16, 424, 128, 240)], drawn [(16, 62, 358, 269), (16, 424, 128, 240)], open false
      #|under a wide head, told the other way first, then upright (the same image as first told: true): room [(16, 424, 128, 240)], drawn [(16, 62, 358, 269), (16, 424, 128, 240)]; pressed at its middle, opened Some(work/s-c1/row-b.png); shut, room [(16, 424, 128, 240)], drawn [(16, 62, 358, 269), (16, 424, 128, 240)], open false
      #|under a wide head, wide: room [(16, 584, 160, 80)], drawn [(16, -118, 358, 269), (16, 222, 358, 269), (16, 584, 160, 80)]; pressed at its middle, opened Some(work/s-c1/row-b.png); shut, room [(16, 584, 160, 80)], drawn [(16, -118, 358, 269), (16, 222, 358, 269), (16, 584, 160, 80)], open false
      #|under a wide head, told the other way first, then wide (the same image as first told: true): room [(16, 584, 160, 80)], drawn [(16, -118, 358, 269), (16, 222, 358, 269), (16, 584, 160, 80)]; pressed at its middle, opened Some(work/s-c1/row-b.png); shut, room [(16, 584, 160, 80)], drawn [(16, -118, 358, 269), (16, 222, 358, 269), (16, 584, 160, 80)], open false
    ),
  )
}

///|
/// A chat whose last message is a table of one column, its cell `shows` (each "w": tbl-w.png, wide 640×320; "u":
/// tbl-u.png, upright 320×640; "words": words), told as `first` shows first when it is given: each image's press's room
/// by its file, the pictures drawn; each pressed at its middle, what it opens, and all after the preview is shut.
fn table_shows(shows : Array[String], first? : Array[String]) -> String raise {
  let images = @sfbase.ChatImages::new()
  let calls : Array[Made] = []
  let told = @signals.signal(0)
  let text_of = fn(xs : Array[String]) {
    let cell = xs.map(fn(x) { if x == "words" { "说明" } else { "![](tbl-\{x}.png)" } }).join("")
    "| 图 |\n| --- |\n| \{cell} |"
  }
  let tree_of = fn(xs : Array[String]) -> Json {
    let cell : Array[Json] = xs.map(fn(x) -> Json {
      if x == "words" { Json::string("说明") } else { ["img", { "src": Json::string("tbl-\{x}.png") }] }
    })
    [["table", [["tr", [["th", ["图"]]]], ["tr", [["td", Json::array(cell)]]]]]]
  }
  let t = wide_tester(calls, mode="chat-many-images", w=390.0, h=844.0, platform=2, wrap=fn(base) {
    { ..base, images,
      topic: fn(name, params) {
        let got = (base.topic)(name, params)
        if name != "chat" { return got }
        let version = told.get()
        guard version > 0 && got.value is Some(value) else { return got }
        let xs = if version == 1 { first.unwrap_or(shows) } else { shows }
        let files : Array[Json] = [
          { "name": "tbl-w.png", "path": "work/s-c1/tbl-w.png", "owner": "s-c1", "width": 640, "height": 320 },
          { "name": "tbl-u.png", "path": "work/s-c1/tbl-u.png", "owner": "s-c1", "width": 320, "height": 640 },
        ]
        { ..got, version: got.version + version, value: Some(with_chat_message(value, 129.0, [
          ("text", Json::string(text_of(xs))), ("placed", ["tbl-w.png", "tbl-u.png"]), ("attachments", Json::array(files)),
        ])) }
      },
      file: fn(station, owner, name) {
        images.get(station, @sfbase.file_image_id(station, owner, name), "mem:table-shows/" + name, fn(_, done) {
          done(Ok((Json::object({}), Some(fixture_file_png("many-0.png")))))
        })
      },
    }
  })
  t.add_image("mem:table-shows/tbl-w.png", 640, 320)
  t.add_image("mem:table-shows/tbl-u.png", 320, 640)
  t.check_looks(false)
  t.run_for(first_page_ms + @ui.move_most_ms + @sfpages.reveal_ms)
  let trees = [first.unwrap_or(shows), shows].map(fn(xs) { (text_of(xs), tree_of(xs)) })
  @sf.markdown_read.val = Some(fn(words, done) {
    done(trees.search_by(fn(x) { x.0 == words }).map(fn(i) { trees[i].1 }))
  })
  told.set(if first is Some(_) { 1 } else { 2 })
  t.run_for(@ui.move_most_ms)
  if first is Some(_) {
    told.set(2)
    t.run_for(@ui.move_most_ms)
  }
  let r = fn(x : Double) { x.round() }
  let rect = fn(q : (Double, Double, Double, Double)) { (r(q.0), r(q.1), r(q.2), r(q.3)) }
  let found = fn() { t.semantics().filter(fn(s) { s.label.contains("tbl-") && s.label.contains(".png") }) }
  let file_of = fn(label : String) { if label.contains("tbl-w.png") { "w" } else if label.contains("tbl-u.png") { "u" } else { "?" } }
  let seen = fn() {
    let room = found().map(fn(s) { "\{file_of(s.label)} \{rect((s.rect.0, s.rect.1, s.rect.2, s.rect.3))}" })
    let drawn = t.drawn_images().filter(fn(i) { i[8] > 0.5 && i[2] > 40.0 && i[1] > 300.0 }).map(fn(i) { rect((i[0], i[1], i[2], i[3])) })
    let words = t.semantics().filter(fn(s) { s.label == "说明" }).length()
    "rooms \{room}, drawn \{drawn}, words \{words}"
  }
  let shown = seen()
  let pressed = found().map(fn(s) {
    let b = s.rect
    t.tap(b.0 + b.2 / 2.0, b.1 + b.3 / 2.0)
    let opened = viewer.get().map(fn(v) { v.file.path })
    t.run_for(@ui.move_most_ms * 2.0)
    t.back()
    t.run_for(@ui.move_most_ms * 2.0)
    "\{file_of(s.label)} opened \{opened}, hidden after \{pv_hidden.get() != ""}"
  })
  let after = seen()
  @sf.markdown_read.val = None
  let said = fn(xs : Array[String]) { xs.join(" ") }
  "\{first.map(fn(xs) { said(xs) + " then " }).unwrap_or("")}\{said(shows)}: \{shown}; pressed \{pressed}; shut, \{if after == shown { "the same" } else { after }}"
}

///|
test "a table's cell of images made again with other images, in another order, one more or fewer, or words: the same as the table made with them so" {
  let cases : Array[(Array[String], Array[String])] = [
    (["w"], ["u"]), (["u"], ["w"]), (["w", "u"], ["u", "w"]), (["w"], ["w", "u"]), (["w", "u"], ["u"]), (["w"], ["words"]),
    (["words"], ["u"]),
  ]
  let seen = []
  for c in cases {
    let made = table_shows(c.1)
    let told = table_shows(c.1, first=c.0)
    // (what is seen, pressed and shut: the same whatever the cell showed first)
    let body = fn(s : String) { s.view(start_offset=s.find(": rooms").unwrap()).to_owned() }
    assert_eq(body(told), body(made))
    seen.push(made)
    seen.push(told)
  }
  inspect(
    seen.join("\n"),
    content=(
      #|u: rooms [u (16, 424, 128, 240)], drawn [(16, 424, 128, 240)], words 0; pressed [u opened Some(work/s-c1/tbl-u.png), hidden after false]; shut, the same
      #|w then u: rooms [u (16, 424, 128, 240)], drawn [(16, 424, 128, 240)], words 0; pressed [u opened Some(work/s-c1/tbl-u.png), hidden after false]; shut, the same
      #|w: rooms [w (16, 584, 160, 80)], drawn [(16, 584, 160, 80)], words 0; pressed [w opened Some(work/s-c1/tbl-w.png), hidden after false]; shut, the same
      #|u then w: rooms [w (16, 584, 160, 80)], drawn [(16, 584, 160, 80)], words 0; pressed [w opened Some(work/s-c1/tbl-w.png), hidden after false]; shut, the same
      #|u w: rooms [u (16, 424, 128, 240), w (150, 424, 160, 80)], drawn [(16, 424, 128, 240), (150, 424, 160, 80)], words 0; pressed [u opened Some(work/s-c1/tbl-u.png), hidden after false, w opened Some(work/s-c1/tbl-w.png), hidden after false]; shut, the same
      #|w u then u w: rooms [u (16, 424, 128, 240), w (150, 424, 160, 80)], drawn [(16, 424, 128, 240), (150, 424, 160, 80)], words 0; pressed [u opened Some(work/s-c1/tbl-u.png), hidden after false, w opened Some(work/s-c1/tbl-w.png), hidden after false]; shut, the same
      #|w u: rooms [w (16, 424, 160, 80), u (182, 424, 128, 240)], drawn [(16, 424, 160, 80), (182, 424, 128, 240)], words 0; pressed [w opened Some(work/s-c1/tbl-w.png), hidden after false, u opened Some(work/s-c1/tbl-u.png), hidden after false]; shut, the same
      #|w then w u: rooms [w (16, 424, 160, 80), u (182, 424, 128, 240)], drawn [(16, 424, 160, 80), (182, 424, 128, 240)], words 0; pressed [w opened Some(work/s-c1/tbl-w.png), hidden after false, u opened Some(work/s-c1/tbl-u.png), hidden after false]; shut, the same
      #|u: rooms [u (16, 424, 128, 240)], drawn [(16, 424, 128, 240)], words 0; pressed [u opened Some(work/s-c1/tbl-u.png), hidden after false]; shut, the same
      #|w u then u: rooms [u (16, 424, 128, 240)], drawn [(16, 424, 128, 240)], words 0; pressed [u opened Some(work/s-c1/tbl-u.png), hidden after false]; shut, the same
      #|words: rooms [], drawn [], words 1; pressed []; shut, the same
      #|w then words: rooms [], drawn [], words 1; pressed []; shut, the same
      #|u: rooms [u (16, 424, 128, 240)], drawn [(16, 424, 128, 240)], words 0; pressed [u opened Some(work/s-c1/tbl-u.png), hidden after false]; shut, the same
      #|words then u: rooms [u (16, 424, 128, 240)], drawn [(16, 424, 128, 240)], words 0; pressed [u opened Some(work/s-c1/tbl-u.png), hidden after false]; shut, the same
    ),
  )
}

///|
/// A chat whose last message is a table of one column, its cell `shows` first (as table_shows has them; "s": tbl-s.png,
/// square 400×400), the image A pressed (the `press`th), its preview opening (`during` "opening": halfway out) or
/// shutting ("shutting": an eighth of the way back) as the cell is told to show `then` (and `more` after it): what A is after (the same image or made again, where
/// it is drawn, where the preview flew back into, pressed again what it opens), what the others are, and each file's
/// pictures asked for again after the change.
fn table_pair_kept(shows : Array[String], then : Array[String], during : String, more? : Array[Array[String]] = [], press? : Int = 0) -> String raise {
  let images = @sfbase.ChatImages::new()
  let calls : Array[Made] = []
  let told = @signals.signal(0)
  let asked : Map[String, Int] = {}
  let text_of = fn(xs : Array[String]) {
    "| 图 |\n| --- |\n| \{xs.map(fn(x) { "![](tbl-\{x}.png)" }).join("")} |"
  }
  let tree_of = fn(xs : Array[String]) -> Json {
    let cell : Array[Json] = xs.map(fn(x) -> Json { ["img", { "src": Json::string("tbl-\{x}.png") }] })
    [["table", [["tr", [["th", ["图"]]]], ["tr", [["td", Json::array(cell)]]]]]]
  }
  let t = wide_tester(calls, mode="chat-many-images", w=390.0, h=844.0, platform=2, wrap=fn(base) {
    { ..base, images,
      topic: fn(name, params) {
        let got = (base.topic)(name, params)
        if name != "chat" { return got }
        let version = told.get()
        guard version > 0 && got.value is Some(value) else { return got }
        let xs = if version == 1 { shows } else if version == 2 { then } else { more[version - 3] }
        let files : Array[Json] = [
          { "name": "tbl-w.png", "path": "work/s-c1/tbl-w.png", "owner": "s-c1", "width": 640, "height": 320 },
          { "name": "tbl-u.png", "path": "work/s-c1/tbl-u.png", "owner": "s-c1", "width": 320, "height": 640 },
          { "name": "tbl-s.png", "path": "work/s-c1/tbl-s.png", "owner": "s-c1", "width": 400, "height": 400 },
        ]
        { ..got, version: got.version + version, value: Some(with_chat_message(value, 129.0, [
          ("text", Json::string(text_of(xs))), ("placed", ["tbl-w.png", "tbl-u.png", "tbl-s.png"]),
          ("attachments", Json::array(files)),
        ])) }
      },
      file: fn(station, owner, name) {
        asked[name] = asked.get(name).unwrap_or(0) + 1
        images.get(station, @sfbase.file_image_id(station, owner, name), "mem:table-pair/" + name, fn(_, done) {
          done(Ok((Json::object({}), Some(fixture_file_png("many-0.png")))))
        })
      },
    }
  })
  t.add_image("mem:table-pair/tbl-w.png", 640, 320)
  t.add_image("mem:table-pair/tbl-u.png", 320, 640)
  t.add_image("mem:table-pair/tbl-s.png", 400, 400)
  t.check_looks(false)
  t.run_for(first_page_ms + @ui.move_most_ms + @sfpages.reveal_ms)
  let all_told = [shows, then]
  all_told.append(more)
  let trees = all_told.map(fn(xs) { (text_of(xs), tree_of(xs)) })
  @sf.markdown_read.val = Some(fn(words, done) {
    done(trees.search_by(fn(x) { x.0 == words }).map(fn(i) { trees[i].1 }))
  })
  told.set(1)
  t.run_for(@ui.move_most_ms)
  let r = fn(x : Double) { x.round() }
  let rect = fn(q : (Double, Double, Double, Double)) { (r(q.0), r(q.1), r(q.2), r(q.3)) }
  let found = fn() { t.semantics().filter(fn(s) { s.label.contains("tbl-") && s.label.contains(".png") }) }
  let file_of = fn(label : String) {
    if label.contains("tbl-w.png") { "w" } else if label.contains("tbl-u.png") { "u" } else if label.contains("tbl-s.png") { "s" } else { "?" }
  }
  guard found().get(press) is Some(a) else { fail("no image: \{found().map(fn(s) { s.label })}") }
  let ids = found().map(fn(s) { s.id })
  let a_file = file_of(a.label)
  // (which of the showings of A's file the one pressed is, as they read)
  let a_nth = found().filter(fn(s) { file_of(s.label) == a_file }).search_by(fn(s) { s.id == a.id }).unwrap_or(0)
  t.tap(a.rect.0 + a.rect.2 / 2.0, a.rect.1 + a.rect.3 / 2.0)
  guard viewer.get() is Some(v) else { fail("A opened nothing") }
  let opened = v.file.path
  let a_thumb = v.thumb_id()
  if during == "opening" {
    t.run_for(@ui.move_most_ms / 2.0)
  } else {
    t.run_for(@ui.move_most_ms * 2.0)
    t.back()
    t.run_for(@ui.move_most_ms / 8.0)
  }
  let before = asked.copy()
  told.set(2)
  // (each frame at the moments said: the pictures of A's proportion drawn, A's thumbnail where the viewer flies, hidden
  // or not, a twelfth of the most a motion takes apart; the next of `more` told at every other one)
  let ratio = if a_file == "w" { 2.0 } else if a_file == "u" { 0.5 } else { 1.0 }
  let t0 = t.time()
  let frames = []
  for i in 1..=8 {
    let at = t0 + @ui.move_most_ms * i.to_double() / 12.0
    let k = (i - 1) / 2
    if k < more.length() && (i - 1) % 2 == 0 {
      told.set(3 + k)
    }
    t.frame_at(at)
    let pics = t.drawn_images().filter(fn(d) { d[8] > 0.5 && d[3] > 0.0 && (d[2] / d[3] - ratio).abs() < 0.05 && d[1] > 300.0 })
    let th = thumb_of(t.ctx(), a_thumb).map(fn(th) { rect((th.x, th.y, th.w, th.h)) })
    frames.push("\{i}: \{pics.map(fn(d) { rect((d[0], d[1], d[2], d[3])) })} into \{th} hidden \{pv_hidden.get() != ""}")
  }
  if during == "opening" {
    t.back()
    t.run_for(@ui.move_most_ms * 2.0)
  }
  let after = found()
  let a_now = after.filter(fn(s) { file_of(s.label) == a_file }).get(a_nth)
  let kept = after.map(fn(s) { "\{file_of(s.label)} \{if ids.contains(s.id) { "kept" } else { "made" }} \{rect((s.rect.0, s.rect.1, s.rect.2, s.rect.3))}" })
  let landed = match (a_now, thumb_of(t.ctx(), a_thumb)) {
    (Some(n), Some(th)) => "\{rect((th.x, th.y, th.w, th.h)) == rect((n.rect.0, n.rect.1, n.rect.2, n.rect.3))}, A drawn there \{drawn_at(t, (n.rect.0, n.rect.1, n.rect.2, n.rect.3))}"
    _ => "no A or no thumbnail"
  }
  let shut = "open \{viewer.get() is Some(_)}, hidden \{pv_hidden.get() != ""}"
  let again = match a_now {
    Some(n) => {
      t.tap(n.rect.0 + n.rect.2 / 2.0, n.rect.1 + n.rect.3 / 2.0)
      let p = viewer.get().map(fn(v) { v.file.path })
      t.run_for(@ui.move_most_ms * 2.0)
      t.back()
      t.run_for(@ui.move_most_ms * 2.0)
      p
    }
    None => None
  }
  let asked_again = ["w", "u", "s"].map(fn(x) {
    let n = "tbl-\{x}.png"
    "\{x} \{asked.get(n).unwrap_or(0) - before.get(n).unwrap_or(0)}"
  })
  @sf.markdown_read.val = None
  "\{shows.join(" ")} then \{then.join(" ")}\{more.map(fn(m) { " then " + m.join(" ") }).join("")}, \{during}: A \{a_file} opened \{opened}; after: \{kept}; flew back into A \{landed}; \{shut}; A pressed again opened \{again}; pictures asked again [\{asked_again.join(", ")}]; frames [\{frames.join("; ")}]"
}

///|
test "a table's cell of images, one pressed, its preview opening or shutting as another of the cell is put in, taken out, swapped or shown twice: the one pressed the same image, flown back into, the others as the cell is" {
  let seen = []
  for during in ["opening", "shutting"] {
    for c in [(["w", "u"], ["w", "s"]), (["w", "u"], ["w"]), (["w"], ["w", "u"]), (["w", "u"], ["u", "w"]), (["w", "u"], ["w", "u", "u"]), (["w", "u", "u"], ["w", "u"])] {
      seen.push(table_pair_kept(c.0, c.1, during))
    }
  }
  // (shutting: the table made again (S wider than U) with A shown twice, the second pressed; told back and forth while
  // it flies; A gone from the cell: no showing of it left, the picture fading out)
  seen.push(table_pair_kept(["w", "w", "u"], ["w", "w", "s"], "shutting", press=1))
  seen.push(table_pair_kept(["w", "u"], ["w", "s"], "shutting", more=[["w", "u"], ["w", "s"]]))
  seen.push(table_pair_kept(["w", "u"], ["u"], "shutting"))
  // (flown back into the one pressed where it is drawn then, wherever A is still shown)
  for i, one in seen {
    assert_true(i == seen.length() - 1 || one.contains("flew back into A true, A drawn there true"), msg=one)
  }
  inspect(
    seen.join("\n"),
    content=(
      #|w u then w s, opening: A w opened work/s-c1/tbl-w.png; after: [w made (16, 497, 160, 80), s made (182, 497, 160, 160)]; flew back into A true, A drawn there true; open false, hidden false; A pressed again opened Some(work/s-c1/tbl-w.png); pictures asked again [w 0, u 0, s 2]; frames [1: [(16, 444, 160, 80), (12, 354, 366, 183)] into None hidden true; 2: [(16, 469, 160, 80), (12, 354, 366, 183)] into None hidden false; 3: [(16, 484, 160, 80), (12, 354, 366, 183)] into None hidden false; 4: [(16, 491, 160, 80), (12, 354, 366, 183)] into None hidden false; 5: [(16, 495, 160, 80), (12, 354, 366, 183)] into None hidden false; 6: [(16, 497, 160, 80), (12, 354, 366, 183)] into None hidden false; 7: [(16, 497, 160, 80), (12, 354, 366, 183)] into None hidden false; 8: [(16, 497, 160, 80), (12, 354, 366, 183)] into None hidden false]
      #|w u then w, opening: A w opened work/s-c1/tbl-w.png; after: [w kept (16, 584, 160, 80)]; flew back into A true, A drawn there true; open false, hidden false; A pressed again opened Some(work/s-c1/tbl-w.png); pictures asked again [w 0, u 0, s 0]; frames [1: [(12, 354, 366, 183)] into Some((16, 468, 160, 80)) hidden true; 2: [(16, 522, 160, 80), (12, 354, 366, 183)] into Some((16, 522, 160, 80)) hidden false; 3: [(16, 555, 160, 80), (12, 354, 366, 183)] into Some((16, 555, 160, 80)) hidden false; 4: [(16, 572, 160, 80), (12, 354, 366, 183)] into Some((16, 572, 160, 80)) hidden false; 5: [(16, 579, 160, 80), (12, 354, 366, 183)] into Some((16, 579, 160, 80)) hidden false; 6: [(16, 583, 160, 80), (12, 354, 366, 183)] into Some((16, 583, 160, 80)) hidden false; 7: [(16, 584, 160, 80), (12, 354, 366, 183)] into Some((16, 584, 160, 80)) hidden false; 8: [(16, 584, 160, 80), (12, 354, 366, 183)] into Some((16, 584, 160, 80)) hidden false]
      #|w then w u, opening: A w opened work/s-c1/tbl-w.png; after: [w kept (16, 424, 160, 80), u made (182, 424, 128, 240)]; flew back into A true, A drawn there true; open false, hidden false; A pressed again opened Some(work/s-c1/tbl-w.png); pictures asked again [w 0, u 2, s 0]; frames [1: [(12, 354, 366, 183)] into Some((16, 540, 160, 80)) hidden true; 2: [(16, 486, 160, 80), (12, 354, 366, 183)] into Some((16, 486, 160, 80)) hidden false; 3: [(16, 454, 160, 80), (12, 354, 366, 183)] into Some((16, 454, 160, 80)) hidden false; 4: [(16, 437, 160, 80), (12, 354, 366, 183)] into Some((16, 437, 160, 80)) hidden false; 5: [(16, 429, 160, 80), (12, 354, 366, 183)] into Some((16, 429, 160, 80)) hidden false; 6: [(16, 426, 160, 80), (12, 354, 366, 183)] into Some((16, 426, 160, 80)) hidden false; 7: [(16, 424, 160, 80), (12, 354, 366, 183)] into Some((16, 424, 160, 80)) hidden false; 8: [(16, 424, 160, 80), (12, 354, 366, 183)] into Some((16, 424, 160, 80)) hidden false]
      #|w u then u w, opening: A w opened work/s-c1/tbl-w.png; after: [u kept (16, 424, 128, 240), w kept (150, 424, 160, 80)]; flew back into A true, A drawn there true; open false, hidden false; A pressed again opened Some(work/s-c1/tbl-w.png); pictures asked again [w 0, u 0, s 0]; frames [1: [(12, 354, 366, 183)] into Some((150, 424, 160, 80)) hidden true; 2: [(150, 424, 160, 80), (12, 354, 366, 183)] into Some((150, 424, 160, 80)) hidden false; 3: [(150, 424, 160, 80), (12, 354, 366, 183)] into Some((150, 424, 160, 80)) hidden false; 4: [(150, 424, 160, 80), (12, 354, 366, 183)] into Some((150, 424, 160, 80)) hidden false; 5: [(150, 424, 160, 80), (12, 354, 366, 183)] into Some((150, 424, 160, 80)) hidden false; 6: [(150, 424, 160, 80), (12, 354, 366, 183)] into Some((150, 424, 160, 80)) hidden false; 7: [(150, 424, 160, 80), (12, 354, 366, 183)] into Some((150, 424, 160, 80)) hidden false; 8: [(150, 424, 160, 80), (12, 354, 366, 183)] into Some((150, 424, 160, 80)) hidden false]
      #|w u then w u u, opening: A w opened work/s-c1/tbl-w.png; after: [w kept (16, 417, 160, 80), u kept (182, 417, 128, 240), u made (316, 417, 128, 240)]; flew back into A true, A drawn there true; open false, hidden false; A pressed again opened Some(work/s-c1/tbl-w.png); pictures asked again [w 0, u 0, s 0]; frames [1: [(12, 354, 366, 183)] into Some((16, 422, 160, 80)) hidden true; 2: [(16, 420, 160, 80), (12, 354, 366, 183)] into Some((16, 420, 160, 80)) hidden false; 3: [(16, 419, 160, 80), (12, 354, 366, 183)] into Some((16, 419, 160, 80)) hidden false; 4: [(16, 418, 160, 80), (12, 354, 366, 183)] into Some((16, 418, 160, 80)) hidden false; 5: [(16, 417, 160, 80), (12, 354, 366, 183)] into Some((16, 417, 160, 80)) hidden false; 6: [(16, 417, 160, 80), (12, 354, 366, 183)] into Some((16, 417, 160, 80)) hidden false; 7: [(16, 417, 160, 80), (12, 354, 366, 183)] into Some((16, 417, 160, 80)) hidden false; 8: [(16, 417, 160, 80), (12, 354, 366, 183)] into Some((16, 417, 160, 80)) hidden false]
      #|w u u then w u, opening: A w opened work/s-c1/tbl-w.png; after: [w kept (16, 424, 160, 80), u kept (182, 424, 128, 240)]; flew back into A true, A drawn there true; open false, hidden false; A pressed again opened Some(work/s-c1/tbl-w.png); pictures asked again [w 0, u 0, s 0]; frames [1: [(12, 354, 366, 183)] into Some((16, 419, 160, 80)) hidden true; 2: [(16, 422, 160, 80), (12, 354, 366, 183)] into Some((16, 422, 160, 80)) hidden false; 3: [(16, 423, 160, 80), (12, 354, 366, 183)] into Some((16, 423, 160, 80)) hidden false; 4: [(16, 424, 160, 80), (12, 354, 366, 183)] into Some((16, 424, 160, 80)) hidden false; 5: [(16, 424, 160, 80), (12, 354, 366, 183)] into Some((16, 424, 160, 80)) hidden false; 6: [(16, 424, 160, 80), (12, 354, 366, 183)] into Some((16, 424, 160, 80)) hidden false; 7: [(16, 424, 160, 80), (12, 354, 366, 183)] into Some((16, 424, 160, 80)) hidden false; 8: [(16, 424, 160, 80), (12, 354, 366, 183)] into Some((16, 424, 160, 80)) hidden false]
      #|w u then w s, shutting: A w opened work/s-c1/tbl-w.png; after: [w made (16, 497, 160, 80), s made (182, 497, 160, 160)]; flew back into A true, A drawn there true; open false, hidden false; A pressed again opened Some(work/s-c1/tbl-w.png); pictures asked again [w 0, u 0, s 2]; frames [1: [(15, 420, 216, 108)] into Some((16, 444, 160, 80)) hidden true; 2: [(16, 455, 185, 93)] into Some((16, 469, 160, 80)) hidden true; 3: [(16, 477, 170, 85)] into Some((16, 484, 160, 80)) hidden true; 4: [(16, 489, 164, 82)] into Some((16, 491, 160, 80)) hidden true; 5: [(16, 494, 161, 80)] into Some((16, 495, 160, 80)) hidden true; 6: [(16, 497, 160, 80)] into Some((16, 497, 160, 80)) hidden false; 7: [(16, 497, 160, 80)] into Some((16, 497, 160, 80)) hidden false; 8: [(16, 497, 160, 80)] into Some((16, 497, 160, 80)) hidden false]
      #|w u then w, shutting: A w opened work/s-c1/tbl-w.png; after: [w kept (16, 584, 160, 80)]; flew back into A true, A drawn there true; open false, hidden false; A pressed again opened Some(work/s-c1/tbl-w.png); pictures asked again [w 0, u 0, s 0]; frames [1: [(15, 437, 216, 108)] into Some((16, 468, 160, 80)) hidden true; 2: [(16, 501, 185, 93)] into Some((16, 522, 160, 80)) hidden true; 3: [(16, 545, 170, 85)] into Some((16, 555, 160, 80)) hidden true; 4: [(16, 568, 164, 82)] into Some((16, 572, 160, 80)) hidden true; 5: [(16, 578, 161, 80)] into Some((16, 579, 160, 80)) hidden true; 6: [(16, 583, 160, 80)] into Some((16, 583, 160, 80)) hidden false; 7: [(16, 584, 160, 80)] into Some((16, 584, 160, 80)) hidden false; 8: [(16, 584, 160, 80)] into Some((16, 584, 160, 80)) hidden false]
      #|w then w u, shutting: A w opened work/s-c1/tbl-w.png; after: [w kept (16, 424, 160, 80), u made (182, 424, 128, 240)]; flew back into A true, A drawn there true; open false, hidden false; A pressed again opened Some(work/s-c1/tbl-w.png); pictures asked again [w 0, u 2, s 0]; frames [1: [(15, 490, 216, 108)] into Some((16, 540, 160, 80)) hidden true; 2: [(16, 470, 185, 93)] into Some((16, 486, 160, 80)) hidden true; 3: [(16, 448, 170, 85)] into Some((16, 454, 160, 80)) hidden true; 4: [(16, 435, 164, 82)] into Some((16, 437, 160, 80)) hidden true; 5: [(16, 429, 161, 80)] into Some((16, 429, 160, 80)) hidden true; 6: [(16, 426, 160, 80)] into Some((16, 426, 160, 80)) hidden false; 7: [(16, 424, 160, 80)] into Some((16, 424, 160, 80)) hidden false; 8: [(16, 424, 160, 80)] into Some((16, 424, 160, 80)) hidden false]
      #|w u then u w, shutting: A w opened work/s-c1/tbl-w.png; after: [u kept (16, 424, 128, 240), w kept (150, 424, 160, 80)]; flew back into A true, A drawn there true; open false, hidden false; A pressed again opened Some(work/s-c1/tbl-w.png); pictures asked again [w 0, u 0, s 0]; frames [1: [(113, 405, 216, 108)] into Some((150, 424, 160, 80)) hidden true; 2: [(133, 416, 185, 93)] into Some((150, 424, 160, 80)) hidden true; 3: [(143, 421, 170, 85)] into Some((150, 424, 160, 80)) hidden true; 4: [(147, 423, 164, 82)] into Some((150, 424, 160, 80)) hidden true; 5: [(149, 424, 161, 80)] into Some((150, 424, 160, 80)) hidden true; 6: [(150, 424, 160, 80)] into Some((150, 424, 160, 80)) hidden false; 7: [(150, 424, 160, 80)] into Some((150, 424, 160, 80)) hidden false; 8: [(150, 424, 160, 80)] into Some((150, 424, 160, 80)) hidden false]
      #|w u then w u u, shutting: A w opened work/s-c1/tbl-w.png; after: [w kept (16, 417, 160, 80), u kept (182, 417, 128, 240), u made (316, 417, 128, 240)]; flew back into A true, A drawn there true; open false, hidden false; A pressed again opened Some(work/s-c1/tbl-w.png); pictures asked again [w 0, u 0, s 0]; frames [1: [(15, 404, 216, 108)] into Some((16, 422, 160, 80)) hidden true; 2: [(16, 412, 185, 93)] into Some((16, 420, 160, 80)) hidden true; 3: [(16, 415, 170, 85)] into Some((16, 419, 160, 80)) hidden true; 4: [(16, 417, 164, 82)] into Some((16, 418, 160, 80)) hidden true; 5: [(16, 417, 161, 80)] into Some((16, 417, 160, 80)) hidden true; 6: [(16, 417, 160, 80)] into Some((16, 417, 160, 80)) hidden false; 7: [(16, 417, 160, 80)] into Some((16, 417, 160, 80)) hidden false; 8: [(16, 417, 160, 80)] into Some((16, 417, 160, 80)) hidden false]
      #|w u u then w u, shutting: A w opened work/s-c1/tbl-w.png; after: [w kept (16, 424, 160, 80), u kept (182, 424, 128, 240)]; flew back into A true, A drawn there true; open false, hidden false; A pressed again opened Some(work/s-c1/tbl-w.png); pictures asked again [w 0, u 0, s 0]; frames [1: [(15, 401, 216, 108)] into Some((16, 419, 160, 80)) hidden true; 2: [(16, 413, 185, 93)] into Some((16, 422, 160, 80)) hidden true; 3: [(16, 419, 170, 85)] into Some((16, 423, 160, 80)) hidden true; 4: [(16, 422, 164, 82)] into Some((16, 424, 160, 80)) hidden true; 5: [(16, 424, 161, 80)] into Some((16, 424, 160, 80)) hidden true; 6: [(16, 424, 160, 80)] into Some((16, 424, 160, 80)) hidden false; 7: [(16, 424, 160, 80)] into Some((16, 424, 160, 80)) hidden false; 8: [(16, 424, 160, 80)] into Some((16, 424, 160, 80)) hidden false]
      #|w w u then w w s, shutting: A w opened work/s-c1/tbl-w.png; after: [w kept (16, 497, 160, 80), w kept (182, 497, 160, 80), s made (348, 497, 160, 160)]; flew back into A true, A drawn there true; open false, hidden false; A pressed again opened Some(work/s-c1/tbl-w.png); pictures asked again [w 0, u 0, s 2]; frames [1: [(16, 439, 160, 80), (136, 416, 216, 108)] into Some((182, 439, 160, 80)) hidden true; 2: [(16, 466, 160, 80), (161, 452, 185, 93)] into Some((182, 466, 160, 80)) hidden true; 3: [(16, 483, 160, 80), (173, 476, 170, 85)] into Some((182, 483, 160, 80)) hidden true; 4: [(16, 491, 160, 80), (179, 488, 164, 82)] into Some((182, 491, 160, 80)) hidden true; 5: [(16, 495, 160, 80), (181, 494, 161, 80)] into Some((182, 495, 160, 80)) hidden true; 6: [(16, 496, 160, 80), (182, 496, 160, 80)] into Some((182, 496, 160, 80)) hidden false; 7: [(16, 497, 160, 80), (182, 497, 160, 80)] into Some((182, 497, 160, 80)) hidden false; 8: [(16, 497, 160, 80), (182, 497, 160, 80)] into Some((182, 497, 160, 80)) hidden false]
      #|w u then w s then w u then w s, shutting: A w opened work/s-c1/tbl-w.png; after: [w made (16, 497, 160, 80), s made (182, 497, 160, 160)]; flew back into A true, A drawn there true; open false, hidden false; A pressed again opened Some(work/s-c1/tbl-w.png); pictures asked again [w 0, u 0, s 2]; frames [1: [(15, 405, 216, 108)] into Some((16, 424, 160, 80)) hidden true; 2: [(16, 416, 185, 93)] into Some((16, 424, 160, 80)) hidden true; 3: [(16, 440, 170, 85)] into Some((16, 444, 160, 80)) hidden true; 4: [(16, 467, 164, 82)] into Some((16, 469, 160, 80)) hidden true; 5: [(16, 483, 161, 80)] into Some((16, 484, 160, 80)) hidden true; 6: [(16, 491, 160, 80)] into Some((16, 491, 160, 80)) hidden false; 7: [(16, 495, 160, 80)] into Some((16, 495, 160, 80)) hidden false; 8: [(16, 497, 160, 80)] into Some((16, 497, 160, 80)) hidden false]
      #|w u then u, shutting: A w opened work/s-c1/tbl-w.png; after: [u kept (16, 424, 128, 240)]; flew back into A no A or no thumbnail; open false, hidden false; A pressed again opened None; pictures asked again [w 0, u 0, s 0]; frames [1: [(15, 405, 216, 108)] into None hidden true; 2: [(16, 416, 185, 93)] into None hidden true; 3: [(16, 421, 170, 85)] into None hidden true; 4: [(16, 423, 164, 82)] into None hidden true; 5: [(16, 424, 161, 80)] into None hidden true; 6: [] into None hidden false; 7: [] into None hidden false; 8: [] into None hidden false]
    ),
  )
}
