// The still.fail team's replies on a chat's bug report (sfpages feedback_replies.mbt): said over its composer, read in a
// panel, handed to its agent only as a quote the person sends, answered as the person.

///|
/// The core's `chatFeedback` for the chat: FB-12, the team's reply on it.
fn feedback_value() -> Json {
  {
    "reports": [
      {
        "id": "FB12",
        "workspace": "ws1",
        "account": "u1",
        "number": 12,
        "label": "FB-12",
        "title": "chat_post 偶尔发不出去",
        "heading": "still.fail 团队回复了 FB-12",
        "latest": "能再说一下出错时在跑什么吗？",
        "replies": [
          { "id": "r1", "from": "team", "who": "still.fail 团队", "text": "能再说一下出错时在跑什么吗？", "when": "14:05" },
        ],
      },
    ],
  }
}

///|
fn feedback_core(calls : Array[Made], replied? : Bool = true) -> @ui.Tester {
  fake_core(calls, over=fn(name, tp) {
    if name == "chatFeedback" && replied {
      { ..tp, value: Some(feedback_value()) }
    } else {
      tp
    }
  })
}

///|
test "a chat whose report the team replied on says so over its composer; one with none says nothing" {
  let calls : Array[Made] = []
  let t = feedback_core(calls)
  assert_true(t.find("still.fail 团队回复了 FB-12：能再说一下出错时在跑什么吗？") is Some(_))
  assert_true(t.find("查看") is Some(_))
  // nothing of it is sent anywhere by being shown: no call names it
  assert_eq(calls.filter(fn(m) { m.name.contains("feedback") || m.name == "chat.send" }).length(), 0)
  let none = feedback_core([], replied=false)
  assert_true(none.find("查看") is None)
}

///|
test "查看 opens the replies; 回复 answers the team as the person, the field emptied once it is there" {
  let calls : Array[Made] = []
  let t = feedback_core(calls)
  t.tap_text("查看")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("FB-12 · chat_post 偶尔发不出去") is Some(_))
  assert_true(t.find("能再说一下出错时在跑什么吗？") is Some(_))
  t.tap_text("回复 still.fail 团队…")
  t.type_text("那会儿在跑 pnpm build")
  t.click(Button, label="回复")
  let asked = named(calls, "workspace.feedbackReply")
  assert_eq(asked.length(), 1)
  let p = Some(asked[0].params)
  assert_eq([text(p, "account"), text(p, "workspace"), text(p, "id"), text(p, "text")], ["u1", "ws1", "FB12", "那会儿在跑 pnpm build"])
  // nothing goes to the chat's agent
  assert_eq(named(calls, "chat.send").length(), 0)
  assert_eq(named(calls, "composer.quote").length(), 0)
  (asked[0].done)(Ok({ "id": "r2" }))
  t.draw()
  assert_true(t.find("那会儿在跑 pnpm build") is None)
}

///|
test "交给 agent puts the team's reply in the chat's draft as a quote, whose it is and on what, and closes the panel" {
  let calls : Array[Made] = []
  let t = feedback_core(calls)
  t.tap_text("查看")
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="交给 agent")
  t.run_for(@ui.move_most_ms)
  let quoted = named(calls, "composer.quote")
  assert_eq(quoted.length(), 1)
  let q = field(Some(quoted[0].params), "quote")
  assert_eq(text(q, "author"), "still.fail 团队 · FB-12")
  assert_eq(text(q, "text"), "能再说一下出错时在跑什么吗？")
  // in the draft, not sent: the person sends it, or not
  assert_eq(named(calls, "chat.send").length(), 0)
  assert_true(t.find("FB-12 · chat_post 偶尔发不出去") is None)
}
