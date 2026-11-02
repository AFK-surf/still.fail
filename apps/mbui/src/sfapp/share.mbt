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
      shared_head(c, source, title, share_narrow)
    }
  }
  match accounts.value {
    Some(Array(list)) if list.length() == 0 => {
      head()
      share_note(c, sh("android-misc.shareIn.signIn"), share_narrow)
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
/// How the body is laid out: a phone's sheet (the web's mobile/ShareIn.tsx, its PickRows) or the wide frame's panel
/// (the web's ShareIn.tsx, ⌘K's: Switcher.css.ts, ShareIn.css.ts).
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
  /// under the list, and between its rows
  list_pb : Double
  list_gap : Double
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
}

///|
// kept across runs: a value (no field of it changes)
let share_whole : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let share_cut : @ui.Style = @ui.css("w=Full clip")

///|
/// 找 chat under 发到; 正在读取 where the rows will be; 新 chat 开在 (as 发到 is on the wide panel); what went wrong.
// kept across runs: a value (no field of it changes)
let share_find_room : @ui.Style = @ui.css("pt=S1_5 pb=S1")

///|
// kept across runs: a value (no field of it changes)
let share_wait_room : @ui.Style = @ui.css("pt=S2")

///|
// kept across runs: a value (no field of it changes)
let share_label_room : @ui.Style = @ui.css("pt=S2_5 pb=S1")

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
  list_gap: 0.0,
  row_h: 46.0,
  row_padx: 0.0,
  row_pady: 12.0,
  row_corner: 0.0,
  row_line: 21.0,
  row_gap: 0.0,
  model: 36.0,
  inset: @ui.css("w=Full"),
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
  list_gap: 2.0,
  row_h: 38.0,
  row_padx: 12.0,
  row_pady: 8.0,
  row_corner: @sf.pill_inner(12.0, 38.0),
  row_line: 20.0,
  row_gap: 2.0,
  model: 18.0,
  inset: @ui.css("w=Full px=S3"),
}

///|
/// The sheet (mobile/ShareIn.tsx Sheet), or with a wide window the panel (ShareIn.tsx ShareInPanel): what is shared, 发到
/// the chats, 新 chat.
fn share_in_sheet(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let (ww, _) = c.window_size()
  share_body(c, src, w, if @sf.layout(ww) is Small { share_narrow } else { share_wide_look })
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
  let topic = (src.topic)("shareIn", {
    "scope": Json::string(w.id),
    "source": Json::string(source),
    "query": Json::string(if share_in.searching.get() { query.trim().to_owned() } else { "" }),
  })
  let v = topic.value
  let rows = items(v, "items")
  if share_in.files.get().length() > 0 {
    shared_files_head(c, share_in.files.get(), source, title)
  } else {
    let site = text(v, "site")
    shared_head(c, source, if title is Some(_) || site == "" { title } else { Some(site) }, look)
  }
  // 发到, and at its end 搜索 (取消 while searching)
  c.box(dir=Row, w=Fill(1.0), padx=look.side, pt=look.label_pt, pb=look.label_pb, align=ACenter, fn() {
    c.box(style=share_whole, fn() { c.text(sh("android-misc.shareIn.to"), size=t.t.meta, color=t.p.muted, wrap=false) |> ignore }) |> ignore
    if share_in.searching.get() || rows.length() >= searched_from {
      let id = c.id("share-in/search")
      if c.clicked(id) {
        share_in.searching.set(!share_in.searching.get())
        if !share_in.searching.get() {
          share_in.query.set("")
          share_in.find.set("")
        }
      }
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
  c.box(w=Fill(1.0), pb=look.list_pb, gap=look.list_gap, fn() {
    match v {
      None =>
        c.box(style=look.inset.then(share_wait_room), fn() {
          @sf.wait_line(
            c,
            if topic.error is Some(_) { sh("android-misc.shareIn.update") } else { sh("common.reading") },
            key="share-in",
            error=topic.error is Some(_),
          )
        })
        |> ignore
      Some(_) => {
        match text(v, "note") {
          "" => ()
          n => share_note(c, n, look)
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
          if share_row(
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
                  // (no agent yet: still.fail's mark wide, the phone's 新 chat mark)
                  None if look.wide => @sf.drawable(c, if t.dark { "stillfail_mark_dark" } else { "stillfail_mark" }, 16.0) |> ignore
                  None => @sf.icon(c, "compose", size=look.icon, color=t.p.muted) |> ignore
                }
              },
            ) {
            share_open(c, src, w, station, Some(id), session=text(it, "session"))
          }
        }
        if rows.length() == 0 && searching {
          share_note(c, sh("android-chat.ref.none.match"), look)
        }
        let stations = items(v, "stations")
        let new_on = text(v, "newOn")
        let on = match stations.iter().find_first(fn(s) { text(Some(s), "station") == new_on }) {
          Some(s) => Some(s)
          None => stations.get(0)
        }
        match on {
          Some(s) if !searching => {
            let on_station = text(Some(s), "station")
            if share_row(
                c,
                look,
                "share-in/new",
                sh("android-misc.shareIn.newChat"),
                "",
                "",
                opening == Some((on_station, "")),
                opening is None,
                fn() { @sf.icon(c, "compose", size=look.icon, color=t.p.muted) |> ignore },
              ) {
              share_open(c, src, w, on_station, None)
            }
            // with several stations, each to start one on (新 chat 开在)
            if stations.length() > 1 {
              c.box(style=look.inset.then(share_label_room), fn() {
                c.text(sh("web-main.shareIn.startOn"), size=t.t.meta, color=t.p.muted, wrap=false) |> ignore
              })
              |> ignore
              for st in stations {
                let station = text(Some(st), "station")
                if share_row(
                    c,
                    look,
                    "share-in/on/" + station,
                    text(Some(st), "name"),
                    "",
                    "",
                    opening == Some((station, "")),
                    opening is None,
                    fn() { @sf.icon(c, "server", size=look.icon, color=t.p.muted) |> ignore },
                  ) {
                  share_open(c, src, w, station, None)
                }
              }
            }
          }
          _ => ()
        }
      }
    }
  })
  |> ignore
  if share_in.error.get() != "" {
    c.box(style=look.inset.then(share_error_room), fn() {
      c.text(share_in.error.get(), size=t.t.meta, color=t.p.red) |> ignore
    })
    |> ignore
  }
}

///|
/// What is shared (ShareIn.tsx What): a mark of what it is (a link, some text), its title (the app's subject, else the
/// link's site) over what it is, two lines of it cut short (three, in the text's ink, when it is all there is).
fn shared_head(c : @ui.Ctx, source : String, head : String?, look : ShareLook) -> Unit {
  let t = @sf.theme()
  let link = source.to_lower().contains("http://") || source.to_lower().contains("https://")
  let alone = head is None
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
          c.text(source, size=if look.wide { t.t.meta } else { t.t.caption }, color=t.p.muted, line=look.source_line, w=Fill(1.0), max_lines=2) |> ignore
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
) -> Bool {
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

