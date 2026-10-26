// The search over the made-up chats (search.mbt; the core's `search` topic, its SearchView): what a few words find.
// Every word here is made up. "签名" finds a chat by its title, one by a line of it, two messages (more of them with
// 查看更多), a file and a service; "虚拟列表" a message of the first chat; "没有" finds nothing; "等等" is still being looked for on a station and
// could not be on the other; "登录" is what the Android app's SearchResultsTest finds (its screenshots' twin: the modes
// search-results, search-jobs); anything else finds nothing.

///|
pub fn found_mark(from : Int, to : Int) -> Json {
  { "from": Json::number(from.to_double()), "to": Json::number(to.to_double()) }
}

///|
/// Where `word` is in `text` (UTF-16), each time.
pub fn found_marks(text : String, word : String) -> Json {
  let out : Array[Json] = []
  let mut at = 0
  while at + word.length() <= text.length() {
    if text.view(start_offset=at, end_offset=at + word.length()).to_string() == word {
      out.push(found_mark(at, at + word.length()))
      at = at + word.length()
    } else {
      at = at + 1
    }
  }
  Json::array(out)
}

///|
pub fn found_time(ago : String) -> Json {
  { "createdAt": { "at": 0, "ago": Json::string(ago), "full": "", "until": "", "past": true } }
}

///|
pub fn found_message(seq : Int, by : String, text : String, word : String, ago : String) -> Json {
  {
    "station": "ws1/st1",
    "thread": 2,
    "seq": Json::number(seq.to_double()),
    "chat": row("c1", "整理发布清单", "ws1/st1", "2 分钟前", {}),
    "by": Json::string(by),
    "text": Json::string(text),
    "marks": found_marks(text, word),
    "createdAt": 0,
    "time": found_time(ago),
  }
}

///|
pub fn found_item(kind : String, key : String, title : String, text : String, word : String, more : Map[String, Json]) -> Json {
  let o : Map[String, Json] = {
    "kind": Json::string(kind),
    "key": Json::string(key),
    "station": "ws1/st1",
    "stationName": "Studio",
    "title": Json::string(title),
    "text": Json::string(text),
    "marks": found_marks(text, word),
  }
  for k, v in more {
    o[k] = v
  }
  Json::object(o)
}

///|
pub fn fixture_search(f : Fixture, params : Map[String, Json]) -> Json? {
  let query = match params.get("query") {
    Some(String(q)) => q
    _ => ""
  }
  let kind = match params.get("kind") {
    Some(String(k)) => k
    _ => ""
  }
  let none : Json = { "reading": false, "failing": [], "empty": true }
  if query == "签名" {
    let line = "正在核对第三项：安装包的签名，再看一遍签名用的证书"
    let chats : Array[Json] = [
      row("c9", "签名证书续期", "ws1/st2", "3 天前", {}),
      row("c1", "整理发布清单", "ws1/st1", "2 分钟前", {
        "foundText": Json::string(line),
        "foundMarks": found_marks(line, "签名"),
      }),
    ]
    let messages : Array[Json] = [
      found_message(5, "Claude", "安装包的签名对上了，下一步核对版本号", "签名", "5 分钟前"),
      found_message(3, "林", "…先别发，签名的证书下个月就到期了", "签名", "1 小时前"),
    ]
    if kind == "message" {
      messages.push(found_message(2, "Ana", "签名的步骤写在发布说明的第二节", "签名", "昨天"))
      messages.push(found_message(1, "Claude", "我先把签名脚本跑一遍看看", "签名", "昨天"))
    }
    let groups : Array[Json] = if kind == "" {
      [
        {
          "kind": "file",
          "title": "文件",
          "more": false,
          "items": [
            found_item("file", "f1", "签名说明.md", "发布前先检查签名和证书", "签名", {
              "path": "/Users/lin/docs/签名说明.md",
              "fileKind": "markdown",
              "time": found_time("3 天前"),
              "open": { "to": "files", "station": "ws1/st1", "root": "/Users/lin/docs", "path": "签名说明.md", "how": "read" },
            }),
          ],
        },
        {
          "kind": "job",
          "title": "服务和任务",
          "more": false,
          "items": [
            found_item("job", "j1", "签名检查页", "", "签名", {
              "chat": "s-c1",
              "chatTitle": "整理发布清单",
              "job": "job-1",
              "port": 5173,
              "open": { "to": "service", "station": "ws1/st1", "chat": "s-c1", "job": "job-1" },
            }),
          ],
        },
      ]
    } else {
      []
    }
    Some({
      "items": Json::array(if kind == "" || kind == "chat" { chats } else { [] }),
      "chatsMore": false,
      "words": ["签名"],
      "messages": Json::array(if kind == "" || kind == "message" { messages } else { [] }),
      "messagesMore": Json::boolean(kind == ""),
      "groups": Json::array(groups),
      "wait": none,
    })
  } else if query == "登录" {
    Some(login_search(kind))
  } else if query == "虚拟列表" {
    // the first chat's own message (chat_fixture.mbt), opened at it
    Some({
      "items": [],
      "words": ["虚拟列表"],
      "messages": [found_message(2, "林", "帮我把聊天页的列表做成虚拟列表，几千条消息也要滚得顺。", "虚拟列表", "3 小时前")],
      "groups": [],
      "wait": none,
    })
  } else if query == "等等" {
    Some({
      "items": [],
      "words": ["等等"],
      "messages": [],
      "groups": [],
      "wait": {
        "reading": true,
        "text": "正在搜索 Studio",
        "failing": [{ "station": "ws1/st2", "text": "MBA 无法搜索：它的版本太旧" }],
        "empty": false,
      },
      "note": "还有 1 台 station 离线，没有搜它上面的内容",
    })
  } else {
    // the device's chats whose titles have the words (with none, the latest), as the core's search lists them
    let words = query.trim(chars=" ").to_string().to_lower()
    let chats : Array[Json] = []
    for d in fixture_days(f) {
      for c in items(Some(d), "items") {
        if words == "" || text(Some(c), "title").to_lower().contains(words) {
          chats.push(c)
        }
      }
    }
    Some({
      "items": Json::array(chats),
      "words": Json::array(if words == "" { [] } else { [Json::string(words)] }),
      "messages": [],
      "groups": [],
      "wait": none,
    })
  }
}

///|
/// A chat of SearchResultsTest's: on studio or on mac, active `minutes` ago.
pub fn login_chat(id : String, title : String, minutes : Int, station? : String = "ws1/st1", name? : String = "studio") -> Json {
  row(id, title, station, "\{minutes} 分钟前", {
    "session": Json::string("ember:" + id),
    "stationName": Json::string(name),
    "stationIcon": "",
    "agents": [agent("anthropic", "claude")],
  })
}

///|
pub fn login_message(chat : Json, seq : Int, by : String, text : String, minutes : Int) -> Json {
  {
    "station": Json::string(text_of(chat, "station")),
    "thread": 1,
    "seq": Json::number(seq.to_double()),
    "chat": chat,
    "by": Json::string(by),
    "text": Json::string(text),
    "marks": found_marks(text, "登录"),
    "createdAt": 0,
    "time": found_time("\{minutes} 分钟前"),
  }
}

///|
pub fn text_of(v : Json, key : String) -> String {
  text(Some(v), key)
}

///|
pub fn login_job(chat : Json, id : String, title : String, line : String, port : Int?, minutes : Int) -> Json {
  let more : Map[String, Json] = {
    "stationName": Json::string(text_of(chat, "stationName")),
    "station": Json::string(text_of(chat, "station")),
    "chat": Json::string(text_of(chat, "session")),
    "job": Json::string(id),
    "time": found_time("\{minutes} 分钟前"),
  }
  match port {
    Some(p) => more["port"] = Json::number(p.to_double())
    None => ()
  }
  more["open"] = {
    "to": if port is Some(_) { "service" } else { "task" },
    "station": Json::string(text_of(chat, "station")),
    "chat": Json::string(text_of(chat, "session")),
    "job": Json::string(id),
  }
  found_item("job", text_of(chat, "station") + "\u{1}j:" + id, title, line, "登录", more)
}

///|
/// What "登录" finds (SearchResultsTest's `all`, and `onlyJobs` for the services and tasks alone).
pub fn login_search(kind : String) -> Json {
  let safari = login_chat("c-2", "登录页在 Safari 上没反应", 12)
  let sso = login_chat("c-5", "SSO 登录接入", 95, station="ws1/mac", name="mac")
  let jobs = [
    login_job(safari, "j-1", "登录页预览", "vite dev · 登录页 :5173", Some(5173), 10),
    login_job(sso, "j-2", "登录回归测试", "pnpm test e2e/登录.spec.ts", None, 80),
    login_job(safari, "j-3", "登录接口 mock", "node mock/登录.js :4000", Some(4000), 30),
  ]
  if kind == "job" {
    return {
      "items": [],
      "words": ["登录"],
      "messages": [],
      "groups": [{ "kind": "job", "title": "服务和任务", "items": Json::array(jobs), "more": false }],
      "wait": { "reading": false, "failing": [], "empty": false },
    }
  }
  {
    "items": [safari, sso],
    "chatsMore": false,
    "words": ["登录"],
    "messages": [
      login_message(safari, 41, "Alice", "Safari 17 上点了登录没有任何反应", 12),
      login_message(sso, 7, "Opus 5.5", "…登录成功后回到原来的页面", 95),
    ],
    "messagesMore": false,
    "groups": [
      { "kind": "job", "title": "服务和任务", "items": Json::array(jobs[0:2].to_array()), "more": true },
      {
        "kind": "member",
        "title": "成员",
        "more": false,
        "items": [
          {
            "kind": "member",
            "key": "member\u{1}denglu@example.com",
            "station": "",
            "stationName": "",
            "title": "登录组 · 王五",
            "text": "denglu@example.com",
            "marks": [],
            "email": "denglu@example.com",
          },
        ],
      },
    ],
    "wait": { "reading": true, "text": "正在等待 mini", "failing": [], "empty": false },
    "note": "mini 离线，其上的内容未搜索",
  }
}
