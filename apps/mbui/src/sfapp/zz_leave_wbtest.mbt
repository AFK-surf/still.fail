///|
test "zzshot newchat leave" {
  for w in [1280.0, 740.0] {
    let held : Map[String, () -> Unit] = {}
    let unread = @signals.signal(true)
    let t = held_core(held, unread, w~, h=800.0, platform=0)
    t.frame()
    t.tap_text("做任何事")
    t.type_text("把发布说明写一下")
    t.draw()
    t.record_host()
    let n = Ref(0)
    t.each_frame(Some(fn() {
      if n.val <= 30 {
        println("DLBEGIN \{w.to_int()} \{n.val}")
        println(t.drawlist(bytes=true))
        println("DLEND")
      }
      n.val += 1
    }))
    t.enter()
    t.run_for(new_fade_ms + 50.0)
    t.each_frame(None)
    for f in t.host_frames() {
      println("HF \{w.to_int()} at=\{f.at} old_built=\{f.old_built} why=\{f.why}")
    }
  }
}
