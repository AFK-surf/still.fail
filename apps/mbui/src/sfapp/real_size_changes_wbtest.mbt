// What changes of the workspace of real size (src/sfrealsize's c_*.mbt files: what the core sends each way the app asks
// a topic as each cause of client/core-ts/test/real-size-asked.ts happens, written by real-size-app.test.ts), kept so
// it cannot rot before the app's sweep of change frames reads it: each file read, each of its messages applied in
// order to the value its v_*.mbt file has (`@core.apply_delta`, a value whole in its place) giving a value.

///|
test "every change of the workspace of real size reads, and applies to the value it changes" {
  let faults : Array[String] = []
  let all = @sfrealsize.real_size_changes()
  for c in all {
    let (topic, params, cause, messages) = c
    let name = "\{topic}/\{cause} \{Json::object(params).stringify()}"
    if messages.length() == 0 {
      faults.push("\{name}: no messages read")
      continue
    }
    guard @sfrealsize.real_size_value(topic, params) is Some(first) else {
      faults.push("\{name}: no v_ value it changes")
      continue
    }
    let mut v = first
    for m in messages {
      match m {
        Array(ops) => v = @core.apply_delta(v, ops)
        Object(o) =>
          match o.get("value") {
            Some(whole) => v = whole
            None => faults.push("\{name}: a message neither ops nor a value")
          }
        _ => faults.push("\{name}: a message neither ops nor a value")
      }
    }
    if v is Null {
      faults.push("\{name}: applied, no value")
    }
  }
  assert_true(all.length() > 0)
  assert_eq(faults, [])
}
