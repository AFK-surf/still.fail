// What the core sent the app for its subscriptions in a run (a trace, e2e/traces/NAME.trace), counted from the trace
// alone: a flow's replay holds the app to asking what its run asked (Flow::end: diverged, unmade), so what a trace
// says came for those asks is what the app as it is now is sent. The user (2026-11-10, 「ui 应该只订阅目前 ui 需要或者
// 可能需要的东西，严格控制通讯和序列化的量」): a phone's chats' list caught 25–55 ms at a time reading values whole
// (stations 434 KB, chats 286 KB, the changelog 125 KB sent again whole each time the list was gone back to, values
// for subscriptions already let go of), and no test saw any of it. Each trace keeps to its bar (the flows' test
// topic_bytes_known_test.mbt): how many KB of values came whole, how many of those came again for what had had one
// (the same topic and params asked again, or a whole value in place of a delta), and how many came for what was let
// go of; and each topic to the most KB one whole value of it came to in any trace. A trace's data is the e2e run's
// (a few chats, one station: a value is far smaller than on a phone in use), so the KB say what grows with what is
// asked, not what a phone is sent; how often a value comes again whole does not depend on the data. A replay asks what
// its run's app did: where the released app has a way of asking its run did not (sfcore's trace_switches), the trace
// says what an older app was sent, until it is recorded again (flows/trace_switches_test.mbt counts how many).
// A subscription let go of keeping its value (`keep`: @core.Client::keep) is held till the core's answer, `{id, v}`,
// its last message: what came for it before that is applied to what is kept, so it is not for what was let go of,
// nor is that answer (the coordinator of the migration, 2026-11-10). A `same` (asked with `have`, its value unchanged)
// is no value sent: nothing counted. Nor is what changed from the value kept (`{id, delta, kept}`, asked with `have`,
// its value changed): a message of its size as any delta, not a value whole, nor one sent again.

///|
/// What one trace says came for the app's subscriptions (tape_topics).
pub(all) struct TapeTopics {
  /// KB (rounded up) of the values that came whole
  whole_kb : Int
  /// values that came whole for a topic and params that had had one before in the run
  again : Int
  /// values or deltas that came for a subscription already let go of
  unheld : Int
  /// each topic's largest whole value, in KB (rounded up)
  topics : Map[String, Int]
}

///|
fn kb(bytes : Int) -> Int {
  (bytes + 1023) / 1024
}

///|
/// What `trace` (a trace's text: its lines, or a log with them after CORETRACE) says came for the app's
/// subscriptions. A message in is counted as its line's bytes.
pub fn tape_topics(trace : String) -> TapeTopics {
  // (a subscription by its id in the run: its topic, and its topic with its params, what one asked again shares)
  let subs : Map[Int, (String, String)] = Map([])
  let gone : Map[Int, Bool] = Map([])
  // (let go of keeping its value, till the core's `{id, v}`)
  let keeping : Map[Int, Bool] = Map([])
  let wholes : Map[String, Int] = Map([])
  let topics : Map[String, Int] = Map([])
  let mut whole = 0
  let mut again = 0
  let mut unheld = 0
  for v in trace.split("\n") {
    let line = v.to_owned()
    let start = match line.find("CORETRACE ") {
      Some(i) => i + 10
      None => if line.has_prefix("{") { 0 } else { continue }
    }
    let text = line.exact_view(start=start).to_owned()
    let j = @json.parse(text) catch {
      _ => continue
    }
    guard j is Object(m) else { continue }
    match (m.get("out"), m.get("in")) {
      (Some(Object(o)), _) =>
        match (o.get("id"), o.get("subscribe"), o.get("unsubscribe")) {
          (Some(Number(id, ..)), Some(Object(s)), _) => {
            let topic = match s.get("topic") {
              Some(String(t)) => t
              _ => "?"
            }
            subs[id.to_int()] = (topic, Json::object(s).stringify())
            gone.remove(id.to_int())
            keeping.remove(id.to_int())
          }
          (Some(Number(id, ..)), _, Some(True)) =>
            if o.get("keep") is Some(True) {
              keeping[id.to_int()] = true
            } else {
              gone[id.to_int()] = true
            }
          _ => ()
        }
      (_, Some(Object(i))) => {
        guard i.get("id") is Some(Number(id, ..)) else { continue }
        guard subs.get(id.to_int()) is Some((topic, key)) else { continue }
        if gone.contains(id.to_int()) {
          unheld += 1
          continue
        }
        if keeping.contains(id.to_int()) && i.contains("v") {
          keeping.remove(id.to_int())
          gone[id.to_int()] = true
          continue
        }
        if i.contains("value") {
          let n = @utf8.encode(text).length()
          whole += n
          let had = wholes.get(key).unwrap_or(0)
          if had > 0 {
            again += 1
          }
          wholes[key] = had + 1
          if kb(n) > topics.get(topic).unwrap_or(0) {
            topics[topic] = kb(n)
          }
        }
      }
      _ => ()
    }
  }
  { whole_kb: kb(whole), again, unheld, topics }
}

///|
/// Each trace's bar (topic_bytes_known_test.mbt): its name, the KB that may come whole, how many may come again whole,
/// how many may come for what was let go of. Empty until a test package says them (trace then says nothing of them).
let tape_bars : Map[String, (Int, Int, Int)] = Map([])

///|
/// The traces' bars, said once as a test package starts (its init): every trace a flow reads must have one.
pub fn tape_topics_known(bars : Array[(String, Int, Int, Int)]) -> Unit {
  for b in bars {
    tape_bars[b.0] = (b.1, b.2, b.3)
  }
}

///|
/// A trace's bar, None when it has none.
pub fn tape_bar(name : String) -> (Int, Int, Int)? {
  tape_bars.get(name)
}

///|
/// The names the bars are said of, as they were said.
pub fn tape_barred() -> Array[String] {
  tape_bars.keys().to_array()
}

///|
/// Whether a bar of KB `bar` holds `kb` measured: over it fails, and well under it (a tenth, at least 2 KB) fails too,
/// the bar to be brought down to what it is now.
pub fn kb_within(kb : Int, bar : Int) -> Bool {
  let slack = if bar / 10 > 2 { bar / 10 } else { 2 }
  kb <= bar && kb > bar - slack
}
