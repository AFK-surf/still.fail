// The actual core answer also drawn by Android's FormulaTest and the web. The optional draw lists are rendered by
// the host's offscreen GPU renderer for inspection, not pictures of a whole app on a device.
///|
test "core formulas use the packaged outlines, retain source and share the text baseline" {
  let fixture = @json.parse(math_fixture)
  let text = math_string(math_field(fixture, "text"))
  let tree = math_field(fixture, "md")
  for dark in [false, true] {
    let t = @ui.Tester::new(fn(c) {
      set_dark(Some(dark))
      let look = begin(c)
      c.set_clear((look.p.bg >> 8) & 0xFFFFFFL)
      c.box(w=Fill(1.0), h=Fill(1.0), bg=look.p.bg, pad=24.0, fn() {
        markdown(c, text, tree=Some(tree), size=18.0) |> ignore
      }) |> ignore
    }, w=390.0, h=540.0, scale=2.0, text=math_text)
    t.draw()
    assert_eq(t.text_missing(), [])
    let (lay,_,_) = t.rich_of("Inline ").unwrap()
    assert_eq(t.run_rects("E=mc^2").length(), 1)
    assert_true(t.find("Invalid ") is Some(_))
    let blocks = core_blocks(math_array(tree), text)
    guard blocks[0] is Paragraph(xs) else { fail("missing inline formula") }
    guard xs[1] is Formula(source,drawing) else { fail("missing core formula") }
    let d = math_inline(drawing).unwrap()
    assert_eq(source,"E=mc^2")
    assert_true(d.paths.length() >= 5)
    assert_true(d.width > 0.0 && d.height > 0.0)
    // TeX remains the selected/copied value; only its positioned paths are painted.
    assert_true(lay.text.contains("E=mc^2"))
    if math_evidence() != "" {
      println("DLBEGIN " + (if dark { "native-dark" } else { "native-light" }))
      println(t.drawlist(bytes=true))
      println("DLEND")
    }
  }
  set_dark(None)
}

///|
test "the packed outlines are the alphabet's (client/math/font.json): cut as svg_path cuts their path data" {
  let table = math_glyph_table().unwrap()
  for g in [
    ("ceab738", "M698 450C698 444 700 444 705 440L717 440C731 440 735 441 737 447C738 450 764 662 764 669C764 674 760 677 757 680L203 680C196 676 197 675 193 659C188 641 190 641 197 634L228 634C255 633 276 631 281 629C284 629 285 626 285 622C285 616 147 68 144 61C140 54 135 51 125 49C114 48 88 46 65 46C39 46 39 46 34 25C32 17 31 13 31 11C31 9 32 8 33 6C36 0 12 0 322 0C596 0 605 0 608 2C613 7 718 261 718 261C718 264 715 270 712 272C708 274 687 274 683 272C680 270 680 270 670 248C620 127 584 82 518 61C478 47 456 46 334 46C244 47 243 47 243 52C243 55 305 304 312 330L364 330C429 330 446 329 462 322C477 316 482 306 482 285C482 273 481 262 475 240C471 223 471 219 476 216C479 213 480 213 492 213C505 213 505 213 508 216C511 218 512 222 544 351L577 483C572 490 574 493 557 493C534 493 538 490 534 472C529 455 524 439 519 429C496 377 456 376 381 376L372 376C347 376 324 377 324 377C324 379 384 618 386 622C388 627 391 630 396 632C401 633 410 633 485 634C588 634 610 633 638 627C688 615 704 585 704 528C704 512 698 470 698 450Z"),
    ("831e6878", "M56 347C56 335 62 330 72 327L390 327L708 328C715 332 722 336 722 347C722 358 715 363 707 367L70 367C62 363 56 358 56 347M56 153C56 142 62 137 70 133L707 133C715 137 722 142 722 153C722 165 714 168 708 173L72 173C62 170 56 165 56 153Z"),
    ("8c668546", "M406 121C403 121 400 118 394 111C355 66 302 37 240 28C232 27 220 26 209 26C177 26 162 34 147 50C129 66 121 87 121 119C121 139 125 164 132 194C153 283 171 324 206 359C220 373 233 383 249 390C270 401 283 404 306 404C350 404 367 390 367 387L366 386C365 386 360 384 355 381C333 371 319 348 319 325C319 300 335 285 360 285C399 285 427 314 427 355C427 387 406 416 371 431C352 438 329 442 306 442C300 442 293 442 287 441C188 430 92 353 53 253C40 220 34 191 34 159C34 126 40 102 53 77C78 25 129-11 202-11C215-11 230-10 241-9C302 0 356 23 398 61C409 71 429 91 429 98C429 103 412 121 406 121Z"),
  ] {
    let (id, path) = g
    assert_eq(math_outline(table, id, 0.25), Some(@pixels.svg_path(path, 0.25)))
  }
  assert_eq(math_outline(table, "0", 0.25), None)
  assert_eq(math_outline(table, "not hex", 0.25), None)
}
