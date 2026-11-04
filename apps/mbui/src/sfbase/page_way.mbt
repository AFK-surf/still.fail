// The page on its way to another width (the sidebar opening or folding beside it, a side panel): said by the shell as
// the page is built, for what is laid out by that width to go on as it is till it is there.

///|
/// The page's way: which one (none: at rest), and how wide it goes to.
pub(all) struct PageWay {
  mut id : String
  mut to : Double
}

///|
// kept across runs: said anew as each page is built
pub let page_way : PageWay = { id: "", to: 0.0 }

///|
/// The page at rest, or on way `id` to width `to`.
pub fn page_way_said(id : String, to : Double) -> Unit {
  page_way.id = id
  page_way.to = to
}
