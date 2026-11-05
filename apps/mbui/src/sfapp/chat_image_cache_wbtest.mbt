///|
test "pictures already seen are not asked for or decoded again as a chat is reopened and scrolled" {
  new_run()
  let images = @sfbase.ChatImages::new()
  let asks : Array[String] = []
  let src : Source = {
    ..fixture("chat-table-images"),
    file: fn(station, key, name) {
      images.get(station, @sfbase.file_image_id(station, key, name), "mem:cache-test/" + name, fn(_, done) {
        asks.push(name)
        done(Ok((Json::object({}), Some(fixture_file_png(name)))))
      })
    },
    images,
  }
  let open = fn() {
    open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  }
  open()
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms + @sfpages.reveal_ms)
  assert_true(asks.length() > 0 && t.drawn_images().length() > 0, msg="message pictures requested and drawn")
  let (first_asks, first_decodes) = (asks.length(), t.image_loads().length())
  t.back()
  t.run_for(@ui.move_most_ms)
  open()
  t.run_for(@ui.move_most_ms + @sfpages.reveal_ms)
  assert_true(t.drawn_images().length() > 0, msg="pictures drawn again")
  assert_eq((asks.length(), t.image_loads().length()), (first_asks, first_decodes), msg="reopening keeps the pictures")
  let through = fn() {
    t.drag(195.0, 250.0, 195.0, 650.0, steps=20)
    t.run_for(@ui.move_most_ms)
    t.drag(195.0, 650.0, 195.0, 250.0, steps=20)
    t.run_for(@ui.move_most_ms)
  }
  through()
  let (seen_asks, seen_decodes) = (asks.length(), t.image_loads().length())
  through()
  assert_eq((asks.length(), t.image_loads().length()), (seen_asks, seen_decodes), msg="scrolling over them again keeps the pictures")
}
