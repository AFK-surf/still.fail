// Digits all one width (Ctx::text and Ctx::rich `tabular`, TextStyle's, the theme's): asked of the host as
// style_tabular.

///|
/// Whether `text` was shaped in a font with digits all one width, and whether in one without.
fn shaped_tabular(text : String) -> (Bool, Bool) {
  let mut tab = false
  let mut own = false
  for f in text_cache.fonts {
    if f.map.contains(text) {
      if (f.style & @hostapi.style_tabular) != 0 {
        tab = true
      } else {
        own = true
      }
    }
  }
  (tab, own)
}

///|
test "a number said to be tabular is shaped with digits all one width, words not said so as the font has them" {
  let on = Ref(true)
  let t = Tester::new(
    fn(c) {
      c.column(fn() {
        c.text("45%", tabular=on.val) |> ignore
        c.text("12 MB", style=text_style(size=Sm, tabular=true)) |> ignore
        c.text("v1.2") |> ignore
      })
      |> ignore
    },
    w=300.0,
    h=200.0,
  )
  assert_eq(shaped_tabular("45%"), (true, false))
  assert_eq(shaped_tabular("12 MB"), (true, false))
  assert_eq(shaped_tabular("v1.2"), (false, true))
  // said otherwise: laid out again, as the font has them
  on.val = false
  t.frame()
  assert_eq(shaped_tabular("45%"), (true, true))
}

///|
test "a theme's tabular: the app's own words with digits all one width, what people wrote with the font's own" {
  let _ = Tester::new(
    fn(c) {
      c.with_theme({ ..Theme::light(), tabular: true }, fn() {
        c.column(fn() {
          c.text("3 of 12") |> ignore
          c.rich([span("Uploading "), span("42%", bold=true)]) |> ignore
          c.rich([span("I wrote 7 lines")], words=true) |> ignore
          c.text("v2.0", tabular=false) |> ignore
          // (no digit: shaped as it is either way, in the font the rest of the words without one are; the code face's
          // digits are all one width as they are)
          c.text("Done") |> ignore
          c.rich([span("1:03", mono=true)]) |> ignore
        })
        |> ignore
      })
    },
    w=300.0,
    h=200.0,
  )
  assert_eq(shaped_tabular("3 of 12"), (true, false))
  assert_eq(shaped_tabular("42%"), (true, false))
  assert_eq(shaped_tabular("Uploading "), (false, true))
  assert_eq(shaped_tabular("I wrote 7 lines"), (false, true))
  assert_eq(shaped_tabular("v2.0"), (false, true))
  assert_eq(shaped_tabular("Done"), (false, true))
  assert_eq(shaped_tabular("1:03"), (false, true))
}

///|
test "a style's tabular is kept through then, a later one saying otherwise over it" {
  let s = text_style(size=Sm, tabular=true)
  assert_eq(s.then(text_style(weight=Semibold)).base.tabular, Some(true))
  assert_eq(s.then(text_style(tabular=false)).base.tabular, Some(false))
}
