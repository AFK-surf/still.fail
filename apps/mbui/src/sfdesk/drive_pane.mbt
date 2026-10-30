// The preview beside a folder's list (⌘⇧P, as Finder's preview pane: ember web/src/pages/DrivePane.tsx, Drive.tsx
// usePreviewShown): the file chosen shown there as it is chosen (a picture whole, the start of a text, Markdown
// rendered, code as it is), with what it is, where (its station, its path) and its size and time; what plays (a video,
// a song) or needs a page of its own (a PDF) says how to open it. Several chosen, or a folder, say so. The files' page
// and a chat's 文件 tab both have it; shown or not is kept on the device (prefs `driveViews`: `preview`, `tabPreview`).

///|
/// Whether the preview shows beside a folder's list (`place`: the files' page's, `page`, or a chat's 文件 tab's, `tab`).
pub fn preview_shown(src : Source, place : String) -> Bool {
  text(field((src.topic)("prefs", {}).value, "driveViews"), if place == "page" { "preview" } else { "tabPreview" }) ==
  "shown"
}

///|
/// The preview shown or not (`prefs.set {driveViews: {preview | tabPreview}}`).
pub fn set_preview_shown(src : Source, place : String, on : Bool) -> Unit {
  let o : Map[String, Json] = {}
  o[if place == "page" { "preview" } else { "tabPreview" }] = if on { Json::string("shown") } else { Json::null() }
  (src.call)("prefs.set", { "driveViews": Json::object(o) }, fn(_) {  })
}

///|
/// What the preview shows (Previewed): one file (the folder it is in, its entry), several chosen, or nothing.
pub(all) enum Previewed {
  One(DriveAt, DvEntry)
  Many(Int)
  Nothing
}

///|
/// A picture is shown whole up to this size (MOST_PICTURE); past it, as the others are, by how to open it.
let fpane_most_picture : Double = 32.0 * 1024.0 * 1024.0

///|
/// The start of a text shown (TEXT_PART).
let fpane_text_part : Int = 64 * 1024

///|
/// What the preview has read of the file shown: by the file (its station, root, path and time), its picture's bytes or
/// its text's start, or that it could not be read.
priv struct FPane {
  key : @signals.Signal[String]
  picture : @signals.Signal[String]
  text : @signals.Signal[String?]
  failed : @signals.Signal[Bool]
}

///|
let fpane : FPane = { key: @signals.signal("", same=fn(a, b) { a == b }), picture: @signals.signal("", same=fn(a, b) { a == b }), text: @signals.signal(None), failed: @signals.signal(false, same=fn(a, b) { a == b })}

///|
fn pane_reset() -> Unit {
  fpane.key.set("")
  fpane.picture.set("")
  fpane.text.set(None)
  fpane.failed.set(false)
}

///|
/// What the file is shown as here: a picture, a text, or neither (its kind's mark and how to open it).
fn fpane_way(e : DvEntry) -> String {
  let lower = e.name.to_lower()
  if e.dir {
    ""
  } else if e.kind == "image" && e.size <= fpane_most_picture && !lower.has_suffix(".heic") && !lower.has_suffix(".heif") {
    "picture"
  } else if ["text", "markdown", "code", "csv", "html", "subtitle"].contains(e.kind) {
    "text"
  } else {
    ""
  }
}

///|
/// The file read as the preview shows it, once a file (and its time): a picture whole, a part at a time; a text's start.
fn fpane_read(src : Source, station : String, root : String, path : String, e : DvEntry, way : String) -> Unit {
  let key = station + "\u{1}" + root + "\u{1}" + path + "\u{1}" + e.mtime.to_string()
  if fpane.key.get() == key {
    return
  }
  pane_reset()
  fpane.key.set(key)
  if way == "" {
    return
  }
  let parts : Array[Bytes] = []
  fn next(got : Int) {
    let want = if way == "text" {
      dmin(fpane_text_part.to_double(), e.size).to_int()
    } else {
      drive_part
    }
    let p : Map[String, Json] = {
      "station": Json::string(station),
      "root": Json::string(root),
      "path": Json::string(path),
      "offset": Json::number(got.to_double()),
      "length": Json::number(want.to_double()),
    }
    drive_keep(p, "file", e.mtime, e.size)
    (src.read_bytes)("drive.read", Json::object(p), fn(r) {
      // (another file chosen since: what comes is let go)
      if fpane.key.get() != key {
        return
      }
      match r {
        Ok((answer, bytes)) => {
          let total = match field(Some(answer), "total") {
            Some(Number(n, ..)) => n.to_int()
            _ => got + bytes.length()
          }
          parts.push(bytes)
          let now = got + bytes.length()
          if way == "text" {
            let (words, _) = @hostapi.decode_text(bytes, truncated=total > now)
            fpane.text.set(Some(words))
          } else if bytes.length() > 0 && now < total {
            next(now)
          } else {
            let whole : Array[Byte] = Array(capacity=now)
            for b in parts {
              for i in 0..<b.length() {
                whole.push(b[i])
              }
            }
            fpane.picture.set("mem:files-pane/" + key)
            @ui.add_image(fpane.picture.get(), Bytes::from_array(whole[:]))
          }
        }
        Err(_) => fpane.failed.set(true)
      }
    })
  }
  next(0)
}

///|
/// The preview (DrivePane): beside the list (`below`: under it, a chat's 文件 tab's), what is chosen shown, else what
/// to do to see one; 打开, 下载, 复制路径 under what the file is.
pub fn drive_pane(
  c : @ui.Ctx,
  src : Source,
  shown : Previewed,
  station_name : String,
  on_open : () -> Unit,
  on_save : () -> Unit,
  on_copy_path : (String) -> Unit,
  below? : Bool = false,
) -> Unit {
  c.box(style=if below { fpane_below } else { fpane_box }, fn() {
    match shown {
      Nothing => c.box(style=fpane_none_at, fn() { c.text(@sf.t("web-pages.files.previewNone"), style=fpane_none) |> ignore }) |> ignore
      Many(n) =>
        c.box(style=fpane_none_at, fn() {
          c.text(@sf.t("web-pages.files.previewMany", args=[("n", n.to_string())]), style=fpane_none) |> ignore
        })
        |> ignore
      One(at, e) => {
        let root = at.root.unwrap_or("")
        let path = dv_join(at.path, e.name)
        let abs = dv_absolute(root, path)
        let way = fpane_way(e)
        fpane_read(src, at.station, root, path, e, way)
        fpane_body(c, e, way, on_open, room=c.height * (if below { fpane_below_tall } else { fpane_most_tall }), fixed=below)
        c.box(style=fpane_about, fn() {
          c.text(e.name, style=fpane_name) |> ignore
          // what it is, as a grid of two columns: what is said, then its value
          let facts : Array[(String, String)] = []
          if !e.dir {
            facts.push((@sf.t("web-pages.files.size"), e.size_text))
          }
          facts.push((@sf.t("web-pages.files.modified"), e.time_text))
          facts.push(("Station", station_name))
          facts.push((@sf.t("web-pages.files.where"), abs))
          c.box(style=fpane_facts, fn() {
            c.box(style=fpane_facts_column, fn() {
              for f in facts {
                c.text(f.0, style=fpane_fact_said) |> ignore
              }
            })
            |> ignore
            c.box(style=fpane_values_column, fn() {
              for f in facts {
                if f.1 == abs {
                  c.rich([@ui.span(abs, mono=true)], style=fpane_path) |> ignore
                } else {
                  c.text(f.1, style=fpane_fact_value) |> ignore
                }
              }
            })
            |> ignore
          })
          |> ignore
          c.box(style=fpane_actions, fn() {
            if @sf.button(c, @sf.t("web-pages.drive.open"), key="files/preview/open") {
              on_open()
            }
            if !e.dir &&
              @sf.button(c, @sf.t("web-pages.drive.download"), key="files/preview/download", tone=Ghost, icon="download") {
              on_save()
            }
            if @sf.button(c, @sf.t("web-pages.drive.copyPath"), key="files/preview/copy", tone=Ghost, icon="copy") {
              on_copy_path(abs)
            }
          })
          |> ignore
        })
        |> ignore
      }
    }
  })
  |> ignore
}

///|
/// What the file is, shown as it can be here (DrivePane.tsx Body): its picture, its text's start, else its kind's mark
/// and how to open it (pressed, it opens).
fn fpane_body(c : @ui.Ctx, e : DvEntry, way : String, open : () -> Unit, room~ : Double, fixed? : Bool = false) -> Unit {
  let t = @sf.theme()
  if fpane.failed.get() {
    c.box(style=fpane_body_box, fn() { c.text(@sf.t("web-pages.files.previewFailed"), style=fpane_none) |> ignore })
    |> ignore
    return
  }
  match way {
    "picture" =>
      c.box(style=fpane_picture_box, fn() {
        if fpane.picture.get() == "" {
          c.box(style=fpane_waiting, fn() {  }) |> ignore
        } else {
          // whole, as large as the pane is wide and no taller than its room
          let (nw, nh) = @ui.image_natural(fpane.picture.get()).unwrap_or((fpane_inner, fpane_inner))
          let s = dmin(fpane_inner / dmax(1.0, nw), room / dmax(1.0, nh))
          let s = dmin(s, 1.0)
          c.image(fpane.picture.get(), w=Px(nw * s), h=Px(nh * s), fit=FitContain, bg=0L) |> ignore
        }
      })
      |> ignore
    "text" =>
      match fpane.text.get() {
        None => c.box(style=fpane_picture_box, fn() { c.box(style=fpane_waiting, fn() {  }) |> ignore }) |> ignore
        Some(words) => {
          let cut = e.size > fpane_text_part.to_double()
          // (as tall as the pane has room for, at most `room`; under a list, `room` itself)
          c.box(style=fpane_text_box.then(if fixed { @ui.style(h=Fixed(room)) } else { @ui.style(max_h=Fixed(room)) }), fn() {
            if e.kind == "markdown" {
              c.list("files/preview/text", 1, room, fn(_) {
                c.box(style=fpane_prose, fn() {
                  @sf.markdown(c, words, key="files/preview/md", size=12.0, ink=t.p.text, document=true) |> ignore
                  if cut {
                    c.text(@sf.t("web-pages.files.previewMore"), style=fpane_more) |> ignore
                  }
                })
                |> ignore
              })
              |> ignore
            } else {
              let (blocks, _) = @sf.chunk_text(words)
              c.list("files/preview/text", blocks.length() + (if cut { 1 } else { 0 }), fpane_block_est, fn(i) {
                c.box(style=fpane_code, fn() {
                  if i < blocks.length() {
                    c.rich([@ui.span(blocks[i], mono=true)], style=fpane_code_words) |> ignore
                  } else {
                    c.text(@sf.t("web-pages.files.previewMore"), style=fpane_more) |> ignore
                  }
                })
                |> ignore
              })
              |> ignore
            }
          })
          |> ignore
        }
      }
    _ => {
      let id = c.id("files/preview/mark")
      if c.clicked(id) {
        open()
      }
      let words = if e.kind == "video" || e.kind == "audio" {
        @sf.t("web-pages.files.previewPlay")
      } else if e.dir {
        @sf.t("web-pages.files.previewFolder")
      } else {
        @sf.t("web-pages.files.previewOpen")
      }
      let b = c.box(style=fpane_mark, id~, fn() {
        @sf.icon(c, dv_kind_icon(if e.dir { "folder" } else { e.kind }), size=fpane_mark_icon, color=t.p.muted) |> ignore
        c.text(words, style=fpane_mark_words) |> ignore
      })
      c.semantics(b, Button, id~, label=words)
    }
  }
}

///|
/// The pane (DrivePane.css.ts pane: 300 wide, 12 in, 12 between what it shows and what the file is), the room inside.
let fpane_w : Double = 300.0

///|
let fpane_inner : Double = 276.0

///|
/// Under a chat's 文件 tab's list (below: at most half the window, what it shows a quarter).
let fpane_below_tall : Double = 0.25

///|
// kept across runs: a value (no field of it changes)
let fpane_below : @ui.Style = @ui.css("w=Full p=S3 gap=S3")

///|
/// A picture or a text no taller than this much of the window (body: 60vh); a text as tall as the pane has room for
/// under it.
let fpane_most_tall : Double = 0.6

///|
/// A text's block as guessed before it is laid out.
let fpane_block_est : Double = 400.0

///|
/// What it shows at least 120 high (body), a kind's mark 180 (mark).
let fpane_least : Double = 120.0

///|
let fpane_mark_least : Double = 180.0

///|
/// A kind's mark (56).
let fpane_mark_icon : Double = 56.0

///|
// kept across runs: a value (no field of it changes)
let fpane_box : @ui.Style = @ui.style(w=Fixed(fpane_w), h=Full, p=S3, gap=S3)

///|
// kept across runs: a value (no field of it changes)
let fpane_none_at : @ui.Style = @ui.css("w=Full py=S6")

///|
// kept across runs: a value (no field of it changes)
let fpane_none : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, w=Full, center=true)

///|
/// What it shows (body: the field's corner, on the neutral ground), a picture centred in it, 120 high at least.
// kept across runs: a value (no field of it changes)
let fpane_body_box : @ui.Style = @ui.style(w=Full, min_h=Fixed(fpane_least), py=S6, radius=Xl, bg=Neutral, align=ACenter, justify=JCenter)

///|
// kept across runs: a value (no field of it changes)
let fpane_picture_box : @ui.Style = @ui.style(w=Full, min_h=Fixed(fpane_least), radius=Xl, bg=Neutral, clip=true, align=ACenter, justify=JCenter)

///|
/// While it is read (waiting: 160 of nothing).
// kept across runs: a value (no field of it changes)
let fpane_waiting : @ui.Style = @ui.css("w=Full h=S40")

///|
// kept across runs: a value (no field of it changes)
let fpane_text_box : @ui.Style = @ui.style(w=Full, h=@sf.grow, radius=Xl, bg=Neutral, clip=true)

///|
/// A text's lines (textBox: 10 by 12), Markdown's (prose: 4 by 12).
// kept across runs: a value (no field of it changes)
let fpane_code : @ui.Style = @ui.css("w=Full px=S3 py=S2_5")

///|
// kept across runs: a value (no field of it changes)
let fpane_code_words : @ui.TextStyle = @ui.text_style(size=Caption, color=Fg, w=Full, leading=L4)

///|
// kept across runs: a value (no field of it changes)
let fpane_prose : @ui.Style = @ui.css("w=Full px=S3 py=S1")

///|
// kept across runs: a value (no field of it changes)
let fpane_more : @ui.TextStyle = @ui.text_style(size=Caption, color=Subtle, w=Full)

///|
/// A kind's mark and how to open it, 10 apart, 180 high at least.
// kept across runs: a value (no field of it changes)
let fpane_mark : @ui.Style = @ui.style(w=Full, min_h=Fixed(fpane_mark_least), gap=S2_5, radius=Xl, bg=Neutral, align=ACenter, justify=JCenter)

///|
// kept across runs: a value (no field of it changes)
let fpane_mark_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
/// What the file is (about: 8 between), its name (the ui's words, bold).
// kept across runs: a value (no field of it changes)
let fpane_about : @ui.Style = @ui.css("w=Full gap=S2")

///|
// kept across runs: a value (no field of it changes)
let fpane_name : @ui.TextStyle = @ui.text_style(size=Ui, weight=Semibold, color=Fg, w=Full)

///|
/// Its facts (facts: two columns, 4 by 12 between).
// kept across runs: a value (no field of it changes)
let fpane_facts : @ui.Style = @ui.css("row w=Full gap=S3")

///|
// kept across runs: a value (no field of it changes)
let fpane_facts_column : @ui.Style = @ui.css("gap=S1")

///|
// kept across runs: a value (no field of it changes)
let fpane_values_column : @ui.Style = @ui.style(w=@sf.grow, gap=S1, clip=true)

///|
// kept across runs: a value (no field of it changes)
let fpane_fact_said : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let fpane_fact_value : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, wrap=false)

///|
/// Its path, in the code's letters, on one line (cut where it does not fit).
// kept across runs: a value (no field of it changes)
let fpane_path : @ui.TextStyle = @ui.text_style(size=Caption, color=Fg, wrap=false, max_lines=1, leading=L4)

///|
/// 打开, 下载, 复制路径 (actions: 6 apart, wrapped).
// kept across runs: a value (no field of it changes)
let fpane_actions : @ui.Style = @ui.css("row w=Full gap=S1_5")
