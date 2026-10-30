// The rest of settings' pages (the Android app's settings module): what the automatic decisions' pages keep (their
// drafts: the pages are src/sfpages automatic_decisions.mbt's, one each in every frame), this device's bottom bars
// (BarSettings.kt), what this device keeps (KeptFiles.kt), the changelog (Changelog.kt), the prices the usage is
// counted at (Usage.kt UsagePricesScreen); and, used from the chats' pages, how an agent runs (History.kt
// RunSettingsScreen, run_page) and the machine's own sessions to go on with (NewChat.kt MachineSessions).

// ---------------------------------------------------------------------------
// 自动决策

///|
/// The drafts of the stations' rules open on the page (`decisionForm`), by station.
let decision_forms : Map[String, String] = Map([])

///|
/// The drafts of the stations' archive policies open (`policyForm`), by station.
pub let policy_forms : Map[String, String] = Map([])

///|
/// The drafts a decisions' page opened, dropped as it is left.
fn decisions_left(core : Core, route : Route) -> Unit {
  match route {
    AutoCompletion => {
      for station, form in decision_forms {
        act(core, tr("web-pages.automaticDecisions.configAction"), "automaticDecisions.form.drop", obj([("station", str(station)), ("form", str(form)), ("input", obj([]))]))
      }
      decision_forms.clear()
    }
    AutoPolicy(station) =>
      match policy_forms.get(station) {
        Some(form) => {
          policy_forms.remove(station)
          act(core, tr("web-pages.archivePolicy.closeAction"), "automaticDecisions.policy.drop", obj([("station", str(station)), ("form", str(form)), ("input", obj([]))]))
        }
        None => ()
      }
    _ => ()
  }
}

// ---------------------------------------------------------------------------
// 下方栏

///|
/// How many places a bar holds (BAR_SIZE).
pub let bar_size : Int = 4

///|
/// Every place, in the picker's order (Places.kt PLACES).
// kept across runs: a table of constants, never written
pub let all_places : Array[String] = ["chats", "decisions", "files", "stations", "profiles", "connects", "usage", "archive"]

///|
/// What settings' row says of the bars (barsValue): how many, or the one bar's places.
pub fn bars_value(core : Core) -> String {
  let (sets, _) = (core.bars)()
  if sets.length() > 1 {
    fill("android-misc.bar.count", [("n", sets.length().to_string())])
  } else {
    join(sets[0].map(fn(p) { tr("android-misc.bar.place." + p) }), tr("android-misc.bar.sep"))
  }
}

///|
/// The bars kept whole (BarSettings.kt save): an empty one dropped, the one in view still the same bar after it.
pub fn save_bars(core : Core, sets : Array[Array[String]], current : Int) -> Unit {
  let mut cur = current
  let kept : Array[Array[String]] = []
  for i, s in sets {
    if s.length() == 0 {
      if i < current {
        cur -= 1
      }
    } else {
      kept.push(s)
    }
  }
  if kept.length() > 0 {
    (core.set_bars)(kept, if cur < 0 { 0 } else if cur >= kept.length() { kept.length() - 1 } else { cur })
  }
}

///|
/// A bar just made on 下方栏's page (sfpages bars.mbt), empty until a place is added (the core keeps no empty bar): let
/// go of as the page is left.
pub let bar_adding : @signals.Signal[Bool] = @signals.signal(false, same=fn(a, b) { a == b })

///|
/// How far a place held on 下方栏's page is moved along its bar (BarCard's `dx`: the finger's way past the slop), by
/// its bar and its name, while a finger has it.
pub let bar_moves : Map[String, Double] = {}

// ---------------------------------------------------------------------------
// 存储空间 (what this device keeps)

///|
/// What the core keeps of each chat (its messages, the files opened in it) and of the drives' files, and the files of
/// no chat known (`cache.usage`), read as the page opens and again after a deletion.
priv struct Kept {
  chats : @signals.Signal[Array[Json]?]
  /// the bytes of the drives' files kept (drive.read's `keep`)
  drive : @signals.Signal[Double]
  /// the files of no chat known (`loose`)
  loose : @signals.Signal[Array[Json]]
  asked : @signals.Signal[Int]
  read : @signals.Signal[Int]
}

///|
let kept : Kept = { chats: @signals.signal(None), drive: @signals.signal(0.0, same=fn(a, b) { a == b }), loose: @signals.signal([]), asked: @signals.signal(0, same=fn(a, b) { a == b }), read: @signals.signal(-1, same=fn(a, b) { a == b })}

///|
/// The chats' kept data asked of the core again.
fn kept_read(c : @ui.Ctx, core : Core) -> Unit {
  if kept.read.get() == kept.asked.get() {
    return
  }
  kept.read.set(kept.asked.get())
  // (asked once the frame's builds are over: the build that first comes to it alone)
  c.tell("cache.usage", fn() {
    (core.call)("cache.usage", obj([]), fn(r) {
      kept.chats.set(Some(
        match r {
          Ok(v) => items(Some(v), "chats")
          Err(_) => []
        },
      ))
      kept.drive.set(match r {
        Ok(v) => number(Some(v), "drive")
        Err(_) => 0.0
      })
      kept.loose.set(match r {
        Ok(v) => items(Some(v), "loose")
        Err(_) => []
      })
    })
  })
}

///|
/// What 本机缓存's row in the settings' list says: all its page counts (kept_total), once the core has said it (""
/// until then).
pub fn kept_said(c : @ui.Ctx, core : Core) -> String {
  kept_read(c, core)
  match kept.chats.get() {
    Some(chats) => size_words(kept_total(chats))
    None => ""
  }
}

///|
/// All that is kept: the chats' (their messages and files), the files of no chat known and the drives' files.
fn kept_total(chats : Array[Json]) -> Double {
  chats.fold(init=kept.drive.get() + files_bytes(kept.loose.get()), fn(s, x) { s + chat_bytes(x) })
}

///|
/// The bytes kept of `files` (a chat's, or those of no chat).
fn files_bytes(files : Array[Json]) -> Double {
  files.fold(init=0.0, fn(s, f) { s + number(Some(f), "bytes") })
}

///|
/// What is kept of a chat: its messages and the files opened in it.
fn chat_bytes(x : Json) -> Double {
  number(Some(x), "bytes") + files_bytes(items(Some(x), "files"))
}

///|
/// A size in bytes in words (fileSize).
fn size_words(n : Double) -> String {
  let one = fn(x : Double) { ((x * 10.0).round() / 10.0).to_string() }
  if n < 1024.0 {
    n.to_int().to_string() + " B"
  } else if n < 1024.0 * 1024.0 {
    one(n / 1024.0) + " KB"
  } else if n < 1024.0 * 1024.0 * 1024.0 {
    one(n / 1024.0 / 1024.0) + " MB"
  } else {
    one(n / 1024.0 / 1024.0 / 1024.0) + " GB"
  }
}

///|
/// How long ago `at` was, in the app's words (KeptFiles.kt since): just now, minutes, hours, days.
fn since_words(now : Double, at : Double) -> String {
  let minutes = ((now - at) / 60000.0).floor().to_int()
  if minutes < 1 {
    tr("android-settings.files.justNow")
  } else if minutes < 60 {
    fill("android-settings.files.minutes", [("n", minutes.to_string())])
  } else if minutes < 24 * 60 {
    fill("android-settings.files.hours", [("n", (minutes / 60).to_string())])
  } else {
    fill("android-settings.files.days", [("n", (minutes / (24 * 60)).to_string())])
  }
}

///|
/// A row of a size (SizeRow): what, a line under it, its size; tapped when `key` is given; `piece`: a piece of its card
/// (list_row).
fn size_row(
  c : @ui.Ctx,
  key : String,
  title : String,
  sub : String,
  size : Double,
  more? : Bool = false,
  piece? : (Bool, Bool),
) -> Bool {
  let t = @sf.theme()
  list_row(c, key~, piece?, fn() {
    // its size and chevron by its title, what it holds under them as wide as the row
    row_lines(c, title, sub, end=fn() {
      c.text(size_words(size), size=t.t.meta, color=t.p.muted, wrap=false) |> ignore
      if more {
        chevron(c)
      }
    })
  })
}

///|
/// What this device keeps while it is read (the library's Waiting, in its bones): made-up rows of sizes on their card,
/// as size_row draws them (`chats`: what all is made of, then the chats under their heading; else a chat's messages,
/// then its files).
fn kept_sample(c : @ui.Ctx, chats : Bool) -> Unit {
  list_card(c, fn() {
    for n in if chats { [6, 8, 5] } else { [4] } {
      size_row(c, "", @sf.sample_words(n), if chats { "" } else { @sf.sample_words(14) }, 1.0) |> ignore
    }
  })
  section_header(c, @sf.sample_words(4), start=S6)
  let rows = [(8, 16), (6, 12), (10, 18), (7, 14)]
  for i, n in rows {
    size_row(c, "", @sf.sample_words(n.0), @sf.sample_words(n.1), 1.0, more=chats, piece=(i == 0, i == rows.length() - 1))
    |> ignore
  }
}

///|
/// What this device keeps: all of it first, as one figure over a bar of what it is made of (the chats' messages, the
/// files opened in them, the drives' files, the files of no chat known), each part a row under it, those that can be
/// gone into or let go so; then the chats, the one keeping most first, the first few until all are asked for; then
/// whether opened files go on coming, and everything let go at once. (The Android app also lists its web pages' cache,
/// update packages, temporary files and the core's own data: this app keeps none of those apart.)
fn kept_page(c : @ui.Ctx, core : Core) -> Unit {
  let t = @sf.theme()
  kept_read(c, core)
  let blocks : Array[() -> Unit] = [
    fn() { top_back(c, core, tr("android-settings.title")) },
    fn() { large_title(c, tr("android-settings.files.title")) },
    fn() { page_note(c, tr("android-settings.files.note")) },
  ]
  match kept.chats.get() {
    None => blocks.push(fn() { waiting_rows(c, fn() { kept_sample(c, true) }) })
    Some(chats) => {
      let loose = kept.loose.get()
      let total = kept_total(chats)
      blocks.push(fn() { kept_parts(c, core, chats, loose, total) })
      if chats.length() > 0 {
        blocks.push(fn() { section_header(c, tr("android-settings.files.byChat"), start=S6) })
        // a block each, one card's pieces: of many chats only the rows in view are laid out (one block of them all was
        // built whole each frame, every row's words with it)
        let more = chats.length() > kept_first
        let all = kept_all.get()
        let shown = if more && !all { kept_first } else { chats.length() }
        for i in 0..<shown {
          let x = chats[i]
          blocks.push(fn() { kept_chat_row(c, core, x, (i == 0, i == shown - 1 && !more)) })
        }
        if more {
          blocks.push(fn() {
            let words = if all {
              tr("web-main.fold")
            } else {
              fill("web-main.usage.showAll", [("n", chats.length().to_string())])
            }
            if list_row(c, key="kept-chats-all", piece=(false, true), fn() { row_title(c, words, color=t.p.muted) }) {
              kept_all.set(!all)
            }
          })
        }
      }
      fill_blocks(c, core, blocks)
      if total > 0.0 {
        blocks.push(fn() {
          list_card(c, fn() {
            if list_row(c, key="kept-all", fn() { row_title(c, tr("android-settings.files.clearAll"), color=t.p.red) }) {
              confirm(
                tr("android-settings.files.clearAll.title"),
                fill("android-settings.files.clearAll.text", [("size", size_words(total))]),
                tr("android-settings.files.clear.action"),
                danger=true,
                fn() {
                  for x in chats {
                    (core.call)("cache.clear", obj([("station", str(text(Some(x), "station"))), ("thread", Json::number(number(Some(x), "thread")))]), fn(_) {
                      kept.asked.set(kept.asked.get() + 1)
                    })
                  }
                  kept_files_clear(core, loose)
                  if kept.drive.get() > 0.0 {
                    (core.call)("drive.kept.clear", obj([]), fn(_) { kept.asked.set(kept.asked.get() + 1)})
                  }
                },
              )
            }
          })
        })
      }
    }
  }
  blocks.push(fn() { gap(c, 30.0) })
  scroll_page(c, "kept", blocks)
}

///|
/// The chats shown until all are asked for (as 用量's lists show theirs).
let kept_first : Int = 8

///|
/// Whether all the chats are shown on 本机缓存, not only the first kept_first.
let kept_all : @signals.Signal[Bool] = @signals.signal(false, same=fn(a, b) { a == b })

///|
/// All that is kept, large, over a bar of what it is made of, each part a row with its colour's dot: the chats'
/// messages, the files opened in them, the drives' files (let go when asked), the files of no chat known (gone into);
/// those with nothing in them left out.
fn kept_parts(c : @ui.Ctx, core : Core, chats : Array[Json], loose : Array[Json], total : Double) -> Unit {
  let messages = chats.fold(init=0.0, fn(s, x) { s + number(Some(x), "bytes") })
  let opened = chats.fold(init=0.0, fn(s, x) { s + files_bytes(items(Some(x), "files")) })
  let drive = kept.drive.get()
  let parts = [
    ("messages", tr("android-settings.files.messages"), messages),
    ("opened", tr("android-settings.files.chatFiles"), opened),
    ("drive", tr("android-settings.files.drive"), drive),
    ("loose", tr("android-settings.files.looseShort"), files_bytes(loose)),
  ].filter(fn(p) { p.2 > 0.0 })
  list_card(c, fn() {
    // (as a row of the card: the bar as far in as the rows' words, high enough over the row's foot to keep out of
    // its corners)
    list_row(c, fn() {
      c.box(style=kept_whole, fn() {
        c.text(size_words(total), style=kept_figure) |> ignore
        if total > 0.0 {
          c.box(style=kept_bar, fn() {
            for i, p in parts {
              let (_, _, size) = p
              let share = @cmp.maximum(kept_bar_least, size / total)
              c.box(style=kept_bar_part.then(@ui.style(w=Grow(share), bg=Data(@sf.usage_series(i)))), fn() {  }) |> ignore
            }
          })
          |> ignore
        }
      })
      |> ignore
    })
    |> ignore
    // the parts two by two under it, each its dot, its name over its size (as wide as half the card: what is in
    // them a word or two)
    for k in 0..<((parts.length() + 1) / 2) {
      c.box(style=kept_parts_line, fn() {
        for i in (k * 2)..<(k * 2 + 2) {
          if i >= parts.length() {
            c.box(style=kept_part_room, fn() {  }) |> ignore
            continue
          }
          let (what, name, size) = parts[i]
          let id = match what {
            "drive" => c.id("kept-drive")
            "loose" => c.id("kept-loose")
            _ => 0
          }
          // (as high as a press's room at least, the native input's)
          c.box(style=(if id != 0 { kept_part_lit } else { kept_part_room }).then(@sf.row_least_h()), id~, fn() {
            c.box(style=kept_part_head, fn() {
              c.box(style=kept_dot.then(@ui.style(bg=Data(@sf.usage_series(i)))), fn() {  }) |> ignore
              c.text(name, style=kept_part_name) |> ignore
            })
            |> ignore
            c.box(style=kept_part_size_room, fn() { c.text(size_words(size), style=kept_part_size) |> ignore }) |> ignore
            if id != 0 {
              @motion.ripple(c, id, @sf.row_corner)
            }
          })
          |> ignore
          if id != 0 && hit(c, id) {
            if what == "drive" {
              confirm(tr("android-settings.files.drive"), tr("android-settings.files.drive.text"), tr("android-settings.files.clear.action"), danger=true, fn() {
                (core.call)("drive.kept.clear", obj([]), fn(_) { kept.asked.set(kept.asked.get() + 1)})
              })
            } else {
              (core.push)(KeptChat("", -1))
            }
          }
        }
      })
      |> ignore
    }
  })
}

///|
/// A chat on 本机缓存: what it is called, what it keeps; gone into.
fn kept_chat_row(c : @ui.Ctx, core : Core, x : Json, piece : (Bool, Bool)) -> Unit {
  let xv = Some(x)
  let title = match text(xv, "title") {
    "" => fill("android-settings.files.untitled", [("n", count(xv, "thread").to_string())])
    s => s
  }
  let files = items(xv, "files")
  let size = chat_bytes(x)
  // (its messages alone: the size at its end says it)
  let sub = if files.length() == 0 {
    ""
  } else {
    fill("android-settings.files.chat.both", [
      ("size", size_words(number(xv, "bytes"))),
      ("n", files.length().to_string()),
      ("files", size_words(files_bytes(files))),
    ])
  }
  let key = "kept/" + text(xv, "station") + "/" + count(xv, "thread").to_string()
  if list_row(c, key~, piece~, fn() {
      row_lines(c, title, sub, end=fn() {
        c.text(size_words(size), style=fill_size_words) |> ignore
        chevron(c)
      })
    }) {
    (core.push)(KeptChat(text(xv, "station"), count(xv, "thread")))
  }
}

///|
/// The figure and the bar under it, 12 apart; 8 under the bar, out of its row's corners.
// kept across runs: a value (no field of it changes)
let kept_whole : @ui.Style = @ui.css("w=Full gap=S3 pb=S2")

///|
/// The least share of the bar a part has, seen however little it keeps.
let kept_bar_least : Double = 0.01

///|
/// All that is kept, as 用量's totals are said (the heading's size, 600).
// kept across runs: a value (no field of it changes)
let kept_figure : @ui.TextStyle = @ui.text_style(size=Heading, weight=Semibold, color=Fg, wrap=false, w=Full)

///|
/// What all that is kept is made of: its parts side by side, 1 apart, as wide as what each keeps.
// kept across runs: a value (no field of it changes)
let kept_bar : @ui.Style = @ui.css("row w=Full h=S2 gap=SPx radius=Full bg=TintStrong clip")

///|
// kept across runs: a value (no field of it changes)
let kept_bar_part : @ui.Style = @ui.css("h=Full")

///|
/// Two parts side by side.
// kept across runs: a value (no field of it changes)
let kept_parts_line : @ui.Style = @ui.css("row w=Full")

///|
/// A part: its name's line over its size, as far in as a row's words.
// kept across runs: a value (no field of it changes)
let kept_part_room : @ui.Style = @ui.css("gap=SPx radius=Inner").then(@ui.style(w=@sf.grow, p=@sf.list_words_room))

///|
/// One that is tapped: lit under the hand.
// kept across runs: a value (no field of it changes)
let kept_part_lit : @ui.Style = kept_part_room.then(@ui.css("hovered{bg=Hover}"))

///|
/// Its dot and its name, 8 apart.
// kept across runs: a value (no field of it changes)
let kept_part_head : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let kept_part_name : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false, w=Full)

///|
/// Its size under its name, as far in as the name (past its dot's 8 and the 8 after it).
// kept across runs: a value (no field of it changes)
let kept_part_size_room : @ui.Style = @ui.css("w=Full pl=S4")

///|
// kept across runs: a value (no field of it changes)
let kept_part_size : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Medium, color=Fg, wrap=false, w=Full)

///|
/// A part's dot, its colour in the bar (用量's people's).
// kept across runs: a value (no field of it changes)
let kept_dot : @ui.Style = @ui.css("w=S2 h=S2 radius=Full")

///|
/// A row's words beside what is at its end (a switch, a ✕), as wide as it leaves them.
// kept across runs: a value (no field of it changes)
let fill_words : @ui.Style = @ui.style(w=@sf.grow)

///|
/// The size chosen at its row's end, as a size row's.
// kept across runs: a value (no field of it changes)
let fill_size_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
/// The sizes a file opened and let go may be brought whole up to (prefs `fillMax`: 0 any), the core's own first.
// kept across runs: a table, never written
let fill_sizes : Array[Double] = [1024.0 * 1024.0 * 1024.0, 100.0 * 1024.0 * 1024.0, 500.0 * 1024.0 * 1024.0, 0.0]

///|
/// 后台下载 (client/core-ts fill.ts): whether what was opened and let go goes on coming after everything else (prefs
/// `fillOff`), up to how big (`fillMax`, picked from fill_sizes), and what is coming so now (the `downloads` topic's
/// `keeping`), each with how it stands, all of them stopped at once; into `blocks`.
fn fill_blocks(c : @ui.Ctx, core : Core, blocks : Array[() -> Unit]) -> Unit {
  let t = @sf.theme()
  let prefs = (core.topic)("prefs", Map::new()).value
  let on = !flag(prefs, "fillOff")
  let most = match field(prefs, "fillMax") {
    Some(Number(n, ..)) => n
    _ => fill_sizes[0]
  }
  let size_said = fn(n : Double) { if n == 0.0 { tr("android-settings.files.fill.any") } else { size_words(n) } }
  let set = fn(name : String, value : Json) { (core.call)("prefs.set", obj([(name, value)]), fn(_) {  }) }
  blocks.push(fn() { section_header(c, tr("android-settings.files.fill.title"), start=S6) })
  blocks.push(fn() {
    list_card(c, fn() {
      // (the switch in the row's middle, off its corners, as settings' switches are)
      if list_row(c, key="kept-fill", fn() {
          c.box(style=fill_words, fn() { row_lines(c, tr("android-settings.files.fill.on"), tr("android-settings.files.fill.on.sub"), wrap_sub=true) })
          |> ignore
          switch(c, "kept-fill-switch", on)
        }) {
        set("fillOff", if on { Json::boolean(true) } else { Json::null() })
      }
      if on {
        let id = c.id("kept-fill-max")
        if list_row(c, key="kept-fill-max", fn() {
            row_lines(c, tr("android-settings.files.fill.max"), tr("android-settings.files.fill.max.sub"), end=fn() {
              c.text(size_said(most), style=fill_size_words) |> ignore
              chevron(c)
            })
          }) {
          let choices = fill_sizes.map(fn(n) { @sf.choice(n.to_string(), size_said(n)) })
          @sf.pick(
            tr("android-settings.files.fill.max"),
            choices,
            most.to_string(),
            fn(k) {
              let n = fill_sizes.search_by(fn(x) { x.to_string() == k }).map(fn(i) { fill_sizes[i] }).unwrap_or(fill_sizes[0])
              set("fillMax", if n == fill_sizes[0] { Json::null() } else { Json::number(n) })
            },
            from=Of(id),
          )
        }
      }
    })
  })
  let keeping = items((core.topic)("downloads", Map::new()).value, "keeping")
  if !on || keeping.length() == 0 {
    return
  }
  let total = keeping.fold(init=0.0, fn(n, k) { n + number(Some(k), "size") })
  blocks.push(fn() {
    section_header(c, tr("android-settings.files.fill.going"), trailing=fill("android-settings.files.total", [("size", size_words(total))]), start=S6)
  })
  for i, k in keeping {
    blocks.push(fn() {
      let kv = Some(k)
      // (each stopped where it shows: the transfers' list, its message's card; all of them here at once)
      list_row(c, key="", piece=(i == 0, false), fn() { row_lines(c, text(kv, "title"), text(kv, "statusText")) })
      |> ignore
    })
  }
  blocks.push(fn() {
    if list_row(c, key="kept-fill-stop-all", piece=(false, true), fn() {
        row_title(c, tr("android-settings.files.fill.stopAll"), color=t.p.red)
      }) {
      (core.call)("fill.stopAll", obj([]), fn(_) {  })
    }
  })
}

///|
/// Files kept let go, each (`cache.file.clear`), of no chat known: by the station each says.
fn kept_files_clear(core : Core, files : Array[Json]) -> Unit {
  for f in files {
    kept_file_clear(core, text(Some(f), "station"), f)
  }
}

///|
/// A file kept of a chat on `station` let go (`cache.file.clear`): read again from its station when opened.
fn kept_file_clear(core : Core, station : String, f : Json) -> Unit {
  let fv = Some(f)
  (core.call)("cache.file.clear", obj([("station", str(station)), ("key", str(text(fv, "key"))), ("name", str(text(fv, "name")))]), fn(_) {
    kept.asked.set(kept.asked.get() + 1)
  })
}

///|
/// A file kept (KeptChatScreen's row): its name, how much and when it was last opened (未下载完成 when only a part of
/// it came), deleted by its bin (a 36 circle, its 18 icon muted); a piece of its card (list_row).
fn kept_file_row(c : @ui.Ctx, core : Core, station : String, f : Json, piece : (Bool, Bool)) -> Unit {
  let t = @sf.theme()
  let fv = Some(f)
  let name = text(fv, "name")
  let bytes = number(fv, "bytes")
  let sub = if bytes < number(fv, "size") {
    fill("android-settings.files.partial", [("size", size_words(bytes))])
  } else {
    fill("android-settings.files.meta", [("size", size_words(bytes)), ("opened", since_words((core.now)(), number(fv, "opened")))])
  }
  list_row(c, key="", piece~, fn() {
    // its bin by its name, how much and when under them as wide as the row
    row_lines(c, name, sub, end=fn() {
      let id = c.id("kept-file/" + station + "/" + text(fv, "key") + "/" + name)
      let b = c.box(style=kept_bin, id~, fn() {
        @sf.icon(c, "trash", size=18.0, color=t.p.muted) |> ignore
        // clip(CircleShape).clickable
        @motion.ripple(c, id, 18.0)
      })
      c.semantics(b, Button, id~, label=tr("android-settings.files.clear.action") + "「" + name + "」")
      if hit(c, id) {
        kept_file_clear(core, station, f)
      }
    })
  })
  |> ignore
}

///|
/// A kept file's bin (KeptFiles.kt: 36 across, its icon in its middle, its ripple a circle): no ground or corner of its
/// own, pressed or not, so none stands round in its card's corner where no circle is concentric with it.
// kept across runs: a value (no field of it changes)
let kept_bin : @ui.Style = @ui.css("w=S9 h=S9 align=ACenter justify=JCenter")

///|
/// A chat's (KeptChatScreen): what is kept of its messages, deleted when asked (`cache.clear`: read again from its
/// station when it is opened), and the files opened in it, each to delete; or all of it. Station "": the files of no
/// chat known.
fn kept_chat_page(c : @ui.Ctx, core : Core, station : String, thread : Int) -> Unit {
  let t = @sf.theme()
  kept_read(c, core)
  let loose = station == ""
  let chat = match kept.chats.get() {
    Some(a) if !loose => a.iter().find_first(fn(x) { text(Some(x), "station") == station && count(Some(x), "thread") == thread })
    _ => None
  }
  let files = if loose { kept.loose.get() } else { items(chat, "files") }
  let blocks : Array[() -> Unit] = [
    fn() { top_back(c, core, tr("android-settings.files.title")) },
    fn() { large_title(c, if loose { tr("android-settings.files.loose") } else { text(chat, "title") }) },
  ]
  let clear = fn() {
    match chat {
      Some(_) =>
        (core.call)("cache.clear", obj([("station", str(station)), ("thread", Json::number(thread.to_double()))]), fn(_) {
          kept.asked.set(kept.asked.get() + 1)
        })
      None => kept_files_clear(core, files)
    }
  }
  if kept.chats.get() is None {
    blocks.push(fn() { waiting_rows(c, fn() { kept_sample(c, false) }) })
  } else {
    let messages = number(chat, "bytes")
    if chat is Some(_) {
      blocks.push(fn() {
        list_card(c, fn() {
          if size_row(c, if messages > 0.0 { "kept-messages" } else { "" }, tr("android-settings.files.messages"), tr("android-settings.files.messages.text"), messages) {
            confirm(tr("android-settings.files.messages"), tr("android-settings.files.messages.clear"), tr("android-settings.files.clear.action"), danger=true, fn() {
              (core.call)("cache.clear", obj([("station", str(station)), ("thread", Json::number(thread.to_double()))]), fn(_) {
                kept.asked.set(kept.asked.get() + 1)
              })
            })
          }
        })
      })
    }
    if files.length() > 0 {
      blocks.push(fn() {
        section_header(
          c,
          tr("android-settings.files.files"),
          trailing=fill("android-settings.files.filesTotal", [("n", files.length().to_string()), ("size", size_words(files_bytes(files)))]),
          start=S6,
        )
      })
      // a block each, one card's pieces (as the chats' on 本机缓存): of many only those in view laid out
      let n = files.length()
      for i, f in files {
        blocks.push(fn() { kept_file_row(c, core, if loose { text(Some(f), "station") } else { station }, f, (i == 0, i == n - 1)) })
      }
    }
    let all = messages + files_bytes(files)
    if all > 0.0 {
      blocks.push(fn() {
        list_card(c, fn() {
          if list_row(c, key="kept-chat-all", fn() { row_title(c, tr("android-settings.files.clearChat"), color=t.p.red) }) {
            confirm(
              tr("android-settings.files.clearChat"),
              fill("android-settings.files.clearChat.text", [("size", size_words(all))]),
              tr("android-settings.files.clear.action"),
              danger=true,
              clear,
            )
          }
        })
      })
    }
  }
  blocks.push(fn() { gap(c, 30.0) })
  scroll_page(c, "kept/" + station + "/" + thread.to_string(), blocks)
}

///|
/// A station's rule's draft (`decisionForm`), opened once (by the frame's builds' end) and kept by station (src/sfpages
/// automatic_decisions.mbt).
pub fn decision_form(c : @ui.Ctx, core : Core, station : String) -> String {
  match decision_forms.get(station) {
    Some(f) => f
    None => {
      profile_forms.val += 1
      let f = "mbui-decision-" + profile_forms.val.to_string()
      decision_forms[station] = f
      // (opened once the frame's builds are over: the build that first comes to it alone)
      c.tell("decision-open/" + f, fn() {
        act(core, tr("web-pages.automaticDecisions.configAction"), "automaticDecisions.form.open", obj([("station", str(station)), ("form", str(f)), ("input", obj([]))]))
      })
      f
    }
  }
}
