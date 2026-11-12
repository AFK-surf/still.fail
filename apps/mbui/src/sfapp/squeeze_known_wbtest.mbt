// What each screen still has squeezed (squeeze_wbtest.mbt), by window, language and screen: the bar it may only fall
// from. A screen not listed has none. One that comes squeezed is given a way to give, not listed here; those listed are
// the window tree's, found as the squeeze came to hold its nodes (squeeze_tree.mbt, 2026-11-11), each to be mended,
// the bar brought down as it is: what each is and where it was made beside it.

///|
let squeeze_known : Map[String, Int] = {
  let known = Map([])
  for k in [
    // 真问题，待修: (g) a member's note broken onto 2 lines beside what is at the row's end, one line alone:
    // sf/page_node.mbt:935, asked for at sfpages/workspace_page.mbt:397
    ("phone-en settings-workspace", 1),
    ("phone-en settings-add-people", 1),
    ("phone-en settings-workspace-mark", 1),
  ] {
    known[k.0] = k.1
  }
  known
}
