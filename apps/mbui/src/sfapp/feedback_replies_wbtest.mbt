// The still.fail team's replies on a chat's bug report (sfpages feedback_replies.mbt): said over its composer, read in a
// panel, handed to its agent only as a quote the person sends, answered as the person.

///|
/// The core's `chatFeedback` for the chat: FB-12, the team's reply on it.
fn feedback_value(latest_id? : String = "r1", latest_text? : String = "能再说一下出错时在跑什么吗？", dismissed? : Bool = false) -> Json {
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
        "latest": latest_text,
        "latestId": latest_id,
        "dismissed": dismissed,
        "replies": [
          { "id": latest_id, "from": "team", "who": "still.fail 团队", "text": latest_text, "when": "14:05" },
        ],
      },
    ],
  }
}

///|
fn feedback_core(calls : Array[Made], replied? : Bool = true, value? : Json = feedback_value()) -> @ui.Tester {
  fake_core(calls, over=fn(name, tp) {
    if name == "chatFeedback" && replied {
      { ..tp, value: Some(value) }
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

///|
test "关闭 lets the notice go (feedback.dismiss), still reachable from the chat's menu; a newer reply brings it back" {
  let calls : Array[Made] = []
  let reply_val : @signals.Signal[Json] = @signals.signal(feedback_value())
  let t = fake_core(calls, over=fn(name, tp) {
    if name == "chatFeedback" {
      { ..tp, value: Some(reply_val.get()) }
    } else if name == "chatRow" {
      { ..tp, value: Some(Json::null()) }
    } else {
      tp
    }
  })
  assert_true(t.find("still.fail 团队回复了 FB-12：能再说一下出错时在跑什么吗？") is Some(_))
  // 查看 and 关闭 keep to the room, corner, gap, contrast and hand rules
  let notice_faults = t.room_faults().filter(fn(f) { f.contains("composer/feedback") || f.contains("查看") || f.contains("关闭") })
  assert_eq(notice_faults, [])
  assert_eq(t.hand_moves(), [])
  assert_eq(t.fixed_outgrown(), [])

  t.click(Button, label="关闭")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("still.fail 团队回复了 FB-12：能再说一下出错时在跑什么吗？") is None)
  assert_true(t.find("查看") is None)
  let dismissed = named(calls, "feedback.dismiss")
  assert_eq(dismissed.length(), 1)
  let dp = Some(dismissed[0].params)
  assert_eq([text(dp, "workspace"), text(dp, "id"), text(dp, "reply")], ["ws1", "FB12", "r1"])
  assert_eq(named(calls, "chat.send").length(), 0)

  // still reachable from the chat's "…" menu once the banner is gone
  t.click(Button, label="更多")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("FB-12 的回复") is Some(_))
  t.tap_text("FB-12 的回复")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("FB-12 · chat_post 偶尔发不出去") is Some(_))
  t.back()
  t.run_for(@ui.move_most_ms)

  // a newer reply from the team brings the notice back over the composer
  reply_val.set(feedback_value(latest_id="r2", latest_text="查到了，下个版本修。"))
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("still.fail 团队回复了 FB-12：查到了，下个版本修。") is Some(_))

  // already dismissed in the core: does not show on opening
  let already = feedback_core([], value=feedback_value(dismissed=true))
  assert_true(already.find("查看") is None)
}
