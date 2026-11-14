// A file opened beside a chat: a tab of the wide frame's side panel (`view:[…]`, the core's chat-tabs.ts isView), the
// same viewer as over the whole window (viewer.mbt) made for the tab (Viewer's `beside`), one a tab, kept by the chat's
// tabs' key and the tab while the tab is open, let go as it is closed. What it shows is the whole window's: a picture
// fitted, zoomed by the wheel, two fingers or a double press, panned by a finger (the zoom's: @kit.Zoom); a PDF, a page,
// a table, code, words read in the reader, as Viewer::content shows them (an old view hosted in the panel's island);
// a film or a song in the one player embedded in the stage as part of the pane (@sf.player_view's `embedded`: on the
// pane's own ground, its picture or a song's cover fitted in the room over its controls as a tab's picture is, the
// controls always there under it in the pane's colours, laid out by the stage's width; its own player and view, not
// the whole window's, which stays the cinema);
// told of, coming, failed, as the whole window's stage says them (viewer_tree.mbt). Over it a row of tools as tall as a
// service's bar: the file's name and what it is, 预览 / 源码 where the whole window's bar has them, the reader's 目录, 搜索
// and 排版, 下载, 全屏 (the whole window's preview of it, the tab staying; a film or a song there from where the tab's
// was). Nothing of the whole window's is the tab's: no marking, no stepping to the pictures beside it, no flight from a
// thumbnail, no keys of the window's.
//
// How a file comes here: open_preview asked beside (the command key held as it is pressed: beside_held; a menu's
// 在侧边打开; the whole window's 移到侧边), said to the shell (Shell's `beside`), which puts it where the layout has a side
// panel for the page in view, and says whether it did. A film or a song asked so plays at once (the whole window's from
// where it was); a tab only shown again (the app begun, the chat opened, the tab or the panel back) plays from its play
// key. It is paused as its tab is no longer shown (another tab in front, the panel closed, the page gone, no panel on
// 小屏) and as the whole window's viewer opens over it, and never plays again by itself.

///|
/// Whether the command key of the system the person types with is held now (@ui.keys_system: ⌘ on Apple's, Ctrl
/// elsewhere; a browser's the system under it, so ⌘ in one on a Mac, where Ctrl and a press is the context menu): a press
/// with it asks for its file beside the page (open_preview's default). Read here once, never by a page.
pub fn beside_held() -> Bool {
  let primary = match @ui.keys_system() {
    0 | 1 => @ui.mod_cmd
    _ => @ui.mod_ctrl
  }
  (@ui.mods_held() & primary) != 0
}

///|
/// Whether a file at `path` named `name` opens beside the page when that is asked: anything the viewer shows, a film and
/// a song too, but one whose bytes are only in this run's memory (a `draft:` path: the composer's pending attachments, a
/// Mermaid picture, read by keep_read), which opens over the whole window whatever was asked: a tab is kept per chat on
/// the device and made again from its key alone (view_tab_file), where a draft's bytes are gone after a restart.
pub fn opens_beside(path : String, name : String) -> Bool {
  ignore(name)
  !path.has_prefix("draft:")
}

///|
/// Whether a file at `path` named `name` is offered to be opened beside the page (a menu's 在侧边打开, the whole
/// window's 移到侧边): where the shell has a side panel for the page in view (Shell's `beside_room`, followed as it
/// changes: beside_room_now), and it opens there.
pub fn beside_offered(path : String, name : String) -> Bool {
  opens_beside(path, name) && beside_room_now.get()
}

///|
/// The tab of file `a` on `station` (kept by session `key`; a drive's `drive`; one a message names by its path,
/// `named`): which of the three it is, its station, the session (a drive's root), its path, its name and its size as it
/// was opened (a drive's its time too), all a viewer of it is made again by (view_tab_file). The same file, the same
/// tab.
pub fn view_tab_key(station : String, key : String, a : Attachment, drive : DriveFile?, named : Bool) -> String {
  let parts = match drive {
    Some(d) =>
      [
        Json::string("drive"),
        Json::string(d.station),
        Json::string(d.root),
        Json::string(d.path),
        Json::string(d.name),
        Json::number(d.size),
        Json::number(d.mtime),
      ]
    None =>
      [
        Json::string(if named { "named" } else { "chat" }),
        Json::string(station),
        Json::string(key),
        Json::string(a.path),
        Json::string(a.name),
        Json::number(a.size),
      ]
  }
  "view:" + Json::array(parts).stringify()
}

///|
/// Viewer `vw`'s file's tab (view_tab_key).
pub fn Viewer::view_tab(self : Viewer) -> String {
  view_tab_key(self.station, self.key, self.file, self.drive, self.named)
}

///|
/// A file's tab read (view_tab_key's): where it is and what it is.
pub(all) struct ViewTab {
  station : String
  key : String
  file : Attachment
  drive : DriveFile?
  named : Bool
}

///|
/// The file tab `tab` is (None: no file's tab, or one that does not read).
pub fn view_tab_file(tab : String) -> ViewTab? {
  guard tab.has_prefix("view:") else { return None }
  let v = @json.parse(tab.exact_view(start="view:".length()).to_owned()) catch { _ => return None }
  guard v is Array(xs) && xs.length() >= 6 else { return None }
  guard xs[0] is String(of) &&
    xs[1] is String(station) &&
    xs[2] is String(at) &&
    xs[3] is String(path) &&
    xs[4] is String(name) &&
    xs[5] is Number(size, ..) &&
    station != "" &&
    path != "" else {
    return None
  }
  let file : Attachment = {
    name,
    path,
    size,
    width: 0.0,
    height: 0.0,
    thumbhash: "",
    owner: "",
    upload: "",
    duration: 0.0,
    frames: 0,
    held: false,
  }
  match of {
    "chat" | "named" if xs.length() == 6 => Some({ station, key: at, file, drive: None, named: of == "named" })
    "drive" if xs.length() == 7 =>
      match xs[6] {
        Number(mtime, ..) => {
          let d : DriveFile = { station, root: at, path, name, size, mtime, kind: "", mime: preview_kind(name).1 }
          Some({ station, key: "", file: drive_attachment(d), drive: Some(d), named: false })
        }
        _ => None
      }
    _ => None
  }
}

///|
/// Whether two files' tabs are of the same file, whatever its size said (a drive's changed since it was opened): which
/// of the three, its station, its session (a drive's root), its path.
pub fn ViewTab::same_file(self : ViewTab, other : ViewTab) -> Bool {
  self.station == other.station &&
  self.key == other.key &&
  self.file.path == other.file.path &&
  self.named == other.named &&
  self.drive.map(fn(d) { d.root }) == other.drive.map(fn(d) { d.root })
}

///|
/// A tab's viewer, how many nodes draw it, and whether its tab was closed while one did (let go as the last goes).
priv struct TabViewer {
  viewer : Viewer
  mut drawn : Int
  mut closing : Bool
}

///|
/// The viewers of the files open beside chats, by the chat's tabs' key and the tab (tab_viewer_id).
// kept across runs: put back by tab_viewers_reset (file_viewer_reset)
let tab_viewers : Map[String, TabViewer] = Map([])

///|
fn tab_viewer_id(chat : String, tab : String) -> String {
  chat + "\n" + tab
}

///|
/// The viewer of tab `tab` of the chat whose tabs are kept by `chat`: made as it is first shown (of the tab alone: its
/// file read again after a restart), kept while the tab is open. None: no file's tab, or one of a draft's.
pub fn tab_viewer(chat : String, tab : String) -> Viewer? {
  let id = tab_viewer_id(chat, tab)
  match tab_viewers.get(id) {
    Some(t) => Some(t.viewer)
    None =>
      match view_tab_file(tab) {
        Some(f) if opens_beside(f.file.path, f.file.name) => {
          let v = new_viewer(f.station, f.key, f.file, f.drive, NoSteps, named=f.named, beside=true)
          tab_viewers[id] = { viewer: v, drawn: 0, closing: false }
          Some(v)
        }
        _ => None
      }
  }
}

///|
/// Whether tab `tab` of chat `chat` holds a viewer still (what it read, its page, its PDF).
pub fn tab_viewer_held(chat : String, tab : String) -> Bool {
  tab_viewers.contains(tab_viewer_id(chat, tab))
}

///|
/// Tab `tab` of chat `chat` closed (sfdesk's tab_let_go): its viewer let go (what it read, its page, its PDF, its
/// reader's place kept): at once where nothing draws it, else as the last that does goes (the panel showing what it
/// had as it slides out).
pub fn tab_viewer_let_go(chat : String, tab : String) -> Unit {
  let id = tab_viewer_id(chat, tab)
  match tab_viewers.get(id) {
    Some(t) if t.drawn <= 0 => {
      t.viewer.let_go()
      tab_viewers.remove(id)
    }
    Some(t) => t.closing = true
    None => ()
  }
}

///|
/// Tab `tab` of chat `chat` opened again before what drew it went: its viewer kept.
pub fn tab_viewer_kept(chat : String, tab : String) -> Unit {
  match tab_viewers.get(tab_viewer_id(chat, tab)) {
    Some(t) => t.closing = false
    None => ()
  }
}

///|
/// Every tab's viewer let go (the app begun again).
fn tab_viewers_reset() -> Unit {
  tab_viewers.each(fn(_, t) { t.viewer.let_go() })
  tab_viewers.clear()
  tab_asked.clear()
}

///|
/// The files the person asked beside the page just now (a press with the command key held, a menu's 在侧边打开, the
/// whole window's 移到侧边), by their tab: where a film's or a song's player starts there (ms; 0 where it was left),
/// taken by its tab's viewer as the tab's node is made (viewer_tab_node), its player played at once.
// kept across runs: put back by tab_viewers_reset (file_viewer_reset)
let tab_asked : Map[String, Double] = Map([])

///|
/// File tab `tab` asked beside the page in view by the person (Shell's `beside`), a film or a song in it to play at once
/// from `at` (ms; 0 where it was left): whether the shell put it there. The tab the shell put in front may be another
/// of the same file (opened by another key: sfdesk's view_beside), the one asked of then. Its tab drawn in front
/// already (the same file asked again), no node is made for it: its viewer told here.
fn beside_open(tab : String, at : Double) -> Bool {
  // (said before the shell is asked: its tab's node may be made as the shell puts it there)
  tab_asked[tab] = at
  let put = match (shell.val.beside)(tab) {
    Some(put) => put
    None => {
      tab_asked.remove(tab)
      return false
    }
  }
  if put != tab {
    tab_asked.remove(tab)
    tab_asked[put] = at
  }
  tab_viewers.each(fn(id, t) {
    if t.drawn > 0 && id.has_suffix("\n" + put) && tab_asked.contains(put) {
      tab_asked.remove(put)
      t.viewer.play_asked(at)
    }
  })
  true
}

///|
/// A tab's viewer asked beside by the person just now (tab_asked): its film or song played at once, from `at` (ms; 0
/// where it is): its player sent there and played where it is open already, else opened so (Viewer::fetch).
fn Viewer::play_asked(self : Viewer, at : Double) -> Unit {
  self.plays_now = true
  match self.media {
    Some(m) => {
      if at > 0.0 {
        m.seek(at)
      }
      match m.native() {
        Some(n) => n.play()
        None => ()
      }
    }
    None =>
      if at > 0.0 {
        self.start_at = at
      }
  }
}

///|
/// Its film or song paused, where one plays (its tab no longer shown, the whole window's viewer opened over it).
fn Viewer::pause_player(self : Viewer) -> Unit {
  match self.media {
    Some(m) => m.pause()
    None => ()
  }
}

///|
/// What every tab beside a chat plays, paused (the whole window's viewer opened over them: open_preview); `chat`: only
/// those of the chat whose tabs are kept by it (its page shown no more while it is kept under another: sfdesk's
/// side_panel_node).
pub fn tab_players_pause(chat? : String = "") -> Unit {
  tab_viewers.each(fn(id, t) {
    if chat == "" || id.has_prefix(chat + "\n") {
      t.viewer.pause_player()
    }
  })
}

///|
/// 移到侧边 (the whole window's bar): viewer `vw`'s file beside the page, it closed at once (no flight back: it goes to
/// the tab); a film or a song played there from where it was. Where the shell has nowhere to put it, it stays.
pub fn Viewer::move_beside(self : Viewer) -> Unit {
  let at = match self.media {
    Some(m) => m.position()
    None => 0.0
  }
  if beside_open(self.view_tab(), at) {
    close_now()
  }
}

///|
/// 全屏 (a tab's tools): its file over the whole window, as it opens from where it is listed (a picture stepping through
/// `steps`; a film or a song from where the tab's player is, the tab's paused), the tab staying.
pub fn Viewer::full_window(self : Viewer, steps : Stepping) -> Unit {
  let at = match self.media {
    Some(m) => m.position()
    None => -1.0
  }
  open_preview(
    self.station,
    self.key,
    self.file,
    drive=self.drive,
    steps=if self.shown_kind() == Some(KImage) { steps } else { NoSteps },
    named=self.named,
    beside=false,
    start=at,
  )
}

///|
/// The file of tab `tab` beside the chat whose tabs are kept by `chat`, in node `q` (the panel under its bar): its tools
/// (tab_tools_node), then its stage, the rest: a picture its nodes (tab_picture_node), anything else as the whole
/// window's stage shows it, its old views hosted in `island` (the panel's), told of, coming or failed its nodes
/// (viewer_note_node); a film or a song its player embedded (Viewer::player_stage, hosted in `island` too). What it reads
/// asked of the core as what it needs comes; 下载 told the core as it is asked. Made as the person asked the file beside
/// just now (tab_asked), its film or song plays at once; let go (the tab no longer shown), it is paused. `steps`: what
/// its picture steps through over the whole window (全屏).
pub fn viewer_tab_node(
  q : @view.View,
  src : Source,
  chat : String,
  tab : String,
  island : (@view.View, (@ui.Ctx) -> Unit, Bool) -> @view.View,
  steps : () -> Stepping,
) -> Unit {
  guard tab_viewer(chat, tab) is Some(vw) else { return }
  let id = tab_viewer_id(chat, tab)
  match tab_viewers.get(id) {
    Some(t) => t.drawn += 1
    None => ()
  }
  // (asked beside just now: its film or song played at once, before its player is made below)
  match tab_asked.get(tab) {
    Some(at) => {
      tab_asked.remove(tab)
      vw.play_asked(at)
    }
    None => ()
  }
  q.owns(fn() {
    // (its tab no longer shown: what it plays paused, played again only from its play key)
    vw.pause_player()
    match tab_viewers.get(id) {
      Some(t) => {
        t.drawn -= 1
        if t.drawn <= 0 && t.closing {
          t.viewer.let_go()
          tab_viewers.remove(id)
        }
      }
      None => ()
    }
  })
  |> ignore
  // what it reads asked of the core as what it needs comes (its kind sniffed, its bytes, a read failed, 下载 asked)
  q.reacts(fn() { (vw.sniffed.get(), vw.bytes.get() is Some(_), vw.error.get() is Some(_), vw.fetching.get(), vw.asked_told.get()) }, fn(_) {
    vw.fetch(src)
  })
  // 下载 asked: a chat's file's download said to the core at that change; what was asked before it was here saved, or
  // installed, as its whole comes; each once
  q.reacts(fn() { (vw.asked_told.get(), vw.bytes.get() is Some(_)) }, fn(_) {
    download_told(src, vw)
    if vw.bytes.untracked() is Some(_) {
      if vw.save_after {
        vw.save_after = false
        vw.save_now()
      }
      if vw.install_after {
        vw.install_after = false
        vw.ask_install()
      }
      vw.share_came()
    }
  })
  let tips_at : Ref[@view.View?] = Ref(None)
  let tips = @sf.TipLayer::new(fn() { tips_at.val })
  q.box(fn(row) { tab_tools_node(row, src, vw, fn() { vw.full_window(steps()) }, tips) }) |> ignore
  q.box(fn(s) {
    s
    .grow(Is(1.0))
    .shrink(Is(1.0))
    .basis(Is(Some(0.0)))
    .min_height(Is(Some(0.0)))
    .clips(Is(true))
    |> ignore
    // a film or a song: the one player embedded, hosted in the panel's island (no keys, nothing of the window's)
    let played = vw.played()
    if played {
      s.box(fn(h) {
        h.over(Is(true)) |> ignore
        island(
          h,
          fn(c) {
            src_now.val = src.now
            let stage = c.id("preview/beside-player")
            c.cursor(stage, Arrow)
            c.box(style=stage_whole, id=stage, fn() { vw.player_stage(c, src, stage) }) |> ignore
          },
          false,
        )
        .over(Is(true))
        |> ignore
      })
      |> ignore
    }
    let picture = fn() { vw.markable() }
    s.show(picture, fn(p) { tab_picture_node(p, src, vw) })
    let stage = fn() { vw.outer_stage() }
    // (what the old views show of it: hosted in the panel's island, its words picked as a page's are)
    s.show(fn() { !played && !picture() && stage() == Hosted }, fn(h) {
      h.over(Is(true)) |> ignore
      island(
        h,
        fn(c) {
          src_now.val = src.now
          let stage = c.id("preview/beside-stage")
          c.cursor(stage, Arrow)
          @ui.capture(c, stage, zooms=true)
          c.selectable(color=@sf.alpha(@sf.theme().p.blue, 0.28), fn() {
            c.box(style=stage_whole, id=stage, fn() { vw.content(c, src, stage) }) |> ignore
          })
        },
        false,
      )
      .over(Is(true))
      |> ignore
    })
    s.show(fn() { !played && !picture() && stage() != Hosted }, fn(note) {
      viewer_note_node(note, src, vw, stage, bars=false)
    })
    // the reader's 排版 while its reading has it open: docked at the stage's right from its top, no wider than it (the
    // tab's own, going with it as another tab comes to the front and there again as it comes back)
    s.show(fn() { @sf.reader_panel_of(vw.read_key()) == @sf.ReaderPanel::Layout }, fn(l) {
      l.over(Is(true)) |> ignore
      @sf.reader_layout_docked(l, fn() { @sf.reader_panel_toggle(vw.read_key(), @sf.ReaderPanel::Layout) }, fits=true)
    })
  })
  |> ignore
  // (its tips over all of it)
  tips_at.val = Some(q.box(fn(l) { l.over(Is(true)) |> ignore }))
}

///|
/// The tools over a file's tab in `row` (as tall as a service's bar, PreviewBar's): its name and the line about it (its
/// size, its kind), cut short where the tab is narrow; then 预览 / 源码 (a table's, a page's, once read: as the whole
/// window's bar has them), the reader's 目录, 搜索 and 排版 (Markdown and words read in it: its panels opened from here,
/// the layout's in the tab's stage, viewer_tab_node's), 下载 (a ring while the core downloads it), 全屏 (`full`). Each
/// done at its press's moment; their tips in `tips`.
fn tab_tools_node(
  row : @view.View,
  src : Source,
  vw : Viewer,
  full : () -> Unit,
  tips : @sf.TipLayer,
) -> Unit {
  row
  .row(Is(true))
  .lines_up(Is(Some(Middle)))
  .gap(Is(@ui.Space::px(S2)))
  .min_height(Is(Some(@ui.room_least())))
  .padding(Is((@ui.Space::px(S3), @ui.Space::px(S1_5), @ui.Space::px(S2), @ui.Space::px(S1_5))))
  .shrink(Is(0.0))
  .says(Is(Some(@view.said(Toolbar, label=vw.file.name))))
  |> ignore
  let ink = fn() { @sf.page_viewer_ink() }
  let corner : @view.Live[Double] = Is(@sf.tool_side / 2.0)
  // its name and the line about it, giving way to the tools
  row.box(fn(f) {
    f.grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0))).clips(Is(true)) |> ignore
    f.box(fn(n) {
      n
      .words(By(fn() { vw.file.name }))
      .words_look(By(fn() { tab_words(Ui, L5, 600) }))
      .ink(By(fn() { ink().ink }))
      .says(By(fn() { Some(@view.said(Text, label=vw.file.name)) }))
      |> ignore
    })
    |> ignore
    f.show(fn() { vf_meta(vw, src) != "" }, fn(l) {
      l
      .words(By(fn() { vf_meta(vw, src) }))
      .words_look(By(fn() { tab_words(Caption, L4, 400) }))
      .ink(By(fn() { ink().muted }))
      .says(By(fn() { Some(@view.said(Text, label=vf_meta(vw, src))) }))
      |> ignore
    })
  })
  |> ignore
  row.box(fn(r) {
    r.row(Is(true)).lines_up(Is(Some(Middle))).gap(Is(@sf.keys_apart())).shrink(Is(0.0)) |> ignore
    // 预览 / 源码: a table's, a page's, once read (the library's segmented choice, what it chooses told:
    // Viewer::set_source)
    r.show(fn() { vw.bytes.get() is Some(_) && (vw.shown_kind() == Some(KCsv) || vw.shown_kind() == Some(KHtml)) }, fn(x) {
      x.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
      @sf.seg_node(
        x,
        fn() { [@sf.t("web-main.preview.rendered"), @sf.t("web-main.preview.source")] },
        fn() {
          vw.source_told.get() |> ignore
          if vw.source {
            1
          } else {
            0
          }
        },
        fn(k) { vw.set_source(k == 1) },
        item_w=vf_tabs_item,
      )
      |> ignore
    })
    // the reader's panels, opened from here (the layout's in the tab's stage)
    r.show(fn() { vf_reads(vw) }, fn(x) {
      x.row(Is(true)).lines_up(Is(Some(Middle))).gap(Is(@sf.keys_apart())) |> ignore
      let panels = [
        (@sf.ReaderPanel::Contents, "list", @sf.t("web-pages.drive.reader.contents")),
        (@sf.ReaderPanel::Find, "search", @sf.t("web-pages.drive.reader.find")),
        (@sf.ReaderPanel::Layout, "text", @sf.t("web-pages.drive.reader.layout")),
      ]
      for p in panels {
        let (panel, icon, label) = p
        @sf.tool_node(
          x,
          fn() { { icon, label, on: @sf.reader_panel_of(vw.read_key()) == panel, disabled: false } },
          ink,
          corner,
          fn() { @sf.reader_panel_toggle(vw.read_key(), panel) },
          tip=tips,
        )
        |> ignore
      }
    })
    // 下载: what is here saved at once; one told of, read whole first; a ring while the core downloads it
    let dl = fn() { vw.download(src) }
    r.show(fn() { !vw.coming() && !downloading(dl()) }, fn(x) {
      @sf.tool_node(
        x,
        fn() {
          // (a film or a song played as it comes: read whole as it is asked)
          let saving = vw.bytes.get() is Some(_) || ((vw.told_of() || vw.played()) && !vw.asked_now())
          { icon: "download", label: @sf.t("web-main.preview.download"), on: false, disabled: !saving }
        },
        ink,
        corner,
        fn() { vw.save_now() },
        tip=tips,
      )
      |> ignore
    })
    r.show(fn() { !vw.coming() && downloading(dl()) }, fn(x) {
      @sf.tool_ring_node(x, fn() { number(dl(), "progress") }, fn() { @sf.t("web-main.preview.download") }, ink, corner)
      |> ignore
    })
    // 全屏: over the whole window, the tab staying
    @sf.tool_node(
      r,
      fn() { { icon: "expand", label: @sf.t("web-main.preview.fullWindow"), on: false, disabled: false } },
      ink,
      corner,
      full,
      tip=tips,
    )
    |> ignore
  })
  |> ignore
}

///|
/// How far a tab's picture is fitted clear of its stage's edges (the whole window's on a stage under 640, @kit.Zoom's),
/// and its room to be taken by the hand in from them.
let tab_picture_margin : Double = 12.0

///|
/// Words of the tools' row: the theme's `size`, `line` a line, `weight`, on one line.
fn tab_words(size : @ui.TextSize, line : @ui.Leading, weight : Int) -> @view.WordsLook {
  let th = @ui.tree_theme()
  let (px, own) = th.text_size(size)
  { size: px, weight, line: th.leading(line).unwrap_or(own), wrap: false, tracking: @view.letters_own, balance: false, max_lines: 0 }
}

///|
/// A tab's picture in `s` (its stage, all of it): fitted as the whole window's is (tab_picture_margin clear of the
/// stage's edges, never larger than its own size: its zoom's, new_viewer), laid out so in the stage less that margin
/// and drawn as its zoom has it as the frame is drawn, grown about its middle and moved as far from it as the zoom
/// says; the wheel zooms it (with ⌘ or ⌃, a trackpad's pinch) or pans it zoomed, two fingers pinch it, one pans it
/// zoomed, a double press zooms in and back, each at its event's moment, the zoom told the stage's size and the
/// picture's then. What takes the hand is the stage less the margin, clear of what lies at its edges (the side panel's
/// edge). While it comes with nothing to stand in for it, how much has; not read, or no picture in it, why.
fn tab_picture_node(s : @view.View, src : Source, vw : Viewer) -> Unit {
  s.over(Is(true)) |> ignore
  let z = vw.zoom
  let m = tab_picture_margin
  // (the zoom's terms are the stage's: what the hand's room says, the margin round it put back)
  let tell = fn(w : Double, h : Double, at : Double) {
    z.boxed(w + 2.0 * m, h + 2.0 * m, at~)
    let (nw, nh) = vw.natural_size(src)
    z.natural(nw, nh, at~)
  }
  // how much larger than fitted it is drawn, and how far its middle is from the stage's, as node `n` is drawn: where
  // the zoom has it (as each frame draws it while it glides or flings, else as it was told)
  let placed = fn(n : @view.View) -> (Double, Double, Double) {
    z.told()
    let t = n.drawn_while(fn(at) { z.goes_at(at) })
    let fitted = z.nw * z.fit()
    match z.rect_at(t) {
      Some((x, y, w, h)) if fitted > 0.0 => (w / fitted, x + w / 2.0 - z.bw / 2.0, y + h / 2.0 - z.bh / 2.0)
      _ => (1.0, 0.0, 0.0)
    }
  }
  // two fingers' last middle and how far apart they were (0: one finger), one finger's last place
  let fingers : Map[Int, (Double, Double)] = Map([])
  let pinch : Ref[(Double, Double, Double)] = Ref((0.0, 0.0, 0.0))
  let last : Ref[(Double, Double)] = Ref((0.0, 0.0))
  let moved : Ref[Double] = Ref(0.0)
  let apart = fn() {
    let at = fingers.values().to_array()
    if at.length() < 2 {
      (0.0, 0.0, 0.0)
    } else {
      let (ax, ay) = at[0]
      let (bx, by) = at[1]
      ((ax + bx) / 2.0, (ay + by) / 2.0, ((ax - bx) * (ax - bx) + (ay - by) * (ay - by)).sqrt())
    }
  }
  s.box(fn(room) {
    room.over(Is(true)).padding(Is((m, m, m, m))) |> ignore
    room.box(fn(area) {
      area
      .grow(Is(1.0))
      .basis(Is(Some(0.0)))
      .min_height(Is(Some(0.0)))
      .lines_up(Is(Some(Middle)))
      .lies_along(Is(Middle))
      .says(By(fn() { Some(@view.said(Image, label=vw.file.name)) }))
      .on_drag(
        fn(d) {
          tell(d.w, d.h, d.at)
          // (the stage's own terms for a point of the window's, as it is drawn then)
          let (ox, oy) = (d.x - d.wx + m, d.y - d.wy + m)
          match d.kind {
            Down => {
              fingers[d.finger] = (d.wx, d.wy)
              if fingers.length() == 1 {
                z.stop_fling(at=d.at) |> ignore
                last.val = (d.wx, d.wy)
                moved.val = 0.0
              } else {
                pinch.val = apart()
              }
            }
            Moved => {
              fingers[d.finger] = (d.wx, d.wy)
              if fingers.length() >= 2 {
                let (cx, cy, dist) = apart()
                let (px, py, was) = pinch.val
                if was > 0.0 && dist > 0.0 {
                  z.transform(cx + ox, cy + oy, dist / was, cx - px, cy - py, at=d.at)
                }
                pinch.val = (cx, cy, dist)
              } else {
                let (lx, ly) = last.val
                moved.val = moved.val + (d.wx - lx).abs() + (d.wy - ly).abs()
                if z.zoomed_at(d.at) {
                  z.pan(d.wx - lx, d.wy - ly, at=d.at)
                }
                last.val = (d.wx, d.wy)
              }
            }
            Up | Off => {
              let alone = fingers.length() == 1
              fingers.remove(d.finger)
              if fingers.length() == 1 {
                // (one of two let go: the one left followed from where it is next)
                pinch.val = (0.0, 0.0, 0.0)
                last.val = fingers.values().to_array()[0]
              }
              // a press let go where it went down, the second of two: in to 2.5 times fitted round it, or back
              if d.kind == Up && alone && moved.val <= tap_slop && area.twice(d) {
                z.double_tap(d.x + m, d.y + m, at=d.at)
              }
            }
          }
        },
        fingers=2,
        whole=true,
      )
      .on_wheel(fn(w) {
        tell(w.w, w.h, w.at)
        vw.wheeled(z, w.x + m, w.y + m, w.dx, w.dy, w.mods, w.at)
      })
      |> ignore
      // fitted: as wide as it is at most and no wider than its room, as tall for as wide, no taller than its room, in
      // its middle (contained in that box: as large as the zoom's fitted scale has it)
      area.box(fn(p) {
        p
        .width(By(fn() {
          let (nw, _) = vw.natural_size(src)
          if nw > 0.0 {
            Some(nw)
          } else {
            None
          }
        }))
        .max_width(Is(None), within=true)
        .aspect(By(fn() {
          let (nw, nh) = vw.natural_size(src)
          if nw > 0.0 && nh > 0.0 {
            nw / nh
          } else {
            0.0
          }
        }))
        .shrink(Is(1.0))
        .min_height(Is(Some(0.0)))
        .image(By(fn() { if vw.picture_failed() { None } else { vw.picture_shown(src) } }))
        .image_contains(Is(true))
        .scale(By(fn() { placed(p).0 }))
        .offset(By(fn() {
          let (_, x, y) = placed(p)
          (x, y)
        }))
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
  // (coming with nothing to stand in for it: how much has; its read failed, or no picture in it: why)
  s.show(fn() { vw.coming() && vw.stand_in(src) == "" }, fn(f) {
    f.over(Is(true)).lines_up(Is(Some(Middle))).padding(Is((24.0, 24.0, 24.0, 24.0))) |> ignore
    f.box(fn(g) { g.grow(Is(1.0)) |> ignore }) |> ignore
    f.box(fn(c) { viewer_coming_node(c, vw) }) |> ignore
    f.box(fn(g) { g.grow(Is(1.0)) |> ignore }) |> ignore
  })
  s.show(fn() { vw.picture_failed() || vw.error.get() is Some(_) }, fn(f) {
    f.over(Is(true)).padding(Is((24.0, 24.0, 24.0, 24.0))).lines_up(Is(Some(Middle))) |> ignore
    f.box(fn(g) { g.grow(Is(1.0)) |> ignore }) |> ignore
    f.box(fn(w) {
      w
      .words(By(fn() {
        match vw.error.get() {
          Some(e) => pv_fill("android-chat.file.loadFailed", [("error", e)])
          None => pv("android-chat.file.image.failed")
        }
      }))
      .words_look(By(fn() {
        let size = @sf.theme().t.body
        { size, weight: 400, line: @ui.tree_theme().text_line * size, wrap: true, tracking: @view.letters_own, balance: false, max_lines: 0 }
      }))
      .ink(By(fn() { @sf.theme().p.muted }))
      |> ignore
    })
    |> ignore
    f.box(fn(g) { g.grow(Is(1.0)) |> ignore }) |> ignore
  })
}
