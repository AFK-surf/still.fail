// A settings page on the desktop as the web's frames one (ember web/src/styles/pages.css.ts page, pageNarrow,
// pageHead; brand.css.ts: the narrow page's column): its head, then what it holds in the 760 column in the pane's
// middle, 28 under the head, 80 room at its foot. The pages ported from the web's onto the library's parts
// (web_notifications.mbt, …) are laid out in it; their words in the library's true sizes (home.mbt `page`: no wide
// scale over them).

///|
/// `title`'s page holding `content`, a block at a time (each laid out as it comes into view), `about` what it is for
/// said by a mark beside its title.
fn desk_page(c : @ui.Ctx, core : Core, key : String, title : String, content : Array[() -> Unit], about? : String = "") -> Unit {
  let blocks : Array[() -> Unit] = [
    fn() { top_back(c, core, tr("android-settings.title")) },
    fn() { large_title(c, title, about~) },
  ]
  for i, b in content {
    blocks.push(fn() { c.box(style=if i == 0 { desk_first } else { desk_block }, fn() { b() }) |> ignore })
  }
  scroll_page(c, key, blocks)
}

///|
/// How wide the page's column is (pageNarrow: 760 at most), for what is drawn to its width before it is laid out.
fn desk_column(c : @ui.Ctx) -> Double {
  dmin(desk_column_most, c.width - 2.0 * wide_side(c) - 2.0 * desk_column_in)
}

///|
let desk_column_most : Double = 760.0

///|
let desk_column_in : Double = 16.0

///|
/// A block of the page, at the column's edges; the first 28 under the head (its own 12 and these 16).
// kept across runs: a value (no field of it changes)
let desk_block : @ui.Style = @ui.style(w=Full, px=S4)

///|
// kept across runs: a value (no field of it changes)
let desk_first : @ui.Style = desk_block.then(@ui.style(pt=S4))
