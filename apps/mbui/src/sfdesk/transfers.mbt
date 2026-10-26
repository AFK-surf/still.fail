// What comes to this device and goes between its stations (ember web/src/pages/Transfers.tsx, Files.css.ts
// transfers): the copies between folders and stations, the files downloaded to this device (a chat's, a drive's) and
// those opened and let go being brought after everything else (client/core-ts fill.ts). On the files' bar its 传输,
// and in the chats' sidebar's foot (how many go, how far); its list (each copy's way, how it stands, stopped, tried
// again, its folder shown once done; each download, how far, stopped, tried again; each file being brought, how far
// and how it stands, stopped).

///|
/// Whether the bar's 传输 has its list open, and the list as presented (@sf.last_presented; 0 none).
priv struct Transfers {
  mut open : Bool
  mut shown : Int
}

///|
// kept across runs: the list's state (transfers_reset puts it back)
let ftransfers : Transfers = { open: false, shown: 0 }

///|
fn transfers_reset() -> Unit {
  ftransfers.open = false
  ftransfers.shown = 0
}

///|
/// The bar's 传输 with its list open (a page shown at that moment: the fixture's).
pub fn transfers_open() -> Unit {
  ftransfers.open = true
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
/// Their list, while `ftransfers.open`: the library's panel from `id` (beside it, or a sheet from the foot on a small
/// screen), what is being brought first, then the downloads, then the copies (what is in it read as it is drawn);
/// closed once there is none. `go`: where a copy's folder is shown.
fn transfers_list(c : @ui.Ctx, src : Source, ws : String, id : Int, go : (DriveAt) -> Unit, none : Bool) -> Unit {
  if none {
    ftransfers.open = false
  }
  if ftransfers.open && ftransfers.shown == 0 {
    @sf.panel(
      @sf.t("web-pages.files.transfers"),
      fn(c, _) {
        let all = coming(src, ws)
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
      gone=fn() {
        ftransfers.open = false
        ftransfers.shown = 0
      },
    )
    ftransfers.shown = @sf.last_presented()
  } else if !ftransfers.open && ftransfers.shown > 0 {
    @sf.close_presented_of(ftransfers.shown)
    ftransfers.shown = 0
  }
}

///|
/// On the files' bar: what comes and goes, how many go and how far they are (in the accent while they go, red when
/// one failed); pressed, their list. Nothing while there has been none.
pub fn transfers_button(c : @ui.Ctx, src : Source, ws : String, go : (DriveAt) -> Unit) -> Unit {
  let t = @sf.theme()
  let all = coming(src, ws)
  let id = c.id("files/transfers")
  if all.none() {
    transfers_list(c, src, ws, id, go, true)
    return
  }
  let (n, percent, failed) = all.going()
  let label = coming_words(n, percent)
  if c.clicked(id) {
    ftransfers.open = !ftransfers.open
  }
  let (style, words, ink) = if failed {
    (ftransfers_chip_failed, ftransfers_chip_failed_words, t.p.red)
  } else if n > 0 {
    (ftransfers_chip_going, ftransfers_chip_going_words, t.p.accent_text)
  } else {
    (ftransfers_chip, ftransfers_chip_words, t.p.muted)
  }
  let b = c.box(style~, id~, fn() {
    @sf.icon(c, "move", size=transfer_icon, color=ink) |> ignore
    c.text(label, style=words) |> ignore
  })
  c.semantics(b, Button, id~, label~)
  transfers_list(c, src, ws, id, go, false)
}

///|
/// In the sidebar's foot (beside 运行中, lists.mbt lists_foot): what comes and goes, how many and how far, as the
/// files' bar says it; pressed, their list over it. Nothing while there is none.
fn side_transfers(c : @ui.Ctx, src : Source, ws : String) -> Unit {
  let t = @sf.theme()
  let all = coming(src, ws)
  let id = c.id("side/transfers")
  let go = fn(at : DriveAt) { open_page(Drive(at)) }
  if all.none() {
    transfers_list(c, src, ws, id, go, true)
    return
  }
  let (n, percent, failed) = all.going()
  let label = coming_words(n, percent)
  if c.clicked(id) {
    ftransfers.open = !ftransfers.open
  }
  let b = c.box(style=foot_chip, id~, fn() {
    @sf.icon(c, if failed { "retry" } else { "download" }, size=transfer_icon, color=if failed { t.p.red } else { t.p.muted })
    |> ignore
    c.text(label, style=if failed { foot_chip_failed_words } else { foot_chip_words }) |> ignore
  })
  c.semantics(b, Button, id~, label~)
  transfers_list(c, src, ws, id, go, false)
}

///|
/// Over the chats on a small screen's home (as what the last update brought is: changelog.mbt changelog_news): what
/// comes and goes, how many and how far, the first of them and how it stands, a bar for all of them; pressed, their
/// list (from the foot). Nothing while there is none.
pub fn home_transfers(c : @ui.Ctx, src : Source, ws : String, band_in : Double) -> Unit {
  let t = @sf.theme()
  let all = coming(src, ws)
  let id = c.id("home/transfers")
  let go = fn(at : DriveAt) { open_page(Drive(at)) }
  if all.none() {
    transfers_list(c, src, ws, id, go, true)
    return
  }
  let (n, percent, failed) = all.going()
  if c.clicked(id) {
    ftransfers.open = !ftransfers.open
  }
  // the first of them: what is being brought, else a download, else a copy
  let first = match (all.keeping.get(0), all.downloads.get(0), all.transfers.get(0)) {
    (Some(k), _, _) => Some(k)
    (None, Some(d), _) => Some(d)
    (None, None, x) => x
  }
  let label = coming_words(n, percent)
  c.box(style=home_room.then(@ui.style(px=@sf.room_of(band_in))), fn() {
    let b = c.box(style=home_card, id~, fn() {
      c.box(style=home_head, fn() {
        @sf.icon(c, if failed { "retry" } else { "download" }, size=home_icon, color=if failed { t.p.red } else { t.p.text })
        |> ignore
        c.text(label, style=if failed { home_title_failed } else { home_title }) |> ignore
      })
      |> ignore
      match first {
        Some(f) => {
          let j = Some(f)
          c.text(text(j, "title") + " · " + text(j, "statusText"), style=home_line) |> ignore
        }
        None => ()
      }
      if n > 0 {
        @sf.progress(c, "home/transfers", Some(percent.to_double() / 100.0))
      }
      @motion.ripple(c, id, 0.0)
    })
    c.semantics(b, Button, id~, label~)
  })
  |> ignore
  transfers_list(c, src, ws, id, go, false)
}

///|
/// Its room on the list (as changelog_news's: 4 over, 10 under).
// kept across runs: a value (no field of it changes)
let home_room : @ui.Style = @ui.css("w=Full pt=S1 pb=S2_5")

///|
/// The card (as changelog_news's: the card's corner, its words 16 in, 12 over and under).
// kept across runs: a value (no field of it changes)
let home_card : @ui.Style = @ui.css("w=Full px=S4 py=S3 gap=S1_5 radius=Xl3 bg=Surface clip")

///|
// kept across runs: a value (no field of it changes)
let home_head : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
let home_icon : Double = 16.0

///|
// kept across runs: a value (no field of it changes)
let home_title : @ui.TextStyle = @ui.text_style(size=Ui, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let home_title_failed : @ui.TextStyle = @ui.text_style(size=Ui, weight=Semibold, color=Danger, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let home_line : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false, w=Full)

///|
/// Whether there is anything that comes and goes (the sidebar's foot, a small screen's home show it then).
pub fn transfers_shown(src : Source, ws : String) -> Bool {
  !coming(src, ws).none()
}

///|
/// The list open over the sidebar's foot (a fixture's: MBUI_FIXTURE=home-transfers).
pub fn open_transfers() -> Unit {
  ftransfers.open = true
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
      // (its words say it is kept here as it comes: 后台缓存 …)
      c.box(style=ftransfer_title, fn() { c.text(text(j, "title"), style=ftransfer_title_words) |> ignore }) |> ignore
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
        ftransfers.open = false
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
      c.box(style=ftransfer_title, fn() {
        c.text(text(j, "title"), style=ftransfer_title_words) |> ignore
        c.text(@sf.t("web-pages.files.toDevice"), style=ftransfer_way) |> ignore
      })
      |> ignore
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
/// The chip (transfersChip: 28 high, 10 in, the neutral ground, its words muted; going: the accent's; failed: red's).
// kept across runs: a value (no field of it changes)
let ftransfers_chip : @ui.Style = @ui.css("row h=S7 px=S2_5 gap=S1_5 align=ACenter radius=Full bg=Neutral")

///|
// kept across runs: a value (no field of it changes)
let ftransfers_chip_going : @ui.Style = ftransfers_chip.then(@ui.css("bg=AccentBg"))

///|
// kept across runs: a value (no field of it changes)
let ftransfers_chip_failed : @ui.Style = ftransfers_chip.then(@ui.css("bg=DangerBg"))

///|
// kept across runs: a value (no field of it changes)
let ftransfers_chip_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ftransfers_chip_going_words : @ui.TextStyle = @ui.text_style(size=Meta, color=AccentText, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ftransfers_chip_failed_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Danger, wrap=false)

///|
/// The sidebar's foot's chip's words, failed (as 运行中's: lists.mbt foot_chip_words).
// kept across runs: a value (no field of it changes)
let foot_chip_failed_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Danger, wrap=false)

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
