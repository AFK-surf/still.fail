// A chat's outline as the made-up core says it (the core's `chatOutline`, `chat.outline.rows`, `chat.bring`,
// `chat.outline.find`: views.ts #chatOutline, outlineRows, outlineFound): the outline an index of what people said in
// the chat's thread (7), by the day, oldest first (each day's key, its heading, its messages' seqs; whether someone
// other than the viewer said one), the rows' words asked for by their seqs, a hundred at most, each one line of 64
// columns; what is found the newest fifty, `more` the rest. The modes
// "chat-outline…" (sfapp fixture_open.mbt) open the fixture's first chat as a long one of two people over four days
// (outline_chat: 林, the viewer, and Ana; Claude answering between), some forty things each said at length, as people
// write them; "chat-outline-long…" as one of three hundred over twelve days (outline_long: 240 said by people), its
// list holding the last forty; every other mode's chat says its own people's messages, all of them today.
// "chat-outline-bringing": not all of it is on the device yet (`whole` false). Each asks its parameters as the real
// core reads them (calls.ts parseCall, protocol.ts TOPICS), failing without them. Every word here is made up.

///|
/// The long chat's days: each one's key and its heading as the core says it (format.dayLabel, today the 10th of
/// November, a Tuesday).
// kept across runs: a table, never written
let outline_days : Array[(String, String)] = [
  ("2026-11-07", "星期六"),
  ("2026-11-08", "星期日"),
  ("2026-11-09", "昨天"),
  ("2026-11-10", "今天"),
]

///|
/// The longer one's twelve days.
// kept across runs: a table, never written
let outline_long_days : Array[(String, String)] = [
  ("2026-10-30", "10月30日"),
  ("2026-10-31", "10月31日"),
  ("2026-11-01", "11月1日"),
  ("2026-11-02", "11月2日"),
  ("2026-11-03", "11月3日"),
  ("2026-11-04", "星期三"),
  ("2026-11-05", "星期四"),
  ("2026-11-06", "星期五"),
  ("2026-11-07", "星期六"),
  ("2026-11-08", "星期日"),
  ("2026-11-09", "昨天"),
  ("2026-11-10", "今天"),
]

///|
/// What is said in the long chat, in order: on which day, who (林 the viewer, Ana, Claude), its time of day, its words.
// kept across runs: a table, never written
let outline_said : Array[(Int, String, String, String)] = [
  (0, "林", "09:12", "早，今天想把发布清单从头到尾过一遍：签名、更新日志、商店截图、深色模式，还有夜里的构建，先列出来再分人"),
  (0, "Claude", "09:13", "好，我先把清单拆成九项，标上谁在做、卡在哪里。"),
  (0, "Ana", "09:40", "签名证书下周三过期，我建议这次发布前就换新证书，不然商店那边会拒收更新包"),
  (0, "林", "10:05", "同意换证书。macOS 的公证要多久？上次排队排了快两个小时，我们得把这个时间算进发布那天的计划里"),
  (0, "Claude", "10:07", "公证一般二十分钟内，排队高峰会到一小时以上。"),
  (0, "Ana", "11:30", "Windows 的令牌还在办公室的签名机上，远程签不了，周一我去插一下令牌，你们先别等我"),
  (0, "林", "14:20", "列表加载更早的消息时会不会跳？我昨天在 iPad 上往上翻，屏幕上的内容往下掉了一截又弹回来"),
  (0, "Claude", "14:25", "复现了，是图片还没量好高度就当成了锚点，我改成按估计高度占位。"),
  (0, "林", "16:48", "顺便看一下首页的列表：按天分组以后，“今天”的标题和第一行挨得太近，和设计稿对不上"),
  (0, "Ana", "18:10", "Release notes for 2.4 still mention the old sync screen; can someone rewrite that paragraph before we freeze the strings?"),
  (1, "林", "10:02", "周末也看了一眼夜里的构建，又红了，是测试机磁盘满了还是我们的问题？日志里只看到 ENOSPC"),
  (1, "Claude", "10:04", "是磁盘满了：旧的构建产物没清，我加了一步清理。"),
  (1, "Ana", "11:15", "引导页第二屏的插画可以换成新的那版吗？现在这张在小屏上会把下面的按钮顶到屏幕外面去"),
  (1, "林", "11:40", "可以换，但要先确认深色模式下的颜色，新插画的背景是透明的，放在深色底上边缘会发白"),
  (1, "Claude", "11:42", "深色模式下边缘确实发白，我给插画加了一层描边。"),
  (1, "Ana", "15:20", "商店截图我拍了 iPhone 和 iPad 两套，iPad 那几张字有点小，你们看看要不要放大重拍"),
  (1, "林", "16:05", "iPad 的字放大到 120% 重拍吧，另外 Google Play 的头图还是旧的列表，那张是设计手工做的"),
  (1, "Ana", "17:30", "设计说头图周一给，到时候我直接换上去，不用再走一遍审核流程了吧？"),
  (1, "林", "21:40", "不用走审核。明早我来看截图的初稿，有问题直接在这里说，我们周四上午发"),
  (2, "林", "09:02", "早，昨晚的构建用新证书签名成功了吗？我看邮件里没有失败的通知，但也没看到成功的"),
  (2, "Claude", "09:05", "成功了：macOS 包已经签名、公证完成，Windows 包等令牌。"),
  (2, "Ana", "09:40", "截图初稿我看了，iPad 那几张字还是小，第三张的状态栏也没隐藏，我标出来发你"),
  (2, "林", "10:35", "引导页第二屏的插画可以换成新的那版了，深色模式下描边看起来没问题，你们再确认一下"),
  (2, "Ana", "11:20", "首页的列表改成按天分组了，截图里还是旧的样子，要不要等这个改完再统一重拍一次？"),
  (2, "林", "13:45", "更新日志再看一遍，2.4 的崩溃修复写得太技术了，用户看不懂“空指针”是什么意思"),
  (2, "Claude", "13:50", "我改成了“修复了打开某些对话时会闪退的问题”。"),
  (2, "Ana", "15:10", "新证书的签名在我这台 Mac 上验证过了，codesign 和 spctl 都通过，公证的票据也在"),
  (2, "林", "16:30", "把新证书切到 CI 上吧，今晚的构建就用它签名，旧证书先留着回滚"),
  (2, "Ana", "18:10", "深色模式的颜色改完了吗？我这边看到图片查看器的关闭按钮在深色模式下还是黑的"),
  (2, "林", "21:40", "查看器的关闭按钮我今晚修好，明早再过一遍深色模式的截图"),
  (3, "林", "09:02", "三个平台的包都用新证书签名了吗？都签好的话今天下午就开始准备周四的发布"),
  (3, "Claude", "09:05", "成功了，三个平台的包都签好了，CI 的缓存修复也已经合进去。"),
  (3, "Ana", "09:40", "重拍的 iPad 截图放进共享文件夹了，字已经放大到 120%，状态栏也都隐藏了"),
  (3, "林", "10:35", "新插画已经合进主分支，描边我在 Pixel 和 iPhone 的深色模式下都看过，没问题"),
  (3, "Ana", "11:20", "Play 的头图设计今天早上发过来了，尺寸是 1024×500，我直接替换商店里的旧图"),
  (3, "林", "12:15", "发布前还差哪些？按人分一下剩下的事，方便我们排时间，最好今天下班前能对齐"),
  (3, "Claude", "12:22", "还差三项：Windows 令牌、英文更新日志的三条、深色模式的启动画面。"),
  (3, "林", "13:50", "CI 的那个缓存修复合进去了吗？昨晚的构建时间比前天少了一半，我猜是它起作用了"),
  (3, "Ana", "14:20", "在 Android 上往上翻了二十分钟很久以前的对话，没再看到内容掉一截又弹回来"),
  (3, "林", "14:40", "还有深色模式也看一下，启动画面那张图在深色模式下边缘有一圈白，挺显眼的"),
]

///|
/// Whether a fixture mode shows the long chat of two people (outline_chat).
pub fn outline_mode(mode : String) -> Bool {
  mode.has_prefix("chat-outline")
}

///|
/// Whether it shows the longer one (outline_long).
fn outline_long_mode(mode : String) -> Bool {
  mode.has_prefix("chat-outline-long")
}

///|
/// The long chat's message the "chat-outline…" modes have the list away at (its top: some way into 昨天).
pub let outline_away_seq : Double = 22.0

///|
/// The longer chat's (some way into its 昨天, the last forty of it in the list).
pub let outline_long_away_seq : Double = 283.0

///|
/// How many of the longer chat's last messages its list holds.
let outline_long_held : Int = 40

///|
/// The longer chat: twelve days of twenty-five messages each, every fifth after the first Claude's, the others 林's and
/// Ana's in turn, their words those of the long chat's said again: day, who, time of day, words, as outline_said.
fn outline_long() -> Array[(Int, String, String, String)] {
  let people = outline_said.filter(fn(s) { s.1 != "Claude" })
  let agents = outline_said.filter(fn(s) { s.1 == "Claude" })
  let out : Array[(Int, String, String, String)] = []
  for d in 0..<outline_long_days.length() {
    for j in 0..<25 {
      let n = d * 25 + j
      let minutes = 9 * 60 + j * 28
      let clock = "\{(minutes / 60 / 10)}\{(minutes / 60 % 10)}:\{(minutes % 60 / 10)}\{(minutes % 10)}"
      if j % 5 == 1 {
        out.push((d, "Claude", clock, agents[n % agents.length()].3))
      } else {
        out.push((d, if j % 2 == 0 { "林" } else { "Ana" }, clock, people[n % people.length()].3))
      }
    }
  }
  out
}

///|
/// What mode `mode`'s long chat says (outline_said, or the longer one's), and its days.
fn outline_table(mode : String) -> (Array[(Int, String, String, String)], Array[(String, String)]) {
  if outline_long_mode(mode) {
    (outline_long(), outline_long_days)
  } else {
    (outline_said, outline_days)
  }
}

///|
/// The messages of mode `mode`'s long chat, each with its day: seq i + 1 the ith said.
fn outline_all(mode : String) -> Array[(Int, Json)] {
  let claude = by_agent("anthropic", "claude", "s-c1")
  let (said, days) = outline_table(mode)
  let last = days.length() - 1
  said.mapi(fn(i, s) {
    let (day, who, clock, words) = s
    let seq = i + 1
    let ago = if day == last { clock } else { days[day].1 + " " + clock }
    let m = match who {
      "Claude" => msg(seq, "agent", claude, words, ago, {})
      "林" => msg(seq, "person", by_person("林"), words, ago, { "mine": true, "author": "lin@example.com" })
      _ => msg(seq, "person", by_person("Ana"), words, ago, { "author": "ana@example.com" })
    }
    (day, m)
  })
}

///|
/// The long chat (the fixture's first, 整理发布清单) of mode `mode`: what it says as its messages (the longer one's
/// last forty, the rest before them not in its window, till the page before or one round a message of them is asked
/// for: `around`, all of it), its
/// people the viewer and Ana.
pub fn outline_chat(mode : String, around? : Bool = false) -> Json {
  let all = outline_all(mode).map(fn(dm) { dm.1 })
  let long = outline_long_mode(mode) && !around
  let messages = if long { all[all.length() - outline_long_held:].to_owned() } else { all }
  match rich_chat(0) {
    Object(m) => {
      let o = m.copy()
      o["messages"] = Json::array(messages)
      o["more"] = Json::boolean(long)
      Json::object(o)
    }
    v => v
  }
}

///|
/// The messages of the chat a mode shows in thread 7 (the long chat's, else the first chat's, every page before it
/// included, whatever its window shows), each with its day. The core's outline is of all the device holds of a chat, not
/// of its page's window (views.ts #chatOutline, #peopleSaid): a `chat.older` answered from the device sends it nothing.
fn outline_messages(f : Fixture) -> Array[(Int, Json)] {
  if outline_mode(f.mode) {
    outline_all(f.mode)
  } else {
    items(Some(rich_chat(rich_chat_pages)), "messages").map(fn(m) { (0, m) })
  }
}

///|
/// The days of the chat a mode shows (key, heading): the long chat's, else today alone.
fn outline_days_of_mode(f : Fixture) -> Array[(String, String)] {
  if outline_mode(f.mode) {
    outline_table(f.mode).1
  } else {
    [("2026-11-10", "今天")]
  }
}

///|
/// The parameters a chat's outline is asked with, as the core reads them: its station and thread (None: one missing).
fn outline_asked(params : Json) -> (String, Double)? {
  match (field(Some(params), "station"), field(Some(params), "thread")) {
    (Some(String(st)), Some(Number(th, ..))) if st != "" => Some((st, th))
    _ => None
  }
}

///|
/// What a message is as a row of the outline (`chat.outline.rows`'s OutlineRow; a found one's OutlineFound, `snippet`
/// its line with the words).
fn outline_item_of(m : Json, found : String?) -> Json {
  let v = Some(m)
  let kind = text(v, "authorKind")
  let o : Map[String, Json] = {
    "seq": Json::number(number(v, "seq")),
    "mine": Json::boolean(flag(v, "mine")),
    "author": Json::string(text(v, "author")),
    "by": field(v, "by").unwrap_or(Json::object({})),
    "clock": Json::string(outline_clock(text(field(v, "time").bind(fn(t) { field(Some(t), "createdAt") }), "ago"))),
  }
  match found {
    Some(snippet) => {
      o["agent"] = Json::boolean(kind == "agent")
      o["system"] = Json::boolean(kind == "ember")
      o["snippet"] = Json::string(snippet)
    }
    None =>
      o["words"] = Json::string(outline_cut(text(v, "text").split("\n").next().map(fn(l) { l.to_owned() }).unwrap_or("")))
  }
  Json::object(o)
}

///|
/// A message's time of day as the core says it (14:05), from what the fixture says of when ("昨天 14:05"; another's
/// "3 小时前": none).
fn outline_clock(ago : String) -> String {
  let last = ago.split(" ").fold(init="", fn(_, p) { p.to_owned() })
  if last.length() == 5 && last.contains(":") {
    last
  } else {
    ""
  }
}

///|
/// What people said in the chat a mode shows (not agents' nor still.fail's), each with its day.
fn outline_people(f : Fixture) -> Array[(Int, Json)] {
  outline_messages(f).filter(fn(dm) { text(Some(dm.1), "authorKind") == "person" && !flag(Some(dm.1), "system") })
}

///|
/// The fixture's `chatOutline` {station, thread}: the index of what people said, by the day (each its key, its
/// heading, its messages' seqs, oldest first), how many, whether someone other than the viewer said one.
pub fn fixture_outline(f : Fixture, params : Map[String, Json]) -> Json? {
  guard outline_asked(Json::object(params)) is Some((_, 7.0)) else { return None }
  let said = outline_people(f)
  let names = outline_days_of_mode(f)
  let days : Array[Json] = []
  let mut day = -1
  let mut seqs : Array[Json] = []
  let flush = fn(d : Int, seqs : Array[Json]) {
    if d >= 0 {
      days.push({ "date": Json::string(names[d].0), "day": Json::string(names[d].1), "seqs": Json::array(seqs) })
    }
  }
  for dm in said {
    if dm.0 != day {
      flush(day, seqs)
      day = dm.0
      seqs = []
    }
    seqs.push(Json::number(number(Some(dm.1), "seq")))
  }
  flush(day, seqs)
  let whole = f.mode != "chat-outline-bringing"
  let n = said.length()
  Some({
    "days": Json::array(days),
    "count": Json::number(n.to_double()),
    "others": Json::boolean(said.iter().any(fn(dm) { !flag(Some(dm.1), "mine") })),
    "held": Json::number(n.to_double()),
    "of": Json::number((if whole { n } else { n + 120 }).to_double()),
    "whole": Json::boolean(whole),
  })
}

///|
/// Items with their days as the core puts them: a day each, keyed and headed, oldest first.
fn outline_days_of(dated : Array[(Int, Json)], f : Fixture) -> Json {
  let names = outline_days_of_mode(f)
  let days : Array[Json] = []
  let mut day = -1
  let mut now : Array[Json] = []
  for x in dated {
    if x.0 != day {
      if day >= 0 {
        days.push({ "date": Json::string(names[day].0), "day": Json::string(names[day].1), "items": Json::array(now) })
      }
      day = x.0
      now = []
    }
    now.push(x.1)
  }
  if day >= 0 {
    days.push({ "date": Json::string(names[day].0), "day": Json::string(names[day].1), "items": Json::array(now) })
  }
  Json::array(days)
}

///|
/// How many rows `chat.outline.rows` gives at most (OUTLINE_ROWS), and how many `chat.outline.find` lists (its newest;
/// `more` the rest: OUTLINE_FOUND).
let outline_rows_most : Int = 100

///|
let outline_found_most : Int = 50

///|
/// How many columns a row's words and a found line are cut to (OUTLINE_WORDS: a character from U+1100 on two), and how
/// far before the words a found line starts at most (SNIPPET_LEAD).
let outline_words_most : Int = 64

///|
/// Words cut to outline_words_most columns, `…` after where cut (views.ts cutWords).
fn outline_cut(words : String) -> String {
  let out = StringBuilder()
  let mut columns = 0
  for c in words {
    columns += if c.to_int() >= 0x1100 { 2 } else { 1 }
    if columns > outline_words_most {
      return out.to_string() + "…"
    }
    out.write_char(c)
  }
  words
}

///|
/// The fixture's `chat.bring`, `chat.outline.rows` and `chat.outline.find`, as the core answers them (None: another
/// call).
pub fn fixture_outline_call(f : Fixture, name : String, params : Json) -> Result[Json, Json]? {
  match name {
    "chat.bring" | "chat.outline.rows" | "chat.outline.find" => ()
    // (the longer chat's window round a message it does not hold: all of it, as the core reads the page it is in)
    "chat.around" if outline_long_mode(f.mode) && f.older == 0 => {
      f.older = 1
      f.changed()
      return Some(Ok(Json::object({})))
    }
    _ => return None
  }
  guard outline_asked(params) is Some(_) else {
    return Some(Err({ "code": "bad_request", "message": "缺少 station 或 thread" }))
  }
  let all = outline_messages(f)
  let n = Json::number(all.length().to_double())
  if name == "chat.bring" {
    return Some(Ok({ "held": n, "of": n, "whole": true }))
  }
  if name == "chat.outline.rows" {
    // (the rows asked for, in the order asked; one the device does not hold left out)
    guard field(Some(params), "seqs") is Some(Array(asked)) && asked.length() <= outline_rows_most else {
      return Some(Err({ "code": "bad_request", "message": "seqs: 至多 \{outline_rows_most} 个" }))
    }
    let rows = asked.filter_map(fn(q) {
      match q {
        Number(seq, ..) => all.iter().find_first(fn(dm) { number(Some(dm.1), "seq") == seq }).map(fn(dm) { outline_item_of(dm.1, None) })
        _ => None
      }
    })
    return Some(Ok({ "rows": Json::array(rows) }))
  }
  guard field(Some(params), "query") is Some(String(query)) else {
    return Some(Err({ "code": "bad_request", "message": "缺少 query" }))
  }
  let words = query.to_lower().split(" ").filter(fn(w) { w.length() > 0 }).map(fn(w) { w.to_owned() }).collect()
  let found = all.filter(fn(dm) {
    let said = text(Some(dm.1), "text").to_lower()
    words.length() > 0 && words.iter().all(fn(w) { said.contains(w) })
  })
  // (the newest found listed, fifty at most, oldest first; how many older are not)
  let listed = if found.length() > outline_found_most {
    found[found.length() - outline_found_most:].to_owned()
  } else {
    found
  }
  // (with `bring` the rest of it: all on the device here, but "chat-outline-bringing"'s first answer is of what is held)
  let whole = f.mode != "chat-outline-bringing" || flag(Some(params), "bring")
  Some(
    Ok({
      "words": Json::array(words.map(fn(w) { Json::string(w) })),
      "days": outline_days_of(listed.map(fn(dm) { (dm.0, outline_item_of(dm.1, Some(outline_snippet(text(Some(dm.1), "text"), words)))) }), f),
      "total": Json::number(found.length().to_double()),
      "more": Json::number((found.length() - listed.length()).to_double()),
      "held": n,
      "of": n,
      "whole": Json::boolean(whole),
    }),
  )
}

///|
/// The line of `said` with the first of `words` in it, as the core cuts it (refs.ts excerpt): from a few letters before
/// the words (at a word's start where one is near), "…" where it is cut, one line of outline_words_most columns.
fn outline_snippet(said : String, words : Array[String]) -> String {
  let line = said.split("\n").find_first(fn(l) { words.iter().any(fn(w) { l.to_owned().to_lower().contains(w) }) })
  let line = line.map(fn(l) { l.to_owned() }).unwrap_or(said)
  let at = words.fold(init=line.length(), fn(m, w) {
    match line.to_lower().find(w) {
      Some(i) if i < m => i
      _ => m
    }
  })
  if at > outline_snippet_lead && at < line.length() {
    // (at a word's start where there is one near, as the core's: not in a word's middle)
    let from = at - outline_snippet_lead
    let from = match line.clamped_view(start=from).find(" ") {
      Some(i) if from + i < at => from + i + 1
      _ => from
    }
    outline_cut("…" + line.clamped_view(start=from).to_owned())
  } else {
    outline_cut(line)
  }
}

///|
/// How many letters before the words a found line keeps at most (SNIPPET_LEAD's).
let outline_snippet_lead : Int = 12
