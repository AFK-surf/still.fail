// The desktop's asking before a message that refers to chats of the viewer's other workspaces goes (still.fail web/src/
// OutsideShare.tsx useOutsideShare, OutsideList; ChatRef.css.ts outsideList, outsideItem, outsideCannot, refChip,
// refChipStation): the presenters' panel, 分享对话 and what sharing does, then each chat as a reference shows (`@` and its title in
// the accent) and whose it is, those the viewer may not share saying so; 取消, and 分享并发送 (仍然发送 with none to
// share), Enter again saying yes. What is asked of the core and what the yes does are sfbase's (outside.mbt). What it
// holds and its buttons are nodes of the window's tree, made once as it opens (@sf.panel_nodes).

///|
/// The asking for draft `key`'s send, while it asks (and as it goes): the presenters' panel (a sheet with a finger short
/// of Large, else a dialog in the middle), put up once as it opens, what it says bound to what it asks;
/// taken down once it is decided.
fn outside_dialog(_c : @ui.Ctx, src : Source, key : String) -> Unit {
  guard @sfbase.outside_asking(key) is Some(s) else { return }
  match outside_up.get(key) {
    None if s.open.get() => {
      @sf.panel_nodes(
        @sf.t("web-main.outside.title"),
        fn(v, _) { outside_body(v, s) },
        from=Unanchored,
        description=@sf.t("web-main.outside.lead"),
        foot=fn(v, _) { outside_foot(v, src, s) },
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
    Some(serial) if !s.open.get() => {
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
let outside_up : Map[String, Int] = Map([])

///|
fn outside_reset() -> Unit {
  outside_up.clear()
}

///|
/// What asking `s` asks about, in node `v` (the panel's body's): each chat as a reference shows and whose it is, those
/// the viewer may not share saying so; why sharing failed under them, while it did.
fn outside_body(v : @view.View, s : @sfbase.OutsideAsk) -> Unit {
  v.box(fn(list) {
    @sf.style_node(list, fn() { outside_list })
    // (the chats an asking is about are said before it opens, and are its own: one asked again is another asking, in
    // another panel)
    for x in s.chats.iter() {
      list.box(fn(item) {
        @sf.style_node(item, fn() { outside_item })
        // (wrapping, its lines as far apart as what is on one: an old view's flow)
        item.wraps(Is(Some(outside_item_gap.px()))) |> ignore
        item.box(fn(chip) {
          @sf.style_node(chip, fn() { outside_chip }, in_row=true)
          @sf.words_node(chip, fn() { "@" }, fn() { outside_hash }) |> ignore
          @sf.words_node(chip, fn() { x.title }, fn() { outside_title }) |> ignore
        })
        |> ignore
        item.box(fn(whose) {
          @sf.style_node(whose, fn() { outside_whose }, in_row=true)
          let around = fn() { @sf.t_around("web-main.outside.from", "name") }
          whose.show(fn() { around().0 != "" }, at_once=true, fn(w) {
            @sf.words_node(w, fn() { around().0 }, fn() { outside_whose_words }) |> ignore
          })
          @sf.workspace_badge_node(whose, fn() { x.workspace_name }, fn() { x.workspace_emoji }, fn() { x.workspace_icon }, outside_whose_mark)
          @sf.words_node(whose, fn() { x.workspace_name + around().1 }, fn() { outside_whose_words }) |> ignore
        })
        |> ignore
        if !x.may {
          // (what is left of its line after them, as a row gives what is as wide as it: outside_cannot's w=Full)
          item.box(fn(no) {
            no.grow(Is(1.0)).basis(Is(Some(0.0))) |> ignore
            @sf.words_node(no, fn() { @sf.t("web-main.outside.cannot") }, fn() { outside_cannot }) |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    }
    list.show(fn() { s.error.get() != "" }, fn(e) {
      @sf.words_node(e, fn() { s.error.get() }, fn() { outside_cannot }) |> ignore
    })
  })
  |> ignore
}

///|
/// 取消, and 分享并发送 (仍然发送 with none to share), turning while it shares, in node `v` (the panel's foot's). Enter
/// sent the words, so Enter again says yes: the foot's action `outside.yes`, the window's keymap's key for it where an
/// asking is up (@settings.keymap_of: `OutsideAsk`).
fn outside_foot(v : @view.View, src : Source, s : @sfbase.OutsideAsk) -> Unit {
  v
  .key_context("OutsideAsk")
  .on_action("outside.yes", fn(_) {
    guard s.open.get() else { return false }
    @sfbase.outside_yes(src, s)
    true
  })
  |> ignore
  @sf.button_node(v, fn() { @sf.t("common.cancel") }, fn() { @sfbase.outside_no(s) }, tone=Ghost) |> ignore
  // (a dialog in the middle of the window opens with the focus on its yes: Enter there presses it; a sheet leaves the
  // focus in the words' field, Enter the foot's action)
  @sf.button_node(
    v,
    fn() { @sf.t(if @sfbase.outside_sharable(s) { "web-main.outside.share" } else { "web-main.outside.anyway" }) },
    fn() { @sfbase.outside_yes(src, s) },
    tone=Primary,
    busy=fn() { s.busy.get() },
  )
  |> @sf.panel_opens_on_node
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
/// What is on its line that far apart, and its lines (outside_item's gap).
// kept across runs: a value (no field of it changes)
let outside_item_gap : @ui.Space = S1

///|
/// A reference as it shows (refChip): `@` a little faint (refChipHash, 1 from the title), the title, in the accent.
// kept across runs: a value (no field of it changes)
let outside_chip : @ui.Style = @ui.css("row gap=SPx align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let outside_hash : @ui.TextStyle = @ui.text_style(size=Ui, color=A(Accent, O70), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let outside_title : @ui.TextStyle = @ui.text_style(size=Ui, color=AccentText, wrap=false)

///|
/// Whose it is (refChipStation): a pill 4 after it, 1 by 6 in, the meta size, muted, on the hover's ground.
// kept across runs: a value (no field of it changes)
let outside_whose : @ui.Style = @ui.css("row ml=S1 px=S1_5 py=SPx gap=S1 radius=Full bg=Hover align=ACenter")

///|
/// Its workspace's mark, as a chip's station's.
let outside_whose_mark : Double = 11.0

///|
// kept across runs: a value (no field of it changes)
let outside_whose_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
/// Why it may not be shared, and why sharing failed (outsideCannot): the meta size, in red, a line of its own.
// kept across runs: a value (no field of it changes)
let outside_cannot : @ui.TextStyle = @ui.text_style(size=Meta, color=Danger, w=Full)
