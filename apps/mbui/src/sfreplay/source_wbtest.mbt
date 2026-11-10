///|
test "a replay's direct accounts subscription survives a source signal leaving" {
  @core.client.reset()
  let src = source()
  @core.subscribe("accounts") |> ignore
  let live = src.topic("accounts", {})
  let stop = @signals.effect(fn() { live.get() |> ignore })
  let r = @core.Replay::parse(
    #|{"out":{"id":7,"subscribe":{"topic":"accounts"},"keyed":true}}
    #|{"in":{"id":7,"value":{"signedIn":true}}}
    #|{"in":{"id":7,"value":{"signedIn":false}}}
  )
  r.attach()
  let accounts = @core.subscribe("accounts")
  assert_eq(r.deliver(at_most=1), 1)
  assert_true(@sfbase.flag(accounts.value, "signedIn"))
  stop()
  (src.leave)("accounts", {}, @sfbase.TopicLeave::Legacy)
  assert_eq(r.deliver(at_most=1), 1)
  assert_false(@sfbase.flag(accounts.value, "signedIn"))
  assert_eq(r.diverged().length(), 0)
  @core.Replay::detach()
  @core.client.reset()
}

///|
test "a new flow does not subscribe the previous flow's held topics" {
  let first = Flow::start(trace("wide-send"), w=1280.0, h=800.0)
  first.see("新建对话")
  let src = source()
  @sfbase.hold(src, "previous-flow", "previous-flow-only", {}).get().snapshot() |> ignore
  assert_true(@core.client.peek_topic("previous-flow-only") is Some(_))
  let second = Flow::start(trace("wide-send"), w=1280.0, h=800.0)
  assert_true(@core.client.peek_topic("previous-flow-only") is None)
  assert_false(second.r.diverged().iter().any(fn(m) { m.contains("previous-flow-only") }))
  @sfbase.reset()
  @core.Replay::detach()
  @core.client.reset()
}

///|
test "a run from before the stations' rows: the app's rows, a station and a part read out of its stations, made once" {
  @core.client.reset()
  let src = source()
  let r = @core.Replay::parse(
    #|{"out":{"id":3,"subscribe":{"topic":"stations","scope":"w","brief":true},"keyed":true}}
    #|{"in":{"id":3,"value":[{"station":"w/a","name":"A"}]}}
    #|{"out":{"id":4,"subscribe":{"topic":"stations","scope":"w"},"keyed":true}}
    #|{"in":{"id":4,"value":[{"station":"w/a","name":"A","models":[1],"host":{"os":"mac","cpu":2},"overview":{"disk":{"free":1},"profiles":[{"id":"p"}]}}]}}
  )
  r.keep_stations()
  r.attach()
  let rows_p : Map[String, Json] = { "scope": "w" }
  let one_p : Map[String, Json] = { "scope": "w", "station": "w/a" }
  let part_p : Map[String, Json] = { "scope": "w", "station": "w/a", "part": "profiles" }
  // (nothing yet: no value, none made)
  assert_true((src.topic_read)("station", one_p).value is None)
  (src.topic_read)("stations", rows_p) |> ignore
  (src.topic_read)("stationPart", part_p) |> ignore
  assert_eq(r.deliver(), 2)
  let rows = (src.topic_read)("stations", rows_p)
  assert_eq(
    rows.value.unwrap().stringify(),
    "[{\"station\":\"w/a\",\"name\":\"A\",\"host\":{\"os\":\"mac\"},\"overview\":{\"disk\":{\"free\":1}}}]",
  )
  let one = (src.topic_read)("station", one_p)
  assert_eq(
    one.value.unwrap().stringify(),
    "{\"station\":\"w/a\",\"name\":\"A\",\"host\":{\"os\":\"mac\",\"cpu\":2},\"overview\":{\"disk\":{\"free\":1},\"profiles\":[{\"id\":\"p\"}]}}",
  )
  assert_eq((src.topic_read)("stationPart", part_p).value.unwrap().stringify(), "[{\"id\":\"p\"}]")
  assert_eq((src.topic_read)("station", { "scope": "w", "station": "w/b" }).value, Some(Json::null()))
  // read again while nothing changed: the same value, the same version
  let again = (src.topic_read)("station", one_p)
  assert_true(physical_equal(again.value.unwrap(), one.value.unwrap()))
  assert_eq(again.version, one.version)
  // one followed `stations` for all of them, let go of once the last leaves
  (src.leave)("station", one_p, @sfbase.TopicLeave::Legacy)
  (src.leave)("station", { "scope": "w", "station": "w/b" }, @sfbase.TopicLeave::Legacy)
  (src.leave)("stationPart", part_p, @sfbase.TopicLeave::Legacy)
  assert_true(@core.client.peek_topic("stations", params=rows_p) is Some(_))
  (src.leave)("stations", rows_p, @sfbase.TopicLeave::Legacy)
  assert_true(@core.client.peek_topic("stations", params=rows_p) is None)
  assert_eq(r.left(), 0)
  assert_eq(r.unmade(), [])
  // (what the shared client held from the tests before, asked again as it is attached, aside)
  assert_false(r.diverged().iter().any(fn(m) { m.contains("station") }))
  @core.Replay::detach()
  @core.client.reset()
}

///|
test "a run from before the connects' rows: one connect and its choice's sessions read out of its connects whole, made once, held with them" {
  @core.client.reset()
  let src = source()
  let r = @core.Replay::parse(
    #|{"out":{"id":5,"subscribe":{"topic":"connects","scope":"w","mine":false},"keyed":true}}
    #|{"in":{"id":5,"value":{"me":{},"items":[{"station":"w/a","stationName":"A","connect":{"id":"c1","name":"One"},"sessions":[{"key":"s1"}],"running":1,"candidates":[{"key":"s1","titleText":"T","description":"D","current":true,"statusText":"x"}]}],"wait":{"reading":false,"failing":[]},"slackApps":[],"noProfile":false}}}
  )
  r.keep_stations()
  r.attach()
  let all_p : Map[String, Json] = { "scope": "w", "mine": false }
  let one_p : Map[String, Json] = { "scope": "w", "station": "w/a", "id": "c1" }
  // (nothing yet: no value, none made)
  assert_true((src.topic_read)("connect", one_p).value is None)
  (src.topic_read)("connectCandidates", one_p) |> ignore
  (src.topic_read)("connects", all_p) |> ignore
  assert_eq(r.deliver(), 1)
  let one = (src.topic_read)("connect", one_p)
  assert_eq(
    one.value.unwrap().stringify(),
    "{\"station\":\"w/a\",\"stationName\":\"A\",\"connect\":{\"id\":\"c1\",\"name\":\"One\"},\"sessions\":[{\"key\":\"s1\"}],\"running\":1}",
  )
  assert_eq(
    (src.topic_read)("connectCandidates", one_p).value.unwrap().stringify(),
    "{\"candidates\":[{\"key\":\"s1\",\"titleText\":\"T\",\"description\":\"D\",\"current\":true}]}",
  )
  // (the list's rows: the run's items as they are, each a row and more)
  assert_eq(@settings.items((src.topic_read)("connects", all_p).value, "items").length(), 1)
  assert_eq((src.topic_read)("connect", { "scope": "w", "station": "w/a", "id": "c9" }).value, Some(Json::null()))
  // read again while nothing changed: the same value, the same version
  let again = (src.topic_read)("connect", one_p)
  assert_true(physical_equal(again.value.unwrap(), one.value.unwrap()))
  assert_eq(again.version, one.version)
  // one followed `connects` for all of them, the list's own too, let go of once the last leaves
  (src.leave)("connect", one_p, @sfbase.TopicLeave::Legacy)
  (src.leave)("connect", { "scope": "w", "station": "w/a", "id": "c9" }, @sfbase.TopicLeave::Legacy)
  (src.leave)("connectCandidates", one_p, @sfbase.TopicLeave::Legacy)
  assert_true(@core.client.peek_topic("connects", params=all_p) is Some(_))
  (src.leave)("connects", all_p, @sfbase.TopicLeave::Legacy)
  assert_true(@core.client.peek_topic("connects", params=all_p) is None)
  assert_eq(r.left(), 0)
  assert_eq(r.unmade(), [])
  assert_false(r.diverged().iter().any(fn(m) { m.contains("connect") }))
  @core.Replay::detach()
  @core.client.reset()
}
