// A chat shared, as its sheet lists it (web/src/mobile/Chat.tsx PublishList, PublishedRow): 分享图片 opens the sharing
// (sfpages' publish.mbt, one on every screen: the chat drawn as one long picture), and under it each public link made
// of it before pictures (docs/public-share.md: still open), 复制 and 撤销 (`chat.unpublish`, asked first; gone from the
// list at once: the core's).

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
/// The words of a row in the chat's sheet (14, the ink, one line).
// kept across runs: a value (no field of it changes)
let publish_row_words : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, wrap=false)

///|
/// A published link's line: when and by whom (13, muted, one line, taking what the row leaves).
// kept across runs: a value (no field of it changes)
let published_words : @ui.TextStyle = @sf.secondary.then(@sf.one_line).then(@sf.full_words)

///|
/// How long ago, as its words are, as long as it is.
// kept across runs: a value (no field of it changes)
let published_ago : @ui.TextStyle = @sf.secondary.then(@sf.one_line)

///|
/// When and by whom in a line, what is left of the row: the face 4 from the words either side.
// kept across runs: a value (no field of it changes)
let published_line : @ui.Style = @ui.css("row gap=S1 align=ACenter").then(@ui.style(w=@sf.grow))

///|
/// Who published it: their face, as large as the words.
let published_face : Double = 16.0

///|
/// Sharing the chat, a card of its own in its sheet (Publish.kt PublishList): 分享图片 opens the page that draws it as a
/// picture, for those who may (not a read-only member); each of its public links under it, when and by whom, 复制, and
/// 撤销 for who published it or an owner or admin (asked first; gone from here at once).
fn publish_list(c : @ui.Ctx, src : Source, r : ChatRef, thread : Double, p : Json?, close : () -> Unit) -> Unit {
  let t = @sf.theme()
  c.box(style=publish_card_top, fn() { publish_list_rows(c, src, r, thread, p, t, close) }) |> ignore
}

///|
fn publish_list_rows(
  c : @ui.Ctx,
  src : Source,
  r : ChatRef,
  thread : Double,
  p : Json?,
  t : @sf.Theme,
  close : () -> Unit,
) -> Unit {
  info_list(c, fn() {
    if flag(p, "may") &&
      info_row(c, "info/publish", fn() {
        // (a picture going out: not the photo of 图片、文件和链接)
        @sf.icon(c, "image-upload", size=16.0, color=t.p.text) |> ignore
        c.text(tr("web-pages.chat.shareImage"), style=publish_row_words.then(@sf.full_words)) |> ignore
        chevron(c)
      }) {
      // (the chat's sheet put down, the publishing over the window)
      close()
      @sfpages.open_publish(src, r, thread)
    }
    for l in items(p, "links") {
      published_row(c, src, r.station, thread, Some(l), close)
    }
  })
}

///|
/// One of the chat's links (Publish.kt PublishedRow): a link's mark (the web's globe, under 分享图片's picture), how long
/// ago and by whom; 复制; 撤销 when the viewer may.
fn published_row(c : @ui.Ctx, src : Source, station : String, thread : Double, l : Json?, close : () -> Unit) -> Unit {
  let id = text(l, "id")
  info_row(c, "", fn() {
    @sf.icon(c, "web", size=published_mark, color=@sf.theme().p.muted) |> ignore
    // how long ago, then who: their face before their name
    let ago = text(field(field(l, "time"), "createdAt"), "ago")
    let by = text(l, "byName")
    c.box(style=published_line, fn() {
      if ago != "" {
        c.text(if by != "" { ago + " · " } else { ago }, style=published_ago) |> ignore
      }
      if by != "" {
        avatar(c, src, if text(l, "by") != "" { text(l, "by") } else { by }, by, text(l, "byPicture"), published_face)
        c.text(by, style=published_words) |> ignore
      }
    })
    |> ignore
    if text_action(c, "publish/copy/" + id, tr("common.copy")) {
      copy_link(c, text(l, "link"))
    }
    if flag(l, "mayRevoke") && text_action(c, "publish/revoke/" + id, tr("web-pages.chat.publish.revoke")) {
      close()
      @sf.confirm(
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
/// A public link's mark, as large as the rows' icons.
let published_mark : Double = 16.0

///|
/// A link's words as a button, in the link's colour with no frame (Publish.kt TextAction): 14, a little room round
/// them, its ground pressed a small block's of the ladder's (text_action_box). True on the frame after a tap.
fn text_action(c : @ui.Ctx, key : String, label : String) -> Bool {
  let id = c.id(key)
  c.box(style=text_action_box, id~, fn() {
    c.text(label, style=text_action_words) |> ignore
    // Publish.kt TextAction: clip(Smooth(…)).clickable
    @motion.ripple(c, id, @sf.small_corner)
  })
  |> ignore
  c.clicked(id)
}

///|
/// Its box: 24 high, 4 in, round by the ladder's last (at the end of an info card's row, 44 high and 10 in, 20 from the
/// card's side and foot both, concentric with its foot corner there).
// kept across runs: a value (no field of it changes)
let text_action_box : @ui.Style = @ui.style(h=S6, px=S1, radius=@sf.small_radius, align=ACenter, justify=JCenter)

///|
// kept across runs: a value (no field of it changes)
let text_action_words : @ui.TextStyle = @ui.text_style(size=Ui, color=Link, wrap=false)

///|
/// Puts a link on the clipboard, saying so (Publish.kt copyLink).
fn copy_link(c : @ui.Ctx, link : String) -> Unit {
  c.copy_text(link)
  say(c, tr("common.link.copied"))
}

///|
/// The publishing card 10 under the chat's actions (ChatInfo.kt: Spacer 10).
// kept across runs: a value (no field of it changes)
let publish_card_top : @ui.Style = @ui.css("w=Full pt=S2_5")
