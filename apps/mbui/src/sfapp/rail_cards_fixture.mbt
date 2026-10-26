// The cards over the rail's places (the core's `railCard` view, views/rail-cards.ts) as the made-up workspace has them:
// Station's from its stations as the chats view has them (each with a machine of its own), the others' figures as a
// busy week's.

///|
fn fixture_rail_card(f : Fixture, params : Map[String, Json]) -> Json? {
  let place = match params.get("place") {
    Some(String(p)) => p
    _ => ""
  }
  let stat = fn(value : String, label : String, tone : String) -> Json {
    if tone == "" {
      { "value": Json::string(value), "label": Json::string(label) }
    } else {
      { "value": Json::string(value), "label": Json::string(label), "tone": Json::string(tone) }
    }
  }
  match place {
    "chats" =>
      Some({
        "head": "3 个对话正在运行",
        "stats": [stat("2", "等你处理", "amber"), stat("1", "出错", "red"), stat("4", "未读", ""), stat("8", "今天归档", "")],
        "rows": [],
      })
    "stations" => {
      let chats = fixture_chats(f, { "scope": Json::string("ws1") })
      let stations = items(chats, "stations")
      let glyph = field(chats, "glyph")
      // each machine as its host says it: its chip, how full its CPU and memory are
      let machine = fn(name : String) -> (String, String) {
        match name {
          "Studio" => ("Apple M2 Max · CPU 62% · 内存 54%", "")
          "ccvm" => ("Apple M1 · CPU 81% · 内存 72%", "amber")
          "Mini1" => ("Apple M4 · CPU 12% · 内存 38%", "")
          _ => ("", "")
        }
      }
      let up = stations.filter(fn(s) { text(Some(s), "state") == "online" }).length()
      let rows = stations.map(fn(s) {
        let s = Some(s)
        let row : Map[String, Json] = { "name": Json::string(text(s, "name")), "value": Json::string(text(s, "doing")) }
        if text(s, "state") == "error" {
          row["tone"] = Json::string("red")
        }
        if text(s, "state") == "online" {
          let (sub, tone) = machine(text(s, "name"))
          row["sub"] = Json::string(sub)
          if tone != "" {
            row["subTone"] = Json::string(tone)
          }
        }
        Json::object(row)
      })
      Some({
        "head": Json::string(text(glyph, "now")),
        "stats": [stat("\{up}/\{stations.length()}", "在线设备", if up < stations.length() { "amber" } else { "" }), stat("4", "后台任务", "")],
        "rows": Json::array(rows),
        "share": Json::boolean(count(glyph, "running") > 0),
      })
    }
    "profiles" =>
      Some({
        "head": "1 个账号额度用完了",
        "stats": [stat("5", "额度充足", ""), stat("2", "快用完", "amber"), stat("1", "已用完", "red")],
        "rows": [
          { "name": "用 6 个 Claude 订阅账号消耗了 489% 的周额度", "value": "" },
          { "name": "用 2 个 ChatGPT 订阅账号消耗了 17% 的周额度", "value": "" },
        ],
        "note": "claude-3 的额度 2 小时后刷新",
      })
    "usage" => {
      let costs = [210.0, 180.0, 95.0, 330.0, 260.0, 474.0, 362.0]
      let labels = ["10/20", "10/21", "10/22", "10/23", "10/24", "10/25", "10/26"]
      Some({
        "head": "近 7 天折合 $1,911",
        "stats": [stat("$362", "今天", ""), stat("3.1 亿", "输入 token", "")],
        "rows": [
          { "name": "Opus 5.5", "value": "$1,207 · 63%" },
          { "name": "GPT-6", "value": "$412 · 22%" },
          { "name": "Sonnet 5", "value": "$188 · 10%" },
        ],
        "days": Json::array(
          costs.mapi(fn(i, x) {
            Json::object({ "label": Json::string(labels[i]), "share": Json::number(x / 474.0), "today": Json::boolean(i == 6) })
          }),
        ),
      })
    }
    _ => None
  }
}
