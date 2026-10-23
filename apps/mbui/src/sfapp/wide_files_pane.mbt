// The preview beside a folder's list on the files' page (⌘⇧P, as Finder's preview pane: ember web/src/pages/
// DrivePane.tsx, Drive.tsx usePreviewShown): the row chosen shown there as it is chosen (a picture whole, the start of
// a text, Markdown rendered, code as it is), with what it is, where (its station, its path), its size and its time;
// what plays (a video, a song) or needs a page of its own (a PDF) says how to open it; a folder says so too. Under it
// 打开, 下载, 复制路径. Shown or not is kept on the device (prefs `driveViews.preview`: shown).

///|
/// Whether the preview shows beside the list (prefs `driveViews.preview`, as chosen here until the prefs say).
fn files_previewing(src : Source) -> Bool {
  match wide.files_preview {
    Some(on) => on
    None => text(field((src.topic)("prefs", {}).value, "driveViews"), "preview") == "shown"
  }
}

///|
/// The preview shown or not (`prefs.set {driveViews: {preview}}`).
fn files_set_preview(src : Source, on : Bool) -> Unit {
  wide.files_preview = Some(on)
  (src.call)(
    "prefs.set",
    { "driveViews": { "preview": if on { Json::string("shown") } else { Json::null() } } },
    fn(_) {  },
  )
}

///|
/// A picture is shown whole up to this size (DrivePane.tsx MOST_PICTURE); past it, as the others are, by how to open it.
let fpane_most_picture : Double = 32.0 * 1024.0 * 1024.0

///|
/// The start of a text shown (DrivePane.tsx TEXT_PART).
let fpane_text_part : Int = 64 * 1024

///|
/// What the preview has read of the file shown: by the file (its station, root, path and time), its picture's bytes or
/// its text's start, or that it could not be read.
priv struct FPane {
  mut key : String
  mut picture : String
  mut text : String?
  mut failed : Bool
}

///|
let fpane : FPane = { key: "", picture: "", text: None, failed: false }

///|
fn fpane_reset() -> Unit {
  fpane.key = ""
  fpane.picture = ""
  fpane.text = None
  fpane.failed = false
}

///|
/// The row chosen, when it is in this side's folder or under it: the folder it is in and its entry as listed there.
fn fpane_chosen(src : Source, at : DriveAt, root : String) -> (String, DvEntry, Array[DvEntry])? {
  let parts = files_chosen_now().split("\u{1}").map(fn(p) { p.to_string() }).collect()
  if parts.length() != 3 || parts[0] != at.station || parts[1] != root {
    return None
  }
  let full = parts[2]
  let dir = match full.rev_find("/") {
    Some(i) => full.view(end_offset=i).to_string()
    None => ""
  }
  if at.path != "" && dir != at.path && !dir.has_prefix(at.path + "/") {
    return None
  }
  let name = dv_name(full)
  match files_entries(src, at.station, root, dir) {
    (Some(list), _) =>
      match list.iter().find_first(fn(e) { e.name == name }) {
        Some(e) => Some((dir, e, list))
        None => None
      }
    _ => None
  }
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
  if fpane.key == key {
    return
  }
  fpane_reset()
  fpane.key = key
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
      if fpane.key != key {
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
            fpane.text = Some(words)
          } else if bytes.length() > 0 && now < total {
            next(now)
          } else {
            let whole : Array[Byte] = Array(capacity=now)
            for b in parts {
              for i in 0..<b.length() {
                whole.push(b[i])
              }
            }
            fpane.picture = "mem:files-pane/" + key
            @ui.add_image(fpane.picture, Bytes::from_array(whole[:]))
          }
        }
        Err(_) => fpane.failed = true
      }
    })
  }
  next(0)
}

///|
/// The preview beside a side's list (DrivePane): the row chosen in it, else what to do to see one.
fn files_preview_pane(c : @ui.Ctx, src : Source, st : DvStation, at : DriveAt, root : String, below? : Bool = false) -> Unit {
  // (under the list in a chat's 文件 tab: as wide as it, at most half the window high)
  c.box(style=if below { files_bar_rule } else { files_column_rule }, fn() {  }) |> ignore
  c.box(style=if below { fpane_below } else { fpane_box }, fn() {
    match fpane_chosen(src, at, root) {
      None => c.text(tr("web-pages.files.previewNone"), style=fpane_none) |> ignore
      Some((dir, e, shown)) => {
        let path = dv_join(dir, e.name)
        let abs = dv_absolute(root, path)
        let in_place : DriveAt = { station: at.station, root: Some(root), path: dir }
        let way = fpane_way(e)
        fpane_read(src, at.station, root, path, e, way)
        let open = fn() { drive_open(c, src, in_place, root, e, shown) }
        fpane_body(c, e, way, open, room=c.height * (if below { fpane_below_tall } else { fpane_most_tall }), fixed=below)
        c.box(style=fpane_about, fn() {
          c.text(e.name, style=fpane_name) |> ignore
          // what it is, as a grid of two columns: what is said, then its value
          let facts : Array[(String, String)] = []
          if !e.dir {
            facts.push((tr("web-pages.files.size"), e.size_text))
          }
          facts.push((tr("web-pages.files.modified"), e.time_text))
          facts.push(("Station", st.name))
          facts.push((tr("web-pages.files.where"), abs))
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
            if @sf.button(c, tr("web-pages.drive.open"), key="files/preview/open") {
              open()
            }
            if !e.dir && @sf.button(c, tr("web-pages.drive.download"), key="files/preview/download", tone=Ghost, icon="download") {
              say(c, fill("android-misc.drive.downloading", [("name", e.name)]))
              download_drive_file(c, src, at.station, root, path, e.name, e.mime, listed=Some((e.mtime, e.size)))
            }
            if @sf.button(c, tr("web-pages.drive.copyPath"), key="files/preview/copy", tone=Ghost, icon="copy") {
              c.copy_text(abs)
              say(c, tr("web-pages.drive.pathCopied"))
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
  if fpane.failed {
    c.box(style=fpane_body_box, fn() { c.text(tr("web-pages.files.previewFailed"), style=fpane_none) |> ignore })
    |> ignore
    return
  }
  match way {
    "picture" =>
      c.box(style=fpane_picture_box, fn() {
        if fpane.picture == "" {
          c.box(style=fpane_waiting, fn() {  }) |> ignore
        } else {
          // whole, as large as the pane is wide and no taller than its room
          let (nw, nh) = @ui.image_natural(fpane.picture).unwrap_or((fpane_inner, fpane_inner))
          let s = dmin(fpane_inner / dmax(1.0, nw), room / dmax(1.0, nh))
          let s = dmin(s, 1.0)
          c.image(fpane.picture, w=Px(nw * s), h=Px(nh * s), fit=FitContain, bg=0L) |> ignore
        }
      })
      |> ignore
    "text" =>
      match fpane.text {
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
                    c.text(tr("web-pages.files.previewMore"), style=fpane_more) |> ignore
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
                    c.text(tr("web-pages.files.previewMore"), style=fpane_more) |> ignore
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
      c.cursor(id, Hand)
      if c.clicked(id) {
        open()
      }
      let words = if e.kind == "video" || e.kind == "audio" {
        tr("web-pages.files.previewPlay")
      } else if e.dir {
        tr("web-pages.files.previewFolder")
      } else {
        tr("web-pages.files.previewOpen")
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
let fpane_below : @ui.Style = @ui.style(w=Full, p=S3, gap=S3)

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
let fpane_none : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, w=Full, center=true)

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
let fpane_waiting : @ui.Style = @ui.style(w=Full, h=S40)

///|
// kept across runs: a value (no field of it changes)
let fpane_text_box : @ui.Style = @ui.style(w=Full, h=@sf.grow, radius=Xl, bg=Neutral, clip=true)

///|
/// A text's lines (textBox: 10 by 12), Markdown's (prose: 4 by 12).
// kept across runs: a value (no field of it changes)
let fpane_code : @ui.Style = @ui.style(w=Full, px=S3, py=S2_5)

///|
// kept across runs: a value (no field of it changes)
let fpane_code_words : @ui.TextStyle = @ui.text_style(size=Xs2, color=Fg, w=Full, leading=L4)

///|
// kept across runs: a value (no field of it changes)
let fpane_prose : @ui.Style = @ui.style(w=Full, px=S3, py=S1)

///|
// kept across runs: a value (no field of it changes)
let fpane_more : @ui.TextStyle = @ui.text_style(size=Xs2, color=Subtle, w=Full)

///|
/// A kind's mark and how to open it, 10 apart, 180 high at least.
// kept across runs: a value (no field of it changes)
let fpane_mark : @ui.Style = @ui.style(w=Full, min_h=Fixed(fpane_mark_least), gap=S2_5, radius=Xl, bg=Neutral, align=ACenter, justify=JCenter)

///|
// kept across runs: a value (no field of it changes)
let fpane_mark_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
/// What the file is (about: 8 between), its name (the ui's words, bold).
// kept across runs: a value (no field of it changes)
let fpane_about : @ui.Style = @ui.style(w=Full, gap=S2)

///|
// kept across runs: a value (no field of it changes)
let fpane_name : @ui.TextStyle = @ui.text_style(size=Sm, weight=Semibold, color=Fg, w=Full)

///|
/// Its facts (facts: two columns, 4 by 12 between).
// kept across runs: a value (no field of it changes)
let fpane_facts : @ui.Style = @ui.style(row=true, w=Full, gap=S3)

///|
// kept across runs: a value (no field of it changes)
let fpane_facts_column : @ui.Style = @ui.style(gap=S1)

///|
// kept across runs: a value (no field of it changes)
let fpane_values_column : @ui.Style = @ui.style(w=@sf.grow, gap=S1, clip=true)

///|
// kept across runs: a value (no field of it changes)
let fpane_fact_said : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let fpane_fact_value : @ui.TextStyle = @ui.text_style(size=Xs, color=Fg, wrap=false)

///|
/// Its path, in the code's letters, on one line (cut where it does not fit).
// kept across runs: a value (no field of it changes)
let fpane_path : @ui.TextStyle = @ui.text_style(size=Xs2, color=Fg, wrap=false, max_lines=1, leading=L4)

///|
/// 打开, 下载, 复制路径 (actions: 6 apart, wrapped).
// kept across runs: a value (no field of it changes)
let fpane_actions : @ui.Style = @ui.style(row=true, w=Full, gap=S1_5)
