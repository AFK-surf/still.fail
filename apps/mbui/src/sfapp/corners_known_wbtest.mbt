// The corner rule (mbui's Tester::corner_faults, still.fail docs/ui-panels.md「所有带圆角的东西」) as each screen keeps it
// now: how many faults it still has, the bar they may only fall from (screen_check fails on one more, and on one less
// until the bar is lowered here). A screen not listed has none.

///|
let corners_known : Map[String, Int] = Map::new()

///|
/// Every screen in every window (corners_wbtest.mbt), by window, language and screen: the bar it may only fall from. A
/// screen not listed has none; none is listed now.
let corners_everywhere_known : Map[String, Int] = Map::new()
