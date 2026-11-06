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
