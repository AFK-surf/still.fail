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
//     "pictures": {"before.png": "<base64>"} }

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
  let session = "s-c1"
  let claude = by_agent("anthropic", "claude", session)
  let before = items(Some(story), "before")
  let messages = before.mapi(fn(i, b) {
    let kind = text(Some(b), "kind")
    let more : Map[String, Json] = { "attachments": Json::array(story_files(b)) }
    if kind == "person" {
      more["mine"] = Json::boolean(true)
      more["author"] = Json::string("lin@example.com")
    }
    msg(i + 1, kind, if kind == "agent" { claude } else { by_person("林") }, text(Some(b), "text"), text(Some(b), "when"), more)
  })
  {
    "archived": false,
    "me": { "email": "lin@example.com" },
    "thread": { "id": 7, "unread": 0 },
    "title": Json::string(text(Some(story), "title")),
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
  let session = "s-c1"
  for s in steps {
    fix_later(number(Some(s), "at"), fn() {
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
            "ts": Json::string("story\{fix_serial.val}"),
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
          fc.sent.push(msg(seq, "agent", by_agent("anthropic", "claude", session), text(Some(p), "text"), "刚刚", more))
        }
        None => ()
      }
    })
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
