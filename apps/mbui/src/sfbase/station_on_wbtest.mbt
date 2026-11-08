///|
test "the list's rows take their station's state from the station, said once" {
  let row = fn(station : String, id : String, lead : String) -> Json {
    {
      "id": Json::string(id),
      "session": Json::string(id),
      "station": Json::string(station),
      "title": "t",
      "swipeArchive": true,
      "swipeAsk": "ask",
      "stateText": "要你帮忙：看一下",
      "stateLead": Json::string(lead),
      "stateRest": "看一下",
    }
  }
  let v : Json = {
    "stations": [
      { "station": "w/a", "offline": "a 正在更新", "updating": true },
      { "station": "w/b", "reconnecting": "正在重新连接 b" },
      { "station": "w/c" },
    ],
    "days": [{ "label": "今天", "items": [row("w/a", "1", "done"), row("w/a", "2", "need"), row("w/b", "3", "done"), row("w/c", "4", "done")] }],
  }
  let items = chats_view_made(v).days[0].items
  // gone for its update: its line says so, not swiped away
  assert_eq(items[0].offline, Some("a 正在更新"))
  assert_eq(items[0].updating, true)
  assert_eq(items[0].swipe_archive, false)
  assert_eq(items[0].swipe_ask, None)
  assert_eq(items[0].state_text, Some("a 正在更新"))
  assert_eq(items[0].state_lead, "")
  // what needs the viewer still says so
  assert_eq(items[1].state_text, Some("要你帮忙：看一下"))
  assert_eq(items[1].state_lead, "need")
  // its link coming back: marked, still swiped away
  assert_eq(items[2].reconnecting, Some("正在重新连接 b"))
  assert_eq(items[2].offline, None)
  assert_eq(items[2].swipe_archive, true)
  // linked: as the row says
  assert_eq(items[3].reconnecting, None)
  assert_eq(items[3].swipe_archive, true)
}
