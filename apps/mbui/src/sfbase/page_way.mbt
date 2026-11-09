// The page on its way to another width (the sidebar opening or folding beside it, a side panel): said by the shell as
// the page is built, for what is laid out by that width to go on as it is till it is there.

///|
/// The page's way: which one (none: at rest), how wide it goes to, and when it is there (whichever frame sees it).
pub(all) struct PageWay {
  mut id : String
  mut to : Double
  mut ends : Double
}

///|
// kept across runs: said anew as each wide page is built, and put back by reset (a run with none says nothing)
pub let page_way : PageWay = { id: "", to: 0.0, ends: 0.0 }

///|
/// The page at rest, or on way `id` to width `to`, there at moment `ends`.
pub fn page_way_said(id : String, to : Double, ends~ : Double) -> Unit {
  page_way.id = id
  page_way.to = to
  page_way.ends = ends
}
