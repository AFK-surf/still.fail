///|
test "zz dbg floor" {
  let t = linger_core()
  let total = fix_deliver_ms + fix_answer_ms + fix_turn_end_ms + emit_all_ms()
  let mut at = 0.0
  while at < total + 400.0 {
    t.run_for(100.0)
    at += 100.0
    let rd = readings.get("ws1/st1\u{1}s-c1")
    println("DBG t=\{at}/\{total} working=\{t.find(tr("android-chat.chat.working")) is Some(_)} linger=\{rd.map(fn(r) { r.linger.length() })} running=\{rd.map(fn(r) { r.running.length() })} rows=\{t.rows().length()} last=\{t.rows().last()}")
    if at >= 3800.0 && at <= 4000.0 {
      for w in t.words() {
        if w.2 > 450.0 { println("DBGW t=\{at} y=\{w.2} h=\{w.4} a=\{w.5} \{w.0}") }
      }
      println("DBGR t=\{at} \{t.rows()}")
    }
  }
}
