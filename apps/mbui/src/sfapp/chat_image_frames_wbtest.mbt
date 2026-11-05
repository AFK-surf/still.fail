///|
test "a picture's progress and decode do not build the old frame of its chat" {
  let progress : Map[String, (Json) -> Unit] = {}
  let answers : Map[String, (Result[(Json, Bytes?), Json]) -> Unit] = {}
  let asked : Array[String] = []
  let images = @sfbase.ChatImages::new()
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat-many-images", w=390.0, h=844.0, platform=2, wrap=fn(base) {
    { ..base, images, file: fn(station, key, name) {
      images.get(station, @sfbase.file_image_id(station, key, name), "mem:frame-test/" + name,
        fn(heard, done) {
          asked.push(name)
          progress[name] = heard
          answers[name] = done
        })
    } }
  })
  // Count only frames asked for by the app, not the Tester's comparison builds.
  t.keep_parts(true)
  t.check_looks(false)
  t.set_frame_period(host_phone_period)
  ignore(host_frames_till(t, t.time() + first_page_ms + @ui.move_most_ms))
  assert_true(asked.length() > 0, msg="the open chat asked for a picture")
  let name = asked[0]
  (progress[name])({ "loaded": 5.0, "total": 10.0 })
  let (_, progress_builds) = steps_built(t, @sfpages.coming_after_ms + @sfpages.coming_in_ms)
  assert_eq(progress_builds, [], msg="a picture's progress must not build the old frame")
  (answers[name])(Ok((Json::object({}), Some(fixture_file_png(name)))))
  let (_, arrival_builds) = steps_built(t, @sfpages.reveal_ms)
  assert_eq(@ui.image_state("mem:frame-test/" + name), 1, msg="the picture is decoded")
  assert_true(t.drawn_images().length() > 0, msg="the picture is shown")
  assert_eq(arrival_builds, [], msg="a picture's decode must not build the old frame")
}
