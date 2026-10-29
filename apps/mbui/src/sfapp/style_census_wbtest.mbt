// How many values of each kind the app's screens use (mbui's Tester::census over the fixtures' screens, narrow and
// wide, light and dark): sizes of words with their lines, weights, paddings and gaps, corners, colours. The styles'
// migration (mbui's docs/style.md) brings each down; scripts/style_census.sh prints them, and the values.

///|
/// The screens counted: the fixtures' modes (scripts/shots.sh's) and the settings' pages.
let census_modes : Array[String] = [
  "home", "chat", "chat-compose", "chat-attach", "chat-quote", "chat-cards", "chat-md", "files", "drive", "drive-sub",
  "reader", "decisions", "history", "chat-info", "chat-jobs", "video", "service", "share-in", "lock-code", "lock-wrong",
  "lock-waiting",
]

///|
let census_pages : Array[String] = [
  "home", "appearance", "me", "workspace", "security", "vault", "stations", "station:ws1/st1", "profiles",
  "profile:ws1/st1#cc", "connects", "memory:ws1/st1", "usage", "archive",
]

///|
test "styles: how many values of each kind the app's screens use" {
  let kinds : Array[(String, Map[String, Bool])] = [
    ("text", {}),
    ("weight", {}),
    ("space", {}),
    ("radius", {}),
    ("color", {}),
  ]
  let take = fn(k : @ui.Census) {
    for v in k.text {
      kinds[0].1[v] = true
    }
    for v in k.weight {
      kinds[1].1[v] = true
    }
    for v in k.space {
      kinds[2].1[v] = true
    }
    for v in k.radius {
      kinds[3].1[v] = true
    }
    for v in k.color {
      kinds[4].1[v] = true
    }
  }
  let screens : Array[(String, String)] = census_modes.map(fn(m) { (m, "") })
  for p in census_pages {
    screens.push(("settings", p))
  }
  for s in screens {
    for dark in ["", "-dark"] {
      for size in style_ref_sizes {
        let (_, w, h) = size
        reset()
        @settings.reset()
        let src = fixture(s.0 + dark)
        let t = @ui.Tester::new(fn(c) { view(c, src) }, w~, h~, platform=platform_of(w))
        if s.1 != "" {
          open_setting(s.1)
        }
        t.draw()
        t.run_for(@ui.move_most_ms)
        take(t.census())
      }
    }
  }
  let counts = StringBuilder()
  for k in kinds {
    let values = k.1.keys().collect()
    values.sort()
    // (scripts/style_census.sh prints these)
    println("census " + k.0 + " " + values.length().to_string() + ": " + values.join(" "))
    counts.write_string(k.0 + " " + values.length().to_string() + "\n")
  }
  inspect(counts.to_string(), content=(
    #|text 34
    #|weight 4
    #|space 22
    #|radius 23
    #|color 63
    #|








































  ))
}
