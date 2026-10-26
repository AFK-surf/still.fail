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
pub let bar_adding : Ref[Bool] = Ref(false)

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
  mut chats : Array[Json]?
  /// the bytes of the drives' files kept (drive.read's `keep`)
  mut drive : Double
  /// the files of no chat known (`loose`)
  mut loose : Array[Json]
  mut asked : Int
  mut read : Int
}

///|
let kept : Kept = { chats: None, drive: 0.0, loose: [], asked: 0, read: -1 }

///|
/// The chats' kept data asked of the core again.
fn kept_read(c : @ui.Ctx, core : Core) -> Unit {
  if kept.read == kept.asked {
    return
  }
  kept.read = kept.asked
  // (asked once the frame's builds are over: the build that first comes to it alone)
  c.tell("cache.usage", fn() {
    (core.call)("cache.usage", obj([]), fn(r) {
      kept.chats = Some(
        match r {
          Ok(v) => items(Some(v), "chats")
          Err(_) => []
        },
      )
      kept.drive = match r {
        Ok(v) => number(Some(v), "drive")
        Err(_) => 0.0
      }
      kept.loose = match r {
        Ok(v) => items(Some(v), "loose")
        Err(_) => []
      }
    })
  })
}

///|
/// What 本机缓存's row in the settings' list says (SettingsHome.kt: KeptFiles.read's total): the chats' kept data in
/// all, once the core has said it ("" until then).
pub fn kept_said(c : @ui.Ctx, core : Core) -> String {
  kept_read(c, core)
  match kept.chats {
    Some(chats) => size_words(chats.fold(init=0.0, fn(s, x) { s + number(Some(x), "bytes") }))
    None => ""
  }
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
/// What this device keeps (KeptFilesScreen): by chat, what the core keeps of each (its messages, its transcripts, the
/// files opened in it), each to look into; then what is of no chat: files of no chat known, the drives' files opened
/// (`drive.kept.clear`); or everything. (The Android app also lists its web pages' cache, update packages, temporary
/// files and the core's own data: this app keeps none of those apart.)
pub fn kept_blocks(c : @ui.Ctx, core : Core) -> Array[() -> Unit] {
  let t = @sf.theme()
  kept_read(c, core)
  let blocks : Array[() -> Unit] = [fn() { page_note(c, tr("android-settings.files.note")) }]
  match kept.chats {
    None => blocks.push(fn() { waiting_rows(c) })
    Some(chats) => {
      let loose = kept.loose
      let total = chats.fold(init=kept.drive + files_bytes(loose), fn(s, x) { s + chat_bytes(x) })
      blocks.push(fn() {
        section_header(c, tr("android-settings.files.byChat"), trailing=fill("android-settings.files.total", [("size", size_words(total))]), start=S6)
      })
      if chats.length() == 0 {
        blocks.push(fn() { page_note(c, tr("android-settings.files.none")) })
      } else {
        // a block each, one card's pieces: of many chats only the rows in view are laid out (one block of them all was
        // built whole each frame, every row's words with it)
        let n = chats.length()
        for i, x in chats {
          blocks.push(fn() {
            let xv = Some(x)
            let title = match text(xv, "title") {
              "" => fill("android-settings.files.untitled", [("n", count(xv, "thread").to_string())])
              s => s
            }
            let files = items(xv, "files")
            let messages = size_words(number(xv, "bytes"))
            let sub = if files.length() == 0 {
              fill("android-settings.files.chat.messages", [("size", messages)])
            } else {
              fill("android-settings.files.chat.both", [
                ("size", messages),
                ("n", files.length().to_string()),
                ("files", size_words(files_bytes(files))),
              ])
            }
            if size_row(
                c,
                "kept/" + text(xv, "station") + "/" + count(xv, "thread").to_string(),
                title,
                sub,
                chat_bytes(x),
                more=true,
                piece=(i == 0, i == n - 1),
              ) {
              (core.push)(KeptChat(text(xv, "station"), count(xv, "thread")))
            }
          })
        }
      }
      // what is of no chat (KeptFiles.kt 其他): files of no chat known, the drives' files opened (文件浏览), each to
      // delete when there are some
      blocks.push(fn() { section_header(c, tr("android-settings.files.other"), start=S6) })
      blocks.push(fn() {
        list_card(c, fn() {
          if loose.length() > 0 &&
            size_row(
              c,
              "kept-loose",
              tr("android-settings.files.loose"),
              fill("android-settings.files.count", [("n", loose.length().to_string())]),
              files_bytes(loose),
              more=true,
            ) {
            (core.push)(KeptChat("", -1))
          }
          let drive = kept.drive
          if size_row(c, if drive > 0.0 { "kept-drive" } else { "" }, tr("android-settings.files.drive"), tr("android-settings.files.drive.sub"), drive) {
            confirm(tr("android-settings.files.drive"), tr("android-settings.files.drive.text"), tr("android-settings.files.clear.action"), danger=true, fn() {
              (core.call)("drive.kept.clear", obj([]), fn(_) { kept.asked += 1 })
            })
          }
        })
      })
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
                      kept.asked += 1
                    })
                  }
                  kept_files_clear(core, loose)
                  if kept.drive > 0.0 {
                    (core.call)("drive.kept.clear", obj([]), fn(_) { kept.asked += 1 })
                  }
                },
              )
            }
          })
        })
      }
    }
  }
  blocks
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
    kept.asked += 1
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
/// A kept file's bin (KeptFiles.kt: a 36 circle, its icon in its middle).
// kept across runs: a value (no field of it changes)
let kept_bin : @ui.Style = @ui.css("w=S9 h=S9 radius=Full align=ACenter justify=JCenter")

///|
/// A chat's (KeptChatScreen): what is kept of its messages, deleted when asked (`cache.clear`: read again from its
/// station when it is opened), and the files opened in it, each to delete; or all of it. Station "": the files of no
/// chat known.
pub fn kept_chat_blocks(c : @ui.Ctx, core : Core, station : String, thread : Int) -> (String, Array[() -> Unit]) {
  let t = @sf.theme()
  kept_read(c, core)
  let loose = station == ""
  let chat = match kept.chats {
    Some(a) if !loose => a.iter().find_first(fn(x) { text(Some(x), "station") == station && count(Some(x), "thread") == thread })
    _ => None
  }
  let files = if loose { kept.loose } else { items(chat, "files") }
  let title = if loose { tr("android-settings.files.loose") } else { text(chat, "title") }
  let blocks : Array[() -> Unit] = []
  let clear = fn() {
    match chat {
      Some(_) =>
        (core.call)("cache.clear", obj([("station", str(station)), ("thread", Json::number(thread.to_double()))]), fn(_) {
          kept.asked += 1
        })
      None => kept_files_clear(core, files)
    }
  }
  if kept.chats is None {
    blocks.push(fn() { waiting_rows(c) })
  } else {
    let messages = number(chat, "bytes")
    if chat is Some(_) {
      blocks.push(fn() {
        list_card(c, fn() {
          if size_row(c, if messages > 0.0 { "kept-messages" } else { "" }, tr("android-settings.files.messages"), tr("android-settings.files.messages.text"), messages) {
            confirm(tr("android-settings.files.messages"), tr("android-settings.files.messages.clear"), tr("android-settings.files.clear.action"), danger=true, fn() {
              (core.call)("cache.clear", obj([("station", str(station)), ("thread", Json::number(thread.to_double()))]), fn(_) {
                kept.asked += 1
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
  (title, blocks)
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
