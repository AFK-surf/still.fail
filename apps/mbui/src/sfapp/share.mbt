// Sharing (ember apps/android app/share/ShareActivity.kt, ShareSheet.kt; drive/DriveScreen.kt hand; docs/share-in.md).
//
// In: what another app shares into still.fail (Android's share sheet: ACTION_SEND of a link, some text or files,
// ACTION_SEND_MULTIPLE of files, @ui.shared_in; MBUI_SHARE_TEXT and MBUI_SHARE_TITLE for scripted runs, the host's
// MBUI_SHARE_FILES on macOS) opens one sheet: what is shared at its top (its title, the
// app's subject or its first line; a link's mark or text's), 发到 the chats it can go to (the core's `shareIn` view: the
// one a thing from the same site went to last first, saying so; 搜索 from six chats), 新 chat last (then which station,
// when there are more). A tap puts what is shared in that chat's composer (`shareIn.open`: a link as a card among its
// files, the words after what is written) and opens the chat there (or a new chat on that station), where it is added
// to and sent. Files (which the Android app does not take in) head the sheet as the composer shows them (pictures as
// tiles, a file's mark, name and size; n 个文件) and go into the chat's composer as attachments, up to the station at once
// as ＋'s files do (composer.mbt add_file); words shared with them go in through `shareIn.open` as before. The Android
// app shows the sheet over the app it came from (an activity of its own); here the app comes to the front and shows it
// over itself.
//
// Out: a file of a drive handed to another app (DriveScreen.kt openElsewhere with share): read whole through the core
// (`drive.read`), then the system's share sheet (@host.share: Android's chooser, a file of the app's own provider;
// macOS's sharing picker); 本机没有可打开此文件的应用 when nothing takes it.

///|
// kept across runs: a table, never written
let share_zh : Map[String, String] = {
  "android-misc.shareIn.to": "发到",
  "android-misc.shareIn.search": "搜索",
  "android-misc.shareIn.find": "找 chat",
  "android-misc.shareIn.newChat": "新 chat",
  "android-misc.shareIn.on": "在 {name} 上开",
  "android-misc.shareIn.failed": "没能打开：{error}",
  "android-misc.shareIn.update": "这台手机上的 still.fail 需要更新才能分享",
  "android-misc.drive.noApp": "本机没有可打开此文件的应用",
  "android-chat.ref.none.match": "没有标题匹配的对话",
  "common.cancel": "取消",
  "android-settings.files.count": "{n} 个文件",
  "common.reading": "正在读取",
}

///|
fn sh(key : String, args? : Array[(String, String)] = []) -> String {
  let mut s = share_zh.get(key).unwrap_or(tr(key))
  for a in args {
    s = s.replace_all(old="{" + a.0 + "}", new=a.1)
  }
  s
}

///|
/// A file shared in: its name and bytes; a picture's key once added (`mem:share-in/…`), else "".
priv struct SharedFile {
  name : String
  bytes : Bytes
  image : String
}

///|
/// What is being shared in, and how its sheet stands.
priv struct ShareIn {
  /// its words and the subject the app gave with them
  mut shared : (String, String?)?
  /// its files
  mut files : Array[SharedFile]
  /// its sheet raised (it closes by itself: then what is shared is let go)
  mut raised : Bool
  mut env_taken : Bool
  mut searching : Bool
  mut choosing : Bool
  /// the row being opened (its station, its id; "" a new chat)
  mut opening : (String, String)?
  mut error : String
  /// what is typed to find a chat (its field's words, last frame)
  mut query : String
  /// the words searched for (its field shows them)
  find : @ui.Field
}

///|
let share_in : ShareIn = {
  shared: None,
  files: [],
  raised: false,
  env_taken: false,
  searching: false,
  choosing: false,
  opening: None,
  error: "",
  query: "",
  find: @ui.Field::new(),
}

///|
/// From six chats the list can be searched.
let searched_from : Int = 6

///|
/// Each frame once signed in: what another app shared since, its sheet raised; let go once its sheet closed.
fn share_in_frame(c : @ui.Ctx) -> Unit {
  // (what the host says was shared, taken once: the same whichever build takes it)
  if share_in.shared is None {
    let said = @ui.shared_in()
    let mut got : (String, String?)? = None
    let files : Array[SharedFile] = []
    if said != "" {
      let v = try Some(@json.parse(said)) catch { _ => None }
      let title = text(v, "title")
      got = Some((text(v, "text"), if title == "" { None } else { Some(title) }))
      for i, f in items(v, "files") {
        let bytes = @ui.shared_in_file(i)
        if bytes.length() == 0 {
          continue
        }
        let name = text(Some(f), "name")
        let image = match image_size(bytes) {
          Some(_) => {
            share_files_made.val += 1
            let key = "mem:share-in/\{share_files_made.val}"
            @ui.add_image(key, bytes)
            key
          }
          None => ""
        }
        files.push({ name, bytes, image })
      }
      // (the host's words are these: the scripted run's are not taken again)
      share_in.env_taken = true
    } else if !share_in.env_taken {
      share_in.env_taken = true
      let words = @ui.env("MBUI_SHARE_TEXT")
      if words != "" {
        let title = @ui.env("MBUI_SHARE_TITLE")

        got = Some((words, if title == "" { None } else { Some(title) }))
      }
    }
    match got {
      Some((words, title)) if words.trim() != "" || files.length() > 0 => {
        @host.log("share in: \{words.length()} characters, \{files.length()} files")
        share_in.shared = Some((words, title))
        share_in.files = files
        share_in.raised = false
        share_in.searching = false
        share_in.choosing = false
        share_in.opening = None
        share_in.error = ""
        c.blur()
        raise_sheet(ShareSheet)
        share_in.raised = true
      }
      _ => ()
    }
  } else if share_in.raised && sheet_host.kind != ShareSheet {
    // closed (the scrim, back, dragged down): let go
    share_in.shared = None
    share_in.files = []
    share_in.raised = false
  }
}

///|
/// The sheet (ShareSheet.kt ShareSheetContent): what is shared, 发到 the chats, 新 chat.
fn share_in_sheet(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let t = @sf.theme()
  let (source, title) = match share_in.shared {
    Some(s) => s
    None => return
  }
  sheet_grab(c)
  if share_in.files.length() > 0 {
    shared_files_head(c, share_in.files, source, title)
  } else {
    shared_head(c, source, title)
  }
  let query = share_in.query
  let topic = (src.topic)("shareIn", {
    "scope": Json::string(w.id),
    "source": Json::string(source),
    "query": Json::string(if share_in.searching { query.trim().to_owned() } else { "" }),
  })
  let v = topic.value
  let rows = items(v, "items")
  c.box(dir=Row, w=Fill(1.0), padx=20.0, align=ACenter, fn() {
    c.box(w=Fill(1.0), pt=14.0, pb=4.0, fn() {
      c.text(sh("android-misc.shareIn.to"), size=13.0, color=t.p.muted, wrap=false) |> ignore
    })
    |> ignore
    if share_in.searching || rows.length() >= searched_from {
      let id = c.id("share-in/search")
      if c.clicked(id) {
        share_in.searching = !share_in.searching
        if !share_in.searching {
          share_in.query = ""
          share_in.find.set("")
        }
      }
      c.box(pt=14.0, pb=4.0, id~, fn() {
        c.text(
          if share_in.searching { sh("common.cancel") } else { sh("android-misc.shareIn.search") },
          size=13.0,
          color=t.p.muted,
          wrap=false,
        )
        |> ignore
      })
      |> ignore
    }
  })
  |> ignore
  if share_in.searching {
    c.box(w=Fill(1.0), pl=20.0, pr=20.0, pb=4.0, fn() {
      c.box(w=Fill(1.0), h=Px(40.0), radius=12.0, bg=t.p.chip, padx=12.0, justify=JCenter, fn() {
        let r = c.editor(
          "share-in/find",
          placeholder=sh("android-misc.shareIn.find"),
          font_size=15.0,
          max_lines=1,
          plain=true,
          color=t.p.text,
          placeholder_color=t.p.muted,
          caret_color=t.p.accent,
          field=share_in.find,
        )
        share_in.query = r.text
      })
      |> ignore
    })
    |> ignore
  }
  let opening = share_in.opening
  c.box(w=Fill(1.0), h=Fill(1.0), pb=16.0, clip=true, fn() {
    match v {
      None =>
        c.box(w=Fill(1.0), padx=20.0, pt=8.0, fn() {
          @sf.wait_line(
            c,
            if topic.error is Some(_) { sh("android-misc.shareIn.update") } else { sh("common.reading") },
            key="share-in",
            error=topic.error is Some(_),
          )
        })
        |> ignore
      Some(_) => {
        let kept = field(v, "kept")
        for item in rows {
          let it = Some(item)
          let station = text(it, "station")
          let id = text(it, "id")
          // (where things of a site went last: files have no site)
          let kept_here = text(kept, "station") == station &&
            text(kept, "id") == id &&
            source.trim() != ""
          let sub = if kept_here {
            text(kept, "text")
          } else {
            match text(field(it, "last"), "preview") {
              "" => line_of(it)
              p => p
            }
          }
          let agent = items(it, "agents").get(0)
          if share_row(
              c,
              "share-in/row/" + station + "/" + id,
              text(it, "title"),
              sub,
              false,
              opening == Some((station, id)),
              opening is None,
              fn() {
                match agent {
                  Some(a) => @sf.maker_mark(c, text(Some(a), "maker"), text(Some(a), "runtime"), 14.0) |> ignore
                  None => ()
                }
              },
            ) {
            share_open(c, src, w, station, Some(id), session=text(it, "session"))
          }
        }
        if rows.length() == 0 && share_in.searching && query.trim() != "" {
          share_note(c, sh("android-chat.ref.none.match"))
        }
        let stations = items(v, "stations")
        let new_on = text(v, "newOn")
        let on = match stations.iter().find_first(fn(s) { text(Some(s), "station") == new_on }) {
          Some(s) => Some(s)
          None => stations.get(0)
        }
        match on {
          Some(s) if !share_in.searching || query.trim() == "" => {
            let many = stations.length() > 1
            let on_station = text(Some(s), "station")
            if share_row(
                c,
                "share-in/new",
                sh("android-misc.shareIn.newChat"),
                if many && share_in.choosing {
                  ""
                } else {
                  sh("android-misc.shareIn.on", args=[("name", text(Some(s), "name"))])
                },
                false,
                !many && opening == Some((on_station, "")),
                opening is None,
                fn() { @sf.icon(c, "compose", size=16.0, color=t.p.muted) |> ignore },
              ) {
              if many {
                share_in.choosing = !share_in.choosing
              } else {
                share_open(c, src, w, on_station, None)
              }
            }
            if many && share_in.choosing {
              for st in stations {
                let station = text(Some(st), "station")
                if share_row(
                    c,
                    "share-in/on/" + station,
                    text(Some(st), "name"),
                    "",
                    station == on_station,
                    opening == Some((station, "")),
                    opening is None,
                    fn() {  },
                  ) {
                  share_open(c, src, w, station, None)
                }
              }
            }
          }
          _ => ()
        }
        match text(v, "note") {
          "" => ()
          n => share_note(c, n)
        }
      }
    }
  })
  |> ignore
  if share_in.error != "" {
    c.box(w=Fill(1.0), padx=20.0, pb=16.0, fn() {
      c.text(share_in.error, size=13.0, color=t.p.red) |> ignore
    })
    |> ignore
  }
}

///|
/// What is shared (ShareSheet.kt SharedHead): its mark (a link's or text's), its title (the app's subject, else its first
/// line) bold, its first line under a subject.
fn shared_head(c : @ui.Ctx, source : String, title : String?) -> Unit {
  let t = @sf.theme()
  let mut first = ""
  for l in source.split("\n") {
    let x = l.to_owned().trim().to_owned()
    if first == "" && x != "" {
      first = x
    }
  }
  let head = title.unwrap_or(first)
  let link = source.to_lower().contains("http://") || source.to_lower().contains("https://")
  c.box(dir=Row, w=Fill(1.0), pl=20.0, pr=20.0, pt=4.0, pb=2.0, gap=12.0, fn() {
    c.box(w=Px(16.0), pt=3.0, align=ACenter, fn() {
      @sf.icon(c, if link { "web" } else { "text" }, size=16.0, color=t.p.muted) |> ignore
    })
    |> ignore
    c.box(w=Fill(1.0), fn() {
      c.box(w=Fill(1.0), max_h=48.0, clip=true, fn() {
        c.text(head, size=17.0, weight=700, color=t.p.text, line=24.0, w=Fill(1.0)) |> ignore
      })
      |> ignore
      if title is Some(_) {
        c.box(w=Fill(1.0), clip=true, fn() {
          c.text(first, size=13.0, color=t.p.muted, wrap=false) |> ignore
        })
        |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// A row's second line without a last message: when it was last active, and on which station.
fn line_of(it : Json?) -> String {
  let parts = []
  let ago = text(field(field(it, "time"), "lastActiveAt"), "ago")
  if ago != "" {
    parts.push(ago)
  }
  let name = text(it, "stationName")
  if name != "" {
    parts.push(name)
  }
  parts.join(" · ")
}

///|
/// A line in the rows' place: why there are none, or what to do first.
fn share_note(c : @ui.Ctx, words : String) -> Unit {
  c.box(w=Fill(1.0), padx=20.0, pady=12.0, fn() {
    c.text(words, size=15.0, color=@sf.theme().p.muted) |> ignore
  })
  |> ignore
}

///|
/// A row of the sheet (Controls.kt PickRow): its mark in a 16 column, its title, a line under it, checked, a spinner
/// while it opens; faint while another opens. True on the frame it was tapped.
fn share_row(
  c : @ui.Ctx,
  key : String,
  title : String,
  sub : String,
  checked : Bool,
  busy : Bool,
  enabled : Bool,
  lead : () -> Unit,
) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  c.box(w=Fill(1.0), pl=12.0, pr=12.0, opacity=if enabled || busy { 1.0 } else { 0.5 }, fn() {
    c.box(
      dir=Row,
      w=Fill(1.0),
      padx=8.0,
      pady=12.0,
      gap=12.0,
      align=ACenter,
      bg=@sf.alpha(t.p.text, 0.06 * @motion.pressing(c, id)),
      id=if enabled { id } else { 0 },
      fn() {
        c.box(w=Px(16.0), align=ACenter, fn() { lead() }) |> ignore
        c.box(w=Fill(1.0), clip=true, fn() {
          c.text(title, size=15.0, color=t.p.text, wrap=false, line=21.0) |> ignore
          if sub != "" {
            c.text(sub, size=13.0, color=t.p.muted, wrap=false, line=18.0) |> ignore
          }
        })
        |> ignore
        if busy {
          @sf.spinner(c, size=14.0) |> ignore
        } else if checked {
          @sf.icon(c, "check", size=14.0, color=t.p.accent) |> ignore
        }
      },
    )
    |> ignore
  })
  |> ignore
  enabled && c.clicked(id)
}

///|
/// What is shared put in the chat's composer (`shareIn.open`; a new chat's on `station` with no `id`), then that chat
/// opened (or a new chat rising), its draft read anew.
fn share_open(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  station : String,
  id : String?,
  session? : String = "",
) -> Unit {
  let (source, title) = match share_in.shared {
    Some(s) => s
    None => return
  }
  if share_in.opening is Some(_) {
    return
  }
  let files = share_in.files
  // files alone: nothing for the core to put in the composer; the chat (or a new chat on that station) opened with
  // them going up from its composer
  if source.trim() == "" {
    share_opened(c, station, match id {
      Some(x) => if session != "" { session } else { x }
      None => ""
    }, "", files, fn() {
      match id {
        // (the station by its own id, the address's last part, as the core's shareIn.open picks it)
        None => {
          let parts = station.split("/").to_array()
          pick_new(c, src, w.id, { "station": Json::string(parts[parts.length() - 1].to_owned()) })
        }
        Some(_) => ()
      }
    })
    return
  }
  share_in.opening = Some((station, id.unwrap_or("")))
  share_in.error = ""
  let params : Map[String, Json] = {
    "scope": Json::string(w.id),
    "source": Json::string(source),
    "station": Json::string(station),
  }
  match id {
    Some(x) => params["id"] = Json::string(x)
    None => ()
  }
  match title {
    Some(x) => params["title"] = Json::string(x)
    None => ()
  }
  (src.call)("shareIn.open", Json::object(params), fn(r) {
    share_in.opening = None
    match r {
      Ok(a) => {
        let key = text(Some(a), "key")
        // the composer reads what the core keeps anew (Drafts.refresh)
        drafts.remove(key)
        share_opened(c, station, text(Some(a), "session"), text(Some(a), "title"), files, fn() {  }, key~)
      }
      Err(e) => share_in.error = sh("android-misc.shareIn.failed", args=[("error", text(Some(e), "message"))])
    }
  })
}

///|
/// What is shared gone into a chat's composer (`session`; "" a new chat on `station`, made the one new chats start on by
/// `pick`): the sheet let go, the chat opened (a new chat rising), the files handed to its composer, which puts them up.
fn share_opened(
  c : @ui.Ctx,
  station : String,
  session : String,
  title : String,
  files : Array[SharedFile],
  pick : () -> Unit,
  key? : String,
) -> Unit {
  let key = match key {
    Some(k) => k
    None => if session == "" { "new:" + station } else { station + ":" + session }
  }
  if files.length() > 0 {
    let list = shared_into.get(key).unwrap_or([])
    for f in files {
      list.push({ name: f.name, bytes: f.bytes })
    }
    shared_into[key] = list
  }
  share_in.shared = None
  share_in.files = []
  share_in.raised = false
  lower_sheet()
  @host.log("share in: into \{key}, \{files.length()} files")
  if session == "" {
    pick()
    while app.nav.depth() > 1 {
      if !app.nav.pop() {
        break
      }
    }
    app.nav.rise(NewChat)
  } else {
    app.nav.push(Chat({ station, session, title, station_name: "" }))
  }
}

///|
/// Files shared in waiting for their chat's composer to take them, by its draft's key (composer.mbt).
let shared_into : Map[String, Array[@host.Picked]] = Map([])

///|
/// How many pictures shared in have been added as images (their keys' numbers).
let share_files_made : Ref[Int] = { val: 0 }

///|
/// What is shared when it is files (the composer's own look: shared_head's place): their pictures as 56 tiles, then
/// a file's mark with its name bold (n 个文件 for several) and under it its size (their names), the words shared with
/// them, when any, under that.
fn shared_files_head(c : @ui.Ctx, files : Array[SharedFile], words : String, title : String?) -> Unit {
  let t = @sf.theme()
  let pictures = files.filter(fn(f) { f.image != "" })
  if pictures.length() > 0 {
    c.box(dir=Row, w=Fill(1.0), pl=20.0, pr=20.0, pt=4.0, pb=8.0, gap=8.0, clip=true, fn() {
      for f in pictures {
        c.box(w=Px(56.0), h=Px(56.0), radius=16.0, bg=t.p.chip, clip=true, fn() {
          c.image(f.image, w=Px(56.0), h=Px(56.0), radius=16.0, fit=FitCover, bg=0L) |> ignore
        })
        |> ignore
      }
    })
    |> ignore
  }
  let one = files.length() == 1
  let mut size = 0
  for f in files {
    size += f.bytes.length()
  }
  let head = if one { files[0].name } else { sh("android-settings.files.count", args=[("n", "\{files.length()}")]) }
  let under = if one {
    file_size(size.to_double())
  } else {
    files.map(fn(f) { f.name }).join("、")
  }
  let said = match title {
    Some(x) => x
    None => words.trim().to_owned()
  }
  c.box(dir=Row, w=Fill(1.0), pl=20.0, pr=20.0, pt=4.0, pb=2.0, gap=12.0, fn() {
    c.box(w=Px(16.0), pt=3.0, align=ACenter, fn() {
      @sf.icon(c, if pictures.length() == files.length() { "photo" } else { "file" }, size=16.0, color=t.p.muted)
      |> ignore
    })
    |> ignore
    c.box(w=Fill(1.0), fn() {
      c.box(w=Fill(1.0), clip=true, fn() {
        c.text(head, size=17.0, weight=700, color=t.p.text, line=24.0, wrap=false) |> ignore
      })
      |> ignore
      c.box(w=Fill(1.0), clip=true, fn() {
        c.text(under, size=13.0, color=t.p.muted, wrap=false) |> ignore
      })
      |> ignore
      if said != "" {
        c.box(w=Fill(1.0), clip=true, fn() {
          c.text(said, size=13.0, color=t.p.muted, wrap=false) |> ignore
        })
        |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// A file of a drive handed to another app (DriveScreen.kt openElsewhere, share): read through the core a part at a
/// time, how far on its row meanwhile (keep.mbt drive_fetch), then the system's share sheet; said when nothing takes it.
fn share_drive_file(c : @ui.Ctx, src : Source, at : DriveAt, e : DvEntry) -> Unit {
  let root = at.root.unwrap_or("")
  let path = dv_join(at.path, e.name)
  let all = Buffer(size_hint=if e.size > 0.0 { e.size.to_int() } else { 0 })
  drive_fetch(
    src,
    at.station,
    root,
    path,
    fn(b) {
      all.write_bytes(b)
      true
    },
    fn(err) {
      match err {
        None =>
          if !@ui.share("", e.name, e.mime, all.to_bytes()) {
            app.toast = sh("android-misc.drive.noApp")
            app.toast_n += 1
          }
        Some(err) => {
          app.toast = fill("android-misc.drive.fetchFailed", [("name", e.name), ("error", dv_error(err))])
          app.toast_n += 1
        }
      }
    },
  )
}
