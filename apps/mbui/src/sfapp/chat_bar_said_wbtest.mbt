///|
/// The ids of the chat's actions the bars hold now, in their order.
fn chat_acts_said(t : @ui.Tester) -> Array[String] {
  let said : Array[String] = []
  fn walk(j : Json) {
    match j {
      Object(o) => {
        match o.get("id") {
          Some(String(id)) if id.has_prefix("page/chat/") && !said.contains(id) => said.push(id)
          _ => ()
        }
        for _, v in o {
          walk(v)
        }
      }
      Array(a) => for v in a { walk(v) }
      _ => ()
    }
  }
  walk(@json.parse(t.nav_said()) catch { _ => Json::null() })
  said
}

///|
test "the top page switched to another chat and back again: the chat's actions its node handed at their cause are in the bars from the frame of the switch" {
  let t = native_chat(951.0, 669.0, true, side=84.0)
  let first = chat_acts_said(t)
  assert_true(first.contains("page/chat/info"), msg=first.to_string())
  open_chat({ station: "ws1/st1", session: "s-c2", title: "首页", station_name: "Willow" })
  t.frame()
  let other = chat_acts_said(t)
  assert_true(other.contains("page/chat/info"), msg="the switch's frame: \{other}")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  t.frame()
  assert_eq(chat_acts_said(t), first)
}
