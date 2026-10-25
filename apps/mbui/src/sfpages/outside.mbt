// The desktop's asking before a message that refers to chats of the viewer's other workspaces goes (ember web/src/
// OutsideShare.tsx useOutsideShare, OutsideList; ChatRef.css.ts outsideList, outsideItem, outsideCannot, refChip,
// refChipStation): the presenters' panel, 分享对话 and what sharing does, then each chat as a reference shows (`@` and its title in
// the accent) and whose it is, those the viewer may not share saying so; 取消, and 分享并发送 (仍然发送 with none to
// share), Enter again saying yes. What is asked of the core and what the yes does are sfbase's (outside.mbt).

///|
/// The asking for draft `key`'s send, while it asks (and as it goes): the presenters' panel (a sheet with a finger short
/// of Large, else a dialog in the middle), put up once as it opens, what it says read anew each frame it is drawn;
/// taken down once it is decided.
fn outside_dialog(c : @ui.Ctx, src : Source, key : String) -> Unit {
  guard @sfbase.outside_asking(key) is Some(s) else { return }
  match outside_up.get(key) {
    None if s.open => {
      @sf.panel(
        @sf.t("web-main.outside.title"),
        fn(c, _) { outside_body(c, key) },
        from=Unanchored,
        description=@sf.t("web-main.outside.lead"),
        foot=fn(c, _) { outside_foot(c, src, key) },
        // (closed unsaid: its scrim, back, Escape) as 取消
        gone=fn() {
          outside_up.remove(key)
          match @sfbase.outside_asking(key) {
            Some(s) => {
              @sfbase.outside_no(s)
              @sfbase.outside_gone(s)
            }
            None => ()
          }
        },
      )
      outside_up[key] = @sf.last_presented()
    }
    // decided (shared, sent as it is, or 取消): down
    Some(serial) if !s.open => {
      outside_up.remove(key)
      @sf.close_presented_of(serial)
      @sfbase.outside_gone(s)
    }
    _ => ()
  }
}

///|
/// The askings up, by draft key: their presented panel (@sf.last_presented).
// kept across runs: put back by outside_reset
let outside_up : Map[String, Int] = {}

///|
fn outside_reset() -> Unit {
  outside_up.clear()
}

///|
/// What it asks about: each chat as a reference shows and whose it is, those the viewer may not share saying so; why
/// sharing failed under them.
fn outside_body(c : @ui.Ctx, key : String) -> Unit {
  guard @sfbase.outside_asking(key) is Some(s) else { return }
  c.box(style=outside_list, fn() {
    for x in s.chats {
      c.box(style=outside_item, flow=true, fn() {
        c.box(style=outside_chip, fn() {
          c.text("@", style=outside_hash) |> ignore
          c.text(x.title, style=outside_title) |> ignore
        })
        |> ignore
        c.box(style=outside_whose, fn() {
          c.text(@sf.t("web-main.outside.from", args=[("name", x.workspace_name)]), style=outside_whose_words)
          |> ignore
        })
        |> ignore
        if !x.may {
          c.text(@sf.t("web-main.outside.cannot"), style=outside_cannot) |> ignore
        }
      })
      |> ignore
    }
    if s.error != "" {
      c.text(s.error, style=outside_cannot) |> ignore
    }
  })
  |> ignore
}

///|
/// 取消, and 分享并发送 (仍然发送 with none to share), turning while it shares.
fn outside_foot(c : @ui.Ctx, src : Source, key : String) -> Unit {
  guard @sfbase.outside_asking(key) is Some(s) else { return }
  // Enter sent it, so Enter again says yes (read in the panel: its keys while it is open)
  if s.open && c.key_pressed(@ui.key_code_enter) {
    @sfbase.outside_yes(src, s)
  }
  if @sf.button(c, @sf.t("common.cancel"), key="outside/cancel", tone=Ghost) {
    @sfbase.outside_no(s)
  }
  let label = @sf.t(if @sfbase.outside_sharable(s) { "web-main.outside.share" } else { "web-main.outside.anyway" })
  if @sf.button(c, label, key="outside/yes", tone=Primary, busy=s.busy) {
    @sfbase.outside_yes(src, s)
  }
}

///|
/// The chats asked about (outsideList): one a line, 10 apart.
// kept across runs: a value (no field of it changes)
let outside_list : @ui.Style = @ui.css("w=Full gap=S2_5")

///|
/// One (outsideItem): its reference and whose it is on a line, wrapping, why it may not be shared under them.
// kept across runs: a value (no field of it changes)
let outside_item : @ui.Style = @ui.css("row w=Full gap=S1 align=ACenter")

///|
/// A reference as it shows (refChip): `@` a little faint (refChipHash, 1 from the title), the title, in the accent.
// kept across runs: a value (no field of it changes)
let outside_chip : @ui.Style = @ui.css("row gap=SPx align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let outside_hash : @ui.TextStyle = @ui.text_style(size=Ui, color=A(Accent, O70), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let outside_title : @ui.TextStyle = @ui.text_style(size=Ui, color=Accent, wrap=false)

///|
/// Whose it is (refChipStation): a pill 4 after it, 1 by 6 in, the meta size, muted, on the hover's ground.
// kept across runs: a value (no field of it changes)
let outside_whose : @ui.Style = @ui.css("ml=S1 px=S1_5 py=SPx radius=Full bg=Hover")

///|
// kept across runs: a value (no field of it changes)
let outside_whose_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
/// Why it may not be shared, and why sharing failed (outsideCannot): the meta size, in red, a line of its own.
// kept across runs: a value (no field of it changes)
let outside_cannot : @ui.TextStyle = @ui.text_style(size=Meta, color=Danger, w=Full)
