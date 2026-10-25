///|
test "station SVGs preserve strokes, filled details and rounded corners" {
  let (lines, dots) = svg_glyph(
    #|<svg fill="none" stroke="currentColor"><rect x="6" y="2.5" width="12" height="19" rx="2.5"/><circle cx="12" cy="12" r="2" fill="currentColor" stroke="none"/><path d="M10 6H14"/></svg>
  )
  assert_eq(lines.length(), 2)
  assert_eq(dots.length(), 1)
  assert_eq(lines[0], "M8.5 2.5h7a2.5 2.5 0 0 1 2.5 2.5v14a2.5 2.5 0 0 1 -2.5 2.5h-7a2.5 2.5 0 0 1 -2.5 -2.5v-14a2.5 2.5 0 0 1 2.5 -2.5Z")
  assert_eq(lines[1], "M10 6H14")
  assert_eq(dots[0], "M10 12a2 2 0 1 0 4 0a2 2 0 1 0 -4 0Z")
}
