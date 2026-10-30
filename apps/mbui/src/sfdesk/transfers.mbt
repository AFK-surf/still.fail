// What comes to this device and goes between its stations (ember web/src/pages/Transfers.tsx, Files.css.ts
// transfers): the copies between folders and stations, the files downloaded to this device (a chat's, a drive's) and
// those opened and let go being brought after everything else (client/core-ts fill.ts). On the files' bar its 传输,
// and in the chats' sidebar's foot (how many go, how far); its list (each copy's way, how it stands, stopped, tried
// again, its folder shown once done; each download, how far, stopped, tried again; each file being brought, how far
// and how it stands, stopped).

///|
/// Whether the bar's 传输 has its list open, and the list as presented (@sf.last_presented; 0 none).
priv struct Transfers {
  open : @signals.Signal[Bool]
  shown : @signals.Signal[Int]
}

///|
// kept across runs: the list's state (transfers_reset puts it back)
let ftransfers : Transfers = { open: @signals.signal(false, same=fn(a, b) { a == b }), shown: @signals.signal(0 , same=fn(a, b) { a == b })}

///|
fn transfers_reset() -> Unit {
  ftransfers.open.set(false)
  ftransfers.shown.set(0)
}

///|
/// The bar's 传输 with its list open (a page shown at that moment: the fixture's).
pub fn transfers_open() -> Unit {
  ftransfers.open.set(true)
}

///|
/// The person's transfers into the workspace's stations (the `driveTransfers` topic), newest first.
fn transfer_list(src : Source, ws : String) -> Array[Json] {
  items((src.topic)("driveTransfers", { "workspace": Json::string(ws) }).value, "transfers")
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
/// Their list, while `ftransfers.open.get()`: the library's panel from `id` (beside it, or a sheet from the foot on a small
/// screen), what is being brought first, then the downloads, then the copies (what is in it read as it is drawn);
/// closed once there is none. `go`: where a copy's folder is shown. `side`, `along`: where it stands beside `id` (the
/// rail's key: beside the rail, `rail_menu_off` out, its foot level with the key's, as the workspaces' menu under it is;
/// under it, it lay over the rail, the mark of the workspace in view showing at its edge).
fn transfers_list(
  c : @ui.Ctx,
  src : Source,
  ws : String,
  id : Int,
  go : (DriveAt) -> Unit,
  none : Bool,
  side? : @ui.Side = Bottom,
  along? : @ui.Along = Start,
) -> Unit {
  if none {
    ftransfers.open.set(false)
  }
  if ftransfers.open.get() && ftransfers.shown.get() == 0 {
    @sf.panel(
      @sf.t("web-pages.files.transfers"),
      fn(c, _) {
        let all = coming(src, ws)
        // (a newer build of the app first: sfbase updates.mbt)
        if update_coming() {
          update_row(c, src)
        }
        for k in all.keeping {
          keeping_row(c, src, k)
        }
        for d in all.downloads {
          download_row(c, src, d)
        }
        for x in all.transfers {
          transfer_row(c, src, x, go)
        }
      },
      from=Of(id),
      w=ftransfers_w,
      side~,
      along~,
      offset=if side is Right { rail_menu_off } else { @sf.panel_offset },
      gone=fn() {
        ftransfers.open.set(false)
        ftransfers.shown.set(0)
      },
    )
    ftransfers.shown.set(@sf.last_presented())
  } else if !ftransfers.open.get() && ftransfers.shown.get() > 0 {
    @sf.close_presented_of(ftransfers.shown.get())
    ftransfers.shown.set(0)
  }
}


///|
/// In the rail of a medium or large screen, over the workspaces (as a small screen's home's key: transfers_key): what
/// comes and goes, as far as it has come (@sf.coming_mark in its mark's place), red's dot when one failed; pressed, their list beside
/// it. Nothing while there is none.
fn rail_transfers(c : @ui.Ctx, src : Source, ws : String) -> Unit {
  let all = coming(src, ws)
  let id = c.id("rail/transfers")
  let go = fn(at : DriveAt) { open_page(Drive(at)) }
  if all.none() {
    transfers_list(c, src, ws, id, go, true, side=Right, along=End)
    return
  }
  let (n, percent, failed) = all.going()
  if c.clicked(id) {
    ftransfers.open.set(!ftransfers.open.get())
  }
  rail_ground(
    c,
    id,
    ftransfers.open.get(),
    fn(color) {
      // (as the small screen's key's: @sf.progress_key)
      @sf.coming_mark(c, "rail/transfers", Some(percent.to_double() / 100.0), rail_icon_size, color)
      if failed {
        rail_tone_mark(c, "alert")
      }
    },
    label=coming_words(n, percent),
  )
  transfers_list(c, src, ws, id, go, false, side=Right, along=End)
}

///|
/// In a small screen's home's top bar: what comes to this device and goes between the stations, a newer build of the
/// app among it (offered, coming, failed: sfbase updates.mbt), as one key (@sf.progress_key: the download's mark, a
/// ring as far as what comes has come, the accent's dot while a build is offered, red's when one failed); pressed,
/// their list (from the foot). Nothing while there is none.
pub fn transfers_key(c : @ui.Ctx, src : Source, ws : String, side : Double, mark : Double) -> Unit {
  let all = coming(src, ws)
  let id = c.id("home/transfers")
  let go = fn(at : DriveAt) { open_page(Drive(at)) }
  let build = update_coming()
  if all.none() && !build {
    transfers_list(c, src, ws, id, go, true)
    return
  }
  let (n, percent, failed) = all.going()
  let updating = @sfbase.update_under_way()
  // how far: what comes, else the build as far as the host says (not known: none)
  let ring = if n > 0 {
    Some(percent.to_double() / 100.0)
  } else if updating {
    Some(@sfbase.update_part().or(0.0))
  } else {
    None
  }
  let label = if n > 0 { coming_words(n, percent) } else { @sf.t("web-pages.files.transfers") }
  let offered = build && !updating && @sfbase.update_phase() != "failed"
  if @sf.progress_key(c, "home/transfers", side, mark, "download", label, ring, dot=offered, failed=failed || @sfbase.update_phase() == "failed") {
    ftransfers.open.set(!ftransfers.open.get())
  }
  transfers_list(c, src, ws, id, go, false)
}

///|
/// Whether a newer build of the app is to be listed with what comes: offered (it brings something the changelog
/// says), coming, being installed, or failed.
fn update_coming() -> Bool {
  let offered = match @sfbase.update.available.get() {
    Some(v) => items(Some(v), "news").length() > 0
    None => false
  }
  offered || @sfbase.update_under_way() || @sfbase.update_phase() == "failed"
}

///|
/// A newer build of the app with what comes (sfbase updates.mbt): 更新到 …; offered, what it brings first, its key
/// to install it (the list staying open, to watch it come); coming, how far (a bar) and how it stands; failed, why in
/// red, its key to try again.
fn update_row(c : @ui.Ctx, src : Source) -> Unit {
  let t = @sf.theme()
  let failed = @sfbase.update_phase() == "failed"
  let going = @sfbase.update_under_way()
  let version = text(@sfbase.update.available.get(), "versionName")
  let first = match items(@sfbase.update.available.get(), "news").get(0) {
    Some(String(line)) => line
    _ => ""
  }
  let said = if going { @sfbase.update_progress() } else if failed { @sfbase.update_why() } else { first }
  c.box(style=ftransfer_row, fn() {
    c.box(style=ftransfer_mark, fn() {
      @sf.icon(c, if failed { "retry" } else { "sparks" }, size=transfer_icon, color=if failed { t.p.red } else { t.p.muted }) |> ignore
    })
    |> ignore
    c.box(style=ftransfer_text, fn() {
      c.box(style=ftransfer_title, fn() {
        c.text(@sf.t("android-chat.home.update", args=[("version", version)]), style=ftransfer_title_words) |> ignore
      })
      |> ignore
      if going {
        @sf.progress(c, "update/coming", @sfbase.update_part())
      }
      if said != "" {
        c.text(said, style=if failed { ftransfer_failed } else { ftransfer_status }) |> ignore
      }
    })
    |> ignore
    c.box(style=ftransfer_actions, fn() {
      if !going &&
        @sf.panel_icon_button(c, "update/install", if failed { "retry" } else { "download" }, @sf.t("android-chat.home.update", args=[("version", version)])) {
        // (the list stays: how far the build has come is said in this row as it downloads)
        c.tell("update/install", fn() { @sfbase.update_install(src) })
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// Whether a small screen's home's top bar has its key (transfers_key): what comes, or a newer build.
pub fn transfers_key_shown(src : Source, ws : String) -> Bool {
  transfers_shown(src, ws) || update_coming()
}

///|
/// Whether there is anything that comes and goes (the sidebar's foot, a small screen's home show it then).
pub fn transfers_shown(src : Source, ws : String) -> Bool {
  !coming(src, ws).none()
}

///|
/// The list open over the sidebar's foot (a fixture's: MBUI_FIXTURE=home-transfers).
pub fn open_transfers() -> Unit {
  ftransfers.open.set(true)
}

///|
/// A file opened and let go, being brought after everything else (fill.ts): its mark, what it is called, how far (a
/// bar), how it stands (后台缓存 …); stopped by its ✕, what was kept of it let go.
fn keeping_row(c : @ui.Ctx, src : Source, k : Json) -> Unit {
  let t = @sf.theme()
  let j = Some(k)
  let kid = text(j, "id")
  c.box(style=ftransfer_row, fn() {
    c.box(style=ftransfer_mark, fn() { @sf.icon(c, "download", size=transfer_icon, color=t.p.muted) |> ignore }) |> ignore
    c.box(style=ftransfer_text, fn() {
      // (its words say it is kept here as it comes: 后台缓存 …; pressed, it is opened again where it was)
      opened_title(c, j, "keeping/open/" + kid, None)
      @sf.progress(c, "keeping/" + kid, Some(number(j, "progress")))
      c.text(text(j, "statusText"), style=ftransfer_status) |> ignore
    })
    |> ignore
    c.box(style=ftransfer_actions, fn() {
      if @sf.panel_icon_button(c, "keeping/stop/" + kid, "close", @sf.t("web-pages.files.stopKeeping")) {
        c.tell("keeping/stop/" + kid, fn() { keeping_stop(src, kid) })
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// What comes, by what it is called (and its way, where it says one): pressed, opened again where it was opened (its
/// `from`, as what opened it said: a chat's file in the viewer over its chat's files, a drive's video or song in its
/// player), or a drive's file's folder; only words where there is nowhere to go.
fn opened_title(c : @ui.Ctx, j : Json?, key : String, way : String?) -> Unit {
  let id = c.id(key)
  let there = opens(j)
  if there && c.clicked(id) {
    open_coming(j)
  }
  let b = c.box(style=ftransfer_title, id=if there { id } else { 0 }, fn() {
    c.text(text(j, "title"), style=ftransfer_title_words) |> ignore
    match way {
      Some(w) => c.text(w, style=ftransfer_way) |> ignore
      None => ()
    }
  })
  if there {
    c.semantics(b, Button, id~, label=text(j, "title"))
  }
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
/// A transfer (TransferRow): its mark, what goes and where, how far (a bar while it copies), how it stands; stopped
/// while it goes, tried again once failed, its folder shown once done.
fn transfer_row(c : @ui.Ctx, src : Source, x : Json, go : (DriveAt) -> Unit) -> Unit {
  let t = @sf.theme()
  let j = Some(x)
  let state = text(j, "state")
  let station = text(j, "station")
  let tid = text(j, "id")
  let way = if text(j, "fromStation") == station {
    @sf.t("web-pages.files.into", args=[("to", text(j, "toText"))])
  } else {
    @sf.t("web-pages.files.fromInto", args=[("from", text(j, "fromStationName")), ("to", text(j, "toText"))])
  }
  let call = fn(name : String) {
    (src.call)(name, { "station": Json::string(station), "id": Json::string(tid) }, act_done(c, @sf.t("web-pages.files.transferWhat")))
  }
  c.box(style=ftransfer_row, fn() {
    let (mark, ink) = match state {
      "done" => ("check", t.p.green)
      "failed" => ("retry", t.p.red)
      "cancelled" => ("close", t.p.muted)
      _ => ("move", t.p.muted)
    }
    c.box(style=ftransfer_mark, fn() { @sf.icon(c, mark, size=transfer_icon, color=ink) |> ignore }) |> ignore
    c.box(style=ftransfer_text, fn() {
      c.box(style=ftransfer_title, fn() {
        c.text(text(j, "title"), style=ftransfer_title_words) |> ignore
        c.text(if flag(j, "move") { @sf.t("web-pages.files.moving", args=[("way", way)]) } else { way }, style=ftransfer_way) |> ignore
      })
      |> ignore
      if state == "copying" {
        @sf.progress(c, "transfer/" + tid, Some(number(j, "progress")))
      }
      let files = number(j, "files").to_int()
      let status = text(j, "statusText") +
        (if (state == "copying" || state == "done") && files > 1 {
          " · " + @sf.t("web-pages.files.filesCount", args=[("n", files.to_string())])
        } else {
          ""
        })
      c.text(status, style=if state == "failed" { ftransfer_failed } else { ftransfer_status }) |> ignore
    })
    |> ignore
    c.box(style=ftransfer_actions, fn() {
      if flag(j, "active") && @sf.panel_icon_button(c, "files/transfer/cancel/" + tid, "close", @sf.t("web-pages.files.cancelTransfer")) {
        call("drive.transfer.cancel")
      }
      if state == "failed" && @sf.panel_icon_button(c, "files/transfer/retry/" + tid, "retry", @sf.t("web-pages.drive.retry")) {
        call("drive.transfer.retry")
      }
      if state == "done" && @sf.panel_button(c, "files/transfer/show/" + tid, @sf.t("web-pages.files.show")) {
        ftransfers.open.set(false)
        go({ station, root: Some(text(j, "toRoot")), path: text(j, "toPath") })
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// A file of the drive (a folder zipped) downloaded to this device (Transfers.tsx DownloadRow): what, how far (a bar
/// while it comes), how it stands; stopped while it comes, tried again once failed.
fn download_row(c : @ui.Ctx, src : Source, d : Json) -> Unit {
  let t = @sf.theme()
  let j = Some(d)
  let failed = text(j, "state") == "failed"
  let did = text(j, "id")
  c.box(style=ftransfer_row, fn() {
    c.box(style=ftransfer_mark, fn() {
      @sf.icon(c, if failed { "retry" } else { "download" }, size=transfer_icon, color=if failed { t.p.red } else { t.p.muted })
      |> ignore
    })
    |> ignore
    c.box(style=ftransfer_text, fn() {
      opened_title(c, j, "download/open/" + did, Some(@sf.t("web-pages.files.toDevice")))
      if flag(j, "active") {
        @sf.progress(c, "download/" + did, Some(number(j, "progress")))
      }
      c.text(text(j, "statusText"), style=if failed { ftransfer_failed } else { ftransfer_status }) |> ignore
    })
    |> ignore
    c.box(style=ftransfer_actions, fn() {
      if flag(j, "active") && @sf.panel_icon_button(c, "files/download/cancel/" + did, "close", @sf.t("web-main.file.cancelDownload")) {
        c.tell("files/download/cancel/" + did, fn() { download_cancel(src, did) })
      }
      if failed && @sf.panel_icon_button(c, "files/download/retry/" + did, "retry", @sf.t("web-main.file.retryDownload")) {
        c.tell("files/download/retry/" + did, fn() { download_retry(src, did) })
      }
    })
    |> ignore
  })
  |> ignore
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
