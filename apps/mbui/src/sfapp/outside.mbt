// What a draft refers to, shared before it goes (ember apps/android chat/screens/Composer.kt sendSharing, askToShare;
// NewChat.kt's first message the same; docs/chat-share.md), the phone's asking: what is asked of the core and what its
// yes does are sfbase's (outside.mbt), for every composer; here, its sheet. It says which chats first, each saying
// whose (来自 its workspace), those the viewer may not share saying so; 分享并发送 shares those they may (the button
// turning meanwhile), then closes and sends; a share failing is said in the sheet, nothing sent, the draft as it was.
// With none they may share, 仍然发送 sends it as it is. 取消 (or the scrim) leaves the draft as it was.

///|
/// Sends what draft `d` holds by `send`, written on `station`, once this workspace's agents can read what it refers
/// to (sfbase's send_sharing).
fn send_sharing(src : Source, d : Draft, station : String, send : () -> Unit) -> Unit {
  @sfbase.send_sharing(src, d.key, station, d.text.get().trim(chars=" \n\t").to_string(), send)
}

///|
fn sharing_go(key : String) -> Unit {
  @sfbase.sharing_go(key)
}

// ── the sheet (Composer.kt askToShare) ────────────────────────────────

///|
/// What it says first: 14/20, muted, 8 over the chats.
// kept across runs: a value (no field of it changes)
let outside_lead_box : @ui.Style = @ui.css("w=Full pb=S2")

///|
// kept across runs: a value (no field of it changes)
let outside_lead : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, w=Full)

///|
/// A chat's row: 5 above and under; its title after `@` (15/22, the link's ink, `@` at 70% of it) and whose it is in a
/// tag, 6 apart; why it may not be shared under them (13/18, red, 2 under).
// kept across runs: a value (no field of it changes)
let outside_row : @ui.Style = @ui.style(w=Full, py=@sf.space_5)

///|
// kept across runs: a value (no field of it changes)
let outside_line : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let outside_title_box : @ui.Style = @ui.css("row")

///|
// kept across runs: a value (no field of it changes)
let outside_at : @ui.TextStyle = @ui.text_style(size=Ui, leading=L7, color=A(Link, O70), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let outside_title : @ui.TextStyle = @ui.text_style(size=Ui, leading=L7, color=Link, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let outside_cannot_box : @ui.Style = @ui.css("w=Full pt=S0_5")

///|
// kept across runs: a value (no field of it changes)
let outside_cannot : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Danger, w=Full)

///|
/// Why sharing failed: 13/18, red, 8 under the chats.
// kept across runs: a value (no field of it changes)
let outside_failed_box : @ui.Style = @ui.css("w=Full pt=S2")

///|
/// Whose a chat is, in a small outlined pill (PageParts.kt StationTag: 104 at most, 8 and 2 in, its mark 4 before its
/// words 12/16 muted on one line).
// kept across runs: a value (no field of it changes)
let words_tag : @ui.Style = @ui.style(
  row=true,
  max_w=@sf.tag_max,
  px=S2,
  py=S0_5,
  gap=S1,
  radius=Full,
  border=B1,
  border_color=Line,
  align=ACenter,
)

///|
// kept across runs: a value (no field of it changes)
let words_tag_words : @ui.TextStyle = @ui.text_style(size=Caption, leading=L4, color=Muted, wrap=false)

///|
/// The presenter asking for each draft's sharing (@sf.last_presented), while it is drawn.
// kept across runs: emptied as each goes (outside_sheet); reset by the app with the presenters (outside_reset)
let outside_shown : @sf.LiveMap[String, Int] = @sf.LiveMap::new()

///|
/// No sheet asking (the app begun again).
fn outside_reset() -> Unit {
  outside_shown.clear()
}

///|
/// The sheet asking to share what draft `key` refers to (the library's panel opened by nothing: with a finger the
/// phone's sheet, with a mouse the web's dialog), put up as the core asks, taken down as it is answered; its scrim,
/// back or a press outside is 取消.
fn outside_sheet(c : @ui.Ctx, src : Source, key : String) -> Unit {
  ignore(c)
  match (@sfbase.outside_asking(key), outside_shown.get(key)) {
    (Some(s), None) if s.open.get() => {
      @sf.panel(
        tr("web-main.outside.title"),
        fn(c, _) { outside_body_of(c, key) },
        from=Unanchored,
        foot=fn(c, _) { outside_foot(c, src, key) },
        gone=fn() {
          match @sfbase.outside_asking(key) {
            Some(s) if s.open.get() => @sfbase.outside_no(s)
            _ => ()
          }
        },
      )
      outside_shown[key] = @sf.last_presented()
    }
    (Some(s), Some(serial)) if !s.open.get() =>
      if @sf.presented_drawn_of(serial) {
        // answered (shared and sent, or 取消): down
        @sf.close_presented_of(serial)
      } else {
        outside_shown.remove(key)
        @sfbase.outside_gone(s)
      }
    (None, Some(serial)) => {
      @sf.close_presented_of(serial)
      outside_shown.remove(key)
    }
    _ => ()
  }
}

///|
/// What it says: the chats, each as a reference shows (its title after `@`, in the link's ink), whose after it as the
/// `@` menu says it, and why one may not be shared; why sharing failed.
fn outside_body_of(c : @ui.Ctx, key : String) -> Unit {
  guard @sfbase.outside_asking(key) is Some(s) else { return }
  c.box(style=outside_lead_box, fn() { c.text(tr("web-main.outside.lead"), style=outside_lead) |> ignore }) |> ignore
  for x in s.chats {
    c.box(style=outside_row, fn() {
      c.box(style=outside_line, fn() {
        c.box(style=outside_title_box, fn() {
          c.text("@", style=outside_at) |> ignore
          c.text(x.title, style=outside_title) |> ignore
        })
        |> ignore
        c.box(style=words_tag, fn() {
          let (before, after) = @sf.t_around("web-main.outside.from", "name")
          if before != "" {
            c.text(before, style=words_tag_words) |> ignore
          }
          @sf.workspace_badge(c, x.workspace_name, x.workspace_emoji, x.workspace_icon, 12.0)
          c.text(x.workspace_name + after, style=words_tag_words) |> ignore
        })
        |> ignore
      })
      |> ignore
      if !x.may {
        c.box(style=outside_cannot_box, fn() { c.text(tr("web-main.outside.cannot"), style=outside_cannot) |> ignore })
        |> ignore
      }
    })
    |> ignore
  }
  if s.error.get() != "" {
    c.box(style=outside_failed_box, fn() { c.text(s.error.get(), style=outside_cannot) |> ignore }) |> ignore
  }
}

///|
/// Its buttons: 取消, and 分享并发送 (仍然发送 with none that may be shared), turning while it shares.
fn outside_foot(c : @ui.Ctx, src : Source, key : String) -> Unit {
  guard @sfbase.outside_asking(key) is Some(s) else { return }
  if dv_button(c, "outside/cancel", tr("common.cancel"), primary=false) {
    @sfbase.outside_no(s)
  }
  let label = tr(if @sfbase.outside_sharable(s) { "web-main.outside.share" } else { "web-main.outside.anyway" })
  if dv_button(c, "outside/go", label, primary=true, busy=s.busy.get()) {
    @sfbase.outside_yes(src, s)
    // (a core that answers at once has cleared it to go already)
    sharing_go(s.key)
  }
}
