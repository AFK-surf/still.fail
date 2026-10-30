// The layout is the screen's, never the hand's (docs/architecture.md): each page with touch and with keyboard and mouse,
// in a window of each tier, drawn pointed at by a finger and by a mouse, lays out the same boxes; only how they answer
// the hand differs.

///|
/// The windows: touch's (Android's) and keyboard and mouse's (a Mac's), each at a width of each tier.
let hand_windows : Array[(String, Double, Double, Int)] = [
  ("touch small", 390.0, 844.0, 2),
  ("touch medium", 720.0, 900.0, 2),
  ("touch large", 1280.0, 800.0, 2),
  ("computer small", 500.0, 800.0, 0),
  ("computer medium", 720.0, 800.0, 0),
  ("computer large", 1280.0, 800.0, 0),
]

///|
/// The pages looked at: the chats' list, a chat, a new chat, the files and a folder, a history, search, the
/// settings and their places, a device waiting in the lock.
let hand_modes : Array[String] = [
  "home", "chat", "newchat", "files", "drive", "history", "search", "settings-home", "settings-appearance",
  "place-stations", "place-profiles", "lock-waiting",
]

///|
/// Where a finger's and a mouse's differ still, and why (none now: the composer's look is the screen's).
let hand_known : Array[String] = []

///|
/// 待处理 open from the rail's bell over the wide frame, in a Windows window, every row lit and its 忽略 shown, each as
/// tall as at rest (the user, 2026-10-26: 「待处理里某个 station 离线也是」「好像是 hover 让高度变化了」: 忽略 a point
/// taller than the row's line). The corners' check holds every screen so (Tester::hand_moves); 待处理 open is none of
/// its screens: in its Mac windows, no window buttons in their top row, the bell lit with its panel open stands off
/// the window's corner (to be stood right apart from this). A Windows window's corner is too square to follow.
test "the hand grows no row of 待处理: a station offline and a decision to let go, 忽略 shown, as tall as at rest" {
  let src : Ref[Source?] = Ref(None)
  let t = @ui.Tester::new(
    fn(c) {
      let s = match src.val {
        Some(s) => s
        None => {
          let s = fixture_app("home-attention")
          src.val = Some(s)
          s
        }
      }
      view(c, s)
    },
    w=1280.0,
    h=800.0,
    platform=3,
    window_corner=test_window_corner(3),
    env=[("MBUI_REDUCE_MOTION", "1")],
  )
  t.run_for(squeeze_opening)
  t.frame()
  assert_true(t.find("MBA 离线") is Some(_))
  assert_true(t.find("选一个发布的时间") is Some(_))
  assert_eq(t.hand_moves(), [])
}

///|
/// Page `mode` in window `win`, pointed at by `hand`, as laid out once it has opened.
fn hand_layout(mode : String, win : (String, Double, Double, Int), hand : @ui.Pointing) -> String {
  let (_, w, h, platform) = win
  let src : Ref[Source?] = Ref(None)
  let t = @ui.Tester::new(
    fn(c) {
      let s = match src.val {
        Some(s) => s
        None => {
          let s = fixture_app(mode)
          src.val = Some(s)
          s
        }
      }
      view(c, s)
    },
    w~,
    h~,
    platform~,
    pointing=hand,
    env=[("MBUI_REDUCE_MOTION", "1")],
  )
  t.run_for(squeeze_opening)
  t.frame()
  t.dump()
}

///|
test "the hand changes no box: every page in every tier, on a touch device and on a computer, a finger's and a mouse's alike" {
  let wrong : Array[String] = []
  for win in hand_windows {
    for mode in hand_modes {
      let finger = hand_layout(mode, win, Finger)
      let mouse = hand_layout(mode, win, Mouse)
      let known = hand_known.contains("\{win.0} \{mode}")
      if finger != mouse && !known {
        let f = finger.split("\n").to_array()
        let m = mouse.split("\n").to_array()
        let mut k = 0
        while k < f.length() && k < m.length() && f[k] == m[k] {
          k += 1
        }
        let at = fn(a : Array[StringView]) { if k < a.length() { a[k].to_string() } else { "(none)" } }
        // (what it is in: the lines over it, the finger's)
        let over = StringBuilder()
        for i in (if k > 6 { k - 6 } else { 0 })..<k {
          over.write_string("    \{f[i]}\n")
        }
        wrong.push("\{win.0} \{mode}: line \{k + 1}\n\{over.to_string()}  finger \{at(f)}\n  mouse  \{at(m)}")
      } else if known && finger == mouse {
        wrong.push("\{win.0} \{mode}: the same now: out of hand_known")
      }
    }
  }
  if wrong.length() > 0 {
    fail(wrong.join("\n"))
  }
}
