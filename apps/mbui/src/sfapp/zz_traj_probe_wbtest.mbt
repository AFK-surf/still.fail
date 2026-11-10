///|
fn traj_probe(name : String, words : String, deliver : Double, answer : Double, core : Double, grow? : Bool = false, kb? : Bool = false, jank? : Bool = false, lead? : Double = 0.0) -> Unit raise {
  new_run()
  fix_pace.val = (deliver, answer, fix_turn_end_ms)
  fix_core_for.val = core
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  t.tap_text("发消息")
  if kb {
    t.set_ime_inset(300.0)
    t.run_for(@ui.move_most_ms)
  }
  t.type_text(words)
  if grow {
    t.frame(ms=116.0)
  } else {
    t.run_for(@ui.move_most_ms)
  }
  let field = match t.find(words) {
    Some((_, y)) => y - 30.0
    None => 844.0
  }
  let said0 = t.words_said()
  let before : Array[String] = []
  for w in said0 {
    if w.2 + w.4 < field && w.2 > 0.0 && said0.filter(fn(x) { x.0 == w.0 }).length() == 1 && w.0 != words {
      before.push(w.0)
    }
  }
  let t0 = t.time()
  if lead > 0.0 {
    let s = t.get(Button, label=@sf.t("web-main.composer.send"))
    let (x, y, w, h) = s.rect
    t.touch_at(0, x + w / 2.0, y + h / 2.0, t.time() + lead)
    t.touch_at(2, x + w / 2.0, y + h / 2.0, t.time() + lead)
    t.draw()
  } else {
    tap_send(t)
  }
  match flight_of("ws1/st1:s-c1") {
    Some(f) => println("LEAD \{name} sent_at-t0=\{f.sent_at - t0} set_out-t0=\{f.set_out - t0} now-t0=\{t.time() - t0}")
    None => println("LEAD \{name} no flight")
  }
  let end_at = t.time() + core + deliver + answer + @sfbase.flight_most_ms + @ui.move_most_ms + 1500.0
  let mut k = 0
  while t.time() < end_at {
    k = k + 1
    if jank {
      t.frame(ms=[16.0, 33.0, 16.0, 50.0, 16.0, 16.0, 66.0][k % 7])
    } else {
      t.frame()
    }
    let said = t.words_said()
    let mut line = "TRAJ \{name} \{(t.time() - t0).to_int()}"
    for w in said {
      if w.0 == words || words.contains(w.0) && w.0.length() > 1 {
        if w.5 > 0.01 {
          line = line + " M:\{w.1.to_int()},\{(w.2 * 10.0).to_int()},\{(w.5 * 100.0).to_int()}"
        }
      }
    }
    for b in before {
      match said.filter(fn(x) { x.0 == b && x.5 > 0.01 }) {
        [w] => line = line + " R:\{(w.2 * 10.0).to_int()}"
        _ => line = line + " R:-"
      }
    }
    println(line)
  }
}

///|
test "zz traj probe" {
  if @ui.test_at_a_rate() {
    return
  }
  for lead in [0.0, 118.0] {
    let n = "lead\{lead.to_int()}"
    traj_probe("short-fast/" + n, "看一下列表", 0.0, 0.0, 0.0, lead~)
    traj_probe("short-slow/" + n, "看一下列表", 300.0, 1400.0, 400.0, lead~)
    traj_probe("long/" + n, "这个列表里的第三项和第五项是不是重复了，帮我看一下然后合并一下，顺便把标题也改短一点", 300.0, 1400.0, 400.0, lead~)
    traj_probe("grow/" + n, "第一行\n第二行", 300.0, 1400.0, 400.0, grow=true, lead~)
    traj_probe("short-slow-jank/" + n, "看一下列表", 300.0, 1400.0, 400.0, jank=true, lead~)
  }
}
