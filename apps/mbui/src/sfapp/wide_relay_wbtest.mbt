// The desktop's relay dialog (sfdesk relay.mbt, Relay.tsx RelayDialog): from a row's menu, the places the station's
// bots are in as the core offers them, one picked with its note, relayed there.

///|
test "wide: 接力到频道… from a row's menu: the dialog lists the bot's places, one picked shows who replies there, 接力 relays it (chat.relay)" {
  reset()
  let calls : Array[Made] = []
  let base = fixture("home")
  let places : Json = {
    "connects": [
      {
        "id": "slack-1",
        "kind": "slack",
        "name": "星火助手",
        "team": "星火",
        "places": [
          { "id": "C1", "name": "dev", "kind": "channel", "used": 20 },
          { "id": "C2", "name": "ops", "kind": "channel", "private": true },
        ],
      },
    ],
  }
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done, heard: None })
      match name {
        "chat.relayPlaces" => done(Ok(places))
        "chat.relay" => done(Ok({ "place": "#dev" }))
        _ => (base.call)(name, params, done)
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=1280.0, h=800.0, platform=0)
  let (x, y) = t.find("整理发布清单").unwrap()
  t.right_click(x, y)
  t.frame()
  t.tap_text("接力到频道…")
  t.frame()
  assert_eq(named(calls, "chat.relayPlaces").length(), 1)
  t.frame()
  assert_true(t.find("接力到频道") is Some(_))
  assert_true(t.find("#dev") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  assert_true(t.find("🔒 #ops") is Some(_))
  // relayed to before: first
  let (_, dev_y) = t.find("#dev").unwrap()
  let (_, ops_y) = t.find("🔒 #ops").unwrap()
  assert_true(dev_y < ops_y)
  t.tap_text("#dev")
  t.frame()
  assert_true(t.find("接力到 #dev") is Some(_))
  assert_true(t.find("开头附一句（可选）") is Some(_))
  // who replies there, in line with the place's name
  let (name_x, _, _, _) = t.rect_of("#dev").unwrap()
  let (via_x, _, _, _) = t.rect_of("那里由").unwrap()
  assert_eq(via_x, name_x)
  t.tap_text("接力到 #dev")
  t.frame()
  let relayed = named(calls, "chat.relay")
  assert_eq(relayed.length(), 1)
  assert_eq(text(Some(relayed[0].params), "connect"), "slack-1")
  assert_eq(text(Some(relayed[0].params), "channel"), "C1")
  // the dialog gone, where it went said
  assert_true(t.find("开头附一句（可选）") is None)
  assert_true(t.find("已接力到 #dev") is Some(_))
}
