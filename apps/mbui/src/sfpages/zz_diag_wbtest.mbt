///|
test "diag 震动 platform 2" {
  for platform in [1, 2] {
    let t = setting_tester(Appearance, 390.0, platform~, h=2400.0)
    let near = t.boxes_held().filter(fn(b) { b.y > 450.0 && b.y < 760.0 })
    println("platform \{platform}: rect_of \{t.rect_of("震动")}")
    for b in near {
      println("  \{(b.index, b.parent, b.kind, b.name, b.text, b.label, b.x, b.y, b.w, b.h)}")
    }
    let s = t.get(Switch, label="震动")
    println("  switch \{s.rect}")
  }
}
