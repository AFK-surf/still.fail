// The files' page's copies between folders and stations and the drive's files downloaded to this device (ember
// web/src/pages/Transfers.tsx, Files.css.ts transfers): the bar's 传输 (how many go, how far), its list (each copy's way,
// how it stands, stopped, tried again, its folder shown once done; each download, how far, stopped, tried again).

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
/// This device's downloads of the workspace's stations' drives (the `downloads` topic's with a root: a file, a folder
/// zipped), newest first.
fn download_list(src : Source, ws : String) -> Array[Json] {
  items((src.topic)("downloads", {}).value, "downloads").filter(fn(d) {
    field(Some(d), "root") is Some(_) && text(Some(d), "station").has_prefix(ws + "/")
  })
}

///|
/// On the bar: the transfers and the drive's downloads, how many go and how far they are (in the accent while they go,
/// red when one failed); pressed, their list. Nothing while there has been none.
pub fn transfers_button(c : @ui.Ctx, src : Source, ws : String, go : (DriveAt) -> Unit) -> Unit {
  let t = @sf.theme()
  let all = transfer_list(src, ws)
  let downloads = download_list(src, ws)
  let id = c.id("files/transfers")
  if all.length() == 0 && downloads.length() == 0 {
    ftransfers.open = false
    if ftransfers.shown > 0 {
      @sf.close_presented_of(ftransfers.shown)
      ftransfers.shown = 0
    }
    return
  }
  let going = all.filter(fn(x) { flag(Some(x), "active") })
  let coming = downloads.filter(fn(d) { flag(Some(d), "active") })
  let failed = all.iter().any(fn(x) { text(Some(x), "state") == "failed" }) ||
    downloads.iter().any(fn(d) { text(Some(d), "state") == "failed" })
  let total = going.fold(init=0.0, fn(a, x) { a + number(Some(x), "total") }) +
    coming.fold(init=0.0, fn(a, d) { a + number(Some(d), "size") })
  let copied = going.fold(init=0.0, fn(a, x) { a + number(Some(x), "copied") }) +
    coming.fold(init=0.0, fn(a, d) { a + number(Some(d), "loaded") })
  let n = going.length() + coming.length()
  let label = if n > 0 {
    let percent = if total > 0.0 { (copied / total * 100.0).floor().to_int() } else { 0 }
    @sf.t("web-pages.files.transfersGoing", args=[("n", n.to_string()), ("percent", percent.to_string())])
  } else {
    @sf.t("web-pages.files.transfers")
  }
  c.cursor(id, Hand)
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
  // its list: the library's panel under it, along its end (what is in it read as it is drawn)
  if ftransfers.open && ftransfers.shown == 0 {
    @sf.panel(
      @sf.t("web-pages.files.transfers"),
      fn(c, _) {
        for d in download_list(src, ws) {
          download_row(c, src, d)
        }
        for x in transfer_list(src, ws) {
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
  c.box(style=transfer_rule, fn() {  }) |> ignore
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
  c.box(style=transfer_rule, fn() {  }) |> ignore
  c.box(style=ftransfer_row, fn() {
    c.box(style=ftransfer_mark, fn() {
      @sf.icon(c, if failed { "retry" } else { "download" }, size=transfer_icon, color=if failed { t.p.red } else { t.p.muted })
      |> ignore
    })
    |> ignore
    c.box(style=ftransfer_text, fn() {
      c.box(style=ftransfer_title, fn() {
        c.text(text(j, "name"), style=ftransfer_title_words) |> ignore
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
/// A transfer (transfer: its mark 18, its words, its keys; 8 apart, a line over it): what it holds as far in as a
/// small panel's words (a row's padding in from the panel's), 8 over and under.
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
/// A row's mark (14), and the line over each row of the list.
let transfer_icon : Double = 14.0

///|
// kept across runs: a value (no field of it changes)
let transfer_rule : @ui.Style = @ui.css("w=Full h=SPx bg=Line")
