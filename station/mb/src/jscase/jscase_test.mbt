///|
/// What node's toLowerCase gives (the final sigma, U+0130, title case, beyond the BMP, Kelvin's sign).
test "lowered as JavaScript lowers" {
  let cases = [
    ("ΑΣ", "ας"),
    ("ΑΣ.", "ας."),
    ("Σ", "σ"),
    ("ΑΣΑ", "ασα"),
    ("A.Σ", "a.ς"),
    ("İstanbul", "i̇stanbul"),
    ("ẞ", "ß"),
    ("ǅ", "ǆ"),
    ("ΌΣΟΣ ΣΟΦΌΣ", "όσος σοφός"),
    ("Ⅻ", "ⅻ"),
    ("𐐀𐐁", "𐐨𐐩"),
    ("Kelvin\u{212a}", "kelvink"),
    ("ΑΣ\u{301}", "ας\u{301}"),
    ("Hello World", "hello world"),
    ("ÀÉÎ", "àéî"),
    ("ΑΣ 1", "ας 1"),
  ]
  for c in cases {
    assert_eq(@jscase.lower(c.0), c.1)
  }
}
