// 97-video-frames (e2e/traces/video-frames.trace): a video's frames (the library's player, @sf.player_view): alice's
// other device sends a clip; opened, it plays, its frames' times read from the file (the host's player: 4 s at 30 a
// second, 120 frames); paused, which frame of how many, and its ±15 s become ‹ and ›: to the one before and the very
// next, each as the player says it is there; 保存此帧: the frame showing grabbed by the host and kept in the
// phone's photo album, a PNG at the video's own size, named by the frame it is.

///|
test "97-video-frames" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("video-frames"), seed~, env=[("MBUI_VIEWER_AWAKE", "1")])
    f.see("端到端测试")
    f.peer("peer createfiles 一段视频 201493 post:收到视频 201493 -- e2e-clip.mp4")
    f.see("一段视频 201493")
    // (its chat to the top of the list as the video comes, there where it goes: tapped once its room is open)
    f.run_for(@ui.row_size_ms)
    f.tap("一段视频 201493")
    f.run_for(@ui.move_most_ms)
    f.see("=studio")
    f.see("e2e-clip.mp4")
    f.tap("e2e-clip.mp4")
    // flown open, its bars on once it is in (preview.mbt: the viewer's way in)
    f.run_to(@sfapp.preview_rest())
    // the system's player reads it through the core, then says its frames' times
    let v = opened_view(f)
    player_opened(f, v)
    player_told(f)
    f.see("/ 0:04")
    read_whole(f, v, 423168)
    // paused, as the player says (its button 播放 again): the frame showing of how many
    f.tap("icon:pause")
    player_told(f)
    f.see("icon:play")
    f.see("/ 120 帧")
    // ‹ to the frame before the one showing; again; › the very next: each shown as the player says it is there
    f.tap("icon:chevron-left")
    player_told(f)
    f.tap("icon:chevron-left")
    player_told(f)
    f.tap("icon:chevron-right")
    player_told(f)
    // 保存此帧 takes the frame of a player paused and ready (player.mbt: the button there only then)
    f.see("icon:play")
    f.tap("icon:camera")
    // (a phone's: into its photo album, said so: keep_way_of)
    f.see("已保存到相册")
    // kept: the grabbed frame, a PNG of the video's size (640 × 360), named by its frame
    let kept = f.t.kept().filter(fn(k) { k.0.has_prefix("e2e-clip-") && k.0.has_suffix(".png") })
    f.check(kept.length() == 1, "kept: \{f.t.kept().map(fn(k) { k.0 })}")
    f.check(
      f.t.kept_ways().iter().any(fn(k) { k.0.has_prefix("e2e-clip-") && k.1.to_string() == "Photos" }),
      "kept: \{f.t.kept_ways()}",
    )
    if kept.length() == 1 {
      let b = kept[0].2
      let be32 = fn(i : Int) { (b[i].to_int() << 24) | (b[i + 1].to_int() << 16) | (b[i + 2].to_int() << 8) | b[i + 3].to_int() }
      f.check(b.length() > 24 && b[1] == b'P' && b[2] == b'N' && b[3] == b'G', "not a PNG")
      f.check(be32(16) == 640 && be32(20) == 360, "the frame kept \{be32(16)} × \{be32(20)}, not the video's 640 × 360")
    }
    f.end()
  })
}
