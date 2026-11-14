// What a chat's row costs as it is made, at rest, on the workspace of real size (src/sfrealsize): each of the list's
// first rows made alone (as a list makes one coming into view) on 小屏 with a finger and on 大屏 with a mouse, held to
// its bar in nodes; and the frame a workspace is switched in on 小屏 (switch_drawer_wbtest's), held to its bar in nodes
// made, let go and laid out. The bars only fall: a row made of fewer nodes brings them down in the same change.

///|
/// The most nodes one chat's row of the real workspace may be made of, at rest: 小屏 (a finger, the whole screen's
/// list) and 大屏 (a mouse, a side column's).
let row_nodes_small_most : Int = 80

///|
let row_nodes_large_most : Int = 85

///|
/// The most the frame a workspace is switched in on 小屏 may make, let go and lay out (the list 25 ms late).
// (2026-11-14: 551, 545, 407 before Home's bar held its key of the stations' newer releases, let go of in the workspace
// left and made in the one come to)
let switch_frame_most : (Int, Int, Int) = (560, 554, 414)

///|
/// The nodes each of the first `n` rows of the real workspace's list is made of, alone, at rest, in a window `w` by
/// `h` on `platform` with the list standing `at`.
fn row_nodes_each(n : Int, w : Double, h : Double, platform : Int, at : @sf.ListAt) -> Array[Int] {
  new_run()
  @sf.set_words(@sfbase.fill)
  let src = @sfrealsize.RealSizeChanging::new().source(fixture("home"))
  let items : Array[@sfbase.ChatItem] = []
  match @signals.untracked(fn() { @sfbase.chats_of(src, "ws1", "all").0 }) {
    Some(view) =>
      for d in view.days {
        for i in d.items {
          if items.length() < n {
            items.push(i)
          }
        }
      }
    None => ()
  }
  let out = []
  for item in items {
    let on : @signals.Signal[Bool] = @signals.signal(false)
    let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w~, h~, platform~)
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(@sf.ui_theme_now)
      let popup = root.box(fn(v) { v.over(Is(true)) |> ignore })
      let tips = @sf.TipLayer::new(fn() { Some(popup) })
      root.show(fn() { on.get() }, fn(slot) {
        @sfpages.chat_row_node(slot, src, tips, fn() { item }, "agents", fn() { false }, at, fn() { 0 }) |> ignore
      })
    })
    t.draw()
    t.tree_frames_from_now()
    @ui.view_tree().unwrap().event(t.time(), fn() { on.set(true) })
    t.frame()
    // (less the show's own box the row is made in)
    out.push(t.tree_frames().iter().fold(init=0, fn(s, f) { s + f.made }) - 1)
  }
  out
}

///|
test "a chat's row of the workspace of real size is made of no more nodes than its bar, on 小屏 and on 大屏" {
  let small = row_nodes_each(4, 390.0, 844.0, 2, Whole)
  let large = row_nodes_each(4, 1280.0, 800.0, 0, Side)
  println("ROWCOST small \{Repr(small)} large \{Repr(large)}")
  assert_true(small.length() == 4 && large.length() == 4)
  assert_eq(small.filter(fn(n) { n > row_nodes_small_most }), [])
  assert_eq(large.filter(fn(n) { n > row_nodes_large_most }), [])
}

///|
test "the frame a workspace is switched in on 小屏 at real size makes, lets go and lays out no more than its bar" {
  new_run()
  let src = sd_source(25.0)
  let t = sd_app(src, 390.0, 844.0, 2)
  sd_open_sheet(t)
  let title = @sf.t("android-misc.workspace.sheet.title")
  let (x, y) = sd_in_sheet(t, "个人")
  let frames = sd_frames(t, src, title, @sfbase.switch_wait_ms + @ui.move_most_ms * 2.0, fn() { t.tap(x + 4.0, y + 4.0) })
  guard frames.search_by(fn(f) { f.ws == "ws2" }) is Some(i) else { fail("not switched") }
  // (the tree's counts of the frames drawn, one a frame sd_frames saw: the switch's own)
  let f = t.tree_frames()
  assert_eq(f.length(), frames.length())
  println("SWITCHCOST \{Repr(f[i])}")
  assert_true(
    f[i].made <= switch_frame_most.0 && f[i].let_go <= switch_frame_most.1 && f[i].laid <= switch_frame_most.2,
    msg="\{Repr(f[i])}",
  )
}
