// What another app shares in, over the fixture (APP=sffix MBUI_FIXTURE=share-in | share-in-stations | share-in-files;
// scripts/shots.sh share, web-share): a link with the app's subject, the sheet over Home (the `shareIn` view: two chats,
// the one a thing from the same site went to last first; two stations up), its stations' choice opened; two pictures
// and a document shared instead. Every word in it is made up.

///|
pub let fix_shared : (String, String?) = (
  "列表滑动的十个细节 https://www.youtube.com/watch?v=e2e-list&si=abc",
  Some("列表滑动的十个细节"),
)

///|
/// The `shareIn` view as the core has it for the made-up workspace.
pub fn fixture_share_topic(params : Map[String, Json]) -> Json? {
  let query = match params.get("query") {
    Some(String(q)) => q
    _ => ""
  }
  let chat = fn(id : String, title : String, preview : String, maker : String, runtime : String) -> Json {
    {
      "id": Json::string(id),
      "station": "ws1/st1",
      "session": Json::string(id),
      "title": Json::string(title),
      "stationName": "Studio",
      "last": { "preview": Json::string(preview) },
      "agents": [{ "maker": { "id": Json::string(maker), "name": Json::string(maker) }, "runtime": Json::string(runtime) }],
    }
  }
  // the one a thing from the same site went to last first, as the core lists them
  let all = [
    chat("s-c4", "收集视频", "下好了，放在 ~/视频 里", "openai", "codex"),
    chat("s-c1", "整理发布清单", "清单里还差签名那一项", "anthropic", "claude"),
  ]
  let items = all.filter(fn(c) { query == "" || text(Some(c), "title").contains(query) })
  Some({
    "site": "youtube.com",
    "items": Json::array(items),
    "kept": { "station": "ws1/st1", "id": "s-c4", "text": "youtube.com 的链接上次发到这里" },
    "stations": [{ "station": "ws1/st1", "name": "Studio" }, { "station": "ws1/st2", "name": "MBA" }],
    "newOn": "ws1/st1",
    "loading": false,
  })
}

///|
/// `shareIn.open` as the core answers it: a chat's key and session, or the workspace's new chat's key.
pub fn fixture_share_call(name : String, params : Json) -> Result[Json, Json]? {
  if name != "shareIn.open" {
    return None
  }
  let p = Some(params)
  let station = text(p, "station")
  match text(p, "id") {
    "" => Some(Ok({ "station": Json::string(station), "key": Json::string("new:" + workspace_of(station)) }))
    id =>
      Some(
        Ok({
          "station": Json::string(station),
          "key": Json::string(station + ":" + id),
          "session": Json::string(id),
          "title": "收集视频",
        }),
      )
  }
}
