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
  d_profiles : Array[String]
  mut d_none : Bool
  /// The most context it runs with, in tokens ("" its model's whole window)
  mut context : String
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
  /// The first station's repositories being cloned (the `presets` topic's `clones`), and those cloned since, among its
  /// folders (`candidates`)
  clones : Array[Json]
  cloned : Array[Json]
  /// The models starred in the model control (`pick.like`), the first starred first
  liked : Array[String]
  /// MBUI_FIXTURE=newchat-providers…: as crowded, with keys of many providers besides (fix_providers)
  mut providers : Bool
  /// MBUI_FIXTURE=settings-connect-borrow: the model drafted another station's, borrowed first (the pick's `borrow`)
  mut borrow : Bool
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
  d_profiles: [],
  d_none: false,
  context: "",
  made: 0,
  reading: 0,
  crowded: false,
  tall: false,
  preset: "",
  presets_late: false,
  clones: [],
  cloned: [],
  presets: [fix_preset_design(), fix_preset("p-tc", "web-app + backend", ["web-app", "backend"], "")],
  liked: [],
  providers: false,
  borrow: false,
}

///|
/// A preset of the made-up station's: its directories clones in its repository cache (fix_candidates).
pub fn fix_preset(id : String, name : String, dirs : Array[String], instructions : String) -> Json {
  {
    "id": Json::string(id),
    "name": Json::string(name),
    "dirs": Json::array(dirs.map(fn(d) { { "path": Json::string(if d == "still.fail" { "/Users/me/projects/still.fail" } else { "/Users/me/code/" + d }), "repo": Json::string(fix_repo(d)) } })),
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
    _ => "github.com/acme/" + name
  }
}

///|
/// How many times the first station's presets were said late (fix_presets_say): a version of the made-up core's.
// kept across runs: put back by fixture_reset
pub let fix_presets_said : Ref[Int] = Ref(0)

///|
/// The first station's presets said, late (newchat's `presets_late` let go), as a station answers once it can.
pub fn fix_presets_say() -> Unit {
  new_fix.presets_late = false
  fix_presets_said.val += 1
  @settings.fixture_changed()
}

///|
/// The made-up station's clone `id` done (`url`'s repository among its folders) or failed (`error`), as a station tells
/// it on its `presets` topic.
pub fn fix_clone_ends(id : String, error? : String = "") -> Unit {
  guard new_fix.clones.iter().find_first(fn(x) { text(Some(x), "id") == id }) is Some(c) else { return }
  match c {
    Object(m) if error != "" => {
      let failed = m.copy()
      failed["state"] = "failed"
      failed["error"] = Json::string(error)
      new_fix.clones.retain(fn(x) { text(Some(x), "id") != id })
      new_fix.clones.insert(0, Json::object(failed))
    }
    _ => {
      new_fix.clones.retain(fn(x) { text(Some(x), "id") != id })
      let name = text(Some(c), "name")
      new_fix.cloned.push({
        "path": Json::string("/Users/me/.stillfail/repos/" + name),
        "name": Json::string(name),
        "repo": Json::string(text(Some(c), "repo")),
        "chats": 0.0,
        "lastAt": 1793500000000.0,
        "where": Json::string(text(Some(c), "repo")),
        "cached": true,
      })
    }
  }
  fix_presets_said.val += 1
  @settings.fixture_changed()
}

///|
/// still.fail 开发: still.fail on the first station, its design folder on Maple.
fn fix_preset_design() -> Json {
  match fix_preset("p-sf", "still.fail 开发", ["still.fail"], "先检查页面布局。") {
    Object(m) => {
      let p = m.copy()
      let dirs = match p.get("dirs") {
        Some(Array(a)) => a.copy()
        _ => []
      }
      dirs.push({ "path": "/Users/me/Design/still.fail 设计稿", "repo": Json::null(), "station": "ws1/st2", "stationName": "Maple" })
      p["dirs"] = Json::array(dirs)
      Json::object(p)
    }
    other => other
  }
}

///|
/// A made-up station's presets and the folders it offers (the `presets` topic): Maple's a design folder and a clone of
/// still.fail of its own (offered under Maple too), the first station's the rest.
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
    {
      "presets": Json::array(new_fix.presets),
      "candidates": match fix_candidates() {
        Array(a) => Json::array(a + new_fix.cloned)
        other => other
      },
      "clones": Json::array(new_fix.clones),
    }
  }
}

///|
/// The directories the made-up station offers for a new preset: its clones, those its chats worked in most first.
pub fn fix_candidates() -> Json {
  Json::array(
    [
      ("still.fail", "~/projects/still.fail", "github.com/AFK-surf/still.fail", 12, false),
      ("web-app", "~/code/web-app", "github.com/acme/web-app", 9, false),
      ("backend", "github.com/acme/backend", "github.com/acme/backend", 3, true),
      ("notes", "~/code/notes", "github.com/acme/notes", 0, false),
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
/// A station a new chat can start on, as the core's `newChat` lists it (NewChatStation): what it is, its agents at work
/// (`overview`) and what is left of its machine (`host`); how this device reaches it is the `stationNet` view's (the
/// made-up stations' `net`: Willow's, none of Maple's).
pub fn fix_station(id : String) -> Json {
  match id {
    "st2" =>
      {
        "station": "ws1/st2",
        "id": "st2",
        "name": "Maple",
        "icon": "glyph:laptop",
        "summary": "空闲 · Apple M4 · 16 GB · macOS 26",
        "online": true,
        "host": {
          "meters": [
            fix_meter("CPU", 91, "ok", "91", "%"),
            fix_meter("内存", 9, "red", "1.4", "GB"),
            fix_meter("磁盘", 12, "amber", "28", "GB"),
          ],
        },
        "overview": { "counts": { "running": 0 } },
      }
    _ =>
      {
        "station": "ws1/st1",
        "id": "st1",
        "name": "Willow",
        "icon": "glyph:desktop",
        "summary": "2 个 agent 正在运行 · Apple M1 Pro · 32 GB · macOS 26",
        "online": true,
        "host": {
          "meters": [
            fix_meter("CPU", 72, "ok", "72", "%"),
            fix_meter("内存", 18, "amber", "5.8", "GB"),
            fix_meter("磁盘", 41, "ok", "380", "GB"),
          ],
        },
        "overview": { "counts": { "running": 2 } },
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
    "maker": { "id": Json::string(maker) },
    "runtimes": Json::array(runtimes.map(x => Json::string(x))),
    "ids": [Json::string(model)],
    "availability": "here",
  }
}

///|
/// The models of newchat-providers besides newchat-crowded's (2026-11-02 用户「我 20 个 provider 你怎么排」, 「分组应该是
/// 模型厂商」): each its id, name, and maker (its id, as format.ts names it, and its name), many makers among them.
// kept across runs: a table, never written
pub let fix_providers : Array[(String, String, String, String)] = [
  ("gemini-3-pro", "Gemini 3 Pro", "gemini", "Google"),
  ("devstral-3", "Devstral 3", "mistral", "Mistral"),
  ("qwen3-8-coder", "Qwen3.8 Coder", "qwen", "Qwen"),
  ("glm-5-3", "GLM-5.3", "zhipu", "Z.ai"),
  ("minimax-m3", "MiniMax M3", "minimax", "MiniMax"),
  ("mimo-3", "MiMo 3", "xiaomi", "Xiaomi"),
  ("nemotron-4", "Nemotron 4", "nvidia", "NVIDIA"),
  ("gpt-oss-2", "gpt-oss 2", "openai", "OpenAI"),
]

///|
/// The makers' names, by id.
fn fix_maker_name(id : String) -> String {
  match id {
    "anthropic" => "Anthropic"
    "openai" => "OpenAI"
    "deepseek" => "DeepSeek"
    "xai" => "xAI"
    "kimi" => "Moonshot AI"
    "devin" => "Cognition"
    other =>
      match fix_providers.iter().find_first(fn(p) { p.2 == other }) {
        Some(p) => p.3
        None => other
      }
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
    m if fix_providers.iter().any(fn(p) { p.0 == m }) => {
      let p = fix_providers.iter().find_first(fn(p) { p.0 == m }).unwrap()
      fix_crowded_model(m, p.1, p.1, p.2, ["claude"])
    }
    "claude-sonnet-5" =>
      {
        "model": "claude-sonnet-5",
        "name": "Sonnet 5",
        "family": "Sonnet",
        "maker": { "id": "anthropic" },
        "runtimes": ["claude"],
        "ids": ["claude-sonnet-5"],
        "availability": "here",
      }
    "gpt-6" =>
      {
        "model": "gpt-6",
        "name": "GPT-6",
        "family": "GPT",
        "maker": { "id": "openai" },
        "runtimes": ["codex"],
        "ids": ["gpt-6"],
        "availability": "here",
      }
    _ =>
      {
        "model": "claude-opus-5-5",
        "name": "Opus 5.5",
        "family": "Opus",
        "maker": { "id": "anthropic" },
        "runtimes": ["claude"],
        "ids": ["claude-opus-5-5"],
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
/// The models the model control offers, in the core's order.
fn fix_shown_models() -> Array[Json] {
  let n = new_fix
  if n.tall {
    fix_crowded_models.map(fix_model) + fix_tall_models.map(fix_model)
  } else if n.providers {
    fix_crowded_models.map(fix_model) + fix_providers.map(fn(p) { fix_model(p.0) })
  } else if n.crowded {
    fix_crowded_models.map(fix_model)
  } else {
    [fix_model("claude-opus-5-5"), fix_model("claude-sonnet-5"), fix_model("gpt-6")]
  }
}

///|
/// A runtime by its short name, as the core says it after a model's name in a model control's panel (format.ts
/// runtimeShort): CC, DSH.
fn fix_runtime_short(runtime : String) -> String {
  match runtime {
    "claude" => "CC"
    "codex" => "Codex"
    "dsh" => "DSH"
    "grok" => "GROK"
    "cursor" => "Cursor"
    "devin" => "Devin"
    "hermes" => "Hermes"
    "agy" => "AGY"
    _ => "CC"
  }
}

///|
/// The configurations taken out of those used most (`pick.forget`), each by fix_combo_key.
let fix_forgotten : Array[String] = []

///|
/// A configuration by what it is: its model, runtime, effort and context (its tokens in digits, "" its whole window).
fn fix_combo_key(model : String, runtime : String, effort : String, context : String) -> String {
  model + "\u{1}" + runtime + "\u{1}" + effort + "\u{1}" + context
}

///|
/// The configurations new chats here started on most, most first, as the core's `combos` has them: one model run two
/// ways (Opus 5.5 at its whole window and kept to 300K; GPT-6 Astra 中 and 高), and one of a model the `-liked` modes
/// and the tests star (Sonnet 5, Kimi For Coding), whichever is starred; those taken out (`pick.forget`:
/// fix_forgotten) left out. Each `selected` while it is exactly what is drafted.
fn fix_combos() -> Json {
  let n = new_fix
  let effort_word = fn(e : String) {
    match e {
      "low" => "低"
      "medium" => "中"
      "high" => "高"
      _ => "默认深度"
    }
  }
  // (model, runtime, effort, context in thousands of tokens: 0 its whole window)
  let all : Array[(String, String, String, Int)] = if n.crowded {
    [
      ("gpt-6-astra", "codex", "medium", 0),
      ("deepseek-v4-1-flash", "dsh", "high", 0),
      ("gpt-6-astra", "codex", "high", 0),
      ("kimi-for-coding", "claude", "high", 0),
    ]
  } else {
    [
      ("claude-opus-5-5", "claude", "high", 0),
      ("gpt-6", "codex", "medium", 0),
      ("claude-opus-5-5", "claude", "high", 300),
      ("claude-sonnet-5", "claude", "low", 0),
    ]
  }
  Json::array(
    all
    .filter(fn(c) { !fix_forgotten.contains(fix_combo_key(c.0, c.1, c.2, if c.3 > 0 { "\{c.3 * 1000}" } else { "" })) })
    .map(fn(c) {
      let (model, runtime, effort, context) = c
      let o = Some(fix_model(model))
      let parts = []
      if items(o, "runtimes").length() > 1 {
        parts.push(fix_runtime_short(runtime))
      }
      parts.push(effort_word(effort))
      if context > 0 {
        parts.push("\{context}K")
      }
      let tokens = if context > 0 { "\{context * 1000}" } else { "" }
      {
        "model": Json::string(model),
        "runtime": Json::string(runtime),
        "effort": Json::string(effort),
        "fast": Json::null(),
        "context": if context > 0 { Json::number((context * 1000).to_double()) } else { Json::null() },
        "name": Json::string(text(o, "name")),
        "text": Json::string(parts.join(" · ")),
        "selected": Json::boolean(n.d_model == model && n.d_runtime == runtime && n.d_effort == effort && n.context == tokens),
      }
    }),
  )
}

///|
pub fn fix_pick() -> Json {
  let n = new_fix
  let changed = !n.d_none &&
    (n.d_model != n.model || n.d_effort != n.effort || n.d_runtime != n.runtime || n.d_profile != "" || !n.d_profiles.is_empty())
  let picked = fn(
    model : String,
    runtime : String,
    effort : String,
    profile : String,
    profiles : Array[String],
    none : Bool,
  ) -> Json {
    let o : Map[String, Json] = {
      "model": Json::string(model),
      "runtime": Json::string(runtime),
    }
    if effort != "" {
      o["effort"] = Json::string(effort)
    }
    if none {
      o["profiles"] = Json::array([])
    } else if profiles.length() >= 2 {
      o["profiles"] = Json::array(profiles.map(fn(s) { Json::string(s) }))
    } else if profiles.length() == 1 {
      o["profile"] = Json::string(profiles[0])
    } else if profile != "" {
      o["profile"] = Json::string(profile)
    }
    Json::object(o)
  }
  {
    "options": fix_pick_options(fix_shown_models()),
    // (the configurations used most, starred or not)
    "combos": fix_combos(),
    // (every model starred, one of the configurations used most or not)
    "liked": Json::array(n.liked.map(x => Json::string(x))),
    // (the makers of its models, in their order, as the core says them)
    "makers": {
      let makers : Array[(String, String, Int)] = []
      for o in fix_shown_models() {
        let id = text(field(Some(o), "maker"), "id")
        match makers.search_by(fn(m) { m.0 == id }) {
          Some(i) => makers[i] = (id, makers[i].1, makers[i].2 + 1)
          None => makers.push((id, fix_maker_name(id), 1))
        }
      }
      Json::array(makers.map(fn(m) { { "id": Json::string(m.0), "title": Json::string(m.1), "count": Json::number(m.2.to_double()) } }))
    },
    "runtimeFixed": false,
    // (the model drafted another station's: borrowed first, asked, from the panel's foot)
    "borrow": if n.borrow {
      {
        "title": "借用 Maple 的 Fable 5.1？",
        "lines": ["Fable 5.1 由 Maple 上的 Claude 订阅运行。", "借用后，这个连接的会话也用它的额度。"],
        "action": "借用",
        "allowed": true,
        "note": "Fable 5.1 在 Maple 上，借用后这里也能用。",
      }
    } else {
      Json::null()
    },
    "value": picked(n.model, n.runtime, n.effort, "", [], false),
    "valueOption": fix_model(n.model),
    "draft": picked(n.d_model, n.d_runtime, n.d_effort, n.d_profile, n.d_profiles, n.d_none),
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
    // (how much context Claude Code can be kept to under the model's 1M)
    "contexts": if n.d_runtime == "claude" {
      [("", "完整 · 1M"), ("500000", "500K"), ("300000", "300K"), ("200000", "200K")].map(fn(c) {
        Json::object({ "id": Json::string(c.0), "text": Json::string(c.1) })
      })
      |> Json::array
    } else {
      []
    },
    "contextNow": Json::string(n.context),
    "accounts": [
      {
        "id": "p1",
        "name": "Claude 订阅",
        "runtime": "claude",
        "quotaLine": { "text": "5 小时窗口已用 32%" },
      },
      { "id": "p2", "name": "团队 API key", "runtime": "claude" },
    ],
    "who": if n.d_none {
      Json::string("未选择")
    } else if n.d_profiles.length() >= 2 {
      Json::string("\{n.d_profiles.length()} 个账号")
    } else {
      let one = if n.d_profiles.length() == 1 { n.d_profiles[0] } else { n.d_profile }
      Json::string(
        match one {
          "p1" => "Claude 订阅"
          "p2" => "团队 API key"
          "p3" => "Claude 备用订阅"
          "" => "全选"
          s => s
        },
      )
    },
    "whoLevel": if n.d_none { Json::string("amber") } else { Json::null() },
    // who runs it as the control says it: the station's pick (no profile kept to), the subset count, or the account pinned
    "account": {
      "text": if n.d_profiles.length() >= 2 {
        Json::string("\{n.d_profiles.length()} 个账号")
      } else {
        let one = if n.d_profiles.length() == 1 { n.d_profiles[0] } else { n.d_profile }
        Json::string(
          match one {
            "p1" => "Claude 订阅"
            "p2" => "团队 API key"
            "p3" => "Claude 备用订阅"
            "" => "自动分配"
            s => s
          },
        )
      },
      "level": "ok",
    },
    "autoNote": if n.d_none {
      "请选择至少一个账号"
    } else if n.d_profiles.length() >= 2 {
      "在已选账号间自动切换"
    } else {
      "由 station 选择：现在是 Claude 订阅"
    },
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
/// drafted): those new chats here started on, the rest never used.
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
  // (model: runtime, effort)
  let used : Map[String, (String, String)] = if n.crowded {
    { "gpt-6-astra": ("codex", "medium"), "deepseek-v4-1-flash": ("dsh", "high"), "swe-2": ("devin", "high") }
  } else {
    { "claude-opus-5-5": ("claude", "high"), "gpt-6": ("codex", "medium") }
  }
  Json::array(
    all.map(fn(o) {
      match o {
        Object(m) => {
          let m = m.copy()
          let model = text(Some(o), "model")
          m["liked"] = Json::boolean(n.liked.contains(model))
          let many = items(Some(o), "runtimes").length() > 1
          let ran = if model == n.d_model { Some((n.d_runtime, n.d_effort)) } else { used.get(model) }
          match ran {
            Some((runtime, effort)) => {
              m["usual"] = {
                "runtime": Json::string(runtime),
                "effort": if effort == "" { Json::null() } else { Json::string(effort) },
                "fast": Json::null(),
              }
              let parts = []
              if many {
                parts.push(fix_runtime_short(runtime))
              }
              if effort_word(effort) != "" {
                parts.push(effort_word(effort))
              }
              if parts.length() > 0 {
                m["usualText"] = Json::string(parts.join(" · "))
              }
            }
            None => ()
          }
          Json::object(m)
        }
        other => other
      }
    }),
  )
}

///|
/// A chat's model control (`pick` of `session:<key>`): the new chat's, with what picks its account again beside 全选,
/// which account runs it now (`current`), and three accounts so multi-account subset selection can be exercised.
pub fn fix_session_pick() -> Json {
  match fix_pick() {
    Object(o) => {
      o["repick"] = if new_fix.d_none || new_fix.d_profile != "" {
        Json::null()
      } else {
        Json::string("重新分配")
      }
      o["accounts"] = [
        {
          "id": "p1",
          "name": "Claude 订阅",
          "runtime": "claude",
          "current": true,
          "quotaLine": { "text": "5 小时窗口已用 32%" },
        },
        {
          "id": "p3",
          "name": "Claude 备用订阅",
          "runtime": "claude",
          "quotaLine": { "text": "5 小时 100% · 每周 84% · 每周 · Fable 100%", "level": "amber" },
        },
        { "id": "p2", "name": "团队 API key", "runtime": "claude" },
      ]
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
      "waiting": false,
    }
  }
  // Its station has no profile, or its only available profiles are disabled.
  if f.mode == "newchat-noprofile" || f.mode == "newchat-disabled" {
    return {
      "kept": Json::string(n.station),
      "stations": [fix_station("st1"), fix_station("st2")],
      "any": true,
      "station": fix_station(n.station),
      "blocked": Json::string(if f.mode == "newchat-disabled" { "disabled" } else { "profile" }),
      "problem": Json::string(if f.mode == "newchat-disabled" { "Willow 的可用 Profile 均已停用，请在 Profile 页面重新启用。" } else { "" }),
      "model": Json::null(),
      "runtime": "",
      "waiting": false,
      "pick": Json::null(),
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
      "waiting": true,
      "problem": "正在读取 Willow 的 Profile",
      "pick": Json::null(),
    }
  }
  // (MBUI_FIXTURE=newchat-files: its stations lend their files, its 文件 tab open beside it; newchat-lend: they lend
  // them, the tab not open, 文件 in its bar alone: what the folders are is the files' own)
  let lend = fn(s : Json) -> Json {
    match s {
      Object(o) if f.mode == "newchat-files" || f.mode == "newchat-lend" => {
        let m = o.copy()
        m["overview"] = { "drive": { "anywhere": true } }
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
    "waiting": false,
    "pick": fix_pick_face(),
    "preset": Json::string(n.preset),
    "presets": Json::array(
      n.presets.map(fn(p) {
        {
          "id": field(Some(p), "id").unwrap_or(Json::string("")),
          "name": field(Some(p), "name").unwrap_or(Json::string("")),
          "station": Json::string(text(Some(fix_station(n.station)), "station")),
          "stationName": Json::string(text(Some(fix_station(n.station)), "name")),
        }
      }),
    ),
    "presetMarks": if n.preset == "" {
      Json::array([])
    } else {
      [{ "name": "still.fail", "repo": "github.com/AFK-surf/still.fail", "icon": Json::string(fix_sf_icon) }, { "name": "still.fail 设计稿", "repo": "" }]
    },
    "presetStation": Json::string(if n.preset == "" { "" } else { text(Some(fix_station(n.station)), "station") }),
    "presetName": Json::string(
      match n.presets.iter().find_first(fn(p) { field(Some(p), "id") == Some(Json::string(n.preset)) }) {
        Some(p) => (if field(Some(p), "name").unwrap_or(Json::string("")) is String(s) { Some(s) } else { None }).unwrap_or("")
        None => ""
      },
    ),
  }
}

///|
/// The new chat's model control as its page draws it closed (the core's NewChatPick, choose.ts `#face`): of the pick, what
/// it runs on, its model's name, maker and runtimes, how hard it can think, Fast, the account it names.
fn fix_pick_face() -> Json {
  let p = Some(fix_pick())
  let o : Map[String, Json] = Map([])
  for k in ["value", "efforts", "fastText"] {
    match field(p, k) {
      Some(v) => o[k] = v
      None => ()
    }
  }
  let vo = field(p, "valueOption")
  if vo is Some(Object(_)) {
    let m : Map[String, Json] = Map([])
    for k in ["name", "maker", "runtimes"] {
      match field(vo, k) {
        Some(v) => m[k] = v
        None => ()
      }
    }
    o["valueOption"] = Json::object(m)
  }
  let account = field(p, "account")
  if account is Some(Object(_)) {
    let m : Map[String, Json] = Map([])
    for k in ["text", "level"] {
      match field(account, k) {
        Some(v) => m[k] = v
        None => ()
      }
    }
    o["account"] = Json::object(m)
  }
  Json::object(o)
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
        Some(Array(a)) => a.map(fn(d) { (if d is String(s) { Some(s) } else { None }).unwrap_or("") })
        _ => []
      }
      let made = fix_preset(id, (if field(p, "name").unwrap_or(Json::string("")) is String(s) { Some(s) } else { None }).unwrap_or(""), dirs.map(fn(d) {
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
    // (one cloned: `acme/notes` it has already; `bad` refused; any other under way, told in its `clones`)
    "preset.clone" => {
      let url = text(p, "url")
      if url == "bad" {
        return Some(Err({ "code": "invalid", "message": "无法克隆这个地址" }))
      }
      let name = match url.rev_find("/") {
        Some(i) => url.unsafe_substring(start=i + 1, end=url.length())
        None => url
      }
      let repo = if url.has_prefix("https://") { url.unsafe_substring(start=8, end=url.length()) } else { "github.com/" + url }
      if url == "acme/notes" {
        return Some(Ok({ "state": "there", "path": "/Users/me/code/notes", "repo": "github.com/acme/notes", "name": "notes" }))
      }
      let id = "c-\{n.clones.length() + n.cloned.length() + 1}"
      let one : Json = {
        "id": Json::string(id),
        "url": Json::string(url),
        "repo": Json::string(repo),
        "name": Json::string(name),
        "state": "cloning",
        "error": "",
        "by": "me@example.com",
        "startedAt": 1793500000000.0,
      }
      n.clones.insert(0, one)
      f.changed()
      Some(Ok(one))
    }
    "preset.cloneDrop" => {
      take("id", fn(s) { n.clones.retain(fn(x) { text(Some(x), "id") != s }) })
      f.changed()
      Some(Ok(Json::object({})))
    }
    "preset.delete" => {
      take("id", fn(s) { n.presets.retain(fn(x) { field(Some(x), "id") != Some(Json::string(s)) }) })
      f.changed()
      Some(Ok(Json::object({})))
    }
    "pick.set" => {
      match field(p, "open") {
        Some(True) => {
          n.d_model = n.model
          n.d_runtime = n.runtime
          n.d_effort = n.effort
          n.d_profile = ""
          n.d_profiles.clear()
          n.d_none = false
        }
        Some(False) =>
          if n.d_none {
            n.d_none = false
          }
        _ => ()
      }
      take("model", fn(s) {
        n.d_model = s
        n.d_runtime = fix_runtime_of(s)
        if n.d_none && field(p, "profiles") is None && field(p, "profile") is None {
          n.d_none = false
        }
      })
      take("runtime", fn(s) { n.d_runtime = s })
      take("effort", fn(s) { n.d_effort = s })
      match field(p, "profiles") {
        Some(Null) => {
          n.d_none = false
          n.d_profile = ""
          n.d_profiles.clear()
        }
        Some(Array(xs)) => {
          n.d_profiles.clear()
          for x in xs {
            if x is String(s) && s != "" && !n.d_profiles.contains(s) {
              n.d_profiles.push(s)
            }
          }
          if n.d_profiles.is_empty() {
            n.d_none = true
            n.d_profile = ""
          } else if n.d_profiles.length() == 1 {
            n.d_none = false
            n.d_profile = n.d_profiles[0]
            n.d_profiles.clear()
          } else {
            n.d_none = false
            n.d_profile = ""
          }
        }
        _ =>
          match field(p, "profile") {
            Some(Null) => {
              n.d_none = false
              n.d_profile = ""
              n.d_profiles.clear()
            }
            Some(String(s)) => {
              n.d_none = false
              n.d_profile = s
              n.d_profiles.clear()
            }
            _ => ()
          }
      }
      f.changed()
      Some(Ok(Json::object({})))
    }
    "pick.like" => {
      take("model", fn(s) {
        n.liked.retain(fn(m) { m != s })
        if flag(p, "liked") {
          n.liked.push(s)
        }
      })
      f.changed()
      Some(Ok(Json::object({})))
    }
    "pick.forget" => {
      let s = fn(k : String) {
        match field(p, k) {
          Some(String(v)) => v
          Some(Number(n, ..)) => n.to_int64().to_string()
          _ => ""
        }
      }
      fix_forgotten.push(fix_combo_key(s("model"), s("runtime"), s("effort"), s("context")))
      f.changed()
      Some(Ok(Json::object({})))
    }
    "pick.save" => {
      // (with picks of its own, a model's as it last ran or a change in the panel: those picked first)
      take("model", fn(s) {
        n.d_model = s
        n.d_runtime = fix_runtime_of(s)
        n.d_none = false
      })
      take("runtime", fn(s) {
        n.d_runtime = s
        n.d_none = false
      })
      take("effort", fn(s) {
        n.d_effort = s
        n.d_none = false
      })
      match field(p, "profiles") {
        Some(Null) => {
          n.d_none = false
          n.d_profile = ""
          n.d_profiles.clear()
        }
        Some(Array(xs)) => {
          n.d_profiles.clear()
          for x in xs {
            if x is String(s) && s != "" && !n.d_profiles.contains(s) {
              n.d_profiles.push(s)
            }
          }
          if n.d_profiles.is_empty() {
            n.d_none = true
            n.d_profile = ""
          } else if n.d_profiles.length() == 1 {
            n.d_none = false
            n.d_profile = n.d_profiles[0]
            n.d_profiles.clear()
          } else {
            n.d_none = false
            n.d_profile = ""
          }
        }
        _ =>
          match field(p, "profile") {
            Some(Null) => {
              n.d_none = false
              n.d_profile = ""
              n.d_profiles.clear()
            }
            Some(String(s)) => {
              n.d_none = false
              n.d_profile = s
              n.d_profiles.clear()
            }
            _ => ()
          }
      }
      // (in tokens, as a configuration used most has it, or its digits, as the panel's context says it)
      match field(p, "context") {
        Some(Number(k, ..)) => {
          n.context = k.to_int64().to_string()
          n.d_none = false
        }
        _ =>
          take("context", fn(s) {
            n.context = s
            n.d_none = false
          })
      }
      if n.d_none {
        f.changed()
        return Some(Ok({ "saved": false }))
      }
      n.model = n.d_model
      n.runtime = n.d_runtime
      n.effort = n.d_effort
      f.changed()
      Some(Ok(Json::object({})))
    }
    "pick.repick" => {
      f.changed()
      Some(Ok({ "said": "已切到 Claude 备用订阅" }))
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
/// beside it; 照片 of Maple the other.
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
