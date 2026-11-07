///|
test "owned renderer preserves pixels across close and reuse" {
  let renderer = Renderer::new()
  let svg = b"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"2\" height=\"1\"><rect width=\"2\" height=\"1\" fill=\"#123456\"/></svg>"
  for _ in 0..<3 {
    let (w, h, rgba) = renderer.rasterize(svg, 4).unwrap()
    assert_eq(w, 4)
    assert_eq(h, 2)
    assert_eq(rgba.length(), 32)
    for i in 0..<8 {
      assert_eq(rgba[i * 4], b'\x12')
      assert_eq(rgba[i * 4 + 1], b'\x34')
      assert_eq(rgba[i * 4 + 2], b'\x56')
      assert_eq(rgba[i * 4 + 3], b'\xFF')
    }
    assert_true(renderer.rasterize(b"not an SVG", 4) is None)
    assert_true(renderer.rasterize(svg, 0) is None)
    renderer.close()
    renderer.close()
  }
}
