// 06-draft (e2e/traces/draft.trace): words left in the field, the chat left and opened again: they are back (the
// core keeps them: composer.text; nothing sent).

///|
test "06-draft" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("draft"), seed~)
    let words = "还没发出去的草稿 082947"
    // Reports may differ in frame timing during replay. Watch this particular write so its text is still checked.
    let written_key : Ref[String] = { val: "" }
    @core.trace_to(fn(line) {
      let event = @json.parse(line) catch { _ => Json::null() }
      if event is Object(e) && e.get("out") is Some(Object(out)) &&
        out.get("call") == Some(Json::string("composer.text")) &&
        out.get("params") is Some(Object(params)) &&
        params.get("text") == Some(Json::string(words)) &&
        params.get("key") is Some(String(key)) {
        written_key.val = key
      }
    })
    defer { @core.trace_stop() }
    f.tap("端到端测试")
    f.run_for(@ui.move_most_ms)
    f.see("=willow")
    f.tap("发消息")
    f.type_text(words)
    // kept by the core as it is typed (composer.text; the next run, 07, finds it there)
    f.answered("composer.text", 1)
    f.check(written_key.val != "", "composer.text must send the draft words")
    let params : Map[String, Json] = { "key": Json::string(written_key.val) }
    let first_id = match @core.client.peek_topic("composer", params~) {
      Some(sub) => sub.id
      None => -1
    }
    f.check(first_id >= 0, "the draft must be subscribed before leaving")
    f.tap("icon:chevron-left")
    f.run_for(@ui.move_most_ms)
    f.check(@core.client.peek_topic("composer", params~) is None, "leaving must release the draft subscription")
    f.see("端到端测试")
    f.tap("端到端测试")
    f.run_for(@ui.move_most_ms)
    f.see("=willow")
    let reopened = fn() {
      match @core.client.peek_topic("composer", params~) {
        Some(sub) if sub.id != first_id =>
          match sub.value {
            Some(Object(value)) => value.get("text") == Some(Json::string(words))
            _ => false
          }
        _ => false
      }
    }
    f.until(reopened)
    f.check(reopened(), "the new draft subscription must receive the written words")
    // the draft back in the field (its words where 发消息 was)
    let field = f.t.get(@ui.Role::TextField)
    f.check(field.value == words, "the field holds \{field.value.escape()}")
    // This assertion is emitted into the live drive as well as checked in the replay.
    f.tap("field:" + words)
    f.field(words)
    // the bar moved by what this did (the field focused, the chat left) at rest
    f.run_to(@sfapp.bar_rest())
    f.end()
  })
}
