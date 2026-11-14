// What the core sends the app for its subscriptions in each flow's run (@sfreplay.tape_topics: src/sfreplay
// topic_bytes.mbt), held to the bars topic_bytes_known_test.mbt says: each trace's, and each topic's largest value.

///|
test "what the core sends for what the app subscribes to: each run and each topic within its bar" {
  let wrong : Array[String] = []
  let said : Array[String] = []
  let largest : Map[String, (Int, String)] = Map([])
  let names = @sfreplay.tape_barred()
  names.sort()
  for name in names {
    let got = @sfreplay.tape_topics(@sfreplay.trace(name))
    said.push("    (\"\{name}\", \{got.whole_kb}, \{got.again}, \{got.unheld}),")
    for topic, n in got.topics {
      if n > largest.get(topic).map(fn(l) { l.0 }).unwrap_or(0) {
        largest[topic] = (n, name)
      }
    }
    guard @sfreplay.tape_bar(name) is Some((kb, again, unheld)) else { continue }
    if !@sfreplay.kb_within(got.whole_kb, kb) {
      wrong.push(
        "\{name}: \{got.whole_kb} KB of values came whole, its bar \{kb} KB" +
        (if got.whole_kb > kb {
          " (more: what does it subscribe to that it does not show? ask for what is shown, and a delta, not the whole again)"
        } else {
          " (fewer: its bar comes down to it)"
        }),
      )
    }
    if got.again != again {
      wrong.push(
        "\{name}: \{got.again} values came again whole for what had had one, its bar \{again}" +
        (if got.again > again {
          " (more: a page let go of a topic and asked it again, or a value came whole in place of a delta)"
        } else {
          " (fewer: its bar comes down to it)"
        }),
      )
    }
    if got.unheld != unheld {
      wrong.push(
        "\{name}: \{got.unheld} messages came for subscriptions let go of, its bar \{unheld}" +
        (if got.unheld > unheld { "" } else { " (fewer: its bar comes down to it)" }),
      )
    }
  }
  let topics = largest.keys().to_array()
  topics.sort()
  let said_topics : Array[String] = []
  for topic in topics {
    let (n, at) = largest[topic]
    said_topics.push("    (\"\{topic}\", \{n}),")
    match topic_whole_known.get(topic) {
      None => wrong.push("\{topic}: a value of it came whole (\{n} KB, in \{at}), and it has no bar")
      Some(bar) =>
        if !@sfreplay.kb_within(n, bar) {
          wrong.push(
            "\{topic}: its largest whole value \{n} KB (in \{at}), its bar \{bar} KB" +
            (if n > bar { " (more: what of it does no page show?)" } else { " (fewer: its bar comes down to it)" }),
          )
        }
    }
  }
  for topic, _ in topic_whole_known {
    if !largest.contains(topic) {
      wrong.push("\{topic}: no run is sent it any more: its bar goes")
    }
  }
  if wrong.length() > 0 {
    println("TOPIC BYTES now, each run:\n" + said.join("\n"))
    println("TOPIC BYTES now, each topic:\n" + said_topics.join("\n"))
    fail(wrong.join("\n"))
  }
}
