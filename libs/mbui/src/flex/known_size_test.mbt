///|
test "one flexible item takes exactly the remaining room, whatever its basis was" {
  for row in [false, true] {
    for basis in [230.567, 1372.34607] {
      let root = @flex.Node::new()
      root.style.direction = if row { Row } else { Column }
      root.style.set_width(Pt(626.0))
      root.style.set_height(Pt(626.0))
      let fixed = @flex.Node::new()
      fixed.style.set_basis(Pt(20.0))
      fixed.style.shrink = 0.0
      root.add(fixed)
      let fill = @flex.Node::new()
      fill.style.set_basis(Pt(basis))
      fill.style.grow = 1.0
      fill.style.shrink = 1.0
      root.add(fill)
      @flex.compute(root, round=false)
      assert_eq(if row { fill.width } else { fill.height }, 606.0, msg="basis \{basis}, row \{row}")
    }
  }
}
