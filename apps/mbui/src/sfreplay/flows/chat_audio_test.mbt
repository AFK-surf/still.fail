// 46-chat-audio (e2e/traces/chat-audio.trace: Mini1 against the local still.fail, 54 messages): a song sent in a chat
// by alice's other device (peer createfiles), opened from its card: the preview's small player (AudioViewer), its name,
// play; the system's player reads the song through the core a part at a time (station.file.part, each part as it
// comes, as the run's AVPlayer asked: its trace's read lines), and plays on (2 s in: 0:02). Back closes it.

///|
/// The native view the preview opened last (the fake host's `open ID KIND …`).
fn opened_view(f : @sfreplay.Flow) -> Int {
  let mut id = -1
  for line in f.t.views() {
    if line.has_prefix("open ") {
      match line.split(" ").to_array() {
        [_, n, ..] => {
          let mut v = 0
          for ch in n.to_string() {
            v = v * 10 + (ch.to_int() - '0'.to_int())
          }
          id = v
        }
        _ => ()
      }
    }
  }
  id
}

///|
test "46-chat-audio" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("chat-audio"), seed~)
    f.see("端到端测试")
    // (alice's other device sends the song: a live run's step beside the app)
    f.peer("peer createfiles 一段录音 104339 post:收到录音 104339 -- e2e-tune.m4a")
    f.see("一段录音 104339")
    // (its chat to the top of the list as the recording comes, there where it goes: tapped once its room is open,
    // where it shows, docs/list-motion.md)
    f.run_for(@ui.row_size_ms)
    f.tap("一段录音 104339")
    f.run_to(@ui.nav_rest())
    f.see("e2e-tune")
    f.tap("e2e-tune")
    f.run_to(@sfapp.preview_rest())
    let v = opened_view(f)
    assert_true(v > 0)
    // the system's player reads the song as the run's asked (the trace's read lines)
    player_opened(f, v)
    // ready and playing as the Mac's player said (the trace's info lines, Replay::host), 2 s in
    f.t.draw()
    f.see("0:02 /")
    read_whole(f, v, 177424)
    f.back()
    f.run_to(@sfapp.preview_rest())
    f.end()
  })
}
