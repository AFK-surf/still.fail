// Sharing.
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
// Out: a file of a drive handed to another app: read whole through the core
// (`drive.read`), then the system's share sheet (@hostapi.share: Android's chooser, a file of the app's own provider;
// macOS's sharing picker); 本机没有可打开此文件的应用 when nothing takes it. A chat's picture or file the same from its
// preview on a phone (sfbase viewer.mbt's Viewer::ask_share: its bar, a picture's held menu, a file told of).

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
/// Whether what is shared is up in the wide window's panel (share_panel) rather than in a sheet: by the window, as the
/// library's presenters are (a sheet on Small).
// kept across runs: put back by the package's reset (app.mbt)
let share_wide : @signals.Signal[Bool] = @signals.signal(false, same=fn(a, b) { a == b })

///|
/// How tall the wide panel's rows may stand, as share_panel last worked it out.
// kept across runs: told anew by each frame before it is read
let share_list_most : Ref[Double] = Ref(400.0)

///|
/// Whether what is shared fills the window rather than a sheet: over another app in a browser, its window the browser
/// extension's own (web/src/mbui/share.ts), with nothing of another app under it.
fn share_inline() -> Bool {
  share_over.get() && @ui.platform() == 4
}

///|
/// That window: what a sheet holds, a sheet's 20 in, room over it as a sheet has under its grip.
// kept across runs: a value (no field of it changes)
let share_window : @ui.Style = @ui.css("w=Full h=Full px=S5 pt=S6 bg=Bg")

///|
/// Over another app, its sheet closed by hand: the app goes once it has sunk away (ShareScreen: onClose after its spring).
let share_closing : Ref[Bool] = Ref(false)

///|
/// Its sheet closed (by hand, or a chat picked): what it shows kept as it was while it sinks away, let go of once it has
/// gone (share_in_frame).
let share_sinking : Ref[Bool] = Ref(false)

///|
/// 打开 still.fail, as a link's words (semibold, the link's ink).
// kept across runs: a value (no field of it changes)
let open_app_words : @ui.TextStyle = @ui.text_style(size=Ui, weight=Semibold, color=Link)

///|
// kept across runs: a value (no field of it changes)
let open_app_box : @ui.Style = @ui.css("px=S5 py=S2 pb=S6")

///|
/// Over another app (ShareActivity): what is shared taken, its sheet over that app and nothing else; the toasts.
fn over_view(c : @ui.Ctx, src : Source) -> Unit {
  share_in_frame(c)
  // a browser's window of its own (the extension's): nothing under the sheet to show, so what it holds is the window's
  if share_inline() {
    c.box(style=share_window, fn() { share_over_sheet(c, src) }) |> ignore
    return
  }
  sheet_contents(fn(kind) { if kind == ShareSheet { share_over_sheet(c, src) } })
  // (nothing of the app's under it: on the page's paper)
  @sf.presented(c, alone=true)
}

///|
/// The sheet over another app: the chats once the core says them, the workspace the
/// app was last in (else the first); reading meanwhile; signed out, to sign in first (SignInFirst).
fn share_over_sheet(c : @ui.Ctx, src : Source) -> Unit {
  let accounts = src.topic("accounts", {}).get().snapshot()
  let (source, title) = match share_in.shared.get() {
    Some(s) => s
    None => return
  }
  let head = fn() {
    if share_in.files.get().length() > 0 {
      shared_files_head(c, share_in.files.get(), source, title, share_narrow)
    } else {
      shared_head(c, source, title, share_narrow)
    }
  }
  match accounts.value {
    Some(Array(list)) if list.length() == 0 => {
      head()
      share_note(c, sh("android-misc.shareIn.signIn"), share_narrow)
      let id = c.id("share-in/open-app")
      c.on_press(id, fn() {
        @ui.over_done(open_app=true)
      })
      c.box(style=open_app_box, id~, fn() {
        // (in still.fail's own theme: its size and the link's ink as Android's C.link, not mbui's own blue)
        c.with_theme(@sf.ui_theme(), fn() {
          c.text(sh("android-misc.shareIn.openApp"), style=open_app_words) |> ignore
        })
      })
      |> ignore
    }
    Some(Array(_)) => {
      let ws = src.topic("workspaces", {}).get().snapshot()
      let prefs = src.topic("prefs", {}).get().snapshot()
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
  // up: in a sheet on a Small window (and over another app), else in the wide panel, as the window is now
  if share_in.raised.get() && !share_over.get() {
    let small = sheet_small(c)
    if small && share_wide.get() {
      share_wide.set(false)
      raise_sheet(ShareSheet)
    } else if !small && sheet_host.kind == ShareSheet {
      share_wide.set(true)
      lower_sheet()
    }
  }
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
      }
      _ => ()
    }
  } else if share_in.raised.get() && sheet_host.kind != ShareSheet && !share_wide.get() && !share_inline() {
    // closed (the scrim, back, dragged down): what it shows kept as it was while it sinks away, let go of once it has
    // (below); over another app, the app goes then
    share_in.raised.set(false)
    share_sinking.val = true
    if share_over.get() {
      share_closing.val = true
    }
  }
  // put up once shared: in a sheet on a Small window or over another app, the wide panel otherwise; filling the window
  // the browser extension opened
  if share_in.shared.get() is Some(_) && !share_in.raised.get() && !share_sinking.val {
    if share_inline() {
      ()
    } else if !share_over.get() && !sheet_small(c) {
      share_wide.set(true)
    } else {
      raise_sheet(ShareSheet)
    }
    share_in.raised.set(true)
  }
  if share_sinking.val && !@sf.presented_drawn() {
    share_sinking.val = false
    share_in.shared.set(None)
    share_in.files.set([])
  }
  if share_closing.val && share_over.get() && !@sf.presented_drawn() {
    share_closing.val = false
    @ui.over_done(open_app=false)
  }
}

///|
/// How the body is laid out: a phone's sheet (its PickRows) or the wide frame's panel
/// .
priv struct ShareLook {
  wide : Bool
  /// how far its words stand in from the body's sides
  side : Double
  /// the mark column's width, and the marks in it (what is shared, a row's picture)
  col : Double
  icon : Double
  /// between a mark and its words
  gap : Double
  /// what is shared: room over and under it, its mark's box's height, its title's and its words' lines
  head_pt : Double
  head_pb : Double
  head_mark_h : Double
  head_words_pt : Double
  title_line : Double
  source_line : Double
  /// 发到 (and 新 chat 开在): room over and under it
  label_pt : Double
  label_pb : Double
  /// under the list, and a row's height as a list first guesses it
  list_pb : Double
  row_est : Double
  /// a row: its least height, how far in its words stand, its corner, its title's line, between its title and line
  row_h : Double
  row_padx : Double
  row_pady : Double
  row_corner : Double
  row_line : Double
  row_gap : Double
  /// a chat's model mark
  model : Double
  /// the whole width, its words `side` in
  inset : @ui.Style
  /// files shared: how far in their tiles and words stand (a tile's corner concentric in the panel's at the wide one)
  files_in : Double
  /// room over the pictures shared, and a picture's tile's corner: concentric in what holds it (the wide panel's, 20
  /// in: one of the ladder's)
  files_top : Double
  tile_corner : Double
}

///|
// kept across runs: a value (no field of it changes)
let share_whole : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let share_cut : @ui.Style = @ui.css("w=Full clip")

///|
/// 找 chat under 发到; 正在读取 where the rows will be; what went wrong.
// kept across runs: a value (no field of it changes)
let share_find_room : @ui.Style = @ui.css("pt=S1_5 pb=S1")

///|
// kept across runs: a value (no field of it changes)
let share_wait_room : @ui.Style = @ui.css("pt=S2")

///|
// kept across runs: a value (no field of it changes)
let share_error_room : @ui.Style = @ui.css("pb=S4")

///|
/// (the sheet's own 20 in is where its words and its rows' marks stand: the web's 20, its PickRows 12 + 8)
// kept across runs: a value (no field of it changes)
let share_narrow : ShareLook = {
  wide: false,
  side: 0.0,
  col: 36.0,
  icon: 20.0,
  gap: 12.0,
  head_pt: 2.0,
  head_pb: 10.0,
  head_mark_h: 36.0,
  head_words_pt: 1.0,
  title_line: 22.0,
  source_line: 17.0,
  label_pt: 6.0,
  label_pb: 2.0,
  list_pb: 16.0,
  row_est: 62.0,
  row_h: 46.0,
  row_padx: 0.0,
  row_pady: 12.0,
  row_corner: 0.0,
  row_line: 21.0,
  row_gap: 0.0,
  model: 36.0,
  inset: @ui.css("w=Full"),
  files_in: 0.0,
  // (in the sheet's top left corner, as far from its top as from its side (the sheet's words' 24, the grabber's room
  // over it a point more), concentric with it there: the ladder's row corner)
  files_top: @sf.panel_words - @sf.sheet_grab_h,
  tile_corner: @sf.row_corner,
}

///|
/// (the panel's own 12 in, then a row's 12 more: a dialog's 24)
// kept across runs: a value (no field of it changes)
let share_wide_look : ShareLook = {
  wide: true,
  side: 12.0,
  col: 20.0,
  icon: 16.0,
  gap: 10.0,
  head_pt: 12.0,
  head_pb: 6.0,
  head_mark_h: 20.0,
  head_words_pt: 0.0,
  title_line: 20.0,
  source_line: 18.0,
  label_pt: 10.0,
  label_pb: 4.0,
  list_pb: 0.0,
  row_est: 56.0,
  row_h: 38.0,
  row_padx: 12.0,
  row_pady: 8.0,
  row_corner: share_row_corner,
  row_line: 20.0,
  row_gap: 2.0,
  model: 18.0,
  inset: @ui.css("w=Full px=S3"),
  // (in the panel's top left corner on its words' line, as far from its top, concentric with it there: the ladder's
  // row corner)
  files_in: @sf.panel_words - 12.0,
  files_top: @sf.panel_words - 12.0,
  tile_corner: @sf.row_corner,
}

///|
/// The sheet, or with a wide window the panel: what is shared, 发到
/// the chats, 新 chat.
fn share_in_sheet(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  share_body(c, src, w, if sheet_small(c) { share_narrow } else { share_wide_look })
}

///|
/// What is shared, 发到 (搜索 from six), the chats it can go to, 新 chat (then the stations, with several), in `look`.
fn share_body(c : @ui.Ctx, src : Source, w : Workspace, look : ShareLook) -> Unit {
  // (one column, its parts as close as they are drawn: not the panel's own gap between them)
  c.box(style=share_whole, fn() { share_parts(c, src, w, look) }) |> ignore
}

///|
fn share_parts(c : @ui.Ctx, src : Source, w : Workspace, look : ShareLook) -> Unit {
  let t = @sf.theme()
  let (source, title) = match share_in.shared.get() {
    Some(s) => s
    None => return
  }
  let query = share_in.query.get()
  let topic = src.topic("shareIn", {
    "scope": Json::string(w.id),
    "source": Json::string(source),
    "query": Json::string(if share_in.searching.get() { query.trim().to_owned() } else { "" }),
  }).get().snapshot()
  let v = topic.value
  let rows = items(v, "items")
  if share_in.files.get().length() > 0 {
    shared_files_head(c, share_in.files.get(), source, title, look)
  } else {
    let site = text(v, "site")
    shared_head(c, source, if title is Some(_) || site == "" { title } else { Some(site) }, look)
  }
  // 发到, and at its end 搜索 (取消 while searching)
  c.box(dir=Row, w=Fill(1.0), padx=look.side, pt=look.label_pt, pb=look.label_pb, align=ACenter, fn() {
    c.box(style=share_whole, fn() { c.text(sh("android-misc.shareIn.to"), size=t.t.meta, color=t.p.muted, wrap=false) |> ignore }) |> ignore
    if share_in.searching.get() || rows.length() >= searched_from {
      let id = c.id("share-in/search")
      c.on_press(id, fn() {
        share_in.searching.set(!share_in.searching.get())
        if !share_in.searching.get() {
          share_in.query.set("")
          share_in.find.set("")
        }
      })
      c.box(id~, fn() {
        c.text(
          if share_in.searching.get() { sh("common.cancel") } else { sh("android-misc.shareIn.search") },
          size=t.t.meta,
          color=if c.lit(id) { t.p.text } else { t.p.muted },
          wrap=false,
        )
        |> ignore
      })
      |> ignore
    }
  })
  |> ignore
  if share_in.searching.get() {
    c.box(style=look.inset.then(share_find_room), fn() {
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
  let searching = share_in.searching.get() && query.trim() != ""
  // the rows, as closures: in the wide panel a list of its own that scrolls, in a sheet one under
  // the other
  let lines : Array[() -> Unit] = []
  match v {
    None =>
      lines.push(fn() {
        c.box(style=look.inset.then(share_wait_room), fn() {
          @sf.wait_line(
            c,
            if topic.error is Some(_) { sh("android-misc.shareIn.update") } else { sh("common.reading") },
            key="share-in",
            error=topic.error is Some(_),
          )
        })
        |> ignore
      })
    Some(_) => {
      match text(v, "note") {
        "" => ()
        n => lines.push(fn() { share_note(c, n, look) })
      }
      let kept = field(v, "kept")
      for item in rows {
        let it = Some(item)
        let station = text(it, "station")
        let id = text(it, "id")
        // (where things of a site went last: files have no site)
        let kept_here = text(kept, "station") == station && text(kept, "id") == id && source.trim() != ""
        let sub = if kept_here { text(kept, "text") } else { text(field(it, "last"), "preview") }
        let agent = items(it, "agents").get(0)
        let ago = text(field(field(it, "time"), "lastActiveAt"), "ago")
        lines.push(fn() {
          share_row(
            c,
            look,
            "share-in/row/" + station + "/" + id,
            text(it, "title"),
            sub,
            if look.wide { ago } else { "" },
            opening == Some((station, id)),
            opening is None,
            fn() {
              match agent {
                Some(a) => {
                  let maker = text(field(Some(a), "maker"), "id")
                  let runtime = text(Some(a), "runtime")
                  if look.wide {
                    @sf.maker_mark(c, maker, runtime, look.model) |> ignore
                  } else {
                    model_mark_big(c, maker, runtime, look.model, "", t.p.bg)
                  }
                }
                // (no agent yet: still.fail's mark wide, the phone's 新建对话 mark)
                None if look.wide => @sf.drawable(c, if t.dark { "stillfail_mark_dark" } else { "stillfail_mark" }, 16.0) |> ignore
                None => @sf.icon(c, "compose", size=look.icon, color=t.p.muted) |> ignore
              }
            },
            on_press=fn() {
              share_open(c, src, w, station, Some(id), session=text(it, "session"))
            },
          )
        })
      }
      if rows.length() == 0 && searching {
        lines.push(fn() { share_note(c, sh("android-chat.ref.none.match"), look) })
      }
      // 新建对话: on the station new chats start on, which its page lets be changed as any new chat's does
      let stations = items(v, "stations")
      let new_on = text(v, "newOn")
      let on = match stations.iter().find_first(fn(s) { text(Some(s), "station") == new_on }) {
        Some(s) => Some(s)
        None => stations.get(0)
      }
      match on {
        Some(s) if !searching => {
          let on_station = text(Some(s), "station")
          lines.push(fn() {
            share_row(
              c,
              look,
              "share-in/new",
              sh("web-main.sidebar.newChat"),
              "",
              "",
              opening == Some((on_station, "")),
              opening is None,
              fn() { @sf.icon(c, "compose", size=look.icon, color=t.p.muted) |> ignore },
              on_press=fn() {
                share_open(c, src, w, on_station, None)
              },
            )
          })
        }
        _ => ()
      }
    }
  }
  if look.wide {
    // (as tall as its rows, the panel's room at most: share_panel's)
    let est = lines.length().to_double() * look.row_est
    c.list("share-in/list", lines.length(), look.row_est, fn(i) { lines[i]() }, h=Px(if est < share_list_most.val { est } else { share_list_most.val })) |> ignore
  } else {
    c.box(style=share_whole, pb=look.list_pb, fn() { for l in lines { l() } }) |> ignore
  }
  if share_in.error.get() != "" {
    c.box(style=look.inset.then(share_error_room), fn() {
      c.text(share_in.error.get(), size=t.t.meta, color=t.p.red) |> ignore
    })
    |> ignore
  }
}

///|
/// What is shared: a mark of what it is (a link, some text), its title (the app's subject, else the
/// link's site) over what it is, two lines of it cut short (three, in the text's ink, when it is all there is).
fn shared_head(c : @ui.Ctx, source : String, head : String?, look : ShareLook) -> Unit {
  let t = @sf.theme()
  let link = source.to_lower().contains("http://") || source.to_lower().contains("https://")
  let alone = head is None
  // (the title said once: what follows it in the words shared under it, a phone's app having put it first)
  let source = match head {
    Some(h) if source.trim().has_prefix(h) && source.trim().length() > h.length() =>
      source.trim().exact_view(start=h.length()).to_owned().trim().to_owned()
    _ => source
  }
  c.box(
    dir=Row,
    w=Fill(1.0),
    pl=look.side,
    pr=look.side,
    pt=look.head_pt,
    pb=look.head_pb,
    gap=look.gap,
    fn() {
      c.box(w=Px(look.col), h=Px(look.head_mark_h), align=ACenter, justify=JCenter, fn() {
        @sf.icon(c, if link { "web" } else { "text" }, size=look.icon, color=t.p.muted) |> ignore
      })
      |> ignore
      c.box(w=Fill(1.0), gap=share_wide_look.row_gap, pt=look.head_words_pt, fn() {
        match head {
          Some(h) =>
            c.box(style=share_cut, fn() {
              c.text(h, size=if look.wide { t.t.ui } else { t.t.body }, weight=600, color=t.p.text, line=look.title_line, wrap=false, allow_ellipsis=true) |> ignore
            })
            |> ignore
          None => ()
        }
        if alone {
          c.box(w=Fill(1.0), pt=if look.wide { 0.0 } else { 7.0 }, fn() {
            c.text(source, size=t.t.ui, color=t.p.text, line=20.0, w=Fill(1.0), max_lines=3) |> ignore
          })
          |> ignore
        } else {
          // (a link one line, cut short: it breaks nowhere)
          c.box(style=share_cut, fn() {
            c.text(source, size=if look.wide { t.t.meta } else { t.t.caption }, color=t.p.muted, line=look.source_line, wrap=false, allow_ellipsis=true) |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    },
  )
  |> ignore
}

///|
/// A line in the rows' place: why there are none, or what to do first.
fn share_note(c : @ui.Ctx, words : String, look : ShareLook) -> Unit {
  let t = @sf.theme()
  c.box(w=Fill(1.0), padx=look.side, pady=8.0, fn() {
    c.text(words, size=if look.wide { t.t.ui } else { t.t.meta }, color=if look.wide { t.p.muted } else { t.p.subtle }) |> ignore
  })
  |> ignore
}

///|
/// A row: on a phone a PickRow (12 from the sheet's sides, 12 by 8 in, its mark a model's tile), in the wide panel ⌘K's
/// (38 high at least, 8 by 12 in, its picture in a 20 column, lit under the pointer, `meta` at its end); its title, a line
/// under it, a spinner while it opens; faint while another opens. True on the frame it was pressed.
fn share_row(
  c : @ui.Ctx,
  look : ShareLook,
  key : String,
  title : String,
  sub : String,
  meta : String,
  busy : Bool,
  enabled : Bool,
  lead : () -> Unit,
  on_press? : () -> Unit,
) -> Unit {
  let t = @sf.theme()
  let id = c.id(key)
  let lit = enabled && c.lit(id)
  c.box(w=Fill(1.0), opacity=if enabled || busy { 1.0 } else { 0.5 }, fn() {
    c.box(
      dir=Row,
      w=Fill(1.0),
      min_h=look.row_h,
      padx=look.row_padx,
      pady=look.row_pady,
      gap=look.gap,
      align=ACenter,
      radius=look.row_corner,
      bg=if look.wide && lit { t.p.hover } else { 0L },
      id=if enabled { id } else { 0 },
      fn() {
        c.box(w=Px(look.col), align=ACenter, justify=JCenter, fn() { lead() }) |> ignore
        c.box(w=Fill(1.0), clip=true, gap=look.row_gap, fn() {
          c.text(title, size=t.t.ui, color=t.p.text, wrap=false, line=look.row_line, allow_ellipsis=true) |> ignore
          if sub != "" {
            c.text(sub, size=t.t.meta, color=t.p.muted, wrap=false, line=18.0, allow_ellipsis=true) |> ignore
          }
        })
        |> ignore
        if busy {
          @sf.spinner(c, size=14.0) |> ignore
        } else if meta != "" {
          c.text(meta, size=t.t.meta, color=t.p.muted, wrap=false) |> ignore
        }
        if enabled && !look.wide {
          @motion.ripple(c, id, @sf.row_corner)
        }
      },
    )
    |> ignore
  })
  |> ignore
  match on_press {
    Some(f) if enabled => c.on_press(id, f)
    _ => ()
  }
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
  _c : @ui.Ctx,
  station : String,
  session : String,
  title : String,
  files : Array[SharedFile],
  pick : () -> Unit,
  key? : String,
) -> Unit {
  let key = match key {
    Some(k) => k
    None => if session == "" { "new:" + @sfbase.workspace_of(station) } else { station + ":" + session }
  }
  if files.length() > 0 {
    let list = shared_into.get(key).unwrap_or([])
    for f in files {
      list.push({ name: f.name, bytes: f.bytes, held: 0, size: f.bytes.length().to_double(), src: "" })
    }
    shared_into[key] = list
    @sfbase.draft_given(key)
  }
  // (what the sheet shows kept as it was while it sinks away, let go of once it has: share_in_frame)
  share_in.raised.set(false)
  share_sinking.val = true
  share_wide.set(false)
  lower_sheet()
  @hostapi.log("share in: into \{key}, \{files.length()} files")
  @sfbase.history_push()
  // over another app: the app opens at the chat (ShareActivity openApp: MainActivity's openItem, over Home); a
  // browser's window the extension shares from has the chat open in the browser's still.fail tab, and goes
  // (web/src/mbui/share.ts)
  if share_over.get() {
    if @ui.platform() == 4 {
      let link = if session == "" { "" } else { chat_link(station, session) }
      @ui.open_url(if link == "" { cloud_origin() } else { link }) |> ignore
      return
    }
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
fn shared_files_head(c : @ui.Ctx, files : Array[SharedFile], words : String, title : String?, look : ShareLook) -> Unit {
  let t = @sf.theme()
  let pictures = files.filter(fn(f) { f.image != "" })
  if pictures.length() > 0 {
    c.box(dir=Row, w=Fill(1.0), pl=look.files_in, pr=look.files_in, mt=look.files_top, pb=8.0, gap=8.0, clip=true, fn() {
      for f in pictures {
        c.box(w=Px(56.0), h=Px(56.0), radius=look.tile_corner, bg=t.p.chip, clip=true, fn() {
          c.image(f.image, w=Px(56.0), h=Px(56.0), radius=look.tile_corner, fit=FitCover, bg=0L) |> ignore
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
  c.box(dir=Row, w=Fill(1.0), pl=look.side, pr=look.side, pt=4.0, pb=2.0, gap=12.0, fn() {
    c.box(w=Px(16.0), pt=3.0, align=ACenter, fn() {
      @sf.icon(c, if pictures.length() == files.length() { "photo" } else { "file" }, size=16.0, color=t.p.muted)
      |> ignore
    })
    |> ignore
    c.box(w=Fill(1.0), fn() {
      c.box(w=Fill(1.0), clip=true, fn() {
        c.text(head, size=t.t.title, weight=700, color=t.p.text, line=24.0, wrap=false, allow_ellipsis=true) |> ignore
      })
      |> ignore
      c.box(w=Fill(1.0), clip=true, fn() {
        c.text(under, size=t.t.meta, color=t.p.muted, wrap=false, allow_ellipsis=true) |> ignore
      })
      |> ignore
      if said != "" {
        c.box(w=Fill(1.0), clip=true, fn() {
          c.text(said, size=t.t.meta, color=t.p.muted, wrap=false, allow_ellipsis=true) |> ignore
        })
        |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// What another app shares, with a wide window (sfdesk's switcher.mbt):
/// a panel over a scrim, 14% down the window, 520 wide at most (32 short of the window), 600 high at most (78% of it),
/// 12 in, its corner from a row's; its rows scroll. Esc, back or a press outside let it go.
fn share_panel(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let shows = @motion.presence(c, "\u{2}share-in", share_wide.get(), initial=true, enter=share_panel_in, exit=share_panel_gone)
  if !share_wide.get() {
    return
  }
  let t = @sf.theme()
  let close = fn() {
    share_wide.set(false)
    c.blur()
  }
  // what is left for its rows: the panel's most, less what is over them (its head, 发到) and its 12 in
  share_list_most.val = dmin2(share_panel_most_h, c.height * share_panel_most_share) - share_panel_rest
  c.with_dismissed(fn(_) { close() }, fn() {
    c.overlay("share-in-layer", modal=true, scrim=t.p.overlay, initial_focus=0, fn() {
      let room = dmin2(share_panel_w, c.width - share_panel_side - share_panel_side)
      let i = c.box(
        style=share_panel_style.then(@ui.style(max_w=Fixed(room))),
        bg=@sf.panel_ground(),
        shadow=@sf.dialog_shadow,
        shadow_y=@sf.dialog_shadow_y,
        shadow_color=t.p.shadow,
        id=c.id("share-in-panel"),
        fn() { share_body(c, src, w, share_wide_look) },
      )
      c.place_by_size(i, fn(pw, _) { ((c.width - pw) / 2.0, c.height * share_panel_top_share) })
      match shows {
        Some(l) => c.look(i, l)
        None => ()
      }
    })
    |> ignore
  })
}

///|
fn dmin2(a : Double, b : Double) -> Double {
  if a < b {
    a
  } else {
    b
  }
}

///|
/// It comes in as ⌘K's: grown out of 97% from its top and faded in; it goes at once.
// kept across runs: a value (no field of it changes)
let share_panel_in : @motion.Trans = @motion.trans(fade=0.0, scale=0.97, oy=0.0, spec=@motion.tween(@kit.pop_ms, ease=Out), ground_first=true)

///|
// kept across runs: a value (no field of it changes)
let share_panel_gone : @motion.Trans = @motion.trans(fade=0.0, spec=@motion.Snap(0.0))

///|
/// The panel (⌘K's switcher): 12 in, its corner from a row's (a pill 38 high 12 in), a small
/// panel's ground and line, 520 wide at most.
// kept across runs: a value (no field of it changes)
let share_panel_style : @ui.Style = share_panel_surface
  .style()
  .then(@ui.style(w=Full, max_w=Fixed(share_panel_w), border=B1, border_color=Line, clip=true))

///|
// kept across runs: a value (no field of it changes)
let share_panel_surface : @sf.Surface = @sf.surface(12.0, share_row_corner)

///|
/// A wide row's corner, and what lies in the panel's corners: concentric 12 in, the panel's own then a pane's (34, one of
/// the ladder's).
let share_row_corner : Double = @ui.concentric(@sf.pane_corner, 12.0)

///|
let share_panel_top_share : Double = 0.14

///|
let share_panel_most_h : Double = 600.0

///|
let share_panel_most_share : Double = 0.78

///|
/// What is left of the window either side of it at least (the web's calc(100vw - 32px)).
let share_panel_side : Double = 16.0

///|
/// What the panel holds over its rows, about: its 12 in at its top and foot, what is shared (two lines), 发到.
let share_panel_rest : Double = 130.0
