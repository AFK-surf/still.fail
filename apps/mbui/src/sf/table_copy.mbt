// A table's copy key (2026-10-26 用户：「支持一下表格导出，可以复制 markdown，csv，或者复制图片」): a code block's
// copy key (copy_key) on a row of its own over the table, at its end, whatever the input (over the table's corner, as a
// code block's is over its code, it would lie over the head's words); its menu copies the table as Markdown or as CSV
// (as the core wrote them: markdown.ts tableMarkdown, tableCsv) or as a picture of it (its shot: the table whole, as
// wide as its columns, on the page's ground; on a phone saved to its photo album: picture_out_way).

///|
/// Its key's row: over the table, at its end, 4 above it.
// kept across runs: a value (no field of it changes)
let table_keys_row : @ui.Style = @ui.css("row justify=JEnd mb=S1")

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
/// The copy key of the table `key` names (`table`, as the core wrote it to copy): pressed, its menu (beside it, along
/// its end) of copying it as Markdown, as CSV, as a picture; once one is copied it says so a moment (copied_ms).
fn Md::table_key(self : Md, key : String, table : MdTable) -> Unit {
  let c = self.c
  let id = c.id(key + "/copy")
  if c.clicked(id) {
    let copied = fn() {
      c.mark(id)
      c.wake_in(copied_ms, later=true)
    }
    let words = fn(s : String) {
      @ui.clipboard_set(s)
      copied()
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
    items.push(
      Some(
        menu_item_of(picture_out_way().0, fn() {
          c.take_shot(
            table_shot(key),
            fn(png) { if (picture_out_by.val)(c, png, !album) && !album { copied() } },
            scale=dmax(c.drawn_scale(), table_shot_scale),
          )
        }),
      ),
    )
    menu(items, from=Of(id), along=End)
  }
  copy_key(c, id, c.within(id, copied_ms), label=t("web-main.prose.copyTable"))
}
