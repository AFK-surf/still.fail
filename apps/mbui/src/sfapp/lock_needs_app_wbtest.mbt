// A web page left out of an upgraded workspace that nobody can approve there (the core's `me.needsAppText`: its person
// has no app in the list; the owner, 2026-11-13: 「开了安全模式那就需要 app」): in the workspace's place (the waiting
// page, sfpages' lock_wait.mbt and lock_wait_node.mbt) and on 安全 (security.mbt), under the title 请先安装客户端 the
// core's words in place of the ask to be approved, no word of waiting or of a trusted device (there is none) and no
// button that asks (nobody could answer it), on every screen; every rule of the Tester's audit
// clean in what those pages make (the frame's own faults around them, its rail's and its edges', are those its other
// lock screens show, lock-waiting's, and held by the sweeps' known lists).

///|
/// The words the fixture gives as the core's (core-misc.lock.needsApp), a piece of them as a line holds it.
let needs_app_piece : String = "请安装桌面或手机客户端并登录"

///|
test "a web page nobody can approve: the core's words where the ask would be, no button that asks, on every screen" {
  let faults : Array[String] = []
  for mode in ["lock-needs-app", "lock-needs-app-security"] {
    for win in corner_windows {
      let t = screen_in(mode, win, "zh")
      let words = t.words().map(fn(w) { w.0 }).join("")
      let at = "\{mode} \{win.0}"
      assert_true(words.contains(needs_app_piece), msg="\{at}: the core's words drawn (\{words})")
      assert_true(!words.contains(@sf.t("web-pages.security.request")), msg="\{at}: no button that asks")
      assert_true(!words.contains(@sf.t("web-pages.security.notAsked")), msg="\{at}: no word of asking")
      // (nothing waits and this person has no trusted device: the page says neither, its title says what to do)
      assert_true(words.contains(@sf.t("web-pages.security.needsAppTitle")), msg="\{at}: 请先安装客户端 its title (\{words})")
      assert_true(!words.contains(@sf.t("web-pages.security.waitingTitle")), msg="\{at}: not 等待批准此设备")
      assert_true(!words.contains("新设备需由你的受信任设备批准"), msg="\{at}: no word of a trusted device")
      for f in t.audit() {
        if f.contains("sfpages/lock_wait") || f.contains("sfpages/security") {
          faults.push("\{at}: \{f}")
        }
      }
    }
  }
  if faults.length() > 0 {
    println(faults.join("\n"))
  }
  assert_eq(faults, [])
}
