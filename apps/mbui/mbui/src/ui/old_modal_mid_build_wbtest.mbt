// What of the window's tree is under the old frame's modal layer takes no input, whatever the tree changes while the
// old frame is being built again: there the old frame answers where its modal layer is from the frame it was last
// built as (Ctx::modal_layer, Ctx::old_modal_stack), not from the nodes the new build has written so far. Asked of
// those, it said no modal layer at all, and a change of the tree made in that build (a toast shown as an old view is
// built: publish_wbtest's 分享图片 sheet over 小屏's tape, its sidebar's resize edge) told all of the tree it takes
// input, the edge with it, till the next whole telling.

///|
/// An old view the whole window (400 by 300), a modal layer over it while `open`; under it, a node of the tree's
/// pressed by a finger, whose taking input is read (`under`); a toast of the tree's, shown as `toast` says, said so by
/// the old view as it builds again for `poke` coming to a count it has not said it for.
fn mid_build_tester(
  open : @signals.Signal[Bool],
  poke : @signals.Signal[Int],
  toast : @signals.Signal[Bool],
  under : Ref[@view.View?],
) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  t.check_looks(false)
  let poked = Ref(0)
  set_view_app(fn(root) {
    root.box(fn(h) {
      h.grow(Is(1.0)) |> ignore
      under.val = Some(
        h.box(fn(b) {
          b
          .width(Is(Some(80.0)))
          .height(Is(Some(40.0)))
          .presses(Is(true))
          .on_press(fn() {  })
          .says(Is(Some(@view.said(Button, label="下面"))))
          |> ignore
          @signals.untracked(fn() { b.takes_input() }) |> ignore
        }),
      )
      old(h, fn(c) {
        // (a change of the tree said as the old view builds: a toast shown)
        if poke.get() > poked.val {
          poked.val = poke.get()
          toast.set(true)
        }
        guard open.get() else { return }
        c.overlay("sheet", modal=true, outside=false, fn() {
          let id = c.id("sheet button")
          let b = c.box(id~, w=Px(400.0), h=Px(300.0), bg=0xFFFFFFFFL, fn() {  })
          c.semantics(b, Button, id~, label="弹层", actions=[Activate])
        })
        |> ignore
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
    root.show(fn() { toast.get() }, fn(s) {
      s.width(Is(Some(80.0))).height(Is(Some(40.0))).says(Is(Some(@view.said(Status, label="已保存")))) |> ignore
    })
  })
  t.draw()
  t.draw()
  t
}

///|
/// How long each step is given: the build its change is said in, and the frame after it; nothing in it moves.
let mid_build_frames_ms : Double = 100.0

///|
/// Whether the node under the layer was last told it takes input.
fn mid_build_told(under : Ref[@view.View?]) -> Bool {
  let v = under.val.unwrap()
  @signals.untracked(fn() { v.takes_input() })
}

///|
test "the old frame's modal layer over the tree, a toast of the tree's shown as the old view is built again: what is under the layer told it takes no input, then and after" {
  let (open, poke, under) = (@signals.signal(true), @signals.signal(0), Ref(None))
  let toast = @signals.signal(false)
  let t = mid_build_tester(open, poke, toast, under)
  let before = mid_build_told(under)
  poke.set(1)
  t.run_for(mid_build_frames_ms)
  // (the toast said shown as the old view built again: under the layer too, read out none)
  let shown = @signals.untracked(fn() { toast.get() })
  let got = (before, shown, mid_build_told(under))
  assert_eq(got, (false, true, false), msg="under the layer, told it takes input (before, the toast said, after the toast): \{Repr(got)}")
}

///|
test "the old frame's modal layer opened, then gone, each in one frame: what is under it told it takes none, then takes input, once the frame that did it has ended" {
  let (open, poke, under) = (@signals.signal(false), @signals.signal(0), Ref(None))
  let toast = @signals.signal(false)
  let t = mid_build_tester(open, poke, toast, under)
  let none_over = mid_build_told(under)
  open.set(true)
  t.run_for(mid_build_frames_ms)
  let opened = mid_build_told(under)
  // (and a toast shown as the next build runs, the layer as it was: told so still)
  poke.set(1)
  t.run_for(mid_build_frames_ms)
  let toasted = mid_build_told(under)
  open.set(false)
  t.run_for(mid_build_frames_ms)
  let gone = mid_build_told(under)
  let got = (none_over, opened, toasted, gone)
  assert_eq(
    got,
    (true, false, false, true),
    msg="under the layer, told it takes input (none over it, the layer opened, a toast shown, the layer gone): \{Repr(got)}",
  )
}
