// The corner rule (mbui's Tester::corner_faults, still.fail docs/ui-panels.md「所有带圆角的东西」) as each screen keeps it
// now: how many faults it still has, the bar they may only fall from (screen_check fails on one more, and on one less
// until the bar is lowered here). A screen not listed has none.

///|
let corners_known : Map[String, Int] = { "chat-info": 2, "chat-jobs": 2 }
