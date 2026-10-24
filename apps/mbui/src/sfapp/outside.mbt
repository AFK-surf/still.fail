// What a draft refers to, shared before it goes (ember apps/android chat/screens/Composer.kt sendSharing, askToShare;
// NewChat.kt's first message the same; docs/chat-share.md). Words with a reference to another chat in them (its mark,
// `@[its title]`: ChatRefs.MARK) are looked at before they go: the chats of the viewer's other workspaces they name that
// are not shared with this workspace yet (the core's `chat.outsideRefs`). With none (or a core that cannot say) they
// go at once; else a sheet says which first, each saying whose (来自 its workspace), those the viewer may not share
// saying so. 分享并发送 shares those they may with this workspace (`chat.xshareAdd`, its station told first; the button
// turning meanwhile), then closes the sheet and sends; a share failing is said in the sheet, nothing sent, the draft as
// it was. With none they may share, 仍然发送 sends it as it is. 取消 (or the scrim) leaves the draft as it was. A second
// send while the core is asked does nothing.

///|
/// A chat of another workspace that what is sent refers to (Calls.kt OutsideRef): its station and id, its title, its
/// workspace and that's name, whether the viewer may share it (its starter, or an owner or admin there).
priv struct OutsideRef {
  station : String
  id : String
  title : String
  workspace : String
  workspace_name : String
  may : Bool
}

///|
/// A draft's send waiting on what it refers to: asked of the core (`checking`), its sheet open, or to go with the
/// composer's next build (`go`: the core said nothing is outside, or it was shared).
priv struct Sharing {
  /// the draft's key, and the station it is written on
  key : String
  station : String
  /// sends it (the composer's send, as it was pressed)
  send : () -> Unit
  mut chats : Array[OutsideRef]
  mut checking : Bool
  mut go : Bool
  /// its sheet: asked open (closed: it sinks away, then this is let go), sharing, why sharing failed ("" none)
  mut open : Bool
  mut busy : Bool
  mut error : String
}

///|
let sharing : Ref[Sharing?] = { val: None }

///|
/// Whether `words` hold a reference to another chat (Composer.kt ChatRefs.MARK, `@\[([^\]\n]{1,120})\]`): `@[`, 1 to
/// 120 UTF-16 units that are neither `]` nor a line's end, then `]`.
fn has_ref_mark(words : String) -> Bool {
  let cs : Array[Char] = []
  for ch in words {
    cs.push(ch)
  }
  let n = cs.length()
  for i in 0..<n {
    if cs[i] == '@' && i + 1 < n && cs[i + 1] == '[' {
      let mut units = 0
      let mut j = i + 2
      while j < n && cs[j] != ']' && cs[j] != '\n' && units <= 120 {
        units += if cs[j].to_int() > 0xFFFF { 2 } else { 1 }
        j += 1
      }
      if j < n && cs[j] == ']' && units >= 1 && units <= 120 {
        return true
      }
    }
  }
  false
}

///|
/// The chats the core's `chat.outsideRefs` answers.
fn outside_refs_of(v : Json) -> Array[OutsideRef] {
  items(Some(v), "chats").map(fn(c) {
    let s = Some(c)
    {
      station: text(s, "station"),
      id: text(s, "id"),
      title: text(s, "title"),
      workspace: text(s, "workspace"),
      workspace_name: text(s, "workspaceName"),
      may: flag(s, "may"),
    }
  })
}

///|
/// Sends what draft `d` holds by `send`, written on `station`, once this workspace's agents can read what it refers to
/// (Composer.kt sendSharing): no mark, at once; else the core is asked first.
fn send_sharing(src : Source, d : Draft, station : String, send : () -> Unit) -> Unit {
  let words = d.text.trim(chars=" \n\t").to_string()
  // no mark, nothing referred to: no need to ask (nor on a read-only run, whose send says it sends nothing)
  if !has_ref_mark(words) || src.read_only {
    send()
    return
  }
  match sharing.val {
    // asked already, or its sheet open: a second send does nothing meanwhile
    Some(s) if s.key == d.key && (s.checking || s.open || s.go) => return
    _ => ()
  }
  let s : Sharing = {
    key: d.key,
    station,
    send,
    chats: [],
    checking: true,
    go: false,
    open: false,
    busy: false,
    error: "",
  }
  sharing.val = Some(s)
  (src.call)("chat.outsideRefs", { "station": Json::string(station), "text": Json::string(words) }, fn(res) {
    s.checking = false
    // a core that cannot say (one before sharing) leaves it as before: sent as it is
    let chats = match res {
      Ok(v) => outside_refs_of(v)
      Err(_) => []
    }
    if chats.length() == 0 {
      s.go = true
    } else {
      s.chats = chats
      s.open = true
    }
  })
}

///|
/// Each build of draft `key`'s composer, before its bar: what was cleared to go goes (said by the core's answer or a
/// share's, which bring this frame), as it would have when pressed.
fn sharing_go(key : String) -> Unit {
  match sharing.val {
    Some(s) if s.key == key && s.go => {
      s.go = false
      // (a sheet shown sinks away first, then lets go of it: outside_sheet)
      if s.chats.is_empty() {
        sharing.val = None
      }
      (s.send)()
    }
    _ => ()
  }
}

// ── the sheet (Composer.kt askToShare) ────────────────────────────────

///|
/// How tall the sheet is (Composer.kt: SheetSpec fit, 22 + 48 + 30, each chat's row (34; 54 with the line saying it
/// may not be shared), 16 + 38 + 24), at most 90% of the window (Sheet.kt).
fn outside_sheet_h(chats : Array[OutsideRef]) -> Double {
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
  let s = match sharing.val {
    Some(s) if s.key == key && (s.open || !s.chats.is_empty()) => s
    _ => return
  }
  let may = s.chats.filter(fn(x) { x.may })
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
              s.open = false
            }
            let label = tr(if may.is_empty() { "web-main.outside.anyway" } else { "web-main.outside.share" })
            if dv_button(c, go_key, label, primary=true, busy=s.busy) {
              if may.is_empty() {
                s.open = false
                (s.send)()
              } else {
                share_outside(src, s, may)
                // (a core that answers at once has cleared it to go already)
                sharing_go(s.key)
              }
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
    s.open = false
  }
  if !s.open && !r.shown {
    sharing.val = None
  }
}

///|
/// 分享并发送: each chat the viewer may share shared with this workspace, all at once, each told on its own (one
/// failing does not stop the rest); all shared, the sheet closes and the draft goes (with the composer's next build);
/// one failing, why is said and nothing goes.
fn share_outside(src : Source, s : Sharing, may : Array[OutsideRef]) -> Unit {
  s.busy = true
  s.error = ""
  let left = Ref(may.length())
  let failed : Ref[Json?] = Ref(None)
  let into = workspace_of(s.station)
  for x in may {
    (src.call)(
      "chat.xshareAdd",
      {
        "station": Json::string(x.station),
        "id": Json::string(x.id),
        "workspace": Json::string(into),
        "prefer": Json::string(s.station),
      },
      fn(res) {
        match res {
          Err(e) if failed.val is None => failed.val = Some(e)
          _ => ()
        }
        left.val -= 1
        if left.val == 0 {
          s.busy = false
          match failed.val {
            Some(e) => s.error = fill("web-main.outside.failed", [("error", text(Some(e), "message"))])
            None => {
              s.open = false
              s.go = true
            }
          }
        }
      },
    )
  }
}
