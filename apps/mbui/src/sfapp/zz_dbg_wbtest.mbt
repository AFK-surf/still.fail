///|
test "zz dbg floor" {
  let t = linger_core()
  t.run_for(fix_deliver_ms + fix_answer_ms + fix_turn_end_ms + emit_all_ms())
  println("DBG floor working=\{t.find(tr("android-chat.chat.working"))} end=\{t.at_end()} vis=\{t.visible()} rows=\{t.rows()}")
  for w in t.words() {
    if w.2 > -200.0 && w.2 < 900.0 {
      println("DBGW y=\{w.2} a=\{w.5} \{w.0}")
    }
  }
}

///|
test "zz dbg emit" {
  let clock = Ref::new(0.0)
  let t = emit_core(clock)
  let more = Array::makei(30, fn(i) { "第 \{i + 1} 段，接着往下讲。" }).join("\n\n")
  fix_later(1.0, fn() {
    fix_chat("s-c1").sent.push(
      msg(170, "agent", @sffixture.by_agent("anthropic", "claude", "s-c1"), long_reply + "\n\n" + more, "刚刚", {
        "ts": Json::string("long170"),
        "said": true,
      }),
    )
  })
  fix_clock_set(clock, clock.val + 1.0)
  t.draw()
  for i in 0..<12 {
    t.run_for((emit_all_ms() + 1000.0) / 12.0)
    println("DBG emit +\{i} end=\{t.at_end()} top=\{t.drawn_of("列表改成虚拟列表")} rows=\{t.rows()}")
  }
  emit_restore()
}
