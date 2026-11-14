// A message's image while it waits (sfpages message_files.mbt image_item, image_reveal): its colours already soft,
// so nothing about it changes as it is decoded but the edge brushing down (the user,
// 2026-10-31: 从 placeholder 切换到缩略图会先变模糊然后再出动效，建议直接 placeholder 就是模糊的).

///|
test "a message's image waits with soft colours, and those colours do not change as its way in begins" {
  reset()
  // what its station has given of it so far: nothing ("": asked), then its picture
  let key = Ref("")
  let src : Source = { ..fixture("chat"), file: fn(_, _, _) { key.val } }
  // (said while the chat shows: the one kind of message whose picture is brushed in, image_reveal's `comes`)
  let m = message_of({
    "seq": 3,
    "ts": "3",
    "said": true,
    "authorKind": "person",
    "author": "Mia",
    "text": "",
    "attachments": [
      {
        "name": "photo.jpg",
        "path": "uploads/fx/photo.jpg",
        "size": 4096,
        "width": 300,
        "height": 200,
        "thumbhash": "1QcSHQRnh493V4dIh4eXh1h4kJUI",
      },
    ],
  })
  let t = @ui.Tester::new(
    fn(c) {
      let here : @sfpages.MessageHere = {
        station: "ws1/st1",
        session: "s-c1",
        view: chat_view_made(Json::object({})),
        go: None,
        inline: true,
        gutter: 0.0,
        list: None,
        core: None,
      }
      @sfpages.message_row(c, src, here, m)
    },
    w=760.0,
    h=600.0,
    platform=0,
    images=[("pic", 600, 400)],
  )
  t.draw()
  assert_eq(t.drawn_glass().length(), 0, msg="the soft colours need no extra blur while waiting")
  t.frame()
  let waiting = t.drawlist_images()[0].2
  // here, not decoded yet; then decoded: the waiting picture stays the same above the arriving image's frost
  key.val = "pic"
  t.frame()
  assert_eq(t.drawlist_images()[0].2, waiting, msg="the waiting picture changed as the file arrived")
  t.frame()
  assert_eq(t.drawlist_images()[0].2, waiting, msg="the waiting picture changed as it was decoded")
  assert_eq(t.drawn_glass().length(), 1, msg="the arriving picture is frosted")
  assert_eq(t.drawn_glass_contained(), [true])
  let order = t.drawn_order()
  let mut glass = -1
  let mut image = -1
  for i, item in order {
    if item.0 == 5 { glass = i }
    if item.0 == 4 { image = i }
  }
  assert_true(glass >= 0 && image > glass, msg="the waiting picture is drawn over the frost")
  // in: as it is, nothing over it
  t.run_for(@sfpages.reveal_ms + 1.0)
  assert_eq(t.drawn_glass().length(), 0)
}

///|
fn waiting_picture_pixels(hash : String) -> (Int, Int, FixedArray[Byte]) raise {
  reset()
  let src : Source = { ..fixture("chat"), file: fn(_, _, _) { "" } }
  let m = message_of({
    "seq": 3, "ts": "3", "authorKind": "person", "author": "Mia", "text": "",
    "attachments": [{
      "name": "wide.png", "path": "uploads/fx/wide.png", "size": 23121,
      "width": 1200, "height": 200, "thumbhash": Json::string(hash),
    }],
  })
  let t = @ui.Tester::new(fn(c) {
    let here : @sfpages.MessageHere = {
      station: "ws1/st1", session: "s-c1", view: chat_view_made(Json::object({})),
      go: None, inline: true, gutter: 0.0, list: None, core: None,
    }
    @sfpages.message_row(c, src, here, m)
  }, w=760.0, h=600.0, platform=0)
  t.draw()
  t.frame()
  let pictures = t.drawlist_images()
  guard pictures.length() > 0 else { fail("the waiting picture was not drawn") }
  guard @pixels.decode_png(pictures[0].2) is Some((w, h, rgba)) else { fail("the waiting picture was not a PNG") }
  (w, h, rgba)
}

///|
test "a short line in a wide screenshot does not become a dark stripe while the picture is coming" {
  let (w, h, rgba) = waiting_picture_pixels("ehgGCYLIl2d5h/dHN4ZwYwg=")
  let channel = fn(y : Int) { rgba[(y * w + w / 2) * 4 + 1].to_int() }
  let (top, middle, bottom) = (channel(0), channel(h / 2), channel(h - 1))
  assert_true((2 * middle - top - bottom).abs() < 16, msg="an isolated dark band: \{top}, \{middle}, \{bottom}")
}

///|
test "an image with transparent parts remains partly transparent while it comes" {
  let (w, h, rgba) = waiting_picture_pixels("VxuDA4BY8sA/1GzjT4sBS3CKeId4d3g=")
  let mut low = 255
  let mut high = 0
  for i in 0..<(w * h) {
    let a = rgba[i * 4 + 3].to_int()
    if a < low { low = a }
    if a > high { high = a }
  }
  assert_true(low < 255 && high > 0, msg="the picture's transparency was lost: \{low}…\{high}")
}
