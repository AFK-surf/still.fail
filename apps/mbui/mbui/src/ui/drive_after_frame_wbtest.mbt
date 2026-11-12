// A scripted run's step (drive_frame) comes where a device's input comes: after all of the frame's own work is done
// (presented, the old frame's modal layer told the window's tree as its frame closes: view_frame_end,
// Tree::hold_under), not between the two. Taken before view_frame_end, what a step's input met of what takes input,
// in the frame an old view's modal layer opened or closed in, was as the frame before had told it (View::takes_input,
// what a tip, a hover card or a peek decides by as the pointer comes over it, sf's tip_node): under a layer just
// opened, told it takes input; where one had just closed, told it takes none, so what came over it then was not
// shown. Where a press goes is asked of the old frame as it is (Tree::allows_at): that was right either way.

///|
/// An old view the whole window (400 by 300), a modal layer over all of it while `open`, whose own press (anywhere on
/// it) says in `asked` whether what is under it was told it takes input then; under it, a node of the tree's (80 by
/// 40 at the top left) whose presses are counted in `pressed`, and, at each change while the pointer is over it,
/// whether it was told it takes input (`over_told`: as a tip decides whether to show).
fn drive_layer_tester(
  open : @signals.Signal[Bool],
  pressed : Ref[Int],
  asked : Array[Bool],
  over_told : Array[Bool],
) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, pointing=Mouse)
  t.check_looks(false)
  let under : Ref[@view.View?] = Ref(None)
  set_view_app(fn(root) {
    root.box(fn(h) {
      h.grow(Is(1.0)) |> ignore
      under.val = Some(
        h.box(fn(b) {
          b
          .width(Is(Some(80.0)))
          .height(Is(Some(40.0)))
          .presses(Is(true))
          .on_press(fn() { pressed.val += 1 })
          .says(Is(Some(@view.said(Button, label="下面"))))
          |> ignore
          b.reacts(fn() { (b.pointed(), b.takes_input()) }, fn(s) {
            if s.0 {
              over_told.push(s.1)
            }
          })
        }),
      )
      old(h, fn(c) {
        guard open.get() else { return }
        c.overlay("sheet", modal=true, outside=false, fn() {
          let id = c.id("sheet button")
          let b = c.box(id~, w=Px(400.0), h=Px(300.0), bg=0xFFFFFFFFL, fn() {  })
          c.semantics(b, Button, id~, label="弹层", actions=[Activate])
          c.on_press(id, fn() {
            match under.val {
              Some(v) => asked.push(@signals.untracked(fn() { v.takes_input() }))
              None => ()
            }
          })
        })
        |> ignore
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.draw()
  t
}

///|
test "a scripted run's tap in the frame an old view's modal layer opens in is the layer's: what is under it told it takes none then, and takes no press" {
  let (open, pressed, asked, over_told) = (@signals.signal(false), Ref(0), [], [])
  let t = drive_layer_tester(open, pressed, asked, over_told)
  // (the layer opened as the run's first frame is built; the tap the step that frame, after it)
  open.set(true)
  let logs = t.drive("tapxy 40 20\nexit")
  assert_true(logs.iter().any(fn(line) { line == "EXIT 0" }), msg=logs.join("\n"))
  // (the layer's press asked whether what is under it takes input: told none, as the frame that opened it left it)
  let got = (pressed.val, asked)
  assert_eq(got, (0, [false]), msg="presses taken under the layer, what the layer's press was told: \{Repr(got)}")
}

///|
test "a scripted run's pointer come over what an old view's modal layer stopped covering that frame: told it takes input as it comes" {
  let (open, pressed, asked, over_told) = (@signals.signal(true), Ref(0), [], [])
  let t = drive_layer_tester(open, pressed, asked, over_told)
  // (the layer gone as the run's first frame is built; the pointer over the node under it the step that frame, after it)
  open.set(false)
  let logs = t.drive("move 40 20\ntapxy 40 20\nexit")
  assert_true(logs.iter().any(fn(line) { line == "EXIT 0" }), msg=logs.join("\n"))
  // (as the pointer came over it, told it takes input: one change, not none then input)
  let got = (over_told, pressed.val)
  assert_eq(got, ([true], 1), msg="told it takes input at each change while over it, presses taken: \{Repr(got)}")
}

///|
test "a scripted run's step finds what the frame drew and acts after it was presented: its press is drawn by the frame after" {
  let said = @signals.signal("按我")
  let pressed = Ref(0)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(b) {
      b
      .width(Is(Some(120.0)))
      .height(Is(Some(44.0)))
      .presses(Is(true))
      .on_press(fn() {
        pressed.val += 1
        said.set("按过了")
      })
      .says(Is(Some(@view.said(Button, label="按钮"))))
      .words(By(fn() { said.get() }))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let unpressed = t.drawn_text()
  // (each frame of the run: whether the press was taken by its end, and whether what it presented was drawn unpressed)
  let frames : Array[(Int, Bool)] = []
  let logs = t.drive("tap 按我\nexit", each=fn(t) { frames.push((pressed.val, t.drawn_text() == unpressed)) })
  assert_true(logs.iter().any(fn(line) { line == "EXIT 0" }), msg=logs.join("\n"))
  // (the frame whose step pressed it presented it unpressed, the step after it; the frame after, pressed)
  let took = frames.search_by(fn(f) { f.0 > 0 }).unwrap_or(-1)
  assert_true(took >= 0 && took + 1 < frames.length(), msg="\{Repr(frames)}")
  assert_eq((frames[took].1, frames[took + 1].1), (true, false), msg="\{Repr(frames)}")
}
