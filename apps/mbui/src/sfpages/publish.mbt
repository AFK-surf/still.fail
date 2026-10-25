// A chat made public (docs/public-share.md; ember web/src/Publish.tsx PublishDialog, PublishMessages, FileToggle;
// Publish.css.ts, FilePreview.css.ts fp; the phone's PublishSheet in mobile/Chat.tsx, the same preview), one on every
// screen: from its info's 公开分享, over the whole window as a file is previewed, what a snapshot would hold now
// (`chat.publishPreview`, asked as it opens: nothing is kept until it is published) laid out as the chat lays out
// messages, each attachment where its message has it, pressed anywhere to tick it or not (all at first: FileToggle's
// label); a bar floating at the top, under the system's, with how much was hidden, 发布 and close. Published
// (`chat.publish`), its link to copy in a small panel (the presenters': a sheet on a touch device short of Large); the
// chat's info lists it from then on. Which files an agent's words place, and those words as Markdown, are the core's
// (the preview's `placed`, `md`). The frames draw it over their pages (publish_layer).

///|
/// The publishing as it stands: the chat it is of and its thread (None: closed), the preview as read (0 being read,
/// 1 read, 2 not: `error` says why), the attachments left out (by their `k`), being published.
priv struct Publishing {
  mut of : (ChatRef, Double)?
  mut read : Int
  mut preview : Json?
  mut error : String
  off : Map[String, Bool]
  mut busy : Bool
}

///|
let publishing : Publishing = {
  of: None,
  read: 0,
  preview: None,
  error: "",
  off: {},
  busy: false,
}

///|
pub fn publish_reset() -> Unit {
  publishing.of = None
  publishing.read = 0
  publishing.preview = None
  publishing.error = ""
  publishing.off.clear()
  publishing.busy = false
}

///|
/// Opened for chat `r`'s `thread`: what a snapshot would hold asked now (usePublishPreview).
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
/// Chat `r`'s `thread` being published, `preview` read (a screen's fixture).
pub fn publish_set(r : ChatRef, thread : Double, preview : Json) -> Unit {
  publish_reset()
  publishing.of = Some((r, thread))
  publishing.preview = Some(preview)
  publishing.read = 1
}

///|
/// Whether attachment `k` is left out of the snapshot (tests).
pub fn publish_left_out(k : String) -> Bool {
  publishing.off.contains(k)
}

///|
/// Published (`chat.publish`): up to the message the preview ended at, with the attachments ticked; its link in the
/// small dialog that follows, why not said.
fn publish_go(src : Source, r : ChatRef, thread : Double, p : Json?) -> Unit {
  let ticked = items(p, "files").map(fn(f) { text(Some(f), "k") }).filter(fn(k) { !publishing.off.contains(k) })
  publishing.busy = true
  act(
    src,
    @sf.t("web-pages.chat.publish.verb"),
    "",
    "chat.publish",
    {
      "station": Json::string(r.station),
      "thread": Json::number(thread),
      "upto": Json::number(number(p, "upto")),
      "files": Json::array(ticked.map(Json::string(_))),
    },
    ok=fn(v) {
      publish_reset()
      publish_made(text(Some(v), "link"))
    },
    failed=fn() { publishing.busy = false },
  )
}

///|
/// The page that publishes it, while it is open, over the frame's pages (under the presenters and the toasts).
pub fn publish_layer(c : @ui.Ctx, src : Source) -> Unit {
  match publishing.of {
    Some((r, thread)) => publish_page(c, src, r, thread)
    None => ()
  }
}

///|
/// Published (PublishDialog's `made`): 已公开分享, who can read it, its link as a one-line field shows it; 完成 and 复制链接.
fn publish_made(link : String) -> Unit {
  @sf.panel(
    @sf.t("web-pages.chat.publish.made"),
    fn(c, _) { c.box(style=publish_made_link, fn() { c.text(link, style=publish_made_words) |> ignore }) |> ignore },
    from=Unanchored,
    description=@sf.t("web-pages.chat.publish.lead"),
    wide=true,
    foot=fn(c, close) {
      if @sf.button(c, @sf.t("common.done"), key="publish-made/done", tone=Ghost) {
        close()
      }
      if @sf.button(c, @sf.t("web-pages.chat.publish.copyLink"), key="publish-made/copy", tone=Primary, icon="copy") {
        c.copy_text(link)
        toast_later(@sf.t("common.link.copied"))
      }
    },
  )
}

///|
/// The page that publishes it (PublishDialog): over the whole window on the canvas, its bar floating at its top
/// (公开分享, how much was hidden, 发布, close), what it would hold under it at the chat's width; Esc closes it.
fn publish_page(c : @ui.Ctx, src : Source, r : ChatRef, thread : Double) -> Unit {
  let p = publishing.preview
  let messages = items(p, "messages")
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
                c.text(@sf.t("web-pages.chat.publish.lead"), style=publish_lead) |> ignore
                let here : MessageHere = {
                  station: r.station,
                  session: r.session,
                  view: @sfbase.chat_view((src.topic)("chat", chat_params(r)).value.unwrap_or(Json::null())),
                  go: None,
                  inline: true,
                  list: None,
                  core: None,
                }
                // (the column's words' width: the window's on a phone)
                let room = dmin(c.width, publish_page_w) - 2.0 * publish_page_in
                for m in messages {
                  publish_message(c, src, here, Some(m), room)
                }
              })
              |> ignore
            })
            |> ignore
          })
          |> ignore
      }
      // its bar, floating at the top (fpHead with Publish.css.ts head: a pill, 20 in at its start, 4 at its end)
      c.layer(fn() {
        c.box(style=publish_bar_room.then(@ui.style(pt=@sf.system_top_room(publish_bar_top))), fn() {
          c.box(style=publish_bar, glass=@sf.glass_floating(), fn() {
            c.text(@sf.t("web-pages.chat.publish"), style=publish_name) |> ignore
            match text(p, "hiddenText") {
              "" => ()
              hidden =>
                // (where the bar has not the room, a phone's in English, left out: each message says its own)
                c.box(style=publish_head_note, drop=publish_drop_note, fn() {
                  @sf.icon(c, "shield-check", size=publish_note_icon, color=@sf.theme().p.muted) |> ignore
                  c.text(hidden, style=publish_meta) |> ignore
                })
                |> ignore
            }
            if @sf.button(
                c,
                @sf.t("web-pages.chat.publish.go"),
                key="publish/go",
                tone=Primary,
                busy=publishing.busy,
                disabled=p is None || messages.length() == 0,
              ) {
              publish_go(src, r, thread, p)
            }
            let close = c.id("publish/close")
            if @sf.icon_button(c, "close", key="publish/close", round=true, label=@sf.t("common.close")) {
              publish_reset()
            }
            @sf.tip(c, "publish/close-tip", close, @sf.t("web-main.preview.closeKey"))
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  if o.dismissed is Some(_) && !publishing.busy {
    publish_reset()
  }
}

///|
/// A snapshot's message as the chat draws others' (PreviewMessage: each one's head in line with its avatar): an agent's
/// Markdown with the attachments its words place where they place them, a person's as written; the rest under it,
/// each to tick; under one with something hidden, how many.
fn publish_message(c : @ui.Ctx, src : Source, here : MessageHere, m : Json?, room : Double) -> Unit {
  let n = number(m, "n").to_int64().to_string()
  let agent = flag(m, "agent")
  let files = items(m, "files")
  let placed = items(m, "placed").map(fn(x) { match x { String(s) => s; _ => "" } })
  let named : Map[String, Json] = {}
  for f in files {
    named[text(Some(f), "name")] = f
  }
  let under = files.filter(fn(f) { !placed.contains(text(Some(f), "name")) })
  others_message(
    c,
    true,
    "publish/" + n,
    @sfbase.stamp_of(m, "createdAt"),
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
              named.get(name).map(fn(f) { fn() { publish_file(c, src, here, f, room) } })
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
            publish_file(c, src, here, f, room)
          }
        })
        |> ignore
      }
      match text(m, "hiddenText") {
        "" => ()
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
/// An attachment in the preview, as the chat shows it (FileToggle): ticked (its box at its end), it goes
/// with the snapshot; unticked, it fades. Its box at its end, half way down (publish_tick).
fn publish_file(c : @ui.Ctx, src : Source, here : MessageHere, f : Json, room : Double) -> Unit {
  let k = text(Some(f), "k")
  let on = !publishing.off.contains(k)
  let a = @sfbase.attachment_of(field(Some(f), "file").unwrap_or(Json::null()))
  // as wide as the chat draws it (message_files.mbt: an image's box, a file's card), the column's at most (`room`)
  let w = match file_kind(a.name) {
    "image" => dmin(image_box(a, image_least).0, room)
    "video" => dmin(image_box(a, video_least).0, room)
    _ => dmin(@sf.file_card_w, room)
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
  c.cursor(id, Hand)
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
let publish_note_icon : Double = 14.0

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
let publish_note_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted)

///|
// kept across runs: a value (no field of it changes)
let publish_problem : @ui.TextStyle = @ui.text_style(size=Sm, color=Danger)

///|
/// What it would hold (page): the chat's width (760 at most) in the middle, 84 down, 32 in, 96 under, 16 apart.
// kept across runs: a value (no field of it changes)
let publish_column_room : @ui.Style = @ui.css("w=Full align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let publish_column : @ui.Style = @ui.css("w=Full px=S8 pb=S24 gap=S4").then(@ui.style(max_w=Fixed(publish_page_w)))

///|
/// What it would hold starts 80 under the window's top (the bar over it), under the system's bar where there is one.
let publish_page_top : Double = 80.0

///|
let publish_page_w : Double = 760.0

///|
/// How far in its words are (page: 32 each side).
let publish_page_in : Double = 32.0

///|
/// Who can read it (lead: the ui's size, muted).
// kept across runs: a value (no field of it changes)
let publish_lead : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, w=Full)

///|
/// The bar's place: in the middle.
// kept across runs: a value (no field of it changes)
let publish_bar_room : @ui.Style = @ui.css("w=Full px=S4 align=ACenter")

///|
/// The bar's 16 under the window's top, under the system's bar where there is one (a phone's).
let publish_bar_top : Double = 16.0

///|
/// The bar (fpHead, Publish.css.ts head): 44 high, a pill, 20 in at its start and 4 at its end, its parts 12 apart, a
/// line round it and a shadow under it.
// kept across runs: a value (no field of it changes)
let publish_bar : @ui.Style = @ui.css("row max_w=Full h=S11 pl=S5 pr=S1 gap=S3 radius=Full align=ACenter border=B1 border_color=Line shadow=Md")

///|
/// What was hidden, beside its name, is the first to give way where the bar has not the room (a phone's, in English):
/// left out whole (each message under says its own), 发布 and close never.
let publish_drop_note : Int = 1


///|
// kept across runs: a value (no field of it changes)
let publish_name : @ui.TextStyle = @ui.text_style(size=Base, weight=Semibold, color=Fg, wrap=false)

///|
/// How much was hidden (headNote, note: its shield 4 or 6 before it, the meta's size, muted).
// kept across runs: a value (no field of it changes)
let publish_head_note : @ui.Style = @ui.css("row gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let publish_meta : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

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

///|
/// The link once published (madeLink: a pill 40 high, 18 in, on the card's ground, cut short at its end).
// kept across runs: a value (no field of it changes)
let publish_made_link : @ui.Style = @ui.css("w=Full h=S10 px=S4_5 radius=Full bg=Card justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let publish_made_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Fg, wrap=false, max_lines=1)
