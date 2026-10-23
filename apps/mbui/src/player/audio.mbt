// A song shown small, in the page's colours (ember apps/android chat/screens/VideoViewer.kt AudioViewer, the chat's
// file preview): its name, and a capsule with play, where it is (tapped or dragged along), how long.

///|
/// The song `n` (a native player of src/ui/native.mbt, not placed: it has no picture) named `name`: its name, then the
/// capsule (54 high on the chip's ground): play or pause on the ink, the timeline, `m:ss / m:ss` (播放失败 when it
/// cannot be played). `key` keeps its widgets apart.
pub fn audio_strip(c : @ui.Ctx, key : String, n : @ui.NativeView, name : String, pinned? : @kit.MediaStatus? = None) -> Unit {
  let t = @sf.theme().p
  let s = match pinned {
    Some(s) => s
    None => @kit.media_status(Some(n))
  }
  let ready = s.state == 1
  let failed = s.state == -1
  c.box(w=Fill(1.0), max_w=480.0, padx=24.0, gap=14.0, align=ACenter, fn() {
    c.text(name, size=15.0, color=t.muted, wrap=false) |> ignore
    c.box(
      dir=Row,
      w=Fill(1.0),
      min_h=54.0,
      radius=27.0,
      bg=t.chip,
      padx=8.0,
      gap=6.0,
      align=ACenter,
      fn() {
        let play = c.id(key + "/play")
        if ready && c.clicked(play) {
          if s.playing {
            n.pause()
          } else {
            n.play()
          }
        }
        c.box(
          w=Px(38.0),
          h=Px(38.0),
          radius=19.0,
          bg=t.text,
          align=ACenter,
          justify=JCenter,
          id=if ready { play } else { 0 },
          fn() {
            @sf.icon(c, if s.playing { "pause" } else { "play" }, size=16.0, color=t.bg) |> ignore
            // VideoViewer.kt: clip(CircleShape).clickable(enabled = ready)
            if ready {
              @motion.ripple(c, play, 19.0)
            }
          },
        )
        |> ignore
        c.box(w=Fill(1.0), fn() { light_timeline(c, key, n, s, ready) }) |> ignore
        c.box(pr=10.0, fn() {
          c.rich(
            [
              @ui.span(
                if failed {
                  word("android-chat.video.playFailed")
                } else {
                  short_clock(s.position) + " / " + short_clock(if s.duration > 0.0 { s.duration } else { 0.0 })
                },
                mono=!failed,
              ),
            ],
            size=12.0,
            color=t.muted,
            wrap=false,
          )
          |> ignore
        })
        |> ignore
      },
    )
    |> ignore
  })
  |> ignore
}

///|
/// Where in the song it is (VideoViewer.kt Timeline, light): a 4 high track of the ink at 12%, what has played and a
/// round head in the accent; tapped or dragged along, it goes there as the finger does.
fn light_timeline(c : @ui.Ctx, key : String, n : @ui.NativeView, s : @kit.MediaStatus, ready : Bool) -> Unit {
  let t = @sf.theme().p
  let id = c.id(key + "/timeline")
  let dur = s.duration
  match c.rect_of(id) {
    Some((x, _, w, _)) if ready && dur > 0.0 && c.pressed(id) => {
      let (px, _, _) = c.pointer()
      let k = (px - x) / (if w < 1.0 { 1.0 } else { w })
      let to = (if k < 0.0 { 0.0 } else if k > 1.0 { 1.0 } else { k }) * dur
      // (once the frame's builds are over: where the finger is on the track as the last laid it out)
      c.after_build(key + "/seek", fn() { n.seek(to) })
    }
    _ => ()
  }
  let part = if dur > 0.0 {
    let k = s.position / dur
    if k < 0.0 {
      0.0
    } else if k > 1.0 {
      1.0
    } else {
      k
    }
  } else {
    0.0
  }
  c.box(w=Fill(1.0), padx=6.0, fn() {
    c.box(w=Fill(1.0), h=Px(22.0), justify=JCenter, id~, fn() {
      c.box(w=Fill(1.0), h=Px(4.0), radius=2.0, bg=@sf.alpha(t.text, 0.12), fn() {  }) |> ignore
      share_bar(c, part, 4.0, t.accent)
      c.layer(fn() {
        c.box(dir=Row, w=Fill(1.0), h=Fill(1.0), align=ACenter, fn() {
          if part > 0.0 {
            c.box(w=Fill(part), fn() {  }) |> ignore
          }
          c.box(w=Px(0.0), h=Px(12.0), fn() {
            c.box(w=Px(12.0), h=Px(12.0), radius=6.0, bg=t.accent, tx=-6.0, fn() {  }) |> ignore
          })
          |> ignore
          if part < 1.0 {
            c.box(w=Fill(1.0 - part), fn() {  }) |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// `m:ss`, the seconds cut (VideoViewer.kt short: the chat's audio).
pub fn short_clock(ms : Double) -> String {
  let t = (if ms < 0.0 { 0.0 } else { ms }).to_int64()
  "\{t / 60000L}:\{two(t / 1000L % 60L)}"
}

///|
fn two(n : Int64) -> String {
  if n < 10L {
    "0\{n}"
  } else {
    "\{n}"
  }
}
