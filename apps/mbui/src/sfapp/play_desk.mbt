// A film or a song played on a desktop (ember @stillfail/ui viewer/Player.tsx with a mouse, Player.css.ts `desk`): over
// the wide frame's whole window, on the page's canvas, in the theme's colours. The bar every file opened has
// (viewer_bar.mbt) along its top: back to the folder by name, the file's name, which of the folder's and its size, 选集
// where there are others, 下载; gone with the controls as it plays on. The picture fitted in the window (a song: its mark
// and its name in the middle). The controls float over its foot on the raised ground (a native view under them cannot
// be blurred: solid), as wide as 1080 allows less 16 either side: where it is along the timeline (what has come lighter
// on it), then the one before, 15 s back, play, 15 s on, the one after, the time, the speed, the subtitle beside it. They
// fade once the pointer rests while it plays and come back as it moves; a click on the picture plays or pauses, ← and →
// jump 15 s, Space plays or pauses. 选集 docks the folder's others at the right under the bar, 320 wide, the picture
// and the controls kept clear of it. How it plays is mbui's player's (@kit.Media).
//
// A chat's song opened in its preview plays here too (preview.mbt: read through the core a part at a time), as the
// web's FilePreview hands it to the same player.

///|
/// What opened a desktop's player tells it: back (by name, and going), the file's name and size, how it is saved, the
/// folder's others it steps through (in order, the one playing among them) and how another is opened.
priv struct DeskPlaying {
  back : String
  name : String
  size : Double
  go_back : () -> Unit
  save : () -> Unit
  list : Array[String]
  open : (String) -> Unit
}

///|
/// Whether 选集 is open, by the player's key (each player's own).
let desk_listing : Map[String, Bool] = Map([])

///|
/// The player `p` over the whole window, as a desktop's (see the file's head).
fn desk_play(c : @ui.Ctx, p : @kit.Media, d : DeskPlaying) -> Unit {
  let f = p.frame(c)
  let s = f.status
  let t = @sf.theme().p
  let key = p.key()
  let name = d.name
  let index = d.list.search(name).unwrap_or(-1)
  let next = @player.next_in(name, d.list)
  let prev = if index > 0 { d.list.get(index - 1) } else { None }
  let many = d.list.length() > 1
  let listing = many && desk_listing.get(key).unwrap_or(false)
  let panel = if listing { desk_panel_w } else { desk_none }
  // the pointer's moves wake the controls, as a mouse's do (Player.tsx onPointerMove)
  let (px, py, _) = c.pointer()
  let moved = desk_moves.get(key)
  if moved is Some((x, y)) && (x != px || y != py) {
    p.wake()
  }
  desk_moves[key] = (px, py)
  // the keys: Space plays or pauses, ← → 15 s back or on, Esc back
  if c.key_pressed(@ui.key_space) {
    p.play_pause()
    p.wake()
  }
  if c.key_pressed(@ui.key_code_left) {
    p.seek_by(-p.nudge_ms())
    p.wake()
  }
  if c.key_pressed(@ui.key_code_right) {
    p.seek_by(p.nudge_ms())
    p.wake()
  }
  if c.key_pressed(@ui.key_escape) {
    if listing {
      desk_listing[key] = false
    } else {
      desk_leave(c, key, d.go_back)
    }
  }
  let ink = page_viewer_ink()
  c.box(style=desk_play_ground, fn() {
    // the picture, in the window less the list beside it; a click on it plays or pauses
    let stage = c.id(key + "/desk-stage")
    c.cursor(stage, Hand)
    if c.clicked(stage) {
      p.play_pause()
      p.wake()
    }
    c.box(style=desk_play_row, fn() {
      c.box(style=desk_grow_full, id=stage, fn() {
        let w = dmax(desk_none, c.width - panel)
        match p.native() {
          Some(n) if n.here() => c.native(n, content=Some(p.picture_rect(s, w, c.height))) |> ignore
          _ => ()
        }
        if f.audio {
          c.layer(fn() {
            c.box(style=desk_play_cover, fn() {
              @sf.icon(c, "file-audio", size=desk_cover_icon, color=t.muted) |> ignore
              c.text(name, style=desk_cover_name) |> ignore
            })
            |> ignore
          })
          |> ignore
        }
        // what it waits on, why it failed
        c.layer(fn() {
          c.box(style=desk_play_middle, fn() {
            match f.phase {
              Opening | Buffering =>
                if f.waited {
                  @sf.wait_pill(c, tr(if f.phase == Opening { "common.opening" } else { "web-pages.drive.player.buffering" }), key="desk-play")
                }
              Failed =>
                c.text(fill("web-pages.drive.player.failed", [("error", "")]), style=desk_facts_words) |> ignore
              _ => ()
            }
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
      c.box(style=@ui.style(w=Fixed(panel), h=Full), fn() {  }) |> ignore
    })
    |> ignore
    // a subtitle's lines over the picture's middle: above the controls while they show, lower once they fade
    if f.said != "" {
      c.layer(fn() {
        c.box(style=if f.shown > desk_half { desk_cue_up } else { desk_cue_down }, fn() {
          c.box(style=desk_cue_row, fn() {
            c.box(style=desk_grow_middle, fn() {
              c.box(style=desk_cue_box, fn() { c.text(f.said, style=desk_cue_words) |> ignore }) |> ignore
            })
            |> ignore
            c.box(style=@ui.style(w=Fixed(panel)), fn() {  }) |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    }
    // the bar along the top
    c.layer(fn() {
      let meta = dv_words([if many && index >= 0 { "\{index + 1} / \{d.list.length()}" } else { "" }, file_size(d.size)], " · ")
      if viewer_bar(c, key + "/bar", d.back, name, meta, !f.on && !listing, ink, fn() {
          if many && viewer_tool(c, key + "/list", "list", tr("web-pages.drive.player.list"), ink, on=listing) {
            desk_listing[key] = !listing
          }
          if viewer_download(c, key + "/download", ink) {
            (d.save)()
          }
        }) {
        desk_leave(c, key, d.go_back)
      }
    })
    |> ignore
    // 选集, docked at the right under the bar
    if listing {
      c.layer(fn() { desk_play_list(c, p, d, index, f.phase == Playing) }) |> ignore
    }
    // the controls over the foot
    c.layer(fn() {
      c.box(style=desk_controls_place, fn() {
        c.box(style=desk_play_row_end, fn() {
          c.box(style=desk_grow_middle, fn() {
            let most = dmin(desk_video_most, dmax(desk_none, c.width - panel - 2.0 * desk_video_in))
            let n = c.box(style=desk_controls_box.then(@ui.style(w=Fixed(most), bg=Data(@sf.over(t.canvas, @sf.alpha(t.raised, desk_video_share))))), id=c.id(key + "/desk-controls"), fn() {
              desk_play_controls(c, p, s, f, d, prev, next)
            })
            c.look(n, @ui.look(alpha=f.shown))
          })
          |> ignore
          c.box(style=@ui.style(w=Fixed(panel)), fn() {  }) |> ignore
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
/// Where the pointer was, by the player's key: its moves wake the controls.
let desk_moves : Map[String, (Double, Double)] = Map([])

///|
/// The players that made the window fill the screen, by key: back as it was when they are left.
let desk_fulled : Map[String, Bool] = Map([])

///|
/// Back from a player (`go_back`), the window as it was if the player made it fill the screen.
fn desk_leave(c : @ui.Ctx, key : String, go_back : () -> Unit) -> Unit {
  if desk_fulled.contains(key) {
    desk_fulled.remove(key)
    if @ui.full_screen() {
      c.set_full_screen(false)
    }
  }
  go_back()
}

///|
/// The controls (Player.tsx's vvBar): the timeline, then the steps and play, the time, the speed and the subtitle.
fn desk_play_controls(
  c : @ui.Ctx,
  p : @kit.Media,
  s : @kit.MediaStatus,
  f : @kit.MediaFrame,
  d : DeskPlaying,
  prev : String?,
  next : String?,
) -> Unit {
  let t = @sf.theme().p
  let key = p.key()
  let on = f.on
  let many = d.list.length() > 1
  desk_play_timeline(c, p, s, on)
  c.box(style=desk_controls_row, fn() {
    c.box(style=desk_controls_group, fn() {
      if many && desk_play_key(c, key + "/prev", "skip-back", tr("web-pages.drive.player.prev"), on && prev is Some(_), small=true) {
        match prev {
          Some(other) => {
            p.pause()
            (d.open)(other)
          }
          None => ()
        }
      }
      if desk_play_key(c, key + "/back15", "back-15", tr("web-pages.drive.player.back15"), on) {
        p.seek_by(-p.nudge_ms())
        p.wake()
      }
      let playing = f.phase == Playing || f.phase == Buffering
      if desk_play_key(c, key + "/play", if playing { "pause" } else { "play" }, tr(if playing { "web-main.video.pauseKey" } else { "web-main.video.playKey" }), on, bright=true) {
        p.play_pause()
        p.wake()
      }
      if desk_play_key(c, key + "/forward15", "forward-15", tr("web-pages.drive.player.forward15"), on) {
        p.seek_by(p.nudge_ms())
        p.wake()
      }
      if many && desk_play_key(c, key + "/next", "skip-forward", tr("web-pages.drive.player.next"), on && next is Some(_), small=true) {
        match next {
          Some(other) => {
            p.pause()
            (d.open)(other)
          }
          None => ()
        }
      }
    })
    |> ignore
    // the time: where it is (the timeline's drag while it is dragged), of how long
    let at = p.scrubbing().unwrap_or(s.position)
    c.box(style=desk_grow_clip, fn() {
      c.rich(
        [
          @ui.span(@player.clock(at), color=t.text, weight=desk_heading_weight, mono=true),
          @ui.span(" / " + (if s.duration > 0.0 { @player.clock(s.duration) } else { "--:--" }), color=t.muted, mono=true),
        ],
        style=desk_time_words,
      )
      |> ignore
    })
    |> ignore
    c.box(style=desk_controls_group, fn() {
      desk_volume(c, p, on)
      // the speed, as a figure: a click goes to the next (1×, 1.25×, 1.5×, 2×, 0.5×, 0.75×)
      let sid = c.id(key + "/speed")
      if on {
        c.cursor(sid, Hand)
      }
      if on && c.clicked(sid) {
        p.step_speed()
        p.wake()
      }
      let b = c.box(style=desk_rate_box.then(@ui.style(bg=Data(@sf.alpha(t.text, desk_rate_share)))), id=if on { sid } else { 0 }, fn() {
        c.rich([@ui.span(@player.speed_label(p.speed()), weight=desk_heading_weight, mono=true)], style=desk_rate_words) |> ignore
      })
      c.semantics(b, Button, id=sid, label=tr("web-pages.drive.player.rate"), disabled=!on)
      let (subtitle, subs_on) = p.subtitle()
      if subtitle &&
        desk_play_key(c, key + "/captions", "captions", tr(if subs_on { "web-pages.drive.player.captionsOff" } else { "web-pages.drive.player.captionsOn" }), on, small=true, lit=subs_on) {
        p.toggle_subtitle()
        p.wake()
      }
      // 全屏: the window filling the screen (macOS's), back as it was (and as the player is left)
      if !f.audio && @ui.platform() == 0 {
        let full = @ui.full_screen()
        if desk_play_key(c, key + "/full", if full { "shrink" } else { "expand" }, tr(if full { "web-pages.drive.player.unfull" } else { "web-pages.drive.player.full" }), on, small=true) {
          c.set_full_screen(!full)
          if full {
            desk_fulled.remove(key)
          } else {
            desk_fulled[key] = true
          }
          p.wake()
        }
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// The sound (Player.tsx VolumeControl): a button that mutes, and beside it a line 72 wide to press or drag along (in
/// twentieths), how loud on it in the words, a 10 head.
fn desk_volume(c : @ui.Ctx, p : @kit.Media, on : Bool) -> Unit {
  let t = @sf.theme().p
  let key = p.key()
  let (volume, muted) = p.volume()
  let silent = muted || volume == 0.0
  c.box(style=desk_volume_row, fn() {
    if desk_play_key(c, key + "/mute", if silent { "volume-x" } else { "volume" }, tr(if silent { "web-pages.drive.player.unmute" } else { "web-pages.drive.player.mute" }), on, small=true) {
      p.toggle_mute()
      p.wake()
    }
    let id = c.id(key + "/volume")
    if on {
      c.cursor(id, Hand)
    }
    // pressed along it: as loud as where (told the player once the frame's builds are over)
    match c.rect_of(id) {
      Some((x, _, w, _)) if on && c.pressed(id) => {
        let (px, _, _) = c.pointer()
        let to = (dmin(desk_whole, dmax(desk_none, (px - x) / dmax(desk_whole, w))) * desk_volume_steps).round() / desk_volume_steps
        c.after_build(key + "/volume", fn() {
          p.set_volume(to)
          p.wake()
        })
      }
      _ => ()
    }
    let shown = if muted { desk_none } else { volume }
    let b = c.box(style=desk_volume_line, id=if on { id } else { 0 }, fn() {
      c.box(style=desk_track.then(@ui.style(bg=Data(@sf.alpha(t.text, desk_track_share)))), fn() {
        c.layer(fn() { desk_share_bar(c, shown, t.text) }) |> ignore
      })
      |> ignore
      c.layer(fn() {
        c.box(style=desk_head_row, fn() {
          c.box(style=@ui.style(w=Grow(shown)), fn() {  }) |> ignore
          c.box(style=desk_volume_head_room, fn() {
            c.box(style=desk_volume_head.then(@ui.style(bg=Data(t.text))), tx=-desk_volume_head_r, fn() {  }) |> ignore
          })
          |> ignore
          c.box(style=@ui.style(w=Grow(desk_whole - shown)), fn() {  }) |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    c.semantics(b, Slider, id~, label=tr("web-pages.drive.player.volume"), range=(desk_none, desk_whole, shown))
  })
  |> ignore
}

///|
/// One of the controls' buttons (page.css.ts iconBtn in vvBar: 32, its corner the bar's less 6): a 20 icon (18
/// `small`), in the quieter ink until pointed at, play's (`bright`) in the words'; `lit` while what it turns on is.
fn desk_play_key(
  c : @ui.Ctx,
  key : String,
  icon : String,
  label : String,
  on : Bool,
  small? : Bool = false,
  bright? : Bool = false,
  lit? : Bool = false,
) -> Bool {
  let t = @sf.theme().p
  let id = c.id(key)
  if on {
    c.cursor(id, Hand)
  }
  let hot = on && (c.hovered(id) || c.pressed(id))
  let b = c.box(style=desk_play_key_box, selected=lit, disabled=!on, id=if on { id } else { 0 }, fn() {
    @sf.icon(c, icon, size=if small { viewer_tool_icon } else { viewer_back_icon }, color=if bright || hot || lit { t.text } else { t.muted })
    |> ignore
  })
  c.semantics(b, Button, id~, label~, disabled=!on, pressed=lit)
  if on {
    @kit.tooltip(c, key + "/tip", id, label) |> ignore
  }
  on && c.clicked(id)
}

///|
/// Where it is, to click or drag to a place (Player.tsx Timeline): a 4 high track on the words at 20%, what has come
/// at 22% over it, what has played in the words, a 12 head; the player sent there once let go (@kit.Media).
fn desk_play_timeline(c : @ui.Ctx, p : @kit.Media, s : @kit.MediaStatus, on : Bool) -> Unit {
  let t = @sf.theme().p
  let id = c.id(p.key() + "/desk-timeline")
  p.timeline(c, id, on)
  let dur = s.duration
  let part = fn(ms : Double) { if dur <= 0.0 { desk_none } else { dmin(desk_whole, dmax(desk_none, ms / dur)) } }
  let shown = part(p.scrubbing().unwrap_or(s.position))
  let came = part(s.buffered)
  if on {
    c.cursor(id, Hand)
  }
  c.box(style=desk_timeline_box, id=if on { id } else { 0 }, fn() {
    c.box(style=desk_track.then(@ui.style(bg=Data(@sf.alpha(t.text, desk_track_share)))), fn() {
      c.layer(fn() { desk_share_bar(c, came, @sf.alpha(t.text, desk_came_share)) }) |> ignore
      c.layer(fn() { desk_share_bar(c, shown, t.text) }) |> ignore
    })
    |> ignore
    // the head where it is
    c.layer(fn() {
      c.box(style=desk_head_row, fn() {
        c.box(style=@ui.style(w=Grow(shown)), fn() {  }) |> ignore
        c.box(style=desk_head_room, fn() {
          c.box(style=desk_head.then(@ui.style(bg=Data(t.text))), tx=-desk_head_r, fn() {  }) |> ignore
        })
        |> ignore
        c.box(style=@ui.style(w=Grow(desk_whole - shown)), fn() {  }) |> ignore
      })
      |> ignore
    })
    |> ignore
    // with a mouse over it (or dragging), the time where it points, over it (Player.tsx Timeline `pointed`)
    match c.rect_of(id) {
      Some((x, _, w, _)) if on && dur > 0.0 && (c.hovered(id) || c.pressed(id)) => {
        let (px, _, _) = c.pointer()
        let at = dmin(desk_whole, dmax(desk_none, (px - x) / dmax(desk_whole, w)))
        c.layer(fn() {
          c.box(style=desk_pointed, tx=px - x - desk_pointed_w / 2.0, ty=-desk_pointed_up, fn() {
            c.rich([@ui.span(@player.clock(at * dur), mono=true)], style=desk_pointed_words) |> ignore
          })
          |> ignore
        })
        |> ignore
      }
      _ => ()
    }
  })
  |> ignore
}

///|
/// `part` of a track from its start, in `color`.
fn desk_share_bar(c : @ui.Ctx, part : Double, color : Int64) -> Unit {
  c.box(style=desk_head_row, fn() {
    c.box(style=@ui.style(w=Grow(part), h=Full, bg=Data(color)), fn() {  }) |> ignore
    c.box(style=@ui.style(w=Grow(desk_whole - part), h=Full), fn() {  }) |> ignore
  })
  |> ignore
}

///|
/// 选集 (Player.tsx list): the folder's others docked at the right under the bar, on the canvas with a line before them:
/// 选集 and which of how many, its close; each numbered, the one playing on the page's chosen ground with ▶ (✓ paused).
fn desk_play_list(c : @ui.Ctx, p : @kit.Media, d : DeskPlaying, index : Int, playing : Bool) -> Unit {
  let t = @sf.theme().p
  let key = p.key()
  c.box(style=desk_panel_place, fn() {
    c.box(style=desk_panel_top, fn() {  }) |> ignore
    c.box(style=desk_panel_row, fn() {
      c.box(style=desk_panel_room, fn() {  }) |> ignore
      c.box(style=desk_panel_rule.then(@ui.style(bg=Data(t.line))), fn() {  }) |> ignore
      c.box(style=desk_panel_box.then(@ui.style(bg=Data(t.canvas))), id=c.id(key + "/list-panel"), fn() {
        c.box(style=desk_list_head, fn() {
          c.text(tr("web-pages.drive.player.list"), style=desk_panel_title) |> ignore
          c.box(style=desk_grow, fn() {
            c.text("\{index + 1} / \{d.list.length()}", style=desk_panel_note.then(@ui.text_style(color=Muted))) |> ignore
          })
          |> ignore
          if viewer_tool(c, key + "/list-close", "close", tr("common.close"), page_viewer_ink()) {
            desk_listing[key] = false
          }
        })
        |> ignore
        c.box(style=desk_panel_list, fn() {
          c.list(key + "/list", d.list.length(), desk_row_h, fn(i) {
            let id = c.id(key + "/list/\{i}")
            let now = i == index
            c.cursor(id, Hand)
            if c.clicked(id) && !now {
              p.pause()
              (d.open)(d.list[i])
            }
            c.box(style=desk_list_row, selected=now, id~, fn() {
              c.box(style=desk_chapter_number, fn() {
                c.text("\{i + 1}", style=desk_chapter_n_words.then(@ui.text_style(color=Muted))) |> ignore
              })
              |> ignore
              c.box(style=desk_grow_clip, fn() {
                c.text(d.list[i], style=if now { desk_list_now } else { desk_list_words }) |> ignore
              })
              |> ignore
              if now {
                @sf.icon(c, if playing { "play" } else { "check" }, size=desk_check_icon, color=t.text) |> ignore
              }
            })
            |> ignore
          })
          |> ignore
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
/// A song's mark (72) in the middle; the time's words (12, the code face); the cue's words (16 on 1.6) on black at
/// 60%; above the controls while they show (112 off the foot), else 28.
let desk_cover_icon : Double = 72.0

///|
let desk_half : Double = 0.5

///|
/// The head on the timeline: 12 across, centred on where it is.
let desk_head_r : Double = 6.0

///|
let desk_came_share : Double = 0.22

///|
/// The time where the pointer is (Player.css.ts pointed): over the timeline, 4 above it, on black at 75%, 11 in white.
let desk_pointed_w : Double = 56.0

///|
let desk_pointed_up : Double = 24.0

///|
// kept across runs: a value (no field of it changes)
let desk_pointed : @ui.Style = @ui.style(w=Fixed(desk_pointed_w), h=S5, radius=Md, bg=VeilDeep, align=ACenter, justify=JCenter)

///|
// kept across runs: a value (no field of it changes)
let desk_pointed_words : @ui.TextStyle = @ui.text_style(size=Xs2, color=OnVeil, wrap=false)

///|
/// The sound's line: in twentieths; its head 10 across.
let desk_volume_steps : Double = 20.0

///|
let desk_volume_head_r : Double = 5.0

///|
// kept across runs: a value (no field of it changes)
let desk_volume_row : @ui.Style = @ui.style(row=true, pr=S1_5, gap=S0_5, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let desk_volume_line : @ui.Style = @ui.style(w=Fixed(desk_volume_w), h=Fixed(desk_timeline_h), justify=JCenter)

///|
let desk_volume_w : Double = 72.0

///|
// kept across runs: a value (no field of it changes)
let desk_volume_head_room : @ui.Style = @ui.style(w=S0, h=S2_5)

///|
// kept across runs: a value (no field of it changes)
let desk_volume_head : @ui.Style = @ui.style(w=S2_5, h=S2_5, radius=Full, shadow=Sm)

///|
// kept across runs: a value (no field of it changes)
let desk_play_ground : @ui.Style = @ui.style(w=Full, h=Full, bg=Bg)

///|
// kept across runs: a value (no field of it changes)
let desk_play_row : @ui.Style = @ui.style(row=true, w=Full, h=Full)

///|
// kept across runs: a value (no field of it changes)
let desk_grow_full : @ui.Style = @ui.style(w=@sf.grow, h=Full)

///|
// kept across runs: a value (no field of it changes)
let desk_play_cover : @ui.Style = @ui.style(w=Full, h=Full, px=S8, gap=S4, align=ACenter, justify=JCenter)

///|
// kept across runs: a value (no field of it changes)
let desk_cover_name : @ui.TextStyle = @ui.text_style(size=Xl, weight=Semibold, color=Fg, center=true)

///|
// kept across runs: a value (no field of it changes)
let desk_play_middle : @ui.Style = @ui.style(w=Full, h=Full, align=ACenter, justify=JCenter)

///|
// kept across runs: a value (no field of it changes)
let desk_cue_up : @ui.Style = @ui.style(w=Full, h=Full, pb=S28, justify=JEnd)

///|
// kept across runs: a value (no field of it changes)
let desk_cue_down : @ui.Style = @ui.style(w=Full, h=Full, pb=S7, justify=JEnd)

///|
// kept across runs: a value (no field of it changes)
let desk_cue_row : @ui.Style = @ui.style(row=true, w=Full, px=S4)

///|
// kept across runs: a value (no field of it changes)
let desk_cue_box : @ui.Style = @ui.style(px=S2, py=S0_5, radius=Md, bg=Veil)

///|
// kept across runs: a value (no field of it changes)
let desk_cue_words : @ui.TextStyle = @ui.text_style(size=Xl, color=OnVeil, center=true, leading=L7)

///|
/// The controls: 16 off the window's foot, in the middle of what the list leaves; 2 over, 6 round, 16 their corner.
// kept across runs: a value (no field of it changes)
let desk_controls_place : @ui.Style = @ui.style(w=Full, h=Full, pb=S4, justify=JEnd)

///|
// kept across runs: a value (no field of it changes)
let desk_play_row_end : @ui.Style = @ui.style(row=true, w=Full)

///|
// kept across runs: a value (no field of it changes)
let desk_controls_box : @ui.Style = @ui.style(pl=S1_5, pr=S1_5, pt=S0_5, pb=S1_5, radius=Xl1_5)

///|
// kept across runs: a value (no field of it changes)
let desk_controls_row : @ui.Style = @ui.style(row=true, w=Full, gap=S3, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let desk_controls_group : @ui.Style = @ui.style(row=true, gap=S0_5, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let desk_time_words : @ui.TextStyle = @ui.text_style(size=Xs, wrap=false)

///|
/// The speed (vvRate): 28 high, 46 wide at least, 8 in, its corner 10, the words at 10% under it.
// kept across runs: a value (no field of it changes)
let desk_rate_box : @ui.Style = @ui.style(h=S7, min_w=Fixed(desk_rate_w), px=S2, radius=Lg, align=ACenter, justify=JCenter)

///|
let desk_rate_w : Double = 46.0

///|
// kept across runs: a value (no field of it changes)
let desk_rate_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let desk_play_key_box : @ui.Style = @ui.style(
  w=S8,
  h=S8,
  radius=Lg,
  align=ACenter,
  justify=JCenter,
  hovered=@ui.patch(bg=Hover),
  selected=@ui.patch(bg=Selected),
  disabled=@ui.patch(opacity=O35),
)

///|
/// The timeline (vvTimeline): 22 high, 10 in from the bar's sides; its track 4, round.
// kept across runs: a value (no field of it changes)
let desk_timeline_box : @ui.Style = @ui.style(w=Full, h=Fixed(desk_timeline_h), px=S2_5, justify=JCenter)

///|
let desk_timeline_h : Double = 22.0

///|
// kept across runs: a value (no field of it changes)
let desk_track : @ui.Style = @ui.style(w=Full, h=S1, radius=Full, clip=true)

///|
// kept across runs: a value (no field of it changes)
let desk_head_row : @ui.Style = @ui.style(row=true, w=Full, h=Full, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let desk_head_room : @ui.Style = @ui.style(w=S0, h=S3)

///|
// kept across runs: a value (no field of it changes)
let desk_head : @ui.Style = @ui.style(w=S3, h=S3, radius=Full, shadow=Sm)

///|
/// 选集's head (listHead: 12 over, 10 right, 6 under, 18 at its start) and rows (listRow: 40 at least, 8 and 10 in, the
/// page's corner; the one playing on the chosen ground, in 500).
// kept across runs: a value (no field of it changes)
let desk_list_head : @ui.Style = @ui.style(row=true, w=Full, pl=S4_5, pr=S2_5, pt=S3, pb=S1_5, gap=S2, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let desk_list_row : @ui.Style = @ui.style(
  row=true,
  w=Full,
  min_h=S10,
  px=S2_5,
  py=S2,
  gap=S1,
  align=ACenter,
  radius=Xl,
  hovered=@ui.patch(bg=Hover),
  selected=@ui.patch(bg=Selected),
)

///|
// kept across runs: a value (no field of it changes)
let desk_list_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let desk_list_now : @ui.TextStyle = @ui.text_style(size=Sm, weight=Medium, color=Fg, wrap=false)
