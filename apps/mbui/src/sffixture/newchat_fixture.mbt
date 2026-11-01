// A new chat over the made-up workspace (fixture.mbt): the `newChat` topic (its stations, what it runs on, the
// combinations used often) and the model control's (`pick`), in the core's shapes; the picks taken as the core would
// (`newChat.pick`, `pick.set`, `pick.save`), a chat made at once (`newChat.create`). MBUI_FIXTURE=newchat opens it,
// newchat-station with its station's sheet, newchat-model with what it runs on, newchat-reading while its stations
// are read, newchat-profiles while its station's profiles are, newchat-crowded with what it runs on as crowded as a
// person's (newchat-crowded-model its panel open); home-bars opens the bar's panel of
// the other bars, place the 文件 place (drive.mbt's page at the root).

///|
/// What is picked for a new chat in the made-up workspace, and in the model control's panel.
pub(all) struct NewFix {
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
  /// MBUI_FIXTURE=newchat-crowded: the models, runtimes and combinations of fix_crowded
  mut crowded : Bool
  /// MBUI_FIXTURE=newchat-tall-model: as crowded, how hard it thinks and how fast as Codex offers them (2026-10-30: the
  /// column beside the models taller than they are at most)
  mut tall : Bool
  /// The preset a new chat is opened with ("" for none), and the station's presets (fix_presets)
  mut preset : String
  presets : Array[Json]
  /// The first station's presets not said yet (their topic as a station still to answer has it)
  mut presets_late : Bool
}

///|
pub let new_fix : NewFix = {
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
  crowded: false,
  tall: false,
  preset: "",
  presets_late: false,
  presets: [fix_preset_design(), fix_preset("p-tc", "tstst + iroh", ["tstst", "iroh"], "")],
}

///|
/// A preset of the made-up station's: its directories clones in its repository cache (fix_candidates).
pub fn fix_preset(id : String, name : String, dirs : Array[String], instructions : String) -> Json {
  {
    "id": Json::string(id),
    "name": Json::string(name),
    "dirs": Json::array(dirs.map(fn(d) { { "path": Json::string(if d == "still.fail" { "/Users/me/WebstormProjects/still.fail" } else { "/Users/me/code/" + d }), "repo": Json::string(fix_repo(d)) } })),
    "instructions": Json::string(instructions),
    "createdBy": "me@example.com",
    "createdAt": 1793500000000.0,
    "updatedAt": 1793500000000.0,
  }
}

///|
fn fix_repo(name : String) -> String {
  match name {
    "still.fail" => "github.com/AFK-surf/still.fail"
    "mbui" => "github.com/AFK-surf/mbui"
    _ => "github.com/zzj3720/" + name
  }
}

///|
/// still.fail 开发: still.fail on the first station, its design folder on MBA.
fn fix_preset_design() -> Json {
  match fix_preset("p-sf", "still.fail 开发", ["still.fail"], "改界面先发改前改后对比图。") {
    Object(m) => {
      let p = m.copy()
      let dirs = match p.get("dirs") {
        Some(Array(a)) => a.copy()
        _ => []
      }
      dirs.push({ "path": "/Users/me/Design/still.fail 设计稿", "repo": Json::null(), "station": "ws1/st2", "stationName": "MBA" })
      p["dirs"] = Json::array(dirs)
      Json::object(p)
    }
    other => other
  }
}

///|
/// A made-up station's presets and the folders it offers (the `presets` topic): MBA's a design folder and a clone of
/// still.fail of its own (offered once, as the first station's), the first station's the rest.
pub fn fix_presets_of(station : String) -> Json {
  if station.has_suffix("st2") {
    {
      "presets": [],
      "candidates": [
        {
          "path": "/Users/me/Design/still.fail 设计稿",
          "name": "still.fail 设计稿",
          "repo": Json::null(),
          "chats": 0.0,
          "lastAt": 1793500000000.0,
          "where": "~/Design/still.fail 设计稿",
        },
        {
          "path": "/Users/me/code/still.fail",
          "name": "still.fail",
          "repo": "github.com/AFK-surf/still.fail",
          "chats": 2.0,
          "lastAt": 1793500000000.0,
          "where": "~/code/still.fail",
        },
      ],
    }
  } else {
    { "presets": Json::array(new_fix.presets), "candidates": fix_candidates() }
  }
}

///|
/// The directories the made-up station offers for a new preset: its clones, those its chats worked in most first.
pub fn fix_candidates() -> Json {
  Json::array(
    [
      ("still.fail", "~/WebstormProjects/still.fail", "github.com/AFK-surf/still.fail", 41, false),
      ("tstst", "~/code/tstst", "github.com/zzj3720/tstst", 9, false),
      ("iroh", "github.com/zzj3720/iroh", "github.com/zzj3720/iroh", 3, true),
      ("riff", "~/code/riff", "github.com/zzj3720/riff", 0, false),
    ].map(fn(x) {
      let (name, at, repo, chats, cached) = x
      let path = if cached { "/Users/me/.stillfail/repos/" + name } else { "/Users/me" + at.unsafe_substring(start=1, end=at.length()) }
      let o : Map[String, Json] = {
        "path": Json::string(path),
        "name": Json::string(name),
        "repo": if repo == "" { Json::null() } else { Json::string(repo) },
        "chats": Json::number(chats.to_double()),
        "lastAt": 1793500000000.0,
        "where": Json::string(at),
      }
      if cached {
        o["cached"] = Json::boolean(true)
      }
      // (still.fail's own touch icon, as the station finds it in web/public)
      if name == "still.fail" {
        o["icon"] = Json::string(fix_sf_icon)
      }
      Json::object(o)
    }),
  )
}

///|
/// A station a new chat can start on, as the core's `newChat` lists it (StationView): what it is, its agents at work
/// (`overview`) and what is left of its machine (`host`); how this device reaches it is the `stationNet` view's (the
/// made-up stations' `net`: Studio's, none of MBA's).
pub fn fix_station(id : String) -> Json {
  match id {
    "st2" =>
      {
        "station": "ws1/st2",
        "id": "st2",
        "name": "MBA",
        "icon": "glyph:laptop",
        "summary": "空闲 · Apple M4 · 16 GB · macOS 27.0.1",
        "online": true,
        "host": {
          "meters": [
            fix_meter("CPU", 91, "ok", "91", "%"),
            fix_meter("内存", 9, "red", "1.4", "GB"),
            fix_meter("磁盘", 12, "amber", "28", "GB"),
          ],
        },
        "overview": { "counts": { "running": 0 } },
        "models": [],
        "runtimes": [],
      }
    _ =>
      {
        "station": "ws1/st1",
        "id": "st1",
        "name": "Studio",
        "icon": "glyph:desktop",
        "summary": "2 个 agent 正在运行 · Apple M2 Max · 64 GB · macOS 27.0.1",
        "online": true,
        "host": {
          "meters": [
            fix_meter("CPU", 72, "ok", "72", "%"),
            fix_meter("内存", 18, "amber", "11.5", "GB"),
            fix_meter("磁盘", 41, "ok", "380", "GB"),
          ],
        },
        "overview": { "counts": { "running": 2 } },
        "models": [],
        "runtimes": [],
      }
  }
}

///|
/// A meter of a station's machine (Meter), what is left of it `left` percent, `big` its figure in `unit`.
pub fn fix_meter(short : String, left : Int, level : String, big : String, unit : String) -> Json {
  {
    "short": Json::string(short),
    "left": Json::number(left.to_double()),
    "level": Json::string(level),
    "remaining": Json::string(if unit == "%" { "空闲 " + big + "%" } else { "剩 " + big + " G" }),
    "big": Json::string(big),
    "unit": Json::string(unit),
  }
}

///|
/// The models of newchat-crowded, in the core's order: as many series and names as long as a person's phone showed
/// them (2026-10-26), the one it starts on running on three runtimes.
// kept across runs: a table, never written
pub let fix_crowded_models : Array[String] = [
  "claude-opus-5-5", "claude-sonnet-5", "gpt-6-astra", "deepseek-v4-1-flash", "grok-4-7-build-fast", "kimi-for-coding",
  "swe-2",
]

///|
/// The models newchat-tall-model has besides newchat-crowded's: more of them than the models' column shows at most.
// kept across runs: a table, never written
pub let fix_tall_models : Array[String] = ["gpt-6-1-sol", "gpt-6-1-terra"]

///|
/// A model of newchat-crowded's (the ones not the plain fixture's), as the core's `pick` lists it.
pub fn fix_crowded_model(model : String, name : String, family : String, maker : String, runtimes : Array[String]) -> Json {
  {
    "model": Json::string(model),
    "name": Json::string(name),
    "family": Json::string(family),
    "maker": { "id": Json::string(maker), "name": Json::string(maker) },
    "runtimes": Json::array(runtimes.map(Json::string(_))),
    "ids": [Json::string(model)],
    "efforts": {},
    "accounts": {},
    "availability": "here",
  }
}

///|
pub fn fix_model(model : String) -> Json {
  match model {
    "gpt-6-astra" => fix_crowded_model(model, "GPT-6 Astra", "Astra", "openai", ["codex"])
    "deepseek-v4-1-flash" => fix_crowded_model(model, "DeepSeek V4.1 Flash", "DeepSeek", "deepseek", ["claude", "codex", "dsh"])
    "grok-4-7-build-fast" => fix_crowded_model(model, "Grok 4.7 Build Fast", "Grok", "xai", ["grok"])
    "kimi-for-coding" => fix_crowded_model(model, "Kimi For Coding", "Kimi", "kimi", ["claude"])
    "swe-2" => fix_crowded_model(model, "SWE-2", "SWE", "devin", ["devin"])
    "gpt-6-1-sol" => fix_crowded_model(model, "GPT-6.1 Sol", "Sol", "openai", ["codex"])
    "gpt-6-1-terra" => fix_crowded_model(model, "GPT-6.1 Terra", "GPT", "openai", ["codex"])
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
pub fn fix_runtime_of(model : String) -> String {
  match items(Some(fix_model(model)), "runtimes").get(0) {
    Some(String(r)) => r
    _ => "claude"
  }
}

///|
pub fn fix_pick() -> Json {
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
    "options": fix_pick_options(
      if n.tall {
        fix_crowded_models.map(fix_model) + fix_tall_models.map(fix_model)
      } else if n.crowded {
        fix_crowded_models.map(fix_model)
      } else {
        [fix_model("claude-opus-5-5"), fix_model("claude-sonnet-5"), fix_model("gpt-6")]
      },
    ),
    "near": if n.crowded { ["gpt-6-astra", "deepseek-v4-1-flash", "swe-2"] } else { ["claude-opus-5-5", "gpt-6"] },
    "runtimeFixed": false,
    "value": picked(n.model, n.runtime, n.effort, ""),
    "valueOption": fix_model(n.model),
    "draft": picked(n.d_model, n.d_runtime, n.d_effort, n.d_profile),
    "option": Json::string(n.d_model),
    // (all the drafted model runs on, crowded; else the one it runs on)
    "runtimes": if n.crowded {
      Json::array(items(Some(fix_model(n.d_model)), "runtimes"))
    } else {
      [Json::string(n.d_runtime)]
    },
    "efforts": if n.tall {
      ["minimal", "low", "medium", "high", "xhigh", "max", "ultra"]
    } else if n.crowded {
      ["low", "medium", "high", "max"]
    } else {
      ["low", "medium", "high"]
    },
    "fastAvailable": n.tall,
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
    // who runs it as the control says it: the station's pick (no profile kept to)
    "account": { "text": "自动分配", "auto": true, "level": "ok" },
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
/// The models as the model control has them: each as it last ran here (`usual`, `usualText`; the one drafted as it is
/// drafted) and how often new chats started on it (`uses`): the new chat's frequent ones, the rest never used.
fn fix_pick_options(all : Array[Json]) -> Json {
  let n = new_fix
  let effort_word = fn(e : String) {
    match e {
      "low" => "低"
      "medium" => "中"
      "high" => "高"
      "max" => "最高"
      _ => ""
    }
  }
  // (model: runtime, effort, uses)
  let used : Map[String, (String, String, Int)] = if n.crowded {
    { "gpt-6-astra": ("codex", "medium", 6), "deepseek-v4-1-flash": ("dsh", "high", 4), "swe-2": ("devin", "high", 2) }
  } else {
    { "claude-opus-5-5": ("claude", "high", 9), "gpt-6": ("codex", "medium", 5) }
  }
  Json::array(
    all.map(fn(o) {
      match o {
        Object(m) => {
          let m = m.copy()
          let model = text(Some(o), "model")
          let many = items(Some(o), "runtimes").length() > 1
          let ran = if model == n.d_model {
            Some((n.d_runtime, n.d_effort, used.get(model).map(fn(u) { u.2 }).unwrap_or(0)))
          } else {
            used.get(model)
          }
          match ran {
            Some((runtime, effort, uses)) => {
              m["usual"] = {
                "runtime": Json::string(runtime),
                "effort": if effort == "" { Json::null() } else { Json::string(effort) },
                "fast": Json::null(),
              }
              let parts = []
              if many {
                parts.push(@settings.runtime_label(runtime))
              }
              if effort_word(effort) != "" {
                parts.push(effort_word(effort))
              }
              if parts.length() > 0 {
                m["usualText"] = Json::string(parts.join(" · "))
              }
              m["uses"] = Json::number(uses.to_double())
            }
            None => m["uses"] = Json::number(0.0)
          }
          Json::object(m)
        }
        other => other
      }
    }),
  )
}

///|
/// A chat's model control (`pick` of `session:<key>`): the new chat's, with what picks its account again beside 自动.
pub fn fix_session_pick() -> Json {
  match fix_pick() {
    Object(o) => {
      o["repick"] = Json::string("重新分配")
      Json::object(o)
    }
    other => other
  }
}

///|
/// The `newChat` topic (fix_new_chat_of), with the key the next chat made from it is to have (`next`: new:N, as
/// newChat.create makes it).
pub fn fix_new_chat(f : Fixture) -> Json {
  match fix_new_chat_of(f) {
    Object(m) => {
      let o = m.copy()
      o["next"] = Json::string("new:\{new_fix.made + 1}")
      Json::object(o)
    }
    v => v
  }
}

///|
fn fix_new_chat_of(f : Fixture) -> Json {
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
  // its station with no profile open here: what to add first (newchat-noprofile)
  if f.mode == "newchat-noprofile" {
    return {
      "kept": Json::string(n.station),
      "stations": [fix_station("st1"), fix_station("st2")],
      "any": true,
      "station": fix_station(n.station),
      "blocked": "profile",
      "model": Json::null(),
      "runtime": "",
      "effort": "",
      "efforts": [],
      "accounts": [],
      "pickAccount": false,
      "waiting": false,
      "pick": Json::null(),
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
  // (MBUI_FIXTURE=newchat-files: its stations lend their files, its 文件 tab open beside it; newchat-lend: they lend
  // them, the tab not open, 文件 in its bar alone)
  let lend = fn(s : Json) -> Json {
    match s {
      Object(o) if f.mode == "newchat-files" || f.mode == "newchat-lend" => {
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
    "frequent": if n.crowded { fix_crowded_frequent() } else { fix_frequent() },
    "label": Json::string(effort_word),
    "preset": Json::string(n.preset),
    "presets": Json::array(
      n.presets.map(fn(p) {
        {
          "id": field(Some(p), "id").unwrap_or(Json::string("")),
          "name": field(Some(p), "name").unwrap_or(Json::string("")),
          "dirs": Json::number(
            match field(Some(p), "dirs") {
              Some(Array(a)) => a.length().to_double()
              _ => 0.0
            },
          ),
          "station": Json::string(text(Some(fix_station(n.station)), "station")),
          "stationName": Json::string(text(Some(fix_station(n.station)), "name")),
        }
      }),
    ),
    "presetStation": Json::string(if n.preset == "" { "" } else { text(Some(fix_station(n.station)), "station") }),
    "presetName": Json::string(
      match n.presets.iter().find_first(fn(p) { field(Some(p), "id") == Some(Json::string(n.preset)) }) {
        Some(p) => field(Some(p), "name").unwrap_or(Json::string("")).as_string().unwrap_or("")
        None => ""
      },
    ),
  }
}

///|
/// The frequent combinations of newchat-crowded: one naming its runtime, as the core names one of a model that runs on
/// more than one.
pub fn fix_crowded_frequent() -> Json {
  let n = new_fix
  let combo = fn(model : String, runtime : String, effort : String, name : String, runtime_text : String, effort_text : String) {
    let o : Map[String, Json] = {
      "model": Json::string(model),
      "runtime": Json::string(runtime),
      "effort": Json::string(effort),
      "label": Json::string(
        if runtime_text == "" {
          name + " · " + effort_text
        } else {
          name + " · " + runtime_text + " · " + effort_text
        },
      ),
      "name": Json::string(name),
      "effortText": Json::string(effort_text),
      "selected": Json::boolean(n.model == model && n.runtime == runtime && n.effort == effort),
    }
    if runtime_text != "" {
      o["runtimeText"] = Json::string(runtime_text)
    }
    Json::object(o)
  }
  [
    combo("gpt-6-astra", "codex", "medium", "GPT-6 Astra", "", "中"),
    combo("deepseek-v4-1-flash", "dsh", "high", "DeepSeek V4.1 Flash", "DeepSeek Harness", "高"),
    combo("swe-2", "devin", "high", "SWE-2", "", "高"),
  ]
}

///|
/// The frequent combinations of the plain fixture.
pub fn fix_frequent() -> Json {
  let n = new_fix
  [
    {
      "model": "claude-opus-5-5",
      "runtime": "claude",
      "effort": "high",
      "label": "Opus 5.5 · 高",
      "name": "Opus 5.5",
      "effortText": "高",
      "selected": Json::boolean(n.model == "claude-opus-5-5" && n.effort == "high"),
    },
    {
      "model": "gpt-6",
      "runtime": "codex",
      "effort": "medium",
      "label": "GPT-6 · 中",
      "name": "GPT-6",
      "effortText": "中",
      "selected": Json::boolean(n.model == "gpt-6" && n.effort == "medium"),
    },
    {
      "model": "claude-sonnet-5",
      "runtime": "claude",
      "effort": "low",
      "label": "Sonnet 5 · 低",
      "name": "Sonnet 5",
      "effortText": "低",
      "selected": Json::boolean(n.model == "claude-sonnet-5" && n.effort == "low"),
    },
  ]
}

///|
/// How long stations-slow's stations take to be read.
pub let stations_slow_ms : Double = 1200.0

///|
/// The new chat's topics, None for any other.
pub fn fixture_new_topic(f : Fixture, name : String) -> Json? {
  match name {
    "newChat" => Some(fix_new_chat(f))
    "pick" => Some(fix_pick())
    _ => None
  }
}

///|
/// The new chat's calls, None for any other.
pub fn fixture_new_call(f : Fixture, name : String, params : Json) -> Result[Json, Json]? {
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
      take("preset", fn(s) { n.preset = s })
      f.changed()
      Some(Ok(Json::object({})))
    }
    "preset.add" | "preset.put" => {
      let id = match field(p, "id") {
        Some(String(s)) => s
        _ => "p-\{n.presets.length()}"
      }
      let dirs = match field(p, "dirs") {
        Some(Array(a)) => a.map(fn(d) { d.as_string().unwrap_or("") })
        _ => []
      }
      let made = fix_preset(id, field(p, "name").unwrap_or(Json::string("")).as_string().unwrap_or(""), dirs.map(fn(d) {
        match d.rev_find("/") {
          Some(i) => d.unsafe_substring(start=i + 1, end=d.length())
          None => d
        }
      }), "")
      n.presets.retain(fn(x) { field(Some(x), "id") != Some(Json::string(id)) })
      n.presets.push(made)
      f.changed()
      Some(Ok(made))
    }
    "preset.delete" => {
      take("id", fn(s) { n.presets.retain(fn(x) { field(Some(x), "id") != Some(Json::string(s)) }) })
      f.changed()
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
      f.changed()
      Some(Ok(Json::object({})))
    }
    "pick.save" => {
      // (with picks of its own, a model's as it last ran or a change in the panel: those picked first)
      take("model", fn(s) {
        n.d_model = s
        n.d_runtime = fix_runtime_of(s)
      })
      take("runtime", fn(s) { n.d_runtime = s })
      take("effort", fn(s) { n.d_effort = s })
      take("profile", fn(s) { n.d_profile = s })
      n.model = n.d_model
      n.runtime = n.d_runtime
      n.effort = n.d_effort
      f.changed()
      Some(Ok(Json::object({})))
    }
    "newChat.create" => {
      n.made += 1
      // (under the key the page had for it, `next`)
      let key = match params {
        Object(p) =>
          match p.get("key") {
            Some(String(k)) => k
            _ => "new:\{n.made}"
          }
        _ => "new:\{n.made}"
      }
      f.changed()
      Some(Ok({ "key": Json::string(key) }))
    }
    _ => None
  }
}

///|
/// The files' page's tabs of files-split, as the core keeps them: two, the one shown split, 文档 in front and the home
/// beside it; 照片 of MBA the other.
pub fn fix_split_tabs() -> Json {
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

///|
/// still.fail's web/public/apple-touch-icon.png, as a data URL.
let fix_sf_icon : String = "data:image/png;base64,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"
