// 05-agent-reply (agent_reply_test.mbt) with what is kept as it was drawn kept (mbui's kept_part.mbt, kept_rows.mbt):
// the core's messages as they come, the agent's answer among them, change its topics, which what read them follows; no
// part nor row kept is built anew for a message but where it read what changed. Every frame from the words sent on is
// drawn as building every row draws it.

///|
/// What the last frame drew (Tester::drawn_text's instances), a glyph's place in the atlas left out (the atlas fills
/// in another order where rows are built every frame: what is drawn the same).
fn drawn_insts(t : @ui.Tester) -> Array[String] {
  let out = []
  for line in t.drawn_text().split("\n") {
    if line.has_prefix("inst ") {
      let f = line.split(" ").map(fn(v) { v.to_string() }).collect()
      // ("inst", then its numbers: its kind the 6th, in 1/64ths; a glyph's atlas rect the 13th to the 16th)
      if f.length() > 16 && (f[6] == "64" || f[6] == "192" || f[6] == "448") {
        for j in 13..=16 {
          f[j] = "_"
        }
      }
      out.push(f.join(" "))
    }
  }
  out
}

///|
/// The flow's steps (agent_reply_test.mbt's), the parts and rows kept, drawn again where they can be (`again`) or built
/// every frame: what each frame from the words sent on drew.
fn kept_reply(again : Bool) -> Array[Array[String]] raise {
  let f = @sfreplay.Flow::start(@sfreplay.trace("agent-reply"))
  f.t.keep_parts(true)
  f.t.drawn_again(again)
  f.tap("端到端测试")
  f.run_for(@ui.nav_push_ms)
  f.see("=studio")
  f.tap("发消息")
  f.type_text("请回答一句 064618 post:收到，这是 agent 的回复 064618")
  let frames = []
  f.t.on_each_frame(Some(fn() { frames.push(drawn_insts(f.t)) }))
  f.tap("icon:arrow-up")
  f.run_for(@sfapp.flight_ms)
  f.gone("正在发送")
  f.see_n(2, "收到，这是 agent 的回复 064618")
  f.t.on_each_frame(None)
  f.end() |> ignore
  frames
}

///|
test "05-agent-reply kept as drawn: the core's messages built again only where what they changed was read" {
  let kept = kept_reply(true)
  let built = kept_reply(false)
  assert_true(kept.length() > 10, msg="frames: \{kept.length()}")
  assert_eq(kept.length(), built.length())
  for i in 0..<kept.length() {
    let a = kept[i]
    let b = built[i]
    for j in 0..<(if a.length() < b.length() { a.length() } else { b.length() }) {
      if a[j] != b[j] {
        fail("frame \{i}, instance \{j} of \{a.length()} drawn again, \{b.length()} built:\n  again \{a[j]}\n  built \{b[j]}")
      }
    }
    if a.length() != b.length() {
      fail("frame \{i}: \{a.length()} instances drawn again, \{b.length()} built")
    }
  }
}
