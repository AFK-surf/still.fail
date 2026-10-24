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
  @sfbase.send_sharing(src, d.key, station, d.text.trim(chars=" \n\t").to_string(), send)
}

///|
fn sharing_go(key : String) -> Unit {
  @sfbase.sharing_go(key)
}

// ── the sheet (Composer.kt askToShare) ────────────────────────────────

///|
/// How tall the sheet is (Composer.kt: SheetSpec fit, 22 + 48 + 30, each chat's row (34; 54 with the line saying it
/// may not be shared), 16 + 38 + 24), at most 90% of the window (Sheet.kt).
fn outside_sheet_h(chats : Array[@sfbase.OutsideRef]) -> Double {
  let mut rows = 0.0
  for c in chats {
    rows += if c.may { 34.0 } else { 54.0 }
  }
  22.0 + 48.0 + 30.0 + rows + 16.0 + 38.0 + 24.0
}

///|
/// The sheet's grabber and head as sheet_grab and sheet_head draw them (25, then 4 + 23.8 + 10): what is under them
/// has the rest.
let outside_top : Double = 25.0 + 37.8

///|
/// What is under the head: 20 in from the sheet's sides (Composer.kt padding(horizontal = 20)).
// kept across runs: a value (no field of it changes)
let outside_body : @ui.Style = @ui.css("w=Full px=S5")

///|
/// What it says first: 14/20, muted, 8 over the chats.
// kept across runs: a value (no field of it changes)
let outside_lead_box : @ui.Style = @ui.css("w=Full pb=S2")

///|
// kept across runs: a value (no field of it changes)
let outside_lead : @ui.TextStyle = @ui.text_style(size=Base, leading=L6, color=Muted, w=Full)

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
let outside_at : @ui.TextStyle = @ui.text_style(size=Lg, leading=L7, color=A(Link, O70), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let outside_title : @ui.TextStyle = @ui.text_style(size=Lg, leading=L7, color=Link, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let outside_cannot_box : @ui.Style = @ui.css("w=Full pt=S0_5")

///|
// kept across runs: a value (no field of it changes)
let outside_cannot : @ui.TextStyle = @ui.text_style(size=Sm, leading=L5, color=Danger, w=Full)

///|
/// Why sharing failed: 13/18, red, 8 under the chats.
// kept across runs: a value (no field of it changes)
let outside_failed_box : @ui.Style = @ui.css("w=Full pt=S2")

///|
/// The buttons at its end, 8 apart: 16 under what is over them, 24 over the sheet's foot.
// kept across runs: a value (no field of it changes)
let outside_buttons : @ui.Style = @ui.css("row w=Full pt=S4 pb=S6 gap=S2 justify=JEnd")

///|
/// Whose a chat is, in a small outlined pill (PageParts.kt StationTag with words alone: 104 at most, 8 and 2 in, its
/// words 12/16 muted on one line).
// kept across runs: a value (no field of it changes)
let words_tag : @ui.Style = @ui.style(
  row=true,
  max_w=@sf.tag_max,
  px=S2,
  py=S0_5,
  radius=Full,
  border=B1,
  border_color=Line,
  align=ACenter,
)

///|
// kept across runs: a value (no field of it changes)
let words_tag_words : @ui.TextStyle = @ui.text_style(size=Xs, leading=L4, color=Muted, wrap=false)

///|
/// The sheet asking to share what draft `key` refers to, while it is open or sinking away.
fn outside_sheet(c : @ui.Ctx, src : Source, key : String) -> Unit {
  guard @sfbase.outside_asking(key) is Some(s) else { return }
  let sharable = @sfbase.outside_sharable(s)
  let h = dmin(outside_sheet_h(s.chats), c.height * 0.9)
  let cancel_key = "outside/cancel"
  let go_key = "outside/go"
  let r = @kit.sheet(
    c,
    "outside-sheet",
    s.open,
    h~,
    scrim=@sf.sheet_scrim,
    look=@sf.sheet_look(),
    fn() {
      @sf.sheet_grab(c)
      sheet_head(c, tr("web-main.outside.title"))
      c.capped("outside/" + key, h - outside_top, fn() {
        c.box(style=outside_body, fn() {
          c.box(style=outside_lead_box, fn() {
            c.text(tr("web-main.outside.lead"), style=outside_lead) |> ignore
          })
          |> ignore
          // each as a reference shows (its title after `@`, in the link's ink), whose after it as the `@` menu says it
          for x in s.chats {
            c.box(style=outside_row, fn() {
              c.box(style=outside_line, fn() {
                c.box(style=outside_title_box, fn() {
                  c.text("@", style=outside_at) |> ignore
                  c.text(x.title, style=outside_title) |> ignore
                })
                |> ignore
                c.box(style=words_tag, fn() {
                  c.text(fill("web-main.outside.from", [("name", x.workspace_name)]), style=words_tag_words)
                  |> ignore
                })
                |> ignore
              })
              |> ignore
              if !x.may {
                c.box(style=outside_cannot_box, fn() {
                  c.text(tr("web-main.outside.cannot"), style=outside_cannot) |> ignore
                })
                |> ignore
              }
            })
            |> ignore
          }
          if s.error != "" {
            c.box(style=outside_failed_box, fn() { c.text(s.error, style=outside_cannot) |> ignore })
            |> ignore
          }
          c.box(style=outside_buttons, fn() {
            if dv_button(c, cancel_key, tr("common.cancel"), primary=false) {
              @sfbase.outside_no(s)
            }
            let label = tr(if sharable { "web-main.outside.share" } else { "web-main.outside.anyway" })
            if dv_button(c, go_key, label, primary=true, busy=s.busy) {
              @sfbase.outside_yes(src, s)
              // (a core that answers at once has cleared it to go already)
              sharing_go(s.key)
            }
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    },
  )
  // closed by its scrim or dragged down: as 取消
  if s.open && !r.open {
    @sfbase.outside_no(s)
  }
  if !s.open && !r.shown {
    @sfbase.outside_gone(s)
  }
}
