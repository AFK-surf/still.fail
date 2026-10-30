// Sharing (ember apps/android app/share/ShareActivity.kt, ShareSheet.kt; drive/DriveScreen.kt hand; docs/share-in.md).
//
// In: what another app shares into still.fail (Android's share sheet: ACTION_SEND of a link, some text or files,
// ACTION_SEND_MULTIPLE of files, iOS's share extension's as the app next comes to the front, @ui.shared_in;
// MBUI_SHARE_TEXT and MBUI_SHARE_TITLE for scripted runs, the host's MBUI_SHARE_FILES on macOS and iOS) opens one
// sheet: what is shared at its top (its title, the app's subject or its first line; a link's mark or text's), 发到
// the chats it can go to (the core's `shareIn` view: the one a thing from the same site went to last first, saying so;
// 搜索 from six chats), 新 chat last (then which station,
// when there are more). A tap puts what is shared in that chat's composer (`shareIn.open`: a link as a card among its
// files, the words after what is written) and opens the chat there (or a new chat on that station), where it is added
// to and sent. Files (which the Android app does not take in) head the sheet as the composer shows them (pictures as
// tiles, a file's mark, name and size; n 个文件) and go into the chat's composer as attachments, up to the station at once
// as ＋'s files do (composer.mbt add_file); words shared with them go in through `shareIn.open` as before. The sheet
// shows over the app it came from (Android's OverActivity, as the Android app's ShareActivity: the host says so,
// @hostapi.system_channel `over`), on the page's paper: nothing of the app's own under it. Closed, the app goes and the
// person is back where they were; gone into a chat, the app opens at it (@ui.over_done). Signed out, it says to sign in
// in the app first, with 打开 still.fail.
//
// Out: a file of a drive handed to another app (DriveScreen.kt openElsewhere with share): read whole through the core
// (`drive.read`), then the system's share sheet (@hostapi.share: Android's chooser, a file of the app's own provider;
// macOS's sharing picker); 本机没有可打开此文件的应用 when nothing takes it.

///|
fn sh(key : String, args? : Array[(String, String)] = []) -> String {
  fill(key, args)
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
  shared : @signals.Signal[(String, String?)?]
  /// its files
  files : @signals.Signal[Array[SharedFile]]
  /// its sheet raised (it closes by itself: then what is shared is let go)
  raised : @signals.Signal[Bool]
  env_taken : @signals.Signal[Bool]
  searching : @signals.Signal[Bool]
  choosing : @signals.Signal[Bool]
  /// the row being opened (its station, its id; "" a new chat)
  opening : @signals.Signal[(String, String)?]
  error : @signals.Signal[String]
  /// what is typed to find a chat (its field's words, last frame)
  query : @signals.Signal[String]
  /// the words searched for (its field shows them)
  find : @ui.Field
}

///|
let share_in : ShareIn = {
  shared: @signals.signal(None),
  files: @signals.signal([]),
  raised: @signals.signal(false, same=fn(a, b) { a == b }),
  env_taken: @signals.signal(false, same=fn(a, b) { a == b }),
  searching: @signals.signal(false, same=fn(a, b) { a == b }),
  choosing: @signals.signal(false, same=fn(a, b) { a == b }),
  opening: @signals.signal(None),
  error: @signals.signal("", same=fn(a, b) { a == b }),
  query: @signals.signal("", same=fn(a, b) { a == b }),
  find: @ui.Field::new(),
}



///|
/// Over another app, its sheet closed by hand: the app goes once it has sunk away (ShareScreen: onClose after its spring).
let share_closing : Ref[Bool] = Ref(false)

///|
/// 打开 still.fail, as a link's words (ShareSheet.kt SignInFirst: 15, semibold, the link's ink).
// kept across runs: a value (no field of it changes)
let open_app_words : @ui.TextStyle = @ui.text_style(size=Ui, weight=Semibold, color=Link)

///|
// kept across runs: a value (no field of it changes)
let open_app_box : @ui.Style = @ui.css("px=S5 py=S2 pb=S6")

///|
/// Over another app (ShareActivity): what is shared taken, its sheet over that app and nothing else; the toasts.
fn over_view(c : @ui.Ctx, src : Source) -> Unit {
  share_in_frame(c)
  sheet_contents(fn(kind) { if kind == ShareSheet { share_over_sheet(c, src) } })
  // (nothing of the app's under it: on the page's paper)
  @sf.presented(c, alone=true)
  toast(c)
}

///|
/// The sheet over another app (ShareSheet.kt ShareSheetContent): the chats once the core says them, the workspace the
/// app was last in (else the first); reading meanwhile; signed out, to sign in first (SignInFirst).
fn share_over_sheet(c : @ui.Ctx, src : Source) -> Unit {
  let accounts = (src.topic)("accounts", {})
  let (source, title) = match share_in.shared.get() {
    Some(s) => s
    None => return
  }
  let head = fn() {
    if share_in.files.get().length() > 0 {
      shared_files_head(c, share_in.files.get(), source, title)
    } else {
      shared_head(c, source, title)
    }
  }
  match accounts.value {
    Some(Array(list)) if list.length() == 0 => {
      head()
      share_note(c, sh("android-misc.shareIn.signIn"))
      let id = c.id("share-in/open-app")
      if c.clicked(id) {
        @ui.over_done(open_app=true)
      }
      c.box(style=open_app_box, id~, fn() {
        // (in still.fail's own theme: its size and the link's ink as Android's C.link, not mbui's own blue)
        c.with_theme(@sf.ui_theme(), fn() {
          c.text(sh("android-misc.shareIn.openApp"), style=open_app_words) |> ignore
        })
      })
      |> ignore
    }
    Some(Array(_)) => {
      let ws = (src.topic)("workspaces", {})
      let prefs = (src.topic)("prefs", {})
      let (all, answered, _) = workspaces_of(ws.value)
      let kept = text(prefs.value, "workspace")
      match all.iter().find_first(fn(w) { w.id == kept }) {
        Some(w) => share_in_sheet(c, src, w)
        None if all.length() > 0 && (kept == "" || answered) => share_in_sheet(c, src, all[0])
        _ => {
          head()
          share_reading(c)
        }
      }
    }
    _ => {
      head()
      share_reading(c)
    }
  }
}

///|
fn share_reading(c : @ui.Ctx) -> Unit {
  c.box(style=share_reading_box, fn() { @sf.wait_line(c, sh("common.reading"), key="share-in") }) |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let share_reading_box : @ui.Style = @ui.css("w=Full px=S5 pt=S2")

///|
/// From six chats the list can be searched.
let searched_from : Int = 6

///|
/// Each frame once signed in: what another app shared since, its sheet raised; let go once its sheet closed.
fn share_in_frame(c : @ui.Ctx) -> Unit {
  // (what the host says was shared, taken once: the same whichever build takes it)
  if share_in.shared.get() is None {
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
        let image = match @pixels.image_size(bytes) {
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
      share_in.env_taken.set(true)
    } else if !share_in.env_taken.get() {
      share_in.env_taken.set(true)
      let words = @ui.env("MBUI_SHARE_TEXT")
      if words != "" {
        let title = @ui.env("MBUI_SHARE_TITLE")

        got = Some((words, if title == "" { None } else { Some(title) }))
      }
    }
    match got {
      Some((words, title)) if words.trim() != "" || files.length() > 0 => {
        @hostapi.log("share in: \{words.length()} characters, \{files.length()} files")
        share_in.shared.set(Some((words, title)))
        share_in.files.set(files)
        share_in.raised.set(false)
        share_in.searching.set(false)
        share_in.choosing.set(false)
        share_in.opening.set(None)
        share_in.error.set("")
        c.blur()
        raise_sheet(ShareSheet)
        share_in.raised.set(true)
      }
      _ => ()
    }
  } else if share_in.raised.get() && sheet_host.kind != ShareSheet {
    // closed (the scrim, back, dragged down): let go; over another app, the app goes once the sheet has sunk away
    share_in.shared.set(None)
    share_in.files.set([])
    share_in.raised.set(false)
    if share_over.get() {
      share_closing.val = true
    }
  }
  if share_closing.val && share_over.get() && !@sf.presented_drawn() {
    share_closing.val = false
    @ui.over_done(open_app=false)
  }
}

///|
/// The sheet (ShareSheet.kt ShareSheetContent): what is shared, 发到 the chats, 新 chat.
fn share_in_sheet(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let t = @sf.theme()
  let (source, title) = match share_in.shared.get() {
    Some(s) => s
    None => return
  }
  if share_in.files.get().length() > 0 {
    shared_files_head(c, share_in.files.get(), source, title)
  } else {
    shared_head(c, source, title)
  }
  let query = share_in.query.get()
  let topic = (src.topic)("shareIn", {
    "scope": Json::string(w.id),
    "source": Json::string(source),
    "query": Json::string(if share_in.searching.get() { query.trim().to_owned() } else { "" }),
  })
  let v = topic.value
  let rows = items(v, "items")
  c.box(dir=Row, w=Fill(1.0), padx=20.0, align=ACenter, fn() {
    c.box(w=Fill(1.0), pt=14.0, pb=4.0, fn() {
      c.text(sh("android-misc.shareIn.to"), size=t.t.meta, color=t.p.muted, wrap=false) |> ignore
    })
    |> ignore
    if share_in.searching.get() || rows.length() >= searched_from {
      let id = c.id("share-in/search")
      if c.clicked(id) {
        share_in.searching.set(!share_in.searching.get())
        if !share_in.searching.get() {
          share_in.query.set("")
          share_in.find.set("")
        }
      }
      c.box(pt=14.0, pb=4.0, id~, fn() {
        c.text(
          if share_in.searching.get() { sh("common.cancel") } else { sh("android-misc.shareIn.search") },
          size=t.t.meta,
          color=t.p.muted,
          wrap=false,
        )
        |> ignore
      })
      |> ignore
    }
  })
  |> ignore
  if share_in.searching.get() {
    c.box(w=Fill(1.0), pl=20.0, pr=20.0, pb=4.0, fn() {
      // (Controls.kt Field: the surface, a line round it, as the invitation's field)
      c.box(style=invite_field, h=Px(40.0), justify=JCenter, fn() {
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
        share_in.query.set(r.text)
      })
      |> ignore
    })
    |> ignore
  }
  let opening = share_in.opening.get()
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
                  Some(a) => @sf.maker_mark(c, text(field(Some(a), "maker"), "id"), text(Some(a), "runtime"), 14.0) |> ignore
                  None => ()
                }
              },
            ) {
            share_open(c, src, w, station, Some(id), session=text(it, "session"))
          }
        }
        if rows.length() == 0 && share_in.searching.get() && query.trim() != "" {
          share_note(c, sh("android-chat.ref.none.match"))
        }
        let stations = items(v, "stations")
        let new_on = text(v, "newOn")
        let on = match stations.iter().find_first(fn(s) { text(Some(s), "station") == new_on }) {
          Some(s) => Some(s)
          None => stations.get(0)
        }
        match on {
          Some(s) if !share_in.searching.get() || query.trim() == "" => {
            let many = stations.length() > 1
            let on_station = text(Some(s), "station")
            if share_row(
                c,
                "share-in/new",
                sh("android-misc.shareIn.newChat"),
                if many && share_in.choosing.get() {
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
                share_in.choosing.set(!share_in.choosing.get())
              } else {
                share_open(c, src, w, on_station, None)
              }
            }
            if many && share_in.choosing.get() {
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
  if share_in.error.get() != "" {
    c.box(w=Fill(1.0), padx=20.0, pb=16.0, fn() {
      c.text(share_in.error.get(), size=t.t.meta, color=t.p.red) |> ignore
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
      // (two lines at most, the last ending in an ellipsis: not a third cut off below them)
      c.text(head, size=t.t.title, weight=700, color=t.p.text, line=24.0, w=Fill(1.0), max_lines=2) |> ignore
      if title is Some(_) {
        c.box(w=Fill(1.0), clip=true, fn() {
          c.text(first, size=t.t.meta, color=t.p.muted, wrap=false) |> ignore
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
    c.text(words, size=@sf.theme().t.body, color=@sf.theme().p.muted) |> ignore
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
      id=if enabled { id } else { 0 },
      fn() {
        c.box(w=Px(16.0), align=ACenter, fn() { lead() }) |> ignore
        c.box(w=Fill(1.0), clip=true, fn() {
          c.text(title, size=t.t.ui, color=t.p.text, wrap=false, line=21.0) |> ignore
          if sub != "" {
            c.text(sub, size=t.t.meta, color=t.p.muted, wrap=false, line=18.0) |> ignore
          }
        })
        |> ignore
        if busy {
          @sf.spinner(c, size=14.0) |> ignore
        } else if checked {
          @sf.icon(c, "check", size=14.0, color=t.p.accent) |> ignore
        }
        // a PickRow: clip(Smooth(LIST_ROW_CORNER)).clickable
        if enabled {
          @motion.ripple(c, id, @sf.row_corner)
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
  let (source, title) = match share_in.shared.get() {
    Some(s) => s
    None => return
  }
  if share_in.opening.get() is Some(_) {
    return
  }
  let files = share_in.files.get()
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
          pick_new(src, w.id, { "station": Json::string(parts[parts.length() - 1].to_owned()) })
        }
        Some(_) => ()
      }
    })
    return
  }
  share_in.opening.set(Some((station, id.unwrap_or(""))))
  share_in.error.set("")
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
    share_in.opening.set(None)
    match r {
      Ok(a) => {
        let key = text(Some(a), "key")
        // the composer reads what the core keeps anew (Drafts.refresh)
        drafts.remove(key)
        share_opened(c, station, text(Some(a), "session"), text(Some(a), "title"), files, fn() {  }, key~)
      }
      Err(e) => share_in.error.set(sh("android-misc.shareIn.failed", args=[("error", text(Some(e), "message"))]))
    }
  })
}

///|
/// What is shared gone into a chat's composer (`session`; "" the workspace's new chat, `station` made the one it starts
/// on by `pick`): the sheet let go, the chat opened (a new chat rising), the files handed to its composer, which puts
/// them up.
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
    None => if session == "" { "new:" + workspace_of(station) } else { station + ":" + session }
  }
  if files.length() > 0 {
    let list = shared_into.get(key).unwrap_or([])
    for f in files {
      list.push({ name: f.name, bytes: f.bytes, held: 0, size: f.bytes.length().to_double(), src: "" })
    }
    shared_into[key] = list
    @sfbase.draft_given()
  }
  share_in.shared.set(None)
  share_in.files.set([])
  share_in.raised.set(false)
  lower_sheet()
  @hostapi.log("share in: into \{key}, \{files.length()} files")
  @sfbase.history_push()
  // over another app: the app opens at the chat (ShareActivity openApp: MainActivity's openItem, over Home)
  if share_over.get() {
    home()
    @ui.over_done(open_app=true)
  }
  if session == "" {
    pick()
    while app.nav.depth() > 1 {
      if !app.nav.pop() {
        break
      }
    }
    open_page(NewChat)
  } else {
    app.nav.push(Chat({ station, session, title, station_name: "" }))
  }
}


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
    @sf.file_size(size.to_double())
  } else {
    files.map(fn(f) { f.name }).join(tr("web-main.list.separator"))
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
        c.text(head, size=t.t.title, weight=700, color=t.p.text, line=24.0, wrap=false) |> ignore
      })
      |> ignore
      c.box(w=Fill(1.0), clip=true, fn() {
        c.text(under, size=t.t.meta, color=t.p.muted, wrap=false) |> ignore
      })
      |> ignore
      if said != "" {
        c.box(w=Fill(1.0), clip=true, fn() {
          c.text(said, size=t.t.meta, color=t.p.muted, wrap=false) |> ignore
        })
        |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

