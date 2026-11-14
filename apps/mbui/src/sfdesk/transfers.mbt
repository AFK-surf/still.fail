// What comes to this device and goes between its stations (still.fail web/src/pages/Transfers.tsx, Files.css.ts
// transfers): the copies between folders and stations, the files downloaded to this device (a chat's, a drive's) and
// those opened and let go being brought after everything else (client/core-ts fill.ts). On the files' bar its 传输,
// and in the chats' sidebar's foot (how many go, how far); its list (each copy's way, how it stands, stopped, tried
// again, its folder shown once done; each download, how far, stopped, tried again; each file being brought, how far
// and how it stands, stopped).

///|
/// Whether the bar's 传输 has its list open, and the list as presented (@sf.last_presented; 0 none).
priv struct Transfers {
  open : @signals.Signal[Bool]
  mut shown : Int
}

///|
// kept across runs: the list's state (transfers_reset puts it back)
let ftransfers : Transfers = { open: @signals.signal(false, same=fn(a, b) { a == b }), shown: 0 }

///|
fn transfers_reset() -> Unit {
  ftransfers.open.set(false)
  ftransfers.shown = 0
}

///|
/// The bar's 传输 with its list open (a page shown at that moment: the fixture's).
pub fn transfers_open() -> Unit {
  ftransfers.open.set(true)
}

///|
/// The person's transfers into the workspace's stations (the `driveTransfers` topic), newest first.
fn transfer_list(src : Source, ws : String) -> Array[Json] {
  items(src.topic("driveTransfers", { "workspace": Json::string(ws) }).get().value, "transfers")
}

///|
/// What comes and goes for the workspace: its copies (the `driveTransfers` topic), this device's downloads from its
/// stations (a chat's file, a drive's, a folder zipped: the `downloads` topic) and what was opened and let go being
/// brought after everything else (its `keeping`: client/core-ts fill.ts).
priv struct Coming {
  transfers : Array[Json]
  downloads : Array[Json]
  keeping : Array[Json]
}

///|
fn coming(src : Source, ws : String) -> Coming {
  let (downloads, keeping) = coming_of(src, ws)
  { transfers: transfer_list(src, ws), downloads, keeping }
}

///|
/// Whether there is none of it.
fn Coming::none(self : Coming) -> Bool {
  self.transfers.length() == 0 && self.downloads.length() == 0 && self.keeping.length() == 0
}

///|
/// How many go (copies and downloads under way, the files being brought), how far they are in all (a percent), and
/// whether one failed.
fn Coming::going(self : Coming) -> (Int, Int, Bool) {
  let going = self.transfers.filter(fn(x) { flag(Some(x), "active") })
  let coming = self.downloads.filter(fn(d) { flag(Some(d), "active") })
  let failed = self.transfers.iter().any(fn(x) { text(Some(x), "state") == "failed" }) ||
    self.downloads.iter().any(fn(d) { text(Some(d), "state") == "failed" })
  let sizes = fn(a : Array[Json], field : String) { a.fold(init=0.0, fn(n, x) { n + number(Some(x), field) }) }
  let total = sizes(going, "total") + sizes(coming, "size") + sizes(self.keeping, "size")
  let copied = sizes(going, "copied") + sizes(coming, "loaded") + sizes(self.keeping, "loaded")
  let percent = if total > 0.0 { (copied / total * 100.0).floor().to_int() } else { 0 }
  (going.length() + coming.length() + self.keeping.length(), percent, failed)
}

///|
/// What their chip says: how many go and how far, else 传输.
fn coming_words(n : Int, percent : Int) -> String {
  if n > 0 {
    @sf.t("web-pages.files.transfersGoing", args=[("n", n.to_string()), ("percent", percent.to_string())])
  } else {
    @sf.t("web-pages.files.transfers")
  }
}

///|
/// Their list, while `ftransfers.open.get()`: the library's panel from `from` (beside it, or a sheet from the foot on a
/// small screen), what is being brought first, then the downloads, then the copies (nodes of the window's tree made once
/// as it opens, each row made as the core lists it, bound to what it says: transfers_body); closed once there is none. `go`: where a copy's folder is shown. `side`, `along`: where it stands beside `id` (the
/// rail's key: beside the rail, `rail_menu_off` out, its foot level with the key's, as the workspaces' menu under it is;
/// under it, it lay over the rail, the mark of the workspace in view showing at its edge).
fn transfers_list(
  src : Source,
  ws : String,
  from : @sf.Anchor,
  go : (DriveAt) -> Unit,
  none : Bool,
  side? : @ui.Side = Bottom,
  along? : @ui.Along = Start,
) -> Unit {
  if none {
    ftransfers.open.set(false)
  }
  if ftransfers.open.get() && ftransfers.shown == 0 {
    @sf.panel_nodes(
      @sf.t("web-pages.files.transfers"),
      fn(v, _) { transfers_body(v, src, ws, go) },
      from~,
      w=ftransfers_w,
      side~,
      along~,
      offset=if side is Right { rail_menu_off } else { @sf.panel_offset },
      gone=fn() {
        ftransfers.open.set(false)
        ftransfers.shown = 0
      },
    )
    ftransfers.shown = @sf.last_presented()
  } else if !ftransfers.open.get() && ftransfers.shown > 0 {
    @sf.close_presented_of(ftransfers.shown)
    ftransfers.shown = 0
  }
}

///|
/// Their list from the rail's key of them (rail_transfers_node), drawn over the frame (rail_overlays): beside the key
/// where it was as the list was opened from it (else where it is now), its foot level with the key's, as the
/// workspaces' menu under it is.
fn rail_transfers_list(src : Source, w : Workspace) -> Unit {
  let all = coming(src, w.id)
  let from : @sf.Anchor = match (transfers_from.val, rail_transfers_key.val) {
    (Some((x, y, aw, ah)), _) => At(x, y, aw, ah)
    (None, Some(v)) if v.alive() => {
      let (x, y, aw, ah) = v.placed_window_now()
      At(x, y, aw, ah)
    }
    _ => Unanchored
  }
  transfers_list(src, w.id, from, fn(at) { open_page(Drive(at)) }, all.none(), side=Right, along=End)
}

///|
/// In a small screen's home's top bar: what comes to this device and goes between the stations, as one key
/// (@sf.progress_key: the download's mark, a ring as far as what comes has come, red's dot when one failed); pressed,
/// their list (from the foot). Nothing while there is none. (A newer build of the app is not among it: the host
/// brings it by itself, sfbase updates.mbt.)
pub fn transfers_key(c : @ui.Ctx, src : Source, ws : String, side : Double, mark : Double) -> Unit {
  let all = coming(src, ws)
  let id = c.id("home/transfers")
  let go = fn(at : DriveAt) { open_page(Drive(at)) }
  if all.none() {
    transfers_list(src, ws, Of(id), go, true)
    return
  }
  let (n, percent, failed) = all.going()
  let ring = if n > 0 { Some(percent.to_double() / 100.0) } else { None }
  let label = if n > 0 { coming_words(n, percent) } else { @sf.t("web-pages.files.transfers") }
  @sf.progress_key(c, "home/transfers", side, mark, "download", label, ring, failed~, on_press=fn() {
    ftransfers.open.set(!ftransfers.open.get())
  })
  transfers_list(src, ws, Of(id), go, false)
}

///|
/// The list open over the sidebar's foot (a fixture's: MBUI_FIXTURE=home-transfers).
pub fn open_transfers() -> Unit {
  ftransfers.open.set(true)
}

///|
/// The list's rows in node `v` (its panel's body's), made once as it opens: what is being brought, then the downloads,
/// then the copies, each a row by its station and id made as the core lists it and let go as it lists it no more,
/// what it says bound to what the core says of it. `go`: where a copy's folder is shown.
fn transfers_body(v : @view.View, src : Source, ws : String, go : (DriveAt) -> Unit) -> Unit {
  // (none left: the list closes (transfers_list), what it showed last kept as it goes, not closed row by row under it)
  let last : Ref[Coming?] = Ref(None)
  let all = fn() {
    let now = coming(src, ws)
    match (now.none(), last.val) {
      (true, Some(was)) => was
      _ => {
        last.val = Some(now)
        now
      }
    }
  }
  let id = fn(j : Json) { text(Some(j), "station") + "|" + text(Some(j), "id") }
  // (each row in a box of no padding of its own: what comes and goes down a column closes its way to none of what it
  // holds, its padding not (flex's come_*), so a row's 8 over and under would be let go at once at its way's end)
  let rowed = fn(row : @view.View, made : (@view.View) -> Unit) { row.box(made) |> ignore }
  v.each(fn() { all().keeping }, id, fn(row, k) { rowed(row, fn(r) { keeping_row(r, src, k) }) })
  v.each(fn() { all().downloads }, id, fn(row, d) { rowed(row, fn(r) { download_row(r, src, d) }) })
  v.each(fn() { all().transfers }, id, fn(row, x) { rowed(row, fn(r) { transfer_row(r, src, x, go) }) })
}

///|
/// Node `row` as a row of the list (ftransfer_row): its mark, its words and its keys, each made by what is given in a
/// box of its own.
fn transfer_row_of(
  row : @view.View,
  mark : (@view.View) -> Unit,
  words : (@view.View) -> Unit,
  keys : (@view.View) -> Unit,
) -> Unit {
  @sf.style_node(row, fn() { ftransfer_row })
  row.box(fn(m) {
    @sf.style_node(m, fn() { ftransfer_mark }, in_row=true)
    mark(m)
  })
  |> ignore
  row.box(fn(w) {
    @sf.style_node(w, fn() { ftransfer_text }, in_row=true)
    words(w)
  })
  |> ignore
  row.box(fn(k) {
    @sf.style_node(k, fn() { ftransfer_actions }, in_row=true)
    keys(k)
  })
  |> ignore
}

///|
/// Words of a row in `parent`, `words` in `style` as they change, cut short with an ellipsis on their line where it has
/// not the room (as the old row's were, allow_ellipsis): given way along a row, never squeezed down (View::cuts).
fn transfer_words(parent : @view.View, words : () -> String, style : () -> @ui.TextStyle) -> Unit {
  @sf.words_node(parent, words, style).cuts(Is(true))
  .min_width(Is(Some(0.0)))
  // (each, as an old view's words were measured, no wider than its line: two long ones beside each other given way alike)
  .max_width(Is(Some(1.0e9)), within=true)
  .allow_ellipsis(Is(true))
  |> ignore
}

///|
/// How far a row's has come (`part`, 0 to 1, as it changes) in `parent`: the library's bar (@sf.progress's).
fn transfer_bar(parent : @view.View, part : () -> Double) -> Unit {
  @sf.progress_node(parent, fn() { Some(part()) }, fn() { @ui.tree_theme().line }, fn() { @sf.theme().p.accent })
  |> ignore
}

///|
/// A file opened and let go, being brought after everything else (fill.ts), in `row` as the core says it (`k`): its
/// mark, what it is called, how far (a bar), how it stands (后台缓存 …); stopped by its ✕, what was kept of it let go.
fn keeping_row(row : @view.View, src : Source, k : @signals.Signal[Json]) -> Unit {
  let j = fn() { Some(k.get()) }
  let kid = text(Some(k.untracked()), "id")
  transfer_row_of(
    row,
    fn(m) { @sf.icon_node(m, "download", transfer_icon, By(fn() { @sf.theme().p.muted })) |> ignore },
    fn(w) {
      // (its words say it is kept here as it comes: 后台缓存 …; pressed, it is opened again where it was)
      opened_title(w, j, None)
      transfer_bar(w, fn() { number(j(), "progress") })
      transfer_words(w, fn() { text(j(), "statusText") }, fn() { ftransfer_status })
    },
    fn(a) {
      @sf.panel_icon_button_node(a, "close", fn() { @sf.t("web-pages.files.stopKeeping") }, fn() { keeping_stop(src, kid) })
      |> ignore
    },
  )
}

///|
/// What comes, by what it is called (and its `way`, where it says one), in `parent` as `j` says it: pressed, opened
/// again where it was opened (its `from`, as what opened it said: a chat's file in the viewer over its chat's files, a
/// drive's video or song in its player), or a drive's file's folder; only words where there is nowhere to go.
fn opened_title(parent : @view.View, j : () -> Json?, way : (() -> String)?) -> Unit {
  parent.box(fn(b) {
    @sf.style_node(b, fn() { ftransfer_title })
    let there = fn() { opens(j()) }
    @sf.presses_node(b, fn() { if @signals.untracked(there) { open_coming(@signals.untracked(j)) } }, on=there)
    b.says(By(fn() { if there() { Some(@view.said(Button, label=text(j(), "title"))) } else { None } })) |> ignore
    transfer_words(b, fn() { text(j(), "title") }, fn() { ftransfer_title_words })
    match way {
      Some(w) => transfer_words(b, w, fn() { ftransfer_way })
      None => ()
    }
  })
  |> ignore
}

///|
/// Whether it can be opened again from the list: where it was opened is known, or it is a drive's file.
fn opens(j : Json?) -> Bool {
  let from = field(j, "from")
  field(from, "file") is Some(_) || text(from, "root") != "" || text(j, "root") != ""
}

///|
/// Opened again where it was opened: a chat's file in the viewer over its chat's files (its message's file, as the
/// core kept it), a drive's video or song in its player; else a drive's download's folder. The list goes.
fn open_coming(j : Json?) -> Unit {
  let from = field(j, "from")
  let station = text(j, "station")
  ftransfers.open.set(false)
  match field(from, "file") {
    Some(f) => {
      let thread = match field(from, "thread") {
        Some(Number(n, ..)) => Some(n)
        _ => None
      }
      @sfbase.open_preview(station, text(j, "key"), @sfbase.attachment_of(f), steps=@sfbase.Stepping::InChat(thread, text(from, "session")))
    }
    None =>
      if text(from, "root") != "" {
        open_page(DrivePlay({ station, root: Some(text(from, "root")), path: text(from, "path") }))
      } else {
        open_page(Drive({ station, root: Some(text(j, "root")), path: @sfbase.dv_parent(text(j, "path")) }))
      }
  }
}

///|
/// A transfer (TransferRow) in `row` as the core says it (`x`): its mark, what goes and where, how far (a bar while it
/// copies), how it stands; stopped while it goes, tried again once failed, its folder shown once done.
fn transfer_row(row : @view.View, src : Source, x : @signals.Signal[Json], go : (DriveAt) -> Unit) -> Unit {
  let j = fn() { Some(x.get()) }
  let state = fn() { text(j(), "state") }
  let (station, tid) = (text(Some(x.untracked()), "station"), text(Some(x.untracked()), "id"))
  let way = fn() {
    let way = if text(j(), "fromStation") == station {
      @sf.t("web-pages.files.into", args=[("to", text(j(), "toText"))])
    } else {
      @sf.t("web-pages.files.fromInto", args=[("from", text(j(), "fromStationName")), ("to", text(j(), "toText"))])
    }
    if flag(j(), "move") {
      @sf.t("web-pages.files.moving", args=[("way", way)])
    } else {
      way
    }
  }
  let call = fn(name : String) {
    (src.call)(name, { "station": Json::string(station), "id": Json::string(tid) }, act_said(@sf.t("web-pages.files.transferWhat")))
  }
  let mark = fn() {
    let t = @sf.theme()
    match state() {
      "done" => ("check", t.p.green)
      "failed" => ("retry", t.p.red)
      "cancelled" => ("close", t.p.muted)
      _ => ("move", t.p.muted)
    }
  }
  transfer_row_of(
    row,
    fn(m) {
      @sf.icon_node(m, @signals.untracked(mark).0, transfer_icon, By(fn() { mark().1 }), name_now=fn() { mark().0 })
      |> ignore
    },
    fn(w) {
      w.box(fn(b) {
        @sf.style_node(b, fn() { ftransfer_title })
        transfer_words(b, fn() { text(j(), "title") }, fn() { ftransfer_title_words })
        transfer_words(b, way, fn() { ftransfer_way })
      })
      |> ignore
      w.show(fn() { state() == "copying" }, fn(p) { transfer_bar(p, fn() { number(j(), "progress") }) })
      transfer_words(
        w,
        fn() {
          let files = number(j(), "files").to_int()
          text(j(), "statusText") +
          (if (state() == "copying" || state() == "done") && files > 1 {
            " · " + @sf.t("web-pages.files.filesCount", args=[("n", files.to_string())])
          } else {
            ""
          })
        },
        fn() { if state() == "failed" { ftransfer_failed } else { ftransfer_status } },
      )
    },
    fn(a) {
      a.show(fn() { flag(j(), "active") }, fn(k) {
        @sf.panel_icon_button_node(k, "close", fn() { @sf.t("web-pages.files.cancelTransfer") }, fn() {
          call("drive.transfer.cancel")
        })
        |> ignore
      })
      a.show(fn() { state() == "failed" }, fn(k) {
        @sf.panel_icon_button_node(k, "retry", fn() { @sf.t("web-pages.drive.retry") }, fn() { call("drive.transfer.retry") })
        |> ignore
      })
      a.show(fn() { state() == "done" }, fn(k) {
        @sf.panel_button_node(k, fn() { @sf.t("web-pages.files.show") }, fn() {
          ftransfers.open.set(false)
          let j = x.untracked()
          go({ station, root: Some(text(Some(j), "toRoot")), path: text(Some(j), "toPath") })
        })
        |> ignore
      })
    },
  )
}

///|
/// A file of the drive (a folder zipped) downloaded to this device, in `row` as the core says it (`d`): what, how far
/// (a bar while it comes), how it stands; stopped while it comes, tried again once failed.
fn download_row(row : @view.View, src : Source, d : @signals.Signal[Json]) -> Unit {
  let j = fn() { Some(d.get()) }
  let failed = fn() { text(j(), "state") == "failed" }
  let active = fn() { flag(j(), "active") }
  let did = text(Some(d.untracked()), "id")
  transfer_row_of(
    row,
    fn(m) {
      @sf.icon_node(
        m,
        if @signals.untracked(failed) { "retry" } else { "download" },
        transfer_icon,
        By(fn() { if failed() { @sf.theme().p.red } else { @sf.theme().p.muted } }),
        name_now=fn() { if failed() { "retry" } else { "download" } },
      )
      |> ignore
    },
    fn(w) {
      opened_title(w, j, Some(fn() { @sf.t("web-pages.files.toDevice") }))
      w.show(active, fn(p) { transfer_bar(p, fn() { number(j(), "progress") }) })
      transfer_words(w, fn() { text(j(), "statusText") }, fn() { if failed() { ftransfer_failed } else { ftransfer_status } })
    },
    fn(a) {
      a.show(active, fn(k) {
        @sf.panel_icon_button_node(k, "close", fn() { @sf.t("web-main.file.cancelDownload") }, fn() { download_cancel(src, did) })
        |> ignore
      })
      a.show(failed, fn(k) {
        @sf.panel_icon_button_node(k, "retry", fn() { @sf.t("web-main.file.retryDownload") }, fn() { download_retry(src, did) })
        |> ignore
      })
    },
  )
}

///|
/// The transfers' list (transfers: 360 wide).
let ftransfers_w : Double = 360.0

///|
/// A transfer (transfer: its mark 18, its words, its keys; 8 apart): what it holds as far in as a small panel's words
/// (a row's padding in from the panel's), 8 over and under; set apart by that room alone, no line between.
// kept across runs: a value (no field of it changes)
let ftransfer_row : @ui.Style = @ui.css("row w=Full px=S2_5 py=S2 gap=S2 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let ftransfer_mark : @ui.Style = @ui.css("w=S4_5 h=S4_5 align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let ftransfer_text : @ui.Style = @ui.style(w=@sf.grow, gap=S1, clip=true)

///|
// kept across runs: a value (no field of it changes)
let ftransfer_title : @ui.Style = @ui.css("row gap=S1 clip")

///|
// kept across runs: a value (no field of it changes)
let ftransfer_title_words : @ui.TextStyle = @ui.text_style(size=Meta, weight=Medium, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ftransfer_way : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ftransfer_status : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ftransfer_failed : @ui.TextStyle = @ui.text_style(size=Meta, color=Danger, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ftransfer_actions : @ui.Style = @ui.css("row gap=SPx align=ACenter")

///|
/// A row's mark (14).
let transfer_icon : Double = 14.0
