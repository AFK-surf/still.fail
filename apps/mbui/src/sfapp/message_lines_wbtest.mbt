// What a message says besides its words (sfpages' message.mbt): a failing notice opened to what failed said of it, with
// 复制; under the viewer's message, the runtime it waits for that the station lacks (blocked_line), or that it waits for
// its agent to take it.

///|
/// The fixture's chat, each message of it changed by `change` (the message, as the core says it).
fn changed_chat(calls : Array[Made], change : (Map[String, Json]) -> Unit) -> @ui.Tester {
  fake_core(calls, over=fn(name, tp) {
    guard name == "chat" && tp.value is Some(Object(m)) else { return tp }
    let all = items(tp.value, "messages").map(fn(x) {
      match x {
        Object(xm) => {
          let w = xm.copy()
          change(w)
          Json::object(w)
        }
        _ => x
      }
    })
    let o = m.copy()
    o["messages"] = Json::array(all)
    { ..tp, value: Some(Json::object(o)) }
  })
}

///|
let failed_notice : String = "Willow 上 codex 的登录已失效：请在设置里重新登录"

///|
let failed_detail : String = "codex: 401 Unauthorized (token expired at 2026-10-19T05:12:00Z)"

///|
test "a failing notice pressed opens to what failed said of it, as it said it, with 复制: copied, 已复制 a moment" {
  let calls : Array[Made] = []
  let t = changed_chat(calls, fn(w) {
    match w.get("notice") {
      Some(Object(n)) if text(Some(Json::object(n)), "words") == failed_notice => {
        let o = n.copy()
        o["detail"] = Json::string(failed_detail)
        w["notice"] = Json::object(o)
      }
      _ => ()
    }
  })
  t.run_for(@ui.move_most_ms)
  assert_true(t.find(failed_detail) is None)
  t.tap_text(failed_notice)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find(failed_detail) is Some(_), msg="\{Repr(t.words().map(fn(w) { w.0 }))}")
  t.tap_text("复制")
  t.draw()
  assert_eq(t.clipboard(), failed_detail)
  assert_true(t.find("已复制") is Some(_))
  t.run_for(@sf.copied_ms)
  assert_true(t.find("已复制") is None)
  assert_true(t.find("复制") is Some(_))
  // pressed again, closed
  t.tap_text(failed_notice)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find(failed_detail) is None)
}

///|
/// The viewer's last message (还有深色模式也看一下) waiting for `blocked` (the core's message `blocked`), else for its agent.
fn blocked_chat(calls : Array[Made], blocked : Json?) -> @ui.Tester {
  changed_chat(calls, fn(w) {
    if text(Some(Json::object(w)), "text") == "还有深色模式也看一下" {
      match blocked {
        Some(b) => w["blocked"] = b
        None => w["waiting"] = Json::boolean(true)
      }
    }
  })
}

///|
test "the viewer's message waiting for a runtime its station lacks says so under it; the line pressed installs it there (software.update)" {
  let calls : Array[Made] = []
  let t = blocked_chat(calls, Some({ "runtime": "codex", "state": "missing", "title": "Willow 上没有 codex", "action": "安装" }))
  t.run_for(@ui.move_most_ms)
  let (_, my) = t.find("还有深色模式也看一下").unwrap()
  let (_, by) = t.find("Willow 上没有 codex").unwrap()
  assert_true(by > my, msg="\{by} \{my}")
  t.tap_text("安装")
  t.draw()
  let made = named(calls, "software.update")
  assert_eq(made.length(), 1)
  assert_eq(text(Some(made[0].params), "station"), "ws1/st1")
  assert_eq(text(Some(made[0].params), "id"), "codex")
}

///|
test "a runtime installing says how far under the message, and pressed then installs nothing more" {
  let calls : Array[Made] = []
  let t = blocked_chat(calls, Some({ "runtime": "codex", "state": "installing", "title": "正在安装 codex", "percent": 40 }))
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("正在安装 codex 40%") is Some(_), msg="\{Repr(t.words().map(fn(w) { w.0 }))}")
  t.tap_text("正在安装 codex 40%")
  t.draw()
  assert_eq(named(calls, "software.update").length(), 0)
}

///|
test "the viewer's message its agent has not taken yet says 等待 agent 接收 under it" {
  let calls : Array[Made] = []
  let t = blocked_chat(calls, None)
  t.run_for(@ui.move_most_ms)
  let (_, my) = t.find("还有深色模式也看一下").unwrap()
  guard t.find("等待 agent 接收") is Some((_, wy)) else { fail("\{Repr(t.words().map(fn(w) { w.0 }))}") }
  assert_true(wy > my)
}
