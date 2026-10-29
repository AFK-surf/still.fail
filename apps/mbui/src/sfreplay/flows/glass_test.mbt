// 29-glass (e2e/traces/glass.trace: Mini1 against the local still.fail, 92 messages): the chat under its frosted
// glass, the top bar and the composer glass over the messages. Four long messages sent from the composer, enough that
// the first runs on under the top bar's glass; scrolled up, the last runs under the composer's. (The end-to-end run's
// pictures had the glass's rows not flat; here, the frame's own frosted glass over the words.)

///|
/// The four messages' words (this run's mark), each asking the test's agent for a reply of its own (glass_reply).
let glass_words : Array[String] = [
  "玻璃下的第一条：这句话写得长一些，让气泡占上好几行，消息多了，最上面的就滚到顶栏的玻璃下面去 104339 post:收到第一条 104339",
  "玻璃下的第二条：顶栏是磨砂的，底下滚过去的字会糊成一片颜色，透出来一点点 104339 post:收到第二条 104339",
  "玻璃下的第三条：输入框也是玻璃，浮在消息上面，往上翻的时候消息会从它下面经过 104339 post:收到第三条 104339",
  "玻璃下的第四条：系统要求降低透明度的时候，玻璃换成不透明的底色 104339 post:收到第四条 104339",
]

///|
/// What the test's agent answers message `i` with: each turn waited through to its answer, so what the list holds when
/// it is scrolled is the same in every run, not as far as the agent's answers happened to have come.
fn glass_reply(i : Int) -> String {
  "收到第" + ["一", "二", "三", "四"][i] + "条 104339"
}

///|
/// Whether some of the four messages run under the frosted pane at the top of the window (`top`) or at its foot this
/// frame: their words drawn where the pane is.
fn under_glass(f : @sfreplay.Flow, top~ : Bool) -> Bool {
  let (_, h) = f.t.size()
  let panes = f.t.drawn_glass().filter(fn(g) { g.4 == 5 && (if top { g.1 < h / 2.0 } else { g.1 >= h / 2.0 }) })
  panes.length() > 0 &&
  glass_words.iter().any(fn(words) {
    match (f.t.drawn_of(words), f.t.rect_of(words)) {
      (Some((_, y)), Some((_, _, _, wh))) => panes.iter().any(fn(g) { y < g.1 + g.3 && y + wh > g.1 })
      _ => false
    }
  })
}

///|
/// The window's height: the four run under the bar (the run's fonts' lines as the Tester's are fewer).
let glass_window_h : Double = 700.0

///|
test "29-glass" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("glass"), seed~, h=glass_window_h)
    f.tap("端到端测试")
    f.run_to(@ui.nav_rest())
    f.see("发消息")
    for i, words in glass_words {
      f.tap("发消息")
      f.type_text(words)
      f.tap("icon:arrow-up")
      // the words flown to their bubble
      f.run_for(@sfapp.flight_ms)
      f.see(words)
      f.gone("正在发送")
      // its answer come (in the words sent and in the agent's message)
      f.see_n(2, glass_reply(i))
    }
    // (what came with them in the list in its turn: turns.mbt, one at a time)
    let turns = f.t.rest_of("a chat's list turns")
    if turns > f.t.time() && turns < @double.infinity {
      f.run_to(turns)
    }
    // (the list come to its end after them: gliding to what came at it, the rows over what came in over its end going
    // up for it)
    for moves in ["a list gliding", "Anim \"layout ", "a list's rows' heights"] {
      let rest = f.t.rest_of(moves)
      if rest > f.t.time() && rest < @double.infinity {
        f.run_to(rest)
      }
    }
    // the first scrolled to run on under the top bar's glass (how far it went up past it the layout's: the composer's
    // room under the list, the words' lines)
    let (_, top_y, _, top_h, _, _) = f.t.drawn_glass().filter(fn(g) { g.4 == 5 && g.1 < 100.0 })[0]
    match f.t.rect_of(glass_words[0]) {
      Some((_, y, _, h)) => {
        // (whole points: as the scripted run is told it)
        let down = (top_y + top_h / 2.0 - (y + h / 2.0)).to_int().to_double()
        if down.abs() >= 1.0 {
          f.wheel(-down)
          let eased = f.t.rest_of("wheel ease")
          if eased > f.t.time() && eased < @double.infinity {
            f.run_to(eased)
          }
        }
      }
      None => ()
    }
    assert_true(under_glass(f, top=true))
    f.wheel(-500.0)
    // (eased where its lists have it: a phone's, Android's, go there at once)
    let eased = f.t.rest_of("wheel ease")
    if eased > f.t.time() && eased < @double.infinity {
      f.run_to(eased)
    }
    // scrolled up: what was above runs under the composer's
    assert_true(under_glass(f, top=false))
    f.end()
  })
}
