// TEMP scratch (never committed): a card's option picked at the chat's end, its answer 1378 ms after the fold, as send_card_paced's take 1 had it in its pass at half pace (the fold at ~4588, the answer at 5966)

///|
test "zz card pick" {
  let calls : Array[Made] = []
  let t = cards_core(calls, mode="chat-ask-end")
  // (its answer as the take had it: 1378 ms after the fold, the emit of it 168 ms over what the station takes)
  fix_pace.val = (fix_pace.val.0, 1210.0, fix_pace.val.2)
  // (the core has the pick 49 ms on, as the take's core had it: the fold at 4381.7 for the pick at 4332.8)
  fix_core_for.val = 49.0
  t.run_for(@ui.move_most_ms)
  println("ZZSTEP pick at \{t.time()}")
  @ui.zz_window.val = (t.time() - 50.0, t.time() + 2600.0)
  tap_now(t, "一起改")
  let till = t.time() + 2600.0
  while t.time() < till {
    t.frame()
  }
  println("ZZSTEP end at \{t.time()}")
}
