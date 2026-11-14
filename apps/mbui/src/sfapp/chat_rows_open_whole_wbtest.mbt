// A chat's page opens whole with what its rows read of their own (the owner's, 2026-11-14: data arriving late is no
// cause of motion, and what the reader has before their eyes does not move), as chat_opens_whole_wbtest holds it for a
// login's card: each part of the chat's list whose room hangs on an answer of its own is asked with the chat and
// waited for with it (sfbase's chat_opens), so from the frame its messages are drawn the list is as it is at rest.
//
// Each such part in a chat (a fixture mode holding it), opened by its row (大屏 the sidebar's, from another chat; 小屏
// Home's, back to it from another chat), on the page the app ships and the page made as nodes, over a core answering
// 400 ms late: drawn in at most two ways from the press to rest, nothing drawn moving (that file's judge, ow_watch).
// - chat-screens: links to a station's screens and its web service, each its card (`screenCard`, `job`): a screen
//   its station previews is the screen across the card's top, one it does not a capsule a row high. Before, the
//   cards came a lateness after the rows, the list over them up 185 in one frame (old page, 大屏), and the page made
//   as nodes drew them unnamed meanwhile.

///|
fn init {
  @ui.host_image_bytes_known([("src/sfapp/chat_rows_open_whole_wbtest.mbt", 4000000)])
}

///|
/// Chat s-c1 in fixture mode `mode` opened by its row on screen `s` from s-c2, over a core 400 ms late.
fn rw_opened(mode : String, s : (String, Double, Double, Int), nodes : Bool) -> Array[String] raise {
  let t = ow_app(s, nodes, 400.0, ow_c2, mode~)
  if s.3 == 2 {
    t.back()
    ow_run(t, 1000.0)
  }
  let missing : Ref[Error?] = Ref(None)
  let said = ow_watch(t, s, "\{mode} \{ow_name(nodes)} \{s.0}", fn() {
    ow_open_by_hand(t, s, ow_c1) catch {
      e => missing.val = Some(e)
    }
  }, 1800.0)
  if missing.val is Some(e) {
    raise e
  }
  said
}

///|
fn rw_case(mode : String) -> Unit raise {
  let all = []
  for nodes in [false, true] {
    for s in ow_screens {
      all.push_iter(rw_opened(mode, s, nodes).iter())
    }
  }
  if all.length() > 0 {
    fail(all.join("\n"))
  }
}

///|
test "a chat opens whole with its screens' and service's cards, on both pages, 大屏 and 小屏, over a core 400 ms late: drawn in two ways at most, nothing drawn moving" {
  rw_case("chat-screens")
}
