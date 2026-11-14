// The spacing rules held of the window's tree's nodes too (gaps.mbt, Ctx::with_tree_nodes), as of an old view's: a
// page made as nodes broke them unseen till 2026-11-14 (a terminal's 只看/控制 right on its card). Rule 9: blocks that
// show their edges never meet each other, nor words or a drawing, whatever boxes lay them out.

///|
/// A page of the tree, 400 wide, its ground white, 16 in, `gap` between what it lays out down it: a row holding a
/// control's track (160×36, its own ground) and, under it, a card (its own dark ground) 120 high; `split`: the track
/// in a row of its own and the card in a box of its own, as a page's list lays its blocks, else both the page's.
fn tree_page(gap : Double, split? : Bool = true) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=400.0, platform=0)
  set_view_app(fn(root) {
    root.box(fn(page) {
      page.width(Is(Some(400.0))).height(Is(Some(400.0))).pad(Is(16.0)).ground(Is(0xFFFFFFFFL)).gap(Is(gap)) |> ignore
      let track = fn(v : @view.View) {
        v.box(fn(k) {
          k.width(Is(Some(160.0))).height(Is(Some(36.0))).ground(Is(0xEEEEEEFFL)).radius(Is(18.0)) |> ignore
        })
        |> ignore
      }
      let card = fn(v : @view.View) {
        v.box(fn(k) { k.height(Is(Some(120.0))).ground(Is(0x16171AFFL)).radius(Is(12.0)) |> ignore }) |> ignore
      }
      if split {
        page.box(fn(r) {
          r.row(Is(true)) |> ignore
          track(r)
        })
        |> ignore
        page.box(fn(b) { card(b) }) |> ignore
      } else {
        track(page)
        card(page)
      }
    })
    |> ignore
  })
  t.draw()
  t
}

///|
fn tree_rule(t : Tester, rule : String) -> Array[String] {
  t.gap_faults().filter(fn(f) { f.has_prefix(rule + ":") })
}

///|
test "spacing on the window's tree: a control's track right on the card under it, each in a box of its own, said (rule 9); 12 apart, nothing" {
  let meet = tree_rule(tree_page(0.0), "rule 9")
  let apart = tree_rule(tree_page(12.0), "rule 9")
  assert_eq((meet.length(), apart), (1, []), msg=meet.join("\n"))
}

///|
test "spacing on the window's tree: the same two in one box, rule 3's (not said again by rule 9); and 7 apart, off the scale, rule 6's" {
  let t = tree_page(0.0, split=false)
  let (three, nine) = (tree_rule(t, "rule 3"), tree_rule(t, "rule 9"))
  let six = tree_rule(tree_page(7.0, split=false), "rule 6")
  assert_eq((three.length(), nine, six.length()), (1, [], 1), msg=(three + six).join("\n"))
}

///|
/// A message as the old view laid it (#6285): its words, a file's card (its ground in a box with none round it) and a
/// line under it, `gap` apart down one column.
fn old_message(gap : Double) -> Tester {
  Tester::new(
    fn(c) {
      c.box(w=Px(360.0), pad=16.0, bg=0xFFFFFFFFL, gap~, fn() {
        c.text("words of the message") |> ignore
        c.box(fn() { c.box(w=Px(240.0), h=Px(56.0), radius=12.0, bg=0xEEEEEEFFL, fn() {  }) |> ignore }) |> ignore
        c.text("you chose it") |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=300.0,
  )
}

///|
test "spacing: a message's words right on a file's card over and under it, the card in a box with no ground, said twice (rule 9); 8 apart, nothing" {
  let meet = old_message(0.0)
  meet.frame()
  let said = tree_rule(meet, "rule 9")
  let apart = old_message(8.0)
  apart.frame()
  assert_eq((said.length(), tree_rule(apart, "rule 9")), (2, []), msg=said.join("\n"))
}
