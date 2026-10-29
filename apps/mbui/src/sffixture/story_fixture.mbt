// A told story over the first row's chat (MBUI_FIXTURE=chat-story with a story given: sffilm's MBUI_STORY, a JSON
// file), for the films of still.fail in use: the chat as the story opens it (its title, what was said before), and what
// its agent does as the viewer acts: after each message sent (`sent`: one list of steps for each, in turn) and each
// card answered (`answered`), steps each `at` ms after it: its agent at work or done (`working`), what it does now
// (`activity`), a message posted (`post`: its words, files, a card's options, how its turn ends). Its files' pictures
// are the story's own (`pictures`: PNGs in base64 by name).
//   { "title": "Acme App",
//     "before": [{"kind": "person" | "agent", "text": …, "when": "昨天", "files": [{"name", "w", "h", "size"}]}],
//     "sent": [[{"at": 400, "working": true}, {"at": 600, "activity": "搜索 LoginButton"},
//               {"at": 3000, "post": {"text": …, "files": […], "placed": […], "options": [{"label", "detail",
//                "recommended"}], "ending": "all_done"}}]],
//     "answered": [[…]],
//     "opened": [[…]],   (steps done as the chat is first read, at once: what its agent posted as it opened)
//     "pictures": {"before.png": "<base64>"},
//     "words": {"整理发布清单": "Release checklist", …} }
// A story told in another language says the made-up chats' words in it (`words`: each of their words as a whole, its
// own; the app's own words are its locale's, MBUI_LOCALE).

///|
/// The story told (none: the made-up chats as they are).
pub let fix_story : Ref[Json?] = { val: None }

///|
/// What the story's agent does now, as its `live` topic says it: its key and words ("" nothing said).
let story_now : Ref[(String, String)] = { val: ("", "") }

///|
/// How many messages were sent and cards answered in the story so far.
let story_sent : Ref[Int] = { val: 0 }

///|
let story_answered : Ref[Int] = { val: 0 }


///|
/// The story's chat as it opens: its title and what was said before.
pub fn story_chat(story : Json) -> Json {
  // (its `opened` steps in its chat as it is read, each once: what the chat's made-up state holds, as it may be begun
  // again, not a flag)
  match items(Some(story), "opened") {
    [Array(steps), ..] =>
      for k, s in steps {
        let ts = "opened\{k}"
        if !fix_chat("s-c1").sent.iter().any(fn(m) { text(Some(m), "ts") == ts }) {
          story_step(s, ts~)
        }
      }
    _ => ()
  }
  let session = "s-c1"
  let claude = by_agent("anthropic", "claude", session)
  let before = items(Some(story), "before")
  let messages = before.mapi(fn(i, b) {
    let kind = text(Some(b), "kind")
    let more : Map[String, Json] = { "attachments": Json::array(story_files(b)) }
    // (a person's: the viewer's, or another's by their name, `by`: one in the Slack thread it came from)
    let by = text(Some(b), "by")
    if kind == "person" && by == "" {
      more["mine"] = Json::boolean(true)
      more["author"] = Json::string("lin@example.com")
    }
    // (an agent's asking: its card's options, answered here as the story's are, its steps after it `answered`'s)
    let options = items(Some(b), "options")
    if options.length() > 0 {
      more["ending"] = "need_decision"
      more["card"] = { "type": "options", "assigneeText": "待你决定", "options": Json::array(options) }
      more["decision"] = { "resolved": false }
      more["asked"] = true
    }
    let who = if kind == "agent" { claude } else if by != "" { by_person(by) } else { by_person("林") }
    msg(i + 1, kind, who, text(Some(b), "text"), text(Some(b), "when"), more)
  })
  {
    "archived": false,
    "me": { "email": "lin@example.com" },
    "thread": { "id": 7, "unread": 0 },
    "title": Json::string(text(Some(story), "title")),
    // (one that came from Slack: the channel it was asked in, `place`)
    "place": Json::string(text(Some(story), "place")),
    "people": [],
    "agents": [
      {
        "session": {
          "key": Json::string(session),
          "runtime": "claude",
          "maker": { "id": "anthropic", "name": "Anthropic" },
          "agentText": "Claude",
          "statusText": "未开始",
          "tone": "neutral",
        },
        "status": "idle",
        // (a story with a web service: its agent's dev server, up)
        "jobs": if field(Some(story), "service") is Some(_) { [fix_job("j-web")] } else { [] },
      },
    ],
    "messages": Json::array(messages),
    "more": false,
    "newer": false,
    "outbox": [],
    "offline": false,
    "asks": [],
  }
}

///|
/// A step's or an earlier message's files, as a message has them.
fn story_files(v : Json) -> Array[Json] {
  items(Some(v), "files").map(fn(x) {
    file(text(Some(x), "name"), number(Some(x), "w").to_int(), number(Some(x), "h").to_int(), number(Some(x), "size").to_int())
  })
}

///|
/// The story's `live` for its agent: what it does now.
pub fn story_live() -> Json {
  let (key, words) = story_now.val
  if words == "" {
    { "loaded": true }
  } else {
    { "loaded": true, "activity": { "now": { "key": Json::string(key), "text": Json::string(words) } } }
  }
}

///|
/// A picture of the story's by its file's name, as PNG bytes (None: not one of its).
pub fn story_picture(name : String) -> Bytes? {
  match field(field(fix_story.val, "pictures"), name) {
    Some(String(b)) => Some(@codec.from_base64(b))
    _ => None
  }
}

///|
/// What the story's agent does after the `n`th message sent (from 0), or `answered` the `n`th card answered.
fn story_play(list : String, n : Int) -> Unit {
  let lists = items(fix_story.val, list)
  guard n < lists.length() else { return }
  guard lists[n] is Array(steps) else { return }
  for s in steps {
    fix_later(number(Some(s), "at"), fn() { story_step(s) })
  }
}

///|
/// One of the story's steps done: its agent at work or done, what it does now, what it posts (as `ts`, where given).
fn story_step(s : Json, ts? : String) -> Unit {
  let session = "s-c1"
  let fc = fix_chat(session)
  match field(Some(s), "working") {
    Some(True) => fc.working = @ui.now()
    Some(False) => {
      fc.working = -1.0
      story_now.val = ("", "")
    }
    _ => ()
  }
  match text(Some(s), "activity") {
    "" => ()
    words => story_now.val = ("step:" + number(Some(s), "at").to_string(), words)
  }
  match field(Some(s), "post") {
    Some(p) => {
      fix_serial.val += 1
      let seq = 200 + fix_serial.val
      let more : Map[String, Json] = {
        "ts": Json::string(ts.unwrap_or("story\{fix_serial.val}")),
        "said": true,
        "attachments": Json::array(story_files(p)),
        "placed": Json::array(items(Some(p), "placed")),
      }
      match text(Some(p), "ending") {
        "" => ()
        e => more["ending"] = Json::string(e)
      }
      let options = items(Some(p), "options")
      if options.length() > 0 {
        more["ending"] = "need_decision"
        more["card"] = { "type": "options", "assigneeText": "待你决定", "options": Json::array(options) }
        more["decision"] = { "resolved": false }
        more["asked"] = true
      }
      // (an agent asking to keep a secret the viewer types in, or to use one: its vault card, `vault` the request as
      // its card says it, with its `request` id)
      match field(Some(p), "vault") {
        Some(ask) =>
          more["card"] = { "type": "options", "vault": Json::string(text(Some(ask), "request")), "vaultAsk": ask }
        None => ()
      }
      // (another person's, `by`: one in the Slack thread the chat came from)
      match text(Some(p), "by") {
        "" => fc.sent.push(msg(seq, "agent", by_agent("anthropic", "claude", session), text(Some(p), "text"), "刚刚", more))
        by => fc.sent.push(msg(seq, "person", by_person(by), text(Some(p), "text"), "刚刚", more))
      }
    }
    None => ()
  }
}

///|
/// A message the story's viewer sent is in the chat: its agent's steps after it (each done as the fixture is next read:
/// fix_tick, a change).
pub fn story_on_sent() -> Unit {
  story_play("sent", story_sent.val)
  story_sent.val += 1
}

///|
/// A card of the story's answered with `label` (its message `seq`): the answer in the chat after what came before it,
/// then its agent's steps after it.
pub fn story_on_answer(f : Fixture, seq : Int, label : String) -> Unit {
  fix_decided[seq] = decided_json(label)
  fix_serial.val += 1
  fix_chat("s-c1").sent.push(
    msg(200 + fix_serial.val, "person", by_person("林"), label, "刚刚", {
      "mine": true,
      "author": "lin@example.com",
      "said": true,
      "ts": Json::string("story\{fix_serial.val}"),
    }),
  )
  f.changed()
  story_play("answered", story_answered.val)
  story_answered.val += 1
}

///|
/// The story's chat's row in the list as it says it (`row`: what of the row it says, over the first row's: its title,
/// that it came from Slack, its last words), else as it is.
///   "row": { "title": …, "connect": "slack-1", "originText": "Slack · Acme · #support", "last": "…", "unread": true }
pub fn story_row(r : Json) -> Json {
  guard text(Some(r), "id") == "c1" && field(fix_story.val, "row") is Some(Object(over)) else { return r }
  guard r is Object(m) else { return r }
  let o = m.copy()
  for k, v in over {
    o[k] = match (k, v) {
      ("last", String(words)) => last(words)
      _ => v
    }
  }
  if over.contains("last") {
    for k in ["state", "tone", "stateText", "stateLead", "stateRest"] {
      o.remove(k)
    }
  }
  Json::object(o)
}

///|
/// What asks the person on a real host (sffix's: the system's prompt, Touch ID or Face ID, with the reason in it):
/// begun with the reason, then asked how it went (0 not yet, 1 yes, 2 no). None: nothing to ask (a Tester), yes at once.
pub let story_ask_person : Ref[((String) -> Unit, () -> Int)?] = { val: None }

///|
/// The story's vault card (a post's `vault`) answered here (`vault.approve`, `vault.deny` for its `request`): allowed, the
/// vault unlocked first as the core unlocks it (the system's prompt, its reason the card's `unlock`); then how it went on
/// its card at once, as the core puts it, and its agent's steps after it (`answered`, in turn with the cards). False
/// where it is not the story's.
pub fn story_vault_answer(f : Fixture, name : String, params : Json) -> Bool {
  let request = text(Some(params), "request")
  let fc = fix_chat("s-c1")
  let at = fc.sent.search_by(fn(m) { text(field(Some(m), "card"), "vault") == request })
  guard request != "" && at is Some(i) else { return false }
  let approved = name == "vault.approve"
  let settle = fn(yes : Bool) {
    match fc.sent[i] {
      Object(m) => {
        let o = m.copy()
        let card = match o.get("card") {
          Some(Object(c)) => c.copy()
          _ => Map([])
        }
        let ask = match card.get("vaultAsk") {
          Some(Object(a)) => a.copy()
          _ => Map([])
        }
        ask["status"] = Json::string(if yes { "granted" } else { "denied" })
        card["vaultAsk"] = Json::object(ask)
        o["card"] = Json::object(card)
        fc.sent[i] = Json::object(o)
      }
      _ => ()
    }
    f.changed()
    if yes {
      story_play("answered", story_answered.val)
      story_answered.val += 1
    }
  }
  match (approved, story_ask_person.val) {
    (true, Some((ask, asked))) => {
      ask(text(field(field(Some(fc.sent[i]), "card"), "vaultAsk"), "unlock"))
      fn wait() {
        match asked() {
          0 => fix_later(100.0, wait)
          n => settle(n == 1)
        }
      }
      wait()
    }
    _ => settle(approved)
  }
  true
}

///|
/// `v` with the made-up chats' words as the story says them in its language (its `words`: each string of `v` that is
/// one of them, whole), where it says any.
pub fn story_words(v : Json) -> Json {
  let words = match fix_story.val {
    Some(Object(o)) =>
      match o.get("words") {
        Some(Object(w)) => w
        _ => return v
      }
    _ => return v
  }
  fn go(v : Json) -> Json {
    match v {
      String(s) =>
        match words.get(s) {
          Some(String(t)) => Json::string(t)
          _ => v
        }
      Array(a) => Json::array(a.map(go))
      Object(o) => {
        let out : Map[String, Json] = Map([])
        for k, x in o {
          out[k] = go(x)
        }
        Json::object(out)
      }
      _ => v
    }
  }
  go(v)
}

///|
/// The story's station screen (`screen`), when it has one: what an agent does on it, seen live. Its card's words, its
/// state as the core says it, its frames each `at` ms after it is asked for (`frames`: a picture of the story's by its
/// name), as the station streams them:
///   "screen": { "title": "Checkout - localhost:5173", "line": "Watching · Claude is driving", "agent": "Claude",
///               "width": 1280, "height": 800, "frames": [{"at": 0, "picture": "screen-0.jpg"}, …] }
fn story_screen() -> Json? {
  field(fix_story.val, "screen")
}

///|
/// The story screen's card (`screenCard`): its title, who is on it, its preview's size.
pub fn story_screen_card(screen : String) -> Json? {
  guard story_screen() is Some(s) else { return None }
  Some({
    "kind": "browser",
    "title": Json::string(text(Some(s), "title")),
    "line": Json::string(text(Some(s), "card")),
    "link": Json::string("/w/ws1/s/st1/screen/" + screen),
    "gone": false,
    "peek": true,
    "width": Json::number(number(Some(s), "width")),
    "height": Json::number(number(Some(s), "height")),
  })
}

///|
/// `screen.view` over the story's screen: its preview (`peek`) the first frame; seen, live, the agent driving it and this
/// view looking on, each frame at its time.
pub fn story_screen_stream(params : Json, on_value : (Json, Bytes?) -> Unit) -> Int? {
  guard story_screen() is Some(s) else { return None }
  let frames = items(Some(s), "frames")
  let picture = fn(f : Json) -> Bytes? { story_picture(text(Some(f), "picture")) }
  fix_stream_ids.val += 1
  if params is Object(o) && o.get("peek") is Some(True) {
    let first = if frames.length() > 0 { picture(frames[0]) } else { None }
    fix_later(0.0, fn() { on_value({ "frame": { "ts": 1 } }, first) })
    return Some(fix_stream_ids.val)
  }
  let w = number(Some(s), "width")
  let h = number(Some(s), "height")
  let agent = text(Some(s), "agent")
  fix_later(0.0, fn() {
    on_value(
      {
        "state": {
          "phase": "live",
          "title": Json::string(text(Some(s), "title")),
          "kind": "browser",
          "control": false,
          "may": true,
          "others": [Json::string(agent)],
          "controllers": [Json::string(agent)],
          "takeOver": true,
          "line": Json::string(text(Some(s), "line")),
          "codec": "jpeg",
          "width": Json::number(w),
          "height": Json::number(h),
        },
      },
      None,
    )
    on_value({ "config": { "codec": "jpeg", "width": Json::number(w), "height": Json::number(h) } }, None)
  })
  for i, f in frames {
    let ts = number(Some(f), "at")
    fix_later(ts, fn() { on_value({ "frame": { "key": true, "ts": Json::number(1000.0 + ts + i.to_double()) } }, picture(f)) })
  }
  Some(fix_stream_ids.val)
}

///|
/// A file of the story's web service (`service`: its `files` by path, what its station's dev server answers through
/// `station.preview`): its status, its type and its body; None where the story has no service.
///   "service": { "files": { "/": "<!doctype html>…", "/app.css": "body { … }" } }
pub fn story_service_file(path : String) -> (Int, String, String)? {
  guard field(fix_story.val, "service") is Some(s) else { return None }
  let path = if path == "/index.html" { "/" } else { path }
  match field(field(Some(s), "files"), path) {
    Some(String(body)) => {
      let kind = if path.has_suffix(".css") {
        "text/css; charset=utf-8"
      } else if path.has_suffix(".js") {
        "text/javascript; charset=utf-8"
      } else {
        "text/html; charset=utf-8"
      }
      Some((200, kind, body))
    }
    _ => Some((404, "text/plain; charset=utf-8", "Not Found"))
  }
}

