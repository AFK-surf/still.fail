// A new chat over the made-up workspace (fixture.mbt): the `newChat` topic (its stations, what it runs on, the
// combinations used often) and the model control's (`pick`), in the core's shapes; the picks taken as the core would
// (`newChat.pick`, `pick.set`, `pick.save`), a chat made at once (`newChat.create`). MBUI_FIXTURE=newchat opens it,
// newchat-station with its station's sheet, newchat-model with what it runs on, newchat-reading while its stations
// are read, newchat-profiles while its station's profiles are; home-bars opens the bar's panel of
// the other bars, place the 文件 place (drive.mbt's page at the root).

///|
/// What is picked for a new chat in the made-up workspace, and in the model control's panel.
priv struct NewFix {
  mut station : String
  mut model : String
  mut runtime : String
  mut effort : String
  mut d_model : String
  mut d_runtime : String
  mut d_effort : String
  mut d_profile : String
  mut made : Int
  /// MBUI_FIXTURE=stations-slow: its stations not asked for yet (0), being read (1), read (2)
  mut reading : Int
}

///|
let new_fix : NewFix = {
  station: "st1",
  model: "claude-opus-5-5",
  runtime: "claude",
  effort: "high",
  d_model: "claude-opus-5-5",
  d_runtime: "claude",
  d_effort: "high",
  d_profile: "",
  made: 0,
  reading: 0,
}

///|
fn fix_station(id : String) -> Json {
  match id {
    "st2" =>
      {
        "station": "ws1/st2",
        "id": "st2",
        "name": "MBA",
        "icon": "glyph:laptop",
        "summary": "在线 · 空闲",
        "online": true,
        "models": [],
        "runtimes": [],
      }
    _ =>
      {
        "station": "ws1/st1",
        "id": "st1",
        "name": "Studio",
        "icon": "glyph:desktop",
        "summary": "在线 · 2 个 agent 在工作",
        "online": true,
        "models": [],
        "runtimes": [],
      }
  }
}

///|
fn fix_model(model : String) -> Json {
  match model {
    "claude-sonnet-5" =>
      {
        "model": "claude-sonnet-5",
        "name": "Sonnet 5",
        "family": "Sonnet",
        "maker": { "id": "anthropic", "name": "anthropic" },
        "runtimes": ["claude"],
        "ids": ["claude-sonnet-5"],
        "efforts": {},
        "accounts": {},
        "availability": "here",
      }
    "gpt-6" =>
      {
        "model": "gpt-6",
        "name": "GPT-6",
        "family": "GPT",
        "maker": { "id": "openai", "name": "openai" },
        "runtimes": ["codex"],
        "ids": ["gpt-6"],
        "efforts": {},
        "accounts": {},
        "availability": "here",
      }
    _ =>
      {
        "model": "claude-opus-5-5",
        "name": "Opus 5.5",
        "family": "Opus",
        "maker": { "id": "anthropic", "name": "anthropic" },
        "runtimes": ["claude"],
        "ids": ["claude-opus-5-5"],
        "efforts": {},
        "accounts": {},
        "availability": "here",
      }
  }
}

///|
fn fix_runtime_of(model : String) -> String {
  if model == "gpt-6" {
    "codex"
  } else {
    "claude"
  }
}

///|
fn fix_pick() -> Json {
  let n = new_fix
  let changed = n.d_model != n.model || n.d_effort != n.effort || n.d_runtime != n.runtime || n.d_profile != ""
  let picked = fn(model : String, runtime : String, effort : String, profile : String) -> Json {
    let o : Map[String, Json] = {
      "model": Json::string(model),
      "runtime": Json::string(runtime),
    }
    if effort != "" {
      o["effort"] = Json::string(effort)
    }
    if profile != "" {
      o["profile"] = Json::string(profile)
    }
    Json::object(o)
  }
  {
    "options": [fix_model("claude-opus-5-5"), fix_model("claude-sonnet-5"), fix_model("gpt-6")],
    "runtimeFixed": false,
    "value": picked(n.model, n.runtime, n.effort, ""),
    "valueOption": fix_model(n.model),
    "draft": picked(n.d_model, n.d_runtime, n.d_effort, n.d_profile),
    "option": Json::string(n.d_model),
    "runtimes": [Json::string(n.d_runtime)],
    "efforts": ["low", "medium", "high"],
    "accounts": [
      {
        "id": "p1",
        "name": "Claude 订阅",
        "runtime": "claude",
        "quotaLine": { "text": "5 小时窗口已用 32%" },
      },
      { "id": "p2", "name": "团队 API key", "runtime": "claude" },
    ],
    "who": if n.d_profile == "p1" {
      "Claude 订阅"
    } else if n.d_profile == "p2" {
      "团队 API key"
    } else {
      "自动"
    },
    "autoNote": "由 station 选择：现在是 Claude 订阅",
    "changed": Json::boolean(changed),
    "was": [],
    "becomes": [],
    "modelText": "",
    "accountText": "",
    "accountNote": "",
    "accountWarn": false,
    "saveText": "",
  }
}

///|
fn fix_new_chat(f : Fixture) -> Json {
  let n = new_fix
  // its stations read stations_slow_ms after the page first asks (MBUI_FIXTURE=stations-slow: Home, for the films of
  // what shows meanwhile)
  let slow = f.mode == "stations-slow" && n.reading < 2
  if slow && n.reading == 0 {
    n.reading = 1
    fix_later(stations_slow_ms, fn() { n.reading = 2 })
  }
  // its stations not read yet: only the one it last started on (MBUI_FIXTURE=newchat-reading)
  if f.mode == "newchat-reading" || slow {
    return {
      "kept": Json::string(n.station),
      "any": false,
      "efforts": [],
      "accounts": [],
      "pickAccount": false,
      "waiting": false,
      "frequent": [],
    }
  }
  // its station's profiles not read yet (newchat-profiles)
  if f.mode == "newchat-profiles" {
    return {
      "kept": Json::string(n.station),
      "stations": [fix_station("st1"), fix_station("st2")],
      "any": true,
      "station": fix_station(n.station),
      "model": Json::null(),
      "runtime": "",
      "effort": "",
      "efforts": [],
      "accounts": [],
      "pickAccount": false,
      "waiting": true,
      "problem": "正在读取 Studio 的 Profile",
      "pick": Json::null(),
      "frequent": [],
    }
  }
  let effort_word = match n.effort {
    "low" => "低"
    "medium" => "中"
    _ => "高"
  }
  // (MBUI_FIXTURE=newchat-files: its stations lend their files, its 文件 tab open beside it)
  let lend = fn(s : Json) -> Json {
    match s {
      Object(o) if f.mode == "newchat-files" => {
        let m = o.copy()
        m["overview"] = { "drive": field(Some(fixture_station_drive(true)), "drive").unwrap_or(Json::null()) }
        Json::object(m)
      }
      _ => s
    }
  }
  {
    "kept": Json::string(n.station),
    "stations": [lend(fix_station("st1")), lend(fix_station("st2"))],
    "any": true,
    "station": lend(fix_station(n.station)),
    "model": fix_model(n.model),
    "runtime": Json::string(n.runtime),
    "effort": Json::string(n.effort),
    "efforts": ["low", "medium", "high"],
    "accounts": [],
    "pickAccount": false,
    "waiting": false,
    "pick": fix_pick(),
    "frequent": [
      {
        "model": "claude-opus-5-5",
        "runtime": "claude",
        "effort": "high",
        "label": "Opus 5.5 · 高",
        "selected": Json::boolean(n.model == "claude-opus-5-5" && n.effort == "high"),
      },
      {
        "model": "gpt-6",
        "runtime": "codex",
        "effort": "medium",
        "label": "GPT-6 · 中",
        "selected": Json::boolean(n.model == "gpt-6" && n.effort == "medium"),
      },
      {
        "model": "claude-sonnet-5",
        "runtime": "claude",
        "effort": "low",
        "label": "Sonnet 5 · 低",
        "selected": Json::boolean(n.model == "claude-sonnet-5" && n.effort == "low"),
      },
    ],
    "label": Json::string(effort_word),
  }
}

///|
/// How long stations-slow's stations take to be read.
let stations_slow_ms : Double = 1200.0

///|
/// The new chat's topics, None for any other.
fn fixture_new_topic(f : Fixture, name : String) -> Json? {
  match name {
    "newChat" => Some(fix_new_chat(f))
    "pick" => Some(fix_pick())
    _ => None
  }
}

///|
/// The new chat's calls, None for any other.
fn fixture_new_call(f : Fixture, name : String, params : Json) -> Result[Json, Json]? {
  let p = Some(params)
  let n = new_fix
  let take = fn(key : String, set : (String) -> Unit) {
    match field(p, key) {
      Some(String(s)) => set(s)
      Some(Null) => set("")
      _ => ()
    }
  }
  match name {
    "newChat.pick" => {
      take("station", fn(s) { n.station = s })
      take("model", fn(s) {
        n.model = s
        n.d_model = s
      })
      take("runtime", fn(s) {
        n.runtime = s
        n.d_runtime = s
      })
      take("effort", fn(s) {
        n.effort = s
        n.d_effort = s
      })
      f.version += 1
      Some(Ok(Json::object({})))
    }
    "pick.set" => {
      if flag(p, "open") {
        n.d_model = n.model
        n.d_runtime = n.runtime
        n.d_effort = n.effort
        n.d_profile = ""
      }
      take("model", fn(s) {
        n.d_model = s
        n.d_runtime = fix_runtime_of(s)
      })
      take("runtime", fn(s) { n.d_runtime = s })
      take("effort", fn(s) { n.d_effort = s })
      take("profile", fn(s) { n.d_profile = s })
      f.version += 1
      Some(Ok(Json::object({})))
    }
    "pick.save" => {
      n.model = n.d_model
      n.runtime = n.d_runtime
      n.effort = n.d_effort
      f.version += 1
      Some(Ok(Json::object({})))
    }
    "newChat.create" => {
      n.made += 1
      Some(Ok({ "key": Json::string("new:\{n.made}") }))
    }
    _ => None
  }
}

///|
/// What a fixture mode opens over Home at the start (src/sffix): a new chat, with one of its sheets; the bar's panel;
/// a place.
pub fn open_mode(mode : String) -> Unit {
  if mode.has_prefix("newchat") {
    app.nav.rise(NewChat)
    match mode {
      "newchat-station" => @sfpages.new_chat_ask("station")
      "newchat-model" => @sfpages.new_chat_ask("model")
      _ => ()
    }
  } else if mode == "home-bars" {
    bar.open_panel(true)
  } else if mode == "place" {
    app.nav.replace(Files)
  } else if mode.has_prefix("place-") {
    // a place of the rail's in the wide frame (wide_places.mbt): place-stations, place-profiles, place-connects,
    // place-usage
    app.nav.replace(Place(mode.view(start_offset=6).to_string()))
  } else if mode.has_prefix("files-") {
    // the files' page in the wide frame (wide_files.mbt) at Studio's 文档: files-columns (设计稿 open beside it, chosen),
    // files-tree (设计稿 opened in place), files-list, files-preview (发布清单.md previewed beside it), files-split (two
    // tabs, the one shown split)
    let docs : DriveAt = { station: "ws1/st1", root: Some(fix_docs), path: "" }
    app.nav.push(Files)
    // (in columns, 设计稿 open beside 文档: the page at it, chosen in the column before as coming to it chooses)
    app.nav.push(Drive(if mode == "files-columns" { { ..docs, path: "设计稿" } } else { docs }))
    // what the made-up core is told before the first frame: the way shown, a tree's folder open, what is chosen
    let browse = fn(params : Map[String, Json]) {
      let o : Map[String, Json] = {
        "owner": "page",
        "station": "ws1/st1",
        "root": Json::string(fix_docs),
        "path": "",
        "place": Json::string(@sfdesk.place_name("page/0")),
      }
      for k, v in params {
        o[k] = v
      }
      fix_browse_do(None, mode, "drive.browse", Json::object(o)) |> ignore
    }
    match mode {
      "files-tree" => {
        fix_browse_prefs_set({ "driveViews": { "page": "tree" } }) |> ignore
        browse({ "act": "tree", "folder": "设计稿", "view": "tree" })
        @sfdesk.nav_open("ws1/st1")
      }
      "files-list" => fix_browse_prefs_set({ "driveViews": { "page": "list" } }) |> ignore
      // a copy asked about a name there (wide_files_drag.mbt): 说明.txt into 会议记录, which has one
      "files-clash" =>
        @sfdesk.drag_ask({
          into: { station: "ws1/st1", root: Some(fix_docs), path: "会议记录" },
          into_name: "会议记录",
          total: 1,
          clashes: [
            {
              name: "说明.txt",
              dir: false,
              size: 2048.0,
              station: "MBA",
              there: dv_entry(fix_entry("说明.txt", false, 320, "10/01")),
            },
          ],
          answers: {},
          all: false,
          done: fn(_) {  },
        })
      // the bar's 传输 open: a copy to MBA going (as the core says it)
      "files-transfers" => {
        fix_transfer({
          "from": { "station": "ws1/st1", "root": Json::string(fix_docs), "path": "", "names": ["演示录屏.mp4"] },
          "to": { "station": "ws1/st2", "root": "/Users/lin/照片", "path": "" },
          "move": false,
        })
        @sfdesk.transfers_open()
      }
      // the preview beside the list (wide_files_pane.mbt), 发布清单.md chosen
      "files-preview" => {
        fix_browse_prefs_set({ "driveViews": { "preview": "shown" } }) |> ignore
        browse({ "act": "choose", "view": "columns", "folder": "", "name": "发布清单.md" })
      }
      // two tabs, the one shown split: 文档 in front, the home beside it
      "files-split" =>
        fix_browse_prefs_set({ "filesTabs": { "ws1": Json::string(fix_split_tabs().stringify()) } }) |> ignore
      _ => ()
    }
  } else if mode == "switcher" || mode == "switcher-found" {
    // ⌘K in the wide frame (sfdesk/switcher.mbt): with nothing typed, and with 签名 typed (what the search finds)
    @sfdesk.switcher_open_with(if mode == "switcher-found" { "签名" } else { "" })
  } else if mode == "home-sheet" || mode == "home-accounts" {
    // (home-accounts: two accounts signed in, what a new workspace asks which of)
    home_sheet_at_start.val = true
  }
}

///|
/// The files' page's tabs of files-split, as the core keeps them: two, the one shown split, 文档 in front and the home
/// beside it; 照片 of MBA the other.
fn fix_split_tabs() -> Json {
  {
    "tabs": [
      {
        "id": "t0",
        "panes": [
          { "station": "ws1/st1", "root": Json::string(fix_docs), "path": "" },
          { "station": "ws1/st1", "root": Json::string(fix_home), "path": "" },
        ],
        "front": 0,
      },
      { "id": "t1", "panes": [{ "station": "ws1/st2", "root": "/Users/lin/照片", "path": "" }], "front": 0 },
    ],
    "current": "t0",
  }
}
