// A chat made public, as its sheet lists it (docs/public-share.md; web/src/mobile/Chat.tsx PublishList, PublishedRow):
// 公开分享 opens the publishing (sfpages' publish.mbt, one on every screen), each of its links under it, 复制 and 撤销
// (`chat.unpublish`, asked first; gone from the list at once: the core's).

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
/// Making the chat public, a card of its own in its sheet (Publish.kt PublishList): 公开分享 opens the sheet that
/// publishes it, for those who may (not a read-only member); each of its links under it, when and by whom, 复制, and
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
        @sf.icon(c, "web", size=16.0, color=t.p.text) |> ignore
        c.text(tr("web-pages.chat.publish"), style=publish_row_words.then(@sf.full_words)) |> ignore
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
/// One of the chat's links (Publish.kt PublishedRow): how long ago and by whom; 复制; 撤销 when the viewer may.
fn published_row(c : @ui.Ctx, src : Source, station : String, thread : Double, l : Json?, close : () -> Unit) -> Unit {
  let id = text(l, "id")
  info_row(c, "", fn() {
    let said = [text(field(field(l, "time"), "createdAt"), "ago"), text(l, "byName")].filter(fn(s) { s != "" })
    c.text(said.join(" · "), style=published_words) |> ignore
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
