///|
test "write_i64 says a number as \\{} says it" {
  let vs : Array[Int64] = [0L, 1L, -1L, 9L, 10L, -10L, 64L, 192L, 448L, 123456789L, -987654321L, 9223372036854775807L,
    -9223372036854775807L - 1L]
  for v in vs {
    let sb = StringBuilder()
    write_i64(sb, v)
    assert_eq(sb.to_string(), v.to_string())
  }
}
