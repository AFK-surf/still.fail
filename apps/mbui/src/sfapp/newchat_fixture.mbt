// A new chat over the made-up workspace (fixture.mbt): the `newChat` topic (its stations, what it runs on, the
// combinations used often) and the model control's (`pick`), in the core's shapes; the picks taken as the core would
// (`newChat.pick`, `pick.set`, `pick.save`), a chat made at once (`newChat.create`). MBUI_FIXTURE=newchat opens it,
// newchat-station with its station's sheet, newchat-model with what it runs on; home-bars opens the bar's panel of
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
  ignore(f)
  let n = new_fix
  let effort_word = match n.effort {
    "low" => "低"
    "medium" => "中"
    _ => "高"
  }
  {
    "kept": Json::string(n.station),
    "stations": [fix_station("st1"), fix_station("st2")],
    "any": true,
    "station": fix_station(n.station),
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
      "newchat-station" => raise_sheet(PickStation("ws1"))
      "newchat-model" => raise_sheet(RunPicker("ws1/st1"))
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
    // files-tree (设计稿 opened in place), files-list, files-split (two tabs, the one shown split)
    let docs : DriveAt = { station: "ws1/st1", root: Some(fix_docs), path: "" }
    app.nav.push(Files)
    app.nav.push(Drive(docs))
    match mode {
      "files-columns" => {
        wide.files_cols["ws1/st1\u{1}" + fix_docs + "\u{1}"] = "设计稿"
        wide.files_chosen = "ws1/st1\u{1}" + fix_docs + "\u{1}设计稿"
      }
      "files-tree" => {
        wide.files_view = Some("tree")
        wide.files_open["tree/ws1/st1/" + fix_docs + "/设计稿"] = true
        wide.files_open["station/ws1/st1"] = true
      }
      "files-list" => wide.files_view = Some("list")
      // two tabs, the one shown split: 文档 in front, the home beside it
      "files-split" =>
        wide.tabs_set["ws1"] = (
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
          } : Json).stringify()
      _ => ()
    }
  } else if mode == "switcher" || mode == "switcher-found" {
    // ⌘K in the wide frame (wide_switcher.mbt): with nothing typed, and with 签名 typed (what the search finds)
    wide.switcher = true
    if mode == "switcher-found" {
      switcher_query.val = "签名"
      switcher_field.set("签名")
    }
  } else if mode == "home-sheet" {
    raise_sheet(Workspaces)
  }
}
