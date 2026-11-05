// Image requests belong to the chat's data, not to the rows a particular run of its layout happened to make.

///|
fn image_window_tester(asked : Array[String], special : Bytes, finish? : Bool = true) -> @ui.Tester {
  let images = @sfbase.ChatImages::new()
  let png = fixture_file_png("many-0.png")
  let last : Ref[(Int, Json)?] = Ref(None)
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat-many-images", w=390.0, h=844.0, platform=2, finish~, wrap=fn(base) {
    { ..base, images,
      // Keep the photo fixture's keys and geometry while using empty message text: the test exercises the images,
      // not a different unrecorded Markdown answer for each of its thirty captions.
      topic: fn(name, params) {
        let got = (base.topic)(name, params)
        if name != "chat" { return got }
        match last.val {
          Some((version, value)) if version == got.version => return { ..got, value: Some(value) }
          _ => ()
        }
        guard got.value is Some(Object(m)) && m.get("messages") is Some(Array(messages)) else { return got }
        let copy = m.copy()
        copy["messages"] = Json::array(messages.map(fn(message) {
          match message {
            Object(item) =>
              match item.get("text") {
                Some(String(words)) if words.has_prefix("图 ") => {
                  let changed = item.copy()
                  changed["text"] = Json::string("")
                  Json::object(changed)
                }
                _ => message
              }
            _ => message
          }
        }))
        let value = Json::object(copy)
        last.val = Some((got.version, value))
        { ..got, value: Some(value) }
      },
      file: fn(station, key, name) {
        images.get(station, @sfbase.file_image_id(station, key, name), "mem:window-test/" + name, fn(_, done) {
          asked.push(name)
          done(Ok((Json::object({}), Some(if name == "many-29.png" { special } else { png }))))
        })
      },
    }
  })
  t.check_looks(false)
  t.set_frame_period(host_phone_period)
  t.run_for(first_page_ms + @ui.move_most_ms + @sfpages.reveal_ms)
  t
}

///|
/// The chat list's slot containing this image, not the attachment's own inner `each` row.
fn image_window_row(t : @ui.Tester, src : String) -> @view.NodeId? {
  ignore(t)
  let tree = @ui.view_tree().unwrap()
  let held = tree.drawn_held()
  let rows = tree.rows_alive()
  let mut result = None
  for i, (d, _, _) in held {
    if d.image.map_or(false, fn(image) { image.0 == src }) {
      let (first, last) = match tree.list_rows() {
        Some(range) => range
        None => return None
      }
      let mid = d.y + d.h / 2.0
      let mut place = None
      for n in first..=last {
        match tree.list_row(n) {
          Some((_, y, _, h)) if mid >= y && mid < y + h => { place = Some((y, h)); break }
          _ => ()
        }
      }
      let mut at = i
      while at >= 0 {
        let (node, parent, _) = held[at]
        if rows.contains(node.id) && place is Some((y, h)) {
          match tree.view_of(node.id) {
            Some(view) => {
              let (_, row_y, _, row_h) = view.rect()
              if (row_y - y).abs() < 0.5 && (row_h - h).abs() < 0.5 {
                result = Some(node.id)
                break
              }
            }
            None => ()
          }
        }
        at = parent
      }
    }
  }
  result
}

///|
fn image_window_visible(t : @ui.Tester) -> Array[String] {
  ignore(t)
  let names : Array[String] = []
  for (d, _, _) in @ui.view_tree().unwrap().drawn_held() {
    match d.image {
      Some((src, _, _)) if src.has_prefix("mem:window-test/many-") && d.y + d.h > 0.0 && d.y < 844.0 =>
        if !names.contains(src) { names.push(src) }
      _ => ()
    }
  }
  names.sort()
  names
}

///|
fn image_window_path(each_frame : Bool) -> (Array[String], Array[String], Int) raise {
  let asked : Array[String] = []
  let t = image_window_tester(asked, fixture_file_png("peek.png"))
  t.drag(195.0, 250.0, 195.0, 650.0, steps=2)
  if each_frame {
    t.run_for(@ui.move_most_ms * 4.0)
  } else {
    t.advance(@ui.move_most_ms * 4.0)
    t.frame()
  }
  // Record requests and decode starts before the next frame: painting that frame is needed only to show the answers.
  let requests = asked.copy()
  requests.sort()
  let loads = t.image_loads().length()
  t.frames_owed()
  let visible = image_window_visible(t)
  assert_false(visible.is_empty(), msg="the final window contains pictures")
  println("IMAGEWINDOW each=\{each_frame} asked=\{requests} decoded=\{loads} visible=\{visible}")
  (visible, requests, loads)
}

///|
test "the same scroll requests and decodes the same pictures with or without intermediate frames" {
  let continuous = image_window_path(true)
  let end_only = image_window_path(false)
  assert_eq(continuous.0, end_only.0, msg="the same images are visible at the end")
  assert_eq(continuous.1.length(), 26, msg="every picture crossed by this scroll was requested")
  assert_eq(continuous.2, 26, msg="each crossed picture was decoded once")
  assert_eq(continuous.1, end_only.1, msg="image requests do not depend on display frames")
  assert_eq(continuous.2, end_only.2, msg="image decode count does not depend on display frames")
}

///|
test "a decoded picture survives its row being recycled and made again" {
  let asked : Array[String] = []
  let special = fixture_file_png("peek.png")
  let t = image_window_tester(asked, special)
  let src = "mem:window-test/many-29.png"
  let row = match image_window_row(t, src) {
    Some(id) => id
    None => fail("the last picture is visible in its row")
  }
  let load_name = "bytes:\{special.length()}"
  let decoded = fn() { t.image_loads().filter(fn(load) { load.0 == load_name }).length() }
  let requests = fn() { asked.filter(fn(name) { name == "many-29.png" }).length() }
  assert_eq((requests(), decoded()), (1, 1), msg="the picture was requested and decoded")
  t.drag(195.0, 250.0, 195.0, 650.0, steps=2)
  t.run_for(@ui.move_most_ms * 4.0)
  assert_false(@ui.view_tree().unwrap().rows_alive().contains(row), msg="the picture's row was recycled")
  t.drag(195.0, 650.0, 195.0, 250.0, steps=2)
  t.run_for(@ui.move_most_ms * 4.0)
  let again = match image_window_row(t, src) {
    Some(id) => id
    None => fail("the same picture is visible again")
  }
  assert_true(again != row, msg="the picture is in a new row")
  assert_eq((requests(), decoded()), (1, 1), msg="recreating the row neither asks nor decodes the picture again")
}
