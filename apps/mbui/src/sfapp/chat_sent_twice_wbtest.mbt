// Words sent soon after words sent, on a chat's page made as nodes (sfbase's chat_page_nodes on): the agent's line is
// the last key then and the new words' key is put before it (chat_body_rows), the first message's time line closing at
// once in that change. A key that comes before keys that stay under it is at the foot for the one reading (the
// coordinator of the migration, 2026-11-14, mbui's list_send_before_tail_test): in every frame a host draws from the
// second press till all rests, no row over the sent rows goes down, the agent's line keeps its distance to the
// composer's top, each sent row is drawn whole at full ink from its own press, and the first's time line is gone from
// the second press's frame. The second sent 0, 200, 1000 and 3000 ms after the first; the core's rows of it 0, 100,
// 400 or 800 ms late; the station taking them 0, 100 or 700 ms after. On 小屏 and 大屏, rows on the host's pixels.

///|
/// The words sent first and second.
let st_first : String = "再看一下"

///|
let st_second : String = "看一下列表"

///|
/// What one frame shows: its moment; each word drawn once over the agent's line by its top (words_said); the agent's
/// line's top and the composer's top; each sent row's words as the tree draws them (top, height, opacity), cut or not;
/// whether a time line or 正在发送 is drawn between the two sent rows.
priv struct StFrame {
  at : Double
  over : Map[String, Double]
  line : Double?
  foot_top : Double?
  first : (Double, Double, Double)?
  second : (Double, Double, Double)?
  cut : String?
  time_between : Bool
}

///|
fn st_row(w : String) -> (Double, Double, Double)? {
  match @ui.view_tree().unwrap().drawn().iter().find_first(fn(d) { d.words.has_prefix(w) && d.bones == 0L }) {
    Some(d) => Some((d.y, d.h, d.alpha))
    None => None
  }
}

///|
fn st_look(t : @ui.Tester) -> StFrame {
  let working = tr("android-chat.chat.working")
  let sending = @sf.t("web-main.chat.sending")
  let line = t.drawn_of(working).map(fn(d) { d.1 })
  let n : Map[String, Int] = Map([])
  let said = t.words_said()
  for w in said {
    n[w.0] = n.get(w.0).unwrap_or(0) + 1
  }
  let over : Map[String, Double] = Map([])
  let first = st_row(st_first)
  let second = st_row(st_second)
  let foot_top = cr_foot_top(t)
  // (over the agent's line where it shows, else over the composer)
  let limit = match (line, foot_top) {
    (Some(l), _) => l - 0.5
    (None, Some(f)) => f
    _ => 0.0
  }
  for w in said {
    guard n.get(w.0) == Some(1) && w.5 > 0.0 && w.2 > 0.0 else { continue }
    guard w.0 != "刚刚" && w.0 != sending && w.0 != working && !w.0.has_prefix(st_second) else { continue }
    if w.2 + w.4 <= limit {
      over[w.0] = w.2
    }
  }
  let time_between = match (first, second) {
    (Some((a, _, _)), Some((b, _, _))) =>
      @ui.view_tree().unwrap().drawn().iter().any(fn(d) { (d.words == "刚刚" || d.words == sending) && d.alpha > 0.0 && d.y > a && d.y < b })
    _ => false
  }
  { at: t.time(), over, line, foot_top, first, second, cut: cr_cut([st_first, st_second], foot_top), time_between }
}

///|
/// The fixture's chat on `screen`, its station taking what is sent `deliver` ms after, the core's row of it `core` ms
/// late; `st_first` sent, `st_second` `after` ms after it: every frame a host draws from the one before the first press
/// till all of it rests, and the index of the second press's look (the frame before it).
fn st_walk(screen : (String, Double, Double, Int), after : Double, deliver : Double, core : Double) -> (Array[StFrame], Int) raise {
  let (_, w, h, platform) = screen
  new_run()
  @sfbase.chat_page_nodes.set(true)
  fix_pace.val = (deliver, 30000.0, fix_turn_end_ms)
  fix_sent_for.val = -1.0
  fix_core_for.val = core
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~)
  t.set_rows_on_pixels(true)
  t.run_for(@ui.move_most_ms)
  guard composer_field(t) is Some((fx, fy, fw, fh)) else { fail("no composer's field") }
  t.tap(fx + fw / 2.0, fy + fh / 2.0)
  t.type_text(st_first)
  t.run_for(@ui.move_most_ms)
  let frames = [st_look(t)]
  t.each_frame(Some(fn() { frames.push(st_look(t)) }))
  tap_send(t)
  if after > 0.0 {
    t.run_shown(after)
  }
  t.type_text(st_second)
  let second = frames.length()
  frames.push(st_look(t))
  tap_send(t)
  t.run_shown(core + deliver + @ui.move_most_ms + 1000.0)
  t.each_frame(None)
  frames.push(st_look(t))
  fix_core_for.val = 0.0
  (frames, second)
}

///|
/// What is wrong among `frames`: a sent row not drawn whole at full ink from its own press (its height otherwise than
/// at rest, cut, or not drawn); from the second press, a word over the agent's line down from the highest it was, the
/// line otherwise from the composer's top than before the press, the first's time line drawn between the two.
fn st_faults(frames : Array[StFrame], second : Int, at : String) -> Array[String] {
  let out = []
  let rest = frames[frames.length() - 1]
  let whole = fn(i : Int, name : String, r : (Double, Double, Double)?, rest_r : (Double, Double, Double)?) {
    match (r, rest_r) {
      (Some((_, h, a)), Some((_, rh, _))) =>
        if (a - 1.0).abs() > 0.001 || (h - rh).abs() > 0.01 {
          out.push("\{at}, frame \{i} at \{frames[i].at}: \{name} drawn \{h} at \{a}, \{rh} at rest")
        }
      (None, _) => out.push("\{at}, frame \{i} at \{frames[i].at}: \{name} drawn nowhere")
      _ => out.push("\{at}: \{name} not drawn at rest")
    }
  }
  for i in 1..<frames.length() {
    whole(i, st_first, frames[i].first, rest.first)
    if i > second {
      whole(i, st_second, frames[i].second, rest.second)
    }
    match frames[i].cut {
      Some(c) => out.push("\{at}, frame \{i} at \{frames[i].at}: \{c}")
      None => ()
    }
  }
  let before = frames[second]
  let high : Map[String, Double] = Map([])
  for k, y in before.over {
    high[k] = y
  }
  let under = match (before.line, before.foot_top) {
    (Some(l), Some(f)) => Some(f - l)
    _ => None
  }
  for i in (second + 1)..<frames.length() {
    let f = frames[i]
    let here = "\{at}, frame \{i} at \{f.at - before.at} after the second press"
    for k, y in f.over {
      match high.get(k) {
        Some(h) => {
          if y > h + 0.01 {
            out.push("\{here}: \{k} down from \{h} to \{y}")
          }
          if y < h {
            high[k] = y
          }
        }
        None => ()
      }
    }
    match (under, f.line, f.foot_top) {
      (Some(u), Some(l), Some(ft)) if ((ft - l) - u).abs() > 0.01 =>
        out.push("\{here}: the agent's line \{ft - l} over the composer's top, \{u} before")
      _ => ()
    }
    if f.time_between {
      out.push("\{here}: the first's time line drawn")
    }
  }
  if out.length() > 6 {
    return out[:6].to_owned() + ["… \{out.length()} in all"]
  }
  out
}

///|
/// Each case of `cases` (deliver, core) with the second sent `after` ms after the first, on both screens.
fn st_cases(after : Double, cases : Array[(Double, Double)]) -> Unit raise {
  let bad = []
  for screen in ss_screens {
    for c in cases {
      let (deliver, core) = c
      let at = "\{screen.0}, after \{after} deliver \{deliver} core \{core}"
      let (frames, second) = st_walk(screen, after, deliver, core)
      bad.append(st_faults(frames, second, at))
    }
  }
  for b in bad {
    println("SENTTWICE " + b)
  }
  if bad.length() > 0 {
    fail("\{bad.length()} faults: " + bad[:bad.length().min(8)].to_owned().join("; "))
  }
}

///|
test "a chat's page made as nodes, 小屏 and 大屏: the second words sent at once after the first (the first still on its way): every sent row whole from its press, nothing over them down, the agent's line kept against the composer" {
  st_cases(0.0, [(700.0, 0.0), (100.0, 400.0), (0.0, 800.0)])
}

///|
test "a chat's page made as nodes, 小屏 and 大屏: the second words sent 200 ms after the first: every sent row whole from its press, nothing over them down, the agent's line kept against the composer" {
  st_cases(200.0, [(700.0, 0.0), (0.0, 100.0), (100.0, 800.0)])
}

///|
test "a chat's page made as nodes, 小屏 and 大屏: the second words sent 1000 ms after the first (the agent's line last, the first's time line under it): nothing over them down, the agent's line kept against the composer, the time line gone in the press's frame" {
  st_cases(1000.0, [(0.0, 100.0), (100.0, 0.0), (100.0, 400.0), (0.0, 800.0)])
}

///|
test "a chat's page made as nodes, 小屏 and 大屏: the second words sent 3000 ms after the first: nothing over them down, the agent's line kept against the composer, the time line gone in the press's frame" {
  st_cases(3000.0, [(700.0, 400.0), (0.0, 100.0), (700.0, 800.0)])
}
