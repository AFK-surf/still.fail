// The cards over the rail's places (the core's `railCard` view, views/rail-cards.ts) as the made-up workspace has them:
// 对话's and 用量's figures as a busy week's, 用量's offering 分享卡片.

///|
pub fn fixture_rail_card(params : Map[String, Json]) -> Json? {
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
        "share": true,
      })
    }
    _ => None
  }
}
