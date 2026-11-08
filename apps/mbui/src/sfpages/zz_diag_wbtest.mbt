///|
test "diag 震动 steps" {
  for (w, platform) in page_cases + [(390.0, 1)] {
    let calls : Array[(String, Json)] = []
    let t = setting_tester(Appearance, w, platform~, h=2400.0, over=fn(s) {
      { ..s, call: fn(name, params, done) {
          calls.push((name, params))
          (s.call)(name, params, done)
        } }
    })
    let at = "\{w} platform \{platform}"
    let sets = fn() { calls.filter(fn(call) { call.0 == "prefs.set" }).map(fn(c) { c.1.stringify() }) }
    let (x, y, sw, sh) = t.get(Switch, label="震动").rect
    println("\{at}: switch \{(x, y, sw, sh)} find \{t.find("震动")}")
    t.tap_text("震动")
    t.draw()
    println("\{at}: after title tap \{sets()}")
    t.tap(x - 4.0, y + sh / 2.0)
    t.frame()
    t.frame()
    println("\{at}: after near tap \{sets()}")
    t.click(Switch, label="震动") catch {
      e => println("\{at}: click: \{e}")
    }
    t.frame()
    t.frame()
    println("\{at}: after click \{sets()}")
  }
}
