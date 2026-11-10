///|
fn zz_log(f : @sfreplay.Flow, name : String, words : String, ms : Double) -> Unit {
  let field = match f.t.find(words) {
    Some((_, y)) => y - 30.0
    None => 700.0
  }
  let said0 = f.t.words_said()
  let before : Array[String] = []
  for w in said0 {
    if w.2 + w.4 < field && w.2 > 0.0 && said0.filter(fn(x) { x.0 == w.0 }).length() == 1 && w.0 != words {
      before.push(w.0)
    }
  }
  f.tap("icon:arrow-up")
  let t0 = f.t.time()
  while f.t.time() - t0 < ms {
    f.run_for(f.t.frame_period())
    let said = f.t.words_said()
    let mut line = "TRAJ \{name} \{(f.t.time() - t0).to_int()}"
    for w in said {
      if w.0 == words && w.5 > 0.01 {
        line = line + " M:\{w.1.to_int()},\{(w.2 * 10.0).to_int()},\{(w.5 * 100.0).to_int()}"
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
test "zz traj flow" {
  if @ui.test_at_a_rate() {
    return
  }
  let mut n = 0
  @sfreplay.orders(fn(seed) raise {
    n += 1
    let f = @sfreplay.Flow::start(@sfreplay.trace("send-paced"), seed~)
    f.tap("端到端测试")
    f.run_for(@ui.move_most_ms)
    f.tap("发消息")
    f.type_text("先说一句 064618 post:好的 064618")
    zz_log(f, "paced1/\{n}", "先说一句 064618 post:好的 064618", 3000.0)
    f.run_for(@sfapp.emit_out_ms + @ui.move_most_ms)
    f.tap("发消息")
    f.type_text("慢慢做 064618 slow:60 post:做完了 064618")
    zz_log(f, "paced2/\{n}", "慢慢做 064618 slow:60 post:做完了 064618", 6000.0)
    "x"
  })
}
