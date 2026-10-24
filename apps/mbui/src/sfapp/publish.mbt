// A chat made public (ember apps/android chat/screens/Publish.kt; docs/public-share.md; the core's views/publish.ts),
// from its sheet (sheets.mbt chat_info_sheet): its links, and the sheet that publishes it. What a snapshot would hold
// is asked as that sheet opens (`chat.publishPreview`), nothing kept until 发布 (`chat.publish`); a link is revoked
// once asked (`chat.unpublish`), gone from the list at once (the core's).

///|
/// The publishing sheet's state: what it is for, what the preview said (or why not), the attachments left out, the
/// snapshot made.
priv struct Publishing {
  /// the chat it is of (station, thread), as the sheet was opened for it
  mut of : String
  mut preview : Json?
  mut failed : String
  /// left out of the snapshot, by their `k` (all ticked at first)
  off : Map[String, Bool]
  mut made : Json?
}

///|
let publishing : Publishing = { of: "", preview: None, failed: "", off: {}, made: None }

///|
/// As at the start (tests).
fn publish_reset() -> Unit {
  publishing.of = ""
  publishing.preview = None
  publishing.failed = ""
  publishing.off.clear()
  publishing.made = None
}

///|
/// The chat's public links as its sheet shows them (Publish.kt shownPublish): to those who may publish it, or when it
/// has some (a read-only member sees them).
fn shown_publish(chat : Json?) -> Json? {
  match field(chat, "publish") {
    Some(Object(_)) as p if flag(p, "may") || items(p, "links").length() > 0 => p
    _ => None
  }
}

///|
/// What is under way while the snapshot is made (its 发布's spinner).
fn publish_key(station : String, thread : Double) -> String {
  "publish/" + station + "/" + thread.to_int64().to_string()
}

///|
/// The words of a row in the chat's sheet (14, the ink, one line).
// kept across runs: a value (no field of it changes)
let publish_row_words : @ui.TextStyle = @ui.text_style(size=Base, color=Fg, wrap=false)

///|
/// A published link's line: when and by whom (13, muted, one line, taking what the row leaves).
// kept across runs: a value (no field of it changes)
let published_words : @ui.TextStyle = @sf.secondary.then(@sf.one_line).then(@sf.full_words)

///|
/// Making the chat public, a card of its own in its sheet (Publish.kt PublishList): 公开分享 opens the sheet that
/// publishes it, for those who may (not a read-only member); each of its links under it, when and by whom, 复制, and
/// 撤销 for who published it or an owner or admin (asked first; gone from here at once).
fn publish_list(c : @ui.Ctx, src : Source, station : String, thread : Double, p : Json?) -> Unit {
  let t = @sf.theme()
  c.box(style=publish_card_top, fn() { publish_list_rows(c, src, station, thread, p, t) }) |> ignore
}

///|
fn publish_list_rows(c : @ui.Ctx, src : Source, station : String, thread : Double, p : Json?, t : @sf.Theme) -> Unit {
  info_list(c, fn() {
    if flag(p, "may") &&
      info_row(c, "info/publish", fn() {
        @sf.icon(c, "web", size=16.0, color=t.p.text) |> ignore
        c.text(tr("web-pages.chat.publish"), style=publish_row_words.then(@sf.full_words)) |> ignore
        chevron(c)
      }) {
      open_publish(c, src, station, thread)
    }
    for l in items(p, "links") {
      published_row(c, src, station, thread, Some(l))
    }
  })
}

///|
/// One of the chat's links (Publish.kt PublishedRow): how long ago and by whom; 复制; 撤销 when the viewer may.
fn published_row(c : @ui.Ctx, src : Source, station : String, thread : Double, l : Json?) -> Unit {
  let id = text(l, "id")
  info_row(c, "", fn() {
    let said = [text(field(field(l, "time"), "createdAt"), "ago"), text(l, "byName")].filter(fn(s) { s != "" })
    c.text(said.join(" · "), style=published_words) |> ignore
    if text_action(c, "publish/copy/" + id, tr("common.copy")) {
      copy_link(c, text(l, "link"))
    }
    if flag(l, "mayRevoke") && text_action(c, "publish/revoke/" + id, tr("web-pages.chat.publish.revoke")) {
      close_sheet(c)
      @settings.confirm(
        tr("web-pages.chat.publish.revokeAsk"),
        tr("web-pages.chat.publish.revokeNote"),
        tr("web-pages.chat.publish.revoke"),
        fn() {
          act(src, tr("web-pages.chat.publish.revokeVerb"), "", "chat.unpublish", {
            "station": Json::string(station),
            "thread": Json::number(thread),
            "id": Json::string(id),
          })
        },
        danger=true,
      )
    }
  })
  |> ignore
}

///|
/// A link's words as a button, in the link's colour with no frame (Publish.kt TextAction): 14, a little room round
/// them, 6 round when pressed. True on the frame after a tap.
fn text_action(c : @ui.Ctx, key : String, label : String) -> Bool {
  let id = c.id(key)
  c.box(style=text_action_box, id~, fn() {
    c.text(label, style=text_action_words) |> ignore
    // Publish.kt TextAction: clip(Smooth(6)).clickable
    @motion.ripple(c, id, 6.0)
  })
  |> ignore
  c.clicked(id)
}

///|
// kept across runs: a value (no field of it changes)
let text_action_box : @ui.Style = @ui.css("px=S1 py=S0_5 radius=Md")

///|
// kept across runs: a value (no field of it changes)
let text_action_words : @ui.TextStyle = @ui.text_style(size=Base, color=Link, wrap=false)

///|
/// Puts a link on the clipboard, saying so (Publish.kt copyLink).
fn copy_link(c : @ui.Ctx, link : String) -> Unit {
  c.copy_text(link)
  say(c, tr("common.link.copied"))
}

///|
/// Opens the sheet that publishes the chat, asking what a snapshot would hold now (Publish.kt openPublish's
/// `publishPreview`, asked as it opens).
fn open_publish(c : @ui.Ctx, src : Source, station : String, thread : Double) -> Unit {
  publish_reset()
  publishing.of = publish_key(station, thread)
  open_sheet(c, Publish(station, thread))
  ask_preview(src, station, thread)
}

///|
/// What a snapshot would hold (`chat.publishPreview`): its answer for the sheet open for that chat, or why not.
fn ask_preview(src : Source, station : String, thread : Double) -> Unit {
  let of = publish_key(station, thread)
  (src.call)("chat.publishPreview", { "station": Json::string(station), "thread": Json::number(thread) }, fn(res) {
    if publishing.of != of {
      return
    }
    match res {
      Ok(v) => publishing.preview = Some(v)
      Err(e) => publishing.failed = error_words(e)
    }
  })
}

///|
/// Its words 20 in from the sheet's edges (Publish.kt `inset`).
// kept across runs: a value (no field of it changes)
let publish_inset : @ui.Style = @ui.css("w=Full px=S5")

///|
/// The snapshot's messages on a card, as the chat draws others' (22 round, the ink at 4%, 16 and 14 in, 16 apart).
// kept across runs: a value (no field of it changes)
let publish_card : @ui.Style = @ui.style(w=Full, px=S4, py=S3_5, radius=Xl3, bg=@sf.faint_ground, gap=S4)

///|
/// The link made, on the card's ground (22 round, 14 and 10 in).
// kept across runs: a value (no field of it changes)
let publish_link_box : @ui.Style = @ui.style(w=Full, px=S3_5, py=S2_5, radius=Xl3, bg=@sf.faint_ground)

///|
/// Buttons at the sheet's end, 8 apart.
// kept across runs: a value (no field of it changes)
let publish_buttons : @ui.Style = @ui.css("row w=Full gap=S2 justify=JEnd")

///|
// kept across runs: a value (no field of it changes)
let publish_empty_words : @ui.TextStyle = @ui.text_style(size=Base, color=Muted)

///|
/// Publishes the chat (Publish.kt openPublish; web mobile/Chat.tsx PublishSheet): what it would hold, asked as the
/// sheet opened; the attachments to tick (all at first); 发布. Published, its link with a way to copy it; the chat's
/// sheet lists it from then on (the core's).
fn publish_sheet(c : @ui.Ctx, src : Source, station : String, thread : Double) -> Unit {
  let busy = doing(publish_key(station, thread))
  sheet_frame(c, "publish", c.height * 0.9, fn() {
    sheet_head(
      c,
      tr(if publishing.made is Some(_) { "web-pages.chat.publish.made" } else { "web-pages.chat.publish" }),
    )
    let rows : Array[() -> Unit] = [
      fn() {
        c.box(style=publish_inset, fn() {
          c.text(tr("web-pages.chat.publish.lead"), style=@sf.caption.then(@sf.full_words)) |> ignore
        })
        |> ignore
      },
    ]
    match (publishing.made, publishing.preview) {
      (Some(made), _) => {
        let link = text(Some(made), "link")
        rows.push(fn() {
          c.box(style=publish_inset, fn() {
            c.box(style=publish_link_box, fn() {
              c.text(link, style=publish_row_words.then(@sf.full_words)) |> ignore
            })
            |> ignore
          })
          |> ignore
        })
        rows.push(fn() {
          c.box(style=publish_inset, fn() {
            c.box(style=publish_buttons, fn() {
              if @settings.button(c, "publish/done", tr("common.done"), false) {
                close_sheet(c)
              }
              if @settings.button(c, "publish/copy", tr("common.link.copy"), true) {
                copy_link(c, link)
              }
            })
            |> ignore
          })
          |> ignore
        })
      }
      (None, None) =>
        rows.push(fn() {
          c.box(style=publish_inset, fn() {
            if publishing.failed != "" {
              c.text(publishing.failed, style=@sf.secondary.then(@sf.bad).then(@sf.full_words)) |> ignore
            } else {
              @settings.wait_line(c, tr("web-pages.chat.publish.reading"))
            }
          })
          |> ignore
        })
      (None, Some(_) as p) if items(p, "messages").length() == 0 =>
        rows.push(fn() {
          c.box(style=publish_inset, fn() {
            c.text(tr("web-pages.chat.publish.empty"), style=publish_empty_words) |> ignore
          })
          |> ignore
        })
      (None, Some(_) as p) => {
        rows.push(fn() {
          c.box(style=publish_inset, fn() {
            c.box(style=publish_card, fn() {
              for m in items(p, "messages") {
                preview_message(c, src, station, Some(m))
              }
            })
            |> ignore
          })
          |> ignore
        })
        match text(p, "hiddenText") {
          "" => ()
          hidden =>
            rows.push(fn() {
              c.box(style=publish_inset, fn() {
                c.text(hidden, style=@sf.caption.then(@sf.full_words)) |> ignore
              })
              |> ignore
            })
        }
        rows.push(fn() {
          c.box(style=publish_inset, fn() {
            c.box(style=publish_buttons, fn() {
              if @settings.button(c, "publish/go", tr("web-pages.chat.publish.go"), true, busy~) {
                let ticked = items(p, "files")
                  .map(fn(f) { text(Some(f), "k") })
                  .filter(fn(k) { !publishing.off.contains(k) })
                act(
                  src,
                  tr("web-pages.chat.publish.verb"),
                  publish_key(station, thread),
                  "chat.publish",
                  {
                    "station": Json::string(station),
                    "thread": Json::number(thread),
                    "upto": Json::number(number(p, "upto")),
                    "files": Json::array(ticked.map(Json::string(_))),
                  },
                  ok=fn(v) { publishing.made = Some(v) },
                )
              }
            })
            |> ignore
          })
          |> ignore
        })
      }
    }
    // (30 under the last: its 12 and 18 more)
    rows.push(fn() { c.box(style=publish_foot, fn() {  }) |> ignore })
    c.list("publish-sheet/" + station, rows.length(), publish_row_est, fn(i) {
      c.box(style=if i == 0 { publish_first_row } else { publish_row }, fn() { (rows[i])() }) |> ignore
    })
    |> ignore
  })
}

///|
/// A row's height as the list counts it before it is built.
let publish_row_est : Double = 60.0

///|
/// The sheet's rows 12 apart.
// kept across runs: a value (no field of it changes)
let publish_row : @ui.Style = @ui.css("w=Full pb=S3")

///|
/// The first, 4 under the sheet's head.
// kept across runs: a value (no field of it changes)
let publish_first_row : @ui.Style = publish_row.then(@ui.css("pt=S1"))

///|
/// What is left under the last row, with its 12: 30 (Publish.kt's bottom padding).
// kept across runs: a value (no field of it changes)
let publish_foot : @ui.Style = @ui.css("h=S4_5")

///|
/// A message as the snapshot would hold it, drawn as the chat draws someone else's (Publish.kt PreviewMessage;
/// Chat.kt SaidRow): its picture over its head's start, its name and when, what it says (an agent's Markdown), under
/// it its attachments each ticked to go or not, and with something hidden, how many.
fn preview_message(c : @ui.Ctx, src : Source, station : String, m : Json?) -> Unit {
  let n = number(m, "n").to_int64().to_string()
  let agent = flag(m, "agent")
  let author = text(m, "author")
  c.box(style=@sf.full_width, fn() {
    c.box(style=preview_column, fn() {
      said_head(c, author, 0, "publish/" + n, stamp_of(m, "createdAt"))
      let words = text(m, "text")
      if agent {
        @sf.markdown(c, words, key="publish/md/" + n, ink=ink().text, on_link=open_link) |> ignore
      } else if words != "" {
        person_words(c, words, "publish/" + n)
      }
      let files = items(m, "files")
      if files.length() > 0 {
        snapshot_files(c, src, station, files)
      }
      match text(m, "hiddenText") {
        "" => ()
        hidden =>
          c.box(style=hidden_line, fn() {
            @sf.icon(c, "shield-check", size=13.0, color=@sf.theme().p.muted) |> ignore
            c.text(hidden, style=@sf.caption) |> ignore
          })
          |> ignore
      }
    })
    |> ignore
    c.layer(fn() {
      said_avatar(c, fn() {
        if agent {
          let maker = field(m, "maker")
          agent_avatar(c, text(maker, "id"), text(m, "runtime"))
        } else {
          avatar(c, src, author, author, text(m, "picture"), avatar_size)
        }
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A person's picture in a message (Parts.kt Avatar at 18).
let avatar_size : Double = 18.0

///|
/// A message's head over what it says, 4 apart (Publish.kt PreviewMessage's Column).
// kept across runs: a value (no field of it changes)
let preview_column : @ui.Style = @ui.css("w=Full gap=S1")

///|
/// Its attachments in rows as wide as the card (FlowRow: 6 apart each way), 2 under its words.
fn snapshot_files(c : @ui.Ctx, src : Source, station : String, files : Array[Json]) -> Unit {
  // the card's room: the sheet's less its insets (20) and the card's (16)
  let room = c.width - 72.0
  let widths = files.map(fn(f) { if is_picture(Some(f)) { toggle_image_w } else { dmin(file_card_w, room) } })
  c.box(style=preview_file_flow, flow=true, fn() {
    for i, f in files {
      file_toggle(c, src, station, Some(f), widths[i])
    }
  })
  |> ignore
}

///|
/// An image's box in the preview (Publish.kt FileToggle: 160 wide, its own proportions).
let toggle_image_w : Double = 160.0

///|
/// The attachments in lines, 6 apart each way, 2 under the words (Publish.kt: a FlowRow).
// kept across runs: a value (no field of it changes)
let preview_file_flow : @ui.Style = @ui.css("row w=Full pt=S0_5 gap=S1_5")

///|
/// Whether an attachment is drawn as its picture: an image its station keeps (its owner known).
fn is_picture(f : Json?) -> Bool {
  kind_of(text(f, "name")) == "image" && text(field(f, "file"), "owner") != ""
}

///|
/// An attachment in the preview as the chat shows it (Publish.kt FileToggle; web Publish.tsx): an image's box, else
/// its card, with the app's checkbox in its top right corner; a tap anywhere on it ticks or unticks it (nothing
/// opens), unticked it fades.
fn file_toggle(c : @ui.Ctx, src : Source, station : String, f : Json?, w : Double) -> Unit {
  let k = text(f, "k")
  let on = !publishing.off.contains(k)
  let a = match field(f, "file") {
    Some(file) => attachment_of(file)
    None => attachment_of(Json::object({}))
  }
  let id = c.id("publish/file/" + k)
  if c.clicked(id) {
    if on {
      publishing.off[k] = true
    } else {
      publishing.off.remove(k)
    }
  }
  c.box(style=if on { toggle_on } else { toggle_off }, id~, fn() {
    if is_picture(f) {
      let (bw, bh, _) = image_box(a, 16.0)
      let key = (src.file)(station, a.owner, base_name(a.path))
      c.box(style=toggle_picture, aspect=bw / bh, fn() {
        if key != "" && key != "!" {
          c.image(key, w=Fill(1.0), h=Fill(1.0), fit=FitCover, bg=0L) |> ignore
        } else {
          match @gallery.thumbhash_image(a.thumbhash) {
            Some(likeness) => c.image(likeness, w=Fill(1.0), h=Fill(1.0), fit=FitCover, bg=0L, fade=false) |> ignore
            None => ()
          }
        }
      })
      |> ignore
    } else {
      file_card(c, a, w)
    }
    // the app's checkbox (web global.css.ts): a soft square, the ink with a check when ticked, 4 in from the corner
    c.layer(fn() {
      c.box(style=tick_place, fn() {
        c.box(style=if on { tick_on } else { tick_off }, fn() {
          if on {
            @sf.icon(c, "check", size=12.0, color=@sf.theme().p.bg) |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// An attachment's box: its corner 8 (a file's card's), what is in it clipped to it; unticked, faded.
// kept across runs: a value (no field of it changes)
let toggle_on : @ui.Style = @ui.css("radius=Lg clip")

///|
// kept across runs: a value (no field of it changes)
let toggle_off : @ui.Style = toggle_on.then(@ui.css("opacity=O45"))

///|
/// An image's box in the preview, 160 wide (its height its proportions'), on the chip's grey until it is here.
// kept across runs: a value (no field of it changes)
let toggle_picture : @ui.Style = @ui.css("w=S40 bg=Neutral")

///|
/// Where the checkbox sits: the box's top right, 4 in.
// kept across runs: a value (no field of it changes)
let tick_place : @ui.Style = @ui.css("row w=Full p=S1 justify=JEnd")

///|
/// The checkbox, 18 square, concentric with the box's corner; the ink when ticked, the page's ground with a line when
/// not.
// kept across runs: a value (no field of it changes)
let tick_on : @ui.Style = @ui.css(
  #|w=S4_5 h=S4_5 radius=Inner bg=Fg border=B1 border_color=Fg align=ACenter justify=JCenter
)

///|
// kept across runs: a value (no field of it changes)
let tick_off : @ui.Style = tick_on.then(@ui.css("bg=Bg border_color=Line"))

///|
/// What was hidden, in a line: the shield and its words, 6 apart.
// kept across runs: a value (no field of it changes)
let hidden_line : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
/// The publishing card 10 under the chat's actions (ChatInfo.kt: Spacer 10).
// kept across runs: a value (no field of it changes)
let publish_card_top : @ui.Style = @ui.css("w=Full pt=S2_5")
