// A video or a song played as it streams (ember apps/android drive/Player.kt PlayerScreen) in still.fail's look: how
// it plays and what the fingers and the clock do with it are mbui's player (@kit.Media: the system's player in a native
// view, its bytes asked a part at a time of the `read` it is given, never fetched whole first); here, how it is drawn
// and what it says. Dark, as a viewer of pictures; its controls float over the picture and fade when left alone while
// it plays (a tap brings them back): the bar at the top (back, the name, which of the folder's it is), at the foot the
// time over where it is and how much is buffered (tapped or dragged along: the player goes there once let go), the one
// before, 15 s back, play, 15 s on, the one after, the speed, the subtitle beside it, fit or fill, sideways. A double
// tap on the left or right third jumps 15 s, in the middle it pauses or plays. A song has no picture: its mark and its
// name in the middle, its controls staying. Where it is goes to whoever keeps it (`position`, `duration`), and it opens
// at a place given (`open(start=)`).
//
// Not here, against Player.kt: the frosted glass (a native view under the bars cannot be blurred: a deeper solid tint),
// the subtitle's shadow (a dark ground under its words only), what was played kept on the device to play again from it
// (DriveCache's played: every play reads through `read` again).

///|
/// Its words (client/i18n/catalog/zh android-misc.json, android-chat.json, common.json).
let words : Map[String, String] = {
  "android-misc.drive.player.buffering": "正在缓冲",
  "android-misc.drive.player.failed": "播放失败",
  "android-misc.drive.player.retry": "重试",
  "android-misc.drive.player.ended": "播放结束",
  "android-misc.drive.player.nextOne": "下一个：{name}",
  "android-misc.drive.player.back": "快退 {n} 秒",
  "android-misc.drive.player.ahead": "快进 {n} 秒",
  "android-misc.drive.player.paused": "已暂停",
  "android-misc.drive.player.playing": "继续播放",
  "android-chat.video.playFailed": "播放失败",
  "common.opening": "正在打开",
  // what its keys say to a screen reader (Player.kt Key, SpeedKey)
  "common.back": "返回",
  "android-misc.drive.player.prev": "上一个",
  "android-misc.drive.player.next": "下一个",
  "android-misc.drive.player.back15": "后退 15 秒",
  "android-misc.drive.player.forward15": "前进 15 秒",
  "android-chat.video.play": "播放",
  "android-chat.video.pause": "暂停",
  "android-misc.drive.player.speed": "播放速度",
  "android-misc.drive.player.subtitlesOn": "显示字幕",
  "android-misc.drive.player.subtitlesOff": "隐藏字幕",
  "android-misc.drive.player.fill": "铺满",
  "android-misc.drive.player.fit": "适应",
  "android-misc.drive.player.full": "全屏",
  "android-misc.drive.player.unfull": "退出全屏",
}

///|
/// The words for `key`, `{name}`s put in from `args`.
pub fn word(key : String, args? : Array[(String, String)] = []) -> String {
  let mut s = words.get(key).unwrap_or(key)
  for a in args {
    s = s.replace_all(old="{" + a.0 + "}", new=a.1)
  }
  s
}

///|
/// Dark whatever the theme, as a viewer of pictures: its text, what is quieter.
let ink : Int64 = 0xF4F4F5FFL

///|
let muted : Int64 = 0xFFFFFF99L

///|
/// A player for a page (`key` keeps its widgets apart from another's), with Player.kt's ways (@kit.Media's own): its
/// waits said once they have waited the app's later_ms.
pub fn player(key? : String = "player") -> @kit.Media {
  @kit.Media::new(key~, wait_ms=@sf.later_ms)
}

///|
/// The player over the whole page: the picture (or a song's mark), what is said over it, its bars. `list`: the
/// folder's playable names in order (empty: it alone), the one playing among them; `top` and `foot` how far the system
/// bars reach in over the page (its bars kept off them); `on_back` leaves, `on_open(name)` plays another of them.
pub fn view(
  p : @kit.Media,
  c : @ui.Ctx,
  list? : Array[String] = [],
  top? : Double = 0.0,
  foot? : Double = 0.0,
  on_back : () -> Unit,
  on_open : (String) -> Unit,
) -> Unit {
  let f = p.frame(c)
  let s = f.status
  let phase = f.phase
  let audio = f.audio
  let waited = f.waited
  let shown = f.shown
  let on = f.on
  let name = match p.track() {
    Some(t) => t.name
    None => ""
  }
  let index = list.search(name).unwrap_or(-1)
  let next = next_in(name, list)
  let prev = if index > 0 { list.get(index - 1) } else { None }
  let glass = if audio { 0x1212149EL } else { 0x121214D9L }
  c.box(w=Fill(1.0), h=Fill(1.0), bg=0x000000FFL, fn() {
    // the picture, fitted in the page or filling it (cropped), in the middle; a stage taking the taps
    let stage = c.id(p.key() + "/stage")
    p.stage(c, stage, c.width)
    c.box(w=Fill(1.0), h=Fill(1.0), id=stage, fn() {
      match p.native() {
        Some(n) if n.here() => c.native(n, content=Some(p.picture_rect(s, c.width, c.height))) |> ignore
        _ => ()
      }
    })
    |> ignore
    if audio {
      c.layer(align=ACenter, fn() {
        c.box(w=Fill(1.0), h=Fill(1.0), pad=32.0, gap=12.0, align=ACenter, justify=JCenter, fn() {
          @sf.icon(c, "file-audio", size=56.0, color=muted) |> ignore
          c.text(name, size=16.0, color=ink, center=true, w=Fill(1.0)) |> ignore
        })
        |> ignore
      })
      |> ignore
    }
    // the subtitle's words, over the foot (higher while the controls show)
    let said = f.said
    if said != "" {
      c.layer(fn() {
        c.box(
          w=Fill(1.0),
          h=Fill(1.0),
          padx=24.0,
          pb=if shown > 0.5 { 132.0 } else { 28.0 },
          align=ACenter,
          justify=JEnd,
          fn() {
            c.box(bg=0x00000059L, radius=6.0, padx=8.0, pady=2.0, fn() {
              c.text(
                said,
                size=if p.is_sideways() { 20.0 } else { 16.0 },
                line=if p.is_sideways() { 26.0 } else { 22.0 },
                color=0xFFFFFFFFL,
                center=true,
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
    // what it waits on, why it failed, what comes next
    c.layer(fn() {
      c.box(style=centred, fn() {
        match phase {
          Opening | Buffering =>
            if waited {
              c.box(dir=Row, padx=12.0, pady=6.0, gap=8.0, radius=15.0, bg=glass, align=ACenter, fn() {
                @sf.spinner(c, size=12.0) |> ignore
                c.text(
                  if phase == Opening {
                    word("common.opening")
                  } else {
                    word("android-misc.drive.player.buffering")
                  },
                  size=13.0,
                  line=18.0,
                  color=ink,
                  wrap=false,
                )
                |> ignore
              })
              |> ignore
            }
          Failed => {
            c.box(pad=32.0, gap=12.0, align=ACenter, fn() {
              c.text(word("android-misc.drive.player.failed"), size=15.0, weight=600, color=ink, wrap=false)
              |> ignore
              if chip(c, p.key() + "/retry", word("android-misc.drive.player.retry")) {
                p.retry()
              }
            })
            |> ignore
          }
          Ended => {
            match next {
              Some(other) =>
                c.box(gap=12.0, align=ACenter, fn() {
                  c.text(word("android-misc.drive.player.ended"), size=14.0, color=muted, wrap=false)
                  |> ignore
                  if chip(c, p.key() + "/next-one", word("android-misc.drive.player.nextOne", args=[("name", other)])) {
                    p.pause()
                    on_open(other)
                  }
                })
                |> ignore
              None => ()
            }
          }
          _ => ()
        }
      })
      |> ignore
    })
    |> ignore
    match f.note {
      Some(note) =>
        c.layer(fn() {
          c.box(w=Fill(1.0), h=Fill(1.0), pb=120.0, align=ACenter, justify=JCenter, fn() {
            c.box(bg=0x0000008CL, radius=12.0, padx=16.0, pady=9.0, fn() {
              c.text(note_words(note), size=14.0, color=ink, wrap=false) |> ignore
            })
            |> ignore
          })
          |> ignore
        })
        |> ignore
      None => ()
    }
    // the bar at the top: back, the name, which of the folder's it is
    c.layer(fn() {
      // under the status bar, `top` (Player.kt: windowInsetsPadding(statusBars), then 6)
      if top > 0.0 {
        c.box(style=@ui.style(w=Full, h=Fixed(top)), fn() {  }) |> ignore
      }
      c.box(w=Fill(1.0), padx=8.0, pady=6.0, opacity=shown, fn() {
        c.box(dir=Row, w=Fill(1.0), h=Px(48.0), radius=16.0, bg=glass, pl=4.0, pr=14.0, align=ACenter, fn() {
          if key_button(c, p.key() + "/back", "chevron-left", on, said=word("common.back")) {
            if p.is_sideways() {
              p.upright()
            } else {
              on_back()
            }
          }
          let room = c.width - 16.0 - 18.0 - 40.0 - (if list.length() > 1 { 56.0 } else { 0.0 })
          c.box(padx=4.0, max_w=if room > 40.0 { room } else { 40.0 }, clip=true, fn() {
            c.text(name, size=15.0, weight=600, color=ink, wrap=false) |> ignore
          })
          |> ignore
          if list.length() > 1 && index >= 0 {
            c.box(pl=4.0, fn() {
              c.text("\{index + 1} / \{list.length()}", size=12.0, color=muted, wrap=false) |> ignore
            })
            |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
    // the controls at the foot
    c.layer(fn() {
      c.spacer()
      // over the navigation bar, `foot` (Player.kt: windowInsetsPadding(navigationBars), then 8)
      c.box(w=Fill(1.0), padx=8.0, pady=8.0, align=ACenter, opacity=shown, fn() {
        controls(p, c, s, phase, audio, on, glass, list, prev, next, on_open)
      })
      |> ignore
      if foot > 0.0 {
        c.box(style=@ui.style(w=Full, h=Fixed(foot)), fn() {  }) |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// What a double tap did, said a moment: 快退 15 秒, 快进 15 秒, 已暂停, 继续播放.
fn note_words(note : @kit.MediaNote) -> String {
  match note {
    Back(ms) => word("android-misc.drive.player.back", args=[("n", (ms / 1000.0).to_int().to_string())])
    Ahead(ms) => word("android-misc.drive.player.ahead", args=[("n", (ms / 1000.0).to_int().to_string())])
    Paused => word("android-misc.drive.player.paused")
    Played => word("android-misc.drive.player.playing")
  }
}

///|
/// The controls (Player.kt's foot): the time over the timeline; the one before, 15 s back, play, 15 s on, the one
/// after; the speed, the subtitle, fit or fill, sideways. A finger down anywhere on them keeps them a while.
fn controls(
  p : @kit.Media,
  c : @ui.Ctx,
  s : @kit.MediaStatus,
  phase : @kit.MediaPhase,
  audio : Bool,
  on : Bool,
  glass : Int64,
  list : Array[String],
  prev : String?,
  next : String?,
  on_open : (String) -> Unit,
) -> Unit {
  let id = c.id(p.key() + "/controls")
  p.keep_awake(c, id)
  c.box(w=Fill(1.0), max_w=720.0, radius=bar_radius, bg=glass, pl=bar_side, pr=bar_side, pt=8.0, pb=bar_foot, id~, fn() {
    let at = p.scrubbing().unwrap_or(s.position)
    c.box(pl=10.0, fn() {
      c.rich(
        [
          @ui.span(clock(at), color=ink, weight=600),
          @ui.span(" / " + (if s.duration > 0.0 { clock(s.duration) } else { "--:--" })),
        ],
        size=12.0,
        color=muted,
        wrap=false,
      )
      |> ignore
    })
    |> ignore
    timeline(p, c, s, on)
    // the speed last on the row (the audio's, no subtitle): in the bar's bottom right corner, as far from its right
    // edge as from its foot (docs/ui-panels.md; Android's SpeedKey, Player.kt:505, sits 6 from the right and 11 from
    // the foot: it keeps no such rule here)
    let (subtitle, subs_on) = p.subtitle()
    let speed_last = audio && !subtitle
    let speed_inset = bar_foot + (key_size - speed_h) / 2.0
    c.box(style=keys_row, pr?=if speed_last { Some(speed_inset - bar_side) } else { None }, fn() {
      if list.length() > 1 &&
        key_button(c, p.key() + "/prev", "skip-back", on && prev is Some(_), said=word("android-misc.drive.player.prev")) {
        match prev {
          Some(other) => {
            p.pause()
            on_open(other)
          }
          None => ()
        }
      }
      if key_button(c, p.key() + "/back15", "back-15", on, said=word("android-misc.drive.player.back15")) {
        p.seek_by(-p.nudge_ms())
        p.wake()
      }
      let playing = phase == Playing || phase == Buffering
      if key_button(c, p.key() + "/play", if playing { "pause" } else { "play" }, on, said=word(if playing { "android-chat.video.pause" } else { "android-chat.video.play" })) {
        p.play_pause()
        p.wake()
      }
      if key_button(c, p.key() + "/forward15", "forward-15", on, said=word("android-misc.drive.player.forward15")) {
        p.seek_by(p.nudge_ms())
        p.wake()
      }
      if list.length() > 1 &&
        key_button(c, p.key() + "/next", "skip-forward", on && next is Some(_), said=word("android-misc.drive.player.next")) {
        match next {
          Some(other) => {
            p.pause()
            on_open(other)
          }
          None => ()
        }
      }
      c.spacer()
      // the speed, as a figure: a tap goes to the next (1×, 1.25×, 1.5×, 2×, 0.5×, 0.75×)
      let sid = c.id(p.key() + "/speed")
      if on && c.clicked(sid) {
        p.step_speed()
        p.wake()
      }
      // Android's SpeedKey (Player.kt:505): 30 high, 44 at least; in the corner concentric with the bar, else Smooth(10)
      let speed_key = c.box(
        h=Px(speed_h),
        min_w=44.0,
        radius=if speed_last { @sf.inner_corner(bar_radius, speed_inset) } else { speed_corner },
        padx=8.0,
        bg=if p.speed() != 1.0 { 0xFFFFFF24L } else { 0xFFFFFF0FL },
        align=ACenter,
        justify=JCenter,
        id=if on { sid } else { 0 },
        fn() {
          c.text(speed_label(p.speed()), size=12.0, weight=600, color=ink, wrap=false) |> ignore
          // Player.kt SpeedKey: clickable over its clip
          if on {
            @motion.ripple(c, sid, if speed_last { @sf.inner_corner(bar_radius, speed_inset) } else { speed_corner })
          }
        },
      )
      c.semantics(speed_key, Button, id=sid, label=word("android-misc.drive.player.speed"), disabled=!on)
      if subtitle &&
        key_button(c, p.key() + "/captions", "captions", on, lit=subs_on, said=word(if subs_on { "android-misc.drive.player.subtitlesOff" } else { "android-misc.drive.player.subtitlesOn" })) {
        p.toggle_subtitle()
        p.wake()
      }
      // turned sideways the picture can fill the screen (cropped) or fit in it
      if !audio &&
        p.is_sideways() &&
        key_button(c, p.key() + "/fill", if p.fills() { "shrink" } else { "expand" }, on, lit=p.fills(), said=word(if p.fills() { "android-misc.drive.player.fit" } else { "android-misc.drive.player.fill" })) {
        p.toggle_fill()
        p.wake()
      }
      if !audio &&
        key_button(c, p.key() + "/sideways", "landscape", on, lit=p.is_sideways(), said=word(if p.is_sideways() { "android-misc.drive.player.unfull" } else { "android-misc.drive.player.full" })) {
        p.toggle_sideways()
        p.wake()
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// Where it is, to tap or drag to a place: a thin track, what is buffered lighter on it, what has played, a round head.
/// The time follows the finger while it drags; the player is sent there once it is let go.
fn timeline(p : @kit.Media, c : @ui.Ctx, s : @kit.MediaStatus, on : Bool) -> Unit {
  let id = c.id(p.key() + "/timeline")
  let dur = s.duration
  p.timeline(c, id, on)
  let part = fn(ms : Double) {
    if dur <= 0.0 {
      0.0
    } else {
      let k = ms / dur
      if k < 0.0 {
        0.0
      } else if k > 1.0 {
        1.0
      } else {
        k
      }
    }
  }
  let scrub = p.scrubbing()
  let dragging = scrub is Some(_)
  let th = if dragging { 4.0 } else { 3.0 }
  let r = if dragging { 8.0 } else { 6.0 }
  let shown = part(scrub.unwrap_or(s.position))
  c.box(w=Fill(1.0), padx=10.0, fn() {
    c.box(w=Fill(1.0), h=Px(26.0), justify=JCenter, id=if on { id } else { 0 }, fn() {
      c.box(w=Fill(1.0), h=Px(th), radius=th / 2.0, bg=0xFFFFFF33L, fn() {  }) |> ignore
      share_bar(c, part(s.buffered), th, 0xFFFFFF59L)
      share_bar(c, shown, th, ink)
      // the head
      c.layer(fn() {
        c.box(style=filled_row, fn() {
          if shown > 0.0 {
            c.box(w=Fill(shown), fn() {  }) |> ignore
          }
          // no room of its own: centred on where it is, at the end as at the start
          c.box(w=Px(0.0), h=Px(r * 2.0), fn() {
            c.box(w=Px(r * 2.0), h=Px(r * 2.0), radius=r, bg=ink, tx=-r, fn() {  }) |> ignore
          })
          |> ignore
          if shown < 1.0 {
            c.box(w=Fill(1.0 - shown), fn() {  }) |> ignore
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
/// `part` of the track from its start, `h` high, in `color`, over what is under it.
fn share_bar(c : @ui.Ctx, part : Double, h : Double, color : Int64) -> Unit {
  if part <= 0.0 {
    return
  }
  c.layer(fn() {
    c.box(style=filled_row, fn() {
      c.box(w=Fill(part), h=Px(h), radius=h / 2.0, bg=color, fn() {  }) |> ignore
      if part < 1.0 {
        c.box(w=Fill(1.0 - part), fn() {  }) |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// What fills the stage, in its middle (what it waits on, why it failed, what comes next).
// kept across runs: a value (no field of it changes)
let centred : @ui.Style = @ui.style(w=Full, h=Full, align=ACenter, justify=JCenter)

///|
/// The controls' keys, a row across the bar.
// kept across runs: a value (no field of it changes)
let keys_row : @ui.Style = @ui.style(row=true, w=Full, align=ACenter)

///|
/// A row filling its place, what it holds in its middle (a track, a filled part over it).
// kept across runs: a value (no field of it changes)
let filled_row : @ui.Style = @ui.style(row=true, w=Full, h=Full, align=ACenter)

///|
/// The controls' bar (Player.kt:401, 403): its corner (Smooth(26)), its sides' and its foot's room; a key's size, the
/// speed's height.
let bar_radius : Double = 26.0

///|
let bar_side : Double = 6.0

///|
let bar_foot : Double = 6.0

///|
let key_size : Double = 40.0

///|
let speed_h : Double = 30.0

///|
/// The speed key's corner away from the bar's (Player.kt SpeedKey: Smooth(10)).
let speed_corner : Double = 10.0

///|
/// A round key on the controls (Player.kt Key): 40, a 20 icon; `lit`, a soft light behind it while what it turns on is
/// on. True on the frame it was tapped; `on` false, it takes no tap (what is under it does).
fn key_button(c : @ui.Ctx, key : String, icon : String, on : Bool, lit? : Bool = false, said~ : String) -> Bool {
  let id = c.id(key)
  let b = c.box(
    w=Px(key_size),
    h=Px(key_size),
    radius=key_size / 2.0,
    align=ACenter,
    justify=JCenter,
    bg=if lit { 0xFFFFFF24L } else { 0L },
    id=if on { id } else { 0 },
    fn() {
      @sf.icon(c, icon, size=20.0, color=ink) |> ignore
      // Player.kt Key: clip(CircleShape).clickable
      if on {
        @motion.ripple(c, id, key_size / 2.0)
      }
    },
  )
  // named `said` (Player.kt Key's contentDescription), pressed while `lit`
  c.semantics(b, Button, id~, label=said, disabled=!on, pressed=lit)
  on && c.clicked(id)
}

///|
/// A choice over the picture (Player.kt Chip): its words on white at 14%, round 12.
fn chip(c : @ui.Ctx, key : String, label : String) -> Bool {
  let id = c.id(key)
  c.box(
    max_w=280.0,
    radius=12.0,
    bg=@sf.alpha(0xFFFFFFFFL, 0.14),
    padx=16.0,
    pady=9.0,
    clip=true,
    id~,
    fn() {
      c.text(label, size=14.0, color=ink, wrap=false) |> ignore
      // Player.kt Chip: clip(Smooth(12)).clickable
      @motion.ripple(c, id, 12.0)
    },
  )
  |> ignore
  c.clicked(id)
}
