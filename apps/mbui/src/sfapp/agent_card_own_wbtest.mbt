// An agent's card where its model has a week of its own (Fable's) under its account's windows: the three chips beside
// the account's name, each whole.

///|
/// The agent's card of fixture `chat-agent-card`, opened over its latest message's name, its account named `name` and
/// its allowance as a chat on Fable has it (views/models.ts quotaFor: the account's windows, then its model's own).
fn own_agent_card(name : String) -> @ui.Tester {
  new_run()
  let base = fixture("chat-agent-card")
  let src : Source = {
    ..base,
    topic_read: fn(topic, params) {
      let got = base.topic(topic, params).get().snapshot()
      match (topic, got.value) {
        ("chat", Some(Object(m))) => {
          let o = m.copy()
          o["agents"] = Json::array(
            items(got.value, "agents").map(fn(a) {
              guard a is Object(am) && am.get("account") is Some(Object(acc)) && acc.get("quota") is Some(Object(q)) else {
                return a
              }
              let quota = q.copy()
              quota["windows"] = Json::array(
                items(Some(Json::object(q)), "windows") +
                [{ "label": "每周 · Fable", "mark": "Fable", "scope": "Fable", "left": 46, "level": "ok", "refills": "2 天 4 小时后刷新" }],
              )
              let account = acc.copy()
              account["name"] = Json::string(name)
              account["quota"] = Json::object(quota)
              let agent = am.copy()
              agent["account"] = Json::object(account)
              Json::object(agent)
            }),
          )
          { ..got, value: Some(Json::object(o)) }
        }
        _ => got
      }
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  let last = t
    .words()
    .filter(fn(w) { w.0 == "Claude" && w.5 > 0.5 })
    .iter()
    .fold(init=None, fn(acc : (String, Double, Double, Double, Double, Double)?, w) {
      match acc {
        Some(a) if a.2 >= w.2 => acc
        _ => Some(w)
      }
    })
  guard last is Some(at) else { @halt.saying("no agent's message") }
  t.move_to(at.1 - 20.0, at.2 + at.4 / 2.0)
  t.run_for(@sfpages.hover_open_ms * 2.0)
  t
}

///|
test "wide: an agent's card with its model's own week: three chips whole, beside its account's name or under it where the line has not the room for both" {
  let lines = []
  for name in ["林的 Max", "claude-team-account-5@example.com"] {
    let t = own_agent_card(name)
    let shown = t.words().filter(fn(w) { w.5 > 0.5 })
    let one = fn(words : String) {
      match shown.filter(fn(w) { w.0 == words }) {
        [w] => w
        found => @halt.saying("\{name}: \{words}: \{Repr(found)} in \{Repr(shown.map(fn(w) { w.0 }))}")
      }
    }
    // each chip its mark and its figure on one line, the model's own after the account's
    let chips = [("5H", "62%"), ("W", "18%"), ("Fable", "46%")].map(fn(c) { (one(c.0), one(c.1)) })
    assert_true(chips.iter().all(fn(c) { c.0.2 == chips[0].0.2 && c.1.1 > c.0.1 }), msg="\{name}: \{Repr(chips)}")
    assert_true(chips[1].0.1 > chips[0].1.1 && chips[2].0.1 > chips[1].1.1, msg="\{name}: \{Repr(chips)}")
    // its account's name whole: before them on their line, or on the line over them
    let named = one(name)
    assert_true(t.text_runs().iter().any(fn(r) { r.text == name }), msg="\{name}: drawn whole")
    assert_true(t.squeeze_faults().is_empty(), msg="\{name}: \{Repr(t.squeeze_faults())}")
    lines.push(if named.2 + named.4 <= chips[0].0.2 { 2 } else { 1 })
    if lines[lines.length() - 1] == 1 {
      assert_true(named.1 + named.3 <= chips[0].0.1, msg="\{name}: \{Repr(named)} \{Repr(chips)}")
    } else {
      // (its name where its label starts over it; the chips under it at the line's end still)
      assert_eq(named.1, one("Claude · Opus 5.5").1, msg="\{name}: \{Repr(named)}")
      assert_true(chips[2].1.1 + chips[2].1.3 > named.1 + 100.0, msg="\{name}: \{Repr(named)} \{Repr(chips)}")
    }
  }
  assert_eq(lines, [1, 2])
}
