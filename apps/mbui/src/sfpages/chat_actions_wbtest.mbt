// What can be done with a chat, one list (chat_actions.mbt): a row's menu offers what its chat's info does, in the
// same groups, a rule between each two.

///|
fn acts_keys(groups : Array[Array[ChatAction]]) -> Array[Array[String]] {
  groups.map(fn(g) { g.map(fn(x) { x.key }) })
}

///|
test "a row's chat: pinned, renamed, kept; its link and sessions' files; relayed; shared and pictured where the viewer may; archived" {
  let src = @sffixture.fixture("home")
  let row = fn(more : Map[String, Json]) {
    let o : Map[String, Json] = {
      "id": "k1",
      "session": "k1",
      "thread": 7,
      "title": "部署",
      "station": "ws1/st1",
      "stationName": "Studio",
      "pinned": false,
      "agents": [{ "key": "k1" }],
    }
    for k, v in more {
      o[k] = v
    }
    chat_acts_of_row(@sfbase.chat_item(Json::object(o)))
  }
  let none = fn() {  }
  assert_eq(acts_keys(chat_actions(src, row({}), rename=none, archive=none)), [
    ["pin", "rename", "keep"],
    ["link", "transcript"],
    ["relay"],
    ["archive"],
  ])
  // one the viewer may share and make a picture of: as its info offers them
  assert_eq(
    acts_keys(chat_actions(src, row({ "xshareMay": true, "publishMay": true }), rename=none, archive=none))[3],
    ["xshare", "publish"],
  )
  // pinned: kept from the archive already, nothing to keep
  assert_eq(acts_keys(chat_actions(src, row({ "pinned": true }), rename=none, archive=none))[0], ["pin", "rename"])
  // the menu's items: the groups with a rule between each two
  let items = chat_menu_items(chat_actions(src, row({}), rename=none, archive=none))
  assert_eq(items.map(fn(i) { i is None }), [false, false, false, true, false, false, true, false, true, false])
}

///|
test "an open chat's: the same as its row's, with Slack and Feishu where it is there; archived, only what reads it" {
  let src = @sffixture.fixture("home")
  let r : ChatRef = { station: "ws1/st1", session: "k1", title: "部署", station_name: "Studio" }
  let chat = Json::object({
    "thread": { "id": 7 },
    "pinned": false,
    "kept": true,
    "slackUrl": "https://x.slack.com/archives/C1/p1",
    "xshare": { "may": false, "text": "未分享", "session": "k1" },
    "publish": { "may": true, "links": [] },
  })
  let view = fn(archived : Bool) -> ChatView {
    { ..@sfbase.chat_view_made(Json::object({ "title": "部署" })), archived, agents: [@sfbase.agent_of({ "session": { "key": "k1" } })] }
  }
  let none = fn() {  }
  let groups = chat_actions(src, chat_acts_of_chat(r, Some(view(false)), Some(chat)), rename=none, archive=none)
  assert_eq(acts_keys(groups), [
    ["pin", "rename", "keep"],
    ["link", "transcript"],
    ["relay", "slack"],
    ["xshare", "publish"],
    ["archive"],
  ])
  // kept: 取消保留; where it is shared shown to one who may not change it, not to be done
  assert_eq(groups[0][2].label, @sf.t("web-main.chat.unkeep"))
  assert_eq(groups[3][0].end, "未分享")
  assert_true(!groups[3][0].may)
  assert_eq(
    acts_keys(chat_actions(src, chat_acts_of_chat(r, Some(view(true)), Some(chat)), rename=none, archive=none)),
    [["link", "transcript"], ["slack"], ["xshare", "publish"]],
  )
}
