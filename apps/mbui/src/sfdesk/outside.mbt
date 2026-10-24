// The desktop's asking before a message that refers to chats of the viewer's other workspaces goes (ember web/src/
// OutsideShare.tsx useOutsideShare, OutsideList; ChatRef.css.ts outsideList, outsideItem, outsideCannot, refChip,
// refChipStation): a dialog, 分享对话 and what sharing does, then each chat as a reference shows (`@` and its title in
// the accent) and whose it is, those the viewer may not share saying so; 取消, and 分享并发送 (仍然发送 with none to
// share), Enter again saying yes. What is asked of the core and what the yes does are sfbase's (outside.mbt).

///|
/// The asking for draft `key`'s send, while it asks (and as it goes).
fn outside_dialog(c : @ui.Ctx, src : Source, key : String) -> Unit {
  guard @sfbase.outside_asking(key) is Some(s) else { return }
  let sharable = @sfbase.outside_sharable(s)
  // Enter sent it, so Enter again says yes
  if s.open && c.key_pressed(@ui.key_code_enter) {
    @sfbase.outside_yes(src, s)
  }
  let shown = @sf.dialog(
    c,
    "outside-share",
    s.open,
    @sf.t("web-main.outside.title"),
    description=@sf.t("web-main.outside.lead"),
    close_label=@sf.t("common.close"),
    footer=fn() {
      if @sf.button(c, @sf.t("common.cancel"), key="outside/cancel", tone=Ghost) {
        @sfbase.outside_no(s)
      }
      let label = @sf.t(if sharable { "web-main.outside.share" } else { "web-main.outside.anyway" })
      if @sf.button(c, label, key="outside/yes", tone=Primary, busy=s.busy) {
        @sfbase.outside_yes(src, s)
      }
    },
    fn() {
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
    },
  )
  // closed (its ✕, Esc, a press outside): as 取消; gone, let go of
  if s.open && !shown {
    @sfbase.outside_no(s)
  }
  if !s.open && !shown {
    @sfbase.outside_gone(s)
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
let outside_hash : @ui.TextStyle = @ui.text_style(size=Sm, color=A(Accent, O70), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let outside_title : @ui.TextStyle = @ui.text_style(size=Sm, color=Accent, wrap=false)

///|
/// Whose it is (refChipStation): a pill 4 after it, 1 by 6 in, the meta size, muted, on the hover's ground.
// kept across runs: a value (no field of it changes)
let outside_whose : @ui.Style = @ui.css("ml=S1 px=S1_5 py=SPx radius=Full bg=Hover")

///|
// kept across runs: a value (no field of it changes)
let outside_whose_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
/// Why it may not be shared, and why sharing failed (outsideCannot): the meta size, in red, a line of its own.
// kept across runs: a value (no field of it changes)
let outside_cannot : @ui.TextStyle = @ui.text_style(size=Xs, color=Danger, w=Full)
