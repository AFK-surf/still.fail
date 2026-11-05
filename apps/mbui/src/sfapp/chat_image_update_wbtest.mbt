// A picture added to a message already in sight is wanted when the message changes, before another display frame.

///|
fn image_update_delivery(late : Bool) -> Unit raise {
  let changed = @signals.signal(0)
  let images = @sfbase.ChatImages::new()
  let asked : Array[String] = []
  let calls : Array[Made] = []
  let fresh = fixture_file_png("peek.png")
  let answer : Ref[(Result[(Json, Bytes?), Json]) -> Unit] = Ref(fn(_) {  })
  let t = wide_tester(calls, mode="chat-many-images", w=390.0, h=844.0, platform=2, wrap=fn(base) {
    { ..base, images,
      topic: fn(name, params) {
        let got = (base.topic)(name, params)
        if name != "chat" { return got }
        let version = changed.get()
        guard version > 0 && got.value is Some(value) else { return { ..got, version: got.version + version } }
        let files : Array[Json] = [
          { "name": "many-29.png", "path": "work/s-c1/many-29.png", "owner": "s-c1", "width": 640, "height": 480 },
          { "name": "new-picture.png", "path": "work/s-c1/new-picture.png", "owner": "s-c1", "width": 160, "height": 100 },
        ]
        { ..got, value: Some(with_chat_message(value, 129.0, [("attachments", Json::array(files))])), version: got.version + version }
      },
      file: fn(station, key, name) {
        images.get(station, @sfbase.file_image_id(station, key, name), "mem:update-test/" + name, fn(_, done) {
          asked.push(name)
          if late && name == "new-picture.png" {
            answer.val = done
          } else {
            done(Ok((Json::object({}), Some(if name == "new-picture.png" { fresh } else { fixture_file_png("many-0.png") }))))
          }
        })
      },
    }
  })
  t.check_looks(false)
  t.run_for(first_page_ms + @ui.move_most_ms + @sfpages.reveal_ms)
  assert_true(asked.contains("many-29.png"), msg="the changed message is already in sight")
  assert_false(asked.contains("new-picture.png"))
  // The message arrives during another change. A later observer of that delivery must see the file request.
  let requested_with_delivery = Ref(false)
  let deliver = @signals.signal(false)
  let stop = @signals.effect(fn() {
    if deliver.get() {
      @signals.after_flush(fn() { requested_with_delivery.val = asked.contains("new-picture.png") })
      changed.set(1)
    }
  })
  deliver.set(true)
  stop()
  assert_true(requested_with_delivery.val, msg="the request is made in the message's own delivery")
  // No frame is drawn between the new message data and these checks.
  assert_true(asked.contains("new-picture.png"), msg="the new picture is requested by the message change")
  if late {
    assert_eq(t.image_loads().filter(fn(load) { load.0 == "bytes:\{fresh.length()}" }).length(), 0)
    (answer.val)(Ok((Json::object({}), Some(fresh))))
  }
  assert_eq(t.image_loads().filter(fn(load) { load.0 == "bytes:\{fresh.length()}" }).length(), 1,
    msg="the new picture is decoded without waiting for a frame, even after the delivery's effect has stopped")
}

///|
test "an image added to a visible message is requested during delivery, whether its answer is immediate or later" {
  image_update_delivery(false)
  image_update_delivery(true)
}
