// A message can leave the list while its Markdown is being read. Its pictures still need to be requested at the sizes
// their places in that Markdown require, without depending on the row being built again.

///|
test "a crossed message's pictures wait for its Markdown and are decoded at their cell sizes" {
  let images = @sfbase.ChatImages::new()
  let calls : Array[Made] = []
  let web = fixture_file_png("compare.png")
  let phone = fixture_file_png("peek.png")
  let answer : Ref[((Json?) -> Unit)?] = Ref(None)
  let t = wide_tester(calls, mode="chat-many-images", w=390.0, h=844.0, platform=2, wrap=fn(base) {
    { ..base, images,
      topic: fn(name, params) {
        let got = (base.topic)(name, params)
        if name != "chat" { return got }
        guard got.value is Some(value) else { return got }
        let files : Array[Json] = [
          { "name": "web-folded.png", "path": "work/s-c1/web-folded.png", "owner": "s-c1", "width": 1440, "height": 900 },
          { "name": "phone.png", "path": "work/s-c1/phone.png", "owner": "s-c1", "width": 780, "height": 1688 },
        ]
        { ..got, value: Some(with_chat_message(value, 129.0, [
          ("text", Json::string(table_images_answer)), ("md", Json::null()),
          ("placed", ["web-folded.png", "phone.png"]), ("attachments", Json::array(files)),
        ])) }
      },
      file: fn(station, key, name) {
        images.get(station, @sfbase.file_image_id(station, key, name), "mem:markdown-pending/" + name, fn(_, done) {
          let bytes = if name == "web-folded.png" { web } else if name == "phone.png" { phone } else { fixture_file_png("many-0.png") }
          done(Ok((Json::object({}), Some(bytes))))
        })
      },
    }
  })
  @sf.markdown_read.val = Some(fn(text, done) {
    if text == table_images_answer { answer.val = Some(done) } else { done(None) }
  })
  t.check_looks(false)
  t.run_for(first_page_ms + @ui.move_most_ms + @sfpages.reveal_ms)
  assert_true(answer.val is Some(_), msg="the message's Markdown has been requested")
  let picture_loads = fn() {
    t.image_loads().filter(fn(load) { load.0 == "bytes:\{web.length()}" || load.0 == "bytes:\{phone.length()}" })
  }
  assert_eq(picture_loads(), [], msg="the unknown places are not decoded at a guessed size")
  t.drag(195.0, 250.0, 195.0, 650.0, steps=2)
  t.run_for(@ui.move_most_ms * 4.0)
  let tree = @ui.view_tree().unwrap()
  let (first, last) = tree.list_rows().unwrap()
  let visible : Array[String] = []
  for i in first..=last {
    match tree.list_row(i) { Some((key, _, _, _)) => visible.push(key); None => () }
  }
  assert_false(visible.contains("m:ts129"), msg="the message has left the list")
  match answer.val { Some(done) => done(Some(@sffixture.table_images_md)); None => fail("no Markdown request") }
  let decoded = picture_loads()
  @sf.markdown_read.val = None
  assert_eq(decoded.length(), 2, msg="the crossed pictures are decoded when the answer arrives, before another frame")
  assert_true(decoded.iter().all(fn(load) { load.1 == 512 }), msg="both use their table cells' decode size")
}
