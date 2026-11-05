// A chat's latest page in flight: the original page turns its button and will not ask for it twice.

///|
fn latest_pending_core(calls : Array[Made], busy : @signals.Signal[Bool]) -> @ui.Tester {
  fake_core(calls, over=fn(name, tp) {
    if name == "chat" {
      match tp.value {
        Some(Object(m)) => {
          let o = m.copy()
          o["newer"] = Json::boolean(true)
          { ..tp, value: Some(Json::object(o)) }
        }
        _ => tp
      }
    } else if name == "doing" && busy.get() {
      { ..tp, value: Some({ "doing": [
        { "call": "chat.latest", "stage": "running", "params": { "station": "ws1/st1", "thread": "7" } },
      ] }) }
    } else {
      tp
    }
  })
}

///|
test "a latest page being fetched turns a spinner in the jump button" {
  let calls : Array[Made] = []
  let busy = @signals.signal(true)
  let t = latest_pending_core(calls, busy)
  let (x, y, w, h) = t.get(Button, label=@sf.t("web-main.chat.toLatest")).rect
  // The spinner's ring is made of lines inside this button, not elsewhere in the page.
  let pieces = t.drawn_instances().filter(fn(i) {
    i[5] == 10.0 && i[0] >= x && i[1] >= y && i[0] + i[2] <= x + w && i[1] + i[3] <= y + h
  })
  assert_false(pieces.is_empty(), msg="the latest page is being fetched; the button has no spinner")
}

///|
test "a latest page being fetched cannot be requested a second time" {
  let calls : Array[Made] = []
  let busy = @signals.signal(false)
  let t = latest_pending_core(calls, busy)
  t.click(Button, label=@sf.t("web-main.chat.toLatest"))
  assert_eq(named(calls, "chat.latest").length(), 1)
  busy.set(true)
  t.draw()
  t.click(Button, label=@sf.t("web-main.chat.toLatest"))
  assert_eq(named(calls, "chat.latest").length(), 1, msg="the request already under way must not be repeated")
  busy.set(false)
  t.draw()
  t.click(Button, label=@sf.t("web-main.chat.toLatest"))
  assert_eq(named(calls, "chat.latest").length(), 2, msg="the button can be used again once the request has ended")
}
