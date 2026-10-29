// A table's copy key (2026-10-26 用户：「支持一下表格导出，可以复制 markdown，csv，或者复制图片」): an icon button hung
// past the table's right edge, in line with its head's row, whatever the input, taking no room and over nothing of it
// (「应该悬挂在右边，而不是占着实际位置」「不要压在表格上」: a row of its own over the table was 「太拉」, and over its corner,
// as a code block's key is, it lies over the head's words): in what scrolls, after the table, so beside it where the
// message has room, past its end, scrolled to, where it is as wide as the message. Its menu copies the table as
// Markdown or as CSV (as the core wrote them: markdown.ts tableMarkdown, tableCsv) or as a picture of it (its shot: the
// table whole, as wide as its columns, on the page's ground; on a phone saved to its photo album: picture_out_way).
// Shown as the table is pointed at (2026-10-30 用户：「表格右边的按钮改成 hover 表格那一行才显示」), its menu open or
// it saying it copied, always to a finger: what a pointer over a thing shows (@sf.pointed_or_finger); its room kept
// either way, so nothing moves as it comes and goes.

///|
/// The key's size (icon_button's), and how far it is from the table and from what follows it (a press's room round it).
let table_key_size : Double = 32.0

///|
let table_key_gap : Double = @ui.Space::S1_5.px()

///|
/// The room the key takes past the table: its gap either side of it.
let table_key_room : Double = table_key_gap + table_key_size + table_key_gap

///|
/// What scrolls of a table: it, then its key, from their tops.
// kept across runs: a value (no field of it changes)
let table_beside : @ui.Style = @ui.css("row align=AStart")

///|
/// A table's picture: the table on the page's ground, table_shot_in round it.
// kept across runs: a value (no field of it changes)
let table_shot_paper : @ui.Style = @ui.css("w=Full p=S4 bg=Bg")

///|
let table_shot_in : Double = @ui.Space::S4.px()

///|
/// A table's picture's pixels a point at the least (the screen's where it has more): as sharp pasted from a screen of
/// one as from a Mac's.
let table_shot_scale : Double = 2.0

///|
/// The shot (Ctx::shot) of the table `key` names.
fn table_shot(key : String) -> String {
  key + "/picture"
}

///|
/// The copy key of the table `key` names (`table`, as the core wrote it to copy), table_key_gap past it and before what
/// follows, its middle on the head's row's (as the frame measured it: `key`/head; at its top till then). Pressed, its
/// menu (table_menu); once one is copied, a check a moment (copied_ms). Faded in as the table is pointed at (`key`/beside,
/// it and its key), out as the pointer leaves it, its menu gone and its check said; not pressed while not seen.
fn Md::table_key(self : Md, key : String, table : MdTable) -> Unit {
  let c = self.c
  let id = c.id(key + "/copy")
  let y = match @motion.measured(c, key + "/head") {
    // (the head's row at the card's top)
    Some(hh) => dmax(0.0, (hh - table_key_size) / 2.0)
    None => 0.0
  }
  let copied = c.within(id, copied_ms)
  let pointed = c.hovered(c.id(key + "/beside")) || c.lit(id) || table_menus.contains(key) || copied
  let seen = @kit.animate(
    c,
    key + "/copy-seen",
    if pointed_or_finger(c, pointed) { 1.0 } else { 0.0 },
    transition=nav_fade,
  )
  let label = if copied { t("common.copied") } else { t("web-main.prose.copyTable") }
  c.box(style=@ui.style(px=room_of(table_key_gap), pt=room_of(y)), fn() {
    if seen == 0.0 {
      // (its room, nothing in it to press)
      c.box(style=@ui.style(w=Fixed(table_key_size), h=Fixed(table_key_size)), fn() {  }) |> ignore
      return
    }
    // (faded as its icon's ink: the button's own colours, so far on)
    let th = theme()
    let icon = if copied { "check" } else { "copy" }
    if icon_button(
        c,
        icon,
        key=key + "/copy",
        size=table_key_size,
        round=true,
        label~,
        ink=alpha(th.p.text, seen),
        quiet=alpha(th.p.muted, seen),
      ) {
      self.table_menu(key, table, id)
    }
  })
  |> ignore
}

///|
/// The tables whose key's menu is open, by their key: their key shown till it closes.
let table_menus : LiveMap[String, Bool] = LiveMap::new()

///|
/// The menu of the table `key` names (`table`, as the core wrote it to copy), opened by its key (`id`), along its end:
/// copy it as Markdown, as CSV, as a picture (or on a phone save that); once one is copied, the key says so a moment.
/// Open, it is in table_menus.
fn Md::table_menu(self : Md, key : String, table : MdTable, id : Int) -> Unit {
  let c = self.c
  table_menus[key] = true
  let closed = fn() { table_menus.remove(key) }
  let said = fn() {
    c.mark(id)
    c.wake_in(copied_ms, later=true)
  }
  let words = fn(s : String) {
    closed()
    @ui.clipboard_set(s)
    said()
  }
  let items : Array[MenuItem?] = []
  // (none where a core from before them read the tree)
  if table.md != "" {
    items.push(Some(menu_item_of(t("web-main.prose.copyMarkdown"), fn() { words(table.md) })))
  }
  if table.csv != "" {
    items.push(Some(menu_item_of(t("web-main.prose.copyCsv"), fn() { words(table.csv) })))
  }
  let album = picture_to_album()
  let picture = fn() {
    closed()
    c.take_shot(
      table_shot(key),
      fn(png) { if (picture_out_by.val)(c, png, !album) && !album { said() } },
      scale=dmax(c.drawn_scale(), table_shot_scale),
    )
  }
  items.push(Some(menu_item_of(picture_out_way().0, picture)))
  menu(items, from=Of(id), along=End, gone=closed)
}
