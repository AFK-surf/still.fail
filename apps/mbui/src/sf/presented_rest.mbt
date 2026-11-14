// When what the presenters hold up as a sheet is at rest, whichever kind it is drawn as: the old frame's sheet
// (@kit.sheet_rest of the presenters' key) or a sheet of the window's tree (sheet_node). What a test or a flow runs to
// once it opened, dragged or closed one: the moment its motions said end, from their causes' moments and their lengths,
// never found by asking whether something still moves.

///|
/// What each sheet of the window's tree presented says of when its motions end, by a number of its own, let go with its
/// layer.
// kept across runs: each let go with its sheet's layer; presenters_reset empties it
let presented_sheet_rests : Map[Int, (Bool) -> Double] = Map([])

///|
// kept across runs: only counts; presenters_reset puts it back
let presented_sheet_next : Ref[Int] = Ref(0)

///|
/// When the motions of the tree's sheets already let go said they end, the latest: what presented_rest answers for one
/// that has gone, as the old frame's sheet's rest still says its end once it is still.
// kept across runs: presenters_reset puts it back
let presented_sheet_ended : Ref[Double] = Ref(-1.0)

///|
/// Layer `layer` (a sheet of the tree's the presenters hold up) says when its motions end with `rest`, till it is let
/// go: `rest(true)` as it is laid out as of now (asked between frames), `rest(false)` as it was last laid out (asked as
/// the layer is let go, nothing laid out anew then).
fn presented_sheet_rest(layer : @view.View, rest : (Bool) -> Double) -> Unit {
  presented_sheet_next.val += 1
  let k = presented_sheet_next.val
  presented_sheet_rests[k] = rest
  layer.owns(fn() {
    let r = rest(false)
    if r > presented_sheet_ended.val {
      presented_sheet_ended.val = r
    }
    presented_sheet_rests.remove(k)
  })
  |> ignore
}

///|
/// When the sheet the presenters hold up (or let go of, sinking) is at rest: the latest of the old frame's sheet's
/// rest and each of the tree's sheets' (its rise or sink, its scrim, a height it was dragged or tapped to, its way back
/// under a finger let go), each its cause's moment and its length; -1 where none moves or ever did.
pub fn presented_rest() -> Double {
  // (the old frame's: the presenters' own key, present_sheet's)
  let mut end = @kit.sheet_rest("sf-present")
  if presented_sheet_ended.val > end {
    end = presented_sheet_ended.val
  }
  for _, rest in presented_sheet_rests {
    let r = rest(true)
    if r > end {
      end = r
    }
  }
  end
}
