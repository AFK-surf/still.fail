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
/// The chat's public links, a card of its own in its sheet (Publish.kt PublishList; making one is its menu's 分享图片): each
/// when and by whom, 复制, and 撤销 for who published it or an owner or admin (asked first; gone from here at once).
fn publish_list(c : @ui.Ctx, src : Source, r : ChatRef, thread : Double, p : Json?, close : () -> Unit) -> Unit {
  c.box(style=publish_card_top, fn() { publish_list_rows(c, src, r, thread, p, close) }) |> ignore
}

///|
fn publish_list_rows(
  c : @ui.Ctx,
  src : Source,
  r : ChatRef,
  thread : Double,
  p : Json?,
  close : () -> Unit,
) -> Unit {
  info_list(c, fn() {
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
    // (its actions at its end, out to where their small corner is concentric with the card's: text_actions_at)
    c.box(style=text_actions_at, fn() {
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
          @ui.haptic(Confirm)
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
/// Its box: 28 high, 4 in, round by the ladder's last (at the end of an info card's row, 44 high and 8 in, 16 from the
/// card's side and foot both, concentric with its corner there: text_actions_at).
// kept across runs: a value (no field of it changes)
let text_action_box : @ui.Style = @ui.style(h=S7, px=S1, radius=@sf.small_radius, align=ACenter, justify=JCenter)

///|
/// An info row's actions at its end: past the row's words' room to the ladder's inset (8) from its side, so 16 from the
/// card's, where the small corner is concentric with it.
// kept across runs: a value (no field of it changes)
let text_actions_at : @ui.Style = @ui.style(row=true, gap=S1, align=ACenter, mr=@sf.room_of(@sf.corner_inset - @sf.text_in))

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
/// The publishing card under the chat's actions, the room between the info's cards over it (info_lists_gap).
// kept across runs: a value (no field of it changes)
let publish_card_top : @ui.Style = @ui.css("w=Full")
