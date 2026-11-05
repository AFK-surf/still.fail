// Pictures in table cells have a smaller room than the message that holds them. The chat's owner and the
// cell drawing the picture must ask for the same decode, including after the row has been recycled.

///|
test "table pictures are decoded once at their drawn size" {
  for width in [390.0, 740.0] {
    let asked : Array[String] = []
    let images = @sfbase.ChatImages::new()
    let calls : Array[Made] = []
    let web = fixture_file_png("compare.png")
    let phone = fixture_file_png("peek.png")
    let other = fixture_file_png("home-after.png")
    let t = wide_tester(calls, mode="chat-table-images", w=width, h=1000.0, platform=2, wrap=fn(base) {
      { ..base, images, file: fn(station, key, name) {
        images.get(station, @sfbase.file_image_id(station, key, name), "mem:bucket-test/" + name, fn(_, done) {
          asked.push(name)
          let bytes = if name == "web-folded.png" { web } else if name == "phone.png" { phone } else { other }
          done(Ok((Json::object({}), Some(bytes))))
        })
      } }
    })
    t.check_looks(false)
    t.run_for(first_page_ms + @ui.move_most_ms + @sfpages.reveal_ms)
    let web_loads = t.image_loads().filter(fn(x) { x.0 == "bytes:\{web.length()}" })
    let phone_loads = t.image_loads().filter(fn(x) { x.0 == "bytes:\{phone.length()}" })
    println("IMAGEBUCKET width=\{width} asked=\{asked} web=\{web_loads} phone=\{phone_loads}")
    assert_true(asked.contains("web-folded.png") && asked.contains("phone.png"), msg="the table's pictures were requested")
    assert_eq(web_loads.length(), 1, msg="the web picture is decoded once at width \{width}")
    assert_eq(phone_loads.length(), 1, msg="the phone picture is decoded once at width \{width}")
  }
}
