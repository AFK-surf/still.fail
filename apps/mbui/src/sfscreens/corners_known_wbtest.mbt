// The corner rule (mbui's Tester::corner_faults, still.fail docs/ui-panels.md「所有带圆角的东西」) as each screen keeps it
// now: how many faults it still has, the bar they may only fall from (screen_check fails on one more, and on one less
// until the bar is lowered here). A screen not listed has none.

///|
// (chat-publish's: the first message's picture in the snapshot's card, 17 from its top and 16 from its side, as
// Android's Publish.kt PreviewMessage has it: the card's 14 and the picture's 3 under the name's line)
let corners_known : Map[String, Int] = { "chat-info": 2, "chat-jobs": 2, "chat-publish": 1 }
