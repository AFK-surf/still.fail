// Where in the source a node was made and its properties said (source.mbt): kept by a tree made to keep them, the
// place that called each (a part's outside the place its caller asked for it), found from a point drawn; none kept
// by a tree made otherwise.

///|
/// The place this is called at, as source.mbt says one.
#callsite(autofill(loc))
fn here(loc~ : SourceLoc) -> String {
  @view.source_place(loc)
}

///|
/// A part as a library makes one: its outside made as what was asked for at its caller's place, a dot in it.
#callsite(autofill(loc))
fn part(parent : @view.View, dot : Ref[@view.NodeId?], loc~ : SourceLoc) -> @view.View {
  parent.box(made_for=loc, fn(b) {
    b.width(Is(Some(60.0))).height(Is(Some(40.0))).ground(Is(0x112233FFL)) |> ignore
    b.box(fn(d) {
      dot.val = Some(d.id())
      d.width(Is(Some(10.0))).height(Is(Some(10.0))).ground(Is(0x445566FFL)) |> ignore
    })
    |> ignore
  })
}

///|
test "sources: a part's dot found at its point, made in the part, the part asked for at its caller, out to the root" {
  let dot : Ref[@view.NodeId?] = Ref(None)
  let asked = Ref("")
  let padded = Ref("")
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(page) {
        // (each said on the line its place is taken on)
        page.padding(Is((8.0, 4.0, 8.0, 4.0))) |> ignore; padded.val = here()
        part(page, dot) |> ignore; asked.val = here()
      })
      |> ignore
    },
    time=fn() { 0.0 },
    sources=true,
  )
  t.frame(200.0, 100.0) |> ignore
  guard dot.val is Some(id) else { fail("no dot") }
  // (the dot drawn in from the page's padding, in the part)
  assert_eq(t.topmost_at(12.0, 8.0), Some(id))
  let steps = t.sources_of(id)
  assert_eq(steps.length(), 3)
  assert_eq(steps[0].id, id)
  assert_true(steps[0].made.has_prefix("mbui/src/view/source_test.mbt:"))
  assert_eq(steps[0].made_for, "")
  assert_eq(steps[1].made_for, asked.val)
  assert_eq(steps[1].said.map(fn(s) { s.0 }), ["Width", "Height", "Ground"])
  assert_eq(steps[2].said, [("Padding", padded.val)])
  assert_eq(steps[2].made_for, "")
  // (what the dot looks like and where each was said)
  let looks = t.looks_of(id)
  assert_true(looks[0].has_prefix("box 8,4 10×10 (said at mbui/src/view/source_test.mbt:"), msg=looks.join("; "))
  assert_true(looks[1].has_prefix("ground #445566ff (said at mbui/src/view/source_test.mbt:"), msg=looks.join("; "))
}

///|
test "sources: a tree made without keeping them keeps none, its nodes found all the same" {
  let dot : Ref[@view.NodeId?] = Ref(None)
  let t = @view.Tree::new(fn(root) { part(root, dot) |> ignore }, time=fn() { 0.0 })
  t.frame(200.0, 100.0) |> ignore
  guard dot.val is Some(id) else { fail("no dot") }
  assert_eq(t.topmost_at(5.0, 5.0), Some(id))
  assert_eq(t.sources_of(id), [])
  assert_eq(t.looks_of(id), ["box 0,0 10×10", "ground #445566ff"])
}

///|
test "sources: what a structure shows made at the structure's place, rows of a list at the list's" {
  let rows : Array[@view.NodeId] = []
  let at = Ref("")
  let t = @view.Tree::new(
    fn(root) {
      let row = fn(r : @view.View, _) {
        rows.push(r.id())
        r.height(Is(Some(10.0))).ground(Is(0x000000FFL)) |> ignore
      }
      root.each_of(fn() { [1, 2] }, row); at.val = here()
    },
    time=fn() { 0.0 },
    sources=true,
  )
  t.frame(100.0, 100.0) |> ignore
  assert_eq(rows.length(), 2)
  let steps = t.sources_of(rows[1])
  // (the row alone: the list's own node holds no box, the root was made by no call, neither said)
  assert_eq(steps.length(), 1)
  assert_eq(steps[0].made, at.val)
  assert_eq(t.topmost_at(50.0, 15.0), Some(rows[1]))
}

///|
test "sources: the places said as module/path:line" {
  assert_true(here().has_prefix("mbui/src/view/source_test.mbt:"))
  assert_false(here().contains("@"))
  assert_eq(here().split(":").count(), 2)
}
