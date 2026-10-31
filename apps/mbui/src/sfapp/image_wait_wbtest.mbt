// A message's image while it waits (sfpages message_files.mbt image_item, image_reveal): its likeness already as
// blurred as its way in starts, so nothing about it changes as it is decoded but the edge brushing down (the user,
// 2026-10-31: 从 placeholder 切换到缩略图会先变模糊然后再出动效，建议直接 placeholder 就是模糊的).

///|
test "a message's image waiting is its likeness under the frost its way in starts with: the same frost from asked to decoded" {
  reset()
  // what its station has given of it so far: nothing ("": asked), then its picture
  let key = Ref("")
  let src : Source = { ..fixture("chat"), file: fn(_, _, _) { key.val } }
  let m = message_of({
    "seq": 3,
    "ts": "3",
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
  let frost = t.drawn_glass()
  assert_eq(frost.length(), 1, msg="its likeness frosted while asked: \{frost}")
  // here, not decoded yet; then decoded, its way in starting: the same frost over it
  key.val = "pic"
  t.frame()
  assert_eq(t.drawn_glass(), frost)
  t.frame()
  assert_eq(t.drawn_glass(), frost)
  // in: as it is, nothing over it
  t.run_for(@sfpages.reveal_ms + 1.0)
  assert_eq(t.drawn_glass().length(), 0)
}
