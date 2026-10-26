// A chat shared as a picture (2026-10-26 用户：「静态分享功能改成分享图片吧，把内容直接渲染成一张长图」; ember
// web/src/Publish.tsx PublishDialog, PublishMessages, FileToggle; Publish.css.ts, FilePreview.css.ts fp; the phone's
// PublishSheet in mobile/Chat.tsx, the same), one on every screen: from its info's 分享图片, over the whole window as a
// file is previewed, the picture as it would be (`chat.publishPreview`, asked as it opens: what the chat holds now,
// what looks like a secret in it hidden): the chat's name, its messages laid out as the chat lays out messages, each
// attachment where its message has it, pressed anywhere to tick it or not (all at first: FileToggle's label), and
// still.fail's mark at its foot; over it the bar every file opened over the window has (the library's
// viewer_frame_bar: across the top, back to the chat by its name, 分享图片 and how much was hidden, its tool; on a
// small screen floating, the tool and close), its one tool 复制图片 (on a phone 保存到相册: picture_out), as a picture
// opened has its copy (2026-10-26 用户 of the button filled in a pill of its own: 「太不对劲了」). Pressed, the picture
// is drawn whole off the screen as one long picture
// (Ctx::shot), the attachments left out not in it, nor the ticks and the notes of what was hidden that are for the one
// sharing it, its times as dates; then handed out. Which files an agent's words place, and those words as Markdown, are
// the core's (the preview's `placed`, `md`). The frames draw it over their pages (publish_layer). (A link once made of
// a chat, docs/public-share.md, is made no more; those made still open, and its info lists them.)

///|
/// The sharing as it stands: the chat it is of and its thread (None: closed), the preview as read (0 being read, 1
/// read, 2 not: `error` says why), the attachments left out (by their `k`), its picture being taken, how wide its
/// floating bar has been (it only grows: viewer_frame_bar).
priv struct Publishing {
  mut of : (ChatRef, Double)?
  mut read : Int
  mut preview : Json?
  mut error : String
  off : Map[String, Bool]
  mut busy : Bool
  mut head_w : Double
  mut copied : Int
}

///|
let publishing : Publishing = {
  of: None,
  read: 0,
  preview: None,
  error: "",
  off: {},
  busy: false,
  head_w: 0.0,
  copied: 0,
}

///|
pub fn publish_reset() -> Unit {
  publishing.of = None
  publishing.read = 0
  publishing.preview = None
  publishing.error = ""
  publishing.off.clear()
  publishing.busy = false
  publishing.head_w = 0.0
  publishing.copied = 0
}

///|
/// Opened for chat `r`'s `thread`: what the picture would hold asked now (usePublishPreview).
pub fn open_publish(src : Source, r : ChatRef, thread : Double) -> Unit {
  publish_reset()
  publishing.of = Some((r, thread))
  (src.call)("chat.publishPreview", { "station": Json::string(r.station), "thread": Json::number(thread) }, fn(res) {
    match publishing.of {
      Some((o, th)) if o.station == r.station && th == thread =>
        match res {
          Ok(v) => {
            publishing.preview = Some(v)
            publishing.read = 1
          }
          Err(e) => {
            publishing.error = error_words(e)
            publishing.read = 2
          }
        }
      _ => ()
    }
  })
}

///|
/// Chat `r`'s `thread` being shared, `preview` read (a screen's fixture).
pub fn publish_set(r : ChatRef, thread : Double, preview : Json) -> Unit {
  publish_reset()
  publishing.of = Some((r, thread))
  publishing.preview = Some(preview)
  publishing.read = 1
}

///|
/// Whether attachment `k` is left out of the picture (tests).
pub fn publish_left_out(k : String) -> Bool {
  publishing.off.contains(k)
}

///|
/// The picture's shot (Ctx::shot).
let publish_shot : String = "publish/picture"

///|
/// The picture taken (the attachments ticked in it, nothing else of the page's), then handed out as its tool says:
/// copied, its tool a check a moment (as a picture opened says its copy), else what came of it said.
fn publish_go(c : @ui.Ctx) -> Unit {
  publishing.busy = true
  c.take_shot(publish_shot, fn(png) {
    publishing.busy = false
    let (_, icon) = picture_out_way()
    if picture_out(c, png, copy_said=icon == "copy") && icon == "copy" {
      publishing.copied += 1
    }
  })
}

///|
/// The page that shares it, while it is open, over the frame's pages (under the presenters and the toasts).
pub fn publish_layer(c : @ui.Ctx, src : Source) -> Unit {
  match publishing.of {
    Some((r, thread)) => publish_page(c, src, r, thread)
    None => ()
  }
}

///|
/// The page that shares it (PublishDialog): over the whole window on the canvas, the bar a file opened has over it
/// (分享图片, how much was hidden, 复制图片; back or close), the picture as it would be under it at the chat's width; Esc
/// closes it. While its picture is taken, the picture drawn whole off the screen.
fn publish_page(c : @ui.Ctx, src : Source, r : ChatRef, thread : Double) -> Unit {
  let p = publishing.preview
  let messages = items(p, "messages")
  let here : MessageHere = {
    station: r.station,
    session: r.session,
    view: match @sfbase.view_of_chat(src, r).0 {
      Some(v) => v
      None => @sfbase.chat_view_made(Json::null())
    },
    go: None,
    inline: true,
    gutter: 0.0,
    list: None,
    core: None,
  }
  // (the column's width: the window's on a phone)
  let column = dmin(c.width, publish_page_w)
  let o = c.overlay("publish", modal=true, scrim=@sf.theme().p.bg, fn() {
    c.box(style=publish_fill, fn() {
      match publishing.read {
        0 => c.box(style=publish_note, fn() { @sf.wait_line(c, @sf.t("web-pages.chat.publish.reading"), key="publish/reading") }) |> ignore
        2 => c.box(style=publish_note, fn() { c.text(publishing.error, style=publish_problem) |> ignore }) |> ignore
        _ if messages.length() == 0 =>
          c.box(style=publish_note, fn() { c.text(@sf.t("web-pages.chat.publish.empty"), style=publish_note_words) |> ignore })
          |> ignore
        _ =>
          c.list("publish/page/" + r.station + "/" + thread.to_string(), 1, c.height, fn(_) {
            c.box(style=publish_column_room, fn() {
              c.box(style=publish_column.then(@ui.style(pt=@sf.system_top_room(publish_page_top))), fn() {
                publish_picture(c, src, here, p, column, false)
              })
              |> ignore
            })
            |> ignore
          })
          |> ignore
      }
      // its bar, as a file's opened over the window: across the top (back to the chat), or floating on a small screen
      c.layer(fn() {
        let ink = @sf.page_viewer_ink()
        let (closed, wide) = @sf.viewer_frame_bar(
          c,
          "publish",
          if r.title != "" { r.title } else { @sf.t("common.close") },
          @sf.t("web-pages.chat.shareImage"),
          text(p, "hiddenText"),
          false,
          true,
          publishing.head_w,
          1.0,
          ink,
          fn() {
            if p is Some(_) && messages.length() > 0 {
              let (label, icon) = picture_out_way()
              // (copied: a check a moment after, as a picture opened says its copy)
              let shown = publishing.copied > 0 &&
                !@kit.after(c, "publish/copied/\{publishing.copied}", true, @sf.copied_ms)
              if @sf.viewer_tool(
                  c,
                  "publish/go",
                  if shown { "check" } else { icon },
                  if shown { @sf.t("common.copied") } else { label },
                  ink,
                  disabled=publishing.busy,
                ) {
                publish_go(c)
              }
            }
          },
        )
        if wide > publishing.head_w {
          publishing.head_w = wide
        }
        if closed {
          publish_reset()
        }
      })
      |> ignore
    })
    |> ignore
    // the picture itself, while it is taken: the same, all of it, off the screen
    if messages.length() > 0 {
      c.shot(publish_shot, column, fn() { publish_picture(c, src, here, p, column, true) })
    }
  })
  if o.dismissed is Some(_) && !publishing.busy {
    publish_reset()
  }
}

///|
/// The picture, `w` wide (as it is taken: `taking`; else as the page shows it): on the page's ground, the chat's name
/// over its messages, still.fail's mark and name at its foot.
fn publish_picture(c : @ui.Ctx, src : Source, here : MessageHere, p : Json?, w : Double, taking : Bool) -> Unit {
  // (the column's words' width)
  let room = w - 2.0 * publish_page_in
  c.box(style=publish_paper, fn() {
    match text(p, "title") {
      "" => ()
      title => c.text(title, style=publish_title) |> ignore
    }
    for m in items(p, "messages") {
      publish_message(c, src, here, Some(m), room, taking)
    }
    c.box(style=publish_foot, fn() {
      @sf.drawable(c, if @sf.theme().dark { "stillfail_mark_dark" } else { "stillfail_mark" }, publish_mark) |> ignore
      c.text("still.fail", style=publish_brand) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A message of the picture's as the chat draws others' (PreviewMessage: each one's head in line with its avatar): an
/// agent's Markdown with the attachments its words place where they place them, a person's as written; the rest under
/// it. On the page each attachment to tick, and under one with something hidden how many; in the picture taken
/// (`taking`) only those ticked, as the chat shows them, and its time a date (how long ago it was is not so for long).
fn publish_message(c : @ui.Ctx, src : Source, here : MessageHere, m : Json?, room : Double, taking : Bool) -> Unit {
  let n = number(m, "n").to_int64().to_string()
  let agent = flag(m, "agent")
  let files = items(m, "files").filter(fn(f) { !taking || !publishing.off.contains(text(Some(f), "k")) })
  let placed = items(m, "placed").map(fn(x) { match x { String(s) => s; _ => "" } })
  let named : Map[String, Json] = {}
  for f in files {
    named[text(Some(f), "name")] = f
  }
  let under = files.filter(fn(f) { !placed.contains(text(Some(f), "name")) })
  let time = match @sfbase.stamp_of(m, "createdAt") {
    Some(s) if taking => Some({ ..s, ago: s.full })
    s => s
  }
  others_message(
    c,
    true,
    "publish/" + n,
    time,
    fn() {
      if agent {
        agent_avatar(c, src, here, "publish/" + n, text(field(m, "maker"), "id"), text(m, "runtime"), "", "")
      } else {
        person_avatar(c, src, text(m, "author"), text(m, "author"), text(m, "picture"))
      }
    },
    fn() { c.box(style=msg_name_room, fn() { c.text(text(m, "author"), style=msg_name) |> ignore }) |> ignore },
    None,
    fn() {
      if agent {
        @sf.markdown(
          c,
          text(m, "text"),
          tree=field(m, "md"),
          key="publish-md/" + n,
          size=body_size,
          files=fn(name) {
            if placed.contains(name) {
              named.get(name).map(fn(f) -> @sf.Placed {
                let a = @sfbase.attachment_of(field(Some(f), "file").unwrap_or(Json::null()))
                {
                  draw: fn() { publish_file(c, src, here, f, room, taking) },
                  image: image_ratio(a).map(fn(r) { (r, fn(w) { publish_file(c, src, here, f, w, taking) }) }),
                }
              })
            } else {
              None
            }
          },
        )
        |> ignore
      } else {
        person_words(c, text(m, "text"), "publish/" + n)
      }
      if under.length() > 0 {
        c.box(style=publish_files, fn() {
          for f in under {
            publish_file(c, src, here, f, room, taking)
          }
        })
        |> ignore
      }
      match text(m, "hiddenText") {
        "" => ()
        _ if taking => ()
        hidden =>
          c.box(style=publish_head_note, fn() {
            @sf.icon(c, "shield-check", size=publish_note_icon_small, color=@sf.theme().p.muted) |> ignore
            c.text(hidden, style=publish_meta) |> ignore
          })
          |> ignore
      }
    },
  )
}

///|
/// An attachment in the picture, as the chat shows it (FileToggle). On the page, ticked (its box at its end, half
/// way down: publish_tick) it goes in the picture; unticked, it fades. In the picture taken, as it is.
fn publish_file(c : @ui.Ctx, src : Source, here : MessageHere, f : Json, room : Double, taking : Bool) -> Unit {
  let k = text(Some(f), "k")
  let on = !publishing.off.contains(k)
  let a = @sfbase.attachment_of(field(Some(f), "file").unwrap_or(Json::null()))
  // as wide as the chat draws it (message_files.mbt: an image's box, a file's card), the column's at most (`room`)
  let w = match file_kind(a.name) {
    "image" => dmin(image_box(a, image_least).0, room)
    "video" => dmin(image_box(a, video_least).0, room)
    _ => dmin(@sf.file_card_w, room)
  }
  if taking {
    c.box(style=publish_file_box.then(@ui.style(w=Fixed(w))), fn() { message_files(c, src, here, [a], false) }) |> ignore
    return
  }
  let toggle = fn(now : Bool) {
    if now {
      publishing.off.remove(k)
    } else {
      publishing.off[k] = true
    }
  }
  // (pressed anywhere, ticked or not: FileToggle is a label round the file and its box)
  let id = c.id("publish/file/" + k)
  let mut ticked = false
  let card = c.box(style=publish_file_box.then(@ui.style(w=Fixed(w))), fn() {
    message_files(c, src, here, [a], false)
    // (over the file, taking its presses: what the chat would open it by does not here)
    c.layer(fn() {
      c.box(style=publish_tick, id~, fn() {
        let now = @kit.checkbox(c, "publish/tick/" + k, if on { On } else { Off }, label=text(Some(f), "name")).value
        if (now == On) != on {
          ticked = true
          toggle(now == On)
        }
      })
      |> ignore
    })
    |> ignore
  })
  if !ticked && c.clicked(id) {
    toggle(!on)
  }
  if !on {
    c.look(card, @ui.look(alpha=publish_off_alpha))
  }
}

///|
/// An attachment left out (file[data-off]: .45); the shield before how much was hidden, in the bar (14) and under a
/// message (13).
let publish_off_alpha : Double = 0.45

///|
let publish_note_icon_small : Double = 13.0

///|
/// The page over the whole window (fp): the canvas.
// kept across runs: a value (no field of it changes)
let publish_fill : @ui.Style = @ui.css("w=Full h=Full bg=Bg")

///|
/// Being read, not read, nothing to hold (fpNote: in the middle, muted, the ui's size).
// kept across runs: a value (no field of it changes)
let publish_note : @ui.Style = @ui.css("w=Full h=Full align=ACenter justify=JCenter gap=S3_5")

///|
// kept across runs: a value (no field of it changes)
let publish_note_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted)

///|
// kept across runs: a value (no field of it changes)
let publish_problem : @ui.TextStyle = @ui.text_style(size=Ui, color=Danger)

///|
/// What it would hold (page): the chat's width (760 at most) in the middle, 80 down (the bar over it), 96 under.
// kept across runs: a value (no field of it changes)
let publish_column_room : @ui.Style = @ui.css("w=Full align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let publish_column : @ui.Style = @ui.css("w=Full pb=S24").then(@ui.style(max_w=Fixed(publish_page_w)))

///|
/// The picture (page): its words 32 in, 32 down from its top and up from its foot, its parts 16 apart, on the page's
/// ground (what it is drawn on when it is taken too).
// kept across runs: a value (no field of it changes)
let publish_paper : @ui.Style = @ui.css("w=Full px=S8 py=S8 gap=S4 bg=Bg")

///|
/// The chat's name over its messages (the chat's bar's title, its size).
// kept across runs: a value (no field of it changes)
let publish_title : @ui.TextStyle = @ui.text_style(size=Title, weight=Semibold, color=Fg, w=Full)

///|
/// still.fail's mark and name at its foot, 6 apart, 8 under the last message, muted.
// kept across runs: a value (no field of it changes)
let publish_foot : @ui.Style = @ui.css("row pt=S2 gap=S1_5 align=ACenter")

///|
let publish_mark : Double = 16.0

///|
// kept across runs: a value (no field of it changes)
let publish_brand : @ui.TextStyle = @ui.text_style(size=Meta, weight=Medium, color=Muted, wrap=false)

///|
/// Where the picture starts on the page: 80 under the window's top (the bar over it, 45 across the top or 60 floating
/// down to its foot), under the system's bar where there is one; its own 32 in that.
let publish_page_top : Double = 48.0

///|
let publish_page_w : Double = 760.0

///|
/// How far in its words are (page: 32 each side).
let publish_page_in : Double = 32.0

///|
/// How much was hidden (headNote, note: its shield 4 or 6 before it, the meta's size, muted).
// kept across runs: a value (no field of it changes)
let publish_head_note : @ui.Style = @ui.css("row gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let publish_meta : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
/// The attachments under a message (files: 8 apart, 6 under its words), each as wide as the chat draws it.
// kept across runs: a value (no field of it changes)
let publish_files : @ui.Style = @ui.css("w=Full gap=S2 pt=S1_5 align=AStart")

///|
/// An attachment to tick (file), its box at its end (tick).
// kept across runs: a value (no field of it changes)
let publish_file_box : @ui.Style = @ui.css("align=AStart")

///|
/// Its box (tick): at its end, half way down, the ladder's inset in: where a file card's own buttons are on the web
/// (FileCard's fileCardAction: download's ✕, retry's ↻), so the box to tick stands where the card's action does.
// kept across runs: a value (no field of it changes)
let publish_tick : @ui.Style = @ui.css("w=Full h=Full pr=S2_5 align=AEnd justify=JCenter")
